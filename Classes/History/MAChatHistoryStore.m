#import "MAChatHistoryStore.h"
#import "MAChatSession.h"

@interface MAChatHistoryStore ()
@property (nonatomic, strong) NSMutableArray *mutableSessions; // MAChatSession*
@end

@implementation MAChatHistoryStore

+ (instancetype)sharedStore {
	static MAChatHistoryStore *sharedStore = nil;
	static dispatch_once_t onceToken;
	dispatch_once(&onceToken, ^{
		sharedStore = [[self alloc] init];
	});
	return sharedStore;
}

- (instancetype)init {
	self = [super init];
	if (self) {
		_mutableSessions = [[self loadFromDisk] mutableCopy] ?: [NSMutableArray array];
		[self sortSessions];
	}
	return self;
}

- (NSArray *)sessions {
	return [self.mutableSessions copy];
}

- (void)saveSession:(MAChatSession *)session {
	if (!session.sessionID) return;

	NSUInteger existingIndex = [self.mutableSessions indexOfObjectPassingTest:^BOOL(MAChatSession *candidate, NSUInteger idx, BOOL *stop) {
		return [candidate.sessionID isEqualToString:session.sessionID];
	}];

	if (existingIndex == NSNotFound) {
		[self.mutableSessions addObject:session];
	} else {
		self.mutableSessions[existingIndex] = session;
	}

	[self sortSessions];
	[self persistToDisk];
}

- (void)deleteSession:(MAChatSession *)session {
	[self.mutableSessions removeObject:session];
	[self persistToDisk];
}

#pragma mark - Sorting

- (void)sortSessions {
	[self.mutableSessions sortUsingComparator:^NSComparisonResult(MAChatSession *a, MAChatSession *b) {
		return [b.updatedAt compare:a.updatedAt]; // новые сверху
	}];
}

#pragma mark - Persistence

- (NSString *)archivePath {
	NSArray *paths = NSSearchPathForDirectoriesInDomains(NSDocumentDirectory, NSUserDomainMask, YES);
	NSString *documentsDir = (paths.count > 0) ? paths[0] : nil;
	return [documentsDir stringByAppendingPathComponent:@"ChatHistory.archive"];
}

- (NSArray *)loadFromDisk {
	NSString *path = [self archivePath];
	if (![[NSFileManager defaultManager] fileExistsAtPath:path]) return nil;

	@try {
		NSData *data = [NSData dataWithContentsOfFile:path];
		if (!data) return nil;
		id decoded = [NSKeyedUnarchiver unarchiveObjectWithData:data];
		if ([decoded isKindOfClass:[NSArray class]]) {
			return decoded;
		}
	} @catch (NSException *exception) {
		// Повреждённый архив (например, от несовместимой старой версии) —
		// просто начинаем с пустой истории, а не падаем при запуске.
		return nil;
	}
	return nil;
}

- (void)persistToDisk {
	NSData *data = [NSKeyedArchiver archivedDataWithRootObject:self.sessions];
	[data writeToFile:[self archivePath] atomically:YES];
}

@end
