#import <Foundation/Foundation.h>

extern NSString *const MAProviderErrorDomain;

typedef NS_ENUM(NSInteger, MAProviderErrorCode) {
	MAProviderErrorMissingAPIKey = 1,
	MAProviderErrorInvalidURL,
	MAProviderErrorBadResponse,
	MAProviderErrorServerError,
};

// Общий набор настраиваемых полей для ЛЮБОГО провайдера — чат (MAProvider)
// или генерация изображений (MAImageProvider). Экран настроек
// (MAProviderDetailViewController) работает только через этот протокол,
// не зная, что именно провайдер умеет делать.
@protocol MAConfigurableProvider <NSObject>

// Внутренний идентификатор, например "deepseek", "openai-image".
@property (nonatomic, copy, readonly) NSString *identifier;

// Имя для показа в UI, например "OpenAI (DALL·E)".
@property (nonatomic, copy, readonly) NSString *displayName;

// Нужен ли вообще API-ключ (для некоторых локальных серверов — нет).
@property (nonatomic, assign, readonly) BOOL requiresAPIKey;

@property (nonatomic, copy) NSString *apiKey;

// Базовый URL сервера.
@property (nonatomic, copy) NSString *baseURLString;

// Идентификатор модели.
@property (nonatomic, copy) NSString *model;

@end
