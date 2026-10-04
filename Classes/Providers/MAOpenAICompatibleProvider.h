#import <Foundation/Foundation.h>
#import "MAProvider.h"

// Базовая реализация для любого сервера с чат-комплишенами в формате OpenAI
// (POST {baseURL}/chat/completions, Bearer-токен, {choices[0].message.content}
// в ответе). Подходит для DeepSeek, OpenAI, OpenRouter и большинства
// локальных серверов (LM Studio, Ollama в OpenAI-совместимом режиме,
// text-generation-webui и т.п.) — поэтому Custom-провайдер тоже наследуется
// отсюда, просто с пустым baseURLString по умолчанию, который задаёт пользователь.
@interface MAOpenAICompatibleProvider : NSObject <MAProvider>

@property (nonatomic, copy, readonly) NSString *identifier;
@property (nonatomic, copy, readonly) NSString *displayName;
@property (nonatomic, assign) BOOL requiresAPIKey;
@property (nonatomic, copy) NSString *apiKey;
@property (nonatomic, copy) NSString *baseURLString;
@property (nonatomic, copy) NSString *model;

// Доп. заголовки сверх Authorization — например, OpenRouter просит
// HTTP-Referer / X-Title.
@property (nonatomic, copy) NSDictionary *extraHeaders;

- (instancetype)initWithIdentifier:(NSString *)identifier
                        displayName:(NSString *)displayName
                      baseURLString:(NSString *)baseURLString
                              model:(NSString *)model;

@end
