#import "MAImageProviderRegistry.h"
#import "MAOpenAIImageProvider.h"
#import "MAOpenRouterImageProvider.h"
#import "MACustomImageProvider.h"
#import "MAKeychain.h"

static NSString *const kActiveImageProviderDefaultsKey = @"MAActiveImageProviderIdentifier";

@implementation MAImageProviderRegistry

+ (instancetype)sharedRegistry {
	static MAImageProviderRegistry *shared = nil;
	static dispatch_once_t onceToken;
	dispatch_once(&onceToken, ^{
		shared = [[MAImageProviderRegistry alloc] init];
	});
	return shared;
}

- (instancetype)init {
	self = [super init];
	if (self) {
		_providers = @[
			[[MAOpenAIImageProvider alloc] init],
			[[MAOpenRouterImageProvider alloc] init],
			[[MACustomImageProvider alloc] init],
		];

		for (id<MAImageProvider> provider in self.providers) {
			[self loadPersistedSettingsIntoProvider:provider];
		}

		NSString *savedIdentifier = [[NSUserDefaults standardUserDefaults] stringForKey:kActiveImageProviderDefaultsKey];
		id<MAImageProvider> savedProvider = savedIdentifier ? [self providerWithIdentifier:savedIdentifier] : nil;
		_activeProvider = savedProvider ?: ((self.providers.count > 0) ? self.providers[0] : nil);
	}
	return self;
}

- (void)setActiveProvider:(id<MAImageProvider>)activeProvider {
	_activeProvider = activeProvider;
	[[NSUserDefaults standardUserDefaults] setObject:activeProvider.identifier forKey:kActiveImageProviderDefaultsKey];
	[[NSUserDefaults standardUserDefaults] synchronize];
}

- (id<MAImageProvider>)providerWithIdentifier:(NSString *)identifier {
	for (id<MAImageProvider> provider in self.providers) {
		if ([provider.identifier isEqualToString:identifier]) {
			return provider;
		}
	}
	return nil;
}

#pragma mark - Persistence

// Отдельный неймспейс от чат-провайдеров ("image.") — можно указать другой
// ключ/URL для картинок, а можно просто продублировать тот же, что и в чате.

- (NSString *)apiKeyKeychainKeyForProvider:(id<MAImageProvider>)provider {
	return [NSString stringWithFormat:@"apiKey.image.%@", provider.identifier];
}

- (NSString *)baseURLDefaultsKeyForProvider:(id<MAImageProvider>)provider {
	return [NSString stringWithFormat:@"MAImageBaseURL.%@", provider.identifier];
}

- (NSString *)modelDefaultsKeyForProvider:(id<MAImageProvider>)provider {
	return [NSString stringWithFormat:@"MAImageModel.%@", provider.identifier];
}

- (void)loadPersistedSettingsIntoProvider:(id<MAImageProvider>)provider {
	NSString *savedKey = [MAKeychain stringForKey:[self apiKeyKeychainKeyForProvider:provider]];
	if (savedKey.length > 0) {
		provider.apiKey = savedKey;
	}

	NSUserDefaults *defaults = [NSUserDefaults standardUserDefaults];

	NSString *savedBaseURL = [defaults stringForKey:[self baseURLDefaultsKeyForProvider:provider]];
	if (savedBaseURL.length > 0) {
		provider.baseURLString = savedBaseURL;
	}

	NSString *savedModel = [defaults stringForKey:[self modelDefaultsKeyForProvider:provider]];
	if (savedModel.length > 0) {
		provider.model = savedModel;
	}
}

- (void)persistSettingsForProvider:(id<MAImageProvider>)provider {
	[MAKeychain setString:provider.apiKey forKey:[self apiKeyKeychainKeyForProvider:provider]];

	NSUserDefaults *defaults = [NSUserDefaults standardUserDefaults];
	[defaults setObject:(provider.baseURLString ?: @"") forKey:[self baseURLDefaultsKeyForProvider:provider]];
	[defaults setObject:(provider.model ?: @"") forKey:[self modelDefaultsKeyForProvider:provider]];
	[defaults synchronize];
}

@end
