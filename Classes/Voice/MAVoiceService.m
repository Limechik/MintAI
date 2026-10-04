#import "MAVoiceService.h"
#import "MALocalization.h"
#import "MAHTTPClient.h"
#import "MAProviderRegistry.h"
#import "MAProvider.h"
#import "MAKeychain.h"
#import "MAVoxCore.h"
#import "MAOnDeviceRecognizer.h"
#import <AVFoundation/AVFoundation.h>

NSString *const MAVoiceStateDidChangeNotification = @"MAVoiceStateDidChangeNotification";

static NSString *const kAutoSpeakDefaultsKey = @"MAVoiceAutoSpeak";
static NSString *const kVoiceStyleDefaultsKey = @"MAVoiceStyle";
static NSString *const kSpeechRateDefaultsKey = @"MASpeechRate";
static NSString *const kSTTModeDefaultsKey = @"MASTTMode";
static const NSUInteger kMaxSpeechLength = 6000;

#pragma mark - Подготовка текста для озвучки

// Markdown в ответах ИИ (звёздочки, решётки, ``` и т.п.) на слух —
// «звёздочка звёздочка». Вычищаем всё, что не является речью.
static NSString *MACleanTextForSpeech(NSString *text) {
	if (text.length == 0) return @"";

	NSMutableString *result = [text mutableCopy];

	void (^replace)(NSString *, NSString *, NSRegularExpressionOptions) =
		^(NSString *pattern, NSString *withTemplate_, NSRegularExpressionOptions options) {
		NSRegularExpression *regex = [NSRegularExpression regularExpressionWithPattern:pattern options:options error:nil];
		[regex replaceMatchesInString:result options:0 range:NSMakeRange(0, result.length) withTemplate:withTemplate_];
	};

	replace(@"```[\\s\\S]*?```", @" ", 0);                       // блоки кода не читаем
	replace(@"\\[([^\\]]*)\\]\\([^)]*\\)", @"$1", 0);            // [текст](url) -> текст
	replace(@"https?://\\S+", @" ", 0);                          // голые ссылки
	replace(@"^\\s*[-+•]\\s+", @"", NSRegularExpressionAnchorsMatchLines); // маркеры списков
	replace(@"[*_#>`~|]+", @"", 0);                              // остатки разметки
	replace(@"[ \\t]{2,}", @" ", 0);

	NSString *trimmed = [result stringByTrimmingCharactersInSet:[NSCharacterSet whitespaceAndNewlineCharacterSet]];
	if (trimmed.length > kMaxSpeechLength) {
		trimmed = [trimmed substringToIndex:kMaxSpeechLength];
	}
	return trimmed;
}

static NSError *MAVoiceError(NSString *message) {
	return [NSError errorWithDomain:@"MAVoiceErrorDomain"
	                           code:1
	                       userInfo:@{NSLocalizedDescriptionKey: message}];
}

#pragma mark -

@interface MAVoiceService () <AVAudioPlayerDelegate>
@property (nonatomic, strong, readwrite) MAVoiceProvider *sttProvider;
@property (nonatomic, assign, readwrite, getter=isRecording) BOOL recording;
@property (nonatomic, assign, readwrite, getter=isSpeaking) BOOL speaking;
@property (nonatomic, strong) AVAudioRecorder *recorder;
@property (nonatomic, copy) NSString *recordingPath;
@property (nonatomic, assign) BOOL recordingIsLocal; // в каком режиме идёт текущая запись

// Озвучка (см. «Озвучка (встроенный синтезатор VoxSynth)»).
@property (nonatomic, strong) dispatch_queue_t synthQueue;      // serial: куски синтезируются строго по порядку
@property (nonatomic, assign) NSUInteger speechGeneration;      // отбрасывает результаты устаревшей озвучки
@property (nonatomic, strong) NSMutableData *currentCancelFlag; // int-флаг отмены, его читает C-код синтеза
@property (nonatomic, strong) NSMutableArray *playQueue;        // готовые WAV, ждущие своей очереди
@property (nonatomic, assign) BOOL synthesisFinished;
@property (nonatomic, strong) AVAudioPlayer *player;
@end

@implementation MAVoiceService

+ (instancetype)sharedService {
	static MAVoiceService *shared = nil;
	static dispatch_once_t onceToken;
	dispatch_once(&onceToken, ^{
		shared = [[MAVoiceService alloc] init];
	});
	return shared;
}

- (instancetype)init {
	self = [super init];
	if (self) {
		_sttProvider = [[MAVoiceProvider alloc] initWithIdentifier:@"openai-stt"
		                                                displayName:@"Распознавание речи (STT)"
		                                              baseURLString:@"https://api.openai.com/v1"
		                                                      model:@"whisper-1"];
		[self loadPersistedSettingsIntoProvider:_sttProvider];
		_synthQueue = dispatch_queue_create("com.mintai.speech", DISPATCH_QUEUE_SERIAL);
		_playQueue = [NSMutableArray array];
	}
	return self;
}

#pragma mark - Настройки

// По умолчанию озвучиваем все ответы — ради этого голосовой режим и нужен.
- (BOOL)autoSpeak {
	NSNumber *saved = [[NSUserDefaults standardUserDefaults] objectForKey:kAutoSpeakDefaultsKey];
	return saved ? saved.boolValue : YES;
}

- (void)setAutoSpeak:(BOOL)autoSpeak {
	[[NSUserDefaults standardUserDefaults] setBool:autoSpeak forKey:kAutoSpeakDefaultsKey];
	[[NSUserDefaults standardUserDefaults] synchronize];
}

- (MAVoiceSTTMode)sttMode {
	NSInteger saved = [[NSUserDefaults standardUserDefaults] integerForKey:kSTTModeDefaultsKey];
	return saved == MAVoiceSTTModeOnDevice ? MAVoiceSTTModeOnDevice : MAVoiceSTTModeServer;
}

- (void)setSttMode:(MAVoiceSTTMode)sttMode {
	[[NSUserDefaults standardUserDefaults] setInteger:sttMode forKey:kSTTModeDefaultsKey];
	[[NSUserDefaults standardUserDefaults] synchronize];
}

- (NSString *)apiKeyKeychainKeyForProvider:(MAVoiceProvider *)provider {
	return [NSString stringWithFormat:@"apiKey.voice.%@", provider.identifier];
}

- (NSString *)baseURLDefaultsKeyForProvider:(MAVoiceProvider *)provider {
	return [NSString stringWithFormat:@"MAVoiceBaseURL.%@", provider.identifier];
}

- (NSString *)modelDefaultsKeyForProvider:(MAVoiceProvider *)provider {
	return [NSString stringWithFormat:@"MAVoiceModel.%@", provider.identifier];
}

- (void)loadPersistedSettingsIntoProvider:(MAVoiceProvider *)provider {
	NSString *savedKey = [MAKeychain stringForKey:[self apiKeyKeychainKeyForProvider:provider]];
	if (savedKey.length > 0) provider.apiKey = savedKey;

	NSUserDefaults *defaults = [NSUserDefaults standardUserDefaults];
	NSString *savedBaseURL = [defaults stringForKey:[self baseURLDefaultsKeyForProvider:provider]];
	if (savedBaseURL.length > 0) provider.baseURLString = savedBaseURL;
	NSString *savedModel = [defaults stringForKey:[self modelDefaultsKeyForProvider:provider]];
	if (savedModel.length > 0) provider.model = savedModel;
}

- (void)persistSettingsForProvider:(MAVoiceProvider *)provider {
	[MAKeychain setString:provider.apiKey forKey:[self apiKeyKeychainKeyForProvider:provider]];

	NSUserDefaults *defaults = [NSUserDefaults standardUserDefaults];
	[defaults setObject:(provider.baseURLString ?: @"") forKey:[self baseURLDefaultsKeyForProvider:provider]];
	[defaults setObject:(provider.model ?: @"") forKey:[self modelDefaultsKeyForProvider:provider]];
	[defaults synchronize];
}

#pragma mark - Учётные данные

// Если у голосового провайдера ключ не задан, а он смотрит на api.openai.com —
// берём ключ из чат-провайдера OpenAI, чтобы не вводить его дважды.
- (NSString *)effectiveAPIKeyForProvider:(MAVoiceProvider *)provider {
	if (provider.apiKey.length > 0) return provider.apiKey;

	if ([provider.baseURLString rangeOfString:@"api.openai.com"].location != NSNotFound) {
		id<MAProvider> openAI = [[MAProviderRegistry sharedRegistry] providerWithIdentifier:@"openai"];
		if (openAI.apiKey.length > 0) return openAI.apiKey;
	}
	return nil;
}

- (BOOL)isProviderUsable:(MAVoiceProvider *)provider {
	if (provider.baseURLString.length == 0) return NO;
	if (provider.requiresAPIKey && [self effectiveAPIKeyForProvider:provider].length == 0) return NO;
	return YES;
}

- (NSURL *)endpointURLForProvider:(MAVoiceProvider *)provider path:(NSString *)path {
	NSString *base = provider.baseURLString ?: @"";
	if ([base hasSuffix:@"/"]) base = [base substringToIndex:base.length - 1];
	if ([base hasSuffix:path]) return [NSURL URLWithString:base];
	return [NSURL URLWithString:[base stringByAppendingString:path]];
}

- (NSString *)errorMessageFromData:(NSData *)data statusCode:(NSInteger)statusCode {
	id json = data.length ? [NSJSONSerialization JSONObjectWithData:data options:0 error:nil] : nil;
	if ([json isKindOfClass:[NSDictionary class]]) {
		id errorObj = json[@"error"];
		if ([errorObj isKindOfClass:[NSDictionary class]] && [errorObj[@"message"] isKindOfClass:[NSString class]]) {
			return errorObj[@"message"];
		}
		if ([errorObj isKindOfClass:[NSString class]]) return errorObj;
	}
	return [NSHTTPURLResponse localizedStringForStatusCode:statusCode];
}

#pragma mark - Аудиосессия

// PlayAndRecord + принудительный динамик: иначе после записи звук идёт в
// разговорный динамик (у уха) и слышен очень тихо. Работает и для записи, и
// для озвучки.
- (void)activateAudioSession {
	AVAudioSession *session = [AVAudioSession sharedInstance];
	[session setCategory:AVAudioSessionCategoryPlayAndRecord error:nil];
	[session overrideOutputAudioPort:AVAudioSessionPortOverrideSpeaker error:nil];
	[session setActive:YES error:nil];
}

- (void)postStateChange {
	[[NSNotificationCenter defaultCenter] postNotificationName:MAVoiceStateDidChangeNotification object:self];
}

- (void)reportError:(NSString *)message {
	NSLog(@"[MintAI voice] %@", message);
	if (self.errorHandler) self.errorHandler(message);
}

#pragma mark - Озвучка (встроенный синтезатор VoxSynth)

// Озвучку делает само приложение: собственный формантный синтезатор VoxSynth
// (Classes/Voice/Vox, обёртка — MAVoxCore) превращает текст в PCM прямо в памяти,
// дальше звук играет AVAudioPlayer. Ни сервера, ни ключей, ни интернета, ни файлов
// с данными голоса — и без приватных API iOS.
// Говорит только по-русски: цифры раскладываются в слова, латиница читается
// транслитом (см. MAVoxCore.h).

// Нарезка по предложениям: первая фраза синтезируется и начинает играть,
// пока остальные ещё готовятся, — задержка перед речью небольшая даже на
// старом железе.
static NSArray *MASplitIntoSpeechChunks(NSString *text) {
	static const NSUInteger kChunkLimit = 250;
	NSMutableArray *chunks = [NSMutableArray array];
	NSMutableString *current = [NSMutableString string];

	[text enumerateSubstringsInRange:NSMakeRange(0, text.length)
	                         options:NSStringEnumerationBySentences
	                      usingBlock:^(NSString *sentence, NSRange r, NSRange er, BOOL *stop) {
		NSString *piece = [sentence stringByTrimmingCharactersInSet:[NSCharacterSet whitespaceAndNewlineCharacterSet]];
		if (piece.length == 0) return;
		if (current.length > 0 && current.length + piece.length + 1 > kChunkLimit) {
			[chunks addObject:[current copy]];
			[current setString:@""];
		}
		if (current.length > 0) [current appendString:@" "];
		[current appendString:piece];
	}];
	if (current.length > 0) [chunks addObject:[current copy]];
	if (chunks.count == 0) [chunks addObject:text];
	return chunks;
}

// 16-bit mono PCM -> WAV в памяти (AVAudioPlayer умеет играть его из NSData).
static NSData *MAWavDataFromSamples(const short *samples, size_t count, int sampleRate) {
	uint32_t dataLength = (uint32_t)(count * sizeof(short));
	uint32_t riffLength = 36 + dataLength;
	uint32_t fmtLength = 16;
	uint16_t pcmFormat = 1, channels = 1, bitsPerSample = 16, blockAlign = 2;
	uint32_t rate = (uint32_t)sampleRate, byteRate = (uint32_t)sampleRate * 2;

	NSMutableData *wav = [NSMutableData dataWithCapacity:44 + dataLength];
	[wav appendBytes:"RIFF" length:4];
	[wav appendBytes:&riffLength length:4];
	[wav appendBytes:"WAVEfmt " length:8];
	[wav appendBytes:&fmtLength length:4];
	[wav appendBytes:&pcmFormat length:2];
	[wav appendBytes:&channels length:2];
	[wav appendBytes:&rate length:4];
	[wav appendBytes:&byteRate length:4];
	[wav appendBytes:&blockAlign length:2];
	[wav appendBytes:&bitsPerSample length:2];
	[wav appendBytes:"data" length:4];
	[wav appendBytes:&dataLength length:4];
	[wav appendBytes:samples length:dataLength];
	return wav; // armv7 — little-endian, как и требует формат WAV
}

- (NSInteger)voiceStyle {
	NSNumber *saved = [[NSUserDefaults standardUserDefaults] objectForKey:kVoiceStyleDefaultsKey];
	return saved ? saved.integerValue : 0;
}

- (void)setVoiceStyle:(NSInteger)voiceStyle {
	[[NSUserDefaults standardUserDefaults] setInteger:voiceStyle forKey:kVoiceStyleDefaultsKey];
	[[NSUserDefaults standardUserDefaults] synchronize];
}

- (NSInteger)speechRate {
	NSNumber *saved = [[NSUserDefaults standardUserDefaults] objectForKey:kSpeechRateDefaultsKey];
	return saved ? saved.integerValue : 170;
}

- (void)setSpeechRate:(NSInteger)speechRate {
	[[NSUserDefaults standardUserDefaults] setInteger:speechRate forKey:kSpeechRateDefaultsKey];
	[[NSUserDefaults standardUserDefaults] synchronize];
}

// Тембр VoxSynth: 0 — стандартный, 1 — мужской, 2 — женский. Это высота тона и масштаб
// формант (длина «голосового тракта»); громкость между стилями выравнивает MAVoxCore.
- (void)getPitchScale:(float *)pitch formantScale:(float *)formant {
	switch (self.voiceStyle) {
		case 1:  *pitch = 0.8f; *formant = 0.9f;  break;
		case 2:  *pitch = 1.6f; *formant = 1.17f; break;
		default: *pitch = 1.0f; *formant = 1.0f;  break;
	}
}

- (void)speakText:(NSString *)text {
	NSString *clean = MACleanTextForSpeech(text);
	if (clean.length == 0) return;

	[self stopSpeaking];

	[self activateAudioSession];

	NSUInteger generation = self.speechGeneration;
	NSMutableData *cancelFlag = [NSMutableData dataWithLength:sizeof(int)];
	self.currentCancelFlag = cancelFlag;
	self.playQueue = [NSMutableArray array];
	self.synthesisFinished = NO;
	self.speaking = YES;
	[self postStateChange];

	NSArray *chunks = MASplitIntoSpeechChunks(clean);

	// «Обычно» (170) — родной темп VoxSynth, speed = 1.0; «Медленно»/«Быстро» масштабируют его.
	NSInteger rate = self.speechRate;
	float speed = rate > 0 ? (float)rate / 170.0f : 1.0f;
	float pitchScale = 1.0f, formantScale = 1.0f;
	[self getPitchScale:&pitchScale formantScale:&formantScale];
	const int sampleRate = MAVoxSampleRate();

	// Куски синтезируются на отдельной serial-очереди, строго по порядку: первый уже
	// играет, пока остальные готовятся, а новая озвучка стартует после отмены старой.
	__weak typeof(self) weakSelf = self;
	dispatch_async(self.synthQueue, ^{
		volatile int *cancelPointer = (volatile int *)cancelFlag.mutableBytes;
		NSString *failureMessage = nil;

		for (NSString *chunk in chunks) {
			if (*cancelPointer) break;

			short *samples = NULL;
			size_t sampleCount = 0;
			int code = MAVoxSynthesize([chunk UTF8String], speed, pitchScale, formantScale,
			                           cancelPointer, &samples, &sampleCount);
			if (code == -4) break; // отменено пользователем
			if (code != 0) {
				failureMessage = [NSString stringWithFormat:MALocalizedString(@"Синтез речи не удался (код %d)"), code];
				break;
			}
			if (sampleCount == 0) continue; // в куске нечего произносить (одни символы/эмодзи) — не ошибка

			NSData *wav = MAWavDataFromSamples(samples, sampleCount, sampleRate);
			MAVoxFreeSamples(samples);

			dispatch_async(dispatch_get_main_queue(), ^{
				__strong typeof(weakSelf) strongSelf = weakSelf;
				if (!strongSelf || generation != strongSelf.speechGeneration) return;
				[strongSelf.playQueue addObject:wav];
				[strongSelf playNextIfIdle];
			});
		}

		dispatch_async(dispatch_get_main_queue(), ^{
			__strong typeof(weakSelf) strongSelf = weakSelf;
			if (!strongSelf || generation != strongSelf.speechGeneration) return;
			strongSelf.synthesisFinished = YES;
			if (failureMessage) [strongSelf reportError:failureMessage];
			[strongSelf finishIfDone];
		});
	});
}

// Играет следующий готовый кусок, если сейчас ничего не звучит.
- (void)playNextIfIdle {
	if (self.player.playing) return;
	if (self.playQueue.count == 0) {
		[self finishIfDone];
		return;
	}

	NSData *wav = self.playQueue[0];
	[self.playQueue removeObjectAtIndex:0];

	NSError *error = nil;
	AVAudioPlayer *player = [[AVAudioPlayer alloc] initWithData:wav error:&error];
	if (!player) {
		[self reportError:[NSString stringWithFormat:MALocalizedString(@"Не удалось воспроизвести звук: %@"), error.localizedDescription ?: MALocalizedString(@"неизвестная ошибка")]];
		[self stopSpeaking];
		return;
	}
	player.delegate = self;
	self.player = player;
	[player prepareToPlay];
	[player play];
}

- (void)finishIfDone {
	if (self.synthesisFinished && self.playQueue.count == 0 && !self.player.playing) {
		self.player = nil;
		if (self.speaking) {
			self.speaking = NO;
			[self postStateChange];
		}
	}
}

- (void)audioPlayerDidFinishPlaying:(AVAudioPlayer *)player successfully:(BOOL)flag {
	if (player != self.player) return;
	self.player = nil;
	[self playNextIfIdle];
}

- (void)audioPlayerDecodeErrorDidOccur:(AVAudioPlayer *)player error:(NSError *)error {
	if (player != self.player) return;
	self.player = nil;
	[self playNextIfIdle];
}

- (void)stopSpeaking {
	self.speechGeneration++; // отбрасывает всё, что синтез ещё пришлёт на main

	if (self.currentCancelFlag) {
		*(volatile int *)self.currentCancelFlag.mutableBytes = 1; // прерывает идущий синтез
		self.currentCancelFlag = nil;
	}
	[self.playQueue removeAllObjects];
	self.synthesisFinished = YES;

	if (self.player) {
		self.player.delegate = nil;
		[self.player stop];
		self.player = nil;
	}

	if (self.speaking) {
		self.speaking = NO;
		[self postStateChange];
	}
}

#pragma mark - Запись и распознавание

- (void)startRecordingWithCompletion:(void (^)(NSError *))completion {
	if (self.recording) {
		if (completion) completion(nil);
		return;
	}
	[self stopSpeaking];

	BOOL local = (self.sttMode == MAVoiceSTTModeOnDevice);
	if (local) {
		if (![[MAOnDeviceRecognizer sharedRecognizer] isModelInstalled]) {
			if (completion) completion(MAVoiceError(MALocalizedString(@"Модель распознавания не установлена — см. Settings → Голос")));
			return;
		}
	} else if (![self isProviderUsable:self.sttProvider]) {
		if (completion) completion(MAVoiceError(MALocalizedString(@"Задай ключ распознавания речи в Settings → Голос")));
		return;
	}

	[self activateAudioSession];

	// Локальному движку нужен несжатый PCM 16 кГц; серверу хватает компактного AAC.
	NSString *path = [NSTemporaryDirectory() stringByAppendingPathComponent:(local ? @"mintai-voice.wav" : @"mintai-voice.m4a")];
	[[NSFileManager defaultManager] removeItemAtPath:path error:nil];

	NSDictionary *settings = local ? @{
		AVFormatIDKey: @(kAudioFormatLinearPCM),
		AVSampleRateKey: @16000.0f,
		AVNumberOfChannelsKey: @1,
		AVLinearPCMBitDepthKey: @16,
		AVLinearPCMIsBigEndianKey: @NO,
		AVLinearPCMIsFloatKey: @NO,
	} : @{
		AVFormatIDKey: @(kAudioFormatMPEG4AAC),
		AVSampleRateKey: @16000.0f,
		AVNumberOfChannelsKey: @1,
		AVEncoderBitRateKey: @32000,
		AVEncoderAudioQualityKey: @(AVAudioQualityMedium),
	};

	NSError *error = nil;
	AVAudioRecorder *recorder = [[AVAudioRecorder alloc] initWithURL:[NSURL fileURLWithPath:path]
	                                                         settings:settings
	                                                            error:&error];
	if (!recorder || ![recorder prepareToRecord] || ![recorder record]) {
		if (completion) completion(error ?: MAVoiceError(MALocalizedString(@"Не удалось начать запись (проверь доступ к микрофону)")));
		return;
	}

	self.recorder = recorder;
	self.recordingPath = path;
	self.recordingIsLocal = local;
	self.recording = YES;
	[self postStateChange];
	if (completion) completion(nil);
}

- (void)cancelRecording {
	if (!self.recording) return;
	[self.recorder stop];
	self.recorder = nil;
	self.recording = NO;
	if (self.recordingPath) [[NSFileManager defaultManager] removeItemAtPath:self.recordingPath error:nil];
	[self postStateChange];
}

- (void)finishRecordingAndTranscribe:(MAVoiceTranscribeCompletion)completion {
	if (!self.recording) {
		if (completion) completion(nil, MAVoiceError(MALocalizedString(@"Запись не идёт")));
		return;
	}

	NSTimeInterval duration = self.recorder.currentTime;
	[self.recorder stop];
	self.recorder = nil;
	self.recording = NO;
	[self postStateChange];

	NSString *path = self.recordingPath;

	if (self.recordingIsLocal) {
		if (duration < 0.6) {
			if (path) [[NSFileManager defaultManager] removeItemAtPath:path error:nil];
			if (completion) completion(nil, MAVoiceError(MALocalizedString(@"Слишком короткая запись — удерживай дольше")));
			return;
		}
		[[MAOnDeviceRecognizer sharedRecognizer] transcribeWAVAtPath:path completion:^(NSString *text, NSError *error) {
			if (path) [[NSFileManager defaultManager] removeItemAtPath:path error:nil];
			if (completion) completion(text, error);
		}];
		return;
	}

	NSData *audio = path ? [NSData dataWithContentsOfFile:path] : nil;
	if (path) [[NSFileManager defaultManager] removeItemAtPath:path error:nil];

	if (duration < 0.6 || audio.length == 0) {
		if (completion) completion(nil, MAVoiceError(MALocalizedString(@"Слишком короткая запись — удерживай дольше")));
		return;
	}

	NSURL *url = [self endpointURLForProvider:self.sttProvider path:@"/audio/transcriptions"];
	if (!url) {
		if (completion) completion(nil, MAVoiceError(MALocalizedString(@"Некорректный URL распознавания речи")));
		return;
	}

	NSString *boundary = [NSString stringWithFormat:@"MintAIBoundary%u", arc4random()];
	NSMutableData *body = [NSMutableData data];

	void (^appendString)(NSString *) = ^(NSString *string) {
		[body appendData:[string dataUsingEncoding:NSUTF8StringEncoding]];
	};
	void (^appendField)(NSString *, NSString *) = ^(NSString *name, NSString *value) {
		appendString([NSString stringWithFormat:@"--%@\r\nContent-Disposition: form-data; name=\"%@\"\r\n\r\n%@\r\n",
		              boundary, name, value]);
	};

	appendField(@"model", self.sttProvider.model.length ? self.sttProvider.model : @"whisper-1");
	appendField(@"response_format", @"json");
	appendString([NSString stringWithFormat:@"--%@\r\nContent-Disposition: form-data; name=\"file\"; filename=\"voice.m4a\"\r\nContent-Type: audio/m4a\r\n\r\n", boundary]);
	[body appendData:audio];
	appendString([NSString stringWithFormat:@"\r\n--%@--\r\n", boundary]);

	NSMutableURLRequest *request = [NSMutableURLRequest requestWithURL:url];
	request.HTTPMethod = @"POST";
	request.HTTPBody = body;
	request.timeoutInterval = 60.0;
	[request setValue:[NSString stringWithFormat:@"multipart/form-data; boundary=%@", boundary] forHTTPHeaderField:@"Content-Type"];
	NSString *key = [self effectiveAPIKeyForProvider:self.sttProvider];
	if (key.length > 0) {
		[request setValue:[NSString stringWithFormat:@"Bearer %@", key] forHTTPHeaderField:@"Authorization"];
	}

	[MAHTTPClient sendAsynchronousRequest:request completion:^(NSURLResponse *response, NSData *data, NSError *error) {
		if (error) {
			if (completion) completion(nil, error);
			return;
		}

		NSInteger status = 200;
		if ([response isKindOfClass:[NSHTTPURLResponse class]]) status = [(NSHTTPURLResponse *)response statusCode];
		if (status < 200 || status >= 300) {
			NSString *message = [self errorMessageFromData:data statusCode:status];
			if (completion) completion(nil, MAVoiceError([NSString stringWithFormat:MALocalizedString(@"Распознавание: %@"), message]));
			return;
		}

		id json = data.length ? [NSJSONSerialization JSONObjectWithData:data options:0 error:nil] : nil;
		NSString *text = ([json isKindOfClass:[NSDictionary class]] && [json[@"text"] isKindOfClass:[NSString class]]) ? json[@"text"] : nil;
		text = [text stringByTrimmingCharactersInSet:[NSCharacterSet whitespaceAndNewlineCharacterSet]];
		if (text.length == 0) {
			if (completion) completion(nil, MAVoiceError(MALocalizedString(@"Речь не распознана — попробуй ещё раз")));
			return;
		}
		if (completion) completion(text, nil);
	}];
}

@end
