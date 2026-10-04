#import <UIKit/UIKit.h>
#import "MAThemedTableViewController.h"

// Категория «Язык / Language»: язык интерфейса (русский / English), переключается на лету.
@interface MALanguageSettingsViewController : MAThemedTableViewController

// «Русский» / «English» для сводки на корневом экране настроек.
+ (NSString *)summary;

@end
