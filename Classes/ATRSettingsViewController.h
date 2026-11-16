#import <UIKit/UIKit.h>

@protocol ATRSettingsDelegate <NSObject>
- (void)settingsDidDismiss;
@end

@interface ATRSettingsViewController : UIViewController

@property (nonatomic, weak) id<ATRSettingsDelegate> delegate;

@end
