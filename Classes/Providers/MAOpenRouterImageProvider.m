#import "MAOpenRouterImageProvider.h"

// Отношения сторон, которые принимает большинство моделей OpenRouter (у каждой
// модели свой поднабор — недостающее OpenRouter подбирает ближайшим сам).
static NSString *const kAspectRatioNames[] = { @"1:1", @"3:2", @"2:3", @"4:3", @"3:4", @"16:9", @"9:16", @"21:9" };
static const CGFloat kAspectRatioValues[] = { 1.0f, 3.0f / 2, 2.0f / 3, 4.0f / 3, 3.0f / 4, 16.0f / 9, 9.0f / 16, 21.0f / 9 };
static const NSInteger kAspectRatioCount = 8;

@implementation MAOpenRouterImageProvider

- (instancetype)init {
	// google/gemini-2.5-flash-image — дешёвая модель с общим доступом и хорошим
	// пониманием русских промптов; любую другую можно вписать в Settings.
	self = [super initWithIdentifier:@"openrouter-image"
	                      displayName:@"OpenRouter"
	                    baseURLString:@"https://openrouter.ai/api/v1"
	                            model:@"google/gemini-2.5-flash-image"];
	if (self) {
		// Как и у чат-провайдера: идентификация приложения (не обязательна, но рекомендована).
		self.extraHeaders = @{
			@"HTTP-Referer": @"https://mintai.app",
			@"X-Title": @"MintAI"
		};
	}
	return self;
}

#pragma mark - Запрос

- (NSString *)imagesURLString {
	NSString *base = self.baseURLString ?: @"";
	while ([base hasSuffix:@"/"]) {
		base = [base substringToIndex:base.length - 1];
	}
	if ([base hasSuffix:@"/images"]) {
		return base;
	}
	return [base stringByAppendingString:@"/images"];
}

- (NSDictionary *)requestBodyWithPrompt:(NSString *)prompt size:(NSString *)size {
	NSMutableDictionary *body = [NSMutableDictionary dictionary];
	body[@"model"] = self.model ?: @"";
	body[@"prompt"] = prompt ?: @"";

	// Только model и prompt, остальное — по необходимости: не все модели принимают
	// aspect_ratio (у части он вообще не поддерживается), а квадрат и так по умолчанию.
	NSString *aspectRatio = [self aspectRatioForSize:size];
	if (aspectRatio) {
		body[@"aspect_ratio"] = aspectRatio;
	}
	return body;
}

// «1024x1024» → nil (квадрат — значение по умолчанию, параметр не нужен);
// «1792x1024» → ближайшее из известных отношений («16:9»).
- (NSString *)aspectRatioForSize:(NSString *)size {
	NSArray *parts = [[size lowercaseString] componentsSeparatedByString:@"x"];
	if (parts.count != 2) return nil;

	CGFloat width = [parts[0] floatValue];
	CGFloat height = [parts[1] floatValue];
	if (width <= 0 || height <= 0) return nil;

	CGFloat ratio = width / height;
	NSInteger best = 0;
	CGFloat bestDistance = CGFLOAT_MAX;
	for (NSInteger i = 0; i < kAspectRatioCount; i++) {
		CGFloat distance = fabsf(logf(ratio / kAspectRatioValues[i]));
		if (distance < bestDistance) {
			bestDistance = distance;
			best = i;
		}
	}
	return (best == 0) ? nil : kAspectRatioNames[best];
}

- (NSTimeInterval)requestTimeoutInterval {
	// Тяжёлые модели (GPT Image и т.п. в высоком качестве) рисуют больше минуты.
	return 180.0;
}

@end
