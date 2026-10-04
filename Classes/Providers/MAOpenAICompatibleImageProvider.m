#import "MAOpenAICompatibleImageProvider.h"
#import "MALocalization.h"
#import "MAHTTPClient.h"
#import <string.h>

// В iPhoneOS6.1 SDK нет ни initWithBase64Encoding: (появился позже), ни
// initWithBase64EncodedString:options: (iOS7+) — декодируем сами.
static NSData *MABase64Decode(NSString *base64String) {
	if (base64String.length == 0) return nil;

	static char decodeTable[256];
	static BOOL tableBuilt = NO;
	if (!tableBuilt) {
		const char *alphabet = "ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789+/";
		memset(decodeTable, -1, sizeof(decodeTable));
		for (int i = 0; i < 64; i++) {
			decodeTable[(unsigned char)alphabet[i]] = (char)i;
		}
		tableBuilt = YES;
	}

	NSData *asciiData = [base64String dataUsingEncoding:NSASCIIStringEncoding];
	const unsigned char *bytes = asciiData.bytes;
	NSUInteger length = asciiData.length;

	NSMutableData *output = [NSMutableData dataWithCapacity:(length / 4) * 3];

	int buffer = 0;
	int bitsCollected = 0;

	for (NSUInteger i = 0; i < length; i++) {
		unsigned char c = bytes[i];
		if (c == '=') break; // паддинг — конец данных
		char value = decodeTable[c];
		if (value < 0) continue; // переводы строк и прочий мусор пропускаем

		buffer = (buffer << 6) | value;
		bitsCollected += 6;
		if (bitsCollected >= 8) {
			bitsCollected -= 8;
			unsigned char decodedByte = (unsigned char)((buffer >> bitsCollected) & 0xFF);
			[output appendBytes:&decodedByte length:1];
		}
	}

	return output;
}

@implementation MAOpenAICompatibleImageProvider

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

- (NSString *)imagesURLString {
	NSString *base = self.baseURLString ?: @"";
	if ([base hasSuffix:@"/"]) {
		base = [base substringToIndex:base.length - 1];
	}
	if ([base hasSuffix:@"/images/generations"]) {
		return base;
	}
	return [base stringByAppendingString:@"/images/generations"];
}

- (NSDictionary *)requestBodyWithPrompt:(NSString *)prompt size:(NSString *)size {
	return @{
		@"model": self.model ?: @"",
		@"prompt": prompt ?: @"",
		@"size": size.length > 0 ? size : @"1024x1024",
		@"n": @1,
		@"response_format": @"b64_json",
	};
}

- (NSTimeInterval)requestTimeoutInterval {
	return 120.0; // генерация картинки — не быстрая операция
}

#pragma mark - MAImageProvider

- (void)generateImageWithPrompt:(NSString *)prompt
                            size:(NSString *)size
                      completion:(MAImageProviderCompletion)completion {
	if (self.requiresAPIKey && self.apiKey.length == 0) {
		NSError *error = [NSError errorWithDomain:MAProviderErrorDomain
		                                      code:MAProviderErrorMissingAPIKey
		                                  userInfo:@{NSLocalizedDescriptionKey: MALocalizedString(@"Не указан API-ключ")}];
		if (completion) completion(nil, error);
		return;
	}

	NSString *urlString = [self imagesURLString];
	NSURL *url = [NSURL URLWithString:urlString];
	if (!url || urlString.length == 0) {
		NSError *error = [NSError errorWithDomain:MAProviderErrorDomain
		                                      code:MAProviderErrorInvalidURL
		                                  userInfo:@{NSLocalizedDescriptionKey: MALocalizedString(@"Некорректный URL сервера")}];
		if (completion) completion(nil, error);
		return;
	}

	NSDictionary *body = [self requestBodyWithPrompt:prompt size:size];

	NSError *jsonError = nil;
	NSData *bodyData = [NSJSONSerialization dataWithJSONObject:body options:0 error:&jsonError];
	if (!bodyData) {
		if (completion) completion(nil, jsonError);
		return;
	}

	NSMutableURLRequest *request = [NSMutableURLRequest requestWithURL:url];
	request.HTTPMethod = @"POST";
	request.HTTPBody = bodyData;
	request.timeoutInterval = [self requestTimeoutInterval];
	[request setValue:@"application/json" forHTTPHeaderField:@"Content-Type"];
	if (self.apiKey.length > 0) {
		[request setValue:[NSString stringWithFormat:@"Bearer %@", self.apiKey] forHTTPHeaderField:@"Authorization"];
	}
	[self.extraHeaders enumerateKeysAndObjectsUsingBlock:^(NSString *key, NSString *value, BOOL *stop) {
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
             completion:(MAImageProviderCompletion)completion {
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

	NSArray *dataArray = json[@"data"];
	NSDictionary *firstItem = ([dataArray isKindOfClass:[NSArray class]] && dataArray.count > 0) ? dataArray[0] : nil;
	if (![firstItem isKindOfClass:[NSDictionary class]]) {
		NSError *error = [NSError errorWithDomain:MAProviderErrorDomain
		                                      code:MAProviderErrorBadResponse
		                                  userInfo:@{NSLocalizedDescriptionKey: MALocalizedString(@"Не удалось разобрать ответ сервера")}];
		if (completion) completion(nil, error);
		return;
	}

	NSString *base64 = firstItem[@"b64_json"];
	if ([base64 isKindOfClass:[NSString class]] && base64.length > 0) {
		NSData *imageData = MABase64Decode(base64);
		UIImage *image = imageData ? [UIImage imageWithData:imageData] : nil;
		if (image) {
			if (completion) completion(image, nil);
		} else {
			NSString *message = MALocalizedString(@"Не удалось декодировать изображение");
			NSString *mediaType = firstItem[@"media_type"]; // OpenRouter: image/svg+xml у векторных моделей
			if ([mediaType isKindOfClass:[NSString class]] && mediaType.length > 0) {
				message = [NSString stringWithFormat:@"%@ (%@)", message, mediaType];
			}
			NSError *error = [NSError errorWithDomain:MAProviderErrorDomain
			                                      code:MAProviderErrorBadResponse
			                                  userInfo:@{NSLocalizedDescriptionKey: message}];
			if (completion) completion(nil, error);
		}
		return;
	}

	NSString *urlString = firstItem[@"url"];
	if ([urlString isKindOfClass:[NSString class]] && urlString.length > 0) {
		[self downloadImageAtURLString:urlString completion:completion];
		return;
	}

	NSError *error = [NSError errorWithDomain:MAProviderErrorDomain
	                                      code:MAProviderErrorBadResponse
	                                  userInfo:@{NSLocalizedDescriptionKey: MALocalizedString(@"В ответе нет ни b64_json, ни url")}];
	if (completion) completion(nil, error);
}

- (void)downloadImageAtURLString:(NSString *)urlString completion:(MAImageProviderCompletion)completion {
	NSURL *url = [NSURL URLWithString:urlString];
	if (!url) {
		NSError *error = [NSError errorWithDomain:MAProviderErrorDomain
		                                      code:MAProviderErrorBadResponse
		                                  userInfo:@{NSLocalizedDescriptionKey: MALocalizedString(@"Некорректный URL изображения в ответе")}];
		if (completion) completion(nil, error);
		return;
	}

	NSURLRequest *request = [NSURLRequest requestWithURL:url];
	[MAHTTPClient sendAsynchronousRequest:request
	                            completion:^(NSURLResponse *response, NSData *data, NSError *connectionError) {
		if (connectionError || !data) {
			NSError *error = connectionError ?: [NSError errorWithDomain:MAProviderErrorDomain
			                                                          code:MAProviderErrorBadResponse
			                                                      userInfo:@{NSLocalizedDescriptionKey: MALocalizedString(@"Не удалось скачать изображение")}];
			if (completion) completion(nil, error);
			return;
		}
		UIImage *image = [UIImage imageWithData:data];
		if (image) {
			if (completion) completion(image, nil);
		} else {
			NSError *error = [NSError errorWithDomain:MAProviderErrorDomain
			                                      code:MAProviderErrorBadResponse
			                                  userInfo:@{NSLocalizedDescriptionKey: MALocalizedString(@"Файл по ссылке — не изображение")}];
			if (completion) completion(nil, error);
		}
	}];
}

- (NSString *)errorMessageFromJSON:(id)json fallback:(NSString *)fallback {
	if ([json isKindOfClass:[NSDictionary class]]) {
		id errorObj = json[@"error"];
		if ([errorObj isKindOfClass:[NSDictionary class]]) {
			id message = errorObj[@"message"];
			if ([message isKindOfClass:[NSString class]]) return message;
		} else if ([errorObj isKindOfClass:[NSString class]]) {
			return errorObj;
		}
	}
	return fallback ?: MALocalizedString(@"Неизвестная ошибка сервера");
}

@end
