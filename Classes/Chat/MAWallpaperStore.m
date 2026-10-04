#import "MAWallpaperStore.h"

NSString *const MAWallpaperDidChangeNotification = @"MAWallpaperDidChangeNotification";

static NSString *const kWallpaperFileName = @"chat_wallpaper.png";

@interface MAWallpaperStore ()
@property (nonatomic, strong) UIImage *cachedImage;
@property (nonatomic, assign) BOOL cacheLoaded;
@end

@implementation MAWallpaperStore

+ (instancetype)sharedStore {
	static MAWallpaperStore *store = nil;
	static dispatch_once_t onceToken;
	dispatch_once(&onceToken, ^{
		store = [[MAWallpaperStore alloc] init];
	});
	return store;
}

- (NSString *)wallpaperFilePath {
	NSArray *paths = NSSearchPathForDirectoriesInDomains(NSDocumentDirectory, NSUserDomainMask, YES);
	NSString *documentsPath = (paths.count > 0) ? paths[0] : NSTemporaryDirectory();
	return [documentsPath stringByAppendingPathComponent:kWallpaperFileName];
}

- (UIImage *)wallpaperImage {
	if (!self.cacheLoaded) {
		NSString *path = [self wallpaperFilePath];
		if ([[NSFileManager defaultManager] fileExistsAtPath:path]) {
			// scale:1.0 — обои растягиваются под размер экрана средствами
			// UIImageView (contentMode), поэтому масштаб исходника не важен.
			self.cachedImage = [UIImage imageWithContentsOfFile:path];
		}
		self.cacheLoaded = YES;
	}
	return self.cachedImage;
}

- (void)setWallpaperImage:(UIImage *)image {
	self.cachedImage = image;
	self.cacheLoaded = YES;

	NSData *pngData = UIImagePNGRepresentation(image);
	[pngData writeToFile:[self wallpaperFilePath] atomically:YES];

	[[NSNotificationCenter defaultCenter] postNotificationName:MAWallpaperDidChangeNotification object:nil];
}

- (void)clearWallpaper {
	self.cachedImage = nil;
	self.cacheLoaded = YES;

	[[NSFileManager defaultManager] removeItemAtPath:[self wallpaperFilePath] error:nil];

	[[NSNotificationCenter defaultCenter] postNotificationName:MAWallpaperDidChangeNotification object:nil];
}

@end
