#import <Foundation/Foundation.h>

typedef void (^MAHTTPCompletion)(NSURLResponse *response, NSData *data, NSError *error);

// Замена [NSURLConnection sendAsynchronousRequest:queue:completionHandler:].
//
// Почему это нужно: тот метод не даёт подключить делегат, а значит и
// обработать authentication challenge для NSURLAuthenticationMethodServerTrust
// самостоятельно. На iOS 6.1 (сборка сертификатного доверия — 2012 год)
// современные API-хосты (api.anthropic.com, api.openai.com, api.deepseek.com,
// openrouter.ai и т.п.) не проходят системную проверку доверия, challenge
// автоматически отменяется, и NSURLConnection возвращает
// NSURLErrorUserCancelledAuthentication (-1012), хотя с самим запросом
// всё в порядке.
//
// MAHTTPClient использует делегатный NSURLConnection и явно принимает
// server trust, так же как это делают все современные HTTP-клиенты на
// старых прошивках (AFNetworking allowsInvalidSSLCertificate и т.п.).
@interface MAHTTPClient : NSObject

+ (void)sendAsynchronousRequest:(NSURLRequest *)request completion:(MAHTTPCompletion)completion;

@end
