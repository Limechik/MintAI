#import <UIKit/UIKit.h>
#import "MAThemedTableViewController.h"

// Категория «Оформление»: обои вкладки «Chat» (своя картинка из галереи/камеры или стандартный фон).
@interface MAAppearanceSettingsViewController : MAThemedTableViewController

// «Своя картинка» / «Стандартный фон» для сводки на корневом экране настроек.
+ (NSString *)summary;

@end
