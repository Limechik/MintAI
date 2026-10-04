#import <UIKit/UIKit.h>

// Фото в «пузыре» как в Сообщениях iOS 6: картинка обрезана по контуру пузыря вместе
// с хвостиком, поверх — тонкая тёмная обводка и глянцевый блик-«таблетка» сверху.
//
// Вся view целиком (bounds) — это пузырь вместе с хвостиком: тело пузыря занимает
// bounds минус +tailWidth со стороны хвостика. Картинка заполняет всё (aspect fill).
@interface MAPhotoBubbleView : UIView

@property (nonatomic, strong) UIImage *image;

// YES — хвостик справа (мои сообщения), NO — слева (ответы приложения).
@property (nonatomic, assign) BOOL tailOnRight;

// На сколько хвостик выступает за тело пузыря — прибавляется к ширине фото.
+ (CGFloat)tailWidth;

@end
