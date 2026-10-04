#import <Foundation/Foundation.h>

@class MAChatSession;

// Синглтон для чтения/записи списка сохранённых бесед на диск
// (~/Documents/ChatHistory.archive, NSKeyedArchiver — просто и достаточно
// для скелета; без Core Data). Список отсортирован по updatedAt, новые сверху.
@interface MAChatHistoryStore : NSObject

+ (instancetype)sharedStore;

@property (nonatomic, strong, readonly) NSArray *sessions; // MAChatSession*, сорт. по updatedAt desc

// Добавляет сессию (если её ещё нет) или обновляет существующую по sessionID,
// пишет на диск и сортирует список заново.
- (void)saveSession:(MAChatSession *)session;

- (void)deleteSession:(MAChatSession *)session;

@end
