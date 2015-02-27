
#import <Foundation/Foundation.h>
#import <UIKit/UIKit.h>

/**
 * Enumeration of in-app message screen positions.
 */
typedef NS_ENUM(NSInteger, UAInAppMessagePosition) {
    /**
     * The top of the screen.
     */
    UAInAppMessagePositionTop,
    /**
     * The bottom of the screen.
     */
    UAInAppMessagePositionBottom
};

/**
 * Enumeration of in-app message display types.
 */
typedef NS_ENUM(NSInteger, UAInAppMessageDisplayType) {
    /**
     * Unknown or unsupported display type.
     */
    UAInAppMessageDisplayTypeUnknown,
    /**
     * Banner display type.
     */
    UAInAppMessageDisplayTypeBanner
};

@class UAInAppMessageButtonActionBinding;

/**
 * Model object representing in-app message data.
 */
@interface UAInAppMessage : NSObject

/**
 * Class factory method for constructing an unconfigured
 * in-app message model.
 *
 * @return An unconfigured instance of UAInAppMessage.
 */
+ (instancetype)message;

/**
 * Class factory method for constructing an in-app message
 * model from the in-app message section of a push payload.
 *
 * @param payload The in-app message section of a push payload,
 * in NSDictionary representation.
 * @return A fully configured instance of UAInAppMessage.
 */
+ (instancetype)messageWithPayload:(NSDictionary *)payload;

/**
 * Retrieves the most recent pending message payload from disk.
 *
 * @return An in-app message payload in NSDictionary format.
 */
+ (NSDictionary *)pendingMessagePayload;

/**
 * Retrieves the most recent pending message from disk.
 *
 * @return An instance of UAInAppMessage, or nil if no
 * pending message is available.
 */
+ (instancetype)pendingMessage;

/**
 * Stores a pending message for later retrieval and display.
 *
 * @param payload The in-app message section of a push payload,
 * in NSDictionary representation.
 */
+ (void)storePendingMessagePayload:(NSDictionary *)payload;

/**
 * Deletes the pending message payload if present.
 *
 */
+ (void)deletePendingMessagePayload;


/**
 * Deletes the pending message payload if it matches the
 * passed payload argument.
 *
 * @param payload The message payload to delete.
 */
+ (void)deletePendingMessagePayload:(NSDictionary *)payload;


/**
 * Tests whether the message is equal by value to another message.
 *
 * @param message The message the receiver is being compared to.
 * @return `YES` if the two messages are equal by value, `NO` otherwise.
 */
- (BOOL)isEqualToMessage:(UAInAppMessage *)message;

/**
 * The in-app message payload in NSDictionary format
 */
@property(nonatomic, readonly) NSDictionary *payload;

/**
 * The unique identifier for the message (to be set from the associated send ID)
 */
@property(nonatomic, copy) NSString *identifier;

// Top level

/**
 * The expiration date for the message.
 * Unless otherwise specified, defaults to 30 days from construction.
 */
@property(nonatomic, strong) NSDate *expiry;

/**
 * Optional key value extras.
 */
@property(nonatomic, copy) NSDictionary *extra;

// Display

/**
 * The display type. Defaults to `UAInAppMessageDisplayTypeBanner`
 * when built with the default class constructor, or `UAInAppMessageDisplayTypeUnknown`
 * when built from a payload with a missing or unidentified display type.
 */
@property(nonatomic, assign) UAInAppMessageDisplayType displayType;

/**
 * The alert message.
 */
@property(nonatomic, copy) NSString *alert;

/**
 * The screen position. Defaults to `UAInAppMessagePositionBottom`.
 */
@property(nonatomic, assign) UAInAppMessagePosition position;

/**
 * The amount of time to wait before automatically dismissing
 * the message.
 */
@property(nonatomic, assign) NSTimeInterval duration;

/**
 * The primary color.
 */
@property(nonatomic, strong) UIColor *primaryColor;

/**
 * The secondary color.
 */
@property(nonatomic, strong) UIColor *secondaryColor;


// Actions

/**
 * The button group (category) associated with the message.
 * This value will determine which buttons are present and their
 * localized titles.
 */
@property(nonatomic, copy) NSString *buttonGroup;

/**
 * A dictionary mapping button group keys to dictionaries
 * mapping action names to action arguments. The relevant
 * action(s) will be run when the user taps the associated
 * button.
 */
@property(nonatomic, copy) NSDictionary *buttonActions;

/**
 * A dictionary mapping an action name to an action argument.
 * The relevant action will be run when the user taps or "clicks"
 * on the message.
 */
@property(nonatomic, copy) NSDictionary *onClick;

/**
 * An array of UAInAppMessageButtonActionBinding instances,
 * corresponding to the left to right order of interactive message
 * buttons.
 */
@property(nonatomic, readonly) NSArray *buttonActionBindings;

@end
