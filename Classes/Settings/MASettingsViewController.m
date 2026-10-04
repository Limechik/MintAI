#import "MASettingsViewController.h"
#import "MAProvidersSettingsViewController.h"
#import "MAInstructionsSettingsViewController.h"
#import "MAVoiceSettingsViewController.h"
#import "MAAppearanceSettingsViewController.h"
#import "MALanguageSettingsViewController.h"
#import "MALocalization.h"
#import "MATheme.h"

static NSString *const kCategoryCellIdentifier = @"CategoryCell";

typedef NS_ENUM(NSInteger, MASettingsRootSection) {
	MASettingsRootSectionAI = 0,
	MASettingsRootSectionApp = 1,
	MASettingsRootSectionAbout = 2,
	MASettingsRootSectionCount = 3,
};

// Секция «Авторство»: строки-ссылки, открываются в Safari.
typedef NS_ENUM(NSInteger, MAAboutLink) {
	MAAboutLinkTelegram = 0,
	MAAboutLinkSourceCode = 1,
	MAAboutLinkCount = 2,
};

static NSString *const kAboutCellIdentifier = @"AboutCell";
static NSString *const kTelegramURLString = @"https://t.me/LimeDeveloper";
static NSString *const kSourceCodeURLString = @"https://github.com/Limechik/MintAI";

typedef NS_ENUM(NSInteger, MASettingsCategory) {
	MASettingsCategoryChat,
	MASettingsCategoryImages,
	MASettingsCategoryInstructions,
	MASettingsCategoryVoice,
	MASettingsCategoryAppearance,
	MASettingsCategoryLanguage,
};

// Состав и порядок секций корневого экрана.
static const MASettingsCategory kAICategories[] = {
	MASettingsCategoryChat,
	MASettingsCategoryImages,
	MASettingsCategoryInstructions,
};
static const MASettingsCategory kAppCategories[] = {
	MASettingsCategoryVoice,
	MASettingsCategoryAppearance,
	MASettingsCategoryLanguage,
};

#define MA_COUNT_OF(array) ((NSInteger)(sizeof(array) / sizeof((array)[0])))

#pragma mark - Иконки категорий

// Квадратная иконка 29x29 со скруглением и мягким вертикальным градиентом, как в
// системных настройках iOS 6. Внутри — эмодзи (Apple Color Emoji есть с iOS 5).
static UIImage *MASettingsIconImage(NSString *glyph, UIColor *color) {
	static NSMutableDictionary *cache;
	if (!cache) cache = [NSMutableDictionary dictionary];
	UIImage *cached = cache[glyph];
	if (cached) return cached;

	CGSize size = CGSizeMake(29, 29);
	UIGraphicsBeginImageContextWithOptions(size, NO, 0.0);
	CGContextRef context = UIGraphicsGetCurrentContext();

	CGContextSaveGState(context);
	[[UIBezierPath bezierPathWithRoundedRect:CGRectMake(0, 0, size.width, size.height) cornerRadius:6.5] addClip];

	CGFloat red = 0, green = 0, blue = 0, alpha = 0;
	[color getRed:&red green:&green blue:&blue alpha:&alpha];
	CGFloat components[8] = {
		MIN(1.0, red + 0.12), MIN(1.0, green + 0.12), MIN(1.0, blue + 0.12), 1.0, // верх — светлее
		MAX(0.0, red - 0.08), MAX(0.0, green - 0.08), MAX(0.0, blue - 0.08), 1.0, // низ — темнее
	};
	CGColorSpaceRef colorSpace = CGColorSpaceCreateDeviceRGB();
	CGGradientRef gradient = CGGradientCreateWithColorComponents(colorSpace, components, NULL, 2);
	CGContextDrawLinearGradient(context, gradient, CGPointMake(0, 0), CGPointMake(0, size.height), 0);
	CGGradientRelease(gradient);
	CGColorSpaceRelease(colorSpace);
	CGContextRestoreGState(context);

	UIFont *font = [UIFont systemFontOfSize:16];
	CGSize glyphSize = [glyph sizeWithFont:font];
	[glyph drawAtPoint:CGPointMake(floorf((size.width - glyphSize.width) / 2.0f),
	                               floorf((size.height - glyphSize.height) / 2.0f))
	          withFont:font];

	UIImage *image = UIGraphicsGetImageFromCurrentImageContext();
	UIGraphicsEndImageContext();
	cache[glyph] = image;
	return image;
}

static UIColor *MASettingsColor(CGFloat red, CGFloat green, CGFloat blue) {
	return [UIColor colorWithRed:red / 255.0 green:green / 255.0 blue:blue / 255.0 alpha:1.0];
}

@implementation MASettingsViewController

- (instancetype)init {
	self = [super initWithStyle:UITableViewStyleGrouped];
	return self;
}

- (void)viewDidLoad {
	[super viewDidLoad];
	self.title = @"Settings";

	// Сменили язык — перерисовываем все подписи на экране.
	[[NSNotificationCenter defaultCenter] addObserver:self
	                                          selector:@selector(languageDidChange:)
	                                              name:MALanguageDidChangeNotification
	                                            object:nil];
}

- (void)dealloc {
	[[NSNotificationCenter defaultCenter] removeObserver:self];
}

- (void)languageDidChange:(NSNotification *)notification {
	[self.tableView reloadData];
}

- (void)viewWillAppear:(BOOL)animated {
	[super viewWillAppear:animated];
	// Сводки (активный провайдер, обои, инструкция…) могли поменяться на экране категории.
	[self.tableView reloadData];
}

#pragma mark - Категории

- (MASettingsCategory)categoryAtIndexPath:(NSIndexPath *)indexPath {
	return (indexPath.section == MASettingsRootSectionAI) ? kAICategories[indexPath.row] : kAppCategories[indexPath.row];
}

- (NSString *)titleForCategory:(MASettingsCategory)category {
	switch (category) {
		case MASettingsCategoryChat:         return MALocalizedString(@"Чат");
		case MASettingsCategoryImages:       return MALocalizedString(@"Изображения");
		case MASettingsCategoryInstructions: return MALocalizedString(@"Инструкция");
		case MASettingsCategoryVoice:        return MALocalizedString(@"Голос");
		case MASettingsCategoryAppearance:   return MALocalizedString(@"Оформление");
		case MASettingsCategoryLanguage:     return @"Язык / Language"; // намеренно двуязычный и не переводится — чтобы его всегда можно было найти
	}
	return nil;
}

- (NSString *)summaryForCategory:(MASettingsCategory)category {
	switch (category) {
		case MASettingsCategoryChat:         return [MAProvidersSettingsViewController summaryForKind:MAProvidersKindChat];
		case MASettingsCategoryImages:       return [MAProvidersSettingsViewController summaryForKind:MAProvidersKindImage];
		case MASettingsCategoryInstructions: return [MAInstructionsSettingsViewController summary];
		case MASettingsCategoryVoice:        return [MAVoiceSettingsViewController summary];
		case MASettingsCategoryAppearance:   return [MAAppearanceSettingsViewController summary];
		case MASettingsCategoryLanguage:     return [MALanguageSettingsViewController summary];
	}
	return nil;
}

- (UIImage *)iconForCategory:(MASettingsCategory)category {
	switch (category) {
		case MASettingsCategoryChat:         return MASettingsIconImage(@"💬", MASettingsColor(62, 180, 137));  // мятный — цвет бренда
		case MASettingsCategoryImages:       return MASettingsIconImage(@"🎨", MASettingsColor(155, 89, 182));
		case MASettingsCategoryInstructions: return MASettingsIconImage(@"📝", MASettingsColor(243, 156, 18));
		case MASettingsCategoryVoice:        return MASettingsIconImage(@"🔊", MASettingsColor(52, 152, 219));
		case MASettingsCategoryAppearance:   return MASettingsIconImage(@"🖼", MASettingsColor(231, 84, 128));
		case MASettingsCategoryLanguage:     return MASettingsIconImage(@"🌐", MASettingsColor(110, 125, 140));
	}
	return nil;
}

- (UIViewController *)viewControllerForCategory:(MASettingsCategory)category {
	switch (category) {
		case MASettingsCategoryChat:         return [[MAProvidersSettingsViewController alloc] initWithKind:MAProvidersKindChat];
		case MASettingsCategoryImages:       return [[MAProvidersSettingsViewController alloc] initWithKind:MAProvidersKindImage];
		case MASettingsCategoryInstructions: return [[MAInstructionsSettingsViewController alloc] init];
		case MASettingsCategoryVoice:        return [[MAVoiceSettingsViewController alloc] init];
		case MASettingsCategoryAppearance:   return [[MAAppearanceSettingsViewController alloc] init];
		case MASettingsCategoryLanguage:     return [[MALanguageSettingsViewController alloc] init];
	}
	return nil;
}

#pragma mark - Авторство

- (NSString *)titleForAboutLink:(MAAboutLink)link {
	// Названия — имена собственные, не переводятся.
	return (link == MAAboutLinkTelegram) ? @"Telegram" : @"Source Code";
}

- (NSString *)detailForAboutLink:(MAAboutLink)link {
	return (link == MAAboutLinkTelegram) ? @"@LimeDeveloper" : @"Limechik/MintAI";
}

- (UIImage *)iconForAboutLink:(MAAboutLink)link {
	// 29x29 (@2x — 58x58) с белой плиткой и скруглением, чтобы чёрный логотип GitHub
	// был виден и в тёмной теме. Подхватывается из Resources.
	return [UIImage imageNamed:(link == MAAboutLinkTelegram) ? @"settingsTelegram.png" : @"settingsGitHub.png"];
}

- (NSURL *)URLForAboutLink:(MAAboutLink)link {
	return [NSURL URLWithString:(link == MAAboutLinkTelegram) ? kTelegramURLString : kSourceCodeURLString];
}

#pragma mark - UITableViewDataSource

- (NSInteger)numberOfSectionsInTableView:(UITableView *)tableView {
	return MASettingsRootSectionCount;
}

- (NSInteger)tableView:(UITableView *)tableView numberOfRowsInSection:(NSInteger)section {
	if (section == MASettingsRootSectionAbout) return MAAboutLinkCount;
	return (section == MASettingsRootSectionAI) ? MA_COUNT_OF(kAICategories) : MA_COUNT_OF(kAppCategories);
}

- (NSString *)tableView:(UITableView *)tableView titleForHeaderInSection:(NSInteger)section {
	if (section == MASettingsRootSectionAbout) return MALocalizedString(@"Автор");
	return (section == MASettingsRootSectionAI) ? MALocalizedString(@"ИИ") : MALocalizedString(@"Приложение");
}

- (UITableViewCell *)tableView:(UITableView *)tableView cellForRowAtIndexPath:(NSIndexPath *)indexPath {
	if (indexPath.section == MASettingsRootSectionAbout) {
		UITableViewCell *aboutCell = [tableView dequeueReusableCellWithIdentifier:MAThemedReuseID(kAboutCellIdentifier)];
		if (!aboutCell) {
			aboutCell = [[UITableViewCell alloc] initWithStyle:UITableViewCellStyleValue1
			                                   reuseIdentifier:MAThemedReuseID(kAboutCellIdentifier)];
			aboutCell.accessoryType = UITableViewCellAccessoryNone;
		}
		MAAboutLink link = (MAAboutLink)indexPath.row;
		aboutCell.imageView.image = [self iconForAboutLink:link];
		aboutCell.textLabel.text = [self titleForAboutLink:link];
		aboutCell.detailTextLabel.text = [self detailForAboutLink:link];
		return aboutCell;
	}

	UITableViewCell *cell = [tableView dequeueReusableCellWithIdentifier:MAThemedReuseID(kCategoryCellIdentifier)];
	if (!cell) {
		cell = [[UITableViewCell alloc] initWithStyle:UITableViewCellStyleValue1
		                              reuseIdentifier:MAThemedReuseID(kCategoryCellIdentifier)];
		cell.accessoryType = UITableViewCellAccessoryDisclosureIndicator;
	}

	MASettingsCategory category = [self categoryAtIndexPath:indexPath];
	cell.imageView.image = [self iconForCategory:category];
	cell.textLabel.text = [self titleForCategory:category];
	cell.detailTextLabel.text = [self summaryForCategory:category];
	return cell;
}

#pragma mark - UITableViewDelegate

- (void)tableView:(UITableView *)tableView didSelectRowAtIndexPath:(NSIndexPath *)indexPath {
	[tableView deselectRowAtIndexPath:indexPath animated:YES];
	if (indexPath.section == MASettingsRootSectionAbout) {
		[[UIApplication sharedApplication] openURL:[self URLForAboutLink:(MAAboutLink)indexPath.row]];
		return;
	}
	UIViewController *controller = [self viewControllerForCategory:[self categoryAtIndexPath:indexPath]];
	if (controller) {
		[self.navigationController pushViewController:controller animated:YES];
	}
}

@end
