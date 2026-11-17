#import "ATRRemoteViewController.h"
#import "ATRSettingsViewController.h"
#import "ATRAppsViewController.h"
#import "ATRClient.h"
#import "Companion/ATRCompanionClient.h"
#import "ATRIconProvider.h"
#import "ATRTrackpadView.h"
#import <AudioToolbox/AudioToolbox.h>
#import <QuartzCore/QuartzCore.h>

@interface ATRRemoteViewController () <ATRSettingsDelegate, ATRCompanionClientDelegate, ATRAppsViewControllerDelegate, ATRTrackpadViewDelegate, UIActionSheetDelegate>

@property (nonatomic, strong) UIView *headerView;
@property (nonatomic, strong) UIView *ledDot;
@property (nonatomic, strong) UILabel *titleLabel;
@property (nonatomic, strong) UIButton *appsButton;
@property (nonatomic, strong) UIButton *gearButton;
@property (nonatomic, strong) UIButton *powerButton;

// Trackpad
@property (nonatomic, strong) ATRTrackpadView *trackpadView;

// Now Playing
@property (nonatomic, strong) UIView *marqueeContainer;
@property (nonatomic, strong) UIImageView *nowPlayingThumbView;
@property (nonatomic, strong) UILabel *marqueeLabel;
@property (nonatomic, strong) NSString *currentNowPlayingTitle;
@property (nonatomic, strong) NSString *currentNowPlayingArtist;
@property (nonatomic, strong) NSString *currentActiveAppName;
@property (nonatomic, strong) NSString *currentActiveBundleID;
@property (nonatomic, assign) BOOL isPlaying;
@property (nonatomic, strong) UIImage *currentArtworkImage;
@property (nonatomic, strong) UIView *nowPlayingOverlay;

// Buttons
@property (nonatomic, strong) UIButton *menuButton;
@property (nonatomic, strong) UIButton *homeButton;
@property (nonatomic, strong) UIButton *playPauseButton;
@property (nonatomic, strong) UIButton *muteButton;
@property (nonatomic, strong) UIButton *volDownButton;
@property (nonatomic, strong) UIButton *volUpButton;

@property (nonatomic, strong) NSTimer *pollTimer;

@end

@implementation ATRRemoteViewController

- (void)viewDidLoad {
    [super viewDidLoad];
    
    // Remote chassis metallic background
    self.view.backgroundColor = [UIColor colorWithRed:0.09 green:0.10 blue:0.12 alpha:1.0];
    
    CAGradientLayer *grad = [CAGradientLayer layer];
    grad.frame = CGRectMake(0, 0, 320, 480);
    grad.colors = @[
        (id)[UIColor colorWithRed:0.16 green:0.17 blue:0.20 alpha:1.0].CGColor,
        (id)[UIColor colorWithRed:0.08 green:0.09 blue:0.11 alpha:1.0].CGColor,
        (id)[UIColor colorWithRed:0.05 green:0.06 blue:0.07 alpha:1.0].CGColor
    ];
    grad.locations = @[@0.0, @0.45, @1.0];
    [self.view.layer insertSublayer:grad atIndex:0];
    
    [self setupHeader];
    [self setupTrackpad];
    [self setupNowPlayingMarquee];
    [self setupButtons];
    
    [[NSNotificationCenter defaultCenter] addObserver:self
                                             selector:@selector(updateStatusUI)
                                                 name:kATRStatusChangedNotification
                                               object:nil];
                                               
    [[NSNotificationCenter defaultCenter] addObserver:self
                                             selector:@selector(updateNowPlayingUI:)
                                                 name:kATRNowPlayingChangedNotification
                                               object:nil];
                                               
    [[NSNotificationCenter defaultCenter] addObserver:self
                                             selector:@selector(activeAppNotificationReceived:)
                                                 name:@"ATRActiveAppChangedNotification"
                                               object:nil];
                                               
    [ATRCompanionClient sharedClient].delegate = self;
    
    // Restore persistent active app if available
    NSString *lastAppName = [[NSUserDefaults standardUserDefaults] stringForKey:@"ATRLastActiveAppName"];
    NSString *lastBundleID = [[NSUserDefaults standardUserDefaults] stringForKey:@"ATRLastActiveBundleID"];
    if (lastAppName && [lastAppName length] > 0) {
        [self applyActiveAppNamed:lastAppName bundleID:lastBundleID isPlaying:YES];
    }
}

- (void)viewWillAppear:(BOOL)animated {
    [super viewWillAppear:animated];
    NSString *mode = [[NSUserDefaults standardUserDefaults] stringForKey:@"ATRConnectionMode"];
    if ([mode isEqualToString:@"Bridge"]) {
        [self startPolling];
        [self refreshConnection];
    } else {
        [self stopPolling];
        [self updateStatusUI];
        if ([[ATRCompanionClient sharedClient] isPaired]) {
            [[ATRCompanionClient sharedClient] connect];
        }
    }
}

- (void)viewDidAppear:(BOOL)animated {
    [super viewDidAppear:animated];
    dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(1.5 * NSEC_PER_SEC)), dispatch_get_main_queue(), ^{
        UIWindow *w = [[UIApplication sharedApplication] keyWindow];
        if (w) {
            UIGraphicsBeginImageContextWithOptions(w.bounds.size, YES, 0.0);
            [w.layer renderInContext:UIGraphicsGetCurrentContext()];
            UIImage *img = UIGraphicsGetImageFromCurrentImageContext();
            UIGraphicsEndImageContext();
            if (img) {
                UIImageWriteToSavedPhotosAlbum(img, nil, nil, nil);
                NSString *docs = [NSSearchPathForDirectoriesInDomains(NSDocumentDirectory, NSUserDomainMask, YES) objectAtIndex:0];
                NSString *path = [docs stringByAppendingPathComponent:@"remote_screen.png"];
                [UIImagePNGRepresentation(img) writeToFile:path atomically:YES];
                NSLog(@"[Screenshot] Saved remote screenshot to %@", path);
            }
        }
    });
}

- (void)viewWillDisappear:(BOOL)animated {
    [super viewWillDisappear:animated];
    [self stopPolling];
}

- (void)appDidBecomeActive {
    NSString *mode = [[NSUserDefaults standardUserDefaults] stringForKey:@"ATRConnectionMode"];
    if ([mode isEqualToString:@"Bridge"]) {
        [self refreshConnection];
    } else {
        [self updateStatusUI];
        if ([[ATRCompanionClient sharedClient] isPaired]) {
            [[ATRCompanionClient sharedClient] connect];
        }
    }
}

- (void)dealloc {
    [[NSNotificationCenter defaultCenter] removeObserver:self];
    [self stopPolling];
}

#pragma mark - UI Setup

- (void)setupHeader {
    self.headerView = [[UIView alloc] initWithFrame:CGRectMake(0, 10, 320, 40)];
    self.headerView.backgroundColor = [UIColor clearColor];
    [self.view addSubview:self.headerView];
    
    // Status LED dot
    self.ledDot = [[UIView alloc] initWithFrame:CGRectMake(10, 15, 10, 10)];
    self.ledDot.layer.cornerRadius = 5.0;
    self.ledDot.layer.masksToBounds = YES;
    self.ledDot.backgroundColor = [UIColor colorWithRed:0.9 green:0.2 blue:0.2 alpha:1.0]; // Red initially
    self.ledDot.layer.borderColor = [UIColor colorWithWhite:0.3 alpha:0.8].CGColor;
    self.ledDot.layer.borderWidth = 1.0;
    [self.headerView addSubview:self.ledDot];
    
    // Device title
    self.titleLabel = [[UILabel alloc] initWithFrame:CGRectMake(24, 7, 108, 26)];
    self.titleLabel.text = @"Apple TV 4K";
    self.titleLabel.textColor = [UIColor whiteColor];
    self.titleLabel.font = [UIFont boldSystemFontOfSize:15];
    self.titleLabel.backgroundColor = [UIColor clearColor];
    self.titleLabel.shadowColor = [UIColor blackColor];
    self.titleLabel.shadowOffset = CGSizeMake(0, 1);
    [self.headerView addSubview:self.titleLabel];
    
    // Apps Button
    self.appsButton = [UIButton buttonWithType:UIButtonTypeCustom];
    self.appsButton.frame = CGRectMake(134, 5, 66, 30);
    [self.appsButton setTitle:@"📱 APPS" forState:UIControlStateNormal];
    [self.appsButton setTitleColor:[UIColor colorWithWhite:0.92 alpha:1.0] forState:UIControlStateNormal];
    [self.appsButton setTitleColor:[UIColor colorWithRed:0.35 green:0.80 blue:1.0 alpha:1.0] forState:UIControlStateHighlighted];
    self.appsButton.titleLabel.font = [UIFont boldSystemFontOfSize:12];
    self.appsButton.backgroundColor = [UIColor colorWithWhite:0.18 alpha:0.90];
    self.appsButton.layer.cornerRadius = 6.0;
    self.appsButton.layer.borderColor = [UIColor colorWithWhite:0.35 alpha:0.8].CGColor;
    self.appsButton.layer.borderWidth = 1.0;
    [self.appsButton addTarget:self action:@selector(appsTapped) forControlEvents:UIControlEventTouchUpInside];
    [self.headerView addSubview:self.appsButton];
    
    // Settings Gear button
    self.gearButton = [UIButton buttonWithType:UIButtonTypeCustom];
    self.gearButton.frame = CGRectMake(204, 5, 34, 30);
    [self.gearButton setTitle:@"⚙" forState:UIControlStateNormal];
    [self.gearButton setTitleColor:[UIColor colorWithWhite:0.8 alpha:1.0] forState:UIControlStateNormal];
    [self.gearButton setTitleColor:[UIColor colorWithRed:0.35 green:0.75 blue:1.0 alpha:1.0] forState:UIControlStateHighlighted];
    self.gearButton.titleLabel.font = [UIFont systemFontOfSize:20];
    [self.gearButton addTarget:self action:@selector(gearTapped) forControlEvents:UIControlEventTouchUpInside];
    [self.headerView addSubview:self.gearButton];
    
    // Power ON / Sleep Button
    self.powerButton = [UIButton buttonWithType:UIButtonTypeCustom];
    self.powerButton.frame = CGRectMake(242, 5, 68, 30);
    [self.powerButton setTitle:@"⏻ PWR" forState:UIControlStateNormal];
    [self.powerButton setTitleColor:[UIColor colorWithRed:0.35 green:1.0 blue:0.5 alpha:1.0] forState:UIControlStateNormal];
    [self.powerButton setTitleColor:[UIColor whiteColor] forState:UIControlStateHighlighted];
    self.powerButton.titleLabel.font = [UIFont boldSystemFontOfSize:13];
    self.powerButton.backgroundColor = [UIColor colorWithWhite:0.18 alpha:0.95];
    self.powerButton.layer.cornerRadius = 6.0;
    self.powerButton.layer.borderColor = [UIColor colorWithRed:0.35 green:1.0 blue:0.5 alpha:0.4].CGColor;
    self.powerButton.layer.borderWidth = 1.0;
    [self.powerButton addTarget:self action:@selector(powerTapped) forControlEvents:UIControlEventTouchUpInside];
    
    UILongPressGestureRecognizer *pwrLong = [[UILongPressGestureRecognizer alloc] initWithTarget:self action:@selector(handlePowerLongPress:)];
    pwrLong.minimumPressDuration = 0.8;
    [self.powerButton addGestureRecognizer:pwrLong];
    
    [self.headerView addSubview:self.powerButton];
}

- (void)setupTrackpad {
    CGFloat diameter = 196.0;
    CGFloat padX = (320.0 - diameter) / 2.0; // 62
    CGFloat padY = 60.0;
    
    self.trackpadView = [[ATRTrackpadView alloc] initWithFrame:CGRectMake(padX, padY, diameter, diameter)];
    self.trackpadView.delegate = self;
    [self.view addSubview:self.trackpadView];
}

- (void)setupNowPlayingMarquee {
    self.marqueeContainer = [[UIView alloc] initWithFrame:CGRectMake(20, 268, 280, 28)];
    self.marqueeContainer.backgroundColor = [UIColor colorWithWhite:0.10 alpha:0.8];
    self.marqueeContainer.layer.cornerRadius = 14.0;
    self.marqueeContainer.layer.borderColor = [UIColor colorWithWhite:0.25 alpha:0.7].CGColor;
    self.marqueeContainer.layer.borderWidth = 1.0;
    self.marqueeContainer.layer.masksToBounds = YES;
    self.marqueeContainer.userInteractionEnabled = YES;
    [self.view addSubview:self.marqueeContainer];
    
    // Thumbnail view
    self.nowPlayingThumbView = [[UIImageView alloc] initWithFrame:CGRectMake(4, 3, 22, 22)];
    self.nowPlayingThumbView.layer.cornerRadius = 4.0;
    self.nowPlayingThumbView.layer.masksToBounds = YES;
    self.nowPlayingThumbView.contentMode = UIViewContentModeScaleAspectFill;
    self.nowPlayingThumbView.hidden = YES;
    [self.marqueeContainer addSubview:self.nowPlayingThumbView];
    
    self.marqueeLabel = [[UILabel alloc] initWithFrame:CGRectMake(12, 4, 256, 20)];
    self.marqueeLabel.text = @"Apple TV 4K • Ready";
    self.marqueeLabel.textColor = [UIColor colorWithWhite:0.80 alpha:1.0];
    self.marqueeLabel.font = [UIFont systemFontOfSize:12];
    self.marqueeLabel.textAlignment = UITextAlignmentCenter;
    self.marqueeLabel.backgroundColor = [UIColor clearColor];
    [self.marqueeContainer addSubview:self.marqueeLabel];
    
    UITapGestureRecognizer *tap = [[UITapGestureRecognizer alloc] initWithTarget:self action:@selector(marqueeTapped)];
    [self.marqueeContainer addGestureRecognizer:tap];
}

- (void)setupButtons {
    CGFloat btnW = 126.0;
    CGFloat btnH = 46.0;
    CGFloat col1X = 24.0;
    CGFloat col2X = 320.0 - col1X - btnW; // 170
    
    // Row 1: Menu & Home (Y: 306)
    CGFloat row1Y = 306.0;
    self.menuButton = [self createRemoteButtonWithTitle:@"<  MENU" frame:CGRectMake(col1X, row1Y, btnW, btnH)];
    [self.menuButton addTarget:self action:@selector(menuTapped) forControlEvents:UIControlEventTouchUpInside];
    [self.view addSubview:self.menuButton];
    
    self.homeButton = [self createRemoteButtonWithTitle:@"📺  HOME" frame:CGRectMake(col2X, row1Y, btnW, btnH)];
    [self.homeButton addTarget:self action:@selector(homeTapped) forControlEvents:UIControlEventTouchUpInside];
    [self.view addSubview:self.homeButton];
    
    // Row 2: Play/Pause & Mute (Y: 360)
    CGFloat row2Y = 360.0;
    self.playPauseButton = [self createRemoteButtonWithTitle:@"⏯  PLAY" frame:CGRectMake(col1X, row2Y, btnW, btnH)];
    [self.playPauseButton addTarget:self action:@selector(playPauseTapped) forControlEvents:UIControlEventTouchUpInside];
    [self.view addSubview:self.playPauseButton];
    
    self.muteButton = [self createRemoteButtonWithTitle:@"🔇  MUTE" frame:CGRectMake(col2X, row2Y, btnW, btnH)];
    [self.muteButton addTarget:self action:@selector(muteTapped) forControlEvents:UIControlEventTouchUpInside];
    [self.view addSubview:self.muteButton];
    
    // Row 3: Volume Down & Volume Up (Y: 414)
    CGFloat row3Y = 414.0;
    self.volDownButton = [self createRemoteButtonWithTitle:@"🔉  VOL -" frame:CGRectMake(col1X, row3Y, btnW, btnH)];
    [self.volDownButton addTarget:self action:@selector(volDownTapped) forControlEvents:UIControlEventTouchUpInside];
    [self.view addSubview:self.volDownButton];
    
    self.volUpButton = [self createRemoteButtonWithTitle:@"🔊  VOL +" frame:CGRectMake(col2X, row3Y, btnW, btnH)];
    [self.volUpButton addTarget:self action:@selector(volUpTapped) forControlEvents:UIControlEventTouchUpInside];
    [self.view addSubview:self.volUpButton];
}

- (UIButton *)createRemoteButtonWithTitle:(NSString *)title frame:(CGRect)frame {
    UIButton *btn = [UIButton buttonWithType:UIButtonTypeCustom];
    btn.frame = frame;
    [btn setTitle:title forState:UIControlStateNormal];
    [btn setTitleColor:[UIColor colorWithWhite:0.92 alpha:1.0] forState:UIControlStateNormal];
    [btn setTitleColor:[UIColor colorWithRed:0.35 green:0.80 blue:1.0 alpha:1.0] forState:UIControlStateHighlighted];
    btn.titleLabel.font = [UIFont boldSystemFontOfSize:15];
    btn.backgroundColor = [UIColor colorWithWhite:0.18 alpha:0.90];
    btn.layer.cornerRadius = 10.0;
    btn.layer.borderColor = [UIColor colorWithWhite:0.35 alpha:0.7].CGColor;
    btn.layer.borderWidth = 1.0;
    btn.layer.masksToBounds = YES;
    
    [btn addTarget:self action:@selector(buttonTouchDown:) forControlEvents:UIControlEventTouchDown];
    [btn addTarget:self action:@selector(buttonTouchUp:) forControlEvents:UIControlEventTouchUpInside | UIControlEventTouchUpOutside];
    return btn;
}

- (void)buttonTouchDown:(UIButton *)btn {
    [UIView animateWithDuration:0.08 animations:^{
        btn.transform = CGAffineTransformMakeScale(0.94, 0.94);
        btn.backgroundColor = [UIColor colorWithWhite:0.28 alpha:1.0];
    }];
}

- (void)buttonTouchUp:(UIButton *)btn {
    [UIView animateWithDuration:0.08 animations:^{
        btn.transform = CGAffineTransformIdentity;
        btn.backgroundColor = [UIColor colorWithWhite:0.18 alpha:0.90];
    }];
}

#pragma mark - Actions & Sound

- (void)playClickSound {
    // 1104 = Standard iOS keyboard/UI click sound
    AudioServicesPlaySystemSound(1104);
}

- (void)gearTapped {
    [self playClickSound];
    ATRSettingsViewController *svc = [[ATRSettingsViewController alloc] init];
    svc.delegate = self;
    [self presentModalViewController:svc animated:YES];
}

- (void)settingsDidDismiss {
    [self dismissModalViewControllerAnimated:YES];
    [self refreshConnection];
}

- (void)appsTapped {
    [self playClickSound];
    ATRAppsViewController *avc = [[ATRAppsViewController alloc] init];
    avc.delegate = self;
    [self presentModalViewController:avc animated:YES];
}

- (void)appsViewControllerDidDismiss {
    [self dismissModalViewControllerAnimated:YES];
}

- (void)appsViewControllerDidLaunchAppNamed:(NSString *)name bundleID:(NSString *)bundleID {
    [self applyActiveAppNamed:name bundleID:bundleID isPlaying:YES];
}

- (void)activeAppNotificationReceived:(NSNotification *)note {
    NSString *name = [note.userInfo objectForKey:@"name"];
    NSString *bundleID = [note.userInfo objectForKey:@"bundleID"];
    [self applyActiveAppNamed:name bundleID:bundleID isPlaying:YES];
}

- (void)selectTapped {
    [self playClickSound];
    [self sendCommand:@"select"];
}

- (void)menuTapped {
    [self playClickSound];
    [self sendCommand:@"menu"];
}

- (void)homeTapped {
    [self playClickSound];
    [self sendCommand:@"home"];
    [self applyHomeScreenStatus];
}

- (void)playPauseTapped {
    [self playClickSound];
    [self sendCommand:@"play_pause"];
    [self togglePlayPauseStatus];
}

- (void)muteTapped {
    [self playClickSound];
    [self sendCommand:@"volume_down"];
}

- (void)volDownTapped {
    [self playClickSound];
    [self sendCommand:@"volume_down"];
}

- (void)volUpTapped {
    [self playClickSound];
    [self sendCommand:@"volume_up"];
}

#pragma mark - ATRTrackpadViewDelegate

- (void)trackpadViewDidSelect:(ATRTrackpadView *)trackpad {
    [self selectTapped];
}

- (void)trackpadView:(ATRTrackpadView *)trackpad didNavigateInDirection:(NSString *)direction isSwipe:(BOOL)isSwipe {
    [self playClickSound];
    [self sendCommand:direction];
}

#pragma mark - Power Controls

- (void)powerTapped {
    [self playClickSound];
    
    NSString *mode = [[NSUserDefaults standardUserDefaults] stringForKey:@"ATRConnectionMode"];
    BOOL isStandalone = ![mode isEqualToString:@"Bridge"];
    BOOL connected = isStandalone ? [ATRCompanionClient sharedClient].isEncrypted : [ATRClient sharedClient].isConnected;
    
    if (!connected) {
        // Asleep or disconnected: send Wake command
        [self sendCommand:@"wake"];
        self.marqueeLabel.text = @"Waking Apple TV...";
    } else {
        // Connected: show Power sheet
        UIActionSheet *sheet = [[UIActionSheet alloc] initWithTitle:@"Apple TV Power"
                                                           delegate:self
                                                  cancelButtonTitle:@"Cancel"
                                             destructiveButtonTitle:@"Sleep Apple TV"
                                                  otherButtonTitles:@"Wake Apple TV", nil];
        [sheet showInView:self.view];
    }
}

- (void)handlePowerLongPress:(UILongPressGestureRecognizer *)gesture {
    if (gesture.state == UIGestureRecognizerStateBegan) {
        [self playClickSound];
        [self sendCommand:@"sleep"];
        self.marqueeLabel.text = @"Putting Apple TV to Sleep...";
    }
}

- (void)actionSheet:(UIActionSheet *)actionSheet clickedButtonAtIndex:(NSInteger)buttonIndex {
    if (buttonIndex == actionSheet.destructiveButtonIndex) {
        [self playClickSound];
        [self sendCommand:@"sleep"];
    } else if (buttonIndex == 1) {
        [self playClickSound];
        [self sendCommand:@"wake"];
    }
}

- (void)sendCommand:(NSString *)key {
    NSString *mode = [[NSUserDefaults standardUserDefaults] stringForKey:@"ATRConnectionMode"];
    if ([mode isEqualToString:@"Bridge"]) {
        [[ATRClient sharedClient] pressKey:key completion:^(BOOL success, NSString *error) {
            if (!success) {
                NSLog(@"[Remote] Failed to send '%@': %@", key, error);
            }
        }];
    } else {
        // Direct Companion Standalone
        [[ATRCompanionClient sharedClient] sendHIDCommandNamed:key];
    }
}

#pragma mark - Polling & State

- (void)startPolling {
    [self stopPolling];
    self.pollTimer = [NSTimer scheduledTimerWithTimeInterval:3.0
                                                      target:self
                                                    selector:@selector(pollTick)
                                                    userInfo:nil
                                                     repeats:YES];
}

- (void)stopPolling {
    if (self.pollTimer) {
        [self.pollTimer invalidate];
        self.pollTimer = nil;
    }
}

- (void)pollTick {
    [self refreshConnection];
}

- (void)refreshConnection {
    NSString *mode = [[NSUserDefaults standardUserDefaults] stringForKey:@"ATRConnectionMode"];
    if ([mode isEqualToString:@"Bridge"]) {
        [[ATRClient sharedClient] fetchStatusWithCompletion:^(BOOL connected, BOOL paired, NSString *device, NSString *error) {
            [self updateStatusUI];
        }];
        [[ATRClient sharedClient] fetchNowPlayingWithCompletion:nil];
    } else {
        [self updateStatusUI];
    }
}

- (void)updateStatusUI {
    NSString *mode = [[NSUserDefaults standardUserDefaults] stringForKey:@"ATRConnectionMode"];
    if ([mode isEqualToString:@"Bridge"]) {
        ATRClient *client = [ATRClient sharedClient];
        self.titleLabel.text = client.deviceName.length > 0 ? client.deviceName : @"Apple TV 4K";
        
        if (client.isConnected && client.isPaired) {
            self.ledDot.backgroundColor = [UIColor colorWithRed:0.2 green:0.85 blue:0.35 alpha:1.0]; // Bright Green
            [self.powerButton setTitleColor:[UIColor colorWithRed:0.35 green:1.0 blue:0.5 alpha:1.0] forState:UIControlStateNormal];
            self.powerButton.layer.borderColor = [UIColor colorWithRed:0.35 green:1.0 blue:0.5 alpha:0.8].CGColor;
        } else if (client.isPaired) {
            self.ledDot.backgroundColor = [UIColor colorWithRed:0.95 green:0.75 blue:0.2 alpha:1.0]; // Amber
            [self.powerButton setTitleColor:[UIColor colorWithRed:1.0 green:0.75 blue:0.2 alpha:1.0] forState:UIControlStateNormal];
            self.powerButton.layer.borderColor = [UIColor colorWithRed:1.0 green:0.75 blue:0.2 alpha:0.6].CGColor;
        } else {
            self.ledDot.backgroundColor = [UIColor colorWithRed:0.95 green:0.25 blue:0.25 alpha:1.0]; // Red
            [self.powerButton setTitleColor:[UIColor colorWithRed:1.0 green:0.35 blue:0.35 alpha:1.0] forState:UIControlStateNormal];
            self.powerButton.layer.borderColor = [UIColor colorWithRed:1.0 green:0.35 blue:0.35 alpha:0.5].CGColor;
        }
    } else {
        // Direct Companion Mode
        ATRCompanionClient *comp = [ATRCompanionClient sharedClient];
        self.titleLabel.text = @"Apple TV 4K (Direct)";
        if (comp.isEncrypted) {
            self.ledDot.backgroundColor = [UIColor colorWithRed:0.2 green:0.85 blue:0.35 alpha:1.0]; // Green
            self.marqueeLabel.text = @"Apple TV 4K • Direct Connected";
            [self.powerButton setTitleColor:[UIColor colorWithRed:0.35 green:1.0 blue:0.5 alpha:1.0] forState:UIControlStateNormal];
            self.powerButton.layer.borderColor = [UIColor colorWithRed:0.35 green:1.0 blue:0.5 alpha:0.8].CGColor;
        } else if (comp.isConnected) {
            self.ledDot.backgroundColor = [UIColor colorWithRed:0.95 green:0.75 blue:0.2 alpha:1.0]; // Amber
            self.marqueeLabel.text = @"Direct Connecting...";
            [self.powerButton setTitleColor:[UIColor colorWithRed:1.0 green:0.75 blue:0.2 alpha:1.0] forState:UIControlStateNormal];
            self.powerButton.layer.borderColor = [UIColor colorWithRed:1.0 green:0.75 blue:0.2 alpha:0.6].CGColor;
        } else if (comp.isPaired) {
            self.ledDot.backgroundColor = [UIColor colorWithWhite:0.5 alpha:1.0]; // Gray
            self.marqueeLabel.text = @"Standalone Mode (Paired)";
            [self.powerButton setTitleColor:[UIColor colorWithRed:0.35 green:1.0 blue:0.5 alpha:1.0] forState:UIControlStateNormal];
            self.powerButton.layer.borderColor = [UIColor colorWithRed:0.35 green:1.0 blue:0.5 alpha:0.4].CGColor;
        } else {
            self.ledDot.backgroundColor = [UIColor colorWithRed:0.95 green:0.25 blue:0.25 alpha:1.0]; // Red
            self.marqueeLabel.text = @"Standalone (Tap ⚙ to Setup)";
            [self.powerButton setTitleColor:[UIColor colorWithRed:1.0 green:0.35 blue:0.35 alpha:1.0] forState:UIControlStateNormal];
            self.powerButton.layer.borderColor = [UIColor colorWithRed:1.0 green:0.35 blue:0.35 alpha:0.5].CGColor;
        }
    }
}

- (void)updateNowPlayingUI:(NSNotification *)note {
    NSString *mode = [[NSUserDefaults standardUserDefaults] stringForKey:@"ATRConnectionMode"];
    if ([mode isEqualToString:@"Bridge"]) {
        ATRClient *client = [ATRClient sharedClient];
        if (client.nowPlayingTitle.length > 0) {
            [self applyNowPlayingTitle:client.nowPlayingTitle artist:client.nowPlayingArtist];
        } else {
            [self applyNowPlayingTitle:nil artist:nil];
        }
    }
}

- (void)applyActiveAppNamed:(NSString *)name bundleID:(NSString *)bundleID isPlaying:(BOOL)isPlaying {
    if (!name || [name length] == 0) return;
    
    self.currentActiveAppName = name;
    self.currentActiveBundleID = bundleID;
    self.isPlaying = isPlaying;
    
    // Set custom app icon
    UIImage *appIcon = [ATRIconProvider iconForBundleID:bundleID name:name size:CGSizeMake(22, 22)];
    self.currentArtworkImage = [ATRIconProvider iconForBundleID:bundleID name:name size:CGSizeMake(150, 150)];
    
    self.nowPlayingThumbView.image = appIcon;
    self.nowPlayingThumbView.hidden = NO;
    
    NSString *symbol = isPlaying ? @"▶" : @"⏸";
    self.marqueeLabel.text = [NSString stringWithFormat:@"%@ %@ • %@", symbol, name, isPlaying ? @"Active" : @"Paused"];
    self.marqueeLabel.frame = CGRectMake(32, 4, 240, 20);
    self.marqueeLabel.textAlignment = UITextAlignmentLeft;
}

- (void)togglePlayPauseStatus {
    if (self.currentActiveAppName) {
        self.isPlaying = !self.isPlaying;
        [self applyActiveAppNamed:self.currentActiveAppName bundleID:self.currentActiveBundleID isPlaying:self.isPlaying];
    }
}

- (void)applyHomeScreenStatus {
    self.currentActiveAppName = nil;
    self.currentActiveBundleID = nil;
    self.currentArtworkImage = nil;
    self.nowPlayingThumbView.hidden = YES;
    self.marqueeLabel.frame = CGRectMake(12, 4, 256, 20);
    self.marqueeLabel.textAlignment = UITextAlignmentCenter;
    self.marqueeLabel.text = @"Apple TV 4K • Home Screen";
}

- (void)applyNowPlayingTitle:(NSString *)title artist:(NSString *)artist {
    if (title && [title length] > 0) {
        [self applyActiveAppNamed:title bundleID:nil isPlaying:YES];
        if (artist && [artist length] > 0) {
            self.marqueeLabel.text = [NSString stringWithFormat:@"▶ %@ • %@", title, artist];
        }
    } else if (!self.currentActiveAppName) {
        self.currentArtworkImage = nil;
        self.nowPlayingThumbView.hidden = YES;
        self.marqueeLabel.frame = CGRectMake(12, 4, 256, 20);
        self.marqueeLabel.textAlignment = UITextAlignmentCenter;
        [self updateStatusUI];
    }
}

- (void)marqueeTapped {
    if (self.currentActiveAppName) {
        [self showNowPlayingPopup];
    } else {
        [self appsTapped];
    }
}

- (void)popupSwitchAppTapped {
    [self dismissNowPlayingPopup];
    [self appsTapped];
}

- (void)showNowPlayingPopup {
    if (self.nowPlayingOverlay) return;
    
    self.nowPlayingOverlay = [[UIView alloc] initWithFrame:self.view.bounds];
    self.nowPlayingOverlay.backgroundColor = [UIColor colorWithWhite:0.0 alpha:0.75];
    self.nowPlayingOverlay.alpha = 0.0;
    
    UITapGestureRecognizer *dismissTap = [[UITapGestureRecognizer alloc] initWithTarget:self action:@selector(dismissNowPlayingPopup)];
    [self.nowPlayingOverlay addGestureRecognizer:dismissTap];
    
    // Popup Card
    UIView *card = [[UIView alloc] initWithFrame:CGRectMake(30, 80, 260, 310)];
    card.backgroundColor = [UIColor colorWithRed:0.12 green:0.13 blue:0.16 alpha:0.98];
    card.layer.cornerRadius = 14.0;
    card.layer.borderColor = [UIColor colorWithWhite:0.35 alpha:1.0].CGColor;
    card.layer.borderWidth = 1.0;
    card.layer.shadowColor = [UIColor blackColor].CGColor;
    card.layer.shadowOffset = CGSizeMake(0, 4);
    card.layer.shadowOpacity = 0.6;
    card.layer.shadowRadius = 8.0;
    [self.nowPlayingOverlay addSubview:card];
    
    // Artwork Image View
    UIImageView *largeArt = [[UIImageView alloc] initWithFrame:CGRectMake(55, 20, 150, 150)];
    largeArt.layer.cornerRadius = 12.0;
    largeArt.layer.masksToBounds = YES;
    largeArt.contentMode = UIViewContentModeScaleAspectFill;
    largeArt.image = self.currentArtworkImage ?: [ATRIconProvider iconForBundleID:self.currentActiveBundleID name:self.currentActiveAppName size:CGSizeMake(150, 150)];
    largeArt.layer.borderColor = [UIColor colorWithWhite:0.3 alpha:0.6].CGColor;
    largeArt.layer.borderWidth = 1.0;
    [card addSubview:largeArt];
    
    // Title Label
    UILabel *titleLbl = [[UILabel alloc] initWithFrame:CGRectMake(16, 180, 228, 28)];
    titleLbl.text = self.currentActiveAppName ?: @"Apple TV 4K";
    titleLbl.textColor = [UIColor whiteColor];
    titleLbl.font = [UIFont boldSystemFontOfSize:18];
    titleLbl.textAlignment = UITextAlignmentCenter;
    titleLbl.adjustsFontSizeToFitWidth = YES;
    titleLbl.backgroundColor = [UIColor clearColor];
    [card addSubview:titleLbl];
    
    // Status Label
    UILabel *artistLbl = [[UILabel alloc] initWithFrame:CGRectMake(16, 208, 228, 20)];
    artistLbl.text = self.isPlaying ? @"Playing on Apple TV 4K" : @"Paused on Apple TV 4K";
    artistLbl.textColor = [UIColor colorWithRed:0.35 green:0.75 blue:1.0 alpha:1.0];
    artistLbl.font = [UIFont systemFontOfSize:13];
    artistLbl.textAlignment = UITextAlignmentCenter;
    artistLbl.adjustsFontSizeToFitWidth = YES;
    artistLbl.backgroundColor = [UIColor clearColor];
    [card addSubview:artistLbl];
    
    // Switch App button
    UIButton *switchBtn = [UIButton buttonWithType:UIButtonTypeCustom];
    switchBtn.frame = CGRectMake(18, 248, 106, 36);
    switchBtn.backgroundColor = [UIColor colorWithRed:0.20 green:0.55 blue:0.90 alpha:1.0];
    switchBtn.layer.cornerRadius = 6.0;
    switchBtn.layer.borderColor = [UIColor colorWithWhite:0.4 alpha:0.5].CGColor;
    switchBtn.layer.borderWidth = 1.0;
    [switchBtn setTitle:@"📱 Apps" forState:UIControlStateNormal];
    [switchBtn setTitleColor:[UIColor whiteColor] forState:UIControlStateNormal];
    switchBtn.titleLabel.font = [UIFont boldSystemFontOfSize:14];
    [switchBtn addTarget:self action:@selector(popupSwitchAppTapped) forControlEvents:UIControlEventTouchUpInside];
    [card addSubview:switchBtn];
    
    // Close button
    UIButton *closeBtn = [UIButton buttonWithType:UIButtonTypeCustom];
    closeBtn.frame = CGRectMake(136, 248, 106, 36);
    closeBtn.backgroundColor = [UIColor colorWithWhite:0.22 alpha:1.0];
    closeBtn.layer.cornerRadius = 6.0;
    closeBtn.layer.borderColor = [UIColor colorWithWhite:0.4 alpha:0.5].CGColor;
    closeBtn.layer.borderWidth = 1.0;
    [closeBtn setTitle:@"Close" forState:UIControlStateNormal];
    [closeBtn setTitleColor:[UIColor whiteColor] forState:UIControlStateNormal];
    closeBtn.titleLabel.font = [UIFont boldSystemFontOfSize:14];
    [closeBtn addTarget:self action:@selector(dismissNowPlayingPopup) forControlEvents:UIControlEventTouchUpInside];
    [card addSubview:closeBtn];
    
    [self.view addSubview:self.nowPlayingOverlay];
    
    [UIView animateWithDuration:0.25 animations:^{
        self.nowPlayingOverlay.alpha = 1.0;
    }];
}

- (void)dismissNowPlayingPopup {
    if (!self.nowPlayingOverlay) return;
    [UIView animateWithDuration:0.2 animations:^{
        self.nowPlayingOverlay.alpha = 0.0;
    } completion:^(BOOL finished) {
        [self.nowPlayingOverlay removeFromSuperview];
        self.nowPlayingOverlay = nil;
    }];
}

#pragma mark - ATRCompanionClientDelegate

- (void)companionClientDidConnect {
    [self updateStatusUI];
}

- (void)companionClientDidDisconnect:(NSString *)error {
    [self updateStatusUI];
}

- (void)companionClientStateChanged:(NSString *)state {
    if (!self.currentNowPlayingTitle) {
        self.marqueeLabel.text = state;
    }
    [self updateStatusUI];
}

- (void)companionClientReceivedNowPlaying:(NSDictionary *)info {
    NSLog(@"[ATRRemoteViewController] Received Now Playing event: %@", info);
    NSString *title = [info objectForKey:@"_npT"];
    NSString *artist = [info objectForKey:@"_npA"];
    [self applyNowPlayingTitle:title artist:artist];
}

@end
