#import "MAProviderDetailViewController.h"
#import "MALocalization.h"
#import "MATheme.h"

typedef NS_ENUM(NSInteger, MADetailRow) {
	MADetailRowBaseURL,
	MADetailRowModel,
	MADetailRowAPIKey // добавляется в список строк, только если provider.requiresAPIKey
};

@interface MAProviderDetailViewController () <UITextFieldDelegate>

@property (nonatomic, strong) id<MAConfigurableProvider> provider;
@property (nonatomic, copy) BOOL (^isActiveBlock)(void);
@property (nonatomic, copy) void (^activateBlock)(void);
@property (nonatomic, copy) void (^saveBlock)(void);

@property (nonatomic, strong) UITextField *baseURLField;
@property (nonatomic, strong) UITextField *modelField;
@property (nonatomic, strong) UITextField *apiKeyField;

@end

@implementation MAProviderDetailViewController

- (instancetype)initWithProvider:(id<MAConfigurableProvider>)provider
                        isActive:(BOOL (^)(void))isActiveBlock
                        activate:(void (^)(void))activateBlock
                            save:(void (^)(void))saveBlock {
	self = [super initWithStyle:UITableViewStyleGrouped];
	if (self) {
		_provider = provider;
		_isActiveBlock = [isActiveBlock copy];
		_activateBlock = [activateBlock copy];
		_saveBlock = [saveBlock copy];
	}
	return self;
}

- (void)viewDidLoad {
	[super viewDidLoad];
	self.title = self.provider.displayName;
}

// Сохраняем при уходе с экрана — не нужна отдельная кнопка Save.
- (void)viewWillDisappear:(BOOL)animated {
	[super viewWillDisappear:animated];
	[self commitFieldValues];
	if (self.saveBlock) self.saveBlock();
}

- (void)commitFieldValues {
	self.provider.baseURLString = [self trimmed:self.baseURLField.text];
	self.provider.model = [self trimmed:self.modelField.text];
	if (self.provider.requiresAPIKey) {
		self.provider.apiKey = [self trimmed:self.apiKeyField.text];
	}
}

// Ключ, вставленный копипастой (с сайта провайдера, из заметок и т.п.),
// нередко тащит за собой конечный перенос строки или пробел. С таким
// значением локальная проверка "apiKey.length == 0" не срабатывает —
// строка не пустая — но NSMutableURLRequest молча отказывается
// проставить HTTP-заголовок, если в значении есть \r или \n, и запрос
// уходит вообще без Authorization. Поэтому чистим все поля при сохранении.
- (NSString *)trimmed:(NSString *)text {
	return [text stringByTrimmingCharactersInSet:[NSCharacterSet whitespaceAndNewlineCharacterSet]];
}

#pragma mark - Rows

- (NSArray *)rows {
	NSMutableArray *rows = [NSMutableArray arrayWithObjects:@(MADetailRowBaseURL), @(MADetailRowModel), nil];
	if (self.provider.requiresAPIKey) {
		[rows addObject:@(MADetailRowAPIKey)];
	}
	return rows;
}

#pragma mark - UITableViewDataSource

- (NSInteger)numberOfSectionsInTableView:(UITableView *)tableView {
	return 2;
}

- (NSInteger)tableView:(UITableView *)tableView numberOfRowsInSection:(NSInteger)section {
	if (section == 0) return [self rows].count;
	return 1; // кнопка "сделать активным"
}

- (NSString *)tableView:(UITableView *)tableView titleForFooterInSection:(NSInteger)section {
	if (section == 0 && [self.provider.identifier rangeOfString:@"custom"].location != NSNotFound) {
		return MALocalizedString(@"Укажите базовый URL своего сервера. Сервер должен отвечать в формате OpenAI (/chat/completions или /images/generations).");
	}
	if (section == 0 && [self.provider.identifier isEqualToString:@"openrouter-image"]) {
		return MALocalizedString(@"Нужна модель с генерацией изображений, например google/gemini-2.5-flash-image или openai/gpt-image-2. Полный список: openrouter.ai/models?output_modalities=image");
	}
	return nil;
}

- (UITableViewCell *)tableView:(UITableView *)tableView cellForRowAtIndexPath:(NSIndexPath *)indexPath {
	if (indexPath.section == 1) {
		return [self activeButtonCell];
	}

	MADetailRow row = [[self rows][indexPath.row] integerValue];

	NSString *identifier = MAThemedReuseID(@"FieldCell");
	UITableViewCell *cell = [tableView dequeueReusableCellWithIdentifier:identifier];
	if (!cell) {
		cell = [[UITableViewCell alloc] initWithStyle:UITableViewCellStyleDefault reuseIdentifier:identifier];
		cell.selectionStyle = UITableViewCellSelectionStyleNone;
	}
	cell.textLabel.text = nil;

	for (UIView *subview in [cell.contentView.subviews copy]) {
		if ([subview isKindOfClass:[UITextField class]]) {
			[subview removeFromSuperview];
		}
	}

	UITextField *field = [[UITextField alloc] initWithFrame:CGRectMake(15, 0, cell.contentView.bounds.size.width - 30, 44)];
	field.autoresizingMask = UIViewAutoresizingFlexibleWidth;
	field.autocorrectionType = UITextAutocorrectionTypeNo;
	field.autocapitalizationType = UITextAutocapitalizationTypeNone;
	field.clearButtonMode = UITextFieldViewModeWhileEditing;
	field.delegate = self;

	MATheme *theme = [MATheme sharedTheme];
	field.textColor = theme.primaryTextColor;
	field.keyboardAppearance = theme.keyboardAppearance;

	switch (row) {
		case MADetailRowBaseURL:
			field.placeholder = @"Base URL";
			field.text = self.provider.baseURLString;
			field.keyboardType = UIKeyboardTypeURL;
			self.baseURLField = field;
			break;
		case MADetailRowModel:
			field.placeholder = MALocalizedString(@"Модель");
			field.text = self.provider.model;
			self.modelField = field;
			break;
		case MADetailRowAPIKey:
			field.placeholder = MALocalizedString(@"API-ключ");
			field.text = self.provider.apiKey;
			field.secureTextEntry = YES;
			self.apiKeyField = field;
			break;
	}

	[self applyPlaceholderColorToField:field];
	[cell.contentView addSubview:field];
	return cell;
}

// Штатный placeholder серый и на тёмной ячейке едва виден — в тёмной теме перекрашиваем.
- (void)applyPlaceholderColorToField:(UITextField *)field {
	if (![MATheme sharedTheme].dark || field.placeholder.length == 0) return;
	field.attributedPlaceholder = [[NSAttributedString alloc] initWithString:field.placeholder
	                                                              attributes:@{NSForegroundColorAttributeName: [MATheme sharedTheme].placeholderTextColor}];
}

- (UITableViewCell *)activeButtonCell {
	NSString *identifier = MAThemedReuseID(@"ActiveCell");
	UITableViewCell *cell = [[UITableViewCell alloc] initWithStyle:UITableViewCellStyleDefault reuseIdentifier:identifier];
	BOOL isActive = self.isActiveBlock ? self.isActiveBlock() : NO;
	cell.textLabel.text = isActive ? MALocalizedString(@"Активен") : MALocalizedString(@"Сделать активным");
	cell.textLabel.textAlignment = NSTextAlignmentCenter;
	cell.textLabel.textColor = isActive ? [UIColor grayColor] : [MATheme sharedTheme].actionColor;
	cell.selectionStyle = isActive ? UITableViewCellSelectionStyleNone : UITableViewCellSelectionStyleBlue;
	return cell;
}

#pragma mark - UITableViewDelegate

// Базовый класс в тёмной теме красит все подписи в основной цвет — для кнопки
// «Сделать активным» возвращаем её собственный.
- (void)tableView:(UITableView *)tableView willDisplayCell:(UITableViewCell *)cell forRowAtIndexPath:(NSIndexPath *)indexPath {
	[super tableView:tableView willDisplayCell:cell forRowAtIndexPath:indexPath];
	if (indexPath.section != 1) return;
	BOOL isActive = self.isActiveBlock ? self.isActiveBlock() : NO;
	cell.textLabel.textColor = isActive ? [UIColor grayColor] : [MATheme sharedTheme].actionColor;
}

- (void)tableView:(UITableView *)tableView didSelectRowAtIndexPath:(NSIndexPath *)indexPath {
	[tableView deselectRowAtIndexPath:indexPath animated:YES];
	if (indexPath.section != 1) return;

	[self commitFieldValues];
	if (self.activateBlock) self.activateBlock();
	if (self.saveBlock) self.saveBlock();
	[tableView reloadData];
}

#pragma mark - UITextFieldDelegate

- (BOOL)textFieldShouldReturn:(UITextField *)textField {
	[textField resignFirstResponder];
	return YES;
}

@end
