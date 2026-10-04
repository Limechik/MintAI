#import <UIKit/UIKit.h>
#import "MAThemedTableViewController.h"

// Категория «Голос»: озвучка ответов встроенным синтезатором VoxSynth —
// автоозвучка, тембр, скорость, проверка.
@interface MAVoiceSettingsViewController : MAThemedTableViewController

// Название выбранного тембра для сводки на корневом экране настроек.
+ (NSString *)summary;

@end
