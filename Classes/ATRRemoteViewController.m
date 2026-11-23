#import "ATRRemoteViewController.h"
#import "ATRSettingsViewController.h"
#import "ATRAppsViewController.h"
#import "ATRClient.h"
#import "Companion/ATRCompanionClient.h"
#import "ATRIconProvider.h"
#import "ATRTrackpadView.h"
#import <AudioToolbox/AudioToolbox.h>
#import <QuartzCore/QuartzCore.h>
#import <objc/message.h>

@interface ATRRemoteViewController () <ATRSettingsDelegate, ATRCompanionClientDelegate, ATRAppsViewControllerDelegate, ATRTrackpadViewDelegate, UIActionSheetDelegate, UIAlertViewDelegate>

@property (nonatomic, strong) UIView *headerView;
@property (nonatomic, strong) UIView *ledDot;
@property (nonatomic, strong) UILabel *titleLabel;
@property (nonatomic, strong) UIButton *keyboardButton;
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
@property (nonatomic, strong) UIButton *searchButton;
@property (nonatomic, strong) UIButton *muteButton;
@property (nonatomic, strong) UIButton *controlCenterButton;
@property (nonatomic, strong) UIButton *volDownButton;
@property (nonatomic, strong) UIButton *volUpButton;

// Dynamic Panels & Mode Switcher
@property (nonatomic, strong) UIView *buttonsContainer;
@property (nonatomic, strong) UISegmentedControl *modeSwitcher;
@property (nonatomic, strong) UIView *navigationPanel;
@property (nonatomic, strong) UIView *playbackPanel;
@property (nonatomic, assign) NSInteger currentLayoutMode;

@property (nonatomic, strong) NSTimer *pollTimer;

@end

@implementation ATRRemoteViewController

- (void)viewDidLoad {
    [super viewDidLoad];
    
    // Remote chassis metallic background
    self.view.backgroundColor = [UIColor colorWithRed:0.09 green:0.10 blue:0.12 alpha:1.0];
    
    CGRect screenBounds = [UIScreen mainScreen].bounds;
    CAGradientLayer *grad = [CAGradientLayer layer];
    grad.frame = screenBounds;
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
                                               
    [[NSNotificationCenter defaultCenter] addObserver:self
                                             selector:@selector(textInputNotificationReceived:)
                                                 name:@"ATRTextInputRequestedNotification"
                                               object:nil];
                                               
    [self setupRemoteCommandCenter];
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
                [[NSFileManager defaultManager] createDirectoryAtPath:docs withIntermediateDirectories:YES attributes:nil error:nil];
                NSString *path = [docs stringByAppendingPathComponent:@"remote_screen.png"];
                NSData *pngData = UIImagePNGRepresentation(img);
                [pngData writeToFile:path atomically:YES];
                [pngData writeToFile:@"/tmp/remote_screen.png" atomically:YES];
                NSLog(@"[Screenshot] Saved remote screenshot to %@ and /tmp/remote_screen.png", path);
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
    self.ledDot = [[UIView alloc] initWithFrame:CGRectMake(8, 16, 8, 8)];
    self.ledDot.layer.cornerRadius = 4.0;
    self.ledDot.layer.masksToBounds = YES;
    self.ledDot.backgroundColor = [UIColor colorWithWhite:0.25 alpha:1.0];
    self.ledDot.layer.borderColor = [UIColor colorWithWhite:0.35 alpha:0.6].CGColor;
    self.ledDot.layer.borderWidth = 1.0;
    [self.headerView addSubview:self.ledDot];
    
    // Device title
    self.titleLabel = [[UILabel alloc] initWithFrame:CGRectMake(22, 7, 92, 26)];
    self.titleLabel.text = @"Apple TV 4K";
    self.titleLabel.textColor = [UIColor colorWithWhite:0.92 alpha:1.0];
    self.titleLabel.font = [UIFont boldSystemFontOfSize:14];
    self.titleLabel.backgroundColor = [UIColor clearColor];
    [self.headerView addSubview:self.titleLabel];
    
    // Keyboard Button
    self.keyboardButton = [UIButton buttonWithType:UIButtonTypeCustom];
    self.keyboardButton.frame = CGRectMake(118, 5, 34, 30);
    [self.keyboardButton setTitle:@"⌨" forState:UIControlStateNormal];
    [self.keyboardButton setTitleColor:[UIColor colorWithWhite:0.92 alpha:1.0] forState:UIControlStateNormal];
    [self.keyboardButton setTitleColor:[UIColor whiteColor] forState:UIControlStateHighlighted];
    self.keyboardButton.titleLabel.font = [UIFont systemFontOfSize:18];
    self.keyboardButton.backgroundColor = [UIColor colorWithWhite:0.16 alpha:0.95];
    self.keyboardButton.layer.cornerRadius = 8.0;
    self.keyboardButton.layer.borderColor = [UIColor colorWithWhite:0.28 alpha:0.5].CGColor;
    self.keyboardButton.layer.borderWidth = 1.0;
    [self.keyboardButton addTarget:self action:@selector(keyboardTapped) forControlEvents:UIControlEventTouchUpInside];
    [self.headerView addSubview:self.keyboardButton];
    
    // Apps Button
    self.appsButton = [UIButton buttonWithType:UIButtonTypeCustom];
    self.appsButton.frame = CGRectMake(156, 5, 48, 30);
    [self.appsButton setTitle:@"APPS" forState:UIControlStateNormal];
    [self.appsButton setTitleColor:[UIColor colorWithWhite:0.92 alpha:1.0] forState:UIControlStateNormal];
    [self.appsButton setTitleColor:[UIColor whiteColor] forState:UIControlStateHighlighted];
    self.appsButton.titleLabel.font = [UIFont boldSystemFontOfSize:11];
    self.appsButton.backgroundColor = [UIColor colorWithWhite:0.16 alpha:0.95];
    self.appsButton.layer.cornerRadius = 8.0;
    self.appsButton.layer.borderColor = [UIColor colorWithWhite:0.28 alpha:0.5].CGColor;
    self.appsButton.layer.borderWidth = 1.0;
    [self.appsButton addTarget:self action:@selector(appsTapped) forControlEvents:UIControlEventTouchUpInside];
    [self.headerView addSubview:self.appsButton];
    
    // Settings Gear button
    self.gearButton = [UIButton buttonWithType:UIButtonTypeCustom];
    self.gearButton.frame = CGRectMake(208, 5, 34, 30);
    [self.gearButton setTitle:@"⚙" forState:UIControlStateNormal];
    [self.gearButton setTitleColor:[UIColor colorWithWhite:0.92 alpha:1.0] forState:UIControlStateNormal];
    [self.gearButton setTitleColor:[UIColor whiteColor] forState:UIControlStateHighlighted];
    self.gearButton.titleLabel.font = [UIFont systemFontOfSize:19];
    self.gearButton.backgroundColor = [UIColor colorWithWhite:0.16 alpha:0.95];
    self.gearButton.layer.cornerRadius = 8.0;
    self.gearButton.layer.borderColor = [UIColor colorWithWhite:0.28 alpha:0.5].CGColor;
    self.gearButton.layer.borderWidth = 1.0;
    [self.gearButton addTarget:self action:@selector(gearTapped) forControlEvents:UIControlEventTouchUpInside];
    [self.headerView addSubview:self.gearButton];
    
    // Power ON / Sleep Button
    self.powerButton = [UIButton buttonWithType:UIButtonTypeCustom];
    self.powerButton.frame = CGRectMake(246, 5, 66, 30);
    UIImage *pwrNormal = [self powerIconWithSize:CGSizeMake(22, 22) color:[UIColor colorWithWhite:0.92 alpha:1.0]];
    UIImage *pwrHigh = [self powerIconWithSize:CGSizeMake(22, 22) color:[UIColor whiteColor]];
    [self.powerButton setImage:pwrNormal forState:UIControlStateNormal];
    [self.powerButton setImage:pwrHigh forState:UIControlStateHighlighted];
    self.powerButton.backgroundColor = [UIColor colorWithWhite:0.16 alpha:0.95];
    self.powerButton.layer.cornerRadius = 8.0;
    self.powerButton.layer.borderColor = [UIColor colorWithWhite:0.28 alpha:0.5].CGColor;
    self.powerButton.layer.borderWidth = 1.0;
    [self.powerButton addTarget:self action:@selector(powerTapped) forControlEvents:UIControlEventTouchUpInside];
    [self.powerButton addTarget:self action:@selector(buttonTouchDown:) forControlEvents:UIControlEventTouchDown];
    [self.powerButton addTarget:self action:@selector(buttonTouchUp:) forControlEvents:UIControlEventTouchUpInside | UIControlEventTouchUpOutside];
    
    UILongPressGestureRecognizer *pwrLong = [[UILongPressGestureRecognizer alloc] initWithTarget:self action:@selector(handlePowerLongPress:)];
    pwrLong.minimumPressDuration = 0.8;
    [self.powerButton addGestureRecognizer:pwrLong];
    
    [self.headerView addSubview:self.powerButton];
}

- (UIImage *)powerIconWithSize:(CGSize)size color:(UIColor *)color {
    UIGraphicsBeginImageContextWithOptions(size, NO, 0.0);
    
    CGFloat w = size.width;
    CGFloat h = size.height;
    CGPoint center = CGPointMake(w / 2.0, h / 2.0);
    CGFloat radius = (MIN(w, h) - 5.0) / 2.0;
    
    // Circle arc with top gap (from -60 deg to 240 deg)
    CGFloat startAngle = (CGFloat)(-60.0 * M_PI / 180.0);
    CGFloat endAngle   = (CGFloat)(240.0 * M_PI / 180.0);
    
    UIBezierPath *path = [UIBezierPath bezierPathWithArcCenter:center
                                                        radius:radius
                                                    startAngle:startAngle
                                                      endAngle:endAngle
                                                     clockwise:YES];
    path.lineWidth = 2.0;
    path.lineCapStyle = kCGLineCapRound;
    
    // Center vertical stroke in the top gap
    [path moveToPoint:CGPointMake(center.x, center.y - radius - 1.5)];
    [path addLineToPoint:CGPointMake(center.x, center.y + 1.0)];
    
    [color setStroke];
    [path stroke];
    
    UIImage *img = UIGraphicsGetImageFromCurrentImageContext();
    UIGraphicsEndImageContext();
    return img;
}

- (void)setupTrackpad {
    CGFloat screenH = [UIScreen mainScreen].bounds.size.height;
    BOOL isTall = (screenH > 500.0);
    
    CGFloat diameter = isTall ? 204.0 : 196.0;
    CGFloat padX = (320.0 - diameter) / 2.0; // 58 or 62
    CGFloat padY = isTall ? 62.0 : 60.0;
    
    self.trackpadView = [[ATRTrackpadView alloc] initWithFrame:CGRectMake(padX, padY, diameter, diameter)];
    self.trackpadView.delegate = self;
    [self.view addSubview:self.trackpadView];
}

- (void)setupNowPlayingMarquee {
    CGFloat screenH = [UIScreen mainScreen].bounds.size.height;
    BOOL isTall = (screenH > 500.0);
    
    CGFloat marqY = isTall ? 278.0 : 268.0;
    CGFloat marqH = isTall ? 30.0 : 28.0;
    
    self.marqueeContainer = [[UIView alloc] initWithFrame:CGRectMake(20, marqY, 280, marqH)];
    self.marqueeContainer.backgroundColor = [UIColor colorWithWhite:0.10 alpha:0.8];
    self.marqueeContainer.layer.cornerRadius = marqH / 2.0;
    self.marqueeContainer.layer.borderColor = [UIColor colorWithWhite:0.25 alpha:0.7].CGColor;
    self.marqueeContainer.layer.borderWidth = 1.0;
    self.marqueeContainer.layer.masksToBounds = YES;
    self.marqueeContainer.userInteractionEnabled = YES;
    [self.view addSubview:self.marqueeContainer];
    
    // Thumbnail view
    CGFloat thumbSize = isTall ? 24.0 : 22.0;
    self.nowPlayingThumbView = [[UIImageView alloc] initWithFrame:CGRectMake(4, (marqH - thumbSize) / 2.0, thumbSize, thumbSize)];
    self.nowPlayingThumbView.layer.cornerRadius = 4.0;
    self.nowPlayingThumbView.layer.masksToBounds = YES;
    self.nowPlayingThumbView.contentMode = UIViewContentModeScaleAspectFill;
    self.nowPlayingThumbView.hidden = YES;
    [self.marqueeContainer addSubview:self.nowPlayingThumbView];
    
    self.marqueeLabel = [[UILabel alloc] initWithFrame:CGRectMake(12, (marqH - 20) / 2.0, 256, 20)];
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
    CGFloat screenH = [UIScreen mainScreen].bounds.size.height;
    BOOL isTall = (screenH > 500.0);
    
    // Top of button area
    CGFloat containerY = isTall ? 312.0 : 298.0;
    CGFloat containerH = isTall ? 250.0 : 178.0;
    
    self.buttonsContainer = [[UIView alloc] initWithFrame:CGRectMake(0, containerY, 320.0, containerH)];
    self.buttonsContainer.backgroundColor = [UIColor clearColor];
    [self.view addSubview:self.buttonsContainer];
    
    // Segmented Mode Switcher: [ Navigation | Playback ]
    CGFloat segW = isTall ? 220.0 : 200.0;
    CGFloat segH = isTall ? 26.0 : 22.0;
    CGFloat segX = (320.0 - segW) / 2.0;
    self.modeSwitcher = [[UISegmentedControl alloc] initWithItems:@[@"Navigation", @"Playback"]];
    self.modeSwitcher.frame = CGRectMake(segX, 0, segW, segH);
    self.modeSwitcher.segmentedControlStyle = UISegmentedControlStyleBar;
    self.modeSwitcher.tintColor = [UIColor colorWithWhite:0.38 alpha:1.0];
    self.modeSwitcher.selectedSegmentIndex = 0;
    [self.modeSwitcher addTarget:self action:@selector(modeSwitcherChanged:) forControlEvents:UIControlEventValueChanged];
    [self.buttonsContainer addSubview:self.modeSwitcher];
    
    // Fixed Row 1: MENU and TV (available in both modes)
    CGFloat btnW1 = 132.0;
    CGFloat btnH1 = isTall ? 44.0 : 33.0;
    CGFloat col1X = 20.0;
    CGFloat col2X = 320.0 - col1X - btnW1; // 168.0
    CGFloat r1Y = isTall ? 32.0 : 27.0;
    
    self.menuButton = [self createRemoteButtonWithTitle:@"MENU" frame:CGRectMake(col1X, r1Y, btnW1, btnH1)];
    self.menuButton.titleLabel.font = [UIFont boldSystemFontOfSize:isTall ? 14.0 : 12.0];
    [self.menuButton addTarget:self action:@selector(menuTapped) forControlEvents:UIControlEventTouchUpInside];
    [self.buttonsContainer addSubview:self.menuButton];
    
    self.homeButton = [self createRemoteButtonWithTitle:@"TV" frame:CGRectMake(col2X, r1Y, btnW1, btnH1)];
    self.homeButton.titleLabel.font = [UIFont boldSystemFontOfSize:isTall ? 15.0 : 13.0];
    [self.homeButton addTarget:self action:@selector(homeTapped) forControlEvents:UIControlEventTouchUpInside];
    [self.buttonsContainer addSubview:self.homeButton];
    
    // Dynamic Panels Frame (Rows 2, 3, 4)
    CGFloat dynamicY = r1Y + btnH1 + (isTall ? 7.0 : 4.0);
    CGFloat dynamicH = containerH - dynamicY;
    CGRect dynamicFrame = CGRectMake(0, dynamicY, 320.0, dynamicH);
    
    self.navigationPanel = [[UIView alloc] initWithFrame:dynamicFrame];
    self.navigationPanel.backgroundColor = [UIColor clearColor];
    [self.buttonsContainer addSubview:self.navigationPanel];
    
    self.playbackPanel = [[UIView alloc] initWithFrame:dynamicFrame];
    self.playbackPanel.backgroundColor = [UIColor clearColor];
    self.playbackPanel.hidden = YES;
    self.playbackPanel.alpha = 0.0;
    [self.buttonsContainer addSubview:self.playbackPanel];
    
    [self setupNavigationPanelButtons:isTall];
    [self setupPlaybackPanelButtons:isTall];
}

- (void)setupNavigationPanelButtons:(BOOL)isTall {
    CGFloat btnW = 132.0;
    CGFloat btnH = isTall ? 44.0 : 33.0;
    CGFloat col1X = 20.0;
    CGFloat col2X = 320.0 - col1X - btnW; // 168.0
    CGFloat rowGap = isTall ? 7.0 : 4.0;
    
    // Row 2: ▶‖ & SEARCH
    CGFloat r2Y = 0.0;
    self.playPauseButton = [self createRemoteButtonWithTitle:@"▶‖" frame:CGRectMake(col1X, r2Y, btnW, btnH)];
    self.playPauseButton.titleLabel.font = [UIFont boldSystemFontOfSize:isTall ? 17.0 : 15.0];
    [self.playPauseButton addTarget:self action:@selector(playPauseTapped) forControlEvents:UIControlEventTouchUpInside];
    [self.navigationPanel addSubview:self.playPauseButton];
    
    self.searchButton = [self createRemoteButtonWithTitle:@"SEARCH" frame:CGRectMake(col2X, r2Y, btnW, btnH)];
    self.searchButton.titleLabel.font = [UIFont boldSystemFontOfSize:isTall ? 14.0 : 12.0];
    [self.searchButton addTarget:self action:@selector(searchTapped) forControlEvents:UIControlEventTouchUpInside];
    [self.navigationPanel addSubview:self.searchButton];
    
    // Row 3: MUTE & CONTROL
    CGFloat r3Y = r2Y + btnH + rowGap;
    self.muteButton = [self createRemoteButtonWithTitle:@"MUTE" frame:CGRectMake(col1X, r3Y, btnW, btnH)];
    self.muteButton.titleLabel.font = [UIFont boldSystemFontOfSize:isTall ? 14.0 : 12.0];
    [self.muteButton addTarget:self action:@selector(muteTapped) forControlEvents:UIControlEventTouchUpInside];
    [self.navigationPanel addSubview:self.muteButton];
    
    self.controlCenterButton = [self createRemoteButtonWithTitle:@"CONTROL" frame:CGRectMake(col2X, r3Y, btnW, btnH)];
    self.controlCenterButton.titleLabel.font = [UIFont boldSystemFontOfSize:isTall ? 14.0 : 12.0];
    [self.controlCenterButton addTarget:self action:@selector(controlCenterTapped) forControlEvents:UIControlEventTouchUpInside];
    [self.navigationPanel addSubview:self.controlCenterButton];
    
    // Row 4: − & +
    CGFloat r4Y = r3Y + btnH + rowGap;
    self.volDownButton = [self createRemoteButtonWithTitle:@"−" frame:CGRectMake(col1X, r4Y, btnW, btnH)];
    self.volDownButton.titleLabel.font = [UIFont boldSystemFontOfSize:isTall ? 24.0 : 20.0];
    [self.volDownButton addTarget:self action:@selector(volDownTapped) forControlEvents:UIControlEventTouchUpInside];
    [self.navigationPanel addSubview:self.volDownButton];
    
    self.volUpButton = [self createRemoteButtonWithTitle:@"+" frame:CGRectMake(col2X, r4Y, btnW, btnH)];
    self.volUpButton.titleLabel.font = [UIFont boldSystemFontOfSize:isTall ? 24.0 : 20.0];
    [self.volUpButton addTarget:self action:@selector(volUpTapped) forControlEvents:UIControlEventTouchUpInside];
    [self.navigationPanel addSubview:self.volUpButton];
}

- (void)setupPlaybackPanelButtons:(BOOL)isTall {
    CGFloat btnH = isTall ? 44.0 : 33.0;
    CGFloat rowGap = isTall ? 7.0 : 4.0;
    
    // Row 2: 4 buttons (−10s | ▶ | ❚❚ | +10s)
    CGFloat r2Y = 0.0;
    CGFloat btnW4 = 64.0;
    CGFloat gap4 = 8.0;
    CGFloat x0_4 = 20.0;
    
    // 1. Skip Backward 10s (Long press for Rewind)
    UIButton *skipBackBtn = [self createRemoteButtonWithTitle:@"−10s" frame:CGRectMake(x0_4, r2Y, btnW4, btnH)];
    skipBackBtn.titleLabel.font = [UIFont boldSystemFontOfSize:isTall ? 13.0 : 11.5];
    [skipBackBtn addTarget:self action:@selector(skipBackwardTapped) forControlEvents:UIControlEventTouchUpInside];
    UILongPressGestureRecognizer *rwHold = [[UILongPressGestureRecognizer alloc] initWithTarget:self action:@selector(skipBackwardLongPressed:)];
    rwHold.minimumPressDuration = 0.45;
    [skipBackBtn addGestureRecognizer:rwHold];
    [self.playbackPanel addSubview:skipBackBtn];
    
    // 2. Discrete Play
    UIButton *playBtn = [self createRemoteButtonWithTitle:@"▶" frame:CGRectMake(x0_4 + btnW4 + gap4, r2Y, btnW4, btnH)];
    playBtn.titleLabel.font = [UIFont boldSystemFontOfSize:isTall ? 18.0 : 15.0];
    [playBtn addTarget:self action:@selector(discretePlayTapped) forControlEvents:UIControlEventTouchUpInside];
    [self.playbackPanel addSubview:playBtn];
    
    // 3. Discrete Pause
    UIButton *pauseBtn = [self createRemoteButtonWithTitle:@"❚❚" frame:CGRectMake(x0_4 + (btnW4 + gap4) * 2, r2Y, btnW4, btnH)];
    pauseBtn.titleLabel.font = [UIFont boldSystemFontOfSize:isTall ? 15.0 : 13.0];
    [pauseBtn addTarget:self action:@selector(discretePauseTapped) forControlEvents:UIControlEventTouchUpInside];
    [self.playbackPanel addSubview:pauseBtn];
    
    // 4. Skip Forward 10s (Long press for Fast Forward)
    UIButton *skipFwdBtn = [self createRemoteButtonWithTitle:@"+10s" frame:CGRectMake(x0_4 + (btnW4 + gap4) * 3, r2Y, btnW4, btnH)];
    skipFwdBtn.titleLabel.font = [UIFont boldSystemFontOfSize:isTall ? 13.0 : 11.5];
    [skipFwdBtn addTarget:self action:@selector(skipForwardTapped) forControlEvents:UIControlEventTouchUpInside];
    UILongPressGestureRecognizer *ffHold = [[UILongPressGestureRecognizer alloc] initWithTarget:self action:@selector(skipForwardLongPressed:)];
    ffHold.minimumPressDuration = 0.45;
    [skipFwdBtn addGestureRecognizer:ffHold];
    [self.playbackPanel addSubview:skipFwdBtn];
    
    // Row 3: 3 buttons (⏮ | CC | ⏭)
    CGFloat r3Y = r2Y + btnH + rowGap;
    CGFloat btnW3 = 88.0;
    CGFloat gap3 = 8.0;
    CGFloat x0_3 = 20.0;
    
    UIButton *prevBtn = [self createRemoteButtonWithTitle:@"⏮" frame:CGRectMake(x0_3, r3Y, btnW3, btnH)];
    prevBtn.titleLabel.font = [UIFont boldSystemFontOfSize:isTall ? 17.0 : 14.0];
    [prevBtn addTarget:self action:@selector(prevTrackTapped) forControlEvents:UIControlEventTouchUpInside];
    [self.playbackPanel addSubview:prevBtn];
    
    UIButton *ccBtn = [self createRemoteButtonWithTitle:@"CC" frame:CGRectMake(x0_3 + btnW3 + gap3, r3Y, btnW3, btnH)];
    ccBtn.titleLabel.font = [UIFont boldSystemFontOfSize:isTall ? 14.0 : 12.0];
    [ccBtn addTarget:self action:@selector(subtitlesTapped) forControlEvents:UIControlEventTouchUpInside];
    [self.playbackPanel addSubview:ccBtn];
    
    UIButton *nextBtn = [self createRemoteButtonWithTitle:@"⏭" frame:CGRectMake(x0_3 + (btnW3 + gap3) * 2, r3Y, btnW3, btnH)];
    nextBtn.titleLabel.font = [UIFont boldSystemFontOfSize:isTall ? 17.0 : 14.0];
    [nextBtn addTarget:self action:@selector(nextTrackTapped) forControlEvents:UIControlEventTouchUpInside];
    [self.playbackPanel addSubview:nextBtn];
    
    // Row 4: 3 buttons (− | MUTE | +)
    CGFloat r4Y = r3Y + btnH + rowGap;
    UIButton *volD = [self createRemoteButtonWithTitle:@"−" frame:CGRectMake(x0_3, r4Y, btnW3, btnH)];
    volD.titleLabel.font = [UIFont boldSystemFontOfSize:isTall ? 24.0 : 20.0];
    [volD addTarget:self action:@selector(volDownTapped) forControlEvents:UIControlEventTouchUpInside];
    [self.playbackPanel addSubview:volD];
    
    UIButton *muteB = [self createRemoteButtonWithTitle:@"MUTE" frame:CGRectMake(x0_3 + btnW3 + gap3, r4Y, btnW3, btnH)];
    muteB.titleLabel.font = [UIFont boldSystemFontOfSize:isTall ? 13.0 : 11.0];
    [muteB addTarget:self action:@selector(muteTapped) forControlEvents:UIControlEventTouchUpInside];
    [self.playbackPanel addSubview:muteB];
    
    UIButton *volU = [self createRemoteButtonWithTitle:@"+" frame:CGRectMake(x0_3 + (btnW3 + gap3) * 2, r4Y, btnW3, btnH)];
    volU.titleLabel.font = [UIFont boldSystemFontOfSize:isTall ? 24.0 : 20.0];
    [volU addTarget:self action:@selector(volUpTapped) forControlEvents:UIControlEventTouchUpInside];
    [self.playbackPanel addSubview:volU];
}

- (void)modeSwitcherChanged:(UISegmentedControl *)sender {
    [self playClickSound];
    [self setRemoteLayoutMode:sender.selectedSegmentIndex animated:YES];
}

- (void)setRemoteLayoutMode:(NSInteger)mode animated:(BOOL)animated {
    if (self.currentLayoutMode == mode && self.modeSwitcher.selectedSegmentIndex == mode && self.navigationPanel.superview) {
        return;
    }
    self.currentLayoutMode = mode;
    if (self.modeSwitcher.selectedSegmentIndex != mode) {
        self.modeSwitcher.selectedSegmentIndex = mode;
    }
    
    UIView *toShow = (mode == 1) ? self.playbackPanel : self.navigationPanel;
    UIView *toHide = (mode == 1) ? self.navigationPanel : self.playbackPanel;
    
    if (animated) {
        toShow.alpha = 0.0;
        toShow.hidden = NO;
        [UIView animateWithDuration:0.25 delay:0 options:UIViewAnimationOptionCurveEaseInOut animations:^{
            toHide.alpha = 0.0;
            toShow.alpha = 1.0;
        } completion:^(BOOL finished) {
            toHide.hidden = YES;
        }];
    } else {
        toShow.alpha = 1.0;
        toShow.hidden = NO;
        toHide.alpha = 0.0;
        toHide.hidden = YES;
    }
}

- (BOOL)isStreamingApp:(NSString *)bundleID {
    if (!bundleID || [bundleID length] == 0) return NO;
    NSString *b = [bundleID lowercaseString];
    if ([b rangeOfString:@"youtube"].location != NSNotFound ||
        [b rangeOfString:@"netflix"].location != NSNotFound ||
        [b rangeOfString:@"tvwatchlist"].location != NSNotFound ||
        [b rangeOfString:@"tvmusic"].location != NSNotFound ||
        [b rangeOfString:@"music"].location != NSNotFound ||
        [b rangeOfString:@"podcast"].location != NSNotFound ||
        [b rangeOfString:@"digi"].location != NSNotFound ||
        [b rangeOfString:@"plex"].location != NSNotFound ||
        [b rangeOfString:@"infuse"].location != NSNotFound ||
        [b rangeOfString:@"disney"].location != NSNotFound ||
        [b rangeOfString:@"amazon"].location != NSNotFound ||
        [b rangeOfString:@"aiv"].location != NSNotFound ||
        [b rangeOfString:@"hbo"].location != NSNotFound ||
        [b rangeOfString:@"max"].location != NSNotFound ||
        [b rangeOfString:@"twitch"].location != NSNotFound ||
        [b rangeOfString:@"spotify"].location != NSNotFound ||
        [b rangeOfString:@"vlc"].location != NSNotFound ||
        [b rangeOfString:@"media"].location != NSNotFound) {
        return YES;
    }
    return NO;
}

- (void)checkAndAutoSwitchLayoutForApp:(NSString *)bundleID isPlaying:(BOOL)isPlaying {
    BOOL isStream = [self isStreamingApp:bundleID] || (isPlaying && self.currentNowPlayingTitle.length > 0);
    NSInteger targetMode = isStream ? 1 : 0;
    if (self.currentLayoutMode != targetMode) {
        [self setRemoteLayoutMode:targetMode animated:YES];
    }
}

- (UIButton *)createRemoteButtonWithTitle:(NSString *)title frame:(CGRect)frame {
    UIButton *btn = [UIButton buttonWithType:UIButtonTypeCustom];
    btn.frame = frame;
    [btn setTitle:title forState:UIControlStateNormal];
    [btn setTitleColor:[UIColor colorWithWhite:0.92 alpha:1.0] forState:UIControlStateNormal];
    [btn setTitleColor:[UIColor whiteColor] forState:UIControlStateHighlighted];
    btn.titleLabel.font = [UIFont boldSystemFontOfSize:14];
    btn.backgroundColor = [UIColor colorWithWhite:0.16 alpha:0.92];
    btn.layer.cornerRadius = 10.0;
    btn.layer.borderColor = [UIColor colorWithWhite:0.28 alpha:0.5].CGColor;
    btn.layer.borderWidth = 1.0;
    btn.layer.masksToBounds = YES;
    
    [btn addTarget:self action:@selector(buttonTouchDown:) forControlEvents:UIControlEventTouchDown];
    [btn addTarget:self action:@selector(buttonTouchUp:) forControlEvents:UIControlEventTouchUpInside | UIControlEventTouchUpOutside];
    return btn;
}

- (void)buttonTouchDown:(UIButton *)btn {
    [UIView animateWithDuration:0.06 animations:^{
        btn.transform = CGAffineTransformMakeScale(0.95, 0.95);
        btn.backgroundColor = [UIColor colorWithWhite:0.28 alpha:1.0];
    }];
}

- (void)buttonTouchUp:(UIButton *)btn {
    [UIView animateWithDuration:0.08 animations:^{
        btn.transform = CGAffineTransformIdentity;
        btn.backgroundColor = [UIColor colorWithWhite:0.16 alpha:0.92];
    }];
}

#pragma mark - Actions & Sound

- (void)playHapticFeedback {
    Class feedbackClass = NSClassFromString(@"UIImpactFeedbackGenerator");
    if (feedbackClass) {
        id gen = ((id (*)(id, SEL, NSInteger))objc_msgSend)([feedbackClass alloc], sel_registerName("initWithStyle:"), 0);
        if (gen) {
            ((void (*)(id, SEL))objc_msgSend)(gen, sel_registerName("prepare"));
            ((void (*)(id, SEL))objc_msgSend)(gen, sel_registerName("impactOccurred"));
        }
    }
    // AudioServices 1519 is Peek / short tactile vibration tick on iOS
    // Safely no-op on devices without vibration motor (e.g. iPod touch)
    AudioServicesPlaySystemSound(1519);
}

- (void)playClickSound {
    // 1104 = Standard iOS keyboard/UI click sound
    AudioServicesPlaySystemSound(1104);
    [self playHapticFeedback];
}

- (void)keyboardTapped {
    [self playClickSound];
    UIAlertView *alert = [[UIAlertView alloc] initWithTitle:@"Apple TV Keyboard"
                                                    message:@"Enter text to type on Apple TV:"
                                                   delegate:self
                                          cancelButtonTitle:@"Cancel"
                                          otherButtonTitles:@"Send", nil];
    alert.alertViewStyle = UIAlertViewStylePlainTextInput;
    UITextField *tf = [alert textFieldAtIndex:0];
    tf.placeholder = @"Search movies, apps, YouTube...";
    tf.autocorrectionType = UITextAutocorrectionTypeNo;
    tf.autocapitalizationType = UITextAutocapitalizationTypeNone;
    alert.tag = 2001;
    [alert show];
}

- (void)textInputNotificationReceived:(NSNotification *)note {
    [self keyboardTapped];
}

- (void)alertView:(UIAlertView *)alertView clickedButtonAtIndex:(NSInteger)buttonIndex {
    if (alertView.tag == 2001 && buttonIndex == 1) {
        UITextField *tf = [alertView textFieldAtIndex:0];
        NSString *text = tf.text;
        if (text && [text length] > 0) {
            [self sendKeyboardText:text];
        }
    }
}

- (void)sendKeyboardText:(NSString *)text {
    [self playClickSound];
    NSString *mode = [[NSUserDefaults standardUserDefaults] stringForKey:@"ATRConnectionMode"];
    self.marqueeLabel.text = [NSString stringWithFormat:@"Sending \"%@\"...", text];
    if ([mode isEqualToString:@"Bridge"]) {
        [[ATRClient sharedClient] sendTextInput:text completion:^(BOOL success, NSString *error) {
            if (success) {
                self.marqueeLabel.text = [NSString stringWithFormat:@"Typed \"%@\"", text];
            } else {
                self.marqueeLabel.text = @"Focus search on TV first!";
            }
        }];
    } else {
        [[ATRCompanionClient sharedClient] sendTextInput:text completion:^(BOOL success, NSString *error) {
            if (success) {
                self.marqueeLabel.text = [NSString stringWithFormat:@"Typed \"%@\"", text];
            } else {
                self.marqueeLabel.text = @"Focus search on TV first!";
            }
        }];
    }
}

#pragma mark - Lock Screen & Control Center Controls

- (void)setupRemoteCommandCenter {
    Class commandCenterClass = NSClassFromString(@"MPRemoteCommandCenter");
    if (!commandCenterClass) return;
    
    id center = ((id (*)(id, SEL))objc_msgSend)(commandCenterClass, sel_registerName("sharedCommandCenter"));
    if (!center) return;
    
    // Play command
    id playCmd = ((id (*)(id, SEL))objc_msgSend)(center, sel_registerName("playCommand"));
    if (playCmd) {
        ((void (*)(id, SEL, BOOL))objc_msgSend)(playCmd, sel_registerName("setEnabled:"), YES);
        ((void (*)(id, SEL, id, SEL))objc_msgSend)(playCmd, sel_registerName("addTarget:action:"), self, @selector(handleRemoteCommandPlay));
    }
    
    // Pause command
    id pauseCmd = ((id (*)(id, SEL))objc_msgSend)(center, sel_registerName("pauseCommand"));
    if (pauseCmd) {
        ((void (*)(id, SEL, BOOL))objc_msgSend)(pauseCmd, sel_registerName("setEnabled:"), YES);
        ((void (*)(id, SEL, id, SEL))objc_msgSend)(pauseCmd, sel_registerName("addTarget:action:"), self, @selector(handleRemoteCommandPause));
    }
    
    // Toggle play/pause
    id toggleCmd = ((id (*)(id, SEL))objc_msgSend)(center, sel_registerName("togglePlayPauseCommand"));
    if (toggleCmd) {
        ((void (*)(id, SEL, BOOL))objc_msgSend)(toggleCmd, sel_registerName("setEnabled:"), YES);
        ((void (*)(id, SEL, id, SEL))objc_msgSend)(toggleCmd, sel_registerName("addTarget:action:"), self, @selector(handleRemoteCommandToggle));
    }
    
    // Next / Previous Track
    id nextCmd = ((id (*)(id, SEL))objc_msgSend)(center, sel_registerName("nextTrackCommand"));
    if (nextCmd) {
        ((void (*)(id, SEL, BOOL))objc_msgSend)(nextCmd, sel_registerName("setEnabled:"), YES);
        ((void (*)(id, SEL, id, SEL))objc_msgSend)(nextCmd, sel_registerName("addTarget:action:"), self, @selector(handleRemoteCommandNext));
    }
    
    id prevCmd = ((id (*)(id, SEL))objc_msgSend)(center, sel_registerName("previousTrackCommand"));
    if (prevCmd) {
        ((void (*)(id, SEL, BOOL))objc_msgSend)(prevCmd, sel_registerName("setEnabled:"), YES);
        ((void (*)(id, SEL, id, SEL))objc_msgSend)(prevCmd, sel_registerName("addTarget:action:"), self, @selector(handleRemoteCommandPrev));
    }
}

- (NSInteger)handleRemoteCommandPlay {
    [self playClickSound];
    [self sendCommand:@"play"];
    return 0; // MPRemoteCommandHandlerStatusSuccess
}

- (NSInteger)handleRemoteCommandPause {
    [self playClickSound];
    [self sendCommand:@"pause"];
    return 0;
}

- (NSInteger)handleRemoteCommandToggle {
    [self playClickSound];
    [self sendCommand:@"play_pause"];
    return 0;
}

- (NSInteger)handleRemoteCommandNext {
    [self playClickSound];
    [self sendCommand:@"right"];
    return 0;
}

- (NSInteger)handleRemoteCommandPrev {
    [self playClickSound];
    [self sendCommand:@"left"];
    return 0;
}

- (void)updateSystemNowPlayingInfoTitle:(NSString *)title artist:(NSString *)artist artwork:(UIImage *)artwork {
    Class infoCenterClass = NSClassFromString(@"MPNowPlayingInfoCenter");
    if (!infoCenterClass) return;
    
    id infoCenter = ((id (*)(id, SEL))objc_msgSend)(infoCenterClass, sel_registerName("defaultCenter"));
    if (!infoCenter) return;
    
    if (title && [title length] > 0) {
        NSMutableDictionary *dict = [NSMutableDictionary dictionary];
        [dict setObject:title forKey:@"title"];
        if (artist && [artist length] > 0) {
            [dict setObject:artist forKey:@"artist"];
        }
        
        Class mpArtworkClass = NSClassFromString(@"MPMediaItemArtwork");
        if (mpArtworkClass && artwork) {
            id art = ((id (*)(id, SEL, id))objc_msgSend)([mpArtworkClass alloc], sel_registerName("initWithImage:"), artwork);
            if (art) {
                [dict setObject:art forKey:@"artwork"];
            }
        }
        ((void (*)(id, SEL, id))objc_msgSend)(infoCenter, sel_registerName("setNowPlayingInfo:"), dict);
    } else {
        ((void (*)(id, SEL, id))objc_msgSend)(infoCenter, sel_registerName("setNowPlayingInfo:"), nil);
    }
}

- (void)gearTapped {
    [self playClickSound];
    ATRSettingsViewController *svc = [[ATRSettingsViewController alloc] init];
    svc.delegate = self;
    [self presentModalViewController:svc animated:YES];
}

- (void)settingsDidDismiss {
    [self dismissModalViewControllerAnimated:YES];
    NSString *mode = [[NSUserDefaults standardUserDefaults] stringForKey:@"ATRConnectionMode"];
    if ([mode isEqualToString:@"Bridge"]) {
        [self refreshConnection];
    } else {
        if ([[ATRCompanionClient sharedClient] isPaired]) {
            [[ATRCompanionClient sharedClient] disconnect];
            [[ATRCompanionClient sharedClient] connect];
        }
        [self updateStatusUI];
    }
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

- (void)searchTapped {
    [self playClickSound];
    self.marqueeLabel.text = @"Opening Apple TV Search...";
    [self sendCommand:@"search"];
    dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(1.0 * NSEC_PER_SEC)), dispatch_get_main_queue(), ^{
        [self keyboardTapped];
    });
}

- (void)controlCenterTapped {
    [self playClickSound];
    self.marqueeLabel.text = @"Opening Control Center...";
    [self sendCommand:@"control"];
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

- (void)skipBackwardTapped {
    [self playClickSound];
    self.marqueeLabel.text = @"Skip −10s";
    [self sendCommand:@"skip_backward"];
}

- (void)skipBackwardLongPressed:(UILongPressGestureRecognizer *)gesture {
    if (gesture.state == UIGestureRecognizerStateBegan) {
        [self playClickSound];
        self.marqueeLabel.text = @"Rewinding...";
        [self sendCommand:@"skip_backward_15"];
    }
}

- (void)skipForwardTapped {
    [self playClickSound];
    self.marqueeLabel.text = @"Skip +10s";
    [self sendCommand:@"skip_forward"];
}

- (void)skipForwardLongPressed:(UILongPressGestureRecognizer *)gesture {
    if (gesture.state == UIGestureRecognizerStateBegan) {
        [self playClickSound];
        self.marqueeLabel.text = @"Fast Forwarding...";
        [self sendCommand:@"skip_forward_15"];
    }
}

- (void)discretePlayTapped {
    [self playClickSound];
    self.marqueeLabel.text = @"Play";
    [self sendCommand:@"play"];
    self.isPlaying = YES;
    [self updateStatusUI];
}

- (void)discretePauseTapped {
    [self playClickSound];
    self.marqueeLabel.text = @"Pause";
    [self sendCommand:@"pause"];
    self.isPlaying = NO;
    [self updateStatusUI];
}

- (void)prevTrackTapped {
    [self playClickSound];
    self.marqueeLabel.text = @"Previous Track";
    [self sendCommand:@"previous_track"];
}

- (void)nextTrackTapped {
    [self playClickSound];
    self.marqueeLabel.text = @"Next Track";
    [self sendCommand:@"next_track"];
}

- (void)subtitlesTapped {
    [self playClickSound];
    self.marqueeLabel.text = @"Subtitles Toggled";
    [self sendCommand:@"cc"];
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
        ATRCompanionClient *comp = [ATRCompanionClient sharedClient];
        if ([comp isPaired] && !comp.isConnected) {
            [comp connect];
        }
        [self updateStatusUI];
    }
}

- (void)updateStatusUI {
    NSString *mode = [[NSUserDefaults standardUserDefaults] stringForKey:@"ATRConnectionMode"];
    if ([mode isEqualToString:@"Bridge"]) {
        ATRClient *client = [ATRClient sharedClient];
        self.titleLabel.text = client.deviceName.length > 0 ? client.deviceName : @"Apple TV 4K";
        
        if (client.isConnected && client.isPaired) {
            self.ledDot.backgroundColor = [UIColor colorWithRed:0.20 green:0.85 blue:0.35 alpha:1.0]; // Bright Green
        } else if (client.isPaired) {
            self.ledDot.backgroundColor = [UIColor colorWithRed:0.95 green:0.75 blue:0.20 alpha:1.0]; // Amber
        } else {
            self.ledDot.backgroundColor = [UIColor colorWithRed:0.95 green:0.25 blue:0.25 alpha:1.0]; // Red
        }
    } else {
        // Direct Companion Mode
        ATRCompanionClient *comp = [ATRCompanionClient sharedClient];
        self.titleLabel.text = @"Apple TV 4K";
        if (comp.isEncrypted) {
            self.ledDot.backgroundColor = [UIColor colorWithRed:0.20 green:0.85 blue:0.35 alpha:1.0]; // Bright Green!
            if (!self.currentActiveAppName) {
                self.marqueeLabel.text = @"Apple TV 4K • Connected";
            }
        } else if (comp.isConnected) {
            self.ledDot.backgroundColor = [UIColor colorWithRed:0.95 green:0.75 blue:0.20 alpha:1.0]; // Amber
            if (!self.currentActiveAppName) {
                self.marqueeLabel.text = @"Connecting to Apple TV...";
            }
        } else if (comp.isPaired) {
            self.ledDot.backgroundColor = [UIColor colorWithWhite:0.55 alpha:1.0]; // Paired
            if (!self.currentActiveAppName) {
                self.marqueeLabel.text = @"Paired (Connecting...)";
            }
        } else {
            self.ledDot.backgroundColor = [UIColor colorWithRed:0.95 green:0.25 blue:0.25 alpha:1.0]; // Red
            if (!self.currentActiveAppName) {
                self.marqueeLabel.text = @"Tap ⚙ to Pair";
            }
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
    
    [self updateSystemNowPlayingInfoTitle:name artist:isPlaying ? @"Playing on Apple TV" : @"Paused" artwork:self.currentArtworkImage];
    [self checkAndAutoSwitchLayoutForApp:bundleID isPlaying:isPlaying];
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
    [self updateSystemNowPlayingInfoTitle:nil artist:nil artwork:nil];
    [self setRemoteLayoutMode:0 animated:YES];
}

- (void)applyNowPlayingTitle:(NSString *)title artist:(NSString *)artist {
    if (title && [title length] > 0) {
        [self applyActiveAppNamed:title bundleID:nil isPlaying:YES];
        if (artist && [artist length] > 0) {
            self.marqueeLabel.text = [NSString stringWithFormat:@"▶ %@ • %@", title, artist];
        }
        [self updateSystemNowPlayingInfoTitle:title artist:artist artwork:self.currentArtworkImage];
        [self setRemoteLayoutMode:1 animated:YES];
    } else if (!self.currentActiveAppName) {
        self.currentArtworkImage = nil;
        self.nowPlayingThumbView.hidden = YES;
        self.marqueeLabel.frame = CGRectMake(12, 4, 256, 20);
        self.marqueeLabel.textAlignment = UITextAlignmentCenter;
        [self updateStatusUI];
        [self updateSystemNowPlayingInfoTitle:nil artist:nil artwork:nil];
        [self setRemoteLayoutMode:0 animated:YES];
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
    CGFloat screenH = self.view.bounds.size.height;
    CGFloat cardY = (screenH > 500.0) ? 110.0 : 80.0;
    
    UIView *card = nil;
    UIView *cardContainer = nil;
    Class blurClass = NSClassFromString(@"UIBlurEffect");
    Class effectViewClass = NSClassFromString(@"UIVisualEffectView");
    if (blurClass && effectViewClass) {
        // iOS 8+ GPU-Accelerated Frosted Glass Blur
        id blur = ((id (*)(id, SEL, NSInteger))objc_msgSend)(blurClass, sel_registerName("effectWithStyle:"), 1); // Dark
        id effectView = ((id (*)(id, SEL, id))objc_msgSend)([effectViewClass alloc], sel_registerName("initWithEffect:"), blur);
        card = (UIView *)effectView;
        card.frame = CGRectMake(30, cardY, 260, 310);
        card.layer.cornerRadius = 16.0;
        card.layer.masksToBounds = YES;
        card.layer.borderColor = [UIColor colorWithWhite:0.4 alpha:0.6].CGColor;
        card.layer.borderWidth = 1.0;
        cardContainer = ((id (*)(id, SEL))objc_msgSend)(effectView, sel_registerName("contentView"));
    } else {
        // iOS 5-7 Fallback
        card = [[UIView alloc] initWithFrame:CGRectMake(30, cardY, 260, 310)];
        card.backgroundColor = [UIColor colorWithWhite:0.12 alpha:0.98];
        card.layer.cornerRadius = 14.0;
        card.layer.borderColor = [UIColor colorWithWhite:0.30 alpha:1.0].CGColor;
        card.layer.borderWidth = 1.0;
        cardContainer = card;
    }
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
    [cardContainer addSubview:largeArt];
    
    // Title Label
    UILabel *titleLbl = [[UILabel alloc] initWithFrame:CGRectMake(16, 180, 228, 28)];
    titleLbl.text = self.currentActiveAppName ?: @"Apple TV 4K";
    titleLbl.textColor = [UIColor whiteColor];
    titleLbl.font = [UIFont boldSystemFontOfSize:18];
    titleLbl.textAlignment = UITextAlignmentCenter;
    titleLbl.adjustsFontSizeToFitWidth = YES;
    titleLbl.backgroundColor = [UIColor clearColor];
    [cardContainer addSubview:titleLbl];
    
    // Status Label
    UILabel *artistLbl = [[UILabel alloc] initWithFrame:CGRectMake(16, 208, 228, 20)];
    artistLbl.text = self.isPlaying ? @"Playing on Apple TV 4K" : @"Paused on Apple TV 4K";
    artistLbl.textColor = [UIColor colorWithWhite:0.65 alpha:1.0];
    artistLbl.font = [UIFont systemFontOfSize:13];
    artistLbl.textAlignment = UITextAlignmentCenter;
    artistLbl.adjustsFontSizeToFitWidth = YES;
    artistLbl.backgroundColor = [UIColor clearColor];
    [cardContainer addSubview:artistLbl];
    
    // Switch App button
    UIButton *switchBtn = [UIButton buttonWithType:UIButtonTypeCustom];
    switchBtn.frame = CGRectMake(18, 248, 106, 36);
    switchBtn.backgroundColor = [UIColor colorWithWhite:0.24 alpha:1.0];
    switchBtn.layer.cornerRadius = 8.0;
    switchBtn.layer.borderColor = [UIColor colorWithWhite:0.35 alpha:0.6].CGColor;
    switchBtn.layer.borderWidth = 1.0;
    [switchBtn setTitle:@"Apps" forState:UIControlStateNormal];
    [switchBtn setTitleColor:[UIColor colorWithWhite:0.92 alpha:1.0] forState:UIControlStateNormal];
    switchBtn.titleLabel.font = [UIFont boldSystemFontOfSize:14];
    [switchBtn addTarget:self action:@selector(popupSwitchAppTapped) forControlEvents:UIControlEventTouchUpInside];
    [cardContainer addSubview:switchBtn];
    
    // Close button
    UIButton *closeBtn = [UIButton buttonWithType:UIButtonTypeCustom];
    closeBtn.frame = CGRectMake(136, 248, 106, 36);
    closeBtn.backgroundColor = [UIColor colorWithWhite:0.18 alpha:1.0];
    closeBtn.layer.cornerRadius = 8.0;
    closeBtn.layer.borderColor = [UIColor colorWithWhite:0.30 alpha:0.6].CGColor;
    closeBtn.layer.borderWidth = 1.0;
    [closeBtn setTitle:@"Close" forState:UIControlStateNormal];
    [closeBtn setTitleColor:[UIColor colorWithWhite:0.92 alpha:1.0] forState:UIControlStateNormal];
    closeBtn.titleLabel.font = [UIFont boldSystemFontOfSize:14];
    [closeBtn addTarget:self action:@selector(dismissNowPlayingPopup) forControlEvents:UIControlEventTouchUpInside];
    [cardContainer addSubview:closeBtn];
    
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
