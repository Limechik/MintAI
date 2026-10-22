#import "MAProviderDetailViewController.h"
#import "MALocalProvider.h"
#import "MAModelPickerViewController.h"
#import "MALocalization.h"
#import "MATheme.h"

typedef NS_ENUM(NSInteger, MADetailRow) {
	MADetailRowBaseURL,
	MADetailRowModel,
	MADetailRowAPIKey // добавляется в список строк, если provider.requiresAPIKey или это локальный сервер (ключ необязателен)
};

// Секция «инструменты» есть только у локального сервера (MALocalProvider).
typedef NS_ENUM(NSInteger, MALocalToolRow) {
	MALocalToolRowPreset,
	MALocalToolRowCheck
};

@interface MAProviderDetailViewController () <UITextFieldDelegate, UIActionSheetDelegate>

@property (nonatomic, strong) id<MAConfigurableProvider> provider;
@property (nonatomic, copy) BOOL (^isActiveBlock)(void);
@property (nonatomic, copy) void (^activateBlock)(void);
@property (nonatomic, copy) void (^saveBlock)(void);

@property (nonatomic, strong) UITextField *baseURLField;
@property (nonatomic, strong) UITextField *modelField;
@property (nonatomic, strong) UITextField *apiKeyField;
@property (nonatomic, assign) BOOL checkingConnection; // идёт запрос списка моделей

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

// Поля могут быть nil: после -reloadFields они пересоздаются только при следующей отрисовке,
// и устаревшие значения не должны затереть то, что уже записано в провайдер.
- (void)commitFieldValues {
	if (self.baseURLField) self.provider.baseURLString = [self trimmed:self.baseURLField.text];
	if (self.modelField) self.provider.model = [self trimmed:self.modelField.text];
	if (self.apiKeyField && [self showsAPIKeyRow]) {
		self.provider.apiKey = [self trimmed:self.apiKeyField.text];
	}
}

// Перечитывает таблицу, показывая текущие значения провайдера (а не набранное в полях).
- (void)reloadFields {
	self.baseURLField = nil;
	self.modelField = nil;
	self.apiKeyField = nil;
	[self.tableView reloadData];
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

- (BOOL)isLocalServer {
	return [self.provider isKindOfClass:[MALocalProvider class]];
}

// У локального сервера ключ необязателен, но поле нужно: сервер может стоять за прокси с авторизацией.
- (BOOL)showsAPIKeyRow {
	return self.provider.requiresAPIKey || [self isLocalServer];
}

// Разметка секций: 0 — поля; у локального сервера 1 — инструменты (пресет, проверка);
// последняя — кнопка «Сделать активным».
- (NSInteger)toolsSection {
	return [self isLocalServer] ? 1 : NSNotFound;
}

- (NSInteger)activeSection {
	return [self isLocalServer] ? 2 : 1;
}

- (NSArray *)rows {
	NSMutableArray *rows = [NSMutableArray arrayWithObjects:@(MADetailRowBaseURL), @(MADetailRowModel), nil];
	if ([self showsAPIKeyRow]) {
		[rows addObject:@(MADetailRowAPIKey)];
	}
	return rows;
}

#pragma mark - UITableViewDataSource

- (NSInteger)numberOfSectionsInTableView:(UITableView *)tableView {
	return [self activeSection] + 1;
}

- (NSInteger)tableView:(UITableView *)tableView numberOfRowsInSection:(NSInteger)section {
	if (section == 0) return [self rows].count;
	if (section == [self toolsSection]) return 2;
	return 1; // кнопка "сделать активным"
}

- (NSString *)tableView:(UITableView *)tableView titleForFooterInSection:(NSInteger)section {
	if (section == 0 && [self isLocalServer]) {
		return MALocalizedString(@"Укажите адрес сервера в вашей Wi-Fi сети, например http://192.168.0.5:11434/v1. Ollama: запускайте с OLLAMA_HOST=0.0.0.0. LM Studio: включите «Serve on Local Network». Ключ нужен, только если сервер защищён.");
	}
	if (section == 0 && [self.provider.identifier rangeOfString:@"custom"].location != NSNotFound) {
		return MALocalizedString(@"Укажите базовый URL своего сервера. Сервер должен отвечать в формате OpenAI (/chat/completions или /images/generations).");
	}
	if (section == 0 && [self.provider.identifier isEqualToString:@"openrouter-image"]) {
		return MALocalizedString(@"Нужна модель с генерацией изображений, например google/gemini-2.5-flash-image или openai/gpt-image-2. Полный список: openrouter.ai/models?output_modalities=image");
	}
	return nil;
}

- (UITableViewCell *)tableView:(UITableView *)tableView cellForRowAtIndexPath:(NSIndexPath *)indexPath {
	if (indexPath.section == [self toolsSection]) {
		return [self toolCellForRow:indexPath.row];
	}
	if (indexPath.section == [self activeSection]) {
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
			field.placeholder = [self isLocalServer] ? @"http://192.168.0.5:11434/v1" : @"Base URL";
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
			field.placeholder = [self isLocalServer] ? MALocalizedString(@"API-ключ (необязательно)") : MALocalizedString(@"API-ключ");
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

- (UITableViewCell *)toolCellForRow:(NSInteger)row {
	UITableViewCell *cell = [[UITableViewCell alloc] initWithStyle:UITableViewCellStyleDefault
	                                               reuseIdentifier:MAThemedReuseID(@"ToolCell")];
	cell.textLabel.textAlignment = NSTextAlignmentCenter;
	cell.textLabel.textColor = [MATheme sharedTheme].actionColor;

	if (row == MALocalToolRowPreset) {
		cell.textLabel.text = MALocalizedString(@"Выбрать пресет сервера");
	} else if (self.checkingConnection) {
		cell.textLabel.text = MALocalizedString(@"Подключение…");
		UIActivityIndicatorView *spinner = [[UIActivityIndicatorView alloc] initWithActivityIndicatorStyle:
			[MATheme sharedTheme].dark ? UIActivityIndicatorViewStyleWhite : UIActivityIndicatorViewStyleGray];
		[spinner startAnimating];
		cell.accessoryView = spinner;
		cell.selectionStyle = UITableViewCellSelectionStyleNone;
	} else {
		cell.textLabel.text = MALocalizedString(@"Проверить подключение и выбрать модель");
	}
	return cell;
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
	if (indexPath.section == [self toolsSection]) {
		cell.textLabel.textColor = [MATheme sharedTheme].actionColor;
		return;
	}
	if (indexPath.section != [self activeSection]) return;
	BOOL isActive = self.isActiveBlock ? self.isActiveBlock() : NO;
	cell.textLabel.textColor = isActive ? [UIColor grayColor] : [MATheme sharedTheme].actionColor;
}

- (void)tableView:(UITableView *)tableView didSelectRowAtIndexPath:(NSIndexPath *)indexPath {
	[tableView deselectRowAtIndexPath:indexPath animated:YES];

	if (indexPath.section == [self toolsSection]) {
		if (indexPath.row == MALocalToolRowPreset) [self showPresetSheet];
		else [self checkConnection];
		return;
	}
	if (indexPath.section != [self activeSection]) return;

	[self commitFieldValues];
	if (self.activateBlock) self.activateBlock();
	if (self.saveBlock) self.saveBlock();
	[tableView reloadData];
}

#pragma mark - Локальный сервер

- (void)showPresetSheet {
	[self.view endEditing:YES];
	UIActionSheet *sheet = [[UIActionSheet alloc] initWithTitle:MALocalizedString(@"Пресет сервера")
	                                                   delegate:self
	                                          cancelButtonTitle:nil
	                                     destructiveButtonTitle:nil
	                                          otherButtonTitles:nil];
	[[MATheme sharedTheme] styleActionSheet:sheet];
	for (NSDictionary *preset in [MALocalProvider presets]) {
		[sheet addButtonWithTitle:preset[@"name"]];
	}
	sheet.cancelButtonIndex = [sheet addButtonWithTitle:MALocalizedString(@"Отмена")];
	[sheet showInView:self.view];
}

// Подставляет адрес вида http://<хост>:<порт>/v1. Хост берётся из уже введённого адреса;
// если его нет — ставится образец, и фокус уходит в поле, чтобы вписать IP своего ПК.
- (void)actionSheet:(UIActionSheet *)actionSheet didDismissWithButtonIndex:(NSInteger)buttonIndex {
	NSArray *presets = [MALocalProvider presets];
	if (buttonIndex == actionSheet.cancelButtonIndex || buttonIndex < 0 || buttonIndex >= (NSInteger)presets.count) return;

	[self commitFieldValues];
	NSString *host = [self hostOfBaseURL:self.provider.baseURLString];
	BOOL hadHost = (host.length > 0);
	if (!hadHost) host = @"192.168.0.100";

	self.provider.baseURLString = [NSString stringWithFormat:@"http://%@:%@/v1", host, presets[buttonIndex][@"port"]];
	[self reloadFields];

	if (!hadHost) {
		dispatch_async(dispatch_get_main_queue(), ^{
			[self.baseURLField becomeFirstResponder];
		});
	}
}

- (NSString *)hostOfBaseURL:(NSString *)baseURL {
	NSString *base = [self trimmed:baseURL];
	if (base.length == 0) return nil;
	if ([base rangeOfString:@"://"].location == NSNotFound) base = [@"http://" stringByAppendingString:base];
	NSURL *url = [NSURL URLWithString:base]; // в SDK 6.1 метод возвращает id — точка у результата не компилируется
	return url.host;
}

// Запрашивает у сервера список моделей: заодно это проверка, что телефон до него достучался.
- (void)checkConnection {
	if (self.checkingConnection || ![self isLocalServer]) return;

	[self.view endEditing:YES];
	[self commitFieldValues];

	MALocalProvider *local = (MALocalProvider *)self.provider;
	if (local.baseURLString.length == 0) {
		[self showAlertWithTitle:MALocalizedString(@"Ошибка") message:MALocalizedString(@"Сначала укажите адрес сервера.")];
		return;
	}

	self.checkingConnection = YES;
	[self reloadFields];

	__weak typeof(self) weakSelf = self;
	[local fetchModelsWithCompletion:^(NSArray *models, NSError *error) {
		__strong typeof(weakSelf) strongSelf = weakSelf;
		if (!strongSelf) return;

		strongSelf.checkingConnection = NO;
		[strongSelf reloadFields];
		if (!strongSelf.view.window) return; // экран уже закрыли

		if (error) {
			[strongSelf showAlertWithTitle:MALocalizedString(@"Ошибка") message:error.localizedDescription];
			return;
		}
		if (models.count == 0) {
			[strongSelf showAlertWithTitle:MALocalizedString(@"Модели не найдены")
			                       message:MALocalizedString(@"Сервер отвечает, но список моделей пуст. Загрузите модель на сервере (например, ollama pull) и повторите.")];
			return;
		}

		MAModelPickerViewController *picker = [[MAModelPickerViewController alloc]
			initWithModels:models
			 selectedModel:strongSelf.provider.model
			      onSelect:^(NSString *model) {
			__strong typeof(weakSelf) innerSelf = weakSelf;
			if (!innerSelf) return;
			innerSelf.provider.model = model;
			if (innerSelf.saveBlock) innerSelf.saveBlock();
			[innerSelf reloadFields];
		}];
		[strongSelf.navigationController pushViewController:picker animated:YES];
	}];
}

- (void)showAlertWithTitle:(NSString *)title message:(NSString *)message {
	UIAlertView *alert = [[UIAlertView alloc] initWithTitle:title message:message delegate:nil cancelButtonTitle:@"OK" otherButtonTitles:nil];
	[alert show];
}

#pragma mark - UITextFieldDelegate

- (BOOL)textFieldShouldReturn:(UITextField *)textField {
	[textField resignFirstResponder];
	return YES;
}

@end
