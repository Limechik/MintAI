#import "MAOpenAICompatibleImageProvider.h"

// Провайдер для кастомного/локального сервера генерации изображений
// с тем же форматом ответа, что у OpenAI (/images/generations).
// baseURLString и model задаются пользователем в Settings.
@interface MACustomImageProvider : MAOpenAICompatibleImageProvider

- (instancetype)init;

@end
