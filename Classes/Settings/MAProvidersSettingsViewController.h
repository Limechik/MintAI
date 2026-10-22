#import <UIKit/UIKit.h>
#import "MAThemedTableViewController.h"

typedef NS_ENUM(NSInteger, MAProvidersKind) {
	MAProvidersKindChat = 0,  // DeepSeek, OpenAI, Claude, OpenRouter, Mistral, Gemini, OpenCode Zen, Local LLM, Custom
	MAProvidersKindImage = 1, // OpenAI (DALL·E), OpenRouter, Custom
};

// Список провайдеров одного вида (чат или генерация изображений). Галочка — активный
// провайдер; тап открывает MAProviderDetailViewController (Base URL, модель, ключ).
@interface MAProvidersSettingsViewController : MAThemedTableViewController

- (instancetype)initWithKind:(MAProvidersKind)kind;

// Имя активного провайдера для сводки на корневом экране настроек.
+ (NSString *)summaryForKind:(MAProvidersKind)kind;

@end
