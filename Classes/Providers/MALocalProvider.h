#import "MAOpenAICompatibleProvider.h"

// Нейросеть на вашем ПК/сервере в локальной сети: Ollama, LM Studio, llama.cpp (llama-server),
// text-generation-webui и любой другой сервер с OpenAI-совместимым API (/v1/chat/completions).
//
// От Custom отличается тем, что рассчитан именно на локальные модели:
//  • ключ не нужен (но его можно указать — если сервер стоит за прокси с авторизацией);
//  • увеличенный таймаут запроса: локальная модель на CPU отвечает минутами, а первый запрос
//    ещё и ждёт загрузки модели в память;
//  • список моделей с сервера (GET /models) — для экрана выбора модели;
//  • «размышления» (<think>…</think>) моделей вроде DeepSeek-R1 и Qwen3 вырезаются из ответа;
//  • ошибки сети переведены в подсказки («сервер не запущен», «разные Wi-Fi сети» и т.п.).
@interface MALocalProvider : MAOpenAICompatibleProvider

- (instancetype)init;

// Типовые серверы для быстрой подстановки адреса: @[@{@"name": «Ollama», @"port": «11434»}, …].
+ (NSArray *)presets;

// Запрашивает у сервера список моделей (GET {baseURL}/models). Понимает и формат OpenAI
// ({"data": [{"id": …}]}), и нативный формат Ollama ({"models": [{"name": …}]}).
// completion вызывается на main thread: ровно один из двух аргументов не nil.
- (void)fetchModelsWithCompletion:(void (^)(NSArray *modelIDs, NSError *error))completion;

@end
