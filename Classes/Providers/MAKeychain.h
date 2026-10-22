#import <Foundation/Foundation.h>

// Обёртка над Keychain для секретов (API-ключей).
// Ключи НИКОГДА не должны лежать в NSUserDefaults или .plist — только здесь.
//
// Поверх самого Keychain значения дополнительно шифруются AES-256 (MAVault):
// в записи лежит не сам ключ, а зашифрованный блок. Если задан PIN-код, а
// хранилище ещё не открыто, ключи не читаются и не пишутся.
@interface MAKeychain : NSObject

+ (void)setString:(NSString *)value forKey:(NSString *)key;
+ (NSString *)stringForKey:(NSString *)key;
+ (void)deleteKey:(NSString *)key;

// Шифрует все записи, сохранённые старой версией открытым текстом.
// Вызывается после открытия хранилища. Уже зашифрованные не трогает.
+ (void)encryptLegacyItems;

@end
