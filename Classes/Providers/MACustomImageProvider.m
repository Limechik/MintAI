#import "MACustomImageProvider.h"

@implementation MACustomImageProvider

- (instancetype)init {
	self = [super initWithIdentifier:@"custom-image"
	                      displayName:@"Custom / Local"
	                    baseURLString:@""
	                            model:@""];
	if (self) {
		self.requiresAPIKey = NO;
	}
	return self;
}

@end
