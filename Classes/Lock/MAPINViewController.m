#import "MAPINViewController.h"
#import "MAAppLock.h"
#import "MALocalization.h"
#import "MATheme.h"
#import <QuartzCore/QuartzCore.h>

typedef NS_ENUM(NSInteger, MAPINStage) {
	MAPINStageVerify,  // ввод текущего PIN
	MAPINStageCreate,  // ввод нового PIN
	MAPINStageConfirm, // повтор нового PIN
};

static const NSInteger kPINLength = 4;
static const CGFloat kKeySize = 64;
static const CGFloat kKeyGap = 12;
static const CGFloat kDotSize = 14;
static const CGFloat kDotGap = 18;

@interface MAPINViewController ()
@property (nonatomic, assign) MAPINMode mode;
@property (nonatomic, assign) MAPINStage stage;
@property (nonatomic, strong) NSMutableString *entry;
@property (nonatomic, copy) NSString *firstPIN;
@property (nonatomic, assign) BOOL processing;
@property (nonatomic, assign) BOOL showingLockout;

@property (nonatomic, strong) UILabel *titleLabel;
@property (nonatomic, strong) UILabel *messageLabel;
@property (nonatomic, strong) UIView *dotsContainer;
@property (nonatomic, strong) NSArray *dotViews;
@property (nonatomic, strong) NSArray *digitButtons; // индекс = цифра
@property (nonatomic, strong) UIButton *cancelButton;
@property (nonatomic, strong) UIButton *deleteButton;
@property (nonatomic, strong) NSTimer *lockoutTimer;
@end

@implementation MAPINViewController

- (instancetype)initWithMode:(MAPINMode)mode {
	self = [super init];
	if (self) {
		_mode = mode;
		_stage = (mode == MAPINModeCreate) ? MAPINStageCreate : MAPINStageVerify;
		_entry = [NSMutableString string];
	}
	return self;
}

- (void)dealloc {
	[self teardown];
}

- (void)teardown {
	[self.lockoutTimer invalidate];
	self.lockoutTimer = nil;
	[NSObject cancelPreviousPerformRequestsWithTarget:self];
}

#pragma mark - Ориентация

// На iPhone экран только портретный, на iPad — любой (как и само приложение).
- (BOOL)shouldAutorotateToInterfaceOrientation:(UIInterfaceOrientation)orientation {
	if (UI_USER_INTERFACE_IDIOM() == UIUserInterfaceIdiomPad) return YES;
	return orientation == UIInterfaceOrientationPortrait || orientation == UIInterfaceOrientationPortraitUpsideDown;
}

- (BOOL)shouldAutorotate {
	return YES;
}

- (NSUInteger)supportedInterfaceOrientations {
	if (UI_USER_INTERFACE_IDIOM() == UIUserInterfaceIdiomPad) return UIInterfaceOrientationMaskAll;
	return UIInterfaceOrientationMaskPortrait | UIInterfaceOrientationMaskPortraitUpsideDown;
}

#pragma mark - Lifecycle

- (void)viewDidLoad {
	[super viewDidLoad];
	MATheme *theme = [MATheme sharedTheme];
	self.view.backgroundColor = theme.backgroundColor;

	self.titleLabel = [[UILabel alloc] init];
	self.titleLabel.font = [UIFont systemFontOfSize:20];
	self.titleLabel.textColor = theme.primaryTextColor;
	self.titleLabel.textAlignment = NSTextAlignmentCenter;
	self.titleLabel.backgroundColor = [UIColor clearColor];
	self.titleLabel.adjustsFontSizeToFitWidth = YES;
	self.titleLabel.minimumScaleFactor = 0.7f;
	[self.view addSubview:self.titleLabel];

	self.messageLabel = [[UILabel alloc] init];
	self.messageLabel.font = [UIFont systemFontOfSize:14];
	self.messageLabel.textColor = [UIColor colorWithRed:0.86f green:0.27f blue:0.27f alpha:1.0f];
	self.messageLabel.textAlignment = NSTextAlignmentCenter;
	self.messageLabel.backgroundColor = [UIColor clearColor];
	self.messageLabel.adjustsFontSizeToFitWidth = YES;
	self.messageLabel.minimumScaleFactor = 0.7f;
	[self.view addSubview:self.messageLabel];

	self.dotsContainer = [[UIView alloc] init];
	self.dotsContainer.backgroundColor = [UIColor clearColor];
	NSMutableArray *dots = [NSMutableArray array];
	for (NSInteger i = 0; i < kPINLength; i++) {
		UIView *dot = [[UIView alloc] initWithFrame:CGRectMake(i * (kDotSize + kDotGap), 0, kDotSize, kDotSize)];
		dot.layer.cornerRadius = kDotSize / 2.0f;
		dot.layer.borderWidth = 1.5f;
		dot.layer.borderColor = theme.primaryTextColor.CGColor;
		[self.dotsContainer addSubview:dot];
		[dots addObject:dot];
	}
	self.dotViews = dots;
	[self.view addSubview:self.dotsContainer];

	NSMutableArray *buttons = [NSMutableArray array];
	for (NSInteger digit = 0; digit <= 9; digit++) {
		UIButton *button = [self keyButtonWithTitle:[NSString stringWithFormat:@"%ld", (long)digit] circular:YES];
		button.tag = digit;
		[button addTarget:self action:@selector(digitTapped:) forControlEvents:UIControlEventTouchUpInside];
		[self.view addSubview:button];
		[buttons addObject:button];
	}
	self.digitButtons = buttons;

	self.cancelButton = [self keyButtonWithTitle:MALocalizedString(@"Отмена") circular:NO];
	[self.cancelButton addTarget:self action:@selector(cancelTapped) forControlEvents:UIControlEventTouchUpInside];
	self.cancelButton.hidden = (self.mode == MAPINModeUnlock); // из приложения не выйти без PIN
	[self.view addSubview:self.cancelButton];

	self.deleteButton = [self keyButtonWithTitle:MALocalizedString(@"Удалить") circular:NO];
	[self.deleteButton addTarget:self action:@selector(deleteTapped) forControlEvents:UIControlEventTouchUpInside];
	[self.view addSubview:self.deleteButton];

	[self refreshTitle];
	[self updateDots];
}

- (void)viewWillAppear:(BOOL)animated {
	[super viewWillAppear:animated];
	[self updateLockoutState];
}

- (void)viewWillDisappear:(BOOL)animated {
	[super viewWillDisappear:animated];
	[self.lockoutTimer invalidate];
	self.lockoutTimer = nil;
}

- (UIButton *)keyButtonWithTitle:(NSString *)title circular:(BOOL)circular {
	MATheme *theme = [MATheme sharedTheme];
	UIButton *button = [UIButton buttonWithType:UIButtonTypeCustom];
	button.frame = CGRectMake(0, 0, kKeySize, kKeySize);
	[button setTitle:title forState:UIControlStateNormal];
	[button setTitleColor:theme.primaryTextColor forState:UIControlStateNormal];
	[button setTitleColor:theme.secondaryTextColor forState:UIControlStateDisabled];
	button.titleLabel.font = [UIFont systemFontOfSize:circular ? 28 : 15];
	if (circular) {
		button.layer.cornerRadius = kKeySize / 2.0f;
		button.layer.borderWidth = 1.0f;
		button.layer.borderColor = theme.secondaryTextColor.CGColor;
		// Подсветка при нажатии: на время касания заливаем кнопку цветом бренда.
		[button addTarget:self action:@selector(keyTouchDown:) forControlEvents:UIControlEventTouchDown];
		[button addTarget:self action:@selector(keyTouchUp:) forControlEvents:UIControlEventTouchUpInside | UIControlEventTouchUpOutside | UIControlEventTouchCancel];
	} else {
		[button setTitleColor:theme.secondaryTextColor forState:UIControlStateHighlighted];
	}
	return button;
}

- (void)keyTouchDown:(UIButton *)button {
	button.backgroundColor = [[MATheme sharedTheme].accentColor colorWithAlphaComponent:0.35f];
}

- (void)keyTouchUp:(UIButton *)button {
	button.backgroundColor = [UIColor clearColor];
}

#pragma mark - Раскладка

- (void)viewDidLayoutSubviews {
	[super viewDidLayoutSubviews];

	CGRect bounds = self.view.bounds;
	CGFloat gridWidth = 3 * kKeySize + 2 * kKeyGap;
	CGFloat gridHeight = 4 * kKeySize + 3 * kKeyGap;
	CGFloat left = floorf((bounds.size.width - gridWidth) / 2.0f);
	CGFloat gridTop = bounds.size.height - gridHeight - 20;
	CGFloat step = kKeySize + kKeyGap;

	for (NSInteger digit = 1; digit <= 9; digit++) {
		UIButton *button = self.digitButtons[digit];
		button.frame = CGRectMake(left + ((digit - 1) % 3) * step, gridTop + ((digit - 1) / 3) * step, kKeySize, kKeySize);
	}
	((UIButton *)self.digitButtons[0]).frame = CGRectMake(left + step, gridTop + 3 * step, kKeySize, kKeySize);
	self.cancelButton.frame = CGRectMake(left, gridTop + 3 * step, kKeySize, kKeySize);
	self.deleteButton.frame = CGRectMake(left + 2 * step, gridTop + 3 * step, kKeySize, kKeySize);

	// Над клавиатурой: заголовок, точки, сообщение. Верхние 20 pt — под строку состояния.
	CGFloat regionTop = 20;
	CGFloat regionHeight = MAX(0, gridTop - regionTop);
	CGFloat labelWidth = bounds.size.width - 40;

	self.titleLabel.frame = CGRectMake(20, 0, labelWidth, 26);
	self.titleLabel.center = CGPointMake(bounds.size.width / 2.0f, regionTop + regionHeight * 0.28f);

	CGFloat dotsWidth = kPINLength * kDotSize + (kPINLength - 1) * kDotGap;
	self.dotsContainer.bounds = CGRectMake(0, 0, dotsWidth, kDotSize);
	self.dotsContainer.center = CGPointMake(bounds.size.width / 2.0f, regionTop + regionHeight * 0.58f);

	self.messageLabel.frame = CGRectMake(20, 0, labelWidth, 20);
	self.messageLabel.center = CGPointMake(bounds.size.width / 2.0f, regionTop + regionHeight * 0.84f);
}

#pragma mark - Состояние экрана

- (void)refreshTitle {
	switch (self.stage) {
		case MAPINStageVerify:
			self.titleLabel.text = (self.mode == MAPINModeUnlock) ? MALocalizedString(@"Введите PIN-код") : MALocalizedString(@"Введите текущий PIN-код");
			break;
		case MAPINStageCreate:
			self.titleLabel.text = (self.mode == MAPINModeChange) ? MALocalizedString(@"Введите новый PIN-код") : MALocalizedString(@"Придумайте PIN-код");
			break;
		case MAPINStageConfirm:
			self.titleLabel.text = MALocalizedString(@"Повторите PIN-код");
			break;
	}
}

- (void)updateDots {
	MATheme *theme = [MATheme sharedTheme];
	for (NSInteger i = 0; i < kPINLength; i++) {
		UIView *dot = self.dotViews[i];
		dot.backgroundColor = (i < (NSInteger)self.entry.length) ? theme.primaryTextColor : [UIColor clearColor];
	}
	self.deleteButton.hidden = (self.entry.length == 0);
}

- (void)resetEntry {
	[self.entry setString:@""];
	[self updateDots];
}

- (void)setKeysEnabled:(BOOL)enabled {
	for (UIButton *button in self.digitButtons) {
		button.enabled = enabled;
		button.alpha = enabled ? 1.0f : 0.35f;
	}
}

#pragma mark - Пауза после неверных попыток

- (void)updateLockoutState {
	NSTimeInterval remaining = (self.stage == MAPINStageVerify) ? [[MAAppLock sharedLock] lockoutRemaining] : 0;

	if (remaining > 0) {
		NSInteger seconds = (NSInteger)remaining;
		NSString *time = [NSString stringWithFormat:@"%ld:%02ld", (long)(seconds / 60), (long)(seconds % 60)];
		self.messageLabel.text = [NSString stringWithFormat:MALocalizedString(@"Слишком много попыток. Повторите через %@"), time];
		self.showingLockout = YES;
		[self setKeysEnabled:NO];
		if (!self.lockoutTimer) {
			self.lockoutTimer = [NSTimer scheduledTimerWithTimeInterval:1.0 target:self selector:@selector(updateLockoutState) userInfo:nil repeats:YES];
		}
		return;
	}

	[self.lockoutTimer invalidate];
	self.lockoutTimer = nil;
	if (self.showingLockout) {
		self.showingLockout = NO;
		self.messageLabel.text = nil;
	}
	[self setKeysEnabled:YES];
}

#pragma mark - Ввод

- (void)digitTapped:(UIButton *)sender {
	if (self.processing || self.showingLockout) return;
	if (self.entry.length >= kPINLength) return;

	self.messageLabel.text = nil;
	[self.entry appendFormat:@"%ld", (long)sender.tag];
	[self updateDots];

	if (self.entry.length == kPINLength) {
		self.processing = YES; // пока разбираемся с PIN, кнопки не принимают ввод
		[self performSelector:@selector(processEntry) withObject:nil afterDelay:0.12]; // чтобы успела нарисоваться последняя точка
	}
}

- (void)deleteTapped {
	if (self.processing || self.entry.length == 0) return;
	[self.entry deleteCharactersInRange:NSMakeRange(self.entry.length - 1, 1)];
	[self updateDots];
}

- (void)cancelTapped {
	[self teardown];
	if (self.completion) self.completion(NO, nil);
}

- (void)processEntry {
	NSString *pin = [self.entry copy];

	switch (self.stage) {
		case MAPINStageVerify: {
			MAPINVerifyResult result = [[MAAppLock sharedLock] verifyPIN:pin];
			if (result == MAPINVerifyResultOK) {
				if (self.mode == MAPINModeChange) {
					self.stage = MAPINStageCreate; // текущий PIN верный — теперь новый
					[self advanceToNextStep];
				} else {
					[self finishWithPIN:pin];
				}
			} else {
				[self rejectWithMessage:MALocalizedString(@"Неверный PIN-код")];
			}
			break;
		}
		case MAPINStageCreate:
			self.firstPIN = pin;
			self.stage = MAPINStageConfirm;
			[self advanceToNextStep];
			break;
		case MAPINStageConfirm:
			if ([pin isEqualToString:self.firstPIN]) {
				[self finishWithPIN:pin];
			} else {
				self.firstPIN = nil;
				self.stage = MAPINStageCreate;
				[self rejectWithMessage:MALocalizedString(@"PIN-коды не совпали. Попробуйте ещё раз.")];
			}
			break;
	}
}

// Переход на следующий шаг: точки очищаются, заголовок меняется.
- (void)advanceToNextStep {
	[self resetEntry];
	[self refreshTitle];
	self.messageLabel.text = nil;
	self.processing = NO;
}

// Ввод принят: дальше решает вызывающий. Ввод остаётся заблокированным до закрытия экрана.
- (void)finishWithPIN:(NSString *)pin {
	if (self.completion) self.completion(YES, pin);
}

- (void)rejectWithMessage:(NSString *)message {
	self.messageLabel.text = message;
	[self refreshTitle];

	CAKeyframeAnimation *shake = [CAKeyframeAnimation animationWithKeyPath:@"transform.translation.x"];
	shake.values = @[@0, @-10, @10, @-8, @8, @-4, @4, @0];
	shake.duration = 0.4;
	[self.dotsContainer.layer addAnimation:shake forKey:@"shake"];

	__weak typeof(self) weakSelf = self;
	dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(0.4 * NSEC_PER_SEC)), dispatch_get_main_queue(), ^{
		__strong typeof(weakSelf) strongSelf = weakSelf;
		if (!strongSelf) return;
		[strongSelf resetEntry];
		strongSelf.processing = NO;
		[strongSelf updateLockoutState]; // 5-я неверная попытка включает паузу
	});
}

@end
