#import <UIKit/UIKit.h>

@class MAChatItem;

// Ячейка-«пузырь» для сгенерированного изображения: пока isLoading — спиннер,
// потом картинка (или текст ошибки, если генерация не удалась).
// Долгое нажатие на готовую картинку — сохранить в галерею устройства.
@interface MAChatImageCell : UITableViewCell

- (void)configureWithItem:(MAChatItem *)item;

+ (CGFloat)heightForItem:(MAChatItem *)item tableViewWidth:(CGFloat)width;

@end
