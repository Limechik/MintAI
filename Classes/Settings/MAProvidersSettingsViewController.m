#import "MAProvidersSettingsViewController.h"
#import "MAProviderDetailViewController.h"
#import "MAProviderRegistry.h"
#import "MAImageProviderRegistry.h"
#import "MAProvider.h"
#import "MAImageProvider.h"
#import "MALocalization.h"
#import "MATheme.h"

static NSString *const kProviderCellIdentifier = @"ProviderCell";

@interface MAProvidersSettingsViewController ()
@property (nonatomic, assign) MAProvidersKind kind;
@end

@implementation MAProvidersSettingsViewController

- (instancetype)initWithKind:(MAProvidersKind)kind {
	self = [super initWithStyle:UITableViewStyleGrouped];
	if (self) {
		_kind = kind;
		self.title = [self screenTitle];
	}
	return self;
}

+ (NSString *)summaryForKind:(MAProvidersKind)kind {
	id<MAConfigurableProvider> active = (kind == MAProvidersKindChat)
		? (id<MAConfigurableProvider>)[MAProviderRegistry sharedRegistry].activeProvider
		: (id<MAConfigurableProvider>)[MAImageProviderRegistry sharedRegistry].activeProvider;
	return active ? active.displayName : MALocalizedString(@"Не выбран");
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
	self.title = [self screenTitle];
	[self.tableView reloadData];
}

- (void)viewWillAppear:(BOOL)animated {
	[super viewWillAppear:animated];
	// Активный провайдер и его статус могли поменяться на экране деталей.
	[self.tableView reloadData];
}

#pragma mark - Helpers

- (NSString *)screenTitle {
	return (self.kind == MAProvidersKindChat) ? MALocalizedString(@"Провайдеры чата") : MALocalizedString(@"Генерация изображений");
}

- (NSArray *)providers {
	return (self.kind == MAProvidersKindChat)
		? [[MAProviderRegistry sharedRegistry] providers]
		: [[MAImageProviderRegistry sharedRegistry] providers];
}

- (BOOL)isProviderActive:(id<MAConfigurableProvider>)provider {
	id active = (self.kind == MAProvidersKindChat)
		? (id)[MAProviderRegistry sharedRegistry].activeProvider
		: (id)[MAImageProviderRegistry sharedRegistry].activeProvider;
	return provider == active;
}

#pragma mark - UITableViewDataSource

- (NSInteger)numberOfSectionsInTableView:(UITableView *)tableView {
	return 1;
}

- (NSInteger)tableView:(UITableView *)tableView numberOfRowsInSection:(NSInteger)section {
	return [self providers].count;
}

- (NSString *)tableView:(UITableView *)tableView titleForFooterInSection:(NSInteger)section {
	return MALocalizedString(@"Отметка галочкой — провайдер, который используется прямо сейчас. Тапни, чтобы задать ключ/URL/модель.");
}

- (UITableViewCell *)tableView:(UITableView *)tableView cellForRowAtIndexPath:(NSIndexPath *)indexPath {
	UITableViewCell *cell = [tableView dequeueReusableCellWithIdentifier:MAThemedReuseID(kProviderCellIdentifier)];
	if (!cell) {
		cell = [[UITableViewCell alloc] initWithStyle:UITableViewCellStyleSubtitle
		                              reuseIdentifier:MAThemedReuseID(kProviderCellIdentifier)];
	}

	id<MAConfigurableProvider> provider = [self providers][indexPath.row];

	cell.textLabel.text = provider.displayName;

	if (provider.requiresAPIKey && provider.apiKey.length == 0) {
		cell.detailTextLabel.text = MALocalizedString(@"Ключ не задан");
	} else if (!provider.requiresAPIKey && provider.baseURLString.length == 0) {
		cell.detailTextLabel.text = MALocalizedString(@"URL не задан");
	} else {
		cell.detailTextLabel.text = (provider.model.length > 0) ? provider.model : MALocalizedString(@"Настроено");
	}

	cell.accessoryType = [self isProviderActive:provider] ? UITableViewCellAccessoryCheckmark : UITableViewCellAccessoryDisclosureIndicator;
	return cell;
}

#pragma mark - UITableViewDelegate

- (void)tableView:(UITableView *)tableView didSelectRowAtIndexPath:(NSIndexPath *)indexPath {
	[tableView deselectRowAtIndexPath:indexPath animated:YES];

	id<MAConfigurableProvider> provider = [self providers][indexPath.row];
	MAProviderDetailViewController *detailVC;

	if (self.kind == MAProvidersKindChat) {
		id<MAProvider> chatProvider = (id<MAProvider>)provider;
		detailVC = [[MAProviderDetailViewController alloc] initWithProvider:provider
		    isActive:^BOOL{
		        return [MAProviderRegistry sharedRegistry].activeProvider == chatProvider;
		    }
		    activate:^{
		        [MAProviderRegistry sharedRegistry].activeProvider = chatProvider;
		    }
		    save:^{
		        [[MAProviderRegistry sharedRegistry] persistSettingsForProvider:chatProvider];
		    }];
	} else {
		id<MAImageProvider> imageProvider = (id<MAImageProvider>)provider;
		detailVC = [[MAProviderDetailViewController alloc] initWithProvider:provider
		    isActive:^BOOL{
		        return [MAImageProviderRegistry sharedRegistry].activeProvider == imageProvider;
		    }
		    activate:^{
		        [MAImageProviderRegistry sharedRegistry].activeProvider = imageProvider;
		    }
		    save:^{
		        [[MAImageProviderRegistry sharedRegistry] persistSettingsForProvider:imageProvider];
		    }];
	}

	[self.navigationController pushViewController:detailVC animated:YES];
}

@end
