#import "MAOpenCodeZenProvider.h"

@implementation MAOpenCodeZenProvider

- (instancetype)init {
	self = [super initWithIdentifier:@"opencode-zen"
	                      displayName:@"OpenCode Zen"
	                    baseURLString:@"https://opencode.ai/zen/v1"
	                            model:@"big-pickle"];
	return self;
}

@end
