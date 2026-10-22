#import "MAProviderRegistry.h"
#import "MADeepSeekProvider.h"
#import "MAOpenAIProvider.h"
#import "MAClaudeProvider.h"
#import "MAOpenRouterProvider.h"
#import "MAMistralProvider.h"
#import "MAGeminiProvider.h"
#import "MAOpenCodeZenProvider.h"
#import "MALocalProvider.h"
#import "MACustomProvider.h"
#import "MAKeychain.h"

static NSString *const kActiveProviderDefaultsKey = @"MAActiveProviderIdentifier";

@implementation MAProviderRegistry

+ (instancetype)sharedRegistry {
	static MAProviderRegistry *shared = nil;
	static dispatch_once_t onceToken;
	dispatch_once(&onceToken, ^{
		shared = [[MAProviderRegistry alloc] init];
	});
	return shared;
}

- (instancetype)init {
	self = [super init];
	if (self) {
		_providers = @[
			[[MADeepSeekProvider alloc] init],
			[[MAOpenAIProvider alloc] init],
			[[MAClaudeProvider alloc] init],
			[[MAOpenRouterProvider alloc] init],
			[[MAMistralProvider alloc] init],
			[[MAGeminiProvider alloc] init],
			[[MAOpenCodeZenProvider alloc] init],
			[[MALocalProvider alloc] init],
			[[MACustomProvider alloc] init],
		];

		for (id<MAProvider> provider in self.providers) {
			[self loadPersistedSettingsIntoProvider:provider];
		}

		NSString *savedIdentifier = [[NSUserDefaults standardUserDefaults] stringForKey:kActiveProviderDefaultsKey];
		id<MAProvider> savedProvider = savedIdentifier ? [self providerWithIdentifier:savedIdentifier] : nil;
		_activeProvider = savedProvider ?: ((self.providers.count > 0) ? self.providers[0] : nil);
	}
	return self;
}

- (void)setActiveProvider:(id<MAProvider>)activeProvider {
	_activeProvider = activeProvider;
	[[NSUserDefaults standardUserDefaults] setObject:activeProvider.identifier forKey:kActiveProviderDefaultsKey];
	[[NSUserDefaults standardUserDefaults] synchronize];
}

- (id<MAProvider>)providerWithIdentifier:(NSString *)identifier {
	for (id<MAProvider> provider in self.providers) {
		if ([provider.identifier isEqualToString:identifier]) {
			return provider;
		}
	}
	return nil;
}

#pragma mark - Persistence

- (NSString *)apiKeyKeychainKeyForProvider:(id<MAProvider>)provider {
	return [NSString stringWithFormat:@"apiKey.%@", provider.identifier];
}

- (NSString *)baseURLDefaultsKeyForProvider:(id<MAProvider>)provider {
	return [NSString stringWithFormat:@"MABaseURL.%@", provider.identifier];
}

- (NSString *)modelDefaultsKeyForProvider:(id<MAProvider>)provider {
	return [NSString stringWithFormat:@"MAModel.%@", provider.identifier];
}

- (void)loadPersistedSettingsIntoProvider:(id<MAProvider>)provider {
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

- (void)persistSettingsForProvider:(id<MAProvider>)provider {
	[MAKeychain setString:provider.apiKey forKey:[self apiKeyKeychainKeyForProvider:provider]];

	NSUserDefaults *defaults = [NSUserDefaults standardUserDefaults];
	[defaults setObject:(provider.baseURLString ?: @"") forKey:[self baseURLDefaultsKeyForProvider:provider]];
	[defaults setObject:(provider.model ?: @"") forKey:[self modelDefaultsKeyForProvider:provider]];
	[defaults synchronize];
}

@end
