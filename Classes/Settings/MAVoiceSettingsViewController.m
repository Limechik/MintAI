#import "MAVoiceSettingsViewController.h"
#import "MAVoiceService.h"
#import "MALocalization.h"
#import "MATheme.h"

static NSString *const kVoiceCellIdentifier = @"VoiceCell";
static NSString *const kVoiceSwitchCellIdentifier = @"VoiceSwitchCell";

typedef NS_ENUM(NSInteger, MASpeechRow) {
	MASpeechRowAutoSpeak = 0,
	MASpeechRowStyle = 1,
	MASpeechRowRate = 2,
	MASpeechRowTest = 3,
	MASpeechRowCount = 4,
};

static const NSInteger kStyleSheetTag = 400;
static const NSInteger kRateSheetTag = 401;

static NSString *const kVoiceStyleTitles[] = { @"Стандартный", @"Мужской", @"Женский" };
static const NSInteger kVoiceStyleCount = 3;
static NSString *const kSpeechRateTitles[] = { @"Медленно", @"Обычно", @"Быстро" };
static const NSInteger kSpeechRateValues[] = { 140, 170, 210 };
static const NSInteger kSpeechRateCount = 3;

@interface MAVoiceSettingsViewController () <UIActionSheetDelegate>
@end

@implementation MAVoiceSettingsViewController

- (instancetype)init {
	self = [super initWithStyle:UITableViewStyleGrouped];
	if (self) {
		self.title = MALocalizedString(@"Голос");
	}
	return self;
}

+ (NSString *)summary {
	NSInteger style = MAX(0, MIN([MAVoiceService sharedService].voiceStyle, kVoiceStyleCount - 1));
	return MALocalizedString(kVoiceStyleTitles[style]);
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
	self.title = MALocalizedString(@"Голос");
	[self.tableView reloadData];
}

- (void)viewWillAppear:(BOOL)animated {
	[super viewWillAppear:animated];
	[self.tableView reloadData];
}

#pragma mark - UITableViewDataSource

- (NSInteger)numberOfSectionsInTableView:(UITableView *)tableView {
	return 1;
}

- (NSInteger)tableView:(UITableView *)tableView numberOfRowsInSection:(NSInteger)section {
	return MASpeechRowCount;
}

- (NSString *)tableView:(UITableView *)tableView titleForHeaderInSection:(NSInteger)section {
	return MALocalizedString(@"Озвучка ответов");
}

- (NSString *)tableView:(UITableView *)tableView titleForFooterInSection:(NSInteger)section {
	return MALocalizedString(@"Ответы озвучивает встроенный синтезатор VoxSynth: русская речь, цифры читаются словами, латиница — транслитом. Работает без сервера, ключей и интернета; голос заметно роботизированный.");
}

- (UITableViewCell *)tableView:(UITableView *)tableView cellForRowAtIndexPath:(NSIndexPath *)indexPath {
	return [self speechCellForTableView:tableView row:indexPath.row];
}

- (UITableViewCell *)speechCellForTableView:(UITableView *)tableView row:(NSInteger)row {
	MAVoiceService *voice = [MAVoiceService sharedService];

	if (row == MASpeechRowAutoSpeak) {
		UITableViewCell *cell = [tableView dequeueReusableCellWithIdentifier:MAThemedReuseID(kVoiceSwitchCellIdentifier)];
		if (!cell) {
			cell = [[UITableViewCell alloc] initWithStyle:UITableViewCellStyleDefault
			                              reuseIdentifier:MAThemedReuseID(kVoiceSwitchCellIdentifier)];
			UISwitch *toggle = [[UISwitch alloc] init];
			[toggle addTarget:self action:@selector(autoSpeakSwitchChanged:) forControlEvents:UIControlEventValueChanged];
			cell.accessoryView = toggle;
			cell.selectionStyle = UITableViewCellSelectionStyleNone;
		}
		cell.textLabel.text = MALocalizedString(@"Озвучивать все ответы");
		((UISwitch *)cell.accessoryView).on = voice.autoSpeak;
		return cell;
	}

	UITableViewCell *cell = [tableView dequeueReusableCellWithIdentifier:MAThemedReuseID(kVoiceCellIdentifier)];
	if (!cell) {
		cell = [[UITableViewCell alloc] initWithStyle:UITableViewCellStyleSubtitle
		                              reuseIdentifier:MAThemedReuseID(kVoiceCellIdentifier)];
	}

	cell.selectionStyle = UITableViewCellSelectionStyleBlue;
	if (row == MASpeechRowStyle) {
		cell.textLabel.text = MALocalizedString(@"Голос");
		cell.detailTextLabel.text = [[self class] summary];
		cell.accessoryType = UITableViewCellAccessoryDisclosureIndicator;
	} else if (row == MASpeechRowRate) {
		cell.textLabel.text = MALocalizedString(@"Скорость речи");
		NSString *rateTitle = MALocalizedString(@"Обычно");
		for (NSInteger i = 0; i < kSpeechRateCount; i++) {
			if (voice.speechRate == kSpeechRateValues[i]) rateTitle = MALocalizedString(kSpeechRateTitles[i]);
		}
		cell.detailTextLabel.text = rateTitle;
		cell.accessoryType = UITableViewCellAccessoryDisclosureIndicator;
	} else {
		cell.textLabel.text = MALocalizedString(@"Проверить озвучку");
		cell.detailTextLabel.text = MALocalizedString(@"Встроенный синтезатор VoxSynth");
		cell.accessoryType = UITableViewCellAccessoryNone;
	}
	return cell;
}

- (void)autoSpeakSwitchChanged:(UISwitch *)sender {
	[MAVoiceService sharedService].autoSpeak = sender.on;
}

#pragma mark - Действия

- (void)presentOptionsWithTag:(NSInteger)tag title:(NSString *)title options:(NSString *const *)options count:(NSInteger)count {
	UIActionSheet *sheet = [[UIActionSheet alloc] initWithTitle:title
	                                                     delegate:self
	                                            cancelButtonTitle:nil
	                                       destructiveButtonTitle:nil
	                                            otherButtonTitles:nil];
	sheet.tag = tag;
	[[MATheme sharedTheme] styleActionSheet:sheet];
	for (NSInteger i = 0; i < count; i++) {
		[sheet addButtonWithTitle:MALocalizedString(options[i])];
	}
	sheet.cancelButtonIndex = [sheet addButtonWithTitle:MALocalizedString(@"Отмена")];
	[sheet showInView:self.view];
}

- (void)speakTestPhrase {
	MAVoiceService *voice = [MAVoiceService sharedService];
	voice.errorHandler = ^(NSString *message) {
		UIAlertView *alert = [[UIAlertView alloc] initWithTitle:MALocalizedString(@"Голос") message:message delegate:nil
		                                      cancelButtonTitle:@"OK" otherButtonTitles:nil];
		[alert show];
	};
	// Синтезатор говорит только по-русски, поэтому тестовая фраза не переводится вместе с интерфейсом.
	[voice speakText:@"Привет! Это встроенный голос приложения."];
}

#pragma mark - UIActionSheetDelegate

- (void)actionSheet:(UIActionSheet *)actionSheet didDismissWithButtonIndex:(NSInteger)buttonIndex {
	if (buttonIndex < 0 || buttonIndex == actionSheet.cancelButtonIndex) return;

	MAVoiceService *voice = [MAVoiceService sharedService];
	if (actionSheet.tag == kStyleSheetTag && buttonIndex < kVoiceStyleCount) {
		voice.voiceStyle = buttonIndex;
	} else if (actionSheet.tag == kRateSheetTag && buttonIndex < kSpeechRateCount) {
		voice.speechRate = kSpeechRateValues[buttonIndex];
	} else {
		return;
	}
	[self.tableView reloadData];
	[self speakTestPhrase]; // сразу слышно, как звучит выбранный вариант
}

#pragma mark - UITableViewDelegate

- (void)tableView:(UITableView *)tableView didSelectRowAtIndexPath:(NSIndexPath *)indexPath {
	[tableView deselectRowAtIndexPath:indexPath animated:YES];

	switch (indexPath.row) {
		case MASpeechRowStyle:
			[self presentOptionsWithTag:kStyleSheetTag title:MALocalizedString(@"Голос") options:kVoiceStyleTitles count:kVoiceStyleCount];
			break;
		case MASpeechRowRate:
			[self presentOptionsWithTag:kRateSheetTag title:MALocalizedString(@"Скорость речи") options:kSpeechRateTitles count:kSpeechRateCount];
			break;
		case MASpeechRowTest:
			[self speakTestPhrase];
			break;
		default:
			break;
	}
}

@end
