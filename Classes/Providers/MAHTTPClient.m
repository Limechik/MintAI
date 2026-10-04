#import "MAHTTPClient.h"

// Приватный класс-метод, используется из MAHTTPTask ниже до того, как
// компилятор дойдёт до @implementation MAHTTPClient — без этого forward
// declaration clang не знает про такой селектор у класса и падает с
// "no known class method for selector 'activeTasks'".
@interface MAHTTPClient (Private)
+ (NSMutableSet *)activeTasks;
@end

// Один запрос = один MAHTTPTask. Объект держит сам себя живым через
// [MAHTTPClient activeTasks] на время выполнения запроса (ARC освободит
// его сразу после didFailWithError:/connectionDidFinishLoading:, если
// не задержать этим множеством).
@interface MAHTTPTask : NSObject <NSURLConnectionDataDelegate>
@property (nonatomic, strong) NSURLConnection *connection;
@property (nonatomic, strong) NSMutableData *receivedData;
@property (nonatomic, strong) NSURLResponse *response;
@property (nonatomic, copy) MAHTTPCompletion completion;
- (void)startWithRequest:(NSURLRequest *)request;
@end

@implementation MAHTTPTask

- (void)startWithRequest:(NSURLRequest *)request {
	self.receivedData = [NSMutableData data];
	self.connection = [[NSURLConnection alloc] initWithRequest:request delegate:self startImmediately:YES];
}

#pragma mark - NSURLConnectionDataDelegate

- (void)connection:(NSURLConnection *)connection didReceiveResponse:(NSURLResponse *)response {
	self.response = response;
	[self.receivedData setLength:0];
}

- (void)connection:(NSURLConnection *)connection didReceiveData:(NSData *)data {
	[self.receivedData appendData:data];
}

- (void)connection:(NSURLConnection *)connection didFailWithError:(NSError *)error {
	if (self.completion) self.completion(self.response, self.receivedData, error);
	[[MAHTTPClient activeTasks] removeObject:self];
}

- (void)connectionDidFinishLoading:(NSURLConnection *)connection {
	if (self.completion) self.completion(self.response, self.receivedData, nil);
	[[MAHTTPClient activeTasks] removeObject:self];
}

#pragma mark - Server trust

// Явно заявляем, что сами разберёмся с проверкой доверия к серверу —
// иначе система обработает challenge сама и в случае недоверенной цепочки
// (устаревший стор корневых сертификатов iOS 6.1) отменит его сама же,
// что и даёт NSURLErrorUserCancelledAuthentication (-1012).
- (BOOL)connection:(NSURLConnection *)connection canAuthenticateAgainstProtectionSpace:(NSURLProtectionSpace *)protectionSpace {
	return [protectionSpace.authenticationMethod isEqualToString:NSURLAuthenticationMethodServerTrust];
}

- (void)connection:(NSURLConnection *)connection didReceiveAuthenticationChallenge:(NSURLAuthenticationChallenge *)challenge {
	if ([challenge.protectionSpace.authenticationMethod isEqualToString:NSURLAuthenticationMethodServerTrust]) {
		NSURLCredential *credential = [NSURLCredential credentialForTrust:challenge.protectionSpace.serverTrust];
		[challenge.sender useCredential:credential forAuthenticationChallenge:challenge];
		return;
	}
	[challenge.sender continueWithoutCredentialForAuthenticationChallenge:challenge];
}

@end

@implementation MAHTTPClient

+ (NSMutableSet *)activeTasks {
	static NSMutableSet *tasks = nil;
	static dispatch_once_t onceToken;
	dispatch_once(&onceToken, ^{
		tasks = [NSMutableSet set];
	});
	return tasks;
}

+ (void)sendAsynchronousRequest:(NSURLRequest *)request completion:(MAHTTPCompletion)completion {
	MAHTTPTask *task = [[MAHTTPTask alloc] init];
	task.completion = completion;
	[[self activeTasks] addObject:task];
	[task startWithRequest:request];
}

@end
