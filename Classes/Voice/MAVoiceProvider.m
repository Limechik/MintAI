#import "MAVoiceProvider.h"
#import "MALocalization.h"

@implementation MAVoiceProvider

@synthesize displayName = _displayName;

// Название хранится русским ключом и переводится при показе, чтобы менять язык на лету.
- (NSString *)displayName {
	return MALocalizedString(_displayName);
}

- (instancetype)initWithIdentifier:(NSString *)identifier
                        displayName:(NSString *)displayName
                      baseURLString:(NSString *)baseURLString
                              model:(NSString *)model {
	self = [super init];
	if (self) {
		_identifier = [identifier copy];
		_displayName = [displayName copy];
		_baseURLString = [baseURLString copy];
		_model = [model copy];
		_requiresAPIKey = YES;
	}
	return self;
}

@end
