#import "MAInstructionsStore.h"

static NSString *const kInstructionsTextKey = @"MAInstructionsText";
static NSString *const kInstructionsEnabledKey = @"MAInstructionsEnabled";

@implementation MAInstructionsStore

+ (instancetype)sharedStore {
	static MAInstructionsStore *store = nil;
	static dispatch_once_t onceToken;
	dispatch_once(&onceToken, ^{
		store = [[MAInstructionsStore alloc] init];
	});
	return store;
}

- (NSString *)instructions {
	NSString *saved = [[NSUserDefaults standardUserDefaults] stringForKey:kInstructionsTextKey];
	return saved ?: @"";
}

- (void)setInstructions:(NSString *)instructions {
	[[NSUserDefaults standardUserDefaults] setObject:(instructions ?: @"") forKey:kInstructionsTextKey];
}

- (BOOL)enabled {
	NSNumber *saved = [[NSUserDefaults standardUserDefaults] objectForKey:kInstructionsEnabledKey];
	return saved ? saved.boolValue : YES;
}

- (void)setEnabled:(BOOL)enabled {
	[[NSUserDefaults standardUserDefaults] setBool:enabled forKey:kInstructionsEnabledKey];
	[self synchronize];
}

- (NSString *)activeInstructions {
	if (!self.enabled) return nil;
	NSString *trimmed = [self.instructions stringByTrimmingCharactersInSet:[NSCharacterSet whitespaceAndNewlineCharacterSet]];
	return trimmed.length > 0 ? trimmed : nil;
}

- (void)synchronize {
	[[NSUserDefaults standardUserDefaults] synchronize];
}

@end
