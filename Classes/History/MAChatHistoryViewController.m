#import "MAChatHistoryViewController.h"
#import "MALocalization.h"
#import "MATheme.h"
#import "MAChatHistoryStore.h"
#import "MAChatSession.h"
#import "MAMessage.h"
#import "MAChatViewController.h"

static NSString *const kHistoryCellIdentifier = @"HistoryCell";

@interface MAChatHistoryViewController () <UISearchBarDelegate>
@property (nonatomic, strong) NSArray *allSessions; // MAChatSession*, снимок из MAChatHistoryStore
@property (nonatomic, strong) NSArray *sessions;    // MAChatSession*, то, что сейчас показано в таблице (с учётом поиска)
@property (nonatomic, strong) NSMutableDictionary *snippets; // sessionID -> фрагмент сообщения с найденным словом
@property (nonatomic, strong) UISearchBar *searchBar;
@property (nonatomic, assign) BOOL didHideSearchBar;
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

	self.snippets = [NSMutableDictionary dictionary];
	self.searchBar = [[UISearchBar alloc] initWithFrame:CGRectMake(0, 0, 320, 44)];
	self.searchBar.delegate = self;
	self.searchBar.placeholder = MALocalizedString(@"Поиск по истории");
	self.searchBar.autocapitalizationType = UITextAutocapitalizationTypeNone;
	self.searchBar.autocorrectionType = UITextAutocorrectionTypeNo;
	[self applySearchBarTheme];
	self.tableView.tableHeaderView = self.searchBar;

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
	self.searchBar.placeholder = MALocalizedString(@"Поиск по истории");
	self.dateFormatter.locale = [[NSLocale alloc] initWithLocaleIdentifier:[MALocalization sharedLocalization].languageCode];
	[self updateEmptyState];
	[self.tableView reloadData];
}

- (void)applySearchBarTheme {
	MATheme *theme = [MATheme sharedTheme];
	self.searchBar.barStyle = theme.dark ? UIBarStyleBlack : UIBarStyleDefault;
	self.searchBar.tintColor = theme.navigationBarTintColor;
	// До iOS 7 у UISearchBar нет keyboardAppearance — выставляем его внутреннему текстовому полю.
	for (UIView *subview in self.searchBar.subviews) {
		if ([subview isKindOfClass:[UITextField class]]) {
			((UITextField *)subview).keyboardAppearance = theme.keyboardAppearance;
			break;
		}
	}
}


- (void)viewWillAppear:(BOOL)animated {
	[super viewWillAppear:animated];
	self.emptyLabel.textColor = [MATheme sharedTheme].secondaryTextColor; // тему могли сменить в настройках
	[self applySearchBarTheme];
	self.allSessions = [MAChatHistoryStore sharedStore].sessions;
	[self applyFilter]; // заодно перечитывает таблицу; активный поиск сохраняется при возврате из чата

	// Как в системных приложениях: при первом показе строка поиска спрятана под навбаром,
	// достаточно потянуть список вниз. Прячем, только если список длиннее экрана,
	// иначе его не на что прокручивать.
	if (!self.didHideSearchBar) {
		self.didHideSearchBar = YES;
		if (self.searchBar.text.length == 0 &&
		    self.tableView.contentSize.height > self.tableView.bounds.size.height) {
			self.tableView.contentOffset = CGPointMake(0, self.searchBar.bounds.size.height);
		}
	}
}

- (void)viewWillDisappear:(BOOL)animated {
	[super viewWillDisappear:animated];
	[self.searchBar resignFirstResponder];
}

#pragma mark - Поиск

// Разбивает запрос на слова: сессия подходит, если КАЖДОЕ слово встречается в названии
// или в тексте любого сообщения (регистр и диакритика не важны).
- (NSArray *)searchTokens {
	NSString *query = [self.searchBar.text stringByTrimmingCharactersInSet:[NSCharacterSet whitespaceAndNewlineCharacterSet]];
	if (query.length == 0) return @[];
	NSMutableArray *tokens = [NSMutableArray array];
	for (NSString *part in [query componentsSeparatedByCharactersInSet:[NSCharacterSet whitespaceAndNewlineCharacterSet]]) {
		if (part.length > 0) [tokens addObject:part];
	}
	return tokens;
}

static NSStringCompareOptions const kSearchOptions = NSCaseInsensitiveSearch | NSDiacriticInsensitiveSearch;

- (BOOL)text:(NSString *)text containsToken:(NSString *)token {
	return text.length > 0 && [text rangeOfString:token options:kSearchOptions].location != NSNotFound;
}

- (BOOL)session:(MAChatSession *)session matchesTokens:(NSArray *)tokens {
	for (NSString *token in tokens) {
		BOOL found = [self text:session.title containsToken:token] || [self text:[session displayTitle] containsToken:token];
		if (!found) {
			for (MAMessage *message in session.messages) {
				if ([self text:message.content containsToken:token]) { found = YES; break; }
			}
		}
		if (!found) return NO;
	}
	return YES;
}

// Фрагмент первого сообщения, где встречается первое слово запроса: немного текста до
// совпадения и побольше после, переводы строк заменены пробелами, края обозначены «…».
- (NSString *)snippetForSession:(MAChatSession *)session token:(NSString *)token {
	for (MAMessage *message in session.messages) {
		NSString *content = message.content;
		if (content.length == 0) continue;
		NSRange range = [content rangeOfString:token options:kSearchOptions];
		if (range.location == NSNotFound) continue;

		NSUInteger start = (range.location > 20) ? range.location - 20 : 0;
		NSUInteger end = MIN(content.length, NSMaxRange(range) + 60);
		NSRange window = [content rangeOfComposedCharacterSequencesForRange:NSMakeRange(start, end - start)];
		NSString *piece = [content substringWithRange:window];
		piece = [[piece componentsSeparatedByCharactersInSet:[NSCharacterSet newlineCharacterSet]] componentsJoinedByString:@" "];
		piece = [piece stringByTrimmingCharactersInSet:[NSCharacterSet whitespaceCharacterSet]];
		return [NSString stringWithFormat:@"%@%@%@", window.location > 0 ? @"…" : @"", piece, NSMaxRange(window) < content.length ? @"…" : @""];
	}
	return nil; // совпало только название — в подписи останется обычный превью
}

- (void)applyFilter {
	NSArray *tokens = [self searchTokens];
	[self.snippets removeAllObjects];

	if (tokens.count == 0) {
		self.sessions = self.allSessions;
	} else {
		NSMutableArray *result = [NSMutableArray array];
		for (MAChatSession *session in self.allSessions) {
			if (![self session:session matchesTokens:tokens]) continue;
			[result addObject:session];
			NSString *snippet = [self snippetForSession:session token:tokens[0]];
			if (snippet && session.sessionID) self.snippets[session.sessionID] = snippet;
		}
		self.sessions = result;
	}
	[self.tableView reloadData];
	[self updateEmptyState];
}

#pragma mark - UISearchBarDelegate

- (void)searchBarTextDidBeginEditing:(UISearchBar *)searchBar {
	[searchBar setShowsCancelButton:YES animated:YES];
}

- (void)searchBarTextDidEndEditing:(UISearchBar *)searchBar {
	if (searchBar.text.length == 0) [searchBar setShowsCancelButton:NO animated:YES];
}

- (void)searchBar:(UISearchBar *)searchBar textDidChange:(NSString *)searchText {
	[self applyFilter];
}

- (void)searchBarSearchButtonClicked:(UISearchBar *)searchBar {
	[searchBar resignFirstResponder];
}

- (void)searchBarCancelButtonClicked:(UISearchBar *)searchBar {
	searchBar.text = @"";
	[searchBar resignFirstResponder];
	[searchBar setShowsCancelButton:NO animated:YES];
	[self applyFilter];
}

- (void)scrollViewWillBeginDragging:(UIScrollView *)scrollView {
	[self.searchBar resignFirstResponder]; // клавиатура убирается началом прокрутки, как в чате
}

- (void)viewDidLayoutSubviews {
	[super viewDidLayoutSubviews];
	CGRect bounds = self.view.bounds;
	CGFloat margin = 24;
	self.emptyLabel.frame = CGRectMake(margin, bounds.size.height / 2.0 - 60,
	                                    bounds.size.width - margin * 2, 120);
}

- (void)updateEmptyState {
	BOOL searching = ([self searchTokens].count > 0);
	if (searching && self.sessions.count == 0) {
		self.emptyLabel.text = MALocalizedString(@"Ничего не найдено");
	} else {
		self.emptyLabel.text = MALocalizedString(@"Пока нет сохранённых бесед.\nНачни чат на вкладке «Chat» —\nон появится здесь автоматически.");
	}
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
	NSString *preview = self.snippets[session.sessionID] ?: [session lastMessagePreview];
	cell.detailTextLabel.text = [NSString stringWithFormat:@"%@ — %@", date, preview];
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

	NSMutableArray *mutableAll = [self.allSessions mutableCopy];
	[mutableAll removeObject:session];
	self.allSessions = mutableAll;

	NSMutableArray *mutableSessions = [self.sessions mutableCopy];
	[mutableSessions removeObjectAtIndex:indexPath.row];
	self.sessions = mutableSessions;

	[tableView deleteRowsAtIndexPaths:@[indexPath] withRowAnimation:UITableViewRowAnimationFade];
	[self updateEmptyState];
}

#pragma mark - UITableViewDelegate

- (void)tableView:(UITableView *)tableView didSelectRowAtIndexPath:(NSIndexPath *)indexPath {
	[tableView deselectRowAtIndexPath:indexPath animated:YES];
	[self.searchBar resignFirstResponder];
	MAChatSession *session = self.sessions[indexPath.row];
	MAChatViewController *chatVC = [[MAChatViewController alloc] initWithSession:session];
	[self.navigationController pushViewController:chatVC animated:YES];
}

@end
