#import "MACustomProvider.h"

@implementation MACustomProvider

- (instancetype)init {
	self = [super initWithIdentifier:@"custom"
	                      displayName:@"Custom"
	                    baseURLString:@""
	                            model:@""];
	if (self) {
		// Локальные сервера (LM Studio, Ollama и т.п.) обычно не требуют ключа.
		// Пользователь сможет включить требование ключа в Settings, если его
		// сервер всё же защищён.
		self.requiresAPIKey = NO;
	}
	return self;
}

@end
