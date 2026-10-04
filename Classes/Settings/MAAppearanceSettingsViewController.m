#import "MAAppearanceSettingsViewController.h"
#import "MAWallpaperStore.h"
#import "MALocalization.h"
#import "MATheme.h"

static NSString *const kWallpaperCellIdentifier = @"WallpaperCell";
static NSString *const kThemeSwitchCellIdentifier = @"ThemeSwitchCell";
static const NSInteger kWallpaperSheetTag = 300;

typedef NS_ENUM(NSInteger, MAAppearanceSection) {
	MAAppearanceSectionTheme = 0,     // светлая / тёмная тема
	MAAppearanceSectionWallpaper = 1, // обои чата
	MAAppearanceSectionCount = 2,
};

@interface MAAppearanceSettingsViewController () <UIActionSheetDelegate, UIImagePickerControllerDelegate, UINavigationControllerDelegate>
@end

@implementation MAAppearanceSettingsViewController

- (instancetype)init {
	self = [super initWithStyle:UITableViewStyleGrouped];
	if (self) {
		self.title = MALocalizedString(@"Оформление");
	}
	return self;
}

+ (NSString *)summary {
	return [MATheme sharedTheme].dark ? MALocalizedString(@"Тёмная") : MALocalizedString(@"Светлая");
}

- (void)viewDidLoad {
	[super viewDidLoad];
	[[NSNotificationCenter defaultCenter] addObserver:self
	                                          selector:@selector(languageDidChange:)
	                                              name:MALanguageDidChangeNotification
	                                            object:nil];
}

- (void)dealloc {
	[[NSNotificationCenter defaultCenter] removeObserver:self];
}

- (void)languageDidChange:(NSNotification *)notification {
	self.title = MALocalizedString(@"Оформление");
	[self.tableView reloadData];
}

#pragma mark - UITableViewDataSource

- (NSInteger)numberOfSectionsInTableView:(UITableView *)tableView {
	return MAAppearanceSectionCount;
}

- (NSInteger)tableView:(UITableView *)tableView numberOfRowsInSection:(NSInteger)section {
	return 1; // секция «Тема» — переключатель, секция «Обои» — строка «Обои чата»
}

- (NSString *)tableView:(UITableView *)tableView titleForHeaderInSection:(NSInteger)section {
	return (section == MAAppearanceSectionTheme) ? MALocalizedString(@"Тема") : MALocalizedString(@"Обои");
}

- (NSString *)tableView:(UITableView *)tableView titleForFooterInSection:(NSInteger)section {
	if (section == MAAppearanceSectionTheme) {
		return MALocalizedString(@"Тёмное оформление всего приложения. Обои чата остаются как есть.");
	}
	return MALocalizedString(@"Фон вкладки «Chat». Пузыри сообщений остаются поверх него.");
}

- (UITableViewCell *)tableView:(UITableView *)tableView cellForRowAtIndexPath:(NSIndexPath *)indexPath {
	if (indexPath.section == MAAppearanceSectionTheme) {
		UITableViewCell *switchCell = [tableView dequeueReusableCellWithIdentifier:MAThemedReuseID(kThemeSwitchCellIdentifier)];
		if (!switchCell) {
			switchCell = [[UITableViewCell alloc] initWithStyle:UITableViewCellStyleDefault
			                                    reuseIdentifier:MAThemedReuseID(kThemeSwitchCellIdentifier)];
			UISwitch *toggle = [[UISwitch alloc] init];
			[toggle addTarget:self action:@selector(darkThemeSwitchChanged:) forControlEvents:UIControlEventValueChanged];
			switchCell.accessoryView = toggle;
			switchCell.selectionStyle = UITableViewCellSelectionStyleNone;
		}
		switchCell.textLabel.text = MALocalizedString(@"Тёмная тема");
		((UISwitch *)switchCell.accessoryView).on = [MATheme sharedTheme].dark;
		return switchCell;
	}

	UITableViewCell *cell = [tableView dequeueReusableCellWithIdentifier:MAThemedReuseID(kWallpaperCellIdentifier)];
	if (!cell) {
		cell = [[UITableViewCell alloc] initWithStyle:UITableViewCellStyleValue1
		                              reuseIdentifier:MAThemedReuseID(kWallpaperCellIdentifier)];
	}

	cell.textLabel.text = MALocalizedString(@"Обои чата");
	UIImage *wallpaper = [[MAWallpaperStore sharedStore] wallpaperImage];
	cell.detailTextLabel.text = wallpaper ? MALocalizedString(@"Своя картинка") : MALocalizedString(@"Стандартный фон");
	cell.accessoryType = UITableViewCellAccessoryDisclosureIndicator;
	cell.imageView.image = nil;

	if (wallpaper) {
		// Маленький квадратный превью выбранного фона слева от текста.
		CGSize thumbSize = CGSizeMake(30, 30);
		UIGraphicsBeginImageContextWithOptions(thumbSize, YES, 0.0);
		[wallpaper drawInRect:CGRectMake(0, 0, thumbSize.width, thumbSize.height)];
		UIImage *thumbnail = UIGraphicsGetImageFromCurrentImageContext();
		UIGraphicsEndImageContext();
		cell.imageView.image = thumbnail;
	}

	return cell;
}

#pragma mark - Тема

// Переключаем с небольшой задержкой: сама перерисовка таблицы прервала бы
// анимацию тумблера, а так он успевает доехать до конца.
- (void)darkThemeSwitchChanged:(UISwitch *)sender {
	BOOL dark = sender.on;
	dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(0.25 * NSEC_PER_SEC)), dispatch_get_main_queue(), ^{
		[MATheme sharedTheme].dark = dark;
	});
}

#pragma mark - Обои

- (void)presentWallpaperOptions {
	BOOL hasWallpaper = ([[MAWallpaperStore sharedStore] wallpaperImage] != nil);

	UIActionSheet *sheet = [[UIActionSheet alloc] initWithTitle:nil
	                                                     delegate:self
	                                            cancelButtonTitle:nil
	                                       destructiveButtonTitle:nil
	                                            otherButtonTitles:nil];
	sheet.tag = kWallpaperSheetTag;
	[[MATheme sharedTheme] styleActionSheet:sheet];

	[sheet addButtonWithTitle:MALocalizedString(@"Выбрать фото из галереи")];
	if ([UIImagePickerController isSourceTypeAvailable:UIImagePickerControllerSourceTypeCamera]) {
		[sheet addButtonWithTitle:MALocalizedString(@"Сделать фото")];
	}
	if (hasWallpaper) {
		sheet.destructiveButtonIndex = [sheet addButtonWithTitle:MALocalizedString(@"Сбросить на стандартный фон")];
	}
	NSInteger cancelIndex = [sheet addButtonWithTitle:MALocalizedString(@"Отмена")];
	sheet.cancelButtonIndex = cancelIndex;

	[sheet showInView:self.view];
}

- (void)presentWallpaperPickerWithSourceType:(UIImagePickerControllerSourceType)sourceType {
	UIImagePickerController *picker = [[UIImagePickerController alloc] init];
	picker.sourceType = sourceType;
	picker.delegate = self;
	picker.allowsEditing = YES; // даём подрезать/подвинуть фото под экран
	[self presentViewController:picker animated:YES completion:nil];
}

#pragma mark - UIActionSheetDelegate

- (void)actionSheet:(UIActionSheet *)actionSheet didDismissWithButtonIndex:(NSInteger)buttonIndex {
	if (actionSheet.tag != kWallpaperSheetTag || buttonIndex == actionSheet.cancelButtonIndex) return;

	if (actionSheet.destructiveButtonIndex != -1 && buttonIndex == actionSheet.destructiveButtonIndex) {
		[[MAWallpaperStore sharedStore] clearWallpaper];
		[self.tableView reloadData];
		return;
	}

	BOOL cameraAvailable = [UIImagePickerController isSourceTypeAvailable:UIImagePickerControllerSourceTypeCamera];
	if (buttonIndex == 0) {
		[self presentWallpaperPickerWithSourceType:UIImagePickerControllerSourceTypePhotoLibrary];
	} else if (buttonIndex == 1 && cameraAvailable) {
		[self presentWallpaperPickerWithSourceType:UIImagePickerControllerSourceTypeCamera];
	}
}

#pragma mark - UIImagePickerControllerDelegate

- (void)imagePickerController:(UIImagePickerController *)picker didFinishPickingMediaWithInfo:(NSDictionary *)info {
	// allowsEditing=YES отдаёт и оригинал, и обрезанный кадр — обоям нужен
	// именно EditedImage, чтобы учесть, как пользователь его подвинул/подрезал.
	UIImage *image = info[UIImagePickerControllerEditedImage] ?: info[UIImagePickerControllerOriginalImage];
	[picker dismissViewControllerAnimated:YES completion:nil];
	if (image) {
		[[MAWallpaperStore sharedStore] setWallpaperImage:image];
		[self.tableView reloadData];
	}
}

- (void)imagePickerControllerDidCancel:(UIImagePickerController *)picker {
	[picker dismissViewControllerAnimated:YES completion:nil];
}

#pragma mark - UITableViewDelegate

- (void)tableView:(UITableView *)tableView didSelectRowAtIndexPath:(NSIndexPath *)indexPath {
	[tableView deselectRowAtIndexPath:indexPath animated:YES];
	if (indexPath.section != MAAppearanceSectionWallpaper) return;
	[self presentWallpaperOptions];
}

@end
