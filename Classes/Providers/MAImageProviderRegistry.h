#import <Foundation/Foundation.h>
#import "MAImageProvider.h"

// Реестр провайдеров генерации изображений — по аналогии с MAProviderRegistry,
// но отдельно от чата: свои ключи в Keychain/NSUserDefaults, свой активный
// провайдер (используется вкладкой Images).
@interface MAImageProviderRegistry : NSObject

+ (instancetype)sharedRegistry;

// OpenAI (DALL·E), OpenRouter, Custom — в этом порядке.
@property (nonatomic, strong, readonly) NSArray *providers;

@property (nonatomic, strong) id<MAImageProvider> activeProvider;

- (id<MAImageProvider>)providerWithIdentifier:(NSString *)identifier;

- (void)persistSettingsForProvider:(id<MAImageProvider>)provider;

@end
