#import "MAChatImageCell.h"
#import "MALocalization.h"
#import "MAChatItem.h"
#import "MAPhotoBubbleView.h"
#import <QuartzCore/QuartzCore.h>

static const CGFloat kImageBoxSize = 200.0;
static const CGFloat kBubbleMarginOuter = 8.0;
static const CGFloat kBubblePadding = 10.0;
static const CGFloat kErrorBubbleHeight = 60.0;

@interface MAChatImageCell ()
@property (nonatomic, strong) UIView *bubbleView;
@property (nonatomic, strong) MAPhotoBubbleView *photoBubble;
@property (nonatomic, strong) UIActivityIndicatorView *spinner;
@property (nonatomic, strong) UILabel *errorLabel;
@end

@implementation MAChatImageCell

- (instancetype)initWithStyle:(UITableViewCellStyle)style reuseIdentifier:(NSString *)reuseIdentifier {
	self = [super initWithStyle:style reuseIdentifier:reuseIdentifier];
	if (self) {
		self.selectionStyle = UITableViewCellSelectionStyleNone;
		self.backgroundColor = [UIColor clearColor];

		_bubbleView = [[UIView alloc] init];
		_bubbleView.backgroundColor = [UIColor colorWithWhite:0.9 alpha:1.0];
		_bubbleView.layer.cornerRadius = 12.0;
		_bubbleView.layer.masksToBounds = YES;

		// Готовая картинка — пузырь с хвостиком слева, как фото в Сообщениях iOS 6
		// (см. MAPhotoBubbleView). Серый _bubbleView остаётся для спиннера и ошибки.
		_photoBubble = [[MAPhotoBubbleView alloc] init];
		_photoBubble.tailOnRight = NO;
		_photoBubble.hidden = YES;

		UILongPressGestureRecognizer *longPress =
			[[UILongPressGestureRecognizer alloc] initWithTarget:self action:@selector(handleLongPress:)];
		[_photoBubble addGestureRecognizer:longPress];

		_spinner = [[UIActivityIndicatorView alloc] initWithActivityIndicatorStyle:UIActivityIndicatorViewStyleGray];
		_spinner.hidesWhenStopped = YES;

		_errorLabel = [[UILabel alloc] init];
		_errorLabel.numberOfLines = 0;
		_errorLabel.font = [UIFont systemFontOfSize:13];
		_errorLabel.textColor = [UIColor colorWithRed:0.7 green:0.1 blue:0.1 alpha:1.0];
		_errorLabel.hidden = YES;

		[_bubbleView addSubview:_spinner];
		[_bubbleView addSubview:_errorLabel];
		[self.contentView addSubview:_photoBubble];
		[self.contentView addSubview:_bubbleView];
	}
	return self;
}

+ (CGFloat)heightForItem:(MAChatItem *)item tableViewWidth:(CGFloat)width {
	if (item.errorMessage.length > 0) {
		return kErrorBubbleHeight + (2 * kBubbleMarginOuter);
	}
	return kImageBoxSize + (2 * kBubbleMarginOuter);
}

- (void)configureWithItem:(MAChatItem *)item {
	BOOL hasError = (item.errorMessage.length > 0);
	BOOL hasImage = (item.image != nil);

	self.photoBubble.hidden = !hasImage;
	self.photoBubble.image = hasImage ? item.image : nil;
	self.bubbleView.hidden = hasImage; // серый пузырь — только пока нет картинки
	self.errorLabel.hidden = !hasError;
	self.errorLabel.text = hasError ? item.errorMessage : nil;

	if (item.isLoading && !hasError) {
		[self.spinner startAnimating];
	} else {
		[self.spinner stopAnimating];
	}

	CGFloat cellWidth = CGRectGetWidth(self.contentView.bounds);
	if (cellWidth <= 0) {
		cellWidth = [UIScreen mainScreen].bounds.size.width;
	}

	CGFloat bubbleWidth = hasError ? MIN(260.0, cellWidth - (2 * kBubbleMarginOuter) - 20.0) : kImageBoxSize;
	CGFloat bubbleHeight = hasError ? kErrorBubbleHeight : kImageBoxSize;

	// Пузырь всегда слева — это "ответ" приложения на просьбу пользователя,
	// как и текст ассистента в MAChatMessageCell.
	self.bubbleView.frame = CGRectMake(kBubbleMarginOuter, kBubbleMarginOuter, bubbleWidth, bubbleHeight);
	self.photoBubble.frame = CGRectMake(kBubbleMarginOuter, kBubbleMarginOuter,
	                                     kImageBoxSize + [MAPhotoBubbleView tailWidth], kImageBoxSize);
	self.spinner.center = CGPointMake(bubbleWidth / 2.0, bubbleHeight / 2.0);
	self.errorLabel.frame = CGRectMake(kBubblePadding, kBubblePadding,
	                                    bubbleWidth - (2 * kBubblePadding), bubbleHeight - (2 * kBubblePadding));
}

#pragma mark - Сохранение в галерею

- (void)handleLongPress:(UILongPressGestureRecognizer *)recognizer {
	if (recognizer.state != UIGestureRecognizerStateBegan) return;
	if (!self.photoBubble.image) return;

	UIImageWriteToSavedPhotosAlbum(self.photoBubble.image, self,
	                                @selector(image:didFinishSavingWithError:contextInfo:), NULL);
}

- (void)image:(UIImage *)image didFinishSavingWithError:(NSError *)error contextInfo:(void *)contextInfo {
	NSString *title = error ? MALocalizedString(@"Ошибка") : MALocalizedString(@"Готово");
	NSString *message = error ? error.localizedDescription : MALocalizedString(@"Изображение сохранено в галерею.");
	UIAlertView *alert = [[UIAlertView alloc] initWithTitle:title
	                                                  message:message
	                                                 delegate:nil
	                                        cancelButtonTitle:@"OK"
	                                        otherButtonTitles:nil];
	[alert show];
}

@end
