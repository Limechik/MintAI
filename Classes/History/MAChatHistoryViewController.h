#import <UIKit/UIKit.h>
#import "MAThemedTableViewController.h"

// Вкладка "История": список сохранённых бесед (MAChatHistoryStore).
// Тап по строке открывает MAChatViewController с этой сессией, продолжить
// разговор можно прямо оттуда — при новых сообщениях сессия обновляется.
@interface MAChatHistoryViewController : MAThemedTableViewController

@end
