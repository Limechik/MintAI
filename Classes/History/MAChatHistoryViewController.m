#import "MAChatHistoryViewController.h"
#import "MALocalization.h"
#import "MATheme.h"
#import "MAChatHistoryStore.h"
#import "MAChatSession.h"
#import "MAChatViewController.h"

static NSString *const kHistoryCellIdentifier = @"HistoryCell";

@interface MAChatHistoryViewController ()
@property (nonatomic, strong) NSArray *sessions; // MAChatSession*, снимок для текущего показа таблицы
@property (nonatomic, strong) NSDateFormatter *dateFormatter;
@property (nonatomic, strong) UILabel *emptyLabel;
@end

@implementation MAChatHistoryViewController

- (instancetype)init {
	self = [super initWithStyle:UITableViewStylePlain];
	return self;
}

- (void)viewDidLoad {
	[super viewDidLoad];
	self.title = MALocalizedString(@"История чатов");

	self.dateFormatter = [[NSDateFormatter alloc] init];
	self.dateFormatter.dateStyle = NSDateFormatterShortStyle;
	self.dateFormatter.timeStyle = NSDateFormatterShortStyle;
	self.dateFormatter.doesRelativeDateFormatting = YES;
	self.dateFormatter.locale = [[NSLocale alloc] initWithLocaleIdentifier:[MALocalization sharedLocalization].languageCode];

	self.emptyLabel = [[UILabel alloc] init];
	self.emptyLabel.text = MALocalizedString(@"Пока нет сохранённых бесед.\nНачни чат на вкладке «Chat» —\nон появится здесь автоматически.");
	self.emptyLabel.numberOfLines = 0;
	self.emptyLabel.textAlignment = NSTextAlignmentCenter;
	self.emptyLabel.textColor = [MATheme sharedTheme].secondaryTextColor;
	self.emptyLabel.backgroundColor = [UIColor clearColor];
	self.emptyLabel.font = [UIFont systemFontOfSize:15];
	self.emptyLabel.hidden = YES;
	[self.view addSubview:self.emptyLabel];

	[[NSNotificationCenter defaultCenter] addObserver:self
	                                          selector:@selector(languageDidChange:)
	                                              name:MALanguageDidChangeNotification
	                                            object:nil];
}

- (void)dealloc {
	[[NSNotificationCenter defaultCenter] removeObserver:self];
}

- (void)languageDidChange:(NSNotification *)notification {
	self.title = MALocalizedString(@"История чатов");
	self.emptyLabel.text = MALocalizedString(@"Пока нет сохранённых бесед.\nНачни чат на вкладке «Chat» —\nон появится здесь автоматически.");
	self.dateFormatter.locale = [[NSLocale alloc] initWithLocaleIdentifier:[MALocalization sharedLocalization].languageCode];
	[self.tableView reloadData];
}

- (void)viewWillAppear:(BOOL)animated {
	[super viewWillAppear:animated];
	self.emptyLabel.textColor = [MATheme sharedTheme].secondaryTextColor; // тему могли сменить в настройках
	self.sessions = [MAChatHistoryStore sharedStore].sessions;
	[self.tableView reloadData];
	[self updateEmptyState];
}

- (void)viewDidLayoutSubviews {
	[super viewDidLayoutSubviews];
	CGRect bounds = self.view.bounds;
	CGFloat margin = 24;
	self.emptyLabel.frame = CGRectMake(margin, bounds.size.height / 2.0 - 60,
	                                    bounds.size.width - margin * 2, 120);
}

- (void)updateEmptyState {
	self.emptyLabel.hidden = (self.sessions.count > 0);
}

#pragma mark - UITableViewDataSource

- (NSInteger)tableView:(UITableView *)tableView numberOfRowsInSection:(NSInteger)section {
	return self.sessions.count;
}

- (UITableViewCell *)tableView:(UITableView *)tableView cellForRowAtIndexPath:(NSIndexPath *)indexPath {
	UITableViewCell *cell = [tableView dequeueReusableCellWithIdentifier:MAThemedReuseID(kHistoryCellIdentifier)];
	if (!cell) {
		cell = [[UITableViewCell alloc] initWithStyle:UITableViewCellStyleSubtitle
		                                reuseIdentifier:MAThemedReuseID(kHistoryCellIdentifier)];
	}

	MAChatSession *session = self.sessions[indexPath.row];
	cell.textLabel.text = [session displayTitle];
	NSString *date = [self.dateFormatter stringFromDate:session.updatedAt];
	cell.detailTextLabel.text = [NSString stringWithFormat:@"%@ — %@", date, [session lastMessagePreview]];
	cell.accessoryType = UITableViewCellAccessoryDisclosureIndicator;

	return cell;
}

- (BOOL)tableView:(UITableView *)tableView canEditRowAtIndexPath:(NSIndexPath *)indexPath {
	return YES;
}

- (void)tableView:(UITableView *)tableView commitEditingStyle:(UITableViewCellEditingStyle)editingStyle forRowAtIndexPath:(NSIndexPath *)indexPath {
	if (editingStyle != UITableViewCellEditingStyleDelete) return;

	MAChatSession *session = self.sessions[indexPath.row];
	[[MAChatHistoryStore sharedStore] deleteSession:session];

	NSMutableArray *mutableSessions = [self.sessions mutableCopy];
	[mutableSessions removeObjectAtIndex:indexPath.row];
	self.sessions = mutableSessions;

	[tableView deleteRowsAtIndexPaths:@[indexPath] withRowAnimation:UITableViewRowAnimationFade];
	[self updateEmptyState];
}

#pragma mark - UITableViewDelegate

- (void)tableView:(UITableView *)tableView didSelectRowAtIndexPath:(NSIndexPath *)indexPath {
	[tableView deselectRowAtIndexPath:indexPath animated:YES];
	MAChatSession *session = self.sessions[indexPath.row];
	MAChatViewController *chatVC = [[MAChatViewController alloc] initWithSession:session];
	[self.navigationController pushViewController:chatVC animated:YES];
}

@end
