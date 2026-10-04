#import <Foundation/Foundation.h>

// Простая обёртка над Keychain для хранения секретов (API-ключей).
// Ключи НИКОГДА не должны лежать в NSUserDefaults или .plist — только здесь.
@interface MAKeychain : NSObject

+ (void)setString:(NSString *)value forKey:(NSString *)key;
+ (NSString *)stringForKey:(NSString *)key;
+ (void)deleteKey:(NSString *)key;

@end
