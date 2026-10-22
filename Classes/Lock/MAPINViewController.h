#import <UIKit/UIKit.h>

typedef NS_ENUM(NSInteger, MAPINMode) {
	MAPINModeUnlock, // вход в приложение: ввести PIN, отмены нет
	MAPINModeVerify, // подтвердить текущий PIN (например, перед отключением блокировки)
	MAPINModeCreate, // задать новый PIN: ввод и повтор
	MAPINModeChange, // сменить PIN: текущий, затем новый с повтором
};

// Экран с цифровой клавиатурой. Системная клавиатура не используется: поля
// ввода нет, PIN набирается кнопками, на экране четыре точки.
//
// Экран сам ничего не закрывает и не сохраняет: по завершении вызывает completion
// (success = YES и введенный/новый PIN, либо NO при отмене), а дальше решает вызывающий.
// Пока PIN неверный слишком много раз, кнопки отключены и идет обратный отсчет.
@interface MAPINViewController : UIViewController

- (instancetype)initWithMode:(MAPINMode)mode;

@property (nonatomic, copy) void (^completion)(BOOL success, NSString *pin);

// Останавливает таймер и отложенные вызовы. Нужно звать перед тем, как
// убрать экран без viewWillDisappear (например, окно блокировки).
- (void)teardown;

@end
