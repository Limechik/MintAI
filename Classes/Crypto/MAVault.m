#import "MAVault.h"
#import "MAAppLock.h"
#import <Security/Security.h>
#import <CommonCrypto/CommonCryptor.h>      // CCCrypt, kCCSuccess
#import <CommonCrypto/CommonHMAC.h>         // CCHmac
#import <CommonCrypto/CommonKeyDerivation.h> // CCKeyDerivationPBKDF

static NSString *const kVaultService = @"com.mintai.app.vault";
static NSString *const kPlainAccount = @"master";   // мастер-ключ открытым видом (PIN не задан)
static NSString *const kWrappedAccount = @"wrapped"; // мастер-ключ, зашифрованный ключом из PIN

static const uint8_t kMagicData[4] = { 'M', 'A', 'E', '1' };
static const uint8_t kMagicWrapped[4] = { 'M', 'A', 'W', '1' };

static const NSUInteger kMagicLength = 4;
static const NSUInteger kKeyLength = 32;
static const NSUInteger kIVLength = 16;
static const NSUInteger kMACLength = 32;
static const NSUInteger kSaltLength = 16;
static const uint32_t kWrapRounds = 20000;

#pragma mark - Примитивы

static NSData *MARandomBytes(NSUInteger length) {
	NSMutableData *data = [NSMutableData dataWithLength:length];
	if (SecRandomCopyBytes(kSecRandomDefault, length, data.mutableBytes) != 0) {
		arc4random_buf(data.mutableBytes, length);
	}
	return data;
}

static BOOL MAHasMagic(NSData *data, const uint8_t *magic) {
	return data.length >= kMagicLength && memcmp(data.bytes, magic, kMagicLength) == 0;
}

// Сравнение без раннего выхода: время не зависит от того, где значения разошлись.
static BOOL MAConstantTimeEqual(NSData *a, NSData *b) {
	if (a.length != b.length) return NO;
	const uint8_t *x = a.bytes;
	const uint8_t *y = b.bytes;
	uint8_t diff = 0;
	for (NSUInteger i = 0; i < a.length; i++) diff |= (x[i] ^ y[i]);
	return diff == 0;
}

static NSData *MAHMAC(NSData *key, NSData *data) {
	uint8_t mac[CC_SHA256_DIGEST_LENGTH];
	CCHmac(kCCHmacAlgSHA256, key.bytes, key.length, data.bytes, data.length, mac);
	return [NSData dataWithBytes:mac length:sizeof(mac)];
}

// Из одного ключа получаем два независимых: для AES и для HMAC.
static NSData *MASubkey(NSData *rootKey, NSString *label) {
	return MAHMAC(rootKey, [label dataUsingEncoding:NSUTF8StringEncoding]);
}

static NSData *MADerivePINKey(NSString *pin, NSData *salt, uint32_t rounds) {
	NSData *pinData = [pin dataUsingEncoding:NSUTF8StringEncoding];
	uint8_t derived[32];
	int status = CCKeyDerivationPBKDF(kCCPBKDF2,
	                                  (const char *)pinData.bytes, pinData.length,
	                                  (const uint8_t *)salt.bytes, salt.length,
	                                  kCCPRFHmacAlgSHA256, rounds,
	                                  derived, sizeof(derived));
	if (status != kCCSuccess) return nil;
	return [NSData dataWithBytes:derived length:sizeof(derived)];
}

#pragma mark - AES-256 + HMAC

// "MAE1" | IV | AES-256-CBC(plain) | HMAC-SHA256(всё, что до него)
static NSData *MASeal(NSData *plain, NSData *rootKey) {
	NSData *encKey = MASubkey(rootKey, @"mintai.enc");
	NSData *macKey = MASubkey(rootKey, @"mintai.mac");
	NSData *iv = MARandomBytes(kIVLength);
	if (encKey.length != kCCKeySizeAES256 || macKey.length == 0) return nil;

	size_t capacity = plain.length + kCCBlockSizeAES128;
	NSMutableData *cipher = [NSMutableData dataWithLength:capacity];
	size_t moved = 0;
	// kCCAlgorithmAES128 — это просто «AES»; разрядность определяет длина ключа
	// (32 байта = AES-256).
	CCCryptorStatus status = CCCrypt(kCCEncrypt, kCCAlgorithmAES128, kCCOptionPKCS7Padding,
	                                 encKey.bytes, kCCKeySizeAES256, iv.bytes,
	                                 plain.length > 0 ? plain.bytes : "", plain.length,
	                                 cipher.mutableBytes, capacity, &moved);
	if (status != kCCSuccess) return nil;
	cipher.length = moved;

	NSMutableData *blob = [NSMutableData dataWithBytes:kMagicData length:kMagicLength];
	[blob appendData:iv];
	[blob appendData:cipher];
	[blob appendData:MAHMAC(macKey, blob)];
	return blob;
}

// Сначала проверяем HMAC и только потом расшифровываем: подделку отсекаем до AES.
static NSData *MAOpen(NSData *blob, NSData *rootKey) {
	const NSUInteger header = kMagicLength + kIVLength;
	if (blob.length < header + kCCBlockSizeAES128 + kMACLength) return nil;
	if (!MAHasMagic(blob, kMagicData)) return nil;

	NSData *encKey = MASubkey(rootKey, @"mintai.enc");
	NSData *macKey = MASubkey(rootKey, @"mintai.mac");
	if (encKey.length != kCCKeySizeAES256 || macKey.length == 0) return nil;

	NSUInteger macOffset = blob.length - kMACLength;
	NSData *body = [blob subdataWithRange:NSMakeRange(0, macOffset)];
	NSData *storedMAC = [blob subdataWithRange:NSMakeRange(macOffset, kMACLength)];
	if (!MAConstantTimeEqual(MAHMAC(macKey, body), storedMAC)) return nil;

	NSUInteger cipherLength = macOffset - header;
	if (cipherLength == 0 || cipherLength % kCCBlockSizeAES128 != 0) return nil;

	const uint8_t *bytes = blob.bytes;
	NSMutableData *plain = [NSMutableData dataWithLength:cipherLength];
	size_t moved = 0;
	CCCryptorStatus status = CCCrypt(kCCDecrypt, kCCAlgorithmAES128, kCCOptionPKCS7Padding,
	                                 encKey.bytes, kCCKeySizeAES256, bytes + kMagicLength,
	                                 bytes + header, cipherLength,
	                                 plain.mutableBytes, cipherLength, &moved);
	if (status != kCCSuccess) return nil;
	plain.length = moved;
	return plain;
}

#pragma mark - Упаковка мастер-ключа PIN-кодом

// "MAW1" | итерации PBKDF2 (4, big-endian) | соль (16) | MASeal(мастер-ключ, ключ из PIN)
static NSData *MAWrapMasterKey(NSData *masterKey, NSString *pin) {
	NSData *salt = MARandomBytes(kSaltLength);
	NSData *pinKey = MADerivePINKey(pin, salt, kWrapRounds);
	NSData *sealed = pinKey ? MASeal(masterKey, pinKey) : nil;
	if (!sealed) return nil;

	uint8_t rounds[4] = { (uint8_t)(kWrapRounds >> 24), (uint8_t)(kWrapRounds >> 16), (uint8_t)(kWrapRounds >> 8), (uint8_t)kWrapRounds };
	NSMutableData *blob = [NSMutableData dataWithBytes:kMagicWrapped length:kMagicLength];
	[blob appendBytes:rounds length:sizeof(rounds)];
	[blob appendData:salt];
	[blob appendData:sealed];
	return blob;
}

static NSData *MAUnwrapMasterKey(NSData *wrapped, NSString *pin) {
	const NSUInteger header = kMagicLength + 4 + kSaltLength;
	if (wrapped.length <= header || !MAHasMagic(wrapped, kMagicWrapped)) return nil;

	const uint8_t *bytes = wrapped.bytes;
	uint32_t rounds = ((uint32_t)bytes[4] << 24) | ((uint32_t)bytes[5] << 16) | ((uint32_t)bytes[6] << 8) | (uint32_t)bytes[7];
	if (rounds < 1000 || rounds > 1000000) return nil; // защита от испорченного заголовка, из-за которого PBKDF2 «зависнет»

	NSData *salt = [wrapped subdataWithRange:NSMakeRange(kMagicLength + 4, kSaltLength)];
	NSData *sealed = [wrapped subdataWithRange:NSMakeRange(header, wrapped.length - header)];
	NSData *pinKey = MADerivePINKey(pin, salt, rounds);
	NSData *key = pinKey ? MAOpen(sealed, pinKey) : nil;
	return (key.length == kKeyLength) ? key : nil;
}

#pragma mark - Keychain (свои записи хранилища)

// Отдельный service: эти записи не должны попадать под шифрование MAKeychain
// (иначе ключ шифровался бы самим собой).
static NSMutableDictionary *MAVaultQuery(NSString *account) {
	return [@{
		(__bridge id)kSecClass: (__bridge id)kSecClassGenericPassword,
		(__bridge id)kSecAttrService: kVaultService,
		(__bridge id)kSecAttrAccount: account
	} mutableCopy];
}

static NSData *MAVaultRead(NSString *account) {
	NSMutableDictionary *query = MAVaultQuery(account);
	query[(__bridge id)kSecReturnData] = @YES;
	query[(__bridge id)kSecMatchLimit] = (__bridge id)kSecMatchLimitOne;
	CFTypeRef result = NULL;
	if (SecItemCopyMatching((__bridge CFDictionaryRef)query, &result) != errSecSuccess || result == NULL) return nil;
	return (__bridge_transfer NSData *)result;
}

// Запись не удаляется перед заменой: если бы SecItemAdd после этого не удался,
// ключ пропал бы насовсем. Сначала пробуем обновить существующую запись.
static BOOL MAVaultWrite(NSString *account, NSData *data) {
	// ThisDeviceOnly: ключ не попадает в резервные копии и не переезжает на другое устройство.
	id accessible = (__bridge id)kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly;

	if (SecItemCopyMatching((__bridge CFDictionaryRef)MAVaultQuery(account), NULL) == errSecSuccess) {
		NSDictionary *update = @{
			(__bridge id)kSecValueData: data,
			(__bridge id)kSecAttrAccessible: accessible
		};
		OSStatus updateStatus = SecItemUpdate((__bridge CFDictionaryRef)MAVaultQuery(account), (__bridge CFDictionaryRef)update);
		if (updateStatus != errSecSuccess) {
			NSLog(@"[MAVault] SecItemUpdate для '%@' вернул статус %d", account, (int)updateStatus);
		}
		return updateStatus == errSecSuccess;
	}

	NSMutableDictionary *query = MAVaultQuery(account);
	query[(__bridge id)kSecValueData] = data;
	query[(__bridge id)kSecAttrAccessible] = accessible;
	OSStatus addStatus = SecItemAdd((__bridge CFDictionaryRef)query, NULL);
	if (addStatus != errSecSuccess) {
		NSLog(@"[MAVault] SecItemAdd для '%@' вернул статус %d", account, (int)addStatus);
	}
	return addStatus == errSecSuccess;
}

static void MAVaultDelete(NSString *account) {
	SecItemDelete((__bridge CFDictionaryRef)MAVaultQuery(account));
}

#pragma mark - MAVault

@interface MAVault ()
@property (atomic, strong) NSData *masterKey;
@property (nonatomic, assign) BOOL unavailable;
@end

@implementation MAVault

+ (instancetype)sharedVault {
	static MAVault *shared = nil;
	static dispatch_once_t onceToken;
	dispatch_once(&onceToken, ^{
		shared = [[MAVault alloc] init];
	});
	return shared;
}

- (BOOL)isUnlocked {
	return self.masterKey != nil;
}

- (void)prepareAtLaunch {
	if ([MAAppLock sharedLock].enabled) return; // ключ упакован PIN-кодом: ждём ввода

	NSData *key = MAVaultRead(kPlainAccount);
	if (key.length != kKeyLength) {
		// Ключа нет (первый запуск) — создаём. Заодно убираем «осиротевший»
		// упакованный ключ: он остаётся в Keychain после переустановки, когда
		// PIN уже сброшен, и расшифровать его нечем.
		key = MARandomBytes(kKeyLength);
		if (!MAVaultWrite(kPlainAccount, key)) {
			NSLog(@"[MAVault] не удалось сохранить ключ в Keychain: данные будут храниться без шифрования");
			self.unavailable = YES;
			return;
		}
		MAVaultDelete(kWrappedAccount);
	}
	self.masterKey = key;
}

- (BOOL)unlockWithPIN:(NSString *)pin {
	if (self.masterKey) return YES; // уже открыто (возврат из фона)

	NSData *key = nil;
	BOOL needsWrap = NO;

	NSData *plain = MAVaultRead(kPlainAccount);
	if (plain.length == kKeyLength) {
		// PIN уже есть, а ключ ещё лежит открытым: первый запуск после обновления
		// или сбой на полпути при смене режима. Упакуем его PIN-ом.
		key = plain;
		needsWrap = YES;
	} else {
		NSData *wrapped = MAVaultRead(kWrappedAccount);
		if (wrapped) key = MAUnwrapMasterKey(wrapped, pin);
		if (key.length != kKeyLength) {
			// Ключа нет или упакованный блок повреждён: начинаем с нового.
			key = MARandomBytes(kKeyLength);
			needsWrap = YES;
		}
	}

	if (needsWrap) {
		NSData *wrapped = MAWrapMasterKey(key, pin);
		if (!wrapped || !MAVaultWrite(kWrappedAccount, wrapped)) {
			NSLog(@"[MAVault] не удалось сохранить упакованный ключ: данные будут храниться без шифрования");
			self.unavailable = YES;
			return NO;
		}
		MAVaultDelete(kPlainAccount);
	}

	self.masterKey = key;
	return YES;
}

- (BOOL)pinDidChange:(NSString *)pin {
	// Шифрования нет — упаковывать нечего, PIN можно менять.
	if (self.unavailable) return YES;
	if (!self.masterKey) return NO; // закрыто: перепаковать нечем, PIN менять нельзя

	NSData *wrapped = MAWrapMasterKey(self.masterKey, pin);
	if (!wrapped || !MAVaultWrite(kWrappedAccount, wrapped)) {
		NSLog(@"[MAVault] не удалось упаковать ключ новым PIN-кодом");
		return NO; // PIN не меняем: иначе данные стали бы нечитаемыми
	}
	MAVaultDelete(kPlainAccount);
	return YES;
}

- (BOOL)pinWasRemoved {
	if (self.unavailable) return YES;
	if (!self.masterKey) return NO;

	if (!MAVaultWrite(kPlainAccount, self.masterKey)) {
		NSLog(@"[MAVault] не удалось вернуть ключ в Keychain");
		return NO; // PIN оставляем: иначе при следующем запуске ключ потерялся бы
	}
	MAVaultDelete(kWrappedAccount);
	return YES;
}

- (NSData *)encryptData:(NSData *)plaintext {
	NSData *key = self.masterKey;
	if (!key || !plaintext) return nil;
	return MASeal(plaintext, key);
}

- (NSData *)decryptData:(NSData *)blob {
	NSData *key = self.masterKey;
	if (!key || !blob) return nil;
	return MAOpen(blob, key);
}

+ (BOOL)dataIsEncrypted:(NSData *)data {
	return MAHasMagic(data, kMagicData);
}

@end
