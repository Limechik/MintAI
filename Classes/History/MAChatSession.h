#import <Foundation/Foundation.h>

@class MAMessage;

// Одна сохранённая беседа: список сообщений плюс метаданные для списка
// в MAChatHistoryViewController. Название генерируется автоматически из
// первого сообщения пользователя (см. MAChatViewController), пользователь
// его не редактирует — для скелета этого достаточно.
@interface MAChatSession : NSObject <NSCoding>

@property (nonatomic, copy, readonly) NSString *sessionID;
@property (nonatomic, copy) NSString *title;
@property (nonatomic, strong, readonly) NSDate *createdAt;
@property (nonatomic, strong) NSDate *updatedAt;
@property (nonatomic, copy) NSArray *messages; // MAMessage*

- (instancetype)init; // генерирует новый sessionID и createdAt/updatedAt = now

// Текст последнего сообщения — используется как подзаголовок в списке истории.
- (NSString *)lastMessagePreview;

// Название для показа в списке: служебное «Новый чат» переводится на текущий язык, остальное —
// как есть (в файле название хранится исходным, чтобы не зависеть от языка на момент сохранения).
- (NSString *)displayTitle;

@end
