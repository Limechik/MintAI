#import <Foundation/Foundation.h>

typedef void (^MAOnDeviceCompletion)(NSString *text, NSError *error);

// Распознавание речи на устройстве: читает WAV (PCM 16 кГц, 16 бит, моно — так
// пишет MAVoiceService в локальном режиме), гоняет его через движок MASttEngine
// в фоновом потоке и отдаёт текст на main thread.
//
// Файл модели лежит в Documents/stt/model.bin. Пока движок — каркас без нейросети:
// запись проходит весь путь до признаков, а на месте текста возвращается ошибка
// «декодер ещё не готов» (см. MASttEngine.h).
@interface MAOnDeviceRecognizer : NSObject

+ (instancetype)sharedRecognizer;

// Полный путь к файлу модели.
@property (nonatomic, copy, readonly) NSString *modelPath;

// Лежит ли непустой файл модели.
- (BOOL)isModelInstalled;

// Забыть загруженную модель (например, после замены файла).
- (void)reloadModel;

// completion вызывается на main thread: либо текст, либо ошибка.
- (void)transcribeWAVAtPath:(NSString *)path completion:(MAOnDeviceCompletion)completion;

@end
