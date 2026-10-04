#import "MALanguageSettingsViewController.h"
#import "MALocalization.h"
#import "MATheme.h"

static NSString *const kLanguageCellIdentifier = @"LanguageCell";

typedef NS_ENUM(NSInteger, MALanguageRow) {
	MALanguageRowRussian = 0,
	MALanguageRowEnglish = 1,
	MALanguageRowCount = 2,
};

@implementation MALanguageSettingsViewController

- (instancetype)init {
	self = [super initWithStyle:UITableViewStyleGrouped];
	if (self) {
		self.title = @"Язык / Language"; // намеренно двуязычный и не переводится — чтобы его всегда можно было найти
	}
	return self;
}

// Названия языков написаны на самих языках и не переводятся.
+ (NSString *)summary {
	return [MALocalization sharedLocalization].english ? @"English" : @"Русский";
}

- (void)viewDidLoad {
	[super viewDidLoad];
	// Сменили язык — обновляем галочку и подпись под списком.
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

#pragma mark - UITableViewDataSource

- (NSInteger)numberOfSectionsInTableView:(UITableView *)tableView {
	return 1;
}

- (NSInteger)tableView:(UITableView *)tableView numberOfRowsInSection:(NSInteger)section {
	return MALanguageRowCount;
}

- (NSString *)tableView:(UITableView *)tableView titleForFooterInSection:(NSInteger)section {
	return MALocalizedString(@"Язык интерфейса приложения. На язык ответов ИИ это не влияет — его можно задать в «Инструкции».");
}

- (UITableViewCell *)tableView:(UITableView *)tableView cellForRowAtIndexPath:(NSIndexPath *)indexPath {
	UITableViewCell *cell = [tableView dequeueReusableCellWithIdentifier:MAThemedReuseID(kLanguageCellIdentifier)];
	if (!cell) {
		cell = [[UITableViewCell alloc] initWithStyle:UITableViewCellStyleDefault
		                              reuseIdentifier:MAThemedReuseID(kLanguageCellIdentifier)];
	}
	BOOL isEnglishRow = (indexPath.row == MALanguageRowEnglish);
	cell.textLabel.text = isEnglishRow ? @"English" : @"Русский";
	BOOL selected = ([MALocalization sharedLocalization].english == isEnglishRow);
	cell.accessoryType = selected ? UITableViewCellAccessoryCheckmark : UITableViewCellAccessoryNone;
	return cell;
}

#pragma mark - UITableViewDelegate

- (void)tableView:(UITableView *)tableView didSelectRowAtIndexPath:(NSIndexPath *)indexPath {
	[tableView deselectRowAtIndexPath:indexPath animated:YES];
	[MALocalization sharedLocalization].languageCode =
		(indexPath.row == MALanguageRowEnglish) ? MALanguageCodeEnglish : MALanguageCodeRussian;
}

@end
