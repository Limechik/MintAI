#import "MAMessage.h"

// Ни один чат-провайдер не должен получать фото прямо с камеры целиком —
// это и лишний трафик на медленном соединении, и почти наверняка выше
// лимита размера запроса у большинства API.
static const CGFloat kMaxImageDimension = 1280.0;
static const CGFloat kJPEGCompressionQuality = 0.7;

@implementation MAMessage

+ (instancetype)messageWithRole:(MAMessageRole)role content:(NSString *)content {
	return [[self alloc] initWithRole:role content:content image:nil];
}

+ (instancetype)messageWithRole:(MAMessageRole)role content:(NSString *)content image:(UIImage *)image {
	return [[self alloc] initWithRole:role content:content image:image];
}

- (instancetype)initWithRole:(MAMessageRole)role content:(NSString *)content {
	return [self initWithRole:role content:content image:nil];
}

- (instancetype)initWithRole:(MAMessageRole)role content:(NSString *)content image:(UIImage *)image {
	self = [super init];
	if (self) {
		_role = role;
		_content = [content copy];
		_image = image;
		_date = [NSDate date];
	}
	return self;
}

- (NSString *)roleString {
	switch (self.role) {
		case MAMessageRoleSystem:
			return @"system";
		case MAMessageRoleUser:
			return @"user";
		case MAMessageRoleAssistant:
			return @"assistant";
	}
	return @"user";
}

- (NSString *)imageBase64JPEG {
	if (!self.image) return nil;
	UIImage *resized = [self ma_imageResizedToFitMaxDimension:kMaxImageDimension];
	NSData *jpegData = UIImageJPEGRepresentation(resized, kJPEGCompressionQuality);
	if (jpegData.length == 0) return nil;
	// NSData не даёт base64 ни одним способом, который гарантированно есть
	// и в SDK 6.1, и в современных (-base64Encoding в части SDK 6.1 уже не
	// объявлен, -base64EncodedStringWithOptions: появился только в iOS 7) —
	// поэтому кодируем сами, без привязки к версии SDK/рантайма.
	return [[self class] ma_base64EncodedStringFromData:jpegData];
}

+ (NSString *)ma_base64EncodedStringFromData:(NSData *)data {
	static const char table[] = "ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789+/";
	NSUInteger length = data.length;
	if (length == 0) return @"";

	const uint8_t *bytes = (const uint8_t *)data.bytes;
	NSMutableData *outputData = [NSMutableData dataWithLength:((length + 2) / 3) * 4];
	char *output = (char *)outputData.mutableBytes;

	NSUInteger i = 0;
	NSUInteger outputIndex = 0;
	while (i + 2 < length) {
		uint32_t chunk = (bytes[i] << 16) | (bytes[i + 1] << 8) | bytes[i + 2];
		output[outputIndex++] = table[(chunk >> 18) & 0x3F];
		output[outputIndex++] = table[(chunk >> 12) & 0x3F];
		output[outputIndex++] = table[(chunk >> 6) & 0x3F];
		output[outputIndex++] = table[chunk & 0x3F];
		i += 3;
	}

	NSUInteger remaining = length - i;
	if (remaining == 1) {
		uint32_t chunk = bytes[i] << 16;
		output[outputIndex++] = table[(chunk >> 18) & 0x3F];
		output[outputIndex++] = table[(chunk >> 12) & 0x3F];
		output[outputIndex++] = '=';
		output[outputIndex++] = '=';
	} else if (remaining == 2) {
		uint32_t chunk = (bytes[i] << 16) | (bytes[i + 1] << 8);
		output[outputIndex++] = table[(chunk >> 18) & 0x3F];
		output[outputIndex++] = table[(chunk >> 12) & 0x3F];
		output[outputIndex++] = table[(chunk >> 6) & 0x3F];
		output[outputIndex++] = '=';
	}

	return [[NSString alloc] initWithData:outputData encoding:NSASCIIStringEncoding];
}

#pragma mark - NSCoding

// Картинка кодируется как PNG-данные — так UIImage переживает
// архивацию/разархивацию без привязки к масштабу экрана.
static NSString *const kCoderRole = @"role";
static NSString *const kCoderContent = @"content";
static NSString *const kCoderImagePNG = @"imagePNG";
static NSString *const kCoderDate = @"date";

- (void)encodeWithCoder:(NSCoder *)coder {
	[coder encodeInteger:self.role forKey:kCoderRole];
	[coder encodeObject:self.content forKey:kCoderContent];
	if (self.image) {
		NSData *pngData = UIImagePNGRepresentation(self.image);
		if (pngData) {
			[coder encodeObject:pngData forKey:kCoderImagePNG];
		}
	}
	[coder encodeObject:self.date forKey:kCoderDate];
}

- (id)initWithCoder:(NSCoder *)coder {
	NSString *content = [coder decodeObjectForKey:kCoderContent];
	MAMessageRole role = (MAMessageRole)[coder decodeIntegerForKey:kCoderRole];
	UIImage *image = nil;
	NSData *pngData = [coder decodeObjectForKey:kCoderImagePNG];
	if (pngData.length > 0) {
		image = [UIImage imageWithData:pngData];
	}
	self = [self initWithRole:role content:content image:image];
	if (self) {
		// У истории, сохранённой до появления этого поля, kCoderDate просто
		// не найдётся — тогда оставляем дату, уже проставленную конструктором
		// (-initWithRole:content:image: ставит [NSDate date]), чем городить
		// nil и городить проверки на nil в UI.
		NSDate *decodedDate = [coder decodeObjectForKey:kCoderDate];
		if (decodedDate) {
			_date = decodedDate;
		}
	}
	return self;
}

- (UIImage *)ma_imageResizedToFitMaxDimension:(CGFloat)maxDimension {
	CGFloat width = self.image.size.width;
	CGFloat height = self.image.size.height;
	if (width <= 0 || height <= 0) return self.image;

	CGFloat scale = MIN((CGFloat)1.0, maxDimension / MAX(width, height));
	if (scale >= 1.0) return self.image;

	CGSize newSize = CGSizeMake(floorf(width * scale), floorf(height * scale));
	UIGraphicsBeginImageContext(newSize);
	[self.image drawInRect:CGRectMake(0, 0, newSize.width, newSize.height)];
	UIImage *resized = UIGraphicsGetImageFromCurrentImageContext();
	UIGraphicsEndImageContext();
	return resized ?: self.image;
}

@end
