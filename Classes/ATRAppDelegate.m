#import "ATRAppDelegate.h"
#import "ATRRemoteViewController.h"

@implementation ATRAppDelegate

- (BOOL)application:(UIApplication *)application didFinishLaunchingWithOptions:(NSDictionary *)launchOptions {
    self.window = [[UIWindow alloc] initWithFrame:[[UIScreen mainScreen] bounds]];
    self.viewController = [[ATRRemoteViewController alloc] init];
    self.window.rootViewController = self.viewController;
    [self.window makeKeyAndVisible];
    return YES;
}

- (void)applicationDidBecomeActive:(UIApplication *)application {
    if ([self.viewController respondsToSelector:@selector(appDidBecomeActive)]) {
        [self.viewController performSelector:@selector(appDidBecomeActive)];
    }
}

@end
