#import "MAClaudeProvider.h"
#import "MALocalization.h"
#import "MAMessage.h"
#import "MAHTTPClient.h"

static NSString *const kAnthropicVersion = @"2023-06-01";

@implementation MAClaudeProvider

- (instancetype)init {
	self = [super init];
	if (self) {
		_identifier = @"claude";
		_displayName = @"Claude";
		_baseURLString = @"https://api.anthropic.com";
		// TODO: актуализировать под нужную модель / вынести выбор в Settings.
		_model = @"claude-sonnet-4-6";
		_requiresAPIKey = YES;
		_maxTokens = 1024;
	}
	return self;
}

#pragma mark - URL

- (NSString *)messagesURLString {
	NSString *base = self.baseURLString ?: @"";
	if ([base hasSuffix:@"/"]) {
		base = [base substringToIndex:base.length - 1];
	}
	if ([base hasSuffix:@"/v1/messages"]) {
		return base;
	}
	return [base stringByAppendingString:@"/v1/messages"];
}

#pragma mark - MAProvider

- (void)sendMessages:(NSArray *)messages completion:(MAProviderCompletion)completion {
	if (self.apiKey.length == 0) {
		NSError *error = [NSError errorWithDomain:MAProviderErrorDomain
		                                      code:MAProviderErrorMissingAPIKey
		                                  userInfo:@{NSLocalizedDescriptionKey: MALocalizedString(@"Не указан API-ключ Claude")}];
		if (completion) completion(nil, error);
		return;
	}

	NSString *urlString = [self messagesURLString];
	NSURL *url = [NSURL URLWithString:urlString];
	if (!url || urlString.length == 0) {
		NSError *error = [NSError errorWithDomain:MAProviderErrorDomain
		                                      code:MAProviderErrorInvalidURL
		                                  userInfo:@{NSLocalizedDescriptionKey: MALocalizedString(@"Некорректный URL сервера")}];
		if (completion) completion(nil, error);
		return;
	}

	// Claude не принимает role=system внутри messages — собираем все
	// системные сообщения в отдельное поле "system".
	NSMutableArray *payloadMessages = [NSMutableArray array];
	NSMutableString *systemPrompt = [NSMutableString string];
	for (MAMessage *message in messages) {
		if (message.role == MAMessageRoleSystem) {
			if (systemPrompt.length > 0) [systemPrompt appendString:@"\n"];
			[systemPrompt appendString:message.content ?: @""];
			continue;
		}

		NSString *imageBase64 = message.image ? [message imageBase64JPEG] : nil;
		if (imageBase64.length > 0) {
			// Мультимодальный content-блок Anthropic: картинка отдельным
			// блоком (рекомендуется ставить перед текстом), затем текст.
			NSMutableArray *blocks = [NSMutableArray arrayWithCapacity:2];
			[blocks addObject:@{
				@"type": @"image",
				@"source": @{
					@"type": @"base64",
					@"media_type": @"image/jpeg",
					@"data": imageBase64
				}
			}];
			if (message.content.length > 0) {
				[blocks addObject:@{@"type": @"text", @"text": message.content}];
			}
			[payloadMessages addObject:@{@"role": [message roleString], @"content": blocks}];
		} else {
			[payloadMessages addObject:@{
				@"role": [message roleString],
				@"content": message.content ?: @""
			}];
		}
	}

	NSMutableDictionary *body = [NSMutableDictionary dictionary];
	body[@"model"] = self.model ?: @"";
	body[@"max_tokens"] = @(self.maxTokens > 0 ? self.maxTokens : 1024);
	body[@"messages"] = payloadMessages;
	if (systemPrompt.length > 0) {
		body[@"system"] = systemPrompt;
	}

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
	[request setValue:self.apiKey forHTTPHeaderField:@"x-api-key"];
	[request setValue:kAnthropicVersion forHTTPHeaderField:@"anthropic-version"];

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
		NSError *error = [NSError errorWithDomain:MAProviderErrorDomain
		                                      code:MAProviderErrorServerError
		                                  userInfo:@{NSLocalizedDescriptionKey: message}];
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

	NSArray *contentBlocks = json[@"content"];
	NSMutableString *text = [NSMutableString string];
	if ([contentBlocks isKindOfClass:[NSArray class]]) {
		for (NSDictionary *block in contentBlocks) {
			if ([block isKindOfClass:[NSDictionary class]] &&
			    [block[@"type"] isEqual:@"text"] &&
			    [block[@"text"] isKindOfClass:[NSString class]]) {
				[text appendString:block[@"text"]];
			}
		}
	}

	if (text.length == 0) {
		NSError *error = [NSError errorWithDomain:MAProviderErrorDomain
		                                      code:MAProviderErrorBadResponse
		                                  userInfo:@{NSLocalizedDescriptionKey: MALocalizedString(@"Не удалось разобрать ответ Claude")}];
		if (completion) completion(nil, error);
		return;
	}

	if (completion) completion(text, nil);
}

- (NSString *)errorMessageFromJSON:(id)json fallback:(NSString *)fallback {
	if ([json isKindOfClass:[NSDictionary class]]) {
		id errorObj = json[@"error"];
		if ([errorObj isKindOfClass:[NSDictionary class]]) {
			id message = errorObj[@"message"];
			if ([message isKindOfClass:[NSString class]]) return message;
		}
	}
	return fallback ?: MALocalizedString(@"Неизвестная ошибка сервера");
}

@end
