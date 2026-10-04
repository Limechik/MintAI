#import "MAOnDeviceRecognizer.h"
#import "MALocalization.h"
#import "MAWav.h"
#import "MASttEngine.h"

static NSError *MAOnDeviceError(NSInteger code, NSString *message) {
	return [NSError errorWithDomain:@"MAVoiceErrorDomain"
	                           code:code
	                       userInfo:@{NSLocalizedDescriptionKey: message}];
}

static NSString *MAMessageForStatus(MASttStatus status) {
	switch (status) {
		case MASTT_ERR_NO_MODEL:
			return MALocalizedString(@"Модель распознавания не установлена");
		case MASTT_ERR_BAD_MODEL:
			return MALocalizedString(@"Файл модели распознавания повреждён");
		case MASTT_ERR_NO_SPEECH:
			return MALocalizedString(@"Речь не распознана — попробуй ещё раз");
		case MASTT_ERR_NOT_IMPLEMENTED:
			return MALocalizedString(@"Движок распознавания на устройстве пока в разработке");
		case MASTT_ERR_MEMORY:
			return MALocalizedString(@"Не хватило памяти для распознавания");
		case MASTT_ERR_CANCELLED:
			return MALocalizedString(@"Распознавание отменено");
		case MASTT_ERR_BAD_INPUT:
		default:
			return MALocalizedString(@"Не удалось прочитать запись");
	}
}

@interface MAOnDeviceRecognizer ()
@property (nonatomic, strong) dispatch_queue_t queue;   // serial: движок не потокобезопасен
@property (nonatomic, assign) MASttEngine *engine;      // трогаем только на queue
@end

@implementation MAOnDeviceRecognizer

+ (instancetype)sharedRecognizer {
	static MAOnDeviceRecognizer *shared = nil;
	static dispatch_once_t onceToken;
	dispatch_once(&onceToken, ^{ shared = [[MAOnDeviceRecognizer alloc] init]; });
	return shared;
}

- (instancetype)init {
	self = [super init];
	if (self) {
		_queue = dispatch_queue_create("com.mintai.stt", DISPATCH_QUEUE_SERIAL);
		NSArray *dirs = NSSearchPathForDirectoriesInDomains(NSDocumentDirectory, NSUserDomainMask, YES);
		NSString *docs = dirs.count > 0 ? [dirs objectAtIndex:0] : NSTemporaryDirectory();
		_modelPath = [[docs stringByAppendingPathComponent:@"stt"] stringByAppendingPathComponent:@"model.bin"];
	}
	return self;
}

- (BOOL)isModelInstalled {
	NSDictionary *attrs = [[NSFileManager defaultManager] attributesOfItemAtPath:self.modelPath error:nil];
	return attrs != nil && [attrs fileSize] > 0;
}

- (void)reloadModel {
	dispatch_async(self.queue, ^{
		if (self.engine) {
			MASttEngineFree(self.engine);
			self.engine = NULL;
		}
	});
}

- (void)finishWithText:(NSString *)text error:(NSError *)error completion:(MAOnDeviceCompletion)completion {
	if (!completion) return;
	dispatch_async(dispatch_get_main_queue(), ^{ completion(text, error); });
}

- (void)transcribeWAVAtPath:(NSString *)path completion:(MAOnDeviceCompletion)completion {
	NSString *modelPath = self.modelPath;
	dispatch_async(self.queue, ^{
		@autoreleasepool {
			NSData *file = path ? [NSData dataWithContentsOfFile:path options:NSDataReadingMappedIfSafe error:nil] : nil;
			MAWavInfo info;
			if (!file || MAWavParse(file.bytes, file.length, &info) != MAWAV_OK) {
				[self finishWithText:nil error:MAOnDeviceError(MASTT_ERR_BAD_INPUT, MAMessageForStatus(MASTT_ERR_BAD_INPUT)) completion:completion];
				return;
			}
			if (info.sample_rate != MASttEngineSampleRate()) {
				[self finishWithText:nil error:MAOnDeviceError(MASTT_ERR_BAD_INPUT, MAMessageForStatus(MASTT_ERR_BAD_INPUT)) completion:completion];
				return;
			}

			if (!self.engine) {
				MASttStatus loadStatus = MASTT_OK;
				self.engine = MASttEngineLoad(modelPath.fileSystemRepresentation, &loadStatus);
				if (!self.engine) {
					[self finishWithText:nil error:MAOnDeviceError(loadStatus, MAMessageForStatus(loadStatus)) completion:completion];
					return;
				}
			}

			// Не декодируем больше, чем движок готов принять: лишний хвост просто отбрасываем.
			size_t capacity = (size_t)MASttEngineMaxSeconds() * (size_t)MASttEngineSampleRate();
			size_t frames = MAWavFrameCount(&info);
			if (frames > capacity) frames = capacity;
			float *samples = (float *)malloc(sizeof(float) * (frames > 0 ? frames : 1));
			if (!samples) {
				[self finishWithText:nil error:MAOnDeviceError(MASTT_ERR_MEMORY, MAMessageForStatus(MASTT_ERR_MEMORY)) completion:completion];
				return;
			}
			size_t count = MAWavDecodeMono(file.bytes, file.length, &info, samples, frames);

			char text[4096];
			MASttStatus status = MASttEngineTranscribe(self.engine, samples, count, info.sample_rate, NULL, text, sizeof(text));
			free(samples);

			if (status != MASTT_OK) {
				[self finishWithText:nil error:MAOnDeviceError(status, MAMessageForStatus(status)) completion:completion];
				return;
			}
			NSString *result = [[NSString stringWithUTF8String:text]
			                    stringByTrimmingCharactersInSet:[NSCharacterSet whitespaceAndNewlineCharacterSet]];
			if (result.length == 0) {
				[self finishWithText:nil error:MAOnDeviceError(MASTT_ERR_NO_SPEECH, MAMessageForStatus(MASTT_ERR_NO_SPEECH)) completion:completion];
				return;
			}
			[self finishWithText:result error:nil completion:completion];
		}
	});
}

@end
