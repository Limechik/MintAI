#import "MAGeminiProvider.h"

@implementation MAGeminiProvider

- (instancetype)init {
	self = [super initWithIdentifier:@"gemini"
	                      displayName:@"Gemini"
	                    baseURLString:@"https://generativelanguage.googleapis.com/v1beta/openai"
	                            model:@"gemini-2.5-flash"];
	return self;
}

@end
