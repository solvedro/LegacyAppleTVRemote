#import <Foundation/Foundation.h>

typedef NS_ENUM(NSInteger, ATRHIDCommand) {
    ATRHIDCommandUp = 1,
    ATRHIDCommandDown = 2,
    ATRHIDCommandLeft = 3,
    ATRHIDCommandRight = 4,
    ATRHIDCommandMenu = 5,
    ATRHIDCommandSelect = 6,
    ATRHIDCommandHome = 7,
    ATRHIDCommandVolumeUp = 8,
    ATRHIDCommandVolumeDown = 9,
    ATRHIDCommandSiri = 10,
    ATRHIDCommandScreensaver = 11,
    ATRHIDCommandSleep = 12,
    ATRHIDCommandWake = 13,
    ATRHIDCommandPlayPause = 14
};

@protocol ATRCompanionClientDelegate <NSObject>
@optional
- (void)companionClientDidConnect;
- (void)companionClientDidDisconnect:(NSString *)error;
- (void)companionClientStateChanged:(NSString *)state;
- (void)companionClientReceivedNowPlaying:(NSDictionary *)info;
@end

@interface ATRCompanionClient : NSObject <NSStreamDelegate>

@property (nonatomic, copy) NSString *host;
@property (nonatomic, assign) NSInteger port;
@property (nonatomic, readonly) BOOL isConnected;
@property (nonatomic, readonly) BOOL isEncrypted;
@property (nonatomic, readonly) BOOL isPaired;
@property (nonatomic, weak) id<ATRCompanionClientDelegate> delegate;

+ (ATRCompanionClient *)sharedClient;

- (void)connect;
- (void)disconnect;

- (void)sendHIDCommand:(ATRHIDCommand)command;
- (void)sendHIDCommandNamed:(NSString *)name;
- (void)sendTextInput:(NSString *)text;
- (void)sendTextInput:(NSString *)text completion:(void (^)(BOOL success, NSString *error))completion;

// Media & Playback Controls
- (void)skipForward:(double)seconds;
- (void)skipBackward:(double)seconds;
- (void)nextTrack;
- (void)previousTrack;
- (void)toggleSubtitles;

// Credentials
- (void)setCredentialsString:(NSString *)creds;
- (NSString *)getCredentialsString;
- (void)clearCredentials;

// App Launching & Discovery
- (void)fetchLaunchableApps:(void (^)(NSDictionary *apps, NSString *error))completion;
- (void)launchAppWithBundleID:(NSString *)bundleID;

// Import credentials from bridge HTTP endpoint
- (void)importCredentialsFromBridge:(NSString *)bridgeUrl completion:(void (^)(BOOL success, NSString *msg))completion;

@end
