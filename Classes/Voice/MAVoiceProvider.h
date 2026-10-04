#import <Foundation/Foundation.h>
#import "MAConfigurableProvider.h"

// Настройки одного голосового «провайдера» — либо озвучки (TTS,
// /audio/speech), либо распознавания речи (STT, /audio/transcriptions).
// Оба работают по OpenAI-совместимому API, поэтому подходят и OpenAI, и
// Groq (whisper бесплатно), и любой локальный сервер — достаточно поменять
// Base URL / модель в Settings. Реализует MAConfigurableProvider, так что
// экран MAProviderDetailViewController работает с ним без изменений.
@interface MAVoiceProvider : NSObject <MAConfigurableProvider>

@property (nonatomic, copy, readonly) NSString *identifier;
@property (nonatomic, copy, readonly) NSString *displayName;
@property (nonatomic, assign, readwrite) BOOL requiresAPIKey;
@property (nonatomic, copy) NSString *apiKey;
@property (nonatomic, copy) NSString *baseURLString;
@property (nonatomic, copy) NSString *model;

- (instancetype)initWithIdentifier:(NSString *)identifier
                        displayName:(NSString *)displayName
                      baseURLString:(NSString *)baseURLString
                              model:(NSString *)model;

@end
