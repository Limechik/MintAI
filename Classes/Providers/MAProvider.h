#import <Foundation/Foundation.h>
#import "MAConfigurableProvider.h"

@class MAMessage;

// replyText != nil при успехе, error != nil при неудаче — ровно один из двух.
typedef void (^MAProviderCompletion)(NSString *replyText, NSError *error);

// Общий интерфейс любого чат-провайдера: DeepSeek, OpenAI, Claude, OpenRouter
// или кастомный/локальный сервер. UI работает только через этот протокол,
// не зная, с кем на самом деле говорит. Настраиваемые поля (ключ/URL/модель) —
// в MAConfigurableProvider, общем и с MAImageProvider.
@protocol MAProvider <MAConfigurableProvider>

// Отправляет всю историю диалога и получает ответ ассистента.
// completion вызывается на main thread.
- (void)sendMessages:(NSArray *)messages completion:(MAProviderCompletion)completion;

@end
