#import <Foundation/Foundation.h>

// Рассылается, когда пользователь сменил язык интерфейса: экраны, которые уже
// на виду (чат, история, настройки, вкладки), перечитывают свои тексты.
extern NSString *const MALanguageDidChangeNotification;

extern NSString *const MALanguageCodeRussian; // @"ru"
extern NSString *const MALanguageCodeEnglish; // @"en"

// Перевод строки интерфейса на выбранный язык.
//
// Ключ — это сам русский текст (как в исходниках). Для русского языка строка
// возвращается как есть, для английского ищется в Resources/en.lproj/Localizable.strings;
// если перевода нет, вернётся исходный текст — приложение не сломается.
NSString *MALocalizedString(NSString *key);

// Язык интерфейса внутри приложения (не зависит от языка системы).
@interface MALocalization : NSObject

+ (instancetype)sharedLocalization;

// @"ru" (по умолчанию) или @"en". Сохраняется в NSUserDefaults; при смене
// рассылается MALanguageDidChangeNotification.
@property (nonatomic, copy) NSString *languageCode;

@property (nonatomic, assign, readonly, getter=isEnglish) BOOL english;

- (NSString *)localizedStringForKey:(NSString *)key;

@end
