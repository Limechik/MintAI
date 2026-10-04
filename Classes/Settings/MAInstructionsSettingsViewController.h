#import <UIKit/UIKit.h>
#import "MAThemedTableViewController.h"

// Категория «Инструкция»: выключатель + переход к редактору текста
// (MAInstructionsViewController).
@interface MAInstructionsSettingsViewController : MAThemedTableViewController

// «Вкл» / «Выкл» / «Не задана» для сводки на корневом экране настроек.
+ (NSString *)summary;

@end
