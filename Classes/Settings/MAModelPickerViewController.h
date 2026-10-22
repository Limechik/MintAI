#import <UIKit/UIKit.h>
#import "MAThemedTableViewController.h"

// Список моделей, полученных с сервера (MALocalProvider -fetchModelsWithCompletion:).
// Тап по строке — выбор модели и возврат на экран провайдера.
@interface MAModelPickerViewController : MAThemedTableViewController

- (instancetype)initWithModels:(NSArray *)models
                 selectedModel:(NSString *)selectedModel
                      onSelect:(void (^)(NSString *model))onSelect;

@end
