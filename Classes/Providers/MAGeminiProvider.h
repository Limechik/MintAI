#import "MAOpenAICompatibleProvider.h"

// Google Gemini. Нативный REST-формат Gemini (generateContent, contents/parts,
// ключ в query-параметре ?key=) сильно отличается от OpenAI-подобных API, но
// Google сам публикует OpenAI-совместимый шим поверх generativelanguage.googleapis.com
// (/v1beta/openai/chat/completions, Bearer-токен, обычный choices[0].message),
// поэтому используем именно его — не нужна отдельная реализация протокола.
@interface MAGeminiProvider : MAOpenAICompatibleProvider

- (instancetype)init;

@end
