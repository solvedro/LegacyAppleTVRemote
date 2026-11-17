#import <UIKit/UIKit.h>

@protocol ATRAppsViewControllerDelegate <NSObject>
@optional
- (void)appsViewControllerDidDismiss;
- (void)appsViewControllerDidLaunchAppNamed:(NSString *)name bundleID:(NSString *)bundleID;
@end

@interface ATRAppsViewController : UIViewController <UITableViewDataSource, UITableViewDelegate>

@property (nonatomic, weak) id<ATRAppsViewControllerDelegate> delegate;

@end
