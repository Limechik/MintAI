#import <Foundation/Foundation.h>
#import "MAVoiceProvider.h"

extern NSString *const MAVoiceStateDidChangeNotification;

typedef void (^MAVoiceTranscribeCompletion)(NSString *text, NSError *error);

// Где распознаётся запись с микрофона.
typedef NS_ENUM(NSInteger, MAVoiceSTTMode) {
	MAVoiceSTTModeServer = 0,    // отправка на {base}/audio/transcriptions (Whisper)
	MAVoiceSTTModeOnDevice = 1,  // локальный движок (Classes/Voice/Stt), без сети
};

// Голосовой режим: «поговорить с ИИ» и озвучка ответов.
//
// В iOS 6.1 нет публичных API ни для синтеза (AVSpeechSynthesizer — iOS 7+),
// ни для распознавания речи (Speech.framework — iOS 10+), поэтому:
//  • Озвучка — целиком на устройстве: собственный формантный синтезатор VoxSynth
//    (Classes/Voice/Vox) + AVAudioPlayer. Без сервера, ключей и интернета.
//    Говорит только по-русски (цифры — словами, латиница — транслитом).
//  • Распознавание — на выбор (sttMode):
//      - сервер: запись AAC (.m4a) через AVAudioRecorder и отправка на
//        {base}/audio/transcriptions (Whisper);
//      - на устройстве: запись в WAV (PCM 16 кГц, 16 бит, моно) и локальный движок
//        MAOnDeviceRecognizer. Движок пока каркас: см. Classes/Voice/Stt.
@interface MAVoiceService : NSObject

+ (instancetype)sharedService;

@property (nonatomic, strong, readonly) MAVoiceProvider *sttProvider;

// Куда отправлять запись: на сервер (по умолчанию) или в локальный движок.
// Читается в момент старта записи — смена режима посреди записи её не ломает.
@property (nonatomic, assign) MAVoiceSTTMode sttMode;

// Озвучивать ВСЕ ответы ИИ (по умолчанию включено). Если выключено — озвучиваются только ответы на
// сообщения, надиктованные голосом.
@property (nonatomic, assign) BOOL autoSpeak;

// Тембр голоса: 0 — стандартный, 1 — мужской, 2 — женский.
@property (nonatomic, assign) NSInteger voiceStyle;

// Скорость речи, слов в минуту (норма — 170).
@property (nonatomic, assign) NSInteger speechRate;

// Вызывается на main thread при сбое озвучки (неверный ключ, нет сети и т.п.).
@property (nonatomic, copy) void (^errorHandler)(NSString *message);

@property (nonatomic, assign, readonly, getter=isRecording) BOOL recording;
@property (nonatomic, assign, readonly, getter=isSpeaking) BOOL speaking;

- (void)persistSettingsForProvider:(MAVoiceProvider *)provider;

// Озвучка встроенным голосом. Ошибки не блокируют чат: сообщение уходит в
// errorHandler (чат покажет его alert'ом).
- (void)speakText:(NSString *)text;
- (void)stopSpeaking;

// Запись голоса. completion(error) — вызывается на main; error == nil,
// если запись началась.
- (void)startRecordingWithCompletion:(void (^)(NSError *error))completion;
- (void)finishRecordingAndTranscribe:(MAVoiceTranscribeCompletion)completion;
- (void)cancelRecording;

@end
