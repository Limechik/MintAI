#import "MAOpenAIImageProvider.h"

@implementation MAOpenAIImageProvider

- (instancetype)init {
	// TODO: dall-e-3 — надёжный дефолт на сегодня; при желании можно
	// переключить на более новую модель прямо в Settings (поле "Модель").
	self = [super initWithIdentifier:@"openai-image"
	                      displayName:@"OpenAI (DALL·E)"
	                    baseURLString:@"https://api.openai.com/v1"
	                            model:@"dall-e-3"];
	return self;
}

@end
