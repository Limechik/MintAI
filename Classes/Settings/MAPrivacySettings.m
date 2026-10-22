#import "MAPrivacySettings.h"

NSString *const MAIncognitoDidChangeNotification = @"MAIncognitoDidChangeNotification";

static NSString *const kIncognitoDefaultsKey = @"MAIncognitoMode";

@implementation MAPrivacySettings

+ (instancetype)sharedSettings {
	static MAPrivacySettings *shared = nil;
	static dispatch_once_t onceToken;
	dispatch_once(&onceToken, ^{
		shared = [[MAPrivacySettings alloc] init];
	});
	return shared;
}

- (BOOL)isIncognito {
	return [[NSUserDefaults standardUserDefaults] boolForKey:kIncognitoDefaultsKey];
}

- (void)setIncognito:(BOOL)incognito {
	if (incognito == self.incognito) return;

	NSUserDefaults *defaults = [NSUserDefaults standardUserDefaults];
	[defaults setBool:incognito forKey:kIncognitoDefaultsKey];
	[defaults synchronize];
	[[NSNotificationCenter defaultCenter] postNotificationName:MAIncognitoDidChangeNotification object:self];
}

@end
