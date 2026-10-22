#import "MALocalProvider.h"
#import "MALocalization.h"
#import "MAHTTPClient.h"

// Локальная модель на CPU отвечает долго, а при нестриминговом запросе до конца генерации
// не приходит ни одного байта. 10 минут — запас на загрузку модели и длинный ответ.
static const NSTimeInterval kLocalRequestTimeout = 600;
static const NSTimeInterval kModelsRequestTimeout = 15;

@implementation MALocalProvider

- (instancetype)init {
	self = [super initWithIdentifier:@"local"
	                     displayName:@"Local LLM"
	                   baseURLString:@""
	                           model:@""];
	if (self) {
		self.requiresAPIKey = NO;
		self.requestTimeout = kLocalRequestTimeout;
	}
	return self;
}

+ (NSArray *)presets {
	return @[
		@{@"name": @"Ollama",                @"port": @"11434"},
		@{@"name": @"LM Studio",             @"port": @"1234"},
		@{@"name": @"llama.cpp",             @"port": @"8080"},
		@{@"name": @"text-generation-webui", @"port": @"5000"},
	];
}

#pragma mark - Чат

- (void)sendMessages:(NSArray *)messages completion:(MAProviderCompletion)completion {
	[super sendMessages:messages completion:^(NSString *replyText, NSError *error) {
		if (!completion) return;
		if (error) {
			completion(nil, [self friendlyErrorFromError:error]);
			return;
		}
		completion([MALocalProvider replyByRemovingThinking:replyText], nil);
	}];
}

// Reasoning-модели (DeepSeek-R1, Qwen3 и т.п.) кладут рассуждения в сам ответ:
// «<think>…</think> настоящий ответ». В чате они не нужны. Бывает и вариант без открывающего
// тега (шаблон модели уже открыл его в промпте) — тогда ответ начинается сразу с рассуждений
// и заканчивающего «</think>». Если после тега ничего нет, оставляем исходный текст.
+ (NSString *)replyByRemovingThinking:(NSString *)reply {
	if (reply.length == 0) return reply;

	NSCharacterSet *whitespace = [NSCharacterSet whitespaceAndNewlineCharacterSet];
	NSString *trimmed = [reply stringByTrimmingCharactersInSet:whitespace];
	BOOL startsWithThink = [trimmed hasPrefix:@"<think>"];
	BOOL hasOpening = ([reply rangeOfString:@"<think>"].location != NSNotFound);

	NSRange closing = [reply rangeOfString:@"</think>" options:NSBackwardsSearch];
	if (closing.location == NSNotFound) return reply;
	if (!startsWithThink && hasOpening) return reply; // тег где-то посреди текста — не трогаем

	NSString *tail = [[reply substringFromIndex:NSMaxRange(closing)] stringByTrimmingCharactersInSet:whitespace];
	return (tail.length > 0) ? tail : reply;
}

#pragma mark - Ошибки

- (NSError *)friendlyErrorFromError:(NSError *)error {
	if (![error.domain isEqualToString:NSURLErrorDomain]) return error;

	NSString *text = nil;
	switch (error.code) {
		case NSURLErrorCannotConnectToHost:
		case NSURLErrorCannotFindHost:
		case NSURLErrorDNSLookupFailed:
		case NSURLErrorNetworkConnectionLost:
		case NSURLErrorNotConnectedToInternet: {
			NSString *hint = MALocalizedString(@"Не удалось подключиться к серверу. Проверьте: сервер запущен, iPhone и ПК в одной Wi-Fi сети, адрес указан как http://IP:порт/v1, брандмауэр пропускает порт.");
			text = (self.baseURLString.length > 0) ? [hint stringByAppendingFormat:@"\n\n%@", self.baseURLString] : hint;
			break;
		}
		case NSURLErrorTimedOut:
			text = MALocalizedString(@"Сервер слишком долго отвечает. Возможно, модель ещё загружается или она слишком тяжёлая для этого ПК. Попробуйте ещё раз.");
			break;
		default:
			return error;
	}
	return [NSError errorWithDomain:MAProviderErrorDomain
	                           code:MAProviderErrorServerError
	                       userInfo:@{NSLocalizedDescriptionKey: text, NSUnderlyingErrorKey: error}];
}

#pragma mark - Список моделей

- (NSString *)serverRootURLString {
	NSString *base = [self.baseURLString stringByTrimmingCharactersInSet:[NSCharacterSet whitespaceAndNewlineCharacterSet]];
	while ([base hasSuffix:@"/"]) base = [base substringToIndex:base.length - 1];
	if ([base hasSuffix:@"/chat/completions"]) {
		base = [base substringToIndex:base.length - [@"/chat/completions" length]];
	}
	return base;
}

- (void)fetchModelsWithCompletion:(void (^)(NSArray *, NSError *))completion {
	if (!completion) return;

	NSString *root = [self serverRootURLString];
	NSURL *url = (root.length > 0) ? [NSURL URLWithString:[root stringByAppendingString:@"/models"]] : nil;
	if (!url) {
		completion(nil, [NSError errorWithDomain:MAProviderErrorDomain
		                                    code:MAProviderErrorInvalidURL
		                                userInfo:@{NSLocalizedDescriptionKey: MALocalizedString(@"Некорректный URL сервера")}]);
		return;
	}

	NSMutableURLRequest *request = [NSMutableURLRequest requestWithURL:url];
	request.HTTPMethod = @"GET";
	request.timeoutInterval = kModelsRequestTimeout;
	if (self.apiKey.length > 0) {
		[request setValue:[NSString stringWithFormat:@"Bearer %@", self.apiKey] forHTTPHeaderField:@"Authorization"];
	}

	[MAHTTPClient sendAsynchronousRequest:request completion:^(NSURLResponse *response, NSData *data, NSError *connectionError) {
		if (connectionError) {
			completion(nil, [self friendlyErrorFromError:connectionError]);
			return;
		}

		NSInteger status = [response isKindOfClass:[NSHTTPURLResponse class]] ? [(NSHTTPURLResponse *)response statusCode] : 200;
		if (status < 200 || status >= 300) {
			NSString *text = [NSString stringWithFormat:@"%ld: %@", (long)status, [NSHTTPURLResponse localizedStringForStatusCode:status]];
			completion(nil, [NSError errorWithDomain:MAProviderErrorDomain
			                                    code:MAProviderErrorServerError
			                                userInfo:@{NSLocalizedDescriptionKey: text}]);
			return;
		}

		NSArray *models = [MALocalProvider modelIDsFromResponseData:data];
		if (!models) {
			completion(nil, [NSError errorWithDomain:MAProviderErrorDomain
			                                    code:MAProviderErrorBadResponse
			                                userInfo:@{NSLocalizedDescriptionKey: MALocalizedString(@"Не удалось разобрать ответ сервера")}]);
			return;
		}
		completion(models, nil);
	}];
}

// nil — ответ не похож на список моделей; пустой массив — сервер ответил, но моделей нет.
+ (NSArray *)modelIDsFromResponseData:(NSData *)data {
	id json = data ? [NSJSONSerialization JSONObjectWithData:data options:0 error:NULL] : nil;
	if (![json isKindOfClass:[NSDictionary class]]) return nil;

	id list = json[@"data"];                                  // OpenAI, LM Studio, llama.cpp, Ollama /v1
	if (![list isKindOfClass:[NSArray class]]) list = json[@"models"]; // нативный Ollama (/api/tags), llama.cpp
	if (![list isKindOfClass:[NSArray class]]) return nil;

	NSMutableOrderedSet *ids = [NSMutableOrderedSet orderedSet];
	for (id entry in list) {
		NSString *name = nil;
		if ([entry isKindOfClass:[NSString class]]) {
			name = entry;
		} else if ([entry isKindOfClass:[NSDictionary class]]) {
			for (NSString *key in @[@"id", @"name", @"model"]) {
				if ([entry[key] isKindOfClass:[NSString class]] && [entry[key] length] > 0) { name = entry[key]; break; }
			}
		}
		if (name.length > 0) [ids addObject:name];
	}
	return [[ids array] sortedArrayUsingSelector:@selector(localizedCaseInsensitiveCompare:)];
}

@end
