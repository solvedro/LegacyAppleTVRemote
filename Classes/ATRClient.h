#import <Foundation/Foundation.h>

extern NSString *const kATRStatusChangedNotification;
extern NSString *const kATRNowPlayingChangedNotification;

@interface ATRClient : NSObject

@property (nonatomic, copy) NSString *serverHost;
@property (nonatomic, copy, readonly) NSString *deviceName;
@property (nonatomic, assign, readonly) BOOL isConnected;
@property (nonatomic, assign, readonly) BOOL isPaired;
@property (nonatomic, copy, readonly) NSString *nowPlayingTitle;
@property (nonatomic, copy, readonly) NSString *nowPlayingArtist;
@property (nonatomic, copy, readonly) NSString *nowPlayingState;

+ (instancetype)sharedClient;

- (void)saveServerHost:(NSString *)host;
- (void)pressKey:(NSString *)key completion:(void (^)(BOOL success, NSString *error))completion;
- (void)sendTextInput:(NSString *)text completion:(void (^)(BOOL success, NSString *error))completion;
- (void)fetchStatusWithCompletion:(void (^)(BOOL connected, BOOL paired, NSString *device, NSString *error))completion;
- (void)fetchNowPlayingWithCompletion:(void (^)(NSDictionary *info, NSString *error))completion;
- (void)startPairingWithCompletion:(void (^)(BOOL success, NSString *msg))completion;
- (void)submitPIN:(NSString *)pin completion:(void (^)(BOOL success, NSString *msg))completion;

@end
