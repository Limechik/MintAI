#import "MAOpenAICompatibleProvider.h"

// Провайдер для кастомного или локального сервера с OpenAI-совместимым API
// (LM Studio, Ollama в OpenAI-совместимом режиме, text-generation-webui,
// собственный backend и т.п.). baseURLString и model задаются пользователем
// в Settings — здесь только разумные пустые дефолты.
@interface MACustomProvider : MAOpenAICompatibleProvider

- (instancetype)init;

@end
