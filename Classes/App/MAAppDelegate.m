#import "MAAppDelegate.h"
#import "../Chat/MAChatViewController.h"
#import "../Settings/MASettingsViewController.h"
#import "../History/MAChatHistoryViewController.h"
#import "../Lock/MAAppLock.h"
#import "../Crypto/MAVault.h"
#import "../Providers/MAKeychain.h"
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

	// Подпись вкладки «История» зависит от языка интерфейса.
	[[NSNotificationCenter defaultCenter] addObserver:self
	                                          selector:@selector(languageDidChange:)
	                                              name:MALanguageDidChangeNotification
	                                            object:nil];

	// Сменили тему — перекрашиваем бары (UIAppearance на уже созданные не действует).
	[[NSNotificationCenter defaultCenter] addObserver:self
	                                          selector:@selector(themeDidChange:)
	                                              name:MAThemeDidChangeNotification
	                                            object:nil];

	// Ключ шифрования истории и API-ключей. Без PIN он достаётся из Keychain сразу.
	[[MAVault sharedVault] prepareAtLaunch];

	if ([MAAppLock sharedLock].enabled && ![MAVault sharedVault].unlocked) {
		// Ключ упакован PIN-кодом, поэтому историю и API-ключи пока не прочитать.
		// Интерфейс (а с ним история, провайдеры и ключи) создаём только после
		// ввода PIN; пока под экраном блокировки пустой фон.
		UIViewController *placeholder = [[UIViewController alloc] init];
		placeholder.view.backgroundColor = theme.backgroundColor;
		self.window.rootViewController = placeholder;
		[[NSNotificationCenter defaultCenter] addObserver:self
		                                          selector:@selector(appLockDidUnlock:)
		                                              name:MAAppLockDidUnlockNotification
		                                            object:nil];
	} else {
		[self buildInterfaceIfNeeded];
	}
	[self.window makeKeyAndVisible];

	// Если задан PIN-код — закрываем приложение экраном блокировки до ввода.
	[[MAAppLock sharedLock] applicationDidFinishLaunching];

	return YES;
}

// Создаёт вкладки приложения. Все синглтоны с данными (история, провайдеры,
// ключи) оживают только здесь, то есть уже после открытия хранилища.
- (void)buildInterfaceIfNeeded {
	if (self.tabBarController) return;

	MATheme *theme = [MATheme sharedTheme];

	// Ключи, сохранённые старой версией открытым текстом, шифруем сразу.
	[MAKeychain encryptLegacyItems];

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
}

// Верный PIN на холодном запуске: хранилище открыто, можно строить интерфейс.
- (void)appLockDidUnlock:(NSNotification *)notification {
	[[NSNotificationCenter defaultCenter] removeObserver:self name:MAAppLockDidUnlockNotification object:nil];
	[self buildInterfaceIfNeeded];
}

#pragma mark - Блокировка PIN-кодом

- (void)applicationWillResignActive:(UIApplication *)application {
	[[MAAppLock sharedLock] applicationWillResignActive];
}

- (void)applicationDidEnterBackground:(UIApplication *)application {
	[[MAAppLock sharedLock] applicationDidEnterBackground];
}

- (void)applicationDidBecomeActive:(UIApplication *)application {
	[[MAAppLock sharedLock] applicationDidBecomeActive];
}

- (void)themeDidChange:(NSNotification *)notification {
	MATheme *theme = [MATheme sharedTheme];
	self.window.backgroundColor = theme.backgroundColor;
	if (self.tabBarController) [theme applyToTabBarController:self.tabBarController];
}

- (void)languageDidChange:(NSNotification *)notification {
	if (self.tabBarController.viewControllers.count > 1) {
		UIViewController *historyNav = self.tabBarController.viewControllers[1];
		historyNav.tabBarItem.title = MALocalizedString(@"История");
	}
}

@end
