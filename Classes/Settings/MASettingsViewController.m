#import "MASettingsViewController.h"
#import "MAProvidersSettingsViewController.h"
#import "MAInstructionsSettingsViewController.h"
#import "MAVoiceSettingsViewController.h"
#import "MAAppearanceSettingsViewController.h"
#import "MALanguageSettingsViewController.h"
#import "MAPrivacySettings.h"
#import "MAAppLock.h"
#import "MAPINViewController.h"
#import "MAVault.h"
#import "MALocalization.h"
#import "MATheme.h"

static NSString *const kCategoryCellIdentifier = @"CategoryCell";

typedef NS_ENUM(NSInteger, MASettingsRootSection) {
	MASettingsRootSectionAI = 0,
	MASettingsRootSectionApp = 1,
	MASettingsRootSectionPrivacy = 2,
	MASettingsRootSectionAbout = 3,
	MASettingsRootSectionCount = 4,
};

// Секция «Авторство»: строки-ссылки, открываются в Safari.
typedef NS_ENUM(NSInteger, MAAboutLink) {
	MAAboutLinkTelegram = 0,
	MAAboutLinkSourceCode = 1,
	MAAboutLinkCount = 2,
};

static NSString *const kAboutCellIdentifier = @"AboutCell";
static NSString *const kPrivacyCellIdentifier = @"PrivacyCell";
static NSString *const kPINSwitchCellIdentifier = @"PINSwitchCell";
static NSString *const kPINRowCellIdentifier = @"PINRowCell";
static NSString *const kEncryptionCellIdentifier = @"EncryptionCell";

// Строки секции «Приватность». Две последние есть только при включённом PIN-коде.
typedef NS_ENUM(NSInteger, MAPrivacyRow) {
	MAPrivacyRowIncognito = 0,
	MAPrivacyRowPINLock = 1,
	MAPrivacyRowChangePIN = 2,
	MAPrivacyRowAutoLock = 3,
	MAPrivacyRowEncryption = 4, // «Шифрование данных»: только показывает состояние
};

static const NSInteger kAutoLockSheetTag = 500;
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

@interface MASettingsViewController () <UIActionSheetDelegate>
@end

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
	if (section == MASettingsRootSectionPrivacy) return (NSInteger)[self privacyRows].count;
	return (section == MASettingsRootSectionAI) ? MA_COUNT_OF(kAICategories) : MA_COUNT_OF(kAppCategories);
}

- (NSString *)tableView:(UITableView *)tableView titleForHeaderInSection:(NSInteger)section {
	if (section == MASettingsRootSectionAbout) return MALocalizedString(@"Автор");
	if (section == MASettingsRootSectionPrivacy) return MALocalizedString(@"Приватность");
	return (section == MASettingsRootSectionAI) ? MALocalizedString(@"ИИ") : MALocalizedString(@"Приложение");
}

- (NSString *)tableView:(UITableView *)tableView titleForFooterInSection:(NSInteger)section {
	if (section != MASettingsRootSectionPrivacy) return nil;
	return [NSString stringWithFormat:@"%@\n\n%@\n\n%@",
	        MALocalizedString(@"В режиме инкогнито новые беседы не сохраняются в историю. Уже сохранённые беседы остаются на месте. Запросы по-прежнему отправляются выбранному провайдеру."),
	        MALocalizedString(@"PIN-код закрывает вход в приложение и защищает ключ шифрования. Короткий PIN можно подобрать, а если вы его забудете, восстановить данные не получится: придётся переустановить приложение."),
	        MALocalizedString(@"История чатов и API-ключи шифруются алгоритмом AES-256.")];
}

- (UITableViewCell *)tableView:(UITableView *)tableView cellForRowAtIndexPath:(NSIndexPath *)indexPath {
	if (indexPath.section == MASettingsRootSectionPrivacy && [self privacyRowAtIndexPath:indexPath] != MAPrivacyRowIncognito) {
		return [self pinCellForTableView:tableView row:[self privacyRowAtIndexPath:indexPath]];
	}

	if (indexPath.section == MASettingsRootSectionPrivacy) {
		UITableViewCell *privacyCell = [tableView dequeueReusableCellWithIdentifier:MAThemedReuseID(kPrivacyCellIdentifier)];
		if (!privacyCell) {
			privacyCell = [[UITableViewCell alloc] initWithStyle:UITableViewCellStyleDefault
			                                     reuseIdentifier:MAThemedReuseID(kPrivacyCellIdentifier)];
			privacyCell.selectionStyle = UITableViewCellSelectionStyleNone;
			UISwitch *toggle = [[UISwitch alloc] init];
			[toggle addTarget:self action:@selector(incognitoSwitchChanged:) forControlEvents:UIControlEventValueChanged];
			privacyCell.accessoryView = toggle;
		}
		privacyCell.imageView.image = MASettingsIconImage(@"🕶", MASettingsColor(70, 78, 92));
		privacyCell.textLabel.text = MALocalizedString(@"Режим инкогнито");
		((UISwitch *)privacyCell.accessoryView).on = [MAPrivacySettings sharedSettings].incognito;
		return privacyCell;
	}

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

- (void)incognitoSwitchChanged:(UISwitch *)sender {
	[MAPrivacySettings sharedSettings].incognito = sender.on;
}

#pragma mark - Блокировка PIN-кодом

// Какие строки сейчас в секции «Приватность», по порядку. «Сменить PIN-код» и
// «Запрашивать PIN-код» есть только при включённой блокировке.
- (NSArray *)privacyRows {
	NSMutableArray *rows = [NSMutableArray arrayWithObjects:@(MAPrivacyRowIncognito), @(MAPrivacyRowPINLock), nil];
	if ([MAAppLock sharedLock].enabled) {
		[rows addObject:@(MAPrivacyRowChangePIN)];
		[rows addObject:@(MAPrivacyRowAutoLock)];
	}
	[rows addObject:@(MAPrivacyRowEncryption)];
	return rows;
}

- (NSInteger)privacyRowAtIndexPath:(NSIndexPath *)indexPath {
	NSArray *rows = [self privacyRows];
	if (indexPath.row < 0 || indexPath.row >= (NSInteger)rows.count) return MAPrivacyRowIncognito;
	return [rows[indexPath.row] integerValue];
}

- (UITableViewCell *)pinCellForTableView:(UITableView *)tableView row:(NSInteger)row {
	MAAppLock *lock = [MAAppLock sharedLock];

	if (row == MAPrivacyRowPINLock) {
		UITableViewCell *cell = [tableView dequeueReusableCellWithIdentifier:MAThemedReuseID(kPINSwitchCellIdentifier)];
		if (!cell) {
			cell = [[UITableViewCell alloc] initWithStyle:UITableViewCellStyleDefault
			                              reuseIdentifier:MAThemedReuseID(kPINSwitchCellIdentifier)];
			cell.selectionStyle = UITableViewCellSelectionStyleNone;
			UISwitch *toggle = [[UISwitch alloc] init];
			[toggle addTarget:self action:@selector(pinLockSwitchChanged:) forControlEvents:UIControlEventValueChanged];
			cell.accessoryView = toggle;
		}
		cell.imageView.image = MASettingsIconImage(@"🔒", MASettingsColor(214, 78, 67));
		cell.textLabel.text = MALocalizedString(@"Блокировка PIN-кодом");
		((UISwitch *)cell.accessoryView).on = lock.enabled;
		return cell;
	}

	if (row == MAPrivacyRowEncryption) {
		UITableViewCell *cell = [tableView dequeueReusableCellWithIdentifier:MAThemedReuseID(kEncryptionCellIdentifier)];
		if (!cell) {
			cell = [[UITableViewCell alloc] initWithStyle:UITableViewCellStyleValue1
			                              reuseIdentifier:MAThemedReuseID(kEncryptionCellIdentifier)];
			cell.selectionStyle = UITableViewCellSelectionStyleNone;
		}
		cell.textLabel.text = MALocalizedString(@"Шифрование данных");
		cell.detailTextLabel.text = [MAVault sharedVault].unavailable ? MALocalizedString(@"Недоступно") : @"AES-256";
		return cell;
	}

	UITableViewCell *cell = [tableView dequeueReusableCellWithIdentifier:MAThemedReuseID(kPINRowCellIdentifier)];
	if (!cell) {
		cell = [[UITableViewCell alloc] initWithStyle:UITableViewCellStyleValue1
		                              reuseIdentifier:MAThemedReuseID(kPINRowCellIdentifier)];
		cell.accessoryType = UITableViewCellAccessoryDisclosureIndicator;
	}
	if (row == MAPrivacyRowChangePIN) {
		cell.textLabel.text = MALocalizedString(@"Сменить PIN-код");
		cell.detailTextLabel.text = nil;
	} else {
		cell.textLabel.text = MALocalizedString(@"Запрашивать PIN-код");
		cell.detailTextLabel.text = [lock autoLockSummary];
	}
	return cell;
}

- (void)reloadPrivacySection {
	[self.tableView reloadSections:[NSIndexSet indexSetWithIndex:MASettingsRootSectionPrivacy]
	              withRowAnimation:UITableViewRowAnimationFade];
}

// Показывает экран ввода PIN-кода. По завершении закрывает его и обновляет секцию
// (при отмене заодно возвращает переключатель в прежнее положение).
- (void)presentPINControllerWithMode:(MAPINMode)mode onSuccess:(void (^)(NSString *pin))onSuccess {
	MAPINViewController *controller = [[MAPINViewController alloc] initWithMode:mode];
	__weak typeof(self) weakSelf = self;
	__weak typeof(controller) weakController = controller;
	controller.completion = ^(BOOL success, NSString *pin) {
		if (success && onSuccess) onSuccess(pin);
		[weakController teardown];
		[weakSelf dismissViewControllerAnimated:YES completion:nil];
		[weakSelf reloadPrivacySection];
	};
	controller.modalPresentationStyle = UIModalPresentationFullScreen;
	[self presentViewController:controller animated:YES completion:nil];
}

- (void)pinLockSwitchChanged:(UISwitch *)sender {
	MAAppLock *lock = [MAAppLock sharedLock];
	if (sender.on) {
		[self presentPINControllerWithMode:MAPINModeCreate onSuccess:^(NSString *pin) {
			[lock setPIN:pin];
		}];
	} else {
		// Чтобы выключить блокировку, нужно подтвердить текущий PIN.
		[self presentPINControllerWithMode:MAPINModeVerify onSuccess:^(NSString *pin) {
			[lock removePIN];
		}];
	}
}

- (void)presentAutoLockOptions {
	UIActionSheet *sheet = [[UIActionSheet alloc] initWithTitle:MALocalizedString(@"Запрашивать PIN-код")
	                                                     delegate:self
	                                            cancelButtonTitle:nil
	                                       destructiveButtonTitle:nil
	                                            otherButtonTitles:nil];
	sheet.tag = kAutoLockSheetTag;
	[[MATheme sharedTheme] styleActionSheet:sheet];
	for (NSInteger i = 0; i < [MAAppLock autoLockOptionCount]; i++) {
		[sheet addButtonWithTitle:[MAAppLock autoLockTitleAtIndex:i]];
	}
	sheet.cancelButtonIndex = [sheet addButtonWithTitle:MALocalizedString(@"Отмена")];
	[sheet showInView:self.view];
}

#pragma mark - UIActionSheetDelegate

- (void)actionSheet:(UIActionSheet *)actionSheet didDismissWithButtonIndex:(NSInteger)buttonIndex {
	if (actionSheet.tag != kAutoLockSheetTag) return;
	if (buttonIndex < 0 || buttonIndex == actionSheet.cancelButtonIndex) return;
	if (buttonIndex >= [MAAppLock autoLockOptionCount]) return;

	[MAAppLock sharedLock].autoLockDelay = [MAAppLock autoLockDelayAtIndex:buttonIndex];
	[self reloadPrivacySection];
}

#pragma mark - UITableViewDelegate

- (void)tableView:(UITableView *)tableView didSelectRowAtIndexPath:(NSIndexPath *)indexPath {
	[tableView deselectRowAtIndexPath:indexPath animated:YES];
	if (indexPath.section == MASettingsRootSectionPrivacy) {
		NSInteger privacyRow = [self privacyRowAtIndexPath:indexPath];
		if (privacyRow == MAPrivacyRowChangePIN) {
			[self presentPINControllerWithMode:MAPINModeChange onSuccess:^(NSString *pin) {
				[[MAAppLock sharedLock] setPIN:pin];
			}];
		} else if (privacyRow == MAPrivacyRowAutoLock) {
			[self presentAutoLockOptions];
		}
		return; // у строк-переключателей нажатие обрабатывает сам переключатель
	}
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
