#import <Foundation/Foundation.h>
#import "MAProvider.h"

// Провайдер для Anthropic Claude API. Формат запроса/ответа у Anthropic
// отличается от OpenAI-подобных API, поэтому это отдельная реализация,
// а не подкласс MAOpenAICompatibleProvider:
//  - эндпоинт /v1/messages, а не /chat/completions
//  - авторизация через заголовок x-api-key (+ anthropic-version), а не Bearer
//  - системный промпт — отдельное поле "system", а не сообщение с role=system
//  - ответ — массив content-блоков ({"type":"text","text":"..."}), а не choices[0].message
@interface MAClaudeProvider : NSObject <MAProvider>

@property (nonatomic, copy, readonly) NSString *identifier;
@property (nonatomic, copy, readonly) NSString *displayName;
@property (nonatomic, assign, readonly) BOOL requiresAPIKey;
@property (nonatomic, copy) NSString *apiKey;
@property (nonatomic, copy) NSString *baseURLString;
@property (nonatomic, copy) NSString *model;

// Anthropic требует max_tokens в каждом запросе. По умолчанию 1024.
@property (nonatomic, assign) NSInteger maxTokens;

- (instancetype)init;

@end
