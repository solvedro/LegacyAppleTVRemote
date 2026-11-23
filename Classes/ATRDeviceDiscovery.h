#import <Foundation/Foundation.h>

@class ATRDeviceDiscovery;

@protocol ATRDeviceDiscoveryDelegate <NSObject>
@optional
- (void)deviceDiscovery:(ATRDeviceDiscovery *)discovery didFindDeviceNamed:(NSString *)name host:(NSString *)host port:(NSInteger)port;
- (void)deviceDiscoveryDidUpdateDevices:(ATRDeviceDiscovery *)discovery;
@end

@interface ATRDiscoveredDevice : NSObject
@property (nonatomic, copy) NSString *name;
@property (nonatomic, copy) NSString *host;
@property (nonatomic, assign) NSInteger port;
@end

@interface ATRDeviceDiscovery : NSObject <NSNetServiceBrowserDelegate, NSNetServiceDelegate>

@property (nonatomic, weak) id<ATRDeviceDiscoveryDelegate> delegate;
@property (nonatomic, strong, readonly) NSArray *discoveredDevices;
@property (nonatomic, readonly) BOOL isSearching;

+ (instancetype)sharedDiscovery;

- (void)startDiscovery;
- (void)stopDiscovery;

@end
