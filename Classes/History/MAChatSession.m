#import "MAChatSession.h"
#import "MAMessage.h"
#import "MALocalization.h"

static NSString *const kCoderSessionID = @"sessionID";
static NSString *const kCoderTitle = @"title";
static NSString *const kCoderCreatedAt = @"createdAt";
static NSString *const kCoderUpdatedAt = @"updatedAt";
static NSString *const kCoderMessages = @"messages";

@implementation MAChatSession

- (instancetype)init {
	self = [super init];
	if (self) {
		_sessionID = [[NSUUID UUID] UUIDString];
		_createdAt = [NSDate date];
		_updatedAt = [NSDate date];
		_messages = @[];
		_title = @"Новый чат";
	}
	return self;
}

- (NSString *)lastMessagePreview {
	for (MAMessage *message in [self.messages reverseObjectEnumerator]) {
		if (message.content.length > 0) {
			return message.content;
		}
		if (message.image) {
			return MALocalizedString(@"📷 Фото");
		}
	}
	return MALocalizedString(@"Нет сообщений");
}

- (NSString *)displayTitle {
	if ([self.title isEqualToString:@"Новый чат"]) return MALocalizedString(@"Новый чат");
	return self.title;
}

#pragma mark - NSCoding

- (void)encodeWithCoder:(NSCoder *)coder {
	[coder encodeObject:self.sessionID forKey:kCoderSessionID];
	[coder encodeObject:self.title forKey:kCoderTitle];
	[coder encodeObject:self.createdAt forKey:kCoderCreatedAt];
	[coder encodeObject:self.updatedAt forKey:kCoderUpdatedAt];
	[coder encodeObject:self.messages forKey:kCoderMessages];
}

- (id)initWithCoder:(NSCoder *)coder {
	self = [super init];
	if (self) {
		_sessionID = [coder decodeObjectForKey:kCoderSessionID];
		_title = [coder decodeObjectForKey:kCoderTitle] ?: @"Новый чат";
		_createdAt = [coder decodeObjectForKey:kCoderCreatedAt] ?: [NSDate date];
		_updatedAt = [coder decodeObjectForKey:kCoderUpdatedAt] ?: _createdAt;
		_messages = [coder decodeObjectForKey:kCoderMessages] ?: @[];
	}
	return self;
}

@end
