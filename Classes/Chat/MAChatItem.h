#import <UIKit/UIKit.h>

@class MAMessage;

typedef NS_ENUM(NSInteger, MAChatItemKind) {
	MAChatItemKindText,
	MAChatItemKindImage
};

// Один элемент ленты чата на экране. Отдельно от MAMessage (истории для
// LLM), потому что сгенерированные картинки в текстовые провайдеры не
// отправляются — это чисто UI-сущность.
@interface MAChatItem : NSObject

@property (nonatomic, assign, readonly) MAChatItemKind kind;

// kind == MAChatItemKindText
@property (nonatomic, strong, readonly) MAMessage *message;

// kind == MAChatItemKindImage
@property (nonatomic, copy, readonly) NSString *imagePrompt;
@property (nonatomic, strong) UIImage *image;       // nil, пока не сгенерировалось
@property (nonatomic, assign) BOOL isLoading;
@property (nonatomic, copy) NSString *errorMessage; // если генерация не удалась

+ (instancetype)textItemWithMessage:(MAMessage *)message;
+ (instancetype)imageItemWithPrompt:(NSString *)prompt;

@end
