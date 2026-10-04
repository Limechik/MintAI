#import <UIKit/UIKit.h>

typedef NS_ENUM(NSInteger, MAMessageRole) {
	MAMessageRoleSystem,
	MAMessageRoleUser,
	MAMessageRoleAssistant
};

// Одно сообщение в истории диалога. Не зависит от конкретного провайдера —
// каждый провайдер сам конвертирует историю в свой формат запроса.
// Поддерживает NSCoding, чтобы сообщения можно было сохранять в
// MAChatHistoryStore (см. Classes/History) между запусками приложения.
@interface MAMessage : NSObject <NSCoding>

@property (nonatomic, assign, readonly) MAMessageRole role;
@property (nonatomic, copy, readonly) NSString *content;

// Момент отправки/получения сообщения — проставляется автоматически при
// создании (см. -initWithRole:content:image:) и сохраняется вместе с
// остальными полями через NSCoding, чтобы время не "съезжало" на дату
// открытия истории. Показывается в чате как "18:00" (см. MAChatMessageCell).
@property (nonatomic, strong, readonly) NSDate *date;

// Фото, прикреплённое пользователем к сообщению (nil у обычных текстовых
// сообщений и у ответов ассистента). В отличие от результатов генерации
// (/suno, /generateImage — см. MAChatItemKindImage), это фото ЕСТЬ в истории
// и уходит провайдеру как часть запроса, то есть требует vision-модели.
@property (nonatomic, strong, readonly) UIImage *image;

+ (instancetype)messageWithRole:(MAMessageRole)role content:(NSString *)content;
+ (instancetype)messageWithRole:(MAMessageRole)role content:(NSString *)content image:(UIImage *)image;
- (instancetype)initWithRole:(MAMessageRole)role content:(NSString *)content;
- (instancetype)initWithRole:(MAMessageRole)role content:(NSString *)content image:(UIImage *)image;

// "system" / "user" / "assistant" — как ожидают почти все Chat Completion API.
- (NSString *)roleString;

// Уменьшенная (макс. сторона ~1280px) и сжатая в JPEG (0.7) картинка,
// закодированная в base64, — то, что реально уходит в тело запроса.
// nil, если image отсутствует или JPEG не удалось получить.
- (NSString *)imageBase64JPEG;

@end
