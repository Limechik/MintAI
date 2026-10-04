#import <Foundation/Foundation.h>
#import "MAProvider.h"

// Единая точка доступа ко всем провайдерам приложения. UI (Settings, Chat)
// работает через этот реестр, не создавая провайдеров напрямую.
//
// Персистентность ключей/URL/модели (Keychain для ключей, NSUserDefaults для
// остального) — задача экрана Settings, реестр сам по себе её не делает.
@interface MAProviderRegistry : NSObject

+ (instancetype)sharedRegistry;

// Все провайдеры чата в порядке показа в UI:
// DeepSeek, OpenAI, Claude, OpenRouter, Mistral, Gemini, OpenCode Zen, Custom.
@property (nonatomic, strong, readonly) NSArray *providers;

// Провайдер, выбранный сейчас для отправки сообщений в чате.
@property (nonatomic, strong) id<MAProvider> activeProvider;

- (id<MAProvider>)providerWithIdentifier:(NSString *)identifier;

// Сохраняет apiKey (в Keychain) и baseURLString/model (в NSUserDefaults)
// текущего состояния провайдера. Вызывать после редактирования на экране
// настроек конкретного провайдера.
- (void)persistSettingsForProvider:(id<MAProvider>)provider;

@end
