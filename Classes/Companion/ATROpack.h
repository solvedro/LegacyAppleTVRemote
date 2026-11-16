#import <Foundation/Foundation.h>

@interface ATROpack : NSObject

+ (NSData *)pack:(id)obj;
+ (id)unpack:(NSData *)data;
+ (id)unpackBytes:(const uint8_t *)bytes length:(NSUInteger)length consumed:(NSUInteger *)consumed;

@end
