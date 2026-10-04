#import <UIKit/UIKit.h>
#import "MAImageProvider.h"

// Базовая реализация для любого сервера с эндпоинтом в формате OpenAI
// (POST {baseURL}/images/generations, Bearer-токен, ответ в data[0].b64_json
// или data[0].url). Подходит для OpenAI (DALL·E) и локальных серверов с
// таким же форматом (например LocalAI) — Custom-провайдер тоже отсюда
// наследуется, просто с пустым baseURLString по умолчанию.
@interface MAOpenAICompatibleImageProvider : NSObject <MAImageProvider>

@property (nonatomic, copy, readonly) NSString *identifier;
@property (nonatomic, copy, readonly) NSString *displayName;
@property (nonatomic, assign) BOOL requiresAPIKey;
@property (nonatomic, copy) NSString *apiKey;
@property (nonatomic, copy) NSString *baseURLString;
@property (nonatomic, copy) NSString *model;

// Дополнительные HTTP-заголовки каждого запроса (как у чат-провайдера),
// например идентификация приложения для OpenRouter.
@property (nonatomic, copy) NSDictionary *extraHeaders;

- (instancetype)initWithIdentifier:(NSString *)identifier
                        displayName:(NSString *)displayName
                      baseURLString:(NSString *)baseURLString
                              model:(NSString *)model;

// Хуки для наследников с нестандартным API. По умолчанию — формат OpenAI.

// Полный URL эндпоинта генерации.
- (NSString *)imagesURLString;

// JSON-тело запроса. Ответ должен прийти в data[0].b64_json или data[0].url.
- (NSDictionary *)requestBodyWithPrompt:(NSString *)prompt size:(NSString *)size;

// Сколько ждать ответа, секунды.
- (NSTimeInterval)requestTimeoutInterval;

@end
