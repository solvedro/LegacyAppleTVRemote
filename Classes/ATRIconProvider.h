#import <UIKit/UIKit.h>

@interface ATRIconProvider : NSObject

+ (UIImage *)iconForBundleID:(NSString *)bundleID name:(NSString *)name size:(CGSize)size;
+ (UIImage *)defaultThumbnailForMediaTitle:(NSString *)title artist:(NSString *)artist;
+ (void)fetchArtworkForTitle:(NSString *)title artist:(NSString *)artist completion:(void (^)(UIImage *artwork))completion;

@end
