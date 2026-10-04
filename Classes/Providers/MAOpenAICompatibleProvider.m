#import "MAOpenAICompatibleProvider.h"
#import "MALocalization.h"
#import "MAMessage.h"
#import "MAHTTPClient.h"

@implementation MAOpenAICompatibleProvider

- (instancetype)initWithIdentifier:(NSString *)identifier
                        displayName:(NSString *)displayName
                      baseURLString:(NSString *)baseURLString
                              model:(NSString *)model {
	self = [super init];
	if (self) {
		_identifier = [identifier copy];
		_displayName = [displayName copy];
		_baseURLString = [baseURLString copy];
		_model = [model copy];
		_requiresAPIKey = YES;
	}
	return self;
}

#pragma mark - URL

- (NSString *)chatCompletionsURLString {
	NSString *base = self.baseURLString ?: @"";
	// Убираем хвостовой слэш, чтобы не получить двойной "//".
	if ([base hasSuffix:@"/"]) {
		base = [base substringToIndex:base.length - 1];
	}
	// Если пользователь в Settings уже вписал полный путь до /chat/completions —
	// не дублируем его.
	if ([base hasSuffix:@"/chat/completions"]) {
		return base;
	}
	return [base stringByAppendingString:@"/chat/completions"];
}

#pragma mark - MAProvider

- (void)sendMessages:(NSArray *)messages completion:(MAProviderCompletion)completion {
	if (self.requiresAPIKey && self.apiKey.length == 0) {
		NSError *error = [NSError errorWithDomain:MAProviderErrorDomain
		                                      code:MAProviderErrorMissingAPIKey
		                                  userInfo:@{NSLocalizedDescriptionKey: MALocalizedString(@"Не указан API-ключ")}];
		if (completion) completion(nil, error);
		return;
	}

	NSString *urlString = [self chatCompletionsURLString];
	NSURL *url = [NSURL URLWithString:urlString];
	if (!url || urlString.length == 0) {
		NSError *error = [NSError errorWithDomain:MAProviderErrorDomain
		                                      code:MAProviderErrorInvalidURL
		                                  userInfo:@{NSLocalizedDescriptionKey: MALocalizedString(@"Некорректный URL сервера")}];
		if (completion) completion(nil, error);
		return;
	}

	NSMutableArray *payloadMessages = [NSMutableArray arrayWithCapacity:messages.count];
	for (MAMessage *message in messages) {
		NSString *imageBase64 = message.image ? [message imageBase64JPEG] : nil;
		if (imageBase64.length > 0) {
			// Мультимодальное сообщение: content — массив частей вместо строки,
			// как ожидает OpenAI-совместимый /chat/completions (формат общий
			// для OpenAI, DeepSeek, OpenRouter, Mistral, Gemini-шима и Zen).
			NSMutableArray *contentParts = [NSMutableArray arrayWithCapacity:2];
			if (message.content.length > 0) {
				[contentParts addObject:@{@"type": @"text", @"text": message.content}];
			}
			NSString *dataURL = [NSString stringWithFormat:@"data:image/jpeg;base64,%@", imageBase64];
			[contentParts addObject:@{@"type": @"image_url", @"image_url": @{@"url": dataURL}}];
			[payloadMessages addObject:@{
				@"role": [message roleString],
				@"content": contentParts
			}];
		} else {
			[payloadMessages addObject:@{
				@"role": [message roleString],
				@"content": message.content ?: @""
			}];
		}
	}

	NSMutableDictionary *body = [NSMutableDictionary dictionary];
	body[@"model"] = self.model ?: @"";
	body[@"messages"] = payloadMessages;

	NSError *jsonError = nil;
	NSData *bodyData = [NSJSONSerialization dataWithJSONObject:body options:0 error:&jsonError];
	if (!bodyData) {
		if (completion) completion(nil, jsonError);
		return;
	}

	NSMutableURLRequest *request = [NSMutableURLRequest requestWithURL:url];
	request.HTTPMethod = @"POST";
	request.HTTPBody = bodyData;
	[request setValue:@"application/json" forHTTPHeaderField:@"Content-Type"];
	if (self.apiKey.length > 0) {
		NSString *authValue = [NSString stringWithFormat:@"Bearer %@", self.apiKey];
		[request setValue:authValue forHTTPHeaderField:@"Authorization"];
	}
	[self.extraHeaders enumerateKeysAndObjectsUsingBlock:^(id key, id value, BOOL *stop) {
		[request setValue:value forHTTPHeaderField:key];
	}];

	[MAHTTPClient sendAsynchronousRequest:request
	                            completion:^(NSURLResponse *response, NSData *data, NSError *connectionError) {
		[self handleResponse:response data:data error:connectionError completion:completion];
	}];
}

#pragma mark - Response parsing

- (void)handleResponse:(NSURLResponse *)response
                   data:(NSData *)data
                  error:(NSError *)connectionError
             completion:(MAProviderCompletion)completion {
	if (connectionError) {
		if (completion) completion(nil, connectionError);
		return;
	}

	NSInteger statusCode = 200;
	if ([response isKindOfClass:[NSHTTPURLResponse class]]) {
		statusCode = [(NSHTTPURLResponse *)response statusCode];
	}

	NSError *jsonError = nil;
	id json = data ? [NSJSONSerialization JSONObjectWithData:data options:0 error:&jsonError] : nil;

	if (statusCode < 200 || statusCode >= 300) {
		NSString *message = [self errorMessageFromJSON:json
		                                       fallback:[NSHTTPURLResponse localizedStringForStatusCode:statusCode]];
		// Показываем код статуса вместе с текстом: некоторые серверы (Mistral,
		// Gemini-шим и т.п.) не заворачивают ошибку в {"error": {"message": ...}},
		// как OpenAI, и без кода тяжело понять, это 401 (неверный ключ),
		// 403 (ключ верный, но нет доступа/не активирована подписка) или 429.
		NSString *fullMessage = [NSString stringWithFormat:@"%ld: %@", (long)statusCode, message];
		NSError *error = [NSError errorWithDomain:MAProviderErrorDomain
		                                      code:MAProviderErrorServerError
		                                  userInfo:@{NSLocalizedDescriptionKey: fullMessage}];
		if (completion) completion(nil, error);
		return;
	}

	if (![json isKindOfClass:[NSDictionary class]]) {
		NSError *error = [NSError errorWithDomain:MAProviderErrorDomain
		                                      code:MAProviderErrorBadResponse
		                                  userInfo:@{NSLocalizedDescriptionKey: MALocalizedString(@"Сервер вернул некорректный ответ")}];
		if (completion) completion(nil, error);
		return;
	}

	NSString *reply = [self extractReplyFromJSON:json];
	if (!reply) {
		NSError *error = [NSError errorWithDomain:MAProviderErrorDomain
		                                      code:MAProviderErrorBadResponse
		                                  userInfo:@{NSLocalizedDescriptionKey: MALocalizedString(@"Не удалось разобрать ответ сервера")}];
		if (completion) completion(nil, error);
		return;
	}

	if (completion) completion(reply, nil);
}

- (NSString *)extractReplyFromJSON:(NSDictionary *)json {
	NSArray *choices = json[@"choices"];
	if (![choices isKindOfClass:[NSArray class]] || choices.count == 0) return nil;
	NSDictionary *firstChoice = choices[0];
	if (![firstChoice isKindOfClass:[NSDictionary class]]) return nil;
	NSDictionary *message = firstChoice[@"message"];
	NSString *content = message[@"content"];
	if (![content isKindOfClass:[NSString class]]) return nil;
	return content;
}

- (NSString *)errorMessageFromJSON:(id)json fallback:(NSString *)fallback {
	if ([json isKindOfClass:[NSDictionary class]]) {
		// Форма OpenAI/DeepSeek/OpenRouter: {"error": {"message": "..."}}.
		id errorObj = json[@"error"];
		if ([errorObj isKindOfClass:[NSDictionary class]]) {
			id message = errorObj[@"message"];
			if ([message isKindOfClass:[NSString class]] && [message length] > 0) return message;
		} else if ([errorObj isKindOfClass:[NSString class]] && [(NSString *)errorObj length] > 0) {
			return errorObj;
		}
		// Форма Mistral и некоторых других: {"message": "..."} на верхнем уровне,
		// без обёртки "error". Без этой ветки пользователь вместо реальной
		// причины видел только generic "Forbidden"/"Unauthorized" по коду статуса.
		id topLevelMessage = json[@"message"];
		if ([topLevelMessage isKindOfClass:[NSString class]] && [(NSString *)topLevelMessage length] > 0) {
			return topLevelMessage;
		}
	}
	return fallback ?: MALocalizedString(@"Неизвестная ошибка сервера");
}

@end
