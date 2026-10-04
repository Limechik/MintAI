#import "MAOpenAICompatibleImageProvider.h"

// Генерация изображений через OpenRouter: единый доступ к моделям OpenAI, Google
// (Gemini/Nano Banana), Black Forest Labs (FLUX), Recraft, Seedream и др. по одному ключу.
//
// Использует отдельный Image API OpenRouter — POST {baseURL}/images. Формат близок
// к OpenAI, но параметры другие: вместо size — aspect_ratio, response_format нет,
// картинка приходит в data[0].b64_json. Модель — любая из списка
// https://openrouter.ai/api/v1/images/models (поле «Модель» в настройках).
@interface MAOpenRouterImageProvider : MAOpenAICompatibleImageProvider

- (instancetype)init;

@end
