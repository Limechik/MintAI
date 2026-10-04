#import "MAChatItem.h"
#import "MAMessage.h"

@interface MAChatItem ()
@property (nonatomic, assign, readwrite) MAChatItemKind kind;
@property (nonatomic, strong, readwrite) MAMessage *message;
@property (nonatomic, copy, readwrite) NSString *imagePrompt;
@end

@implementation MAChatItem

+ (instancetype)textItemWithMessage:(MAMessage *)message {
	MAChatItem *item = [[self alloc] init];
	item.kind = MAChatItemKindText;
	item.message = message;
	return item;
}

+ (instancetype)imageItemWithPrompt:(NSString *)prompt {
	MAChatItem *item = [[self alloc] init];
	item.kind = MAChatItemKindImage;
	item.imagePrompt = prompt;
	item.isLoading = YES;
	return item;
}

@end
