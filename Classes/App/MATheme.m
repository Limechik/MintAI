#import "MATheme.h"

NSString *const MAThemeDidChangeNotification = @"MAThemeDidChangeNotification";

static NSString *const kThemeDarkDefaultsKey = @"MAInterfaceThemeDark";

static UIColor *MAWhite(CGFloat white) {
	return [UIColor colorWithWhite:white alpha:1.0];
}

static UIColor *MARGB(CGFloat red, CGFloat green, CGFloat blue) {
	return [UIColor colorWithRed:red / 255.0 green:green / 255.0 blue:blue / 255.0 alpha:1.0];
}

@implementation MATheme

+ (instancetype)sharedTheme {
	static MATheme *shared = nil;
	static dispatch_once_t onceToken;
	dispatch_once(&onceToken, ^{
		shared = [[MATheme alloc] init];
	});
	return shared;
}

- (BOOL)isDark {
	return [[NSUserDefaults standardUserDefaults] boolForKey:kThemeDarkDefaultsKey];
}

- (void)setDark:(BOOL)dark {
	if (dark == self.dark) return;

	NSUserDefaults *defaults = [NSUserDefaults standardUserDefaults];
	[defaults setBool:dark forKey:kThemeDarkDefaultsKey];
	[defaults synchronize];

	[self applyAppearanceProxies];
	[[NSNotificationCenter defaultCenter] postNotificationName:MAThemeDidChangeNotification object:self];
}

#pragma mark - Цвета (светлая → прежние значения приложения)

- (UIColor *)accentColor {
	return MARGB(62, 180, 137);
}

- (UIColor *)actionColor {
	return self.dark ? MARGB(89, 201, 156) : [UIColor colorWithRed:0.0 green:0.48 blue:1.0 alpha:1.0];
}

- (UIColor *)navigationBarTintColor {
	return self.dark ? MAWhite(0.16) : self.accentColor;
}

- (UIColor *)backgroundColor {
	return self.dark ? MAWhite(0.08) : [UIColor whiteColor];
}

- (UIColor *)groupedBackgroundColor {
	return self.dark ? MAWhite(0.08) : [UIColor groupTableViewBackgroundColor];
}

- (UIColor *)cellBackgroundColor {
	return self.dark ? MAWhite(0.14) : [UIColor whiteColor];
}

- (UIColor *)cellSelectedColor {
	return self.dark ? MAWhite(0.24) : MAWhite(0.85);
}

- (UIColor *)separatorColor {
	return self.dark ? MAWhite(0.27) : MAWhite(0.67);
}

- (UIColor *)primaryTextColor {
	return self.dark ? MAWhite(0.95) : [UIColor blackColor];
}

- (UIColor *)secondaryTextColor {
	return self.dark ? MAWhite(0.62) : MAWhite(0.5);
}

- (UIColor *)placeholderTextColor {
	return self.dark ? MAWhite(0.42) : MAWhite(0.7);
}

- (UIColor *)groupedHeaderTextColor {
	return self.dark ? MAWhite(0.62) : MARGB(76, 86, 108); // как у штатных подписей grouped-таблицы iOS 6
}

- (UIColor *)groupedHeaderShadowColor {
	return self.dark ? [UIColor clearColor] : [UIColor whiteColor];
}

- (UIColor *)inputBarColor {
	return self.dark ? MAWhite(0.13) : MAWhite(0.95);
}

- (UIColor *)inputBarBorderColor {
	return self.dark ? MAWhite(0.25) : MAWhite(0.8);
}

- (UIColor *)thumbnailPlaceholderColor {
	return self.dark ? MAWhite(0.22) : MAWhite(0.85);
}

- (UIKeyboardAppearance)keyboardAppearance {
	return self.dark ? UIKeyboardAppearanceAlert : UIKeyboardAppearanceDefault; // «Alert» — тёмная клавиатура iOS 6
}

#pragma mark - Помощники

- (NSString *)reuseIdentifierWithBase:(NSString *)base {
	return self.dark ? [base stringByAppendingString:@"-dark"] : base;
}

- (void)styleActionSheet:(UIActionSheet *)sheet {
	if (self.dark) sheet.actionSheetStyle = UIActionSheetStyleBlackOpaque;
}

- (void)applyAppearanceProxies {
	// В iOS 6 у UINavigationBar нет barTintColor (он появился в iOS 7) — красим tintColor.
	[[UINavigationBar appearance] setTintColor:self.navigationBarTintColor];
}

- (void)applyToTabBarController:(UITabBarController *)tabBarController {
	UITabBar *tabBar = tabBarController.tabBar;
	tabBar.tintColor = self.dark ? MAWhite(0.16) : nil;
	// iOS 5/6 рисует иконки таб-бара по альфа-маске: выбранная красится в этот цвет.
	tabBar.selectedImageTintColor = self.accentColor;

	for (UIViewController *controller in tabBarController.viewControllers) {
		if ([controller isKindOfClass:[UINavigationController class]]) {
			((UINavigationController *)controller).navigationBar.tintColor = self.navigationBarTintColor;
		}
	}
}

@end
