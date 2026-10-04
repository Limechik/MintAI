#import "MADeepSeekProvider.h"

@implementation MADeepSeekProvider

- (instancetype)init {
	self = [super initWithIdentifier:@"deepseek"
	                      displayName:@"DeepSeek"
	                    baseURLString:@"https://api.deepseek.com/v1"
	                            model:@"deepseek-chat"];
	return self;
}

@end
