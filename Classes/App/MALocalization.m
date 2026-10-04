#import "MALocalization.h"

NSString *const MALanguageDidChangeNotification = @"MALanguageDidChangeNotification";
NSString *const MALanguageCodeRussian = @"ru";
NSString *const MALanguageCodeEnglish = @"en";

static NSString *const kLanguageDefaultsKey = @"MAInterfaceLanguage";

NSString *MALocalizedString(NSString *key) {
	return [[MALocalization sharedLocalization] localizedStringForKey:key];
}

@interface MALocalization ()
@property (nonatomic, strong) NSBundle *englishBundle;
@property (nonatomic, assign) BOOL englishBundleLoaded;
@end

@implementation MALocalization

+ (instancetype)sharedLocalization {
	static MALocalization *shared = nil;
	static dispatch_once_t onceToken;
	dispatch_once(&onceToken, ^{
		shared = [[MALocalization alloc] init];
	});
	return shared;
}

- (NSString *)languageCode {
	NSString *saved = [[NSUserDefaults standardUserDefaults] stringForKey:kLanguageDefaultsKey];
	return [saved isEqualToString:MALanguageCodeEnglish] ? MALanguageCodeEnglish : MALanguageCodeRussian;
}

- (void)setLanguageCode:(NSString *)languageCode {
	NSString *normalized = [languageCode isEqualToString:MALanguageCodeEnglish] ? MALanguageCodeEnglish : MALanguageCodeRussian;
	if ([normalized isEqualToString:self.languageCode]) return;

	NSUserDefaults *defaults = [NSUserDefaults standardUserDefaults];
	[defaults setObject:normalized forKey:kLanguageDefaultsKey];
	[defaults synchronize];
	[[NSNotificationCenter defaultCenter] postNotificationName:MALanguageDidChangeNotification object:self];
}

- (BOOL)isEnglish {
	return [self.languageCode isEqualToString:MALanguageCodeEnglish];
}

- (NSBundle *)bundleForEnglish {
	if (!self.englishBundleLoaded) {
		self.englishBundleLoaded = YES;
		NSString *path = [[NSBundle mainBundle] pathForResource:@"en" ofType:@"lproj"];
		if (path) self.englishBundle = [NSBundle bundleWithPath:path];
	}
	return self.englishBundle;
}

- (NSString *)localizedStringForKey:(NSString *)key {
	if (key.length == 0 || !self.english) return key;

	NSBundle *bundle = [self bundleForEnglish];
	if (!bundle) return key;
	// value:key — если перевода нет, отдаём исходный (русский) текст, а не пустоту.
	return [bundle localizedStringForKey:key value:key table:nil];
}

@end
