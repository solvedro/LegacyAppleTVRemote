#import <UIKit/UIKit.h>

@protocol ATRAppsViewControllerDelegate <NSObject>
@optional
- (void)appsViewControllerDidDismiss;
@end

@interface ATRAppsViewController : UIViewController <UITableViewDataSource, UITableViewDelegate>

@property (nonatomic, weak) id<ATRAppsViewControllerDelegate> delegate;

@end
