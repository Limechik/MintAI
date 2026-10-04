#import <UIKit/UIKit.h>

// Рассылается, когда пользователь переключил тему: экраны, которые уже на виду
// (чат, история, настройки, бары), перекрашиваются на лету.
extern NSString *const MAThemeDidChangeNotification;

// Идентификатор ячейки с учётом темы. Ячейки grouped-таблиц в тёмной теме получают
// собственный фон, а вернуть штатный вид iOS 6 обратно нельзя — поэтому у светлой
// и тёмной тем разные очереди переиспользования.
#define MAThemedReuseID(base) [[MATheme sharedTheme] reuseIdentifierWithBase:(base)]

// Тема оформления: светлая (как раньше) или тёмная.
//
// В iOS 6 нет системной тёмной темы, поэтому всё рисуем сами: экраны берут цвета
// отсюда, а не из UIColor-констант. Чтобы добавить цвет — новое свойство ниже и по
// значению для каждой темы в MATheme.m.
@interface MATheme : NSObject

+ (instancetype)sharedTheme;

// YES — тёмная тема. Сохраняется в NSUserDefaults; при смене рассылается
// MAThemeDidChangeNotification. По умолчанию светлая.
@property (nonatomic, assign, getter=isDark) BOOL dark;

#pragma mark - Цвета

@property (nonatomic, readonly) UIColor *accentColor;               // мятный цвет бренда (выбранная вкладка, галочки)
@property (nonatomic, readonly) UIColor *actionColor;               // текст кнопок-ячеек («Сделать активным»)
@property (nonatomic, readonly) UIColor *navigationBarTintColor;

@property (nonatomic, readonly) UIColor *backgroundColor;           // фон чата, редактора, plain-таблиц
@property (nonatomic, readonly) UIColor *groupedBackgroundColor;    // фон grouped-таблиц (настройки)
@property (nonatomic, readonly) UIColor *cellBackgroundColor;
@property (nonatomic, readonly) UIColor *cellSelectedColor;
@property (nonatomic, readonly) UIColor *separatorColor;

@property (nonatomic, readonly) UIColor *primaryTextColor;
@property (nonatomic, readonly) UIColor *secondaryTextColor;
@property (nonatomic, readonly) UIColor *placeholderTextColor;

@property (nonatomic, readonly) UIColor *groupedHeaderTextColor;    // заголовки/подписи секций grouped-таблиц
@property (nonatomic, readonly) UIColor *groupedHeaderShadowColor;

@property (nonatomic, readonly) UIColor *inputBarColor;             // панель ввода и панель вложения
@property (nonatomic, readonly) UIColor *inputBarBorderColor;
@property (nonatomic, readonly) UIColor *thumbnailPlaceholderColor;

@property (nonatomic, readonly) UIKeyboardAppearance keyboardAppearance;

#pragma mark - Помощники

- (NSString *)reuseIdentifierWithBase:(NSString *)base;

- (void)styleActionSheet:(UIActionSheet *)sheet;

// UIAppearance для баров, которые будут созданы позже (например, окно выбора фото).
- (void)applyAppearanceProxies;

// Перекрашивает уже созданные таб-бар и navigation bar'ы (UIAppearance на них не действует).
- (void)applyToTabBarController:(UITabBarController *)tabBarController;

@end
