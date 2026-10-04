#import <UIKit/UIKit.h>

// Базовый класс всех табличных экранов приложения (настройки, история).
// Берёт на себя тему оформления, чтобы экраны о ней не заботились:
//  • красит фон таблицы и ячейки (в grouped — скруглённые группы с рамкой и разделителями);
//  • перекрашивает галочку (штатная в iOS 6 тёмно-синяя и теряется на тёмном фоне);
//  • рисует заголовки и подписи секций grouped-таблицы (штатные на тёмном не видны);
//  • перерисовывает таблицу при смене темы (MAThemeDidChangeNotification).
//
// Подклассы по-прежнему отдают title/footer через стандартные tableView:titleFor…InSection:.
// Если подкласс переопределяет tableView:willDisplayCell:forRowAtIndexPath: — вызывать super.
// Идентификаторы ячеек grouped-таблиц нужно оборачивать в MAThemedReuseID() (см. MATheme.h).
@interface MAThemedTableViewController : UITableViewController

@end
