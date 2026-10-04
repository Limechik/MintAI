#import "MAOpenAIProvider.h"

@implementation MAOpenAIProvider

- (instancetype)init {
	// Модель по умолчанию — недорогая и быстрая; пользователь сможет
	// сменить её в Settings на любую другую (gpt-4o, gpt-4.1 и т.д.).
	self = [super initWithIdentifier:@"openai"
	                      displayName:@"OpenAI"
	                    baseURLString:@"https://api.openai.com/v1"
	                            model:@"gpt-4o-mini"];
	return self;
}

@end
