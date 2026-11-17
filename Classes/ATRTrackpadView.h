#import <UIKit/UIKit.h>

@class ATRTrackpadView;

@protocol ATRTrackpadViewDelegate <NSObject>
@optional
- (void)trackpadViewDidSelect:(ATRTrackpadView *)trackpad;
- (void)trackpadView:(ATRTrackpadView *)trackpad didNavigateInDirection:(NSString *)direction isSwipe:(BOOL)isSwipe;
@end

@interface ATRTrackpadView : UIView

@property (nonatomic, weak) id<ATRTrackpadViewDelegate> delegate;

@property (nonatomic, strong, readonly) UILabel *arrowUp;
@property (nonatomic, strong, readonly) UILabel *arrowDown;
@property (nonatomic, strong, readonly) UILabel *arrowLeft;
@property (nonatomic, strong, readonly) UILabel *arrowRight;
@property (nonatomic, strong, readonly) UIView *centerSelectView;
@property (nonatomic, strong, readonly) UILabel *centerLabel;

- (void)flashDirection:(NSString *)direction;

@end
