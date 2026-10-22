#import "MAAppLock.h"
#import "MAPINViewController.h"
#import "MAVault.h"
#import "MALocalization.h"
#import <UIKit/UIKit.h>
#import <Security/Security.h>
#import <CommonCrypto/CommonCryptor.h>      // kCCSuccess
#import <CommonCrypto/CommonKeyDerivation.h> // CCKeyDerivationPBKDF

NSString *const MAAppLockDidUnlockNotification = @"MAAppLockDidUnlockNotification";

static NSString *const kPINHashKey = @"MAPINHash";
static NSString *const kPINSaltKey = @"MAPINSalt";
static NSString *const kPINAttemptsKey = @"MAPINFailedAttempts";
static NSString *const kPINLockoutUntilKey = @"MAPINLockoutUntil";
static NSString *const kAutoLockDelayKey = @"MAPINAutoLockDelay";

static const NSInteger kPINLength = 4;
static const NSInteger kAttemptsBeforeLockout = 5;
static const uint32_t kPBKDFRounds = 10000;

static const NSInteger kAutoLockDelays[] = { 0, 60, 300, 900 };
static NSString *const kAutoLockTitles[] = { @"Сразу", @"Через 1 минуту", @"Через 5 минут", @"Через 15 минут" };
static const NSInteger kAutoLockCount = 4;

#pragma mark - Хеш PIN

static BOOL MAIsValidPIN(NSString *pin) {
	if (pin.length != kPINLength) return NO;
	for (NSUInteger i = 0; i < pin.length; i++) {
		unichar c = [pin characterAtIndex:i];
		if (c < '0' || c > '9') return NO;
	}
	return YES;
}

static NSData *MAPINHash(NSString *pin, NSData *salt) {
	NSData *pinData = [pin dataUsingEncoding:NSUTF8StringEncoding];
	uint8_t derived[32];
	int status = CCKeyDerivationPBKDF(kCCPBKDF2,
	                                  (const char *)pinData.bytes, pinData.length,
	                                  (const uint8_t *)salt.bytes, salt.length,
	                                  kCCPRFHmacAlgSHA256, kPBKDFRounds,
	                                  derived, sizeof(derived));
	if (status != kCCSuccess) return nil;
	return [NSData dataWithBytes:derived length:sizeof(derived)];
}

// Сравнение без раннего выхода: время не зависит от того, где хеши разошлись.
static BOOL MAConstantTimeEqual(NSData *a, NSData *b) {
	if (a.length != b.length) return NO;
	const uint8_t *x = a.bytes;
	const uint8_t *y = b.bytes;
	uint8_t diff = 0;
	for (NSUInteger i = 0; i < a.length; i++) diff |= (x[i] ^ y[i]);
	return diff == 0;
}

static NSData *MARandomSalt(void) {
	uint8_t bytes[16];
	if (SecRandomCopyBytes(kSecRandomDefault, sizeof(bytes), bytes) != 0) {
		for (NSUInteger i = 0; i < sizeof(bytes); i++) bytes[i] = (uint8_t)arc4random_uniform(256);
	}
	return [NSData dataWithBytes:bytes length:sizeof(bytes)];
}

// Пауза после N-й подряд неверной попытки (N >= 5), секунды.
static NSTimeInterval MALockoutPenalty(NSInteger attempts) {
	if (attempts < kAttemptsBeforeLockout) return 0;
	switch (attempts - kAttemptsBeforeLockout) {
		case 0:  return 30;
		case 1:  return 60;
		case 2:  return 300;
		default: return 900;
	}
}

@interface MAAppLock ()
@property (nonatomic, strong) UIWindow *lockWindow;
@property (nonatomic, strong) MAPINViewController *lockController;
// YES, если на экране нужно ввести PIN. NO — окно только прикрывает содержимое
// (шторка уведомлений, системный алерт, быстрый возврат из фона).
@property (nonatomic, assign) BOOL unlockRequired;
@property (nonatomic, strong) NSDate *backgroundDate;
@end

@implementation MAAppLock

+ (instancetype)sharedLock {
	static MAAppLock *shared = nil;
	static dispatch_once_t onceToken;
	dispatch_once(&onceToken, ^{
		shared = [[MAAppLock alloc] init];
	});
	return shared;
}

#pragma mark - PIN

- (BOOL)isEnabled {
	NSUserDefaults *defaults = [NSUserDefaults standardUserDefaults];
	return [defaults dataForKey:kPINHashKey] != nil && [defaults dataForKey:kPINSaltKey] != nil;
}

- (BOOL)setPIN:(NSString *)pin {
	if (!MAIsValidPIN(pin)) return NO;

	NSData *salt = MARandomSalt();
	NSData *hash = MAPINHash(pin, salt);
	if (!hash) return NO;

	// Ключ шифрования данных перепаковываем новым PIN-ом (до записи самого PIN).
	// Не получилось — PIN не меняем, иначе зашифрованные данные стали бы нечитаемыми.
	if (![[MAVault sharedVault] pinDidChange:pin]) return NO;

	NSUserDefaults *defaults = [NSUserDefaults standardUserDefaults];
	[defaults setObject:hash forKey:kPINHashKey];
	[defaults setObject:salt forKey:kPINSaltKey];
	[defaults removeObjectForKey:kPINAttemptsKey];
	[defaults removeObjectForKey:kPINLockoutUntilKey];
	[defaults synchronize];
	return YES;
}

- (void)removePIN {
	// Возвращаем ключ шифрования в Keychain, пока он ещё в памяти. Не вышло —
	// PIN остаётся, иначе при следующем запуске ключ был бы потерян.
	if (![[MAVault sharedVault] pinWasRemoved]) return;

	NSUserDefaults *defaults = [NSUserDefaults standardUserDefaults];
	[defaults removeObjectForKey:kPINHashKey];
	[defaults removeObjectForKey:kPINSaltKey];
	[defaults removeObjectForKey:kPINAttemptsKey];
	[defaults removeObjectForKey:kPINLockoutUntilKey];
	[defaults synchronize];
}

- (MAPINVerifyResult)verifyPIN:(NSString *)pin {
	if ([self lockoutRemaining] > 0) return MAPINVerifyResultLockedOut;

	NSUserDefaults *defaults = [NSUserDefaults standardUserDefaults];
	NSData *storedHash = [defaults dataForKey:kPINHashKey];
	NSData *salt = [defaults dataForKey:kPINSaltKey];
	if (!storedHash || !salt || !MAIsValidPIN(pin)) return MAPINVerifyResultWrong;

	NSData *candidate = MAPINHash(pin, salt);
	if (candidate && MAConstantTimeEqual(candidate, storedHash)) {
		[defaults removeObjectForKey:kPINAttemptsKey];
		[defaults removeObjectForKey:kPINLockoutUntilKey];
		[defaults synchronize];
		return MAPINVerifyResultOK;
	}

	NSInteger attempts = [defaults integerForKey:kPINAttemptsKey] + 1;
	[defaults setInteger:attempts forKey:kPINAttemptsKey];
	NSTimeInterval penalty = MALockoutPenalty(attempts);
	if (penalty > 0) {
		[defaults setObject:[NSDate dateWithTimeIntervalSinceNow:penalty] forKey:kPINLockoutUntilKey];
	}
	[defaults synchronize];
	return MAPINVerifyResultWrong;
}

- (NSTimeInterval)lockoutRemaining {
	NSDate *until = [[NSUserDefaults standardUserDefaults] objectForKey:kPINLockoutUntilKey];
	if (![until isKindOfClass:[NSDate class]]) return 0;
	NSTimeInterval remaining = [until timeIntervalSinceNow];
	return remaining > 0 ? ceil(remaining) : 0;
}

#pragma mark - Автоблокировка

- (NSInteger)autoLockDelay {
	NSInteger saved = [[NSUserDefaults standardUserDefaults] integerForKey:kAutoLockDelayKey];
	for (NSInteger i = 0; i < kAutoLockCount; i++) {
		if (kAutoLockDelays[i] == saved) return saved;
	}
	return 0;
}

- (void)setAutoLockDelay:(NSInteger)autoLockDelay {
	NSUserDefaults *defaults = [NSUserDefaults standardUserDefaults];
	[defaults setInteger:autoLockDelay forKey:kAutoLockDelayKey];
	[defaults synchronize];
}

+ (NSInteger)autoLockOptionCount {
	return kAutoLockCount;
}

+ (NSInteger)autoLockDelayAtIndex:(NSInteger)index {
	return kAutoLockDelays[MAX(0, MIN(index, kAutoLockCount - 1))];
}

+ (NSString *)autoLockTitleAtIndex:(NSInteger)index {
	return MALocalizedString(kAutoLockTitles[MAX(0, MIN(index, kAutoLockCount - 1))]);
}

- (NSString *)autoLockSummary {
	NSInteger delay = self.autoLockDelay;
	for (NSInteger i = 0; i < kAutoLockCount; i++) {
		if (kAutoLockDelays[i] == delay) return [[self class] autoLockTitleAtIndex:i];
	}
	return [[self class] autoLockTitleAtIndex:0];
}

#pragma mark - Окно блокировки

- (void)showLockWindow {
	if (self.lockWindow) return;

	// Клавиатура — отдельное окно, и её можно увидеть сквозь шторку (и в снимке
	// для переключателя задач), поэтому сначала убираем фокус с поля ввода.
	[[[UIApplication sharedApplication] keyWindow] endEditing:YES];

	MAPINViewController *controller = [[MAPINViewController alloc] initWithMode:MAPINModeUnlock];
	__weak typeof(self) weakSelf = self;
	controller.completion = ^(BOOL success, NSString *pin) {
		if (!success) return;
		// На холодном запуске открывает хранилище ключом из PIN; при возврате из фона — ничего.
		[[MAVault sharedVault] unlockWithPIN:pin];
		[weakSelf unlockSucceeded];
	};

	UIWindow *window = [[UIWindow alloc] initWithFrame:[[UIScreen mainScreen] bounds]];
	window.windowLevel = UIWindowLevelAlert + 1; // выше алертов и action sheet'ов
	window.rootViewController = controller;

	self.lockController = controller;
	self.lockWindow = window;
	[window makeKeyAndVisible];
}

- (void)hideLockWindow {
	if (!self.lockWindow) return;

	[self.lockController teardown];
	self.lockWindow.hidden = YES;

	// Возвращаем фокус главному окну приложения.
	for (UIWindow *window in [UIApplication sharedApplication].windows) {
		if (window != self.lockWindow && window.windowLevel == UIWindowLevelNormal) {
			[window makeKeyWindow];
			break;
		}
	}
	self.lockWindow = nil;
	self.lockController = nil;
}

- (void)unlockSucceeded {
	self.unlockRequired = NO;
	// Сначала строим интерфейс (если он ждал PIN), потом убираем экран блокировки.
	[[NSNotificationCenter defaultCenter] postNotificationName:MAAppLockDidUnlockNotification object:self];
	[self hideLockWindow];
}

#pragma mark - События приложения

- (void)applicationDidFinishLaunching {
	if (!self.enabled) return;
	self.unlockRequired = YES;
	[self showLockWindow];
}

- (void)applicationWillResignActive {
	if (!self.enabled) return;
	[self showLockWindow]; // шторка поверх содержимого: снимок для переключателя задач делается уже с ней
}

- (void)applicationDidEnterBackground {
	if (!self.enabled) return;
	self.backgroundDate = [NSDate date];
	[self showLockWindow];
}

- (void)applicationDidBecomeActive {
	if (!self.lockWindow) {
		self.backgroundDate = nil;
		return;
	}
	if (!self.unlockRequired && self.backgroundDate) {
		NSTimeInterval away = -[self.backgroundDate timeIntervalSinceNow];
		if (away >= self.autoLockDelay) self.unlockRequired = YES;
	}
	self.backgroundDate = nil;
	if (!self.unlockRequired) [self hideLockWindow];
}

@end
