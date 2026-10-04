#import "MAThemedTableViewController.h"
#import "MATheme.h"

static const NSInteger kCheckmarkViewTag = 0x4D43;
static const CGFloat kGroupedTextInset = 20;   // отступ подписей секций от края (как у штатных)
static const CGFloat kGroupedGap = 10;         // зазор у секции без заголовка/подписи

#pragma mark - Фон ячейки grouped-таблицы

typedef NS_ENUM(NSInteger, MACellPosition) {
	MACellPositionSingle,
	MACellPositionTop,
	MACellPositionMiddle,
	MACellPositionBottom,
};

// Фон ячейки в grouped-таблице: скругления только у крайних ячеек группы, рамка и
// тонкий разделитель между ячейками. Штатный grouped-фон iOS 6 перекрасить нельзя,
// поэтому в тёмной теме рисуем его сами.
@interface MAGroupedCellBackgroundView : UIView
@property (nonatomic, strong) UIColor *fillColor;
@property (nonatomic, strong) UIColor *borderColor;
@property (nonatomic, assign) MACellPosition position;
@end

@implementation MAGroupedCellBackgroundView

- (instancetype)initWithFrame:(CGRect)frame {
	self = [super initWithFrame:frame];
	if (self) {
		self.backgroundColor = [UIColor clearColor];
		self.opaque = NO;
		self.contentMode = UIViewContentModeRedraw;
	}
	return self;
}

- (void)drawRect:(CGRect)rect {
	CGFloat lineWidth = 1.0f / [UIScreen mainScreen].scale;
	CGFloat half = lineWidth / 2.0f;
	CGRect bounds = self.bounds;

	BOOL roundTop = (self.position == MACellPositionSingle || self.position == MACellPositionTop);
	BOOL roundBottom = (self.position == MACellPositionSingle || self.position == MACellPositionBottom);

	// У средних и нижних ячеек верхнюю линию уводим за край: её уже нарисовала
	// нижняя линия ячейки выше — иначе разделитель вышел бы вдвое толще.
	CGFloat top = roundTop ? half : -lineWidth;
	CGRect shape = CGRectMake(half, top, bounds.size.width - lineWidth, bounds.size.height - half - top);

	UIRectCorner corners = 0;
	if (roundTop) corners |= UIRectCornerTopLeft | UIRectCornerTopRight;
	if (roundBottom) corners |= UIRectCornerBottomLeft | UIRectCornerBottomRight;

	UIBezierPath *path = corners
		? [UIBezierPath bezierPathWithRoundedRect:shape byRoundingCorners:corners cornerRadii:CGSizeMake(9, 9)]
		: [UIBezierPath bezierPathWithRect:shape];

	[self.fillColor setFill];
	[path fill];
	[self.borderColor setStroke];
	path.lineWidth = lineWidth;
	[path stroke];
}

@end

#pragma mark - Галочка

static UIImage *MACheckmarkImage(UIColor *color) {
	static UIImage *cached = nil;
	static dispatch_once_t onceToken;
	dispatch_once(&onceToken, ^{
		CGSize size = CGSizeMake(18, 14);
		UIGraphicsBeginImageContextWithOptions(size, NO, 0.0);
		UIBezierPath *path = [UIBezierPath bezierPath];
		[path moveToPoint:CGPointMake(2, 7.5)];
		[path addLineToPoint:CGPointMake(6.5, 12)];
		[path addLineToPoint:CGPointMake(16, 2)];
		path.lineWidth = 2.5;
		path.lineCapStyle = kCGLineCapRound;
		path.lineJoinStyle = kCGLineJoinRound;
		[color setStroke];
		[path stroke];
		cached = UIGraphicsGetImageFromCurrentImageContext();
		UIGraphicsEndImageContext();
	});
	return cached;
}

#pragma mark - Контроллер

@implementation MAThemedTableViewController

- (void)viewDidLoad {
	[super viewDidLoad];
	[self ma_applyTableTheme];
	[[NSNotificationCenter defaultCenter] addObserver:self
	                                          selector:@selector(ma_themeDidChange:)
	                                              name:MAThemeDidChangeNotification
	                                            object:nil];
}

- (void)dealloc {
	[[NSNotificationCenter defaultCenter] removeObserver:self];
}

- (void)ma_themeDidChange:(NSNotification *)notification {
	[self ma_applyTableTheme];
	[self.tableView reloadData];
}

- (void)ma_applyTableTheme {
	MATheme *theme = [MATheme sharedTheme];
	UITableView *tableView = self.tableView;

	if (tableView.style == UITableViewStyleGrouped) {
		tableView.backgroundView = nil; // иначе штатный фон перекроет цвет
		tableView.backgroundColor = theme.groupedBackgroundColor;
		// В тёмной теме разделители рисует фон ячейки (см. MAGroupedCellBackgroundView).
		tableView.separatorStyle = theme.dark ? UITableViewCellSeparatorStyleNone : UITableViewCellSeparatorStyleSingleLine;
	} else {
		tableView.backgroundColor = theme.backgroundColor;
		tableView.separatorColor = theme.separatorColor;
	}
}

#pragma mark - Ячейки

- (void)tableView:(UITableView *)tableView willDisplayCell:(UITableViewCell *)cell forRowAtIndexPath:(NSIndexPath *)indexPath {
	MATheme *theme = [MATheme sharedTheme];
	BOOL grouped = (tableView.style == UITableViewStyleGrouped);

	// Светлая grouped-таблица — штатный вид iOS 6, как раньше, ничего не трогаем.
	if (grouped && !theme.dark) return;

	cell.textLabel.textColor = theme.primaryTextColor;
	cell.textLabel.backgroundColor = [UIColor clearColor];
	cell.detailTextLabel.textColor = theme.secondaryTextColor;
	cell.detailTextLabel.backgroundColor = [UIColor clearColor];

	if (grouped) {
		[self ma_styleGroupedCell:cell tableView:tableView indexPath:indexPath theme:theme];
	} else {
		// Plain-таблица: ячейки общие для обеих тем, поэтому цвета ставим явно и в светлой.
		cell.backgroundColor = theme.cellBackgroundColor;
		if (theme.dark) {
			UIView *selected = [[UIView alloc] init];
			selected.backgroundColor = theme.cellSelectedColor;
			cell.selectedBackgroundView = selected;
		} else {
			cell.selectedBackgroundView = nil; // штатное синее выделение
		}
	}

	[self ma_styleAccessoryOfCell:cell theme:theme];
}

- (void)ma_styleGroupedCell:(UITableViewCell *)cell tableView:(UITableView *)tableView indexPath:(NSIndexPath *)indexPath theme:(MATheme *)theme {
	NSInteger rows = [tableView numberOfRowsInSection:indexPath.section];
	MACellPosition position;
	if (rows <= 1) position = MACellPositionSingle;
	else if (indexPath.row == 0) position = MACellPositionTop;
	else if (indexPath.row == rows - 1) position = MACellPositionBottom;
	else position = MACellPositionMiddle;

	cell.backgroundColor = [UIColor clearColor];

	MAGroupedCellBackgroundView *background = [cell.backgroundView isKindOfClass:[MAGroupedCellBackgroundView class]]
		? (MAGroupedCellBackgroundView *)cell.backgroundView : [[MAGroupedCellBackgroundView alloc] init];
	background.fillColor = theme.cellBackgroundColor;
	background.borderColor = theme.separatorColor;
	background.position = position;
	[background setNeedsDisplay];
	cell.backgroundView = background;

	MAGroupedCellBackgroundView *selected = [cell.selectedBackgroundView isKindOfClass:[MAGroupedCellBackgroundView class]]
		? (MAGroupedCellBackgroundView *)cell.selectedBackgroundView : [[MAGroupedCellBackgroundView alloc] init];
	selected.fillColor = theme.cellSelectedColor;
	selected.borderColor = theme.separatorColor;
	selected.position = position;
	[selected setNeedsDisplay];
	cell.selectedBackgroundView = selected;
}

// Штатная галочка iOS 6 тёмно-синяя и на тёмном фоне почти не видна — подменяем её
// мятной. Признак подмены — тег на accessoryView; в остальных случаях чужой
// accessoryView (например, UISwitch) не трогаем.
- (void)ma_styleAccessoryOfCell:(UITableViewCell *)cell theme:(MATheme *)theme {
	BOOL hasOurCheckmark = (cell.accessoryView.tag == kCheckmarkViewTag);

	if (theme.dark && cell.accessoryType == UITableViewCellAccessoryCheckmark) {
		if (!hasOurCheckmark) {
			UIImageView *check = [[UIImageView alloc] initWithImage:MACheckmarkImage(theme.accentColor)];
			check.tag = kCheckmarkViewTag;
			cell.accessoryView = check;
		}
	} else if (hasOurCheckmark) {
		cell.accessoryView = nil;
	}
}

#pragma mark - Заголовки и подписи секций (grouped)

- (NSString *)ma_headerTitleInTableView:(UITableView *)tableView section:(NSInteger)section {
	id<UITableViewDataSource> dataSource = tableView.dataSource;
	if (![dataSource respondsToSelector:@selector(tableView:titleForHeaderInSection:)]) return nil;
	return [dataSource tableView:tableView titleForHeaderInSection:section];
}

- (NSString *)ma_footerTitleInTableView:(UITableView *)tableView section:(NSInteger)section {
	id<UITableViewDataSource> dataSource = tableView.dataSource;
	if (![dataSource respondsToSelector:@selector(tableView:titleForFooterInSection:)]) return nil;
	return [dataSource tableView:tableView titleForFooterInSection:section];
}

- (UILabel *)ma_sectionLabelWithText:(NSString *)text font:(UIFont *)font alignment:(NSTextAlignment)alignment {
	MATheme *theme = [MATheme sharedTheme];
	UILabel *label = [[UILabel alloc] init];
	label.text = text;
	label.font = font;
	label.textAlignment = alignment;
	label.numberOfLines = 0;
	label.lineBreakMode = NSLineBreakByWordWrapping;
	label.backgroundColor = [UIColor clearColor];
	label.textColor = theme.groupedHeaderTextColor;
	label.shadowColor = theme.groupedHeaderShadowColor;
	label.shadowOffset = CGSizeMake(0, 1);
	return label;
}

- (UIFont *)ma_headerFont { return [UIFont boldSystemFontOfSize:17]; }
- (UIFont *)ma_footerFont { return [UIFont systemFontOfSize:15]; }

- (CGFloat)ma_textHeight:(NSString *)text font:(UIFont *)font tableView:(UITableView *)tableView {
	CGFloat width = tableView.bounds.size.width - 2 * kGroupedTextInset;
	return ceilf([text sizeWithFont:font constrainedToSize:CGSizeMake(width, 2000) lineBreakMode:NSLineBreakByWordWrapping].height);
}

- (UIView *)tableView:(UITableView *)tableView viewForHeaderInSection:(NSInteger)section {
	if (tableView.style != UITableViewStyleGrouped) return nil;
	NSString *title = [self ma_headerTitleInTableView:tableView section:section];
	if (title.length == 0) return nil;

	CGFloat width = tableView.bounds.size.width;
	UIView *container = [[UIView alloc] initWithFrame:CGRectMake(0, 0, width, 40)];
	UILabel *label = [self ma_sectionLabelWithText:title font:[self ma_headerFont] alignment:NSTextAlignmentLeft];
	label.frame = CGRectMake(kGroupedTextInset, 16, width - 2 * kGroupedTextInset, 22);
	label.autoresizingMask = UIViewAutoresizingFlexibleWidth;
	[container addSubview:label];
	return container;
}

- (CGFloat)tableView:(UITableView *)tableView heightForHeaderInSection:(NSInteger)section {
	NSString *title = [self ma_headerTitleInTableView:tableView section:section];
	if (tableView.style != UITableViewStyleGrouped) return (title.length > 0) ? 22 : 0;
	return (title.length > 0) ? 40 : kGroupedGap;
}

- (UIView *)tableView:(UITableView *)tableView viewForFooterInSection:(NSInteger)section {
	if (tableView.style != UITableViewStyleGrouped) return nil;
	NSString *title = [self ma_footerTitleInTableView:tableView section:section];
	if (title.length == 0) return nil;

	CGFloat width = tableView.bounds.size.width;
	CGFloat textHeight = [self ma_textHeight:title font:[self ma_footerFont] tableView:tableView];
	UIView *container = [[UIView alloc] initWithFrame:CGRectMake(0, 0, width, textHeight + 24)];
	UILabel *label = [self ma_sectionLabelWithText:title font:[self ma_footerFont] alignment:NSTextAlignmentCenter];
	label.frame = CGRectMake(kGroupedTextInset, 8, width - 2 * kGroupedTextInset, textHeight);
	label.autoresizingMask = UIViewAutoresizingFlexibleWidth;
	[container addSubview:label];
	return container;
}

- (CGFloat)tableView:(UITableView *)tableView heightForFooterInSection:(NSInteger)section {
	NSString *title = [self ma_footerTitleInTableView:tableView section:section];
	if (tableView.style != UITableViewStyleGrouped) return (title.length > 0) ? 22 : 0;
	if (title.length == 0) return kGroupedGap;
	return [self ma_textHeight:title font:[self ma_footerFont] tableView:tableView] + 24;
}

@end
