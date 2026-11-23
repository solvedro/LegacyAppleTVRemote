#import "ATRClient.h"
#import "Companion/ATRCompanionClient.h"

NSString *const kATRStatusChangedNotification = @"kATRStatusChangedNotification";
NSString *const kATRNowPlayingChangedNotification = @"kATRNowPlayingChangedNotification";
static NSString *const kPrefServerHost = @"ATR_ServerHost";

@interface ATRClient ()

@property (nonatomic, copy, readwrite) NSString *deviceName;
@property (nonatomic, assign, readwrite) BOOL isConnected;
@property (nonatomic, assign, readwrite) BOOL isPaired;
@property (nonatomic, copy, readwrite) NSString *nowPlayingTitle;
@property (nonatomic, copy, readwrite) NSString *nowPlayingArtist;
@property (nonatomic, copy, readwrite) NSString *nowPlayingState;
@property (nonatomic, strong) NSOperationQueue *networkQueue;

@end

@implementation ATRClient

+ (instancetype)sharedClient {
    static ATRClient *instance = nil;
    static dispatch_once_t onceToken;
    dispatch_once(&onceToken, ^{
        instance = [[ATRClient alloc] init];
    });
    return instance;
}

- (id)init {
    self = [super init];
    if (self) {
        NSUserDefaults *defs = [NSUserDefaults standardUserDefaults];
        NSString *saved = [defs stringForKey:kPrefServerHost];
        if (saved.length > 0) {
            _serverHost = saved;
        } else {
            _serverHost = @"192.168.100.94:8088";
        }
        _deviceName = @"Apple TV 4K";
        _isConnected = NO;
        _isPaired = NO;
        _nowPlayingState = @"idle";
        _networkQueue = [[NSOperationQueue alloc] init];
        _networkQueue.maxConcurrentOperationCount = 4;
    }
    return self;
}

- (void)saveServerHost:(NSString *)host {
    if (host.length == 0) return;
    self.serverHost = host;
    [[NSUserDefaults standardUserDefaults] setObject:host forKey:kPrefServerHost];
    [[NSUserDefaults standardUserDefaults] synchronize];
}

- (NSURL *)baseURL {
    NSString *h = self.serverHost;
    if (![h hasPrefix:@"http://"] && ![h hasPrefix:@"https://"]) {
        h = [NSString stringWithFormat:@"http://%@", h];
    }
    return [NSURL URLWithString:h];
}

- (void)sendTextInput:(NSString *)text completion:(void (^)(BOOL success, NSString *error))completion {
    if (!text || text.length == 0) return;
    
    NSString *escaped = [text stringByAddingPercentEscapesUsingEncoding:NSUTF8StringEncoding];
    NSString *urlStr = [NSString stringWithFormat:@"%@/text?text=%@", [self baseURL].absoluteString, escaped];
    NSURL *url = [NSURL URLWithString:urlStr];
    if (!url) {
        if (completion) completion(NO, @"Invalid URL");
        return;
    }
    
    NSMutableURLRequest *req = [NSMutableURLRequest requestWithURL:url
                                                       cachePolicy:NSURLRequestReloadIgnoringLocalCacheData
                                                   timeoutInterval:5.0];
    
    [NSURLConnection sendAsynchronousRequest:req
                                       queue:[NSOperationQueue mainQueue]
                           completionHandler:^(NSURLResponse *resp, NSData *data, NSError *err) {
        if (err || !data) {
            if (completion) completion(NO, [err localizedDescription] ?: @"No data received");
            return;
        }
        
        NSDictionary *dict = [NSJSONSerialization JSONObjectWithData:data options:0 error:nil];
        if (dict && [[dict objectForKey:@"success"] boolValue]) {
            if (completion) completion(YES, nil);
        } else {
            NSString *msg = [dict objectForKey:@"error"] ?: @"Failed to send text";
            if (completion) completion(NO, msg);
        }
    }];
}

- (void)pressKey:(NSString *)key completion:(void (^)(BOOL success, NSString *error))completion {
    if (!key || key.length == 0) return;
    
    NSString *urlStr = [NSString stringWithFormat:@"%@/press?key=%@", [self baseURL].absoluteString, key];
    NSURL *url = [NSURL URLWithString:urlStr];
    if (!url) {
        if (completion) completion(NO, @"Invalid URL");
        return;
    }
    
    NSMutableURLRequest *req = [NSMutableURLRequest requestWithURL:url
                                                       cachePolicy:NSURLRequestReloadIgnoringLocalCacheData
                                                   timeoutInterval:3.0];
    
    [NSURLConnection sendAsynchronousRequest:req
                                       queue:self.networkQueue
                           completionHandler:^(NSURLResponse *res, NSData *data, NSError *err) {
        dispatch_async(dispatch_get_main_queue(), ^{
            if (err) {
                if (completion) completion(NO, err.localizedDescription);
                return;
            }
            
            NSHTTPURLResponse *http = (NSHTTPURLResponse *)res;
            if (http.statusCode >= 200 && http.statusCode < 300) {
                if (completion) completion(YES, nil);
            } else {
                NSString *respText = [[NSString alloc] initWithData:data encoding:NSUTF8StringEncoding];
                if (completion) completion(NO, respText ?: @"HTTP Error");
            }
        });
    }];
}

- (void)fetchStatusWithCompletion:(void (^)(BOOL connected, BOOL paired, NSString *device, NSString *error))completion {
    NSString *urlStr = [NSString stringWithFormat:@"%@/status", [self baseURL].absoluteString];
    NSURL *url = [NSURL URLWithString:urlStr];
    if (!url) {
        if (completion) completion(NO, NO, nil, @"Invalid URL");
        return;
    }
    
    NSMutableURLRequest *req = [NSMutableURLRequest requestWithURL:url
                                                       cachePolicy:NSURLRequestReloadIgnoringLocalCacheData
                                                   timeoutInterval:3.0];
    
    [NSURLConnection sendAsynchronousRequest:req
                                       queue:self.networkQueue
                           completionHandler:^(NSURLResponse *res, NSData *data, NSError *err) {
        dispatch_async(dispatch_get_main_queue(), ^{
            if (err || !data) {
                self.isConnected = NO;
                [[NSNotificationCenter defaultCenter] postNotificationName:kATRStatusChangedNotification object:nil];
                if (completion) completion(NO, NO, nil, err ? err.localizedDescription : @"No Data");
                return;
            }
            
            NSError *jsonErr = nil;
            NSDictionary *dict = [NSJSONSerialization JSONObjectWithData:data options:0 error:&jsonErr];
            if ([dict isKindOfClass:[NSDictionary class]]) {
                self.isConnected = [[dict objectForKey:@"connected"] boolValue];
                self.isPaired = [[dict objectForKey:@"paired"] boolValue];
                NSString *dev = [dict objectForKey:@"device"];
                if (dev.length > 0) {
                    self.deviceName = dev;
                }
                
                [[NSNotificationCenter defaultCenter] postNotificationName:kATRStatusChangedNotification object:nil];
                if (completion) completion(self.isConnected, self.isPaired, self.deviceName, nil);
            } else {
                if (completion) completion(NO, NO, nil, @"Malformed JSON");
            }
        });
    }];
}

- (void)fetchNowPlayingWithCompletion:(void (^)(NSDictionary *info, NSString *error))completion {
    NSString *urlStr = [NSString stringWithFormat:@"%@/nowplaying", [self baseURL].absoluteString];
    NSURL *url = [NSURL URLWithString:urlStr];
    if (!url) {
        if (completion) completion(nil, @"Invalid URL");
        return;
    }
    
    NSMutableURLRequest *req = [NSMutableURLRequest requestWithURL:url
                                                       cachePolicy:NSURLRequestReloadIgnoringLocalCacheData
                                                   timeoutInterval:3.0];
    
    [NSURLConnection sendAsynchronousRequest:req
                                       queue:self.networkQueue
                           completionHandler:^(NSURLResponse *res, NSData *data, NSError *err) {
        dispatch_async(dispatch_get_main_queue(), ^{
            if (err || !data) {
                if (completion) completion(nil, err ? err.localizedDescription : @"No Data");
                return;
            }
            
            NSDictionary *dict = [NSJSONSerialization JSONObjectWithData:data options:0 error:nil];
            if ([dict isKindOfClass:[NSDictionary class]]) {
                self.nowPlayingTitle = [dict objectForKey:@"title"] ?: @"";
                self.nowPlayingArtist = [dict objectForKey:@"artist"] ?: @"";
                self.nowPlayingState = [dict objectForKey:@"state"] ?: @"idle";
                
                [[NSNotificationCenter defaultCenter] postNotificationName:kATRNowPlayingChangedNotification object:dict];
                if (completion) completion(dict, nil);
            } else {
                if (completion) completion(nil, @"Invalid response");
            }
        });
    }];
}

- (void)startPairingWithCompletion:(void (^)(BOOL success, NSString *msg))completion {
    NSString *urlStr = [NSString stringWithFormat:@"%@/pair/start", [self baseURL].absoluteString];
    NSURL *url = [NSURL URLWithString:urlStr];
    if (!url) {
        if (completion) completion(NO, @"Invalid URL");
        return;
    }
    
    NSMutableURLRequest *req = [NSMutableURLRequest requestWithURL:url
                                                       cachePolicy:NSURLRequestReloadIgnoringLocalCacheData
                                                   timeoutInterval:8.0];
    
    [NSURLConnection sendAsynchronousRequest:req
                                       queue:self.networkQueue
                           completionHandler:^(NSURLResponse *res, NSData *data, NSError *err) {
        dispatch_async(dispatch_get_main_queue(), ^{
            if (err) {
                if (completion) completion(NO, err.localizedDescription);
                return;
            }
            
            NSDictionary *dict = [NSJSONSerialization JSONObjectWithData:data options:0 error:nil];
            if ([dict isKindOfClass:[NSDictionary class]] && [[dict objectForKey:@"success"] boolValue]) {
                if (completion) completion(YES, [dict objectForKey:@"message"] ?: @"PIN displayed on TV");
            } else {
                NSString *errMsg = [dict objectForKey:@"error"] ?: @"Pairing could not start";
                if (completion) completion(NO, errMsg);
            }
        });
    }];
}

- (void)submitPIN:(NSString *)pin completion:(void (^)(BOOL success, NSString *msg))completion {
    NSString *cleanPin = [pin stringByTrimmingCharactersInSet:[NSCharacterSet whitespaceAndNewlineCharacterSet]];
    NSString *urlStr = [NSString stringWithFormat:@"%@/pair/submit?pin=%@", [self baseURL].absoluteString, cleanPin];
    NSURL *url = [NSURL URLWithString:urlStr];
    if (!url) {
        if (completion) completion(NO, @"Invalid URL");
        return;
    }
    
    NSMutableURLRequest *req = [NSMutableURLRequest requestWithURL:url
                                                       cachePolicy:NSURLRequestReloadIgnoringLocalCacheData
                                                   timeoutInterval:10.0];
    
    [NSURLConnection sendAsynchronousRequest:req
                                       queue:self.networkQueue
                           completionHandler:^(NSURLResponse *res, NSData *data, NSError *err) {
        dispatch_async(dispatch_get_main_queue(), ^{
            if (err) {
                if (completion) completion(NO, err.localizedDescription);
                return;
            }
            
            NSDictionary *dict = [NSJSONSerialization JSONObjectWithData:data options:0 error:nil];
            if ([dict isKindOfClass:[NSDictionary class]] && [[dict objectForKey:@"success"] boolValue]) {
                self.isPaired = YES;
                self.isConnected = YES;
                
                NSString *creds = [dict objectForKey:@"credentials"];
                if (creds && [creds length] > 0) {
                    [[ATRCompanionClient sharedClient] setCredentialsString:creds];
                }
                
                [[NSNotificationCenter defaultCenter] postNotificationName:kATRStatusChangedNotification object:nil];
                if (completion) completion(YES, [dict objectForKey:@"message"] ?: @"Paired successfully!");
            } else {
                NSString *errMsg = [dict objectForKey:@"error"] ?: @"Incorrect PIN or pairing failed";
                if (completion) completion(NO, errMsg);
            }
        });
    }];
}

@end
