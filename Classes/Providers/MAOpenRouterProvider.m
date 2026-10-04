#import "MAOpenRouterProvider.h"

@implementation MAOpenRouterProvider

- (instancetype)init {
	self = [super initWithIdentifier:@"openrouter"
	                      displayName:@"OpenRouter"
	                    baseURLString:@"https://openrouter.ai/api/v1"
	                            model:@"openai/gpt-4o-mini"];
	if (self) {
		// OpenRouter просит эти заголовки для идентификации приложения
		// (не обязательны технически, но рекомендованы их доками).
		self.extraHeaders = @{
			@"HTTP-Referer": @"https://mintai.app",
			@"X-Title": @"MintAI"
		};
	}
	return self;
}

@end
