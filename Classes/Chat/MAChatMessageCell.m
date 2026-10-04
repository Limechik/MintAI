#import "MAChatMessageCell.h"
#import "MAMessage.h"
#import "MAMarkdownRenderer.h"
#import "MAPhotoBubbleView.h"
#import <QuartzCore/QuartzCore.h>

static const CGFloat kBubbleMaxWidthRatio = 0.75;
static const CGFloat kBubbleMarginOuter = 8;
static const CGFloat kPhotoMaxSize = 200;   // фото вписывается в квадрат kPhotoMaxSize×kPhotoMaxSize
static const CGFloat kBubbleGap = 4;        // зазор между пузырём с фото и пузырём с текстом

// Вертикальный паддинг внутри пузыря одинаков для обеих текстур — верх/низ
// у bubbleMine.png и bubbleSomeone.png симметричны.
static const CGFloat kBubblePaddingTop = 10;
static const CGFloat kBubblePaddingBottom = 12;

// Горизонтальный паддинг несимметричен: со стороны "хвостика" текстуры
// нужно больше отступа, чтобы текст не наезжал на скругление рядом с ним
// (см. cap insets ниже — там же и сама ширина хвостика).
static const CGFloat kBubblePaddingNearTail = 16;
static const CGFloat kBubblePaddingFarFromTail = 12;

// Время отправки — мелкая серая подпись под пузырём, выровненная по той же
// стороне, что и сам пузырь (справа у моих сообщений, слева у чужих).
// Рядом с ней — кнопка "копировать" (значок двух карточек, у обоих типов
// сообщений) и кнопка "редактировать" (значок карандаша, только у моих
// сообщений — свои ответы ассистента редактировать нельзя).
static const CGFloat kTimeLabelTopSpacing = 2;
static const CGFloat kTimeLabelHeight = 16;
static const CGFloat kCopyButtonSize = 16;
static const CGFloat kEditButtonSize = 16;
static const CGFloat kIconSpacing = 4;

@interface MAChatMessageCell ()
@property (nonatomic, strong) UIImageView *bubbleView;
@property (nonatomic, strong) UILabel *messageLabel;
@property (nonatomic, strong) MAPhotoBubbleView *photoBubble;
@property (nonatomic, strong) UILabel *timeLabel;
@property (nonatomic, strong) UIButton *messageCopyButton;
@property (nonatomic, strong) UIButton *messageEditButton;
@property (nonatomic, strong) MAMessage *currentMessage;
@property (nonatomic, copy) void (^editHandler)(void);
@end

@implementation MAChatMessageCell

// Текстуры пузырей — глянцевые "капли" с хвостиком (bubbleMine.png хвост
// снизу-справа, bubbleSomeone.png — снизу-слева), не готовые resizable-
// картинки. Insets подобраны так, чтобы скругления и хвостик оставались
// целыми при растяжении, а тянулась только плоская область в середине
// (см. MintAI-skeleton, обсуждение пузырей сообщений).
+ (UIImage *)mineBubbleImage {
	static UIImage *image = nil;
	static dispatch_once_t onceToken;
	dispatch_once(&onceToken, ^{
		UIImage *raw = [UIImage imageNamed:@"bubbleMine"];
		image = [raw resizableImageWithCapInsets:UIEdgeInsetsMake(11, 10, 16, 21)
		                             resizingMode:UIImageResizingModeStretch];
	});
	return image;
}

+ (UIImage *)someoneBubbleImage {
	static UIImage *image = nil;
	static dispatch_once_t onceToken;
	dispatch_once(&onceToken, ^{
		UIImage *raw = [UIImage imageNamed:@"bubbleSomeone"];
		image = [raw resizableImageWithCapInsets:UIEdgeInsetsMake(11, 17, 16, 14)
		                             resizingMode:UIImageResizingModeStretch];
	});
	return image;
}

- (instancetype)initWithStyle:(UITableViewCellStyle)style reuseIdentifier:(NSString *)reuseIdentifier {
	self = [super initWithStyle:style reuseIdentifier:reuseIdentifier];
	if (self) {
		self.selectionStyle = UITableViewCellSelectionStyleNone;
		self.backgroundColor = [UIColor clearColor];

		_bubbleView = [[UIImageView alloc] init];

		// Фото — отдельный пузырь с хвостиком, обрезанный по его контуру (см. MAPhotoBubbleView).
		_photoBubble = [[MAPhotoBubbleView alloc] init];
		_photoBubble.hidden = YES;

		_messageLabel = [[UILabel alloc] init];
		_messageLabel.numberOfLines = 0;
		_messageLabel.font = [[self class] messageFont];
		_messageLabel.backgroundColor = [UIColor clearColor];

		_timeLabel = [[UILabel alloc] init];
		_timeLabel.font = [UIFont systemFontOfSize:11];
		_timeLabel.textColor = [UIColor colorWithWhite:0.6 alpha:1.0];
		_timeLabel.backgroundColor = [UIColor clearColor];

		_messageCopyButton = [UIButton buttonWithType:UIButtonTypeCustom];
		[_messageCopyButton setImage:[UIImage imageNamed:@"iconCopy"] forState:UIControlStateNormal];
		[_messageCopyButton addTarget:self action:@selector(copyButtonTapped) forControlEvents:UIControlEventTouchUpInside];

		_messageEditButton = [UIButton buttonWithType:UIButtonTypeCustom];
		[_messageEditButton setImage:[UIImage imageNamed:@"iconEdit"] forState:UIControlStateNormal];
		[_messageEditButton addTarget:self action:@selector(editButtonTapped) forControlEvents:UIControlEventTouchUpInside];

		[_bubbleView addSubview:_messageLabel];
		[self.contentView addSubview:_photoBubble];
		[self.contentView addSubview:_bubbleView];
		[self.contentView addSubview:_timeLabel];
		[self.contentView addSubview:_messageCopyButton];
		[self.contentView addSubview:_messageEditButton];
	}
	return self;
}

+ (UIFont *)messageFont {
	// Явно "Helvetica" (а не systemFontOfSize) — жирный/курсив в разметке
	// (см. MAMarkdownRenderer) собираются из конкретных начертаний этого же
	// семейства ("Helvetica-Bold" и т.п.), и метрики должны совпадать.
	return [UIFont fontWithName:@"Helvetica" size:15] ?: [UIFont systemFontOfSize:15];
}

// "18:00" — время отправки/получения сообщения. NSDateFormatter в SDK 6.1
// уже понимает шаблоны POSIX (setDateFormat:), локальный формат AM/PM тут
// не нужен, поэтому шаблон фиксированный, а не через setTimeStyle:.
+ (NSString *)timeStringForMessage:(MAMessage *)message {
	if (!message.date) return @"";
	static NSDateFormatter *formatter = nil;
	static dispatch_once_t onceToken;
	dispatch_once(&onceToken, ^{
		formatter = [[NSDateFormatter alloc] init];
		[formatter setDateFormat:@"HH:mm"];
	});
	return [formatter stringFromDate:message.date];
}

// Рендер сообщения в NSAttributedString — с Markdown-разметкой для ответов
// ассистента (ссылки, списки, код и т.д., см. MAMarkdownRenderer) и как
// обычный текст для сообщений пользователя (то, что печатает сам человек,
// разметкой не интерпретируем — иначе случайная "звёздочка" в тексте
// неожиданно превратилась бы в курсив).
//
// Кешируем по указателю MAMessage: один и тот же экземпляр сообщения за
// время жизни ячейки просят отрендерить дважды — сначала для измерения
// высоты строки (+heightForMessage:tableViewWidth:), потом для самой ячейки
// (-configureWithMessage:) — а сообщения в MAChatViewController.items
// неизменяемы после создания, так что кеш по указателю безопасен.
+ (NSAttributedString *)attributedContentForMessage:(MAMessage *)message {
	if (message.content.length == 0) return nil;

	static NSMapTable *cache = nil;
	static dispatch_once_t onceToken;
	dispatch_once(&onceToken, ^{
		cache = [NSMapTable weakToStrongObjectsMapTable];
	});

	NSAttributedString *cached = [cache objectForKey:message];
	if (cached) return cached;

	BOOL isUser = (message.role == MAMessageRoleUser);
	UIColor *color = isUser ? [UIColor whiteColor] : [UIColor blackColor]; // пузырь светлый в обеих темах
	UIFont *font = [self messageFont];

	NSAttributedString *result;
	if (isUser) {
		result = [[NSAttributedString alloc] initWithString:message.content
		                                          attributes:@{NSFontAttributeName: font,
		                                                       NSForegroundColorAttributeName: color}];
	} else {
		result = [MAMarkdownRenderer attributedStringFromMarkdown:message.content baseFont:font textColor:color];
	}

	[cache setObject:result forKey:message];
	return result;
}

+ (CGSize)textSizeForMessage:(MAMessage *)message maxWidth:(CGFloat)maxWidth {
	NSAttributedString *attributed = [self attributedContentForMessage:message];
	if (attributed.length == 0) return CGSizeZero;
	// boundingRectWithSize: (а не устаревший sizeWithFont:) — единственный
	// способ измерить NSAttributedString с разными шрифтами/начертаниями
	// внутри одной строки; доступен в UIKit начиная с iOS 6.0.
	CGRect rect = [attributed boundingRectWithSize:CGSizeMake(maxWidth, CGFLOAT_MAX)
	                                        options:NSStringDrawingUsesLineFragmentOrigin | NSStringDrawingUsesFontLeading
	                                        context:nil];
	return CGSizeMake(ceilf(rect.size.width), ceilf(rect.size.height));
}

// Вписываем фото в квадрат kPhotoMaxSize×kPhotoMaxSize с сохранением
// пропорций, без апскейла маленьких картинок.
+ (CGSize)photoSizeForMessage:(MAMessage *)message {
	UIImage *image = message.image;
	if (!image || image.size.width <= 0 || image.size.height <= 0) return CGSizeZero;

	CGFloat scale = MIN(kPhotoMaxSize / image.size.width, kPhotoMaxSize / image.size.height);
	scale = MIN(scale, (CGFloat)1.0);
	return CGSizeMake(floorf(image.size.width * scale), floorf(image.size.height * scale));
}

+ (CGFloat)heightForMessage:(MAMessage *)message tableViewWidth:(CGFloat)width {
	CGFloat maxBubbleWidth = floorf(width * kBubbleMaxWidthRatio) - (kBubblePaddingNearTail + kBubblePaddingFarFromTail);
	CGSize textSize = [self textSizeForMessage:message maxWidth:maxBubbleWidth];
	CGSize photoSize = [self photoSizeForMessage:message];

	// Фото и текст — отдельные пузыри друг под другом, как в Сообщениях iOS 6.
	CGFloat bubblesHeight = photoSize.height;
	if (textSize.height > 0 || photoSize.height == 0) {
		CGFloat textBubbleHeight = MAX(textSize.height + kBubblePaddingTop + kBubblePaddingBottom, 32); // не ниже нативной высоты текстуры
		bubblesHeight += (photoSize.height > 0 ? kBubbleGap : 0) + textBubbleHeight;
	}
	return bubblesHeight + kTimeLabelTopSpacing + kTimeLabelHeight + (2 * kBubbleMarginOuter);
}

- (void)configureWithMessage:(MAMessage *)message editHandler:(void (^)(void))editHandler {
	NSAttributedString *attributedContent = [[self class] attributedContentForMessage:message];
	BOOL hasText = (attributedContent.length > 0);
	BOOL hasPhoto = (message.image != nil);
	BOOL isUser = (message.role == MAMessageRoleUser);

	self.messageLabel.attributedText = attributedContent;
	self.messageLabel.hidden = !hasText;
	self.bubbleView.image = isUser ? [[self class] mineBubbleImage] : [[self class] someoneBubbleImage];

	// Текстовый пузырь нужен, если есть текст; пустое сообщение без фото, как и раньше,
	// остаётся пустым пузырём минимального размера.
	BOOL showTextBubble = (hasText || !hasPhoto);
	self.bubbleView.hidden = !showTextBubble;

	self.photoBubble.image = message.image;
	self.photoBubble.tailOnRight = isUser; // хвостик со стороны отправителя
	self.photoBubble.hidden = !hasPhoto;

	// У "моего" пузыря хвостик справа — там нужен больший отступ, у чужого
	// пузыря хвостик слева — отступ зеркалится.
	CGFloat leftPadding = isUser ? kBubblePaddingFarFromTail : kBubblePaddingNearTail;
	CGFloat rightPadding = isUser ? kBubblePaddingNearTail : kBubblePaddingFarFromTail;

	CGFloat cellWidth = CGRectGetWidth(self.contentView.bounds);
	if (cellWidth <= 0) {
		cellWidth = [UIScreen mainScreen].bounds.size.width;
	}

	CGFloat maxBubbleWidth = floorf(cellWidth * kBubbleMaxWidthRatio) - (leftPadding + rightPadding);
	CGSize textSize = [[self class] textSizeForMessage:message maxWidth:maxBubbleWidth];
	CGSize photoSize = [[self class] photoSizeForMessage:message];

	// Размеры пузырей. Пузырь с фото включает и хвостик (он выступает за край фото).
	CGFloat photoBubbleWidth = photoSize.width + [MAPhotoBubbleView tailWidth];
	// Меньше нативного размера текстуры пузырь быть не должен — иначе
	// cap insets "схлопнутся" и резинка потечёт (см. UIImageResizingMode).
	CGFloat textBubbleWidth = MAX(textSize.width + leftPadding + rightPadding, 43);
	CGFloat textBubbleHeight = MAX(textSize.height + kBubblePaddingTop + kBubblePaddingBottom, 32);

	CGFloat photoBubbleX = isUser ? (cellWidth - photoBubbleWidth - kBubbleMarginOuter) : kBubbleMarginOuter;
	CGFloat textBubbleX = isUser ? (cellWidth - textBubbleWidth - kBubbleMarginOuter) : kBubbleMarginOuter;

	// Раскладываем пузыри сверху вниз: фото, затем текст.
	CGFloat y = kBubbleMarginOuter;
	CGFloat leftEdge = CGFLOAT_MAX;
	CGFloat rightEdge = 0;
	if (hasPhoto) {
		self.photoBubble.frame = CGRectMake(photoBubbleX, y, photoBubbleWidth, photoSize.height);
		leftEdge = MIN(leftEdge, photoBubbleX);
		rightEdge = MAX(rightEdge, photoBubbleX + photoBubbleWidth);
		y += photoSize.height + (showTextBubble ? kBubbleGap : 0);
	}
	if (showTextBubble) {
		self.bubbleView.frame = CGRectMake(textBubbleX, y, textBubbleWidth, textBubbleHeight);
		self.messageLabel.frame = CGRectMake(leftPadding, kBubblePaddingTop, textSize.width, textSize.height);
		leftEdge = MIN(leftEdge, textBubbleX);
		rightEdge = MAX(rightEdge, textBubbleX + textBubbleWidth);
		y += textBubbleHeight;
	}

	self.currentMessage = message;
	self.editHandler = editHandler;
	BOOL hasCopyableText = (message.content.length > 0);
	// Редактировать можно только свои сообщения — у ответов ассистента
	// иконки карандаша нет вообще (editHandler для них не передаётся).
	BOOL showEditButton = (isUser && editHandler != nil);
	self.messageCopyButton.hidden = !hasCopyableText;
	self.messageEditButton.hidden = !showEditButton;

	CGFloat timeRowY = y + kTimeLabelTopSpacing;
	self.timeLabel.text = [[self class] timeStringForMessage:message];

	if (isUser) {
		// Мои сообщения: у правого края — карандаш, левее — копирование,
		// ещё левее — время; всё прижато к правому краю пузырей (под
		// хвостиком). Каждая иконка есть в раскладке, только если видима.
		CGFloat cursorX = rightEdge;
		if (showEditButton) {
			cursorX -= kEditButtonSize;
			self.messageEditButton.frame = CGRectMake(cursorX, timeRowY, kEditButtonSize, kEditButtonSize);
			cursorX -= kIconSpacing;
		}
		if (hasCopyableText) {
			cursorX -= kCopyButtonSize;
			self.messageCopyButton.frame = CGRectMake(cursorX, timeRowY, kCopyButtonSize, kCopyButtonSize);
			cursorX -= kIconSpacing;
		}
		self.timeLabel.textAlignment = NSTextAlignmentRight;
		self.timeLabel.frame = CGRectMake(leftEdge, timeRowY, cursorX - leftEdge, kTimeLabelHeight);
	} else {
		// Чужие сообщения: копирование у левого края, время — правее (без
		// карандаша — showEditButton здесь всегда NO).
		CGFloat cursorX = leftEdge;
		if (hasCopyableText) {
			self.messageCopyButton.frame = CGRectMake(cursorX, timeRowY, kCopyButtonSize, kCopyButtonSize);
			cursorX += kCopyButtonSize + kIconSpacing;
		}
		self.timeLabel.textAlignment = NSTextAlignmentLeft;
		self.timeLabel.frame = CGRectMake(cursorX, timeRowY, rightEdge - cursorX, kTimeLabelHeight);
	}
}

#pragma mark - Копирование и редактирование сообщения

- (void)copyButtonTapped {
	if (self.currentMessage.content.length == 0) return;

	[UIPasteboard generalPasteboard].string = self.currentMessage.content;

	// Лёгкая анимация-подтверждение вместо тоста/алерта — коротко гасим и
	// возвращаем иконку, чтобы было понятно, что тап сработал.
	[UIView animateWithDuration:0.1
	                      delay:0
	                    options:UIViewAnimationOptionAllowUserInteraction
	                 animations:^{
		self.messageCopyButton.alpha = 0.2;
	}
	                 completion:^(BOOL finished) {
		[UIView animateWithDuration:0.15 delay:0 options:UIViewAnimationOptionAllowUserInteraction animations:^{
			self.messageCopyButton.alpha = 1.0;
		} completion:nil];
	}];
}

- (void)editButtonTapped {
	if (self.editHandler) self.editHandler();
}

@end
