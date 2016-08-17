/*
 Copyright 2009-2016 Urban Airship Inc. All rights reserved.

 Redistribution and use in source and binary forms, with or without
 modification, are permitted provided that the following conditions are met:

 1. Redistributions of source code must retain the above copyright notice, this
 list of conditions and the following disclaimer.

 2. Redistributions in binary form must reproduce the above copyright notice,
 this list of conditions and the following disclaimer in the documentation
 and/or other materials provided with the distribution.

 THIS SOFTWARE IS PROVIDED BY THE URBAN AIRSHIP INC ``AS IS'' AND ANY EXPRESS OR
 IMPLIED WARRANTIES, INCLUDING, BUT NOT LIMITED TO, THE IMPLIED WARRANTIES OF
 MERCHANTABILITY AND FITNESS FOR A PARTICULAR PURPOSE ARE DISCLAIMED. IN NO
 EVENT SHALL URBAN AIRSHIP INC OR CONTRIBUTORS BE LIABLE FOR ANY DIRECT,
 INDIRECT, INCIDENTAL, SPECIAL, EXEMPLARY, OR CONSEQUENTIAL DAMAGES (INCLUDING,
 BUT NOT LIMITED TO, PROCUREMENT OF SUBSTITUTE GOODS OR SERVICES; LOSS OF USE,
 DATA, OR PROFITS; OR BUSINESS INTERRUPTION) HOWEVER CAUSED AND ON ANY THEORY OF
 LIABILITY, WHETHER IN CONTRACT, STRICT LIABILITY, OR TORT (INCLUDING NEGLIGENCE
 OR OTHERWISE) ARISING IN ANY WAY OUT OF THE USE OF THIS SOFTWARE, EVEN IF
 ADVISED OF THE POSSIBILITY OF SUCH DAMAGE.
 */

#import <Foundation/Foundation.h>
#import "UANotificationContent.h"

NS_ASSUME_NONNULL_BEGIN

@interface UANotificationResponse : NSObject

/**
 * Action identifier representing an application launch via notification.
 */
extern NSString *const UANotificationDefaultActionIdentifier;

/**
 * Action identifier representing a notification dismissal.
 */
extern NSString *const UANotificationDismissActionIdentifier;

/**
 * Action identifier for the response.
 */
@property (nonatomic, strong, nullable) NSString *actionIdentifier;

/**
 * String populated with any response text provided by the user.
 */
@property (nonatomic, strong, nullable) NSString *responseText;

/**
 * The UANotificationContent instance associated with the response.
 */
@property (nonatomic, strong) UANotificationContent *notificationContent;

/**
 * Generates a UANotificationResponse with a UANotificationContent instance, action identifier.
 *
 * @param notificationContent UANotificationContent instance.
 * @param actionIdentifier NSString action identifier associated with the notification.
 *
 * @return UANotificationResponse instance
 */
+ (instancetype)notificationResponseWithNotificationContent:(UANotificationContent *)notificationContent actionIdentifier:(nullable NSString *)actionIdentifier;

/**
 * Generates a UANotificationResponse with a notification payload, action identifier.
 *
 * @param notificationInfo NSDictionary containing the notification payload.
 * @param actionIdentifier NSString action identifier associated with the notification.
 *
 * @return UANotificationResponse instance
 */
+ (instancetype)notificationResponseWithNotificationInfo:(NSDictionary *)notificationInfo actionIdentifier:(nullable NSString *)actionIdentifier;

@end

NS_ASSUME_NONNULL_END
