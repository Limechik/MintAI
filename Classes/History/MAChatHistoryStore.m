#import "MAChatHistoryStore.h"
#import "MAChatSession.h"
#import "MAVault.h"

@interface MAChatHistoryStore ()
@property (nonatomic, strong) NSMutableArray *mutableSessions; // MAChatSession*
// NO, пока на диске лежит зашифрованная история, которую сейчас нечем прочитать
// (хранилище закрыто). Запись в таком состоянии затёрла бы её пустым списком.
@property (nonatomic, assign) BOOL canPersist;
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
		_canPersist = YES;
		BOOL needsMigration = NO;
		_mutableSessions = [[self loadFromDiskNeedsMigration:&needsMigration] mutableCopy] ?: [NSMutableArray array];
		[self sortSessions];
		// История от старой версии лежала открытым текстом: пересохраняем уже зашифрованной.
		if (needsMigration) [self persistToDisk];
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

- (NSArray *)loadFromDiskNeedsMigration:(BOOL *)needsMigration {
	NSString *path = [self archivePath];
	if (![[NSFileManager defaultManager] fileExistsAtPath:path]) return nil;

	MAVault *vault = [MAVault sharedVault];

	@try {
		NSData *data = [NSData dataWithContentsOfFile:path];
		if (!data) return nil;

		if ([MAVault dataIsEncrypted:data]) {
			if (!vault.unlocked && !vault.unavailable) {
				// Хранилище закрыто (ждёт PIN): историю не трогаем и не перезаписываем.
				self.canPersist = NO;
				return nil;
			}
			NSData *plain = [vault decryptData:data];
			if (!plain) {
				// Ключ утерян (например, резервную копию восстановили на другое
				// устройство) или файл повреждён. Откладываем его в сторону, а не
				// затираем, и начинаем с пустой истории.
				NSString *asidePath = [path stringByAppendingString:@".unreadable"];
				[[NSFileManager defaultManager] removeItemAtPath:asidePath error:nil];
				[[NSFileManager defaultManager] moveItemAtPath:path toPath:asidePath error:nil];
				return nil;
			}
			data = plain;
		} else if (needsMigration) {
			*needsMigration = vault.unlocked; // открытый текст от старой версии
		}

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
	if (!self.canPersist) return;

	NSData *archive = [NSKeyedArchiver archivedDataWithRootObject:self.sessions];
	MAVault *vault = [MAVault sharedVault];

	NSData *data = [vault encryptData:archive];
	if (!data) {
		if (!vault.unavailable) {
			NSLog(@"[MAChatHistoryStore] хранилище закрыто — историю не записываем");
			return;
		}
		data = archive; // шифрование недоступно: пишем как раньше, чтобы история не пропала
	}
	[data writeToFile:[self archivePath] options:NSDataWritingAtomic error:nil];
}

@end
