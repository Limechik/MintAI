#import "MAMistralProvider.h"

@implementation MAMistralProvider

- (instancetype)init {
	// Mistral отдаёт OpenAI-совместимый /v1/chat/completions напрямую —
	// отдельная реализация не нужна, только identifier/URL/модель по умолчанию.
	self = [super initWithIdentifier:@"mistral"
	                      displayName:@"Mistral"
	                    baseURLString:@"https://api.mistral.ai/v1"
	                            model:@"mistral-large-latest"];
	return self;
}

@end
