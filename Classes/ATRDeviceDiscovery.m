#import "ATRDeviceDiscovery.h"
#import <arpa/inet.h>
#import <netinet/in.h>

@implementation ATRDiscoveredDevice
@end

@interface ATRDeviceDiscovery () {
    NSNetServiceBrowser *_companionBrowser;
    NSNetServiceBrowser *_airplayBrowser;
    NSMutableArray *_servicesResolving;
    NSMutableArray *_devices;
}
@property (nonatomic, assign) BOOL isSearching;
@end

@implementation ATRDeviceDiscovery

+ (instancetype)sharedDiscovery {
    static ATRDeviceDiscovery *sShared = nil;
    static dispatch_once_t onceToken;
    dispatch_once(&onceToken, ^{
        sShared = [[ATRDeviceDiscovery alloc] init];
    });
    return sShared;
}

- (id)init {
    self = [super init];
    if (self) {
        _devices = [NSMutableArray array];
        _servicesResolving = [NSMutableArray array];
    }
    return self;
}

- (NSArray *)discoveredDevices {
    return [_devices copy];
}

- (void)startDiscovery {
    if (self.isSearching) return;
    self.isSearching = YES;
    [_devices removeAllObjects];
    [_servicesResolving removeAllObjects];
    
    _companionBrowser = [[NSNetServiceBrowser alloc] init];
    _companionBrowser.delegate = self;
    [_companionBrowser searchForServicesOfType:@"_companion-link._tcp." inDomain:@"local."];
    
    _airplayBrowser = [[NSNetServiceBrowser alloc] init];
    _airplayBrowser.delegate = self;
    [_airplayBrowser searchForServicesOfType:@"_airplay._tcp." inDomain:@"local."];
    
    NSLog(@"[ATRDeviceDiscovery] Started Bonjour discovery for Apple TV services...");
}

- (void)stopDiscovery {
    if (!self.isSearching) return;
    self.isSearching = NO;
    
    [_companionBrowser stop];
    _companionBrowser = nil;
    [_airplayBrowser stop];
    _airplayBrowser = nil;
    
    for (NSNetService *svc in _servicesResolving) {
        [svc stop];
    }
    [_servicesResolving removeAllObjects];
    NSLog(@"[ATRDeviceDiscovery] Stopped Bonjour discovery.");
}

#pragma mark - NSNetServiceBrowserDelegate

- (void)netServiceBrowser:(NSNetServiceBrowser *)browser didFindService:(NSNetService *)service moreComing:(BOOL)moreComing {
    NSLog(@"[ATRDeviceDiscovery] Found Bonjour service: %@ (type: %@)", service.name, service.type);
    service.delegate = self;
    [_servicesResolving addObject:service];
    [service resolveWithTimeout:5.0];
}

- (void)netServiceBrowser:(NSNetServiceBrowser *)browser didRemoveService:(NSNetService *)service moreComing:(BOOL)moreComing {
    ATRDiscoveredDevice *toRemove = nil;
    for (ATRDiscoveredDevice *d in _devices) {
        if ([d.name isEqualToString:service.name]) {
            toRemove = d;
            break;
        }
    }
    if (toRemove) {
        [_devices removeObject:toRemove];
        if ([self.delegate respondsToSelector:@selector(deviceDiscoveryDidUpdateDevices:)]) {
            [self.delegate deviceDiscoveryDidUpdateDevices:self];
        }
    }
}

#pragma mark - NSNetServiceDelegate

- (void)netServiceDidResolveAddress:(NSNetService *)sender {
    // 1. Filter out known non-Apple TV devices by name
    NSString *lowerName = [sender.name lowercaseString];
    if ([lowerName rangeOfString:@"soundbar"].location != NSNotFound ||
        [lowerName rangeOfString:@"samsung"].location != NSNotFound ||
        [lowerName rangeOfString:@"sonos"].location != NSNotFound ||
        [lowerName rangeOfString:@"bose"].location != NSNotFound ||
        [lowerName rangeOfString:@"roku"].location != NSNotFound) {
        NSLog(@"[ATRDeviceDiscovery] Ignoring non-Apple TV device by name: %@", sender.name);
        [_servicesResolving removeObject:sender];
        return;
    }
    
    // 2. Check TXT record for model verification
    BOOL isCompanionService = ([sender.type rangeOfString:@"_companion-link"].location != NSNotFound);
    if (!isCompanionService) {
        // If it's an AirPlay service, verify that the model contains 'AppleTV'
        NSData *txtData = [sender TXTRecordData];
        if (txtData) {
            NSDictionary *txtDict = [NSNetService dictionaryFromTXTRecordData:txtData];
            NSData *modelData = [txtDict objectForKey:@"model"];
            if (modelData) {
                NSString *modelStr = [[NSString alloc] initWithData:modelData encoding:NSUTF8StringEncoding];
                if ([modelStr rangeOfString:@"AppleTV" options:NSCaseInsensitiveSearch].location == NSNotFound) {
                    NSLog(@"[ATRDeviceDiscovery] Ignoring non-Apple TV model: %@ (%@)", sender.name, modelStr);
                    [_servicesResolving removeObject:sender];
                    return;
                }
            }
        }
    }
    
    NSString *ipAddress = nil;
    NSInteger port = sender.port;
    if (port <= 0 || port == 7000) {
        // Fallback default companion port
        port = 50590;
    }
    
    for (NSData *addressData in [sender addresses]) {
        struct sockaddr_in *socketAddress = (struct sockaddr_in *)[addressData bytes];
        if (socketAddress->sin_family == AF_INET) {
            char buffer[INET_ADDRSTRLEN];
            const char *ipStr = inet_ntop(AF_INET, &(socketAddress->sin_addr), buffer, sizeof(buffer));
            if (ipStr) {
                ipAddress = [NSString stringWithUTF8String:ipStr];
                break;
            }
        }
    }
    
    if (ipAddress && [ipAddress length] > 0) {
        NSLog(@"[ATRDeviceDiscovery] Resolved %@ -> %@:%ld (companion=%d)", sender.name, ipAddress, (long)port, isCompanionService);
        
        // Deduplicate
        BOOL exists = NO;
        for (ATRDiscoveredDevice *d in _devices) {
            if ([d.host isEqualToString:ipAddress] || [d.name isEqualToString:sender.name]) {
                exists = YES;
                d.host = ipAddress;
                if (isCompanionService && sender.port > 0) {
                    d.port = sender.port;
                }
                break;
            }
        }
        
        if (!exists) {
            ATRDiscoveredDevice *dev = [[ATRDiscoveredDevice alloc] init];
            dev.name = sender.name;
            dev.host = ipAddress;
            dev.port = port;
            [_devices addObject:dev];
            
            if ([self.delegate respondsToSelector:@selector(deviceDiscovery:didFindDeviceNamed:host:port:)]) {
                [self.delegate deviceDiscovery:self didFindDeviceNamed:dev.name host:dev.host port:dev.port];
            }
            if ([self.delegate respondsToSelector:@selector(deviceDiscoveryDidUpdateDevices:)]) {
                [self.delegate deviceDiscoveryDidUpdateDevices:self];
            }
        }
    }
    
    [_servicesResolving removeObject:sender];
}

- (void)netService:(NSNetService *)sender didNotResolve:(NSDictionary *)errorDict {
    NSLog(@"[ATRDeviceDiscovery] Failed to resolve %@: %@", sender.name, errorDict);
    [_servicesResolving removeObject:sender];
}

@end
