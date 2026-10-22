#import "MAModelPickerViewController.h"
#import "MALocalization.h"
#import "MATheme.h"

static NSString *const kModelCellIdentifier = @"ModelCell";

@interface MAModelPickerViewController ()
@property (nonatomic, copy) NSArray *models; // NSString*
@property (nonatomic, copy) NSString *selectedModel;
@property (nonatomic, copy) void (^onSelect)(NSString *model);
@end

@implementation MAModelPickerViewController

- (instancetype)initWithModels:(NSArray *)models
                 selectedModel:(NSString *)selectedModel
                      onSelect:(void (^)(NSString *model))onSelect {
	self = [super initWithStyle:UITableViewStyleGrouped];
	if (self) {
		_models = [models copy];
		_selectedModel = [selectedModel copy];
		_onSelect = [onSelect copy];
		self.title = MALocalizedString(@"Модели");
	}
	return self;
}

#pragma mark - UITableViewDataSource

- (NSInteger)numberOfSectionsInTableView:(UITableView *)tableView {
	return 1;
}

- (NSInteger)tableView:(UITableView *)tableView numberOfRowsInSection:(NSInteger)section {
	return self.models.count;
}

- (UITableViewCell *)tableView:(UITableView *)tableView cellForRowAtIndexPath:(NSIndexPath *)indexPath {
	UITableViewCell *cell = [tableView dequeueReusableCellWithIdentifier:MAThemedReuseID(kModelCellIdentifier)];
	if (!cell) {
		cell = [[UITableViewCell alloc] initWithStyle:UITableViewCellStyleDefault
		                              reuseIdentifier:MAThemedReuseID(kModelCellIdentifier)];
	}
	NSString *model = self.models[indexPath.row];
	cell.textLabel.text = model;
	cell.textLabel.adjustsFontSizeToFitWidth = YES;
	cell.textLabel.minimumScaleFactor = 0.6;
	cell.accessoryType = [model isEqualToString:self.selectedModel] ? UITableViewCellAccessoryCheckmark : UITableViewCellAccessoryNone;
	return cell;
}

#pragma mark - UITableViewDelegate

- (void)tableView:(UITableView *)tableView didSelectRowAtIndexPath:(NSIndexPath *)indexPath {
	[tableView deselectRowAtIndexPath:indexPath animated:YES];
	NSString *model = self.models[indexPath.row];
	if (self.onSelect) self.onSelect(model);
	[self.navigationController popViewControllerAnimated:YES];
}

@end
