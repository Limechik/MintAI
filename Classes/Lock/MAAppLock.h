#import <Foundation/Foundation.h>

// Рассылается, когда пользователь ввёл верный PIN на экране блокировки
// (в том числе при холодном запуске: тогда MAAppDelegate строит интерфейс).
extern NSString *const MAAppLockDidUnlockNotification;

typedef NS_ENUM(NSInteger, MAPINVerifyResult) {
	MAPINVerifyResultOK,
	MAPINVerifyResultWrong,
	MAPINVerifyResultLockedOut, // слишком много неверных попыток, нужно подождать
};

// Блокировка приложения 4-значным PIN-кодом.
//
// Что делает:
//  • хранит PIN в виде соленого хеша PBKDF2-SHA256 (сам PIN нигде не лежит);
//  • после 5 неверных попыток включает паузу: 30 с, 1 мин, 5 мин, затем 15 мин;
//  • закрывает приложение отдельным окном поверх всего (в том числе поверх
//    алертов и клавиатуры): при запуске и при возврате из фона. Заодно
//    экран блокировки попадает в снимок для переключателя задач, так что
//    переписка там не видна.
//
// Шифрование: сам PIN данные не шифрует, но защищает ключ шифрования истории и
// API-ключей (см. MAVault): при установке, смене и снятии PIN ключ перепаковывается,
// а при запуске с PIN хранилище открывается только после верного ввода. PIN всего
// 4 цифры, поэтому от целенаправленного перебора он не спасёт.
// Хеш PIN лежит в NSUserDefaults, а не в Keychain: Keychain в iOS переживает
// удаление приложения, и забытый PIN нельзя было бы сбросить переустановкой
// (при этом зашифрованные данные пропадают).
//
// Жизненный цикл: MAAppDelegate пробрасывает сюда четыре события приложения.
@interface MAAppLock : NSObject

+ (instancetype)sharedLock;

// YES, если PIN задан.
@property (nonatomic, readonly, getter=isEnabled) BOOL enabled;

// Через сколько секунд после ухода в фон снова спрашивать PIN: 0 — сразу.
// Допустимые значения — см. +autoLockDelayAtIndex:.
@property (nonatomic, assign) NSInteger autoLockDelay;

// Задает (или меняет) PIN. Возвращает NO, если это не ровно 4 цифры.
- (BOOL)setPIN:(NSString *)pin;

// Убирает PIN и сбрасывает счетчик неверных попыток.
- (void)removePIN;

- (MAPINVerifyResult)verifyPIN:(NSString *)pin;

// Сколько секунд осталось ждать после серии неверных попыток (0 — можно вводить).
- (NSTimeInterval)lockoutRemaining;

#pragma mark - Варианты «Запрашивать PIN-код»

+ (NSInteger)autoLockOptionCount;
+ (NSInteger)autoLockDelayAtIndex:(NSInteger)index;
+ (NSString *)autoLockTitleAtIndex:(NSInteger)index; // уже переведено
- (NSString *)autoLockSummary;

#pragma mark - События приложения (вызывает MAAppDelegate)

- (void)applicationDidFinishLaunching;
- (void)applicationWillResignActive;
- (void)applicationDidEnterBackground;
- (void)applicationDidBecomeActive;

@end
