#import "MAPhotoBubbleView.h"
#import <QuartzCore/QuartzCore.h>

// Размеры подобраны по эталону — фото в Сообщениях iOS 6.
static const CGFloat kTailWidth = 9;        // насколько хвостик выступает за тело
static const CGFloat kTailFlareHeight = 16; // с какой высоты от низа край начинает отгибаться наружу
static const CGFloat kCornerRadius = 13;
static const CGFloat kGlossHeight = 20;
static const CGFloat kGlossInsetX = 8;
static const CGFloat kGlossInsetTop = 2;

@interface MAPhotoBubbleView ()
@property (nonatomic, strong) UIImageView *imageView;
@property (nonatomic, strong) CAShapeLayer *maskLayer;
@property (nonatomic, strong) CAShapeLayer *borderLayer;
@property (nonatomic, strong) CAGradientLayer *glossLayer;
@end

@implementation MAPhotoBubbleView

+ (CGFloat)tailWidth {
	return kTailWidth;
}

- (instancetype)initWithFrame:(CGRect)frame {
	self = [super initWithFrame:frame];
	if (self) {
		self.backgroundColor = [UIColor clearColor];
		_tailOnRight = YES;

		_imageView = [[UIImageView alloc] init];
		_imageView.contentMode = UIViewContentModeScaleAspectFill;
		_imageView.clipsToBounds = YES;
		[self addSubview:_imageView];

		// Обрезка фото по контуру пузыря — маской слоя.
		_maskLayer = [CAShapeLayer layer];
		_maskLayer.fillColor = [UIColor blackColor].CGColor;
		_imageView.layer.mask = _maskLayer;

		// Блик: полупрозрачная белая «таблетка», темнеющая к низу.
		_glossLayer = [CAGradientLayer layer];
		_glossLayer.colors = @[(id)[UIColor colorWithWhite:1.0 alpha:0.62].CGColor,
		                       (id)[UIColor colorWithWhite:1.0 alpha:0.14].CGColor];
		_glossLayer.startPoint = CGPointMake(0.5, 0.0);
		_glossLayer.endPoint = CGPointMake(0.5, 1.0);
		_glossLayer.masksToBounds = YES;
		[self.layer addSublayer:_glossLayer];

		// Тонкая обводка по контуру — поверх фото и блика.
		_borderLayer = [CAShapeLayer layer];
		_borderLayer.fillColor = nil;
		_borderLayer.strokeColor = [UIColor colorWithWhite:0.0 alpha:0.6].CGColor;
		_borderLayer.lineWidth = 1.0;
		[self.layer addSublayer:_borderLayer];
	}
	return self;
}

- (UIImage *)image {
	return self.imageView.image;
}

- (void)setImage:(UIImage *)image {
	self.imageView.image = image;
}

- (void)setTailOnRight:(BOOL)tailOnRight {
	if (_tailOnRight == tailOnRight) return;
	_tailOnRight = tailOnRight;
	[self setNeedsLayout];
}

#pragma mark - Контур

// Контур пузыря с хвостиком справа внутри rect (хвостик упирается в правый край rect).
// Для хвостика слева контур зеркалится.
+ (UIBezierPath *)bubblePathInRect:(CGRect)rect tailOnRight:(BOOL)tailOnRight {
	CGFloat bodyWidth = rect.size.width - kTailWidth;
	CGFloat x0 = CGRectGetMinX(rect);
	CGFloat y0 = CGRectGetMinY(rect);
	CGFloat x1 = x0 + bodyWidth;          // правый край тела
	CGFloat y1 = CGRectGetMaxY(rect);
	CGFloat radius = MAX(0, MIN(kCornerRadius, MIN(bodyWidth, rect.size.height) / 2.0));
	CGFloat flareStart = MAX(y0 + radius, y1 - kTailFlareHeight);

	UIBezierPath *path = [UIBezierPath bezierPath];
	[path moveToPoint:CGPointMake(x0 + radius, y0)];
	[path addLineToPoint:CGPointMake(x1 - radius, y0)];
	[path addArcWithCenter:CGPointMake(x1 - radius, y0 + radius) radius:radius startAngle:-M_PI_2 endAngle:0 clockwise:YES];

	// Правый край уходит вниз и у самого низа отгибается наружу в острый хвостик.
	[path addLineToPoint:CGPointMake(x1, flareStart)];
	[path addCurveToPoint:CGPointMake(x1 + kTailWidth, y1)
	        controlPoint1:CGPointMake(x1, y1 - 7)
	        controlPoint2:CGPointMake(x1 + 3, y1)];
	// Нижняя сторона хвостика возвращается к низу тела с лёгкой вогнутостью.
	[path addCurveToPoint:CGPointMake(x1 - 9, y1)
	        controlPoint1:CGPointMake(x1 + 4, y1 - 1.5)
	        controlPoint2:CGPointMake(x1 - 1, y1 - 3.5)];

	[path addLineToPoint:CGPointMake(x0 + radius, y1)];
	[path addArcWithCenter:CGPointMake(x0 + radius, y1 - radius) radius:radius startAngle:M_PI_2 endAngle:M_PI clockwise:YES];
	[path addLineToPoint:CGPointMake(x0, y0 + radius)];
	[path addArcWithCenter:CGPointMake(x0 + radius, y0 + radius) radius:radius startAngle:M_PI endAngle:M_PI + M_PI_2 clockwise:YES];
	[path closePath];

	if (!tailOnRight) {
		// Отражаем по горизонтали относительно середины rect.
		[path applyTransform:CGAffineTransformMake(-1, 0, 0, 1, 2 * CGRectGetMinX(rect) + rect.size.width, 0)];
	}
	return path;
}

#pragma mark - Layout

- (void)layoutSubviews {
	[super layoutSubviews];

	// Слои без view — их свойства анимируются неявно; при переиспользовании ячеек
	// это выглядело бы как «плывущий» контур.
	[CATransaction begin];
	[CATransaction setDisableActions:YES];

	CGRect bounds = self.bounds;
	self.imageView.frame = bounds;

	// Контур — на полпикселя внутрь, чтобы обводка целиком попала в bounds.
	UIBezierPath *path = [[self class] bubblePathInRect:CGRectInset(bounds, 0.5, 0.5) tailOnRight:self.tailOnRight];
	self.maskLayer.frame = bounds;
	self.maskLayer.path = path.CGPath;
	self.borderLayer.frame = bounds;
	self.borderLayer.path = path.CGPath;

	CGFloat bodyX = self.tailOnRight ? 0 : kTailWidth;
	CGFloat bodyWidth = bounds.size.width - kTailWidth;
	CGFloat glossHeight = MIN(kGlossHeight, bounds.size.height * 0.35);
	self.glossLayer.frame = CGRectMake(bodyX + kGlossInsetX, kGlossInsetTop, MAX(0, bodyWidth - 2 * kGlossInsetX), glossHeight);
	self.glossLayer.cornerRadius = glossHeight / 2.0;

	[CATransaction commit];
}

@end
