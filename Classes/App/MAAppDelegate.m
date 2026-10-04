#import "MAAppDelegate.h"
#import "../Chat/MAChatViewController.h"
#import "../Settings/MASettingsViewController.h"
#import "../History/MAChatHistoryViewController.h"
#import "MALocalization.h"
#import "MATheme.h"

@implementation MAAppDelegate

- (BOOL)application:(UIApplication *)application didFinishLaunchingWithOptions:(NSDictionary *)launchOptions {

	// Тема (светлая: мятный navigation bar, тёмная: тёмно-серый) красит все
	// navigation bar'ы приложения разом. В iOS 6 у UINavigationBar ещё нет
	// barTintColor (он появился в iOS 7), поэтому используется tintColor — даёт
	// классический "цветной металлик". Подробности — MATheme.
	MATheme *theme = [MATheme sharedTheme];
	[theme applyAppearanceProxies];

	self.window = [[UIWindow alloc] initWithFrame:[[UIScreen mainScreen] bounds]];
	self.window.backgroundColor = theme.backgroundColor;

	// Вкладка 1: Чат
	MAChatViewController *chatVC = [[MAChatViewController alloc] init];
	UINavigationController *chatNav = [[UINavigationController alloc] initWithRootViewController:chatVC];
	chatNav.tabBarItem = [[UITabBarItem alloc] initWithTitle:@"Chat"
	                                                    image:[UIImage imageNamed:@"tab-chat"]
	                                                      tag:0];

	// Вкладка 2: История чатов
	MAChatHistoryViewController *historyVC = [[MAChatHistoryViewController alloc] init];
	UINavigationController *historyNav = [[UINavigationController alloc] initWithRootViewController:historyVC];
	historyNav.tabBarItem = [[UITabBarItem alloc] initWithTitle:MALocalizedString(@"История")
	                                                       image:[UIImage imageNamed:@"tab-history"]
	                                                         tag:1];

	// Вкладка 3: Настройки (провайдеры, ключи, кастомный URL)
	MASettingsViewController *settingsVC = [[MASettingsViewController alloc] init];
	UINavigationController *settingsNav = [[UINavigationController alloc] initWithRootViewController:settingsVC];
	settingsNav.tabBarItem = [[UITabBarItem alloc] initWithTitle:@"Settings"
	                                                        image:[UIImage imageNamed:@"tab-settings"]
	                                                          tag:2];

	self.tabBarController = [[UITabBarController alloc] init];
	self.tabBarController.viewControllers = @[chatNav, historyNav, settingsNav];
	// Цвет таб-бара и мятная подсветка активной вкладки (иконки рисуются по
	// альфа-маске: неактивная — серая, активная красится accent-цветом).
	[theme applyToTabBarController:self.tabBarController];

	self.window.rootViewController = self.tabBarController;
	[self.window makeKeyAndVisible];

	// Подпись вкладки «История» зависит от языка интерфейса.
	historyNav.tabBarItem.title = MALocalizedString(@"История");
	[[NSNotificationCenter defaultCenter] addObserver:self
	                                          selector:@selector(languageDidChange:)
	                                              name:MALanguageDidChangeNotification
	                                            object:nil];

	// Сменили тему — перекрашиваем бары (UIAppearance на уже созданные не действует).
	[[NSNotificationCenter defaultCenter] addObserver:self
	                                          selector:@selector(themeDidChange:)
	                                              name:MAThemeDidChangeNotification
	                                            object:nil];

	return YES;
}

- (void)themeDidChange:(NSNotification *)notification {
	MATheme *theme = [MATheme sharedTheme];
	self.window.backgroundColor = theme.backgroundColor;
	[theme applyToTabBarController:self.tabBarController];
}

- (void)languageDidChange:(NSNotification *)notification {
	if (self.tabBarController.viewControllers.count > 1) {
		UIViewController *historyNav = self.tabBarController.viewControllers[1];
		historyNav.tabBarItem.title = MALocalizedString(@"История");
	}
}

@end
