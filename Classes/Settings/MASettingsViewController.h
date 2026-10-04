#import <UIKit/UIKit.h>
#import "MAThemedTableViewController.h"

// Корневой экран вкладки «Settings» — меню категорий (как системные «Настройки»):
//
//   ИИ
//     Чат                  -> MAProvidersSettingsViewController (чат)
//     Изображения          -> MAProvidersSettingsViewController (картинки)
//     Инструкция           -> MAInstructionsSettingsViewController
//   Приложение
//     Голос                -> MAVoiceSettingsViewController
//     Оформление           -> MAAppearanceSettingsViewController
//     Язык / Language      -> MALanguageSettingsViewController
//   Автор
//     Telegram             -> https://t.me/LimeDeveloper (Safari)
//     Source Code          -> https://github.com/Limechik/MintAI (Safari)
//
// Справа в каждой строке — краткая сводка текущего значения (активный провайдер,
// язык и т.п.). Сами настройки живут на экранах категорий.
// Чтобы добавить категорию: новый case в MASettingsCategory и по строке в
// kAICategories / kAppCategories (или новая секция).
@interface MASettingsViewController : MAThemedTableViewController

@end
