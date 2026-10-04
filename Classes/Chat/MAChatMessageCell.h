#import <UIKit/UIKit.h>

@class MAMessage;

// Ячейка-«пузырь»: сообщение пользователя выравнено вправо и подсвечено,
// сообщение ассистента — слева, нейтрального цвета.
@interface MAChatMessageCell : UITableViewCell

// editHandler вызывается по тапу на иконку карандаша — она показывается
// только у сообщений пользователя (см. -configureWithMessage:editHandler:
// в реализации). У сообщений ассистента можно передать nil.
- (void)configureWithMessage:(MAMessage *)message editHandler:(void (^)(void))editHandler;

+ (CGFloat)heightForMessage:(MAMessage *)message tableViewWidth:(CGFloat)width;

@end
