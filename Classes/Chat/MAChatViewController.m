#import "MAChatViewController.h"
#import "MALocalization.h"
#import "MATheme.h"
#import "MAChatMessageCell.h"
#import "MAChatImageCell.h"
#import "MAChatItem.h"
#import "MAProviderRegistry.h"
#import "MAImageProviderRegistry.h"
#import "MAProvider.h"
#import "MAImageProvider.h"
#import "MAMessage.h"
#import "MAChatSession.h"
#import "MAChatHistoryStore.h"
#import "MAPrivacySettings.h"
#import "MAWallpaperStore.h"
#import "MAVoiceService.h"
#import "MAInstructionsStore.h"
#import <QuartzCore/QuartzCore.h>

static NSString *const kMessageCellIdentifier = @"MessageCell";
static NSString *const kImageCellIdentifier = @"ImageCell";
static const CGFloat kInputBarHeight = 44.0;
static const CGFloat kAttachmentBarHeight = 60.0;

@interface MAChatViewController () <UITableViewDataSource, UITableViewDelegate, UITextFieldDelegate,
                                     UIActionSheetDelegate, UIImagePickerControllerDelegate, UINavigationControllerDelegate>

@property (nonatomic, strong) UIImageView *backgroundImageView;
@property (nonatomic, strong) UITableView *tableView;
@property (nonatomic, strong) UIView *inputBar;
@property (nonatomic, strong) UIButton *plusButton;
@property (nonatomic, strong) UITextField *inputField;
@property (nonatomic, strong) UIButton *sendButton;

// Голосовой режим: микрофон запускает/останавливает запись, распознанный
// текст сразу отправляется, а ответ ИИ озвучивается (см. MAVoiceService).
@property (nonatomic, strong) UIButton *micButton;
@property (nonatomic, assign) BOOL nextSendIsVoice;
@property (nonatomic, assign) BOOL isTranscribing;
@property (nonatomic, strong) NSMutableArray *items; // MAChatItem*
@property (nonatomic, assign) BOOL isSending;
@property (nonatomic, assign) CGFloat keyboardHeight;

// Плейсхолдер по центру ленты, пока в чате ещё нет ни одного сообщения —
// "Привет! Я <провайдер>\nНапиши сообщение.". Скрывается, как только
// появляется первый item, и обновляет текст при смене активного провайдера
// (см. -updateEmptyState).
@property (nonatomic, strong) UILabel *emptyStateLabel;

// Сессия истории, в которую пишется текущая переписка. nil, пока не
// отправлено первое сообщение — создаётся лениво в -persistCurrentSession.
@property (nonatomic, strong) MAChatSession *currentSession;
// YES, если эта переписка шла (хотя бы частично) в режиме инкогнито: она не
// пишется в историю до «Нового чата», даже если режим уже выключили.
@property (nonatomic, assign) BOOL incognitoConversation;
// YES, если экран экран открыт из MAChatHistoryViewController (тогда это не корень
// вкладки "Chat", у него уже есть системная кнопка "Назад", а "Новый чат"
// не нужен).
@property (nonatomic, assign) BOOL openedFromHistory;
@property (nonatomic, assign) BOOL hasScrolledToInitialBottom;

// Фото, выбранное через "+", но ещё не отправленное — показывается
// превью-плашкой над полем ввода, пока пользователь не нажмёт "Отправить"
// (или не уберёт его крестиком).
@property (nonatomic, strong) UIView *attachmentBar;
@property (nonatomic, strong) UIImageView *attachmentThumbnail;
@property (nonatomic, strong) UIButton *attachmentRemoveButton;
@property (nonatomic, strong) UIImage *pendingImage;

// Действия текущего меню "+", по одному блоку на кнопку — так порядок кнопок
// в UIActionSheet не приходится дублировать хардкодом индексов в делегате,
// список доступных опций всё равно зависит от возможностей устройства
// (симулятор и iPod touch без камеры не показывают пункт "Сделать фото").
@property (nonatomic, strong) NSArray *plusMenuActions;

@end

@implementation MAChatViewController

- (instancetype)init {
	self = [super init];
	if (self) {
		_items = [NSMutableArray array];
	}
	return self;
}

- (instancetype)initWithSession:(MAChatSession *)session {
	self = [super init];
	if (self) {
		_currentSession = session;
		_openedFromHistory = YES;

		NSMutableArray *items = [NSMutableArray arrayWithCapacity:session.messages.count];
		for (MAMessage *message in session.messages) {
			[items addObject:[MAChatItem textItemWithMessage:message]];
		}
		_items = items;
	}
	return self;
}

- (void)dealloc {
	[[NSNotificationCenter defaultCenter] removeObserver:self];
}

#pragma mark - Lifecycle

- (void)viewDidLoad {
	[super viewDidLoad];
	self.view.backgroundColor = [MATheme sharedTheme].backgroundColor;

	self.navigationItem.rightBarButtonItem =
		[[UIBarButtonItem alloc] initWithTitle:MALocalizedString(@"Провайдер")
		                                  style:UIBarButtonItemStylePlain
		                                 target:self
		                                 action:@selector(showProviderPicker)];

	if (!self.openedFromHistory) {
		// На вкладке-корне "Chat" — кнопка сброса на чистый лист (старая
		// переписка к этому моменту уже сохранена в историю, см.
		// -persistCurrentSession, так что ничего не теряется).
		UIBarButtonItem *newChatItem =
			[[UIBarButtonItem alloc] initWithTitle:@"+"
			                                  style:UIBarButtonItemStylePlain
			                                 target:self
			                                 action:@selector(newChatTapped)];
		// Вместо подписи «Новый чат» — просто «+»; для VoiceOver оставляем понятное название.
		newChatItem.accessibilityLabel = MALocalizedString(@"Новый чат");
		self.navigationItem.leftBarButtonItem = newChatItem;
	}

	[self setupBackgroundImageView];
	[self setupTableView];
	[self setupInputBar];
	[self setupAttachmentBar];
	[self updateTitleWithActiveProvider];

	[[NSNotificationCenter defaultCenter] addObserver:self
	                                          selector:@selector(keyboardWillShow:)
	                                              name:UIKeyboardWillShowNotification
	                                            object:nil];
	[[NSNotificationCenter defaultCenter] addObserver:self
	                                          selector:@selector(keyboardWillHide:)
	                                              name:UIKeyboardWillHideNotification
	                                            object:nil];
	[[NSNotificationCenter defaultCenter] addObserver:self
	                                          selector:@selector(voiceStateDidChange:)
	                                              name:MAVoiceStateDidChangeNotification
	                                            object:nil];
	[[NSNotificationCenter defaultCenter] addObserver:self
	                                          selector:@selector(wallpaperDidChange:)
	                                              name:MAWallpaperDidChangeNotification
	                                            object:nil];
	[[NSNotificationCenter defaultCenter] addObserver:self
	                                          selector:@selector(languageDidChange:)
	                                              name:MALanguageDidChangeNotification
	                                            object:nil];
	[[NSNotificationCenter defaultCenter] addObserver:self
	                                          selector:@selector(themeDidChange:)
	                                              name:MAThemeDidChangeNotification
	                                            object:nil];
	[[NSNotificationCenter defaultCenter] addObserver:self
	                                          selector:@selector(incognitoDidChange:)
	                                              name:MAIncognitoDidChangeNotification
	                                            object:nil];
}

- (void)viewWillAppear:(BOOL)animated {
	[super viewWillAppear:animated];
	[self updateTitleWithActiveProvider];
	[self refreshBackgroundImage];

	// Пока экран на виду — ошибки озвучки показываем именно на нём.
	__weak typeof(self) weakSelf = self;
	[MAVoiceService sharedService].errorHandler = ^(NSString *message) {
		[weakSelf showAlertWithTitle:MALocalizedString(@"Голос") message:message];
	};
	[self updateActionButtons];
}

- (void)viewDidAppear:(BOOL)animated {
	[super viewDidAppear:animated];
	if (!self.hasScrolledToInitialBottom) {
		self.hasScrolledToInitialBottom = YES;
		[self scrollToBottomAnimated:NO];
	}
}

- (void)viewDidLayoutSubviews {
	[super viewDidLayoutSubviews];
	[self layoutContentViews];
}

#pragma mark - Setup

- (void)setupBackgroundImageView {
	self.backgroundImageView = [[UIImageView alloc] initWithFrame:self.view.bounds];
	self.backgroundImageView.contentMode = UIViewContentModeScaleAspectFill;
	self.backgroundImageView.clipsToBounds = YES;
	self.backgroundImageView.autoresizingMask = UIViewAutoresizingFlexibleWidth | UIViewAutoresizingFlexibleHeight;
	[self.view addSubview:self.backgroundImageView];
	[self refreshBackgroundImage];
}

// И ячейки сообщений (MAChatMessageCell/MAChatImageCell), и сам UITableView —
// прозрачные, поэтому обои снизу видно сквозь весь стек без доп. правок в
// ячейках; меняется только этот метод.
- (void)refreshBackgroundImage {
	UIImage *wallpaper = [[MAWallpaperStore sharedStore] wallpaperImage];
	self.backgroundImageView.image = wallpaper;
	self.backgroundImageView.hidden = (wallpaper == nil);
	self.view.backgroundColor = wallpaper ? [UIColor blackColor] : [MATheme sharedTheme].backgroundColor;
}

- (void)wallpaperDidChange:(NSNotification *)notification {
	[self refreshBackgroundImage];
}

- (void)setupTableView {
	self.tableView = [[UITableView alloc] initWithFrame:CGRectZero style:UITableViewStylePlain];
	self.tableView.dataSource = self;
	self.tableView.delegate = self;
	self.tableView.backgroundColor = [UIColor clearColor];
	self.tableView.separatorStyle = UITableViewCellSeparatorStyleNone;
	self.tableView.autoresizingMask = UIViewAutoresizingFlexibleWidth | UIViewAutoresizingFlexibleHeight;
	[self.tableView registerClass:[MAChatMessageCell class] forCellReuseIdentifier:kMessageCellIdentifier];
	[self.tableView registerClass:[MAChatImageCell class] forCellReuseIdentifier:kImageCellIdentifier];
	[self.view addSubview:self.tableView];

	// Тап по ленте убирает клавиатуру. cancelsTouchesInView = NO, чтобы не ломать
	// кнопки в ячейках (копировать/редактировать) и выделение.
	UITapGestureRecognizer *dismissTap = [[UITapGestureRecognizer alloc] initWithTarget:self
	                                                                               action:@selector(dismissKeyboardTapped)];
	dismissTap.cancelsTouchesInView = NO;
	[self.tableView addGestureRecognizer:dismissTap];

	self.emptyStateLabel = [[UILabel alloc] init];
	self.emptyStateLabel.numberOfLines = 0;
	self.emptyStateLabel.textAlignment = NSTextAlignmentCenter;
	self.emptyStateLabel.font = [UIFont systemFontOfSize:16];
	self.emptyStateLabel.textColor = [MATheme sharedTheme].secondaryTextColor;
	self.emptyStateLabel.backgroundColor = [UIColor clearColor];
	self.emptyStateLabel.autoresizingMask = UIViewAutoresizingFlexibleWidth | UIViewAutoresizingFlexibleHeight;
	[self.view addSubview:self.emptyStateLabel];
	[self updateEmptyState];
}

- (void)setupInputBar {
	self.inputBar = [[UIView alloc] init];
	self.inputBar.backgroundColor = [MATheme sharedTheme].inputBarColor;
	self.inputBar.autoresizingMask = UIViewAutoresizingFlexibleWidth | UIViewAutoresizingFlexibleTopMargin;

	// Кнопки — готовые круглые текстуры (Resources/Plus, Mic, MicRec, Send + @2x/@3x).
	// Сама картинка 28pt, а область нажатия — вся высота панели (см. layoutContentViews).
	self.plusButton = [UIButton buttonWithType:UIButtonTypeCustom];
	[self.plusButton setImage:[UIImage imageNamed:@"Plus"] forState:UIControlStateNormal];
	[self.plusButton addTarget:self action:@selector(plusTapped) forControlEvents:UIControlEventTouchUpInside];

	self.inputField = [[UITextField alloc] init];
	self.inputField.borderStyle = UITextBorderStyleRoundedRect;
	self.inputField.placeholder = MALocalizedString(@"Сообщение…");
	self.inputField.delegate = self;
	self.inputField.autoresizingMask = UIViewAutoresizingFlexibleWidth;
	self.inputField.returnKeyType = UIReturnKeySend;
	self.inputField.keyboardAppearance = [MATheme sharedTheme].keyboardAppearance;
	self.inputField.enablesReturnKeyAutomatically = YES;
	// Пустое поле — справа микрофон, есть текст — «Отправить».
	[self.inputField addTarget:self action:@selector(inputTextChanged) forControlEvents:UIControlEventEditingChanged];

	self.sendButton = [UIButton buttonWithType:UIButtonTypeCustom];
	[self.sendButton setImage:[UIImage imageNamed:@"Send"] forState:UIControlStateNormal];
	[self.sendButton addTarget:self action:@selector(sendTapped) forControlEvents:UIControlEventTouchUpInside];
	self.sendButton.autoresizingMask = UIViewAutoresizingFlexibleLeftMargin;

	self.micButton = [UIButton buttonWithType:UIButtonTypeCustom];
	self.micButton.autoresizingMask = UIViewAutoresizingFlexibleLeftMargin;
	[self.micButton addTarget:self action:@selector(micTapped) forControlEvents:UIControlEventTouchUpInside];
	[self updateActionButtons];

	[self.inputBar addSubview:self.plusButton];
	[self.inputBar addSubview:self.inputField];
	[self.inputBar addSubview:self.micButton];
	[self.inputBar addSubview:self.sendButton];
	[self.view addSubview:self.inputBar];
}

- (void)setupAttachmentBar {
	self.attachmentBar = [[UIView alloc] init];
	self.attachmentBar.backgroundColor = [MATheme sharedTheme].inputBarColor;
	self.attachmentBar.hidden = YES;
	self.attachmentBar.autoresizingMask = UIViewAutoresizingFlexibleWidth | UIViewAutoresizingFlexibleTopMargin;

	UIView *topBorder = [[UIView alloc] initWithFrame:CGRectMake(0, 0, 0, 0.5)];
	topBorder.backgroundColor = [MATheme sharedTheme].inputBarBorderColor;
	topBorder.autoresizingMask = UIViewAutoresizingFlexibleWidth | UIViewAutoresizingFlexibleBottomMargin;
	topBorder.tag = 999;

	self.attachmentThumbnail = [[UIImageView alloc] init];
	self.attachmentThumbnail.contentMode = UIViewContentModeScaleAspectFill;
	self.attachmentThumbnail.clipsToBounds = YES;
	self.attachmentThumbnail.layer.cornerRadius = 6.0;
	self.attachmentThumbnail.layer.masksToBounds = YES;
	self.attachmentThumbnail.backgroundColor = [MATheme sharedTheme].thumbnailPlaceholderColor;

	self.attachmentRemoveButton = [UIButton buttonWithType:UIButtonTypeRoundedRect];
	[self.attachmentRemoveButton setTitle:MALocalizedString(@"Убрать фото") forState:UIControlStateNormal];
	[self.attachmentRemoveButton addTarget:self action:@selector(removePendingImage) forControlEvents:UIControlEventTouchUpInside];

	[self.attachmentBar addSubview:topBorder];
	[self.attachmentBar addSubview:self.attachmentThumbnail];
	[self.attachmentBar addSubview:self.attachmentRemoveButton];
	[self.view addSubview:self.attachmentBar];
}

- (void)layoutContentViews {
	CGRect bounds = self.view.bounds;
	CGFloat attachmentHeight = self.pendingImage ? kAttachmentBarHeight : 0;

	CGFloat bottomY = bounds.size.height - self.keyboardHeight;
	CGFloat inputBarY = bottomY - kInputBarHeight;
	CGFloat attachmentBarY = inputBarY - attachmentHeight;

	self.inputBar.frame = CGRectMake(0, inputBarY, bounds.size.width, kInputBarHeight);
	self.attachmentBar.frame = CGRectMake(0, attachmentBarY, bounds.size.width, attachmentHeight);
	self.attachmentBar.hidden = (attachmentHeight == 0);
	self.tableView.frame = CGRectMake(0, 0, bounds.size.width, attachmentBarY);

	CGFloat emptyStateInset = 32;
	CGSize emptyStateSize = [self.emptyStateLabel sizeThatFits:CGSizeMake(bounds.size.width - 2 * emptyStateInset, CGFLOAT_MAX)];
	self.emptyStateLabel.frame = CGRectMake(emptyStateInset,
	                                         (attachmentBarY - emptyStateSize.height) / 2.0,
	                                         bounds.size.width - 2 * emptyStateInset,
	                                         emptyStateSize.height);

	CGFloat margin = 8;
	CGFloat buttonWidth = 40; // картинка 28pt по центру, остальное — запас на попадание пальцем
	CGFloat edge = 4;

	// «Отправить» и микрофон занимают одно и то же место — виден один из двух.
	CGFloat actionX = bounds.size.width - buttonWidth - edge;
	CGFloat fieldX = edge + buttonWidth + 2;

	self.plusButton.frame = CGRectMake(edge, 0, buttonWidth, kInputBarHeight);
	self.sendButton.frame = CGRectMake(actionX, 0, buttonWidth, kInputBarHeight);
	self.micButton.frame = CGRectMake(actionX, 0, buttonWidth, kInputBarHeight);
	self.inputField.frame = CGRectMake(fieldX, 6, actionX - 2 - fieldX, kInputBarHeight - 12);

	if (attachmentHeight > 0) {
		CGFloat thumbSize = kAttachmentBarHeight - 2 * margin;
		self.attachmentThumbnail.image = self.pendingImage;
		self.attachmentThumbnail.frame = CGRectMake(margin, margin, thumbSize, thumbSize);
		[self.attachmentRemoveButton sizeToFit];
		CGFloat removeX = margin * 2 + thumbSize;
		self.attachmentRemoveButton.frame = CGRectMake(removeX, (kAttachmentBarHeight - 30) / 2.0,
		                                                bounds.size.width - removeX - margin, 30);
	}
}

#pragma mark - Keyboard

- (void)keyboardWillShow:(NSNotification *)notification {
	NSDictionary *info = notification.userInfo;
	CGRect keyboardFrameEnd = [info[UIKeyboardFrameEndUserInfoKey] CGRectValue];
	CGRect keyboardFrameInView = [self.view convertRect:keyboardFrameEnd fromView:nil];
	CGFloat overlap = CGRectGetMaxY(self.view.bounds) - CGRectGetMinY(keyboardFrameInView);
	self.keyboardHeight = MAX(overlap, 0);
	[self animateKeyboardChangeWithNotification:notification];
}

- (void)keyboardWillHide:(NSNotification *)notification {
	self.keyboardHeight = 0;
	[self animateKeyboardChangeWithNotification:notification];
}

- (void)animateKeyboardChangeWithNotification:(NSNotification *)notification {
	NSDictionary *info = notification.userInfo;
	NSTimeInterval duration = [info[UIKeyboardAnimationDurationUserInfoKey] doubleValue];
	NSInteger curve = [info[UIKeyboardAnimationCurveUserInfoKey] integerValue];

	[UIView animateWithDuration:duration
	                      delay:0
	                    options:(curve << 16)
	                 animations:^{
		[self layoutContentViews];
	}
	                 completion:^(BOOL finished) {
		[self scrollToBottomAnimated:NO];
	}];
}

#pragma mark - Отправка сообщения (текст и/или фото)

- (void)setPendingImage:(UIImage *)pendingImage {
	_pendingImage = pendingImage;
	[self layoutContentViews];
	[self updateActionButtons];
}

- (void)removePendingImage {
	self.pendingImage = nil;
}

- (void)sendTapped {
	NSString *text = [self.inputField.text stringByTrimmingCharactersInSet:[NSCharacterSet whitespaceAndNewlineCharacterSet]];
	UIImage *image = self.pendingImage;
	if (text.length == 0 && !image) return;
	if (self.isSending) return;

	// Озвучиваем ответ, если включено «Озвучивать все ответы» или вопрос
	// был надиктован голосом. Старую озвучку при новом сообщении обрываем.
	[[MAVoiceService sharedService] stopSpeaking];
	BOOL speakReply = self.nextSendIsVoice || [MAVoiceService sharedService].autoSpeak;
	self.nextSendIsVoice = NO;

	MAMessage *userMessage = [MAMessage messageWithRole:MAMessageRoleUser content:text image:image];
	[self.items addObject:[MAChatItem textItemWithMessage:userMessage]];
	self.inputField.text = @"";
	self.pendingImage = nil; // заодно обновит кнопки справа
	[self updateActionButtons];
	[self updateEmptyState];
	[self.tableView reloadData];
	[self scrollToBottomAnimated:YES];
	[self persistCurrentSession];

	id<MAProvider> provider = [MAProviderRegistry sharedRegistry].activeProvider;
	if (!provider) {
		[self showAlertWithTitle:MALocalizedString(@"Нет провайдера") message:MALocalizedString(@"Выбери провайдера кнопкой сверху или в Settings.")];
		return;
	}

	self.isSending = YES;
	self.sendButton.enabled = NO;

	NSArray *historySnapshot = [self providerMessages];

	// «Инструкция» из Settings уходит первым системным сообщением. Только в запрос:
	// в ленту и в сохранённую историю оно не попадает, поэтому правка инструкции
	// действует и на старые беседы, которые продолжаешь.
	NSString *instructions = [[MAInstructionsStore sharedStore] activeInstructions];
	if (instructions.length > 0) {
		NSMutableArray *withInstructions = [NSMutableArray arrayWithCapacity:historySnapshot.count + 1];
		[withInstructions addObject:[MAMessage messageWithRole:MAMessageRoleSystem content:instructions]];
		[withInstructions addObjectsFromArray:historySnapshot];
		historySnapshot = withInstructions;
	}

	__weak typeof(self) weakSelf = self;
	[provider sendMessages:historySnapshot completion:^(NSString *replyText, NSError *error) {
		__strong typeof(weakSelf) strongSelf = weakSelf;
		if (!strongSelf) return;

		strongSelf.isSending = NO;
		strongSelf.sendButton.enabled = YES;

		if (error) {
			[strongSelf showAlertWithTitle:MALocalizedString(@"Ошибка") message:error.localizedDescription];
			return;
		}

		MAMessage *assistantMessage = [MAMessage messageWithRole:MAMessageRoleAssistant content:(replyText ?: @"")];
		[strongSelf.items addObject:[MAChatItem textItemWithMessage:assistantMessage]];
		[strongSelf updateEmptyState];
		[strongSelf.tableView reloadData];
		[strongSelf scrollToBottomAnimated:YES];
		[strongSelf persistCurrentSession];

		if (speakReply) {
			[[MAVoiceService sharedService] speakText:replyText];
		}
	}];
}

#pragma mark - Голос

// Справа от поля ввода — одна из двух кнопок:
//  • поле пустое (и нет прикреплённого фото) — микрофон;
//  • есть текст или фото — «Отправить».
// Пока идёт запись или распознавание, всегда показываем микрофон, чтобы её можно
// было остановить, даже если в поле что-то успели набрать.
- (BOOL)shouldShowSendButton {
	MAVoiceService *voice = [MAVoiceService sharedService];
	if (voice.recording || self.isTranscribing) return NO;

	NSString *text = [self.inputField.text stringByTrimmingCharactersInSet:[NSCharacterSet whitespaceAndNewlineCharacterSet]];
	return text.length > 0 || self.pendingImage != nil;
}

- (void)updateActionButtons {
	MAVoiceService *voice = [MAVoiceService sharedService];

	// Красный микрофон — идёт запись или ИИ говорит: тап по кнопке всё остановит.
	BOOL stopState = voice.recording || voice.speaking;
	[self.micButton setImage:[UIImage imageNamed:(stopState ? @"MicRec" : @"Mic")] forState:UIControlStateNormal];
	self.micButton.enabled = !self.isTranscribing; // при распознавании кнопка тускнеет

	BOOL showSend = [self shouldShowSendButton];
	self.sendButton.hidden = !showSend;
	self.micButton.hidden = showSend;
}

- (void)inputTextChanged {
	[self updateActionButtons];
}

- (void)voiceStateDidChange:(NSNotification *)notification {
	[self updateActionButtons];
}

// Тему сменили в настройках: перекрашиваем панели и перерисовываем переписку
// (пузыри и цвет текста берутся из темы при настройке ячейки).
- (void)themeDidChange:(NSNotification *)notification {
	MATheme *theme = [MATheme sharedTheme];
	[self refreshBackgroundImage];
	self.emptyStateLabel.textColor = theme.secondaryTextColor;
	self.inputBar.backgroundColor = theme.inputBarColor;
	self.attachmentBar.backgroundColor = theme.inputBarColor;
	[self.attachmentBar viewWithTag:999].backgroundColor = theme.inputBarBorderColor;
	self.attachmentThumbnail.backgroundColor = theme.thumbnailPlaceholderColor;
	self.inputField.keyboardAppearance = theme.keyboardAppearance;
	[self.tableView reloadData];
}

// Режим инкогнито переключили, пока чат открыт. Если в ленте уже есть
// переписка, она с этого момента больше не обновляется в истории (то, что
// успело сохраниться до переключения, остаётся как было).
- (void)incognitoDidChange:(NSNotification *)notification {
	if ([MAPrivacySettings sharedSettings].incognito && self.items.count > 0) {
		self.incognitoConversation = YES;
		self.currentSession = nil;
	}
	[self updateTitleWithActiveProvider]; // значок в заголовке и текст пустого чата
}

// Язык интерфейса сменили, пока чат открыт: обновляем подписи, не трогая переписку.
- (void)languageDidChange:(NSNotification *)notification {
	self.navigationItem.rightBarButtonItem.title = MALocalizedString(@"Провайдер");
	self.navigationItem.leftBarButtonItem.accessibilityLabel = MALocalizedString(@"Новый чат");
	self.inputField.placeholder = MALocalizedString(@"Сообщение…");
	[self.attachmentRemoveButton setTitle:MALocalizedString(@"Убрать фото") forState:UIControlStateNormal];
	[self updateTitleWithActiveProvider]; // заодно перерисует приветствие пустого чата
	[self.view setNeedsLayout];
}

// Один тап — начать запись, второй — остановить, распознать и отправить.
// Если ИИ сейчас говорит, тап по кнопке его затыкает.
- (void)micTapped {
	MAVoiceService *voice = [MAVoiceService sharedService];

	if (voice.speaking) {
		[voice stopSpeaking];
		return;
	}
	if (self.isTranscribing) return;

	[self.inputField resignFirstResponder];

	__weak typeof(self) weakSelf = self;

	if (voice.recording) {
		self.isTranscribing = YES;
		[self updateActionButtons];
		[voice finishRecordingAndTranscribe:^(NSString *text, NSError *error) {
			__strong typeof(weakSelf) strongSelf = weakSelf;
			if (!strongSelf) return;

			strongSelf.isTranscribing = NO;
			[strongSelf updateActionButtons];

			if (error) {
				[strongSelf showAlertWithTitle:MALocalizedString(@"Голос") message:error.localizedDescription];
				return;
			}
			strongSelf.inputField.text = text;
			[strongSelf updateActionButtons];
			strongSelf.nextSendIsVoice = YES;
			[strongSelf sendTapped];
			strongSelf.nextSendIsVoice = NO; // если sendTapped ушёл в guard — не оставляем флаг висеть
		}];
		return;
	}

	[voice startRecordingWithCompletion:^(NSError *error) {
		if (error) {
			[weakSelf showAlertWithTitle:MALocalizedString(@"Голос") message:error.localizedDescription];
		}
	}];
}

#pragma mark - История (автосохранение и сброс на новый чат)

// Сохраняет/обновляет текущую переписку в MAChatHistoryStore. Сессия
// создаётся лениво при первом сообщении, а название беседы выводится из
// первого сообщения пользователя (обрезается до ~40 символов).
- (void)persistCurrentSession {
	NSArray *providerMessages = [self providerMessages];
	if (providerMessages.count == 0) return;
	if ([self shouldSkipPersisting]) return;

	if (!self.currentSession) {
		self.currentSession = [[MAChatSession alloc] init];
	}
	self.currentSession.messages = providerMessages;
	self.currentSession.updatedAt = [NSDate date];
	self.currentSession.title = [self titleFromProviderMessages:providerMessages];

	[[MAChatHistoryStore sharedStore] saveSession:self.currentSession];
}

// YES, если эту переписку нельзя писать в историю: включён режим инкогнито
// или беседа уже шла в нём. Попутно запоминает, что беседа «инкогнито», чтобы
// после выключения режима она не попала в историю вместе со всем, что в ней было.
- (BOOL)shouldSkipPersisting {
	if ([MAPrivacySettings sharedSettings].incognito) {
		if (self.items.count > 0) self.incognitoConversation = YES;
		return YES;
	}
	return self.incognitoConversation;
}

// Беседа идёт «не для записи»: для значка в заголовке.
- (BOOL)isIncognitoNow {
	return [MAPrivacySettings sharedSettings].incognito || self.incognitoConversation;
}

- (NSString *)titleFromProviderMessages:(NSArray *)messages {
	for (MAMessage *message in messages) {
		if (message.role == MAMessageRoleUser && message.content.length > 0) {
			NSString *trimmed = [message.content stringByTrimmingCharactersInSet:[NSCharacterSet whitespaceAndNewlineCharacterSet]];
			if (trimmed.length > 40) {
				trimmed = [[trimmed substringToIndex:40] stringByAppendingString:@"…"];
			}
			return trimmed;
		}
	}
	return @"Новый чат";
}

- (void)newChatTapped {
	[[MAVoiceService sharedService] stopSpeaking];
	if (self.items.count == 0) return; // уже чистый лист — сбрасывать нечего

	// Системный "curl" — та самая классическая анимация переворота
	// страницы (как в старых Notes/Reminders). transitionWithView:
	// сама снимает "снимок" текущего состояния tableView, а внутри
	// animations-блока мы меняем данные и вызываем reloadData — на
	// новый (уже пустой) экран нас "переворачивает" анимация.
	[UIView transitionWithView:self.tableView
	                   duration:0.6
	                    options:UIViewAnimationOptionTransitionCurlUp
	                 animations:^{
		self.items = [NSMutableArray array];
		self.currentSession = nil;
		self.incognitoConversation = NO; // чистый лист: дальше решает сам переключатель
		self.pendingImage = nil;
		[self updateTitleWithActiveProvider]; // заодно обновит пустое состояние
		[self.tableView reloadData];
	}
	                 completion:nil];
}

// История для LLM собирается только из текстовых элементов ленты — карточки
// со сгенерированными картинками (MAChatItemKindImage, результат /generateImage)
// в неё не попадают. А вот фото, которое пользователь сам прикрепил к
// сообщению, — это MAMessage.image внутри обычного текстового item'а, и оно
// уходит провайдеру как часть запроса (см. MAOpenAICompatibleProvider/MAClaudeProvider).
- (NSArray *)providerMessages {
	NSMutableArray *messages = [NSMutableArray array];
	for (MAChatItem *item in self.items) {
		if (item.kind == MAChatItemKindText && item.message) {
			[messages addObject:item.message];
		}
	}
	return messages;
}

#pragma mark - Редактирование сообщения

// Правит уже отправленное сообщение пользователя. Само сообщение и всё, что
// шло после него в ленте (включая ответ ассистента на него), убирается —
// иначе редактирование могло бы оставить в истории ответ, который относится
// к уже не существующему тексту. Текст/фото возвращаются в поле ввода,
// дальше это обычное новое сообщение: можно поправить и отправить заново.
- (void)beginEditingMessageAtIndex:(NSInteger)index {
	if (self.isSending) return; // не мешаем уже идущему запросу
	if (index < 0 || index >= (NSInteger)self.items.count) return;

	MAChatItem *item = self.items[index];
	if (item.kind != MAChatItemKindText || item.message.role != MAMessageRoleUser) return;

	MAMessage *message = item.message;
	NSRange rangeToRemove = NSMakeRange(index, self.items.count - index);
	[self.items removeObjectsInRange:rangeToRemove];

	self.inputField.text = message.content;
	self.pendingImage = message.image;
	[self updateActionButtons];

	[self updateEmptyState];
	[self.tableView reloadData];
	[self layoutContentViews];

	if (self.items.count == 0) {
		// Удалили вообще всё — хранить в истории пустую сессию незачем,
		// убираем её целиком, как будто беседы и не было. В инкогнито историю
		// не трогаем: сохранённая беседа, открытая из истории, остаётся на месте.
		if (self.currentSession && ![self shouldSkipPersisting]) {
			[[MAChatHistoryStore sharedStore] deleteSession:self.currentSession];
		}
		self.currentSession = nil;
		self.incognitoConversation = NO;
		[self updateTitleWithActiveProvider];
	} else {
		[self persistCurrentSession];
	}

	[self.inputField becomeFirstResponder];
}

#pragma mark - Меню "+" (генерация фото и прикрепление своего)

- (void)plusTapped {
	[self.inputField resignFirstResponder];

	NSMutableArray *titles = [NSMutableArray array];
	NSMutableArray *actions = [NSMutableArray array];
	__weak typeof(self) weakSelf = self;

	[titles addObject:MALocalizedString(@"Сгенерировать фото")];
	[actions addObject:[^{ [weakSelf startImageGenerationFromInputField]; } copy]];

	if ([UIImagePickerController isSourceTypeAvailable:UIImagePickerControllerSourceTypeCamera]) {
		[titles addObject:MALocalizedString(@"Сделать фото")];
		[actions addObject:[^{ [weakSelf presentImagePickerWithSourceType:UIImagePickerControllerSourceTypeCamera]; } copy]];
	}
	if ([UIImagePickerController isSourceTypeAvailable:UIImagePickerControllerSourceTypePhotoLibrary]) {
		[titles addObject:MALocalizedString(@"Прикрепить фото из галереи")];
		[actions addObject:[^{ [weakSelf presentImagePickerWithSourceType:UIImagePickerControllerSourceTypePhotoLibrary]; } copy]];
	}

	self.plusMenuActions = actions;

	UIActionSheet *sheet = [[UIActionSheet alloc] initWithTitle:nil
	                                                     delegate:self
	                                            cancelButtonTitle:nil
	                                       destructiveButtonTitle:nil
	                                            otherButtonTitles:nil];
	for (NSString *title in titles) {
		[sheet addButtonWithTitle:title];
	}
	sheet.tag = 100; // отличаем от action sheet выбора провайдера
	[[MATheme sharedTheme] styleActionSheet:sheet];
	NSInteger cancelIndex = [sheet addButtonWithTitle:MALocalizedString(@"Отмена")];
	sheet.cancelButtonIndex = cancelIndex;
	[sheet showInView:self.view];
}

- (void)startImageGenerationFromInputField {
	NSString *prompt = [self.inputField.text stringByTrimmingCharactersInSet:[NSCharacterSet whitespaceAndNewlineCharacterSet]];
	if (prompt.length == 0) {
		[self showAlertWithTitle:MALocalizedString(@"Пустой запрос") message:MALocalizedString(@"Сначала напиши в поле ввода, что за фото нужно.")];
		return;
	}
	[self startImageGenerationWithPrompt:prompt];
}

- (void)presentImagePickerWithSourceType:(UIImagePickerControllerSourceType)sourceType {
	UIImagePickerController *picker = [[UIImagePickerController alloc] init];
	picker.sourceType = sourceType;
	picker.delegate = self;
	picker.allowsEditing = NO;
	[self presentViewController:picker animated:YES completion:nil];
}

#pragma mark - UIImagePickerControllerDelegate

- (void)imagePickerController:(UIImagePickerController *)picker didFinishPickingMediaWithInfo:(NSDictionary *)info {
	UIImage *image = info[UIImagePickerControllerOriginalImage];
	[picker dismissViewControllerAnimated:YES completion:nil];
	if (image) {
		self.pendingImage = image;
	}
}

- (void)imagePickerControllerDidCancel:(UIImagePickerController *)picker {
	[picker dismissViewControllerAnimated:YES completion:nil];
}

- (void)startImageGenerationWithPrompt:(NSString *)prompt {
	if (prompt.length == 0) return;

	id<MAImageProvider> provider = [MAImageProviderRegistry sharedRegistry].activeProvider;
	if (!provider) {
		[self showAlertWithTitle:MALocalizedString(@"Нет провайдера изображений")
		                  message:MALocalizedString(@"Настрой OpenAI (DALL·E), OpenRouter или Custom в Settings → Изображения.")];
		return;
	}

	// Описание уходит в чат как обычное сообщение пользователя...
	MAMessage *userMessage = [MAMessage messageWithRole:MAMessageRoleUser content:prompt];
	[self.items addObject:[MAChatItem textItemWithMessage:userMessage]];

	// ...а ниже — карточка с результатом генерации (сперва спиннер).
	MAChatItem *imageItem = [MAChatItem imageItemWithPrompt:prompt];
	[self.items addObject:imageItem];

	self.inputField.text = @"";
	[self updateActionButtons];
	[self updateEmptyState];
	[self.tableView reloadData];
	[self scrollToBottomAnimated:YES];
	[self persistCurrentSession];

	__weak typeof(self) weakSelf = self;
	[provider generateImageWithPrompt:prompt size:@"1024x1024" completion:^(UIImage *image, NSError *error) {
		__strong typeof(weakSelf) strongSelf = weakSelf;
		if (!strongSelf) return;

		imageItem.isLoading = NO;
		if (error) {
			imageItem.errorMessage = error.localizedDescription ?: MALocalizedString(@"Не удалось сгенерировать изображение");
		} else {
			imageItem.image = image;
		}

		[strongSelf.tableView reloadData];
		[strongSelf scrollToBottomAnimated:YES];
	}];
}

- (void)scrollToBottomAnimated:(BOOL)animated {
	if (self.items.count == 0) return;
	NSIndexPath *lastIndexPath = [NSIndexPath indexPathForRow:self.items.count - 1 inSection:0];
	[self.tableView scrollToRowAtIndexPath:lastIndexPath atScrollPosition:UITableViewScrollPositionBottom animated:animated];
}

- (void)showAlertWithTitle:(NSString *)title message:(NSString *)message {
	UIAlertView *alert = [[UIAlertView alloc] initWithTitle:title
	                                                  message:message
	                                                 delegate:nil
	                                        cancelButtonTitle:@"OK"
	                                        otherButtonTitles:nil];
	[alert show];
}

#pragma mark - Провайдер чата (меню в navigation bar)

- (void)updateTitleWithActiveProvider {
	id<MAProvider> provider = [MAProviderRegistry sharedRegistry].activeProvider;
	NSString *title = provider ? [NSString stringWithFormat:@"MintAI — %@", provider.displayName] : @"MintAI";
	self.title = [self isIncognitoNow] ? [@"🕶 " stringByAppendingString:title] : title;
	[self updateEmptyState];
}

// Плейсхолдер "Привет! Я <провайдер> / Напиши сообщение." по центру ленты,
// пока не отправлено ни одного сообщения. Прячется сразу же, как в -items
// попадает первый item (текстовый или карточка генерации фото).
- (void)updateEmptyState {
	id<MAProvider> provider = [MAProviderRegistry sharedRegistry].activeProvider;
	NSString *providerName = provider.displayName;
	if (providerName.length > 0) {
		self.emptyStateLabel.text = [NSString stringWithFormat:MALocalizedString(@"Привет! Я \"%@\"\nНапиши сообщение."), providerName];
	} else {
		self.emptyStateLabel.text = MALocalizedString(@"Привет!\nНапиши сообщение.");
	}
	if ([self isIncognitoNow]) {
		self.emptyStateLabel.text = [self.emptyStateLabel.text stringByAppendingFormat:@"\n\n🕶 %@", MALocalizedString(@"Режим инкогнито: беседа не сохраняется")];
	}
	self.emptyStateLabel.hidden = (self.items.count > 0);
	[self.view setNeedsLayout]; // высота текста могла измениться (строка про инкогнито)
}

- (void)showProviderPicker {
	MAProviderRegistry *registry = [MAProviderRegistry sharedRegistry];

	UIActionSheet *sheet = [[UIActionSheet alloc] initWithTitle:MALocalizedString(@"Выбери провайдера")
	                                                     delegate:self
	                                            cancelButtonTitle:nil
	                                       destructiveButtonTitle:nil
	                                            otherButtonTitles:nil];
	sheet.tag = 200; // отличаем от меню "+"
	[[MATheme sharedTheme] styleActionSheet:sheet];
	for (id<MAProvider> provider in registry.providers) {
		[sheet addButtonWithTitle:provider.displayName];
	}
	NSInteger cancelIndex = [sheet addButtonWithTitle:MALocalizedString(@"Отмена")];
	sheet.cancelButtonIndex = cancelIndex;

	[sheet showInView:self.view];
}

#pragma mark - UIActionSheetDelegate

- (void)actionSheet:(UIActionSheet *)actionSheet didDismissWithButtonIndex:(NSInteger)buttonIndex {
	if (buttonIndex == actionSheet.cancelButtonIndex) return;

	if (actionSheet.tag == 100) {
		// Меню "+": какая кнопка — такой и заранее сохранённый блок-действие.
		if (buttonIndex >= 0 && buttonIndex < (NSInteger)self.plusMenuActions.count) {
			void (^action)(void) = self.plusMenuActions[buttonIndex];
			if (action) action();
		}
		self.plusMenuActions = nil;
		return;
	}

	// Меню выбора провайдера чата.
	MAProviderRegistry *registry = [MAProviderRegistry sharedRegistry];
	if (buttonIndex < 0 || buttonIndex >= (NSInteger)registry.providers.count) return;
	registry.activeProvider = registry.providers[buttonIndex];
	[self updateTitleWithActiveProvider];
}

#pragma mark - UITableViewDataSource

- (NSInteger)tableView:(UITableView *)tableView numberOfRowsInSection:(NSInteger)section {
	return self.items.count;
}

- (UITableViewCell *)tableView:(UITableView *)tableView cellForRowAtIndexPath:(NSIndexPath *)indexPath {
	MAChatItem *item = self.items[indexPath.row];

	if (item.kind == MAChatItemKindImage) {
		MAChatImageCell *cell = [tableView dequeueReusableCellWithIdentifier:kImageCellIdentifier forIndexPath:indexPath];
		[cell configureWithItem:item];
		return cell;
	}

	MAChatMessageCell *cell = [tableView dequeueReusableCellWithIdentifier:kMessageCellIdentifier forIndexPath:indexPath];

	void (^editHandler)(void) = nil;
	if (item.message.role == MAMessageRoleUser) {
		NSInteger row = indexPath.row;
		__weak typeof(self) weakSelf = self;
		editHandler = ^{
			[weakSelf beginEditingMessageAtIndex:row];
		};
	}
	[cell configureWithMessage:item.message editHandler:editHandler];
	return cell;
}

#pragma mark - UITableViewDelegate

- (CGFloat)tableView:(UITableView *)tableView heightForRowAtIndexPath:(NSIndexPath *)indexPath {
	MAChatItem *item = self.items[indexPath.row];
	if (item.kind == MAChatItemKindImage) {
		return [MAChatImageCell heightForItem:item tableViewWidth:tableView.bounds.size.width];
	}
	return [MAChatMessageCell heightForMessage:item.message tableViewWidth:tableView.bounds.size.width];
}

#pragma mark - Скрытие клавиатуры

- (void)dismissKeyboardTapped {
	[self.inputField resignFirstResponder];
}

// Начали листать ленту — клавиатура уходит (UITableView.keyboardDismissMode есть только с iOS 7).
- (void)scrollViewWillBeginDragging:(UIScrollView *)scrollView {
	if (scrollView == self.tableView && self.inputField.isFirstResponder) {
		[self.inputField resignFirstResponder];
	}
}

#pragma mark - UITextFieldDelegate

- (BOOL)textFieldShouldReturn:(UITextField *)textField {
	[self sendTapped];
	return YES;
}

@end
