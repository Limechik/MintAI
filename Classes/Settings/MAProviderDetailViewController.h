#import <UIKit/UIKit.h>
#import "MAThemedTableViewController.h"
#import "MAConfigurableProvider.h"

// Универсальная форма настройки одного провайдера — чат или изображения:
// Base URL, модель, API-ключ (если нужен) и кнопка "сделать активным".
// Не знает про конкретный реестр — активацию и сохранение делает через
// переданные блоки, поэтому годится и для MAProviderRegistry, и для
// MAImageProviderRegistry.
@interface MAProviderDetailViewController : MAThemedTableViewController

- (instancetype)initWithProvider:(id<MAConfigurableProvider>)provider
                        isActive:(BOOL (^)(void))isActiveBlock
                        activate:(void (^)(void))activateBlock
                            save:(void (^)(void))saveBlock;

@end
