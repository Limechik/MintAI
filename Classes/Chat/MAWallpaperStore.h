#import <UIKit/UIKit.h>

// Рассылается всем открытым экранам чата, когда обои меняются (выбрано новое
// фото или сброшено на стандартный фон) — так активный MAChatViewController
// обновляет фон сразу, без необходимости перезаходить на вкладку.
extern NSString *const MAWallpaperDidChangeNotification;

// Хранилище фона чата. Картинка лежит файлом в Documents (а не в
// NSUserDefaults — фото из галереи может быть тяжёлым), путь к ней помнит
// NSUserDefaults. Именно так более уместно, чем Keychain: обои не секрет.
@interface MAWallpaperStore : NSObject

+ (instancetype)sharedStore;

// nil, если пользователь ничего не выбирал — тогда чат остаётся с
// обычным белым фоном.
- (UIImage *)wallpaperImage;

// Сохраняет image на диск и рассылает MAWallpaperDidChangeNotification.
- (void)setWallpaperImage:(UIImage *)image;

// Возврат к стандартному белому фону.
- (void)clearWallpaper;

@end
