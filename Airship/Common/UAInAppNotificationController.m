#import "UAInAppNotificationController.h"
#import "UAInAppNotification.h"
#import "UAInAppNotificationView.h"
#import "UAUtils.h"
#import "UAUserNotificationCategories+Internal.h"
#import "UAInAppNotificationButtonActionBinding.h"
#import "UAActionRunner.h"

#define kUAInAppNotificationDefaultPrimaryColor [UIColor whiteColor]
#define kUAInAppNotificationDefaultSecondaryColor [UIColor colorWithRed:40.0/255 green:40.0/255 blue:40.0/255 alpha:1]
#define kUAInAppNotificationiPhoneScreenWidthPercentage 0.95
#define kUAInAppNotificationPadScreenWidthPercentage 0.45


@interface UAInAppNotificationController ()

@property(nonatomic, strong) UAInAppNotification *notification;
@property(nonatomic, strong) UAInAppNotificationView *notificationView;

/**
 * An array of dictionaries containing localized button titles and
 * action name/argument value bindings.
 */
@property(nonatomic, strong) NSArray *buttonActionBindings;

/**
 * A settable reference to self, so we can self-retain for the notification
 * display duration.
 */
@property(nonatomic, strong) UAInAppNotificationController *referenceToSelf;

@end

@implementation UAInAppNotificationController

- (instancetype)initWithNotification:(UAInAppNotification *)notification {
    self = [super init];
    if (self) {
        self.notification = notification;

        self.buttonActionBindings = notification.buttonActionBindings;

    }
    return self;
}

/**
 * Configures a notification view with the associated
 * notification model data.
 */
- (UAInAppNotificationView *)buildNotificationView {

    UIFont *boldFont = [UIFont boldSystemFontOfSize:12];

    // the primary and secondary colors aren't set in the model, choose sensible defaults
    UIColor *primaryColor = self.notification.primaryColor ?: kUAInAppNotificationDefaultPrimaryColor;
    UIColor *secondaryColor = self.notification.secondaryColor ?: kUAInAppNotificationDefaultSecondaryColor;

    UAInAppNotificationView *notificationView = [[UAInAppNotificationView alloc] initWithPosition:self.notification.position
                                                                                  numberOfButtons:self.buttonActionBindings.count];

    // configure all the subviews
    notificationView.backgroundColor = primaryColor;

    notificationView.tab.backgroundColor = secondaryColor;

    notificationView.messageLabel.text = self.notification.alert;
    notificationView.messageLabel.numberOfLines = 4;
    notificationView.messageLabel.font = boldFont;
    notificationView.messageLabel.textColor = secondaryColor;

    notificationView.button1.titleLabel.font = boldFont;
    notificationView.button2.titleLabel.font = boldFont;

    if (self.buttonActionBindings.count) {
        UAInAppNotificationButtonActionBinding *button1 = self.buttonActionBindings[0];
        [notificationView.button1 setTitle:button1.localizedTitle forState:UIControlStateNormal];
        if (self.buttonActionBindings.count > 1) {
            UAInAppNotificationButtonActionBinding *button2 = self.buttonActionBindings[1];
            [notificationView.button2 setTitle:button2.localizedTitle forState:UIControlStateNormal];
        }
    }

    [notificationView.button1 setTitleColor:primaryColor forState:UIControlStateNormal];
    [notificationView.button2 setTitleColor:primaryColor forState:UIControlStateNormal];
    notificationView.button1.backgroundColor = secondaryColor;
    notificationView.button2.backgroundColor = secondaryColor;

    return notificationView;
}

/**
 * Signs self up for control events on the notification view.
 * This method has the side effect of adding self as a target for
 * button, swipe and tap actions.
 */
- (void)signUpForControlEventsWithNotificationView:(UAInAppNotificationView *)notificationView {
    // add a swipe gesture recognizer corresponding to the position of the notification
    UISwipeGestureRecognizer *swipeGestureRecognizer = [[UISwipeGestureRecognizer alloc] initWithTarget:self action:@selector(swipeWithGestureRecognizer:)];

    if (self.notification.position == UAInAppNotificationPositionTop) {
        swipeGestureRecognizer.direction = UISwipeGestureRecognizerDirectionUp;
    } else {
        swipeGestureRecognizer.direction = UISwipeGestureRecognizerDirectionDown;
    }

    [notificationView addGestureRecognizer:swipeGestureRecognizer];

    // add a tap gesture recognizer if an onClick action is present in the model
    if (self.notification.onClick) {
        UITapGestureRecognizer *tapGestureRecognizer = [[UITapGestureRecognizer alloc] initWithTarget:self action:@selector(tapWithGestureRecognizer:)];
        [notificationView addGestureRecognizer:tapGestureRecognizer];
    }

    // sign up for button touch events
    [notificationView.button1 addTarget:self action:@selector(buttonTapped:) forControlEvents:UIControlEventTouchUpInside];
    [notificationView.button2 addTarget:self action:@selector(buttonTapped:) forControlEvents:UIControlEventTouchUpInside];
}

/**
 * Adds layout constraints to the notification view.
 */
- (void)buildLayoutWithParent:(UIView *)parentView notificationView:(UAInAppNotificationView *)notificationView {
    CGFloat horizontalMargin = 0;
    CGRect screenRect = [UIScreen mainScreen].applicationFrame;
    CGFloat screenWidth = CGRectGetWidth(screenRect);

    // On an iPad, notifications are 45% of the fixed screen width in landscape
    CGFloat longWidth = MAX(screenWidth, CGRectGetHeight(screenRect));
    CGFloat actualLongWidth = longWidth * kUAInAppNotificationPadScreenWidthPercentage;

    // On a phone, notifications are always 95% of current screen width
    horizontalMargin = (screenWidth - screenWidth*kUAInAppNotificationiPhoneScreenWidthPercentage)/2.0;

    id metrics = @{@"horizontalMargin":@(horizontalMargin), @"longWidth":@(actualLongWidth)};
    id views = @{@"notificationView":notificationView};

    [parentView addSubview:notificationView];

    // center the notification view in the parent (this cannot be expressed in VFL)
    [parentView addConstraint:[NSLayoutConstraint constraintWithItem:notificationView
                                                           attribute:NSLayoutAttributeCenterX
                                                           relatedBy:NSLayoutRelationEqual
                                                              toItem:parentView
                                                           attribute:NSLayoutAttributeCenterX multiplier:1
                                                            constant:0]];

    NSString *verticalLayout;
    NSString *horizontalLayout;

    // place the notification view flush against the top or bottom of the parent, depending on position
    if (self.notification.position == UAInAppNotificationPositionBottom) {
        verticalLayout = @"V:[notificationView]|";
    } else {
        verticalLayout = @"V:|[notificationView]";
    }

    // if the UI idiom is iPad, use the fixed width, otherwise offset it with the horizontal margins
    if ([UIDevice currentDevice].userInterfaceIdiom == UIUserInterfaceIdiomPad) {
        horizontalLayout = @"[notificationView(longWidth)]";
    } else {
        horizontalLayout = @"H:|-horizontalMargin-[notificationView]-horizontalMargin-|";
    }

    for (NSString *expression in @[verticalLayout, horizontalLayout]) {
        [parentView addConstraints:[NSLayoutConstraint constraintsWithVisualFormat:expression
                                                                           options:0
                                                                           metrics:metrics
                                                                             views:views]];
    }

    // forces a layout, giving the traditional CGGeometry attributes defined values for the
    // current set of constraints
    [notificationView layoutIfNeeded];
}

- (void)show {

    UIView *parentView = [UAUtils topController].view;

    // retain self for the duration of the notification display, so that avoiding premature deallocation
    // is not directly dependent on arbitrary container/object lifecycles
    self.referenceToSelf = self;

    UAInAppNotificationView *notificationView = [self buildNotificationView];
    [self buildLayoutWithParent:parentView notificationView:notificationView];
    [self signUpForControlEventsWithNotificationView:notificationView];

    self.notificationView = notificationView;

    // simple timer that dispatches a dismiss call after the notification duration has been reached
    void(^timeoutBlock)(void) = ^{
        __weak UAInAppNotificationController *weakSelf = self;
        dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(self.notification.duration * NSEC_PER_SEC)), dispatch_get_main_queue(), ^{
            [weakSelf dismiss];
        });
    };

    // save and offset the notification view's original center point for animation in
    CGPoint originalCenter = self.notificationView.center;
    if (self.notification.position == UAInAppNotificationPositionTop) {
        self.notificationView.center = CGPointMake(originalCenter.x, -(CGRectGetHeight(self.notificationView.frame)/2));
    } else if (self.notification.position == UAInAppNotificationPositionBottom) {
        self.notificationView.center = CGPointMake(originalCenter.x, CGRectGetHeight(parentView.frame) + CGRectGetHeight(self.notificationView.frame)/2);
    }

    // animate the notification view into place, starting the timer when the animation has completed
    [UIView animateWithDuration:0.2 delay:0 options:UIViewAnimationOptionCurveEaseInOut animations:^{
        self.notificationView.center = originalCenter;
    } completion:^(BOOL finished) {
        timeoutBlock();
    }];
}

- (void)dismissWithAnimationBlock:(void(^)(void))block {
    [UIView animateWithDuration:0.2
                          delay:0
                        options:UIViewAnimationOptionCurveEaseInOut
                     animations:block
                     completion:^(BOOL finished){
                         [self.notificationView removeFromSuperview];
                         self.notificationView = nil;
                         // release self
                         self.referenceToSelf = nil;
                     }];
}

- (void)dismiss {
    [self dismissWithAnimationBlock:^{
        // animate the notification view back off the screen
        if (self.notification.position == UAInAppNotificationPositionTop) {
            self.notificationView.center = CGPointMake(self.notificationView.center.x, -(CGRectGetHeight(self.notificationView.frame)/2));
        } else {
            self.notificationView.center = CGPointMake(self.notificationView.center.x, self.notificationView.center.y + (CGRectGetHeight(self.notificationView.frame)/2));
        }
    }];
}

- (void)swipeWithGestureRecognizer:(UIGestureRecognizer *)recognizer {
    [self dismiss];
}

- (void)tapWithGestureRecognizer:(UIGestureRecognizer *)recognizer {
    // run onClick action here
    [self dismiss];
}

- (void)buttonTapped:(id)sender {
    UAInAppNotificationButtonActionBinding *binding;

    // retrieve the binding associated with the tapped button
    if ([sender isEqual:self.notificationView.button1]) {
        binding = self.buttonActionBindings[0];
    } else if ([sender isEqual:self.notificationView.button2])  {
        binding = self.buttonActionBindings[1];
    }

    // run all the bound actions
    for (NSString *actionName in binding.actions) {
        UAActionArguments *args = binding.actions[actionName];
        [UAActionRunner runActionWithName:actionName withArguments:args withCompletionHandler:nil];
    }

    [self dismiss];
}

@end
