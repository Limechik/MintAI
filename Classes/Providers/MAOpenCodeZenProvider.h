#import "MAOpenAICompatibleProvider.h"

// OpenCode Zen (opencode.ai) — платформа с pay-as-you-go доступом к моделям
// разных вендоров (DeepSeek, GLM, Kimi, MiniMax и т.д.) через единый
// OpenAI-совместимый /v1/chat/completions. Часть моделей (GPT через
// /responses, Claude через /messages, Gemini через собственные эндпоинты)
// Zen отдаёт не в этом формате — сюда стоит указывать модели именно из
// раздела "OpenAI-compatible" их списка моделей.
@interface MAOpenCodeZenProvider : MAOpenAICompatibleProvider

- (instancetype)init;

@end
