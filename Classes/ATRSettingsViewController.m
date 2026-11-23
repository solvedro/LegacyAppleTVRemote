#import "ATRSettingsViewController.h"
#import "ATRClient.h"
#import "Companion/ATRCompanionClient.h"
#import "ATRDeviceDiscovery.h"
#import <QuartzCore/QuartzCore.h>

static NSString * const kATRConnectionModeKey = @"ATRConnectionMode"; // @"Direct" or @"Bridge"

@interface ATRSettingsViewController () <UITextFieldDelegate, UIAlertViewDelegate, ATRDeviceDiscoveryDelegate>

@property (nonatomic, strong) UISegmentedControl *modeControl;
@property (nonatomic, strong) UILabel *addressPromptLabel;
@property (nonatomic, strong) UITextField *serverField;
@property (nonatomic, strong) UIButton *bonjourButton;
@property (nonatomic, strong) UILabel *statusLabel;
@property (nonatomic, strong) UIButton *testButton;
@property (nonatomic, strong) UIButton *pairButton;
@property (nonatomic, strong) UIButton *importButton;
@property (nonatomic, strong) UIActivityIndicatorView *spinner;
@property (nonatomic, strong) UILabel *footerLabel;

@end

@implementation ATRSettingsViewController

- (void)viewDidLoad {
    [super viewDidLoad];
    
    self.view.backgroundColor = [UIColor colorWithRed:0.12 green:0.13 blue:0.15 alpha:1.0];
    
    // Top Bar
    UIView *topBar = [[UIView alloc] initWithFrame:CGRectMake(0, 0, 320, 44)];
    topBar.backgroundColor = [UIColor colorWithWhite:0.08 alpha:1.0];
    [self.view addSubview:topBar];
    
    UILabel *titleLabel = [[UILabel alloc] initWithFrame:CGRectMake(60, 10, 200, 24)];
    titleLabel.text = @"Remote Settings";
    titleLabel.textColor = [UIColor whiteColor];
    titleLabel.font = [UIFont boldSystemFontOfSize:17];
    titleLabel.textAlignment = UITextAlignmentCenter;
    titleLabel.backgroundColor = [UIColor clearColor];
    [topBar addSubview:titleLabel];
    
    UIButton *doneBtn = [UIButton buttonWithType:UIButtonTypeCustom];
    doneBtn.frame = CGRectMake(320 - 70, 7, 60, 30);
    [doneBtn setTitle:@"Done" forState:UIControlStateNormal];
    [doneBtn setTitleColor:[UIColor colorWithWhite:0.92 alpha:1.0] forState:UIControlStateNormal];
    doneBtn.titleLabel.font = [UIFont boldSystemFontOfSize:14];
    [doneBtn addTarget:self action:@selector(doneTapped) forControlEvents:UIControlEventTouchUpInside];
    [topBar addSubview:doneBtn];
    
    // Mode Switcher
    NSArray *modes = @[@"Direct (Standalone)", @"Bridge Relay"];
    self.modeControl = [[UISegmentedControl alloc] initWithItems:modes];
    self.modeControl.frame = CGRectMake(20, 52, 280, 32);
    self.modeControl.segmentedControlStyle = UISegmentedControlStyleBar;
    
    NSString *currMode = [[NSUserDefaults standardUserDefaults] stringForKey:kATRConnectionModeKey];
    if (!currMode) currMode = @"Direct";
    self.modeControl.selectedSegmentIndex = [currMode isEqualToString:@"Bridge"] ? 1 : 0;
    [self.modeControl addTarget:self action:@selector(modeChanged:) forControlEvents:UIControlEventValueChanged];
    [self.view addSubview:self.modeControl];
    
    // Address Prompt Label
    self.addressPromptLabel = [[UILabel alloc] initWithFrame:CGRectMake(20, 92, 280, 20)];
    self.addressPromptLabel.textColor = [UIColor colorWithWhite:0.8 alpha:1.0];
    self.addressPromptLabel.font = [UIFont systemFontOfSize:13];
    self.addressPromptLabel.backgroundColor = [UIColor clearColor];
    [self.view addSubview:self.addressPromptLabel];
    
    // Server Text Field
    self.serverField = [[UITextField alloc] initWithFrame:CGRectMake(20, 114, 280, 36)];
    self.serverField.backgroundColor = [UIColor colorWithWhite:0.2 alpha:1.0];
    self.serverField.textColor = [UIColor whiteColor];
    self.serverField.font = [UIFont systemFontOfSize:14];
    self.serverField.autocorrectionType = UITextAutocorrectionTypeNo;
    self.serverField.autocapitalizationType = UITextAutocapitalizationTypeNone;
    self.serverField.keyboardType = UIKeyboardTypeNumbersAndPunctuation;
    self.serverField.layer.cornerRadius = 6.0;
    self.serverField.layer.borderColor = [UIColor colorWithWhite:0.35 alpha:1.0].CGColor;
    self.serverField.layer.borderWidth = 1.0;
    self.serverField.delegate = self;
    
    UIView *padView = [[UIView alloc] initWithFrame:CGRectMake(0, 0, 8, 36)];
    self.serverField.leftView = padView;
    self.serverField.leftViewMode = UITextFieldViewModeAlways;
    [self.view addSubview:self.serverField];
    
    // Auto-Discovery Bonjour button
    self.bonjourButton = [self createStyledButtonWithTitle:@"🔍 Auto-Discover Apple TVs..." frame:CGRectMake(20, 154, 280, 32) color:[UIColor colorWithWhite:0.18 alpha:1.0]];
    self.bonjourButton.titleLabel.font = [UIFont systemFontOfSize:13];
    [self.bonjourButton addTarget:self action:@selector(bonjourTapped) forControlEvents:UIControlEventTouchUpInside];
    [self.view addSubview:self.bonjourButton];
    
    // Status text
    self.statusLabel = [[UILabel alloc] initWithFrame:CGRectMake(20, 190, 280, 26)];
    self.statusLabel.numberOfLines = 2;
    self.statusLabel.textColor = [UIColor colorWithWhite:0.7 alpha:1.0];
    self.statusLabel.font = [UIFont systemFontOfSize:11];
    self.statusLabel.textAlignment = UITextAlignmentCenter;
    self.statusLabel.backgroundColor = [UIColor clearColor];
    [self.view addSubview:self.statusLabel];
    
    // Test Connection Button
    self.testButton = [self createStyledButtonWithTitle:@"Test Connection" frame:CGRectMake(20, 218, 280, 36) color:[UIColor colorWithWhite:0.22 alpha:1.0]];
    [self.testButton addTarget:self action:@selector(testTapped) forControlEvents:UIControlEventTouchUpInside];
    [self.view addSubview:self.testButton];
    
    // Pair Button
    self.pairButton = [self createStyledButtonWithTitle:@"Pair with Apple TV 4K" frame:CGRectMake(20, 258, 280, 36) color:[UIColor colorWithRed:0.20 green:0.55 blue:0.90 alpha:1.0]];
    [self.pairButton addTarget:self action:@selector(pairTapped) forControlEvents:UIControlEventTouchUpInside];
    [self.view addSubview:self.pairButton];
    
    // Import Button (Direct Mode)
    self.importButton = [self createStyledButtonWithTitle:@"Import Keys from Bridge" frame:CGRectMake(20, 298, 280, 36) color:[UIColor colorWithRed:0.25 green:0.40 blue:0.60 alpha:1.0]];
    [self.importButton addTarget:self action:@selector(importTapped) forControlEvents:UIControlEventTouchUpInside];
    [self.view addSubview:self.importButton];
    
    // Info footer
    self.footerLabel = [[UILabel alloc] initWithFrame:CGRectMake(20, 338, 280, 130)];
    self.footerLabel.numberOfLines = 7;
    self.footerLabel.textColor = [UIColor colorWithWhite:0.55 alpha:1.0];
    self.footerLabel.font = [UIFont systemFontOfSize:11];
    self.footerLabel.backgroundColor = [UIColor clearColor];
    [self.view addSubview:self.footerLabel];
    
    self.spinner = [[UIActivityIndicatorView alloc] initWithActivityIndicatorStyle:UIActivityIndicatorViewStyleWhite];
    self.spinner.center = CGPointMake(160, 213);
    self.spinner.hidesWhenStopped = YES;
    [self.view addSubview:self.spinner];
    
    [self updateUIForMode];
}

- (void)viewWillAppear:(BOOL)animated {
    [super viewWillAppear:animated];
    [ATRDeviceDiscovery sharedDiscovery].delegate = self;
    [[ATRDeviceDiscovery sharedDiscovery] startDiscovery];
}

- (void)viewWillDisappear:(BOOL)animated {
    [super viewWillDisappear:animated];
    [[ATRDeviceDiscovery sharedDiscovery] stopDiscovery];
}

- (void)bonjourTapped {
    NSArray *devs = [[ATRDeviceDiscovery sharedDiscovery] discoveredDevices];
    ATRDiscoveredDevice *selected = nil;
    for (ATRDiscoveredDevice *d in devs) {
        if ([d.name rangeOfString:@"Apple" options:NSCaseInsensitiveSearch].location != NSNotFound ||
            [d.name rangeOfString:@"Living Room" options:NSCaseInsensitiveSearch].location != NSNotFound ||
            [d.host isEqualToString:@"192.168.100.155"]) {
            selected = d;
            break;
        }
    }
    if (!selected && [devs count] > 0) {
        selected = [devs objectAtIndex:0];
    }
    
    if (selected) {
        self.serverField.text = selected.host;
        self.statusLabel.text = [NSString stringWithFormat:@"Selected: %@ (%@)", selected.name, selected.host];
        self.statusLabel.textColor = [UIColor colorWithRed:0.35 green:1.0 blue:0.5 alpha:1.0];
        [self testTapped];
    } else {
        self.serverField.text = @"192.168.100.155";
        self.statusLabel.text = @"Searching for Apple TV on Wi-Fi...";
        [[ATRDeviceDiscovery sharedDiscovery] startDiscovery];
    }
}

#pragma mark - ATRDeviceDiscoveryDelegate

- (void)deviceDiscovery:(ATRDeviceDiscovery *)discovery didFindDeviceNamed:(NSString *)name host:(NSString *)host port:(NSInteger)port {
    NSString *btnTitle = [NSString stringWithFormat:@"✨ Found: %@ (%@)", name, host];
    [self.bonjourButton setTitle:btnTitle forState:UIControlStateNormal];
    [self.bonjourButton setTitleColor:[UIColor colorWithRed:0.35 green:1.0 blue:0.5 alpha:1.0] forState:UIControlStateNormal];
    self.bonjourButton.layer.borderColor = [UIColor colorWithRed:0.35 green:1.0 blue:0.5 alpha:0.7].CGColor;
    
    if ([self.serverField.text length] == 0) {
        self.serverField.text = host;
    }
}

- (UIButton *)createStyledButtonWithTitle:(NSString *)title frame:(CGRect)frame color:(UIColor *)color {
    UIButton *btn = [UIButton buttonWithType:UIButtonTypeCustom];
    btn.frame = frame;
    [btn setTitle:title forState:UIControlStateNormal];
    [btn setTitleColor:[UIColor whiteColor] forState:UIControlStateNormal];
    [btn setTitleColor:[UIColor lightGrayColor] forState:UIControlStateHighlighted];
    btn.titleLabel.font = [UIFont boldSystemFontOfSize:14];
    btn.backgroundColor = color;
    btn.layer.cornerRadius = 6.0;
    btn.layer.borderColor = [UIColor colorWithWhite:0.4 alpha:0.5].CGColor;
    btn.layer.borderWidth = 1.0;
    return btn;
}

- (void)modeChanged:(UISegmentedControl *)sender {
    NSString *mode = (sender.selectedSegmentIndex == 0) ? @"Direct" : @"Bridge";
    [[NSUserDefaults standardUserDefaults] setObject:mode forKey:kATRConnectionModeKey];
    [[NSUserDefaults standardUserDefaults] synchronize];
    [self updateUIForMode];
}

- (void)updateUIForMode {
    BOOL isDirect = (self.modeControl.selectedSegmentIndex == 0);
    if (isDirect) {
        self.addressPromptLabel.text = @"Apple TV 4K LAN IP Address:";
        self.serverField.text = [ATRCompanionClient sharedClient].host ?: @"192.168.100.155";
        
        BOOL paired = [[ATRCompanionClient sharedClient] isPaired];
        self.statusLabel.text = paired ? @"Status: Paired (Standalone Direct)" : @"Status: Not Paired (Tap Pair below)";
        self.statusLabel.textColor = paired ? [UIColor colorWithRed:0.4 green:1.0 blue:0.5 alpha:1.0] : [UIColor colorWithWhite:0.7 alpha:1.0];
        
        [self.pairButton setTitle:@"Pair with Apple TV 4K" forState:UIControlStateNormal];
        self.importButton.hidden = NO;
        [self.importButton setTitle:@"Import Keys from Bridge" forState:UIControlStateNormal];
        
        self.footerLabel.text = @"Standalone Direct Mode:\n"
                                @"• iPhone connects directly to Apple TV port 50590.\n"
                                @"• Full on-device RFC 8439 ChaCha20-Poly1305 encryption.\n"
                                @"• Tap 'Pair with Apple TV 4K' or 'Import Keys from Bridge'.\n"
                                @"• Once paired, no PC or server is needed!";
    } else {
        self.addressPromptLabel.text = @"Bridge Server Address (Host:Port):";
        self.serverField.text = [ATRClient sharedClient].serverHost ?: @"192.168.100.94:8088";
        
        self.statusLabel.text = @"Status: Bridge Relay Mode";
        self.statusLabel.textColor = [UIColor colorWithWhite:0.7 alpha:1.0];
        
        [self.pairButton setTitle:@"Pair via Bridge (PIN)" forState:UIControlStateNormal];
        self.importButton.hidden = YES;
        
        self.footerLabel.text = @"Bridge Relay Mode:\n"
                                @"• Commands are relayed through atv_bridge.py.\n"
                                @"• Useful for testing or initial PIN pairing.";
    }
}

- (void)doneTapped {
    [self saveAddress];
    [self.serverField resignFirstResponder];
    if (self.modeControl.selectedSegmentIndex == 0) {
        if ([[ATRCompanionClient sharedClient] isPaired]) {
            [[ATRCompanionClient sharedClient] connect];
        }
    }
    if (self.delegate && [self.delegate respondsToSelector:@selector(settingsDidDismiss)]) {
        [self.delegate settingsDidDismiss];
    } else {
        [self dismissModalViewControllerAnimated:YES];
    }
}

- (void)saveAddress {
    NSString *text = [self.serverField.text stringByTrimmingCharactersInSet:[NSCharacterSet whitespaceAndNewlineCharacterSet]];
    if (text.length == 0) return;
    
    BOOL isDirect = (self.modeControl.selectedSegmentIndex == 0);
    if (isDirect) {
        // May contain host or host:port
        NSArray *p = [text componentsSeparatedByString:@":"];
        [ATRCompanionClient sharedClient].host = [p objectAtIndex:0];
        if ([p count] > 1) {
            [ATRCompanionClient sharedClient].port = [[p objectAtIndex:1] integerValue];
        } else {
            [ATRCompanionClient sharedClient].port = 50590;
        }
        [[NSUserDefaults standardUserDefaults] setObject:[ATRCompanionClient sharedClient].host forKey:@"ATRCompanionHost"];
        [[NSUserDefaults standardUserDefaults] setInteger:[ATRCompanionClient sharedClient].port forKey:@"ATRCompanionPort"];
        [[NSUserDefaults standardUserDefaults] synchronize];
    } else {
        [[ATRClient sharedClient] saveServerHost:text];
    }
}

- (void)testTapped {
    [self saveAddress];
    [self.serverField resignFirstResponder];
    [self.spinner startAnimating];
    
    BOOL isDirect = (self.modeControl.selectedSegmentIndex == 0);
    if (isDirect) {
        self.statusLabel.text = @"Testing Direct Apple TV connection...";
        self.statusLabel.textColor = [UIColor whiteColor];
        
        [[ATRCompanionClient sharedClient] connect];
        dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(2.0 * NSEC_PER_SEC)), dispatch_get_main_queue(), ^{
            [self.spinner stopAnimating];
            if ([ATRCompanionClient sharedClient].isConnected) {
                self.statusLabel.text = @"Direct TCP Socket: REACHABLE!\nApple TV 4K port 50590 is open.";
                self.statusLabel.textColor = [UIColor colorWithRed:0.4 green:1.0 blue:0.5 alpha:1.0];
            } else {
                self.statusLabel.text = @"Cannot reach Apple TV.\nCheck IP and Wi-Fi connection.";
                self.statusLabel.textColor = [UIColor colorWithRed:1.0 green:0.4 blue:0.4 alpha:1.0];
            }
        });
    } else {
        self.statusLabel.text = @"Checking bridge connection...";
        self.statusLabel.textColor = [UIColor whiteColor];
        
        [[ATRClient sharedClient] fetchStatusWithCompletion:^(BOOL connected, BOOL paired, NSString *device, NSString *error) {
            [self.spinner stopAnimating];
            if (error) {
                self.statusLabel.text = [NSString stringWithFormat:@"Cannot reach bridge:\n%@", error];
                self.statusLabel.textColor = [UIColor colorWithRed:1.0 green:0.4 blue:0.4 alpha:1.0];
            } else {
                NSString *pairStatus = paired ? @"Paired" : @"NOT paired yet";
                self.statusLabel.text = [NSString stringWithFormat:@"Bridge connected to '%@'!\nStatus: %@", device ?: @"Apple TV", pairStatus];
                self.statusLabel.textColor = [UIColor colorWithRed:0.4 green:1.0 blue:0.5 alpha:1.0];
            }
        }];
    }
}

- (void)importTapped {
    [self.spinner startAnimating];
    self.statusLabel.text = @"Importing credentials from Bridge...";
    self.statusLabel.textColor = [UIColor whiteColor];
    
    NSString *bridgeHost = [ATRClient sharedClient].serverHost ?: @"192.168.100.94:8088";
    NSString *bridgeUrl = [NSString stringWithFormat:@"http://%@", bridgeHost];
    
    [[ATRCompanionClient sharedClient] importCredentialsFromBridge:bridgeUrl completion:^(BOOL success, NSString *msg) {
        [self.spinner stopAnimating];
        if (success) {
            [ATRCompanionClient sharedClient].host = @"192.168.100.155";
            [ATRCompanionClient sharedClient].port = 50590;
            [[NSUserDefaults standardUserDefaults] setObject:@"192.168.100.155" forKey:@"ATRCompanionHost"];
            [[NSUserDefaults standardUserDefaults] setInteger:50590 forKey:@"ATRCompanionPort"];
            [[NSUserDefaults standardUserDefaults] synchronize];
            [[ATRCompanionClient sharedClient] connect];
            
            self.serverField.text = @"192.168.100.155";
            self.statusLabel.text = @"SUCCESS: Keys imported!\nApple TV 4K is connected directly.";
            self.statusLabel.textColor = [UIColor colorWithRed:0.4 green:1.0 blue:0.5 alpha:1.0];
        } else {
            self.statusLabel.text = [NSString stringWithFormat:@"Import failed:\n%@", msg];
            self.statusLabel.textColor = [UIColor colorWithRed:1.0 green:0.4 blue:0.4 alpha:1.0];
        }
    }];
}

- (void)pairTapped {
    [self saveAddress];
    [self.serverField resignFirstResponder];
    [self.spinner startAnimating];
    self.statusLabel.text = @"Starting pairing... Check TV screen!";
    self.statusLabel.textColor = [UIColor colorWithRed:1.0 green:0.85 blue:0.3 alpha:1.0];
    
    [[ATRClient sharedClient] startPairingWithCompletion:^(BOOL success, NSString *msg) {
        [self.spinner stopAnimating];
        if (success) {
            self.statusLabel.text = @"PIN is shown on your Apple TV!";
            
            UIAlertView *alert = [[UIAlertView alloc] initWithTitle:@"Apple TV 4K Pairing"
                                                            message:@"Enter the 4-digit code displayed on your TV screen:"
                                                           delegate:self
                                                  cancelButtonTitle:@"Cancel"
                                                  otherButtonTitles:@"Submit", nil];
            alert.alertViewStyle = UIAlertViewStylePlainTextInput;
            UITextField *pinField = [alert textFieldAtIndex:0];
            pinField.keyboardType = UIKeyboardTypeNumberPad;
            pinField.placeholder = @"1234";
            [alert show];
        } else {
            self.statusLabel.text = [NSString stringWithFormat:@"Pairing failed:\n%@", msg];
            self.statusLabel.textColor = [UIColor colorWithRed:1.0 green:0.4 blue:0.4 alpha:1.0];
        }
    }];
}

- (void)alertView:(UIAlertView *)alertView clickedButtonAtIndex:(NSInteger)buttonIndex {
    if (buttonIndex == 1) { // Submit
        UITextField *pinField = [alertView textFieldAtIndex:0];
        NSString *pin = pinField.text;
        if (pin.length > 0) {
            [self.spinner startAnimating];
            self.statusLabel.text = @"Verifying PIN with Apple TV...";
            
            [[ATRClient sharedClient] submitPIN:pin completion:^(BOOL success, NSString *msg) {
                [self.spinner stopAnimating];
                if (success) {
                    self.statusLabel.text = @"Pairing SUCCESS! Apple TV is ready.";
                    self.statusLabel.textColor = [UIColor colorWithRed:0.4 green:1.0 blue:0.5 alpha:1.0];
                    // Also trigger import if in Direct mode
                    [self importTapped];
                } else {
                    self.statusLabel.text = [NSString stringWithFormat:@"PIN Error: %@", msg];
                    self.statusLabel.textColor = [UIColor colorWithRed:1.0 green:0.4 blue:0.4 alpha:1.0];
                }
            }];
        }
    }
}

- (BOOL)textFieldShouldReturn:(UITextField *)textField {
    [textField resignFirstResponder];
    [self testTapped];
    return YES;
}

@end
