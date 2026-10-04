#import "MAInstructionsViewController.h"
#import "MALocalization.h"
#import "MAInstructionsStore.h"
#import "MATheme.h"

@interface MAInstructionsViewController () <UITextViewDelegate>
@property (nonatomic, strong) UITextView *textView;
@property (nonatomic, strong) UILabel *placeholderLabel;
@property (nonatomic, assign) CGFloat keyboardHeight;
@end

@implementation MAInstructionsViewController

- (instancetype)init {
	self = [super init];
	if (self) {
		self.title = MALocalizedString(@"Инструкция");
		// Экран целиком под текст: таб-бар внизу только мешал бы клавиатуре.
		self.hidesBottomBarWhenPushed = YES;
	}
	return self;
}

- (void)dealloc {
	[[NSNotificationCenter defaultCenter] removeObserver:self];
}

- (void)viewDidLoad {
	[super viewDidLoad];
	MATheme *theme = [MATheme sharedTheme];
	self.view.backgroundColor = theme.backgroundColor;

	self.textView = [[UITextView alloc] init];
	self.textView.font = [UIFont systemFontOfSize:16];
	self.textView.backgroundColor = theme.backgroundColor;
	self.textView.textColor = theme.primaryTextColor;
	self.textView.keyboardAppearance = theme.keyboardAppearance;
	self.textView.delegate = self;
	self.textView.autocorrectionType = UITextAutocorrectionTypeDefault;
	self.textView.alwaysBounceVertical = YES;
	self.textView.text = [MAInstructionsStore sharedStore].instructions;
	[self.view addSubview:self.textView];

	// У UITextView нет placeholder'а — рисуем свой поверх.
	self.placeholderLabel = [[UILabel alloc] init];
	self.placeholderLabel.text = MALocalizedString(@"Например: отвечай кратко и по-русски, обращайся на «ты», не извиняйся без причины.");
	self.placeholderLabel.font = self.textView.font;
	self.placeholderLabel.textColor = theme.placeholderTextColor;
	self.placeholderLabel.numberOfLines = 0;
	self.placeholderLabel.backgroundColor = [UIColor clearColor];
	self.placeholderLabel.userInteractionEnabled = NO;
	[self.view addSubview:self.placeholderLabel];

	self.navigationItem.rightBarButtonItem =
		[[UIBarButtonItem alloc] initWithTitle:MALocalizedString(@"Очистить")
		                                  style:UIBarButtonItemStylePlain
		                                 target:self
		                                 action:@selector(clearTapped)];
	[self refreshState];

	[[NSNotificationCenter defaultCenter] addObserver:self
	                                          selector:@selector(keyboardWillChange:)
	                                              name:UIKeyboardWillShowNotification
	                                            object:nil];
	[[NSNotificationCenter defaultCenter] addObserver:self
	                                          selector:@selector(keyboardWillChange:)
	                                              name:UIKeyboardWillHideNotification
	                                            object:nil];
}

- (void)viewDidAppear:(BOOL)animated {
	[super viewDidAppear:animated];
	// Пустая инструкция — сразу открываем клавиатуру, чтобы можно было печатать.
	if ([MAInstructionsStore sharedStore].instructions.length == 0) {
		[self.textView becomeFirstResponder];
	}
}

- (void)viewWillDisappear:(BOOL)animated {
	[super viewWillDisappear:animated];
	[MAInstructionsStore sharedStore].instructions = self.textView.text;
	[[MAInstructionsStore sharedStore] synchronize];
}

- (void)viewDidLayoutSubviews {
	[super viewDidLayoutSubviews];
	CGRect bounds = self.view.bounds;
	CGFloat height = MAX(0, bounds.size.height - self.keyboardHeight);
	self.textView.frame = CGRectMake(0, 0, bounds.size.width, height);

	CGFloat labelWidth = bounds.size.width - 2 * 13;
	CGSize labelSize = [self.placeholderLabel sizeThatFits:CGSizeMake(labelWidth, CGFLOAT_MAX)];
	self.placeholderLabel.frame = CGRectMake(13, 8, labelWidth, labelSize.height);
}

#pragma mark - Состояние

- (void)refreshState {
	self.placeholderLabel.hidden = (self.textView.text.length > 0);
	self.navigationItem.rightBarButtonItem.enabled = (self.textView.text.length > 0);
}

- (void)clearTapped {
	self.textView.text = @"";
	[MAInstructionsStore sharedStore].instructions = @"";
	[self refreshState];
	[self.textView becomeFirstResponder];
}

#pragma mark - UITextViewDelegate

- (void)textViewDidChange:(UITextView *)textView {
	[MAInstructionsStore sharedStore].instructions = textView.text;
	[self refreshState];
}

#pragma mark - Клавиатура

- (void)keyboardWillChange:(NSNotification *)notification {
	CGRect keyboardFrame = [notification.userInfo[UIKeyboardFrameEndUserInfoKey] CGRectValue];
	CGRect inView = [self.view convertRect:keyboardFrame fromView:nil];
	BOOL showing = [notification.name isEqualToString:UIKeyboardWillShowNotification];
	self.keyboardHeight = showing ? MAX(0, self.view.bounds.size.height - CGRectGetMinY(inView)) : 0;

	NSTimeInterval duration = [notification.userInfo[UIKeyboardAnimationDurationUserInfoKey] doubleValue];
	[UIView animateWithDuration:duration animations:^{
		[self.view setNeedsLayout];
		[self.view layoutIfNeeded];
	}];
}

@end
