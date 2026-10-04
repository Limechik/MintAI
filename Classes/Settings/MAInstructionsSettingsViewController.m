#import "MAInstructionsSettingsViewController.h"
#import "MAInstructionsViewController.h"
#import "MAInstructionsStore.h"
#import "MALocalization.h"
#import "MATheme.h"

static NSString *const kInstructionsSwitchCellIdentifier = @"InstructionsSwitchCell";
static NSString *const kInstructionsTextCellIdentifier = @"InstructionsTextCell";

typedef NS_ENUM(NSInteger, MAInstructionsRow) {
	MAInstructionsRowEnabled = 0,
	MAInstructionsRowText = 1,
	MAInstructionsRowCount = 2,
};

@implementation MAInstructionsSettingsViewController

- (instancetype)init {
	self = [super initWithStyle:UITableViewStyleGrouped];
	if (self) {
		self.title = MALocalizedString(@"Инструкция");
	}
	return self;
}

+ (NSString *)summary {
	MAInstructionsStore *store = [MAInstructionsStore sharedStore];
	if (!store.enabled) return MALocalizedString(@"Выкл");
	NSString *text = [store.instructions stringByTrimmingCharactersInSet:[NSCharacterSet whitespaceAndNewlineCharacterSet]];
	return (text.length == 0) ? MALocalizedString(@"Не задана") : MALocalizedString(@"Вкл");
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
	self.title = MALocalizedString(@"Инструкция");
	[self.tableView reloadData];
}

- (void)viewWillAppear:(BOOL)animated {
	[super viewWillAppear:animated];
	// Текст могли отредактировать на экране редактора — обновляем превью.
	[self.tableView reloadData];
}

#pragma mark - UITableViewDataSource

- (NSInteger)numberOfSectionsInTableView:(UITableView *)tableView {
	return 1;
}

- (NSInteger)tableView:(UITableView *)tableView numberOfRowsInSection:(NSInteger)section {
	return MAInstructionsRowCount;
}

- (NSString *)tableView:(UITableView *)tableView titleForFooterInSection:(NSInteger)section {
	return MALocalizedString(@"Текст подмешивается к каждому запросу как системное сообщение, поэтому ИИ следует ему во всех чатах (в ленте оно не показывается). Чем длиннее инструкция, тем больше токенов уходит на каждое сообщение.");
}

- (UITableViewCell *)tableView:(UITableView *)tableView cellForRowAtIndexPath:(NSIndexPath *)indexPath {
	MAInstructionsStore *store = [MAInstructionsStore sharedStore];

	if (indexPath.row == MAInstructionsRowEnabled) {
		UITableViewCell *cell = [tableView dequeueReusableCellWithIdentifier:MAThemedReuseID(kInstructionsSwitchCellIdentifier)];
		if (!cell) {
			cell = [[UITableViewCell alloc] initWithStyle:UITableViewCellStyleDefault
			                              reuseIdentifier:MAThemedReuseID(kInstructionsSwitchCellIdentifier)];
			UISwitch *toggle = [[UISwitch alloc] init];
			[toggle addTarget:self action:@selector(instructionsSwitchChanged:) forControlEvents:UIControlEventValueChanged];
			cell.accessoryView = toggle;
			cell.selectionStyle = UITableViewCellSelectionStyleNone;
		}
		cell.textLabel.text = MALocalizedString(@"Использовать инструкцию");
		((UISwitch *)cell.accessoryView).on = store.enabled;
		return cell;
	}

	UITableViewCell *cell = [tableView dequeueReusableCellWithIdentifier:MAThemedReuseID(kInstructionsTextCellIdentifier)];
	if (!cell) {
		cell = [[UITableViewCell alloc] initWithStyle:UITableViewCellStyleSubtitle
		                              reuseIdentifier:MAThemedReuseID(kInstructionsTextCellIdentifier)];
		cell.accessoryType = UITableViewCellAccessoryDisclosureIndicator;
	}
	cell.textLabel.text = MALocalizedString(@"Текст инструкции");

	NSString *text = [store.instructions stringByTrimmingCharactersInSet:[NSCharacterSet whitespaceAndNewlineCharacterSet]];
	if (text.length == 0) {
		cell.detailTextLabel.text = MALocalizedString(@"Не задана");
	} else {
		// Превью в одну строку: переводы строк заменяем пробелами, хвост обрежет сама ячейка.
		cell.detailTextLabel.text = [[text componentsSeparatedByCharactersInSet:[NSCharacterSet newlineCharacterSet]]
		                             componentsJoinedByString:@" "];
	}
	return cell;
}

- (void)instructionsSwitchChanged:(UISwitch *)sender {
	[MAInstructionsStore sharedStore].enabled = sender.on;
}

#pragma mark - UITableViewDelegate

- (void)tableView:(UITableView *)tableView didSelectRowAtIndexPath:(NSIndexPath *)indexPath {
	[tableView deselectRowAtIndexPath:indexPath animated:YES];
	if (indexPath.row == MAInstructionsRowText) {
		[self.navigationController pushViewController:[[MAInstructionsViewController alloc] init] animated:YES];
	}
}

@end
