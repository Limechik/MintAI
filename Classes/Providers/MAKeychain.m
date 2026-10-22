#import "MAKeychain.h"
#import "MAVault.h"
#import <Security/Security.h>

static NSString *const kMAKeychainService = @"com.mintai.app";

@implementation MAKeychain

+ (NSMutableDictionary *)baseQueryForKey:(NSString *)key {
	return [@{
		(__bridge id)kSecClass: (__bridge id)kSecClassGenericPassword,
		(__bridge id)kSecAttrService: kMAKeychainService,
		(__bridge id)kSecAttrAccount: key,
		// Явно фиксируем доступность, а не полагаемся на дефолт
		// (kSecAttrAccessibleWhenUnlocked), чтобы поведение не зависело
		// от состояния блокировки устройства в момент чтения/записи.
		(__bridge id)kSecAttrAccessible: (__bridge id)kSecAttrAccessibleAfterFirstUnlock
	} mutableCopy];
}

+ (void)setString:(NSString *)value forKey:(NSString *)key {
	if (key.length == 0) return;

	if (value.length == 0) {
		[self deleteKey:key];
		return;
	}

	NSData *plain = [value dataUsingEncoding:NSUTF8StringEncoding];
	NSData *data = [[MAVault sharedVault] encryptData:plain];
	if (!data) {
		if ([MAVault sharedVault].unavailable) {
			data = plain; // шифрование недоступно: сохраняем как раньше
		} else {
			NSLog(@"[MAKeychain] хранилище закрыто — значение '%@' НЕ сохранено", key);
			return;
		}
	}
	NSMutableDictionary *query = [self baseQueryForKey:key];

	OSStatus existsStatus = SecItemCopyMatching((__bridge CFDictionaryRef)query, NULL);
	if (existsStatus == errSecSuccess) {
		NSDictionary *update = @{(__bridge id)kSecValueData: data};
		OSStatus updateStatus = SecItemUpdate((__bridge CFDictionaryRef)query, (__bridge CFDictionaryRef)update);
		if (updateStatus != errSecSuccess) {
			NSLog(@"[MAKeychain] SecItemUpdate для '%@' вернул статус %d — значение НЕ сохранено", key, (int)updateStatus);
		}
	} else {
		query[(__bridge id)kSecValueData] = data;
		OSStatus addStatus = SecItemAdd((__bridge CFDictionaryRef)query, NULL);
		if (addStatus != errSecSuccess) {
			// -34018 (errSecMissingEntitlement) — типичный признак, что
			// бинарь подписан без keychain-access-groups.
			NSLog(@"[MAKeychain] SecItemAdd для '%@' вернул статус %d — значение НЕ сохранено", key, (int)addStatus);
		}
	}
}

+ (NSString *)stringForKey:(NSString *)key {
	if (key.length == 0) return nil;

	NSMutableDictionary *query = [self baseQueryForKey:key];
	query[(__bridge id)kSecReturnData] = @YES;
	query[(__bridge id)kSecMatchLimit] = (__bridge id)kSecMatchLimitOne;

	CFTypeRef result = NULL;
	OSStatus status = SecItemCopyMatching((__bridge CFDictionaryRef)query, &result);
	if (status != errSecSuccess || result == NULL) {
		return nil;
	}

	NSData *data = (__bridge_transfer NSData *)result;

	if ([MAVault dataIsEncrypted:data]) {
		NSData *plain = [[MAVault sharedVault] decryptData:data];
		if (!plain) return nil; // хранилище закрыто либо запись повреждена/подделана
		return [[NSString alloc] initWithData:plain encoding:NSUTF8StringEncoding];
	}

	// Запись от старой версии, открытым текстом: отдаём как есть и сразу шифруем.
	NSString *legacy = [[NSString alloc] initWithData:data encoding:NSUTF8StringEncoding];
	if (legacy.length > 0 && [MAVault sharedVault].unlocked) {
		[self setString:legacy forKey:key];
	}
	return legacy;
}

+ (void)encryptLegacyItems {
	if (![MAVault sharedVault].unlocked) return;

	NSMutableDictionary *query = [@{
		(__bridge id)kSecClass: (__bridge id)kSecClassGenericPassword,
		(__bridge id)kSecAttrService: kMAKeychainService,
		(__bridge id)kSecReturnAttributes: @YES,
		(__bridge id)kSecReturnData: @YES,
		(__bridge id)kSecMatchLimit: (__bridge id)kSecMatchLimitAll
	} mutableCopy];

	CFTypeRef result = NULL;
	if (SecItemCopyMatching((__bridge CFDictionaryRef)query, &result) != errSecSuccess || result == NULL) return;

	NSArray *items = (__bridge_transfer NSArray *)result;
	for (NSDictionary *item in items) {
		NSData *data = item[(__bridge id)kSecValueData];
		NSString *account = item[(__bridge id)kSecAttrAccount];
		if (![data isKindOfClass:[NSData class]] || ![account isKindOfClass:[NSString class]]) continue;
		if ([MAVault dataIsEncrypted:data]) continue;

		NSString *plaintext = [[NSString alloc] initWithData:data encoding:NSUTF8StringEncoding];
		if (plaintext.length > 0) [self setString:plaintext forKey:account];
	}
}

+ (void)deleteKey:(NSString *)key {
	if (key.length == 0) return;
	NSMutableDictionary *query = [self baseQueryForKey:key];
	SecItemDelete((__bridge CFDictionaryRef)query);
}

@end
