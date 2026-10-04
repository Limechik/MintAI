#import <UIKit/UIKit.h>

@class MAChatSession;

// Основной экран: история диалога, поле ввода снизу и кнопка в navigation bar
// для быстрого переключения активного провайдера (DeepSeek/OpenAI/Claude/
// OpenRouter/Mistral/Gemini/OpenCode Zen/Custom) без похода в Settings.
//
// Переписка автоматически сохраняется в MAChatHistoryStore по мере
// появления новых сообщений (см. Classes/History) — отдельной кнопки
// "Сохранить" не нужно.
@interface MAChatViewController : UIViewController

// Обычный экран с чистого листа (вкладка "Chat") — новая сессия создаётся
// лениво, при первом сообщении.
- (instancetype)init;

// Открыть уже сохранённую беседу из истории — экран сразу показывает её
// сообщения, а дальнейшая переписка дописывается в ту же сессию.
- (instancetype)initWithSession:(MAChatSession *)session;

@end
