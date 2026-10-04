#import <Foundation/Foundation.h>

// «Инструкция» (custom instructions / системный промпт): текст, который
// подмешивается в начало каждого запроса к ИИ, чтобы не повторять одно и то же
// в каждом чате («отвечай кратко», «обращайся на ты» и т.п.).
//
// Хранится в NSUserDefaults — это не секрет (в отличие от API-ключей, которым
// место в Keychain). Общая для всех провайдеров.
@interface MAInstructionsStore : NSObject

+ (instancetype)sharedStore;

// Текст инструкции (может быть пустым).
@property (nonatomic, copy) NSString *instructions;

// Выключатель: позволяет отключить инструкцию, не стирая текст. По умолчанию YES.
@property (nonatomic, assign) BOOL enabled;

// Текст, который реально нужно отправить: nil, если инструкция выключена или пуста.
- (NSString *)activeInstructions;

// Принудительно сбрасывает настройки на диск.
- (void)synchronize;

@end
