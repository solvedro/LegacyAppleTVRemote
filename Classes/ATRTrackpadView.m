#import "ATRTrackpadView.h"
#import <QuartzCore/QuartzCore.h>

@interface ATRTrackpadView () {
    CGPoint _touchStart;
    CGPoint _lastStep;
    BOOL _swipeTriggered;
    NSTimeInterval _touchStartTime;
}

@property (nonatomic, strong) UILabel *arrowUp;
@property (nonatomic, strong) UILabel *arrowDown;
@property (nonatomic, strong) UILabel *arrowLeft;
@property (nonatomic, strong) UILabel *arrowRight;
@property (nonatomic, strong) UIView *centerSelectView;
@property (nonatomic, strong) UILabel *centerLabel;

@end

@implementation ATRTrackpadView

- (id)initWithFrame:(CGRect)frame {
    self = [super initWithFrame:frame];
    if (self) {
        self.userInteractionEnabled = YES;
        self.multipleTouchEnabled = NO;
        
        CGFloat diameter = frame.size.width;
        self.layer.cornerRadius = diameter / 2.0;
        self.layer.masksToBounds = YES;
        self.backgroundColor = [UIColor colorWithWhite:0.13 alpha:0.95];
        self.layer.borderColor = [UIColor colorWithWhite:0.28 alpha:1.0].CGColor;
        self.layer.borderWidth = 1.5;
        
        CGFloat centerD = 78.0;
        CGFloat padSide = (diameter - centerD) / 2.0; // 59.0
        
        // Direction markings
        self.arrowUp = [self createArrowLabel:@"▲" frame:CGRectMake(0, 8, diameter, 24)];
        self.arrowDown = [self createArrowLabel:@"▼" frame:CGRectMake(0, diameter - 32, diameter, 24)];
        self.arrowLeft = [self createArrowLabel:@"◄" frame:CGRectMake(0, (diameter - 24) / 2.0, padSide, 24)];
        self.arrowRight = [self createArrowLabel:@"►" frame:CGRectMake(diameter - padSide, (diameter - 24) / 2.0, padSide, 24)];
        
        [self addSubview:self.arrowUp];
        [self addSubview:self.arrowDown];
        [self addSubview:self.arrowLeft];
        [self addSubview:self.arrowRight];
        
        // Center Select Button View
        CGFloat centerOffset = (diameter - centerD) / 2.0;
        self.centerSelectView = [[UIView alloc] initWithFrame:CGRectMake(centerOffset, centerOffset, centerD, centerD)];
        self.centerSelectView.layer.cornerRadius = centerD / 2.0;
        self.centerSelectView.layer.masksToBounds = YES;
        self.centerSelectView.backgroundColor = [UIColor colorWithWhite:0.18 alpha:1.0];
        self.centerSelectView.layer.borderColor = [UIColor colorWithWhite:0.35 alpha:1.0].CGColor;
        self.centerSelectView.layer.borderWidth = 1.0;
        self.centerSelectView.userInteractionEnabled = NO; // Let touches pass to trackpad surface
        
        self.centerLabel = [[UILabel alloc] initWithFrame:self.centerSelectView.bounds];
        self.centerLabel.text = @"OK";
        self.centerLabel.textColor = [UIColor colorWithWhite:0.85 alpha:1.0];
        self.centerLabel.font = [UIFont boldSystemFontOfSize:16];
        self.centerLabel.textAlignment = UITextAlignmentCenter;
        self.centerLabel.backgroundColor = [UIColor clearColor];
        [self.centerSelectView addSubview:self.centerLabel];
        
        [self addSubview:self.centerSelectView];
    }
    return self;
}

- (UILabel *)createArrowLabel:(NSString *)text frame:(CGRect)frame {
    UILabel *lbl = [[UILabel alloc] initWithFrame:frame];
    lbl.text = text;
    lbl.textColor = [UIColor colorWithWhite:0.55 alpha:1.0];
    lbl.font = [UIFont boldSystemFontOfSize:15];
    lbl.textAlignment = UITextAlignmentCenter;
    lbl.backgroundColor = [UIColor clearColor];
    lbl.adjustsFontSizeToFitWidth = YES;
    lbl.userInteractionEnabled = NO;
    return lbl;
}

- (void)flashDirection:(NSString *)direction {
    UILabel *target = nil;
    if ([direction isEqualToString:@"up"]) target = self.arrowUp;
    else if ([direction isEqualToString:@"down"]) target = self.arrowDown;
    else if ([direction isEqualToString:@"left"]) target = self.arrowLeft;
    else if ([direction isEqualToString:@"right"]) target = self.arrowRight;
    
    if (target) {
        target.textColor = [UIColor whiteColor];
        [UIView animateWithDuration:0.25 animations:^{
            target.textColor = [UIColor colorWithWhite:0.55 alpha:1.0];
        }];
    }
}

- (void)flashCenterSelect {
    self.centerSelectView.backgroundColor = [UIColor colorWithWhite:0.35 alpha:1.0];
    self.centerLabel.textColor = [UIColor whiteColor];
    [UIView animateWithDuration:0.20 animations:^{
        self.centerSelectView.backgroundColor = [UIColor colorWithWhite:0.18 alpha:1.0];
        self.centerLabel.textColor = [UIColor colorWithWhite:0.85 alpha:1.0];
    }];
}

#pragma mark - Touch Handling

- (void)touchesBegan:(NSSet *)touches withEvent:(UIEvent *)event {
    UITouch *t = [touches anyObject];
    _touchStart = [t locationInView:self];
    _lastStep = _touchStart;
    _swipeTriggered = NO;
    _touchStartTime = [NSDate timeIntervalSinceReferenceDate];
    
    CGFloat center = self.bounds.size.width / 2.0;
    CGFloat cdx = _touchStart.x - center;
    CGFloat cdy = _touchStart.y - center;
    if (sqrt(cdx * cdx + cdy * cdy) <= 39.0) {
        self.centerSelectView.backgroundColor = [UIColor colorWithWhite:0.26 alpha:1.0];
    }
}

- (void)touchesMoved:(NSSet *)touches withEvent:(UIEvent *)event {
    UITouch *t = [touches anyObject];
    CGPoint current = [t locationInView:self];
    
    CGFloat dx = current.x - _lastStep.x;
    CGFloat dy = current.y - _lastStep.y;
    CGFloat dist = sqrt(dx * dx + dy * dy);
    
    const CGFloat kSwipeThreshold = 22.0;
    if (dist >= kSwipeThreshold) {
        _swipeTriggered = YES;
        _lastStep = current;
        self.centerSelectView.backgroundColor = [UIColor colorWithWhite:0.18 alpha:1.0];
        
        NSString *direction = nil;
        if (fabs(dx) > fabs(dy)) {
            direction = (dx > 0) ? @"right" : @"left";
        } else {
            direction = (dy > 0) ? @"down" : @"up";
        }
        
        [self flashDirection:direction];
        if (self.delegate && [self.delegate respondsToSelector:@selector(trackpadView:didNavigateInDirection:isSwipe:)]) {
            [self.delegate trackpadView:self didNavigateInDirection:direction isSwipe:YES];
        }
    }
}

- (void)touchesEnded:(NSSet *)touches withEvent:(UIEvent *)event {
    self.centerSelectView.backgroundColor = [UIColor colorWithWhite:0.18 alpha:1.0];
    
    if (!_swipeTriggered) {
        UITouch *t = [touches anyObject];
        CGPoint endPt = [t locationInView:self];
        
        CGFloat center = self.bounds.size.width / 2.0;
        CGFloat cdx = endPt.x - center;
        CGFloat cdy = endPt.y - center;
        CGFloat distFromCenter = sqrt(cdx * cdx + cdy * cdy);
        
        if (distFromCenter <= 39.0) {
            // Center OK / Select
            [self flashCenterSelect];
            if (self.delegate && [self.delegate respondsToSelector:@selector(trackpadViewDidSelect:)]) {
                [self.delegate trackpadViewDidSelect:self];
            }
        } else {
            // Quadrant Tap
            NSString *direction = nil;
            if (fabs(cdx) > fabs(cdy)) {
                direction = (cdx > 0) ? @"right" : @"left";
            } else {
                direction = (cdy > 0) ? @"down" : @"up";
            }
            [self flashDirection:direction];
            if (self.delegate && [self.delegate respondsToSelector:@selector(trackpadView:didNavigateInDirection:isSwipe:)]) {
                [self.delegate trackpadView:self didNavigateInDirection:direction isSwipe:NO];
            }
        }
    }
}

- (void)touchesCancelled:(NSSet *)touches withEvent:(UIEvent *)event {
    self.centerSelectView.backgroundColor = [UIColor colorWithWhite:0.18 alpha:1.0];
    _swipeTriggered = NO;
}

@end
