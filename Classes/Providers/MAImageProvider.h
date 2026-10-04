#import <UIKit/UIKit.h>
#import "MAConfigurableProvider.h"

// image != nil при успехе, error != nil при неудаче — ровно один из двух.
typedef void (^MAImageProviderCompletion)(UIImage *image, NSError *error);

// Общий интерфейс любого провайдера генерации изображений: OpenAI (DALL·E)
// или кастомный/локальный сервер с тем же форматом ответа. Настраиваемые поля —
// в MAConfigurableProvider, общем и с MAProvider (чат).
@protocol MAImageProvider <MAConfigurableProvider>

// size в формате "1024x1024" — так его ждут OpenAI-совместимые API картинок.
// completion вызывается на main thread.
- (void)generateImageWithPrompt:(NSString *)prompt
                            size:(NSString *)size
                      completion:(MAImageProviderCompletion)completion;

@end
