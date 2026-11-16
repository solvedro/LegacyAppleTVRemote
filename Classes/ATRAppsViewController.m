#import "ATRAppsViewController.h"
#import "Companion/ATRCompanionClient.h"
#import "ATRClient.h"
#import <AudioToolbox/AudioToolbox.h>
#import <QuartzCore/QuartzCore.h>

static NSString * const kATRCachedAppsPrefKey = @"ATRCachedLaunchableApps";

@interface ATRAppsViewController ()

@property (nonatomic, strong) UITableView *tableView;
@property (nonatomic, strong) UIActivityIndicatorView *spinner;
@property (nonatomic, strong) NSMutableArray *appList; // array of @{@"name": ..., @"bundleID": ...}
@property (nonatomic, strong) NSMutableArray *quickShortcuts;

@end

@implementation ATRAppsViewController

- (void)viewDidLoad {
    [super viewDidLoad];
    
    self.view.backgroundColor = [UIColor colorWithWhite:0.09 alpha:1.0];
    
    // Top Navigation Bar (Y: 0 to 48)
    UIView *topBar = [[UIView alloc] initWithFrame:CGRectMake(0, 0, 320, 48)];
    topBar.backgroundColor = [UIColor colorWithWhite:0.14 alpha:0.98];
    topBar.layer.borderColor = [UIColor colorWithWhite:0.25 alpha:1.0].CGColor;
    topBar.layer.borderWidth = 0.5;
    [self.view addSubview:topBar];
    
    // Title
    UILabel *titleLbl = [[UILabel alloc] initWithFrame:CGRectMake(70, 10, 180, 28)];
    titleLbl.text = @"Apple TV Apps";
    titleLbl.textColor = [UIColor whiteColor];
    titleLbl.font = [UIFont boldSystemFontOfSize:17];
    titleLbl.textAlignment = UITextAlignmentCenter;
    titleLbl.backgroundColor = [UIColor clearColor];
    [topBar addSubview:titleLbl];
    
    // Done Button (Right)
    UIButton *doneBtn = [UIButton buttonWithType:UIButtonTypeCustom];
    doneBtn.frame = CGRectMake(252, 8, 60, 32);
    [doneBtn setTitle:@"Done" forState:UIControlStateNormal];
    [doneBtn setTitleColor:[UIColor colorWithRed:0.35 green:0.75 blue:1.0 alpha:1.0] forState:UIControlStateNormal];
    doneBtn.titleLabel.font = [UIFont boldSystemFontOfSize:15];
    [doneBtn addTarget:self action:@selector(doneTapped) forControlEvents:UIControlEventTouchUpInside];
    [topBar addSubview:doneBtn];
    
    // Refresh Button (Left)
    UIButton *refreshBtn = [UIButton buttonWithType:UIButtonTypeCustom];
    refreshBtn.frame = CGRectMake(10, 8, 44, 32);
    [refreshBtn setTitle:@"↻" forState:UIControlStateNormal];
    [refreshBtn setTitleColor:[UIColor colorWithWhite:0.85 alpha:1.0] forState:UIControlStateNormal];
    refreshBtn.titleLabel.font = [UIFont boldSystemFontOfSize:22];
    [refreshBtn addTarget:self action:@selector(loadApps) forControlEvents:UIControlEventTouchUpInside];
    [topBar addSubview:refreshBtn];
    
    // Spinner
    self.spinner = [[UIActivityIndicatorView alloc] initWithActivityIndicatorStyle:UIActivityIndicatorViewStyleWhite];
    self.spinner.frame = CGRectMake(54, 14, 20, 20);
    self.spinner.hidesWhenStopped = YES;
    [topBar addSubview:self.spinner];
    
    // Table View
    self.tableView = [[UITableView alloc] initWithFrame:CGRectMake(0, 48, 320, 480 - 48) style:UITableViewStylePlain];
    self.tableView.backgroundColor = [UIColor colorWithWhite:0.09 alpha:1.0];
    self.tableView.separatorColor = [UIColor colorWithWhite:0.20 alpha:1.0];
    self.tableView.dataSource = self;
    self.tableView.delegate = self;
    self.tableView.rowHeight = 52.0;
    [self.view addSubview:self.tableView];
    
    // Load from cache first
    [self loadCachedApps];
    
    // Fetch fresh apps from device
    [self loadApps];
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
                NSString *path = [docs stringByAppendingPathComponent:@"apps_screen.png"];
                [UIImagePNGRepresentation(img) writeToFile:path atomically:YES];
                NSLog(@"[Screenshot] Saved apps screenshot to %@", path);
            }
        }
    });
}

- (void)loadCachedApps {
    NSDictionary *cached = [[NSUserDefaults standardUserDefaults] dictionaryForKey:kATRCachedAppsPrefKey];
    if (cached && [cached count] > 0) {
        [self processAppsDict:cached];
        [self.tableView reloadData];
    }
}

- (void)processAppsDict:(NSDictionary *)dict {
    NSMutableArray *list = [NSMutableArray array];
    NSMutableArray *shortcuts = [NSMutableArray array];
    
    // Well-known popular app bundle ID prefixes to highlight
    NSSet *popularKeys = [NSSet setWithObjects:
        @"com.google.ios.youtube",
        @"ro.digi.tv",
        @"com.amazon.aiv.AIVApp",
        @"com.plexapp.plex",
        @"com.moonlight-stream.Moonlight",
        @"com.libretro.dist.RetroArch",
        @"org.videolan.vlc-ios",
        @"com.apple.TVMusic",
        @"com.apple.TVWatchList",
        @"com.comedybox.app",
        nil
    ];
    
    for (NSString *bundleID in dict) {
        NSString *name = [dict objectForKey:bundleID];
        NSDictionary *appEntry = @{@"name": name ?: bundleID, @"bundleID": bundleID};
        [list addObject:appEntry];
        
        if ([popularKeys containsObject:bundleID]) {
            [shortcuts addObject:appEntry];
        }
    }
    
    // Sort alphabetically by name
    [list sortUsingComparator:^NSComparisonResult(NSDictionary *a, NSDictionary *b) {
        return [[a objectForKey:@"name"] localizedCaseInsensitiveCompare:[b objectForKey:@"name"]];
    }];
    [shortcuts sortUsingComparator:^NSComparisonResult(NSDictionary *a, NSDictionary *b) {
        return [[a objectForKey:@"name"] localizedCaseInsensitiveCompare:[b objectForKey:@"name"]];
    }];
    
    self.appList = list;
    self.quickShortcuts = shortcuts;
}

- (void)loadApps {
    [self.spinner startAnimating];
    
    NSString *mode = [[NSUserDefaults standardUserDefaults] stringForKey:@"ATRConnectionMode"];
    if ([mode isEqualToString:@"Bridge"]) {
        // Fetch via Bridge HTTP endpoint
        NSString *urlStr = [NSString stringWithFormat:@"%@/apps", [ATRClient sharedClient].serverHost];
        NSURL *url = [NSURL URLWithString:urlStr];
        if (!url) {
            [self.spinner stopAnimating];
            return;
        }
        NSURLRequest *req = [NSURLRequest requestWithURL:url cachePolicy:NSURLRequestReloadIgnoringLocalCacheData timeoutInterval:6.0];
        [NSURLConnection sendAsynchronousRequest:req queue:[NSOperationQueue mainQueue] completionHandler:^(NSURLResponse *res, NSData *data, NSError *err) {
            [self.spinner stopAnimating];
            if (data && !err) {
                NSDictionary *dict = [NSJSONSerialization JSONObjectWithData:data options:0 error:nil];
                if (dict && [dict isKindOfClass:[NSDictionary class]]) {
                    [[NSUserDefaults standardUserDefaults] setObject:dict forKey:kATRCachedAppsPrefKey];
                    [[NSUserDefaults standardUserDefaults] synchronize];
                    [self processAppsDict:dict];
                    [self.tableView reloadData];
                }
            }
        }];
    } else {
        // Standalone Direct Companion Protocol
        [[ATRCompanionClient sharedClient] fetchLaunchableApps:^(NSDictionary *apps, NSString *error) {
            dispatch_async(dispatch_get_main_queue(), ^{
                [self.spinner stopAnimating];
                if (apps && [apps isKindOfClass:[NSDictionary class]] && [apps count] > 0) {
                    [[NSUserDefaults standardUserDefaults] setObject:apps forKey:kATRCachedAppsPrefKey];
                    [[NSUserDefaults standardUserDefaults] synchronize];
                    [self processAppsDict:apps];
                    [self.tableView reloadData];
                }
            });
        }];
    }
}

- (void)doneTapped {
    if (self.delegate && [self.delegate respondsToSelector:@selector(appsViewControllerDidDismiss)]) {
        [self.delegate appsViewControllerDidDismiss];
    } else {
        [self dismissModalViewControllerAnimated:YES];
    }
}

#pragma mark - Table View Data Source & Delegate

- (NSInteger)numberOfSectionsInTableView:(UITableView *)tableView {
    NSInteger count = 0;
    if (self.quickShortcuts && [self.quickShortcuts count] > 0) count++;
    if (self.appList && [self.appList count] > 0) count++;
    return count > 0 ? count : 1;
}

- (NSInteger)tableView:(UITableView *)tableView numberOfRowsInSection:(NSInteger)section {
    if (!self.appList || [self.appList count] == 0) {
        return 1; // "Loading apps..."
    }
    if ([self hasShortcutsSection] && section == 0) {
        return [self.quickShortcuts count];
    }
    return [self.appList count];
}

- (BOOL)hasShortcutsSection {
    return (self.quickShortcuts && [self.quickShortcuts count] > 0);
}

- (NSString *)tableView:(UITableView *)tableView titleForHeaderInSection:(NSInteger)section {
    if (!self.appList || [self.appList count] == 0) return nil;
    if ([self hasShortcutsSection] && section == 0) {
        return @"Quick Shortcuts";
    }
    return [NSString stringWithFormat:@"All Installed Applications (%lu)", (unsigned long)[self.appList count]];
}

- (UIView *)tableView:(UITableView *)tableView viewForHeaderInSection:(NSInteger)section {
    NSString *title = [self tableView:tableView titleForHeaderInSection:section];
    if (!title) return nil;
    
    UIView *header = [[UIView alloc] initWithFrame:CGRectMake(0, 0, 320, 24)];
    header.backgroundColor = [UIColor colorWithWhite:0.14 alpha:0.95];
    
    UILabel *lbl = [[UILabel alloc] initWithFrame:CGRectMake(14, 2, 292, 20)];
    lbl.text = title;
    lbl.textColor = [UIColor colorWithRed:0.35 green:0.75 blue:1.0 alpha:1.0];
    lbl.font = [UIFont boldSystemFontOfSize:12];
    lbl.backgroundColor = [UIColor clearColor];
    [header addSubview:lbl];
    return header;
}

- (CGFloat)tableView:(UITableView *)tableView heightForHeaderInSection:(NSInteger)section {
    return [self tableView:tableView titleForHeaderInSection:section] ? 24.0 : 0.0;
}

- (UITableViewCell *)tableView:(UITableView *)tableView cellForRowAtIndexPath:(NSIndexPath *)indexPath {
    static NSString *CellId = @"ATRAppCell";
    UITableViewCell *cell = [tableView dequeueReusableCellWithIdentifier:CellId];
    if (!cell) {
        cell = [[UITableViewCell alloc] initWithStyle:UITableViewCellStyleSubtitle reuseIdentifier:CellId];
        cell.backgroundColor = [UIColor colorWithWhite:0.10 alpha:1.0];
        cell.textLabel.textColor = [UIColor whiteColor];
        cell.textLabel.font = [UIFont boldSystemFontOfSize:15];
        cell.detailTextLabel.textColor = [UIColor colorWithWhite:0.55 alpha:1.0];
        cell.detailTextLabel.font = [UIFont systemFontOfSize:11];
        
        UIView *selBg = [[UIView alloc] init];
        selBg.backgroundColor = [UIColor colorWithRed:0.15 green:0.35 blue:0.60 alpha:1.0];
        cell.selectedBackgroundView = selBg;
    }
    
    if (!self.appList || [self.appList count] == 0) {
        cell.textLabel.text = @"Connecting to Apple TV...";
        cell.detailTextLabel.text = @"Fetching launchable application list";
        cell.accessoryType = UITableViewCellAccessoryNone;
        return cell;
    }
    
    NSDictionary *entry = nil;
    if ([self hasShortcutsSection] && indexPath.section == 0) {
        entry = [self.quickShortcuts objectAtIndex:indexPath.row];
    } else {
        entry = [self.appList objectAtIndex:indexPath.row];
    }
    
    cell.textLabel.text = [entry objectForKey:@"name"];
    cell.detailTextLabel.text = [entry objectForKey:@"bundleID"];
    cell.accessoryType = UITableViewCellAccessoryDisclosureIndicator;
    return cell;
}

- (void)tableView:(UITableView *)tableView didSelectRowAtIndexPath:(NSIndexPath *)indexPath {
    [tableView deselectRowAtIndexPath:indexPath animated:YES];
    
    if (!self.appList || [self.appList count] == 0) return;
    
    NSDictionary *entry = nil;
    if ([self hasShortcutsSection] && indexPath.section == 0) {
        entry = [self.quickShortcuts objectAtIndex:indexPath.row];
    } else {
        entry = [self.appList objectAtIndex:indexPath.row];
    }
    
    NSString *bundleID = [entry objectForKey:@"bundleID"];
    NSString *name = [entry objectForKey:@"name"];
    
    AudioServicesPlaySystemSound(1104);
    
    // Launch app on Apple TV
    NSString *mode = [[NSUserDefaults standardUserDefaults] stringForKey:@"ATRConnectionMode"];
    if ([mode isEqualToString:@"Bridge"]) {
        NSString *urlStr = [NSString stringWithFormat:@"%@/launch?app=%@", [ATRClient sharedClient].serverHost, bundleID];
        NSURL *url = [NSURL URLWithString:urlStr];
        if (url) {
            NSURLRequest *req = [NSURLRequest requestWithURL:url];
            [NSURLConnection sendAsynchronousRequest:req queue:[NSOperationQueue mainQueue] completionHandler:nil];
        }
    } else {
        [[ATRCompanionClient sharedClient] launchAppWithBundleID:bundleID];
    }
    
    // Show brief confirmation and dismiss
    NSLog(@"[Apps] Launched '%@' (%@)", name, bundleID);
    [self doneTapped];
}

@end
