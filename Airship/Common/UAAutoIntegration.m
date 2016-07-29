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

#import "UAAutoIntegration+Internal.h"
#import <UserNotifications/UserNotifications.h>
#import <objc/runtime.h>

#import "UAirship+Internal.h"
#import "UAPush.h"

static UAAutoIntegration *instance_;

@interface UAAutoIntegrationDummyDelegate : NSObject<UNUserNotificationCenterDelegate>

@end

@implementation UAAutoIntegrationDummyDelegate

- (void)userNotificationCenter:(UNUserNotificationCenter *)center didReceiveNotificationResponse:(UNNotificationResponse *)response withCompletionHandler:(void (^)())completionHandler {
    //This is a dummy implementation, use respective C methods instead
}

- (void)userNotificationCenter:(UNUserNotificationCenter *)center willPresentNotification:(UNNotification *)notification withCompletionHandler:(void (^)(UNNotificationPresentationOptions))completionHandler {
    //This is a dummy implementation, use respective C methods instead
}

@end

@interface UAAutoIntegration()
@property (nonatomic, strong) NSMutableDictionary *originalMethods;
@property (nonatomic, strong) UAAutoIntegrationDummyDelegate *dummyNotificationDelegate;
@end

@implementation UAAutoIntegration

+ (void)integrate {
    static dispatch_once_t onceToken;
    dispatch_once(&onceToken, ^{
        instance_ = [[UAAutoIntegration alloc] init];

        [instance_ swizzleAppDelegate];

        if ([[NSProcessInfo processInfo] isOperatingSystemAtLeastVersion:(NSOperatingSystemVersion){10, 0, 0}]) {
            [instance_ swizzleNotificationCenter];
        }
    });
}

- (instancetype)init {
    self = [super init];
    if (self) {
        self.originalMethods = [NSMutableDictionary dictionary];
        self.dummyNotificationDelegate = [[UAAutoIntegrationDummyDelegate alloc] init];
    }

    return self;
}

- (void)swizzleAppDelegate {
    id delegate = [UIApplication sharedApplication].delegate;
    if (!delegate) {
        UA_LERR(@"App delegate not set, unable to perform automatic setup.");
        return;
    }

    Class class = [delegate class];


    // Device token
    [self swizzle:@selector(application:didRegisterForRemoteNotificationsWithDeviceToken:)
   implementation:(IMP)ApplicationDidRegisterForRemoteNotificationsWithDeviceToken class:class];

    // Device token errors
    [self swizzle:@selector(application:didFailToRegisterForRemoteNotificationsWithError:)
   implementation:(IMP)ApplicationDidFailToRegisterForRemoteNotificationsWithError
            class:class];

    // iOS 10+
    if ([[NSProcessInfo processInfo] isOperatingSystemAtLeastVersion:(NSOperatingSystemVersion){10, 0, 0}]) {

        // Silent notifications
        [self swizzle:@selector(application:didReceiveRemoteNotification:fetchCompletionHandler:)
       implementation:(IMP)ApplicationDidReceiveRemoteNotificationFetchCompletionHandler
                class:class];


    } else { // iOS 8 & 9

        // application:handleActionWithIdentifier:forRemoteNotification:completionHandler:
        [self swizzle:@selector(application:handleActionWithIdentifier:forRemoteNotification:completionHandler:)
       implementation:(IMP)ApplicationHandleActionWithIdentifierForRemoteNotificationCompletionHandler
                class:class];

        SEL responseInfoSelector = NSSelectorFromString(@"application:handleActionWithIdentifier:forRemoteNotification:withResponseInfo:completionHandler:");

        [self swizzle:responseInfoSelector implementation:(IMP)ApplicationHandleActionWithIdentifierForRemoteNotificationWithResponseInfoCompletionHandler class:class];

        // If we implement application:didReceiveRemoteNotification:fetchCompletionHandler: it prevents
        // application:didReceiveRemoteNotification: from being called. Only implement it if the app does not implement,
        // the app already implements application:didReceiveRemoteNotification:fetchCompletionHandler:, or if
        // background push is enabled.
        if ([delegate respondsToSelector:@selector(application:didReceiveRemoteNotification:fetchCompletionHandler:)] ||
            ![delegate respondsToSelector:@selector(application:didReceiveRemoteNotification:)] ||
            [UAirship shared].remoteNotificationBackgroundModeEnabled) {

            [self swizzle:@selector(application:didReceiveRemoteNotification:fetchCompletionHandler:)
           implementation:(IMP)ApplicationDidReceiveRemoteNotificationFetchCompletionHandler
                    class:class];
        }

        // application:didReceiveRemoteNotification:
        [self swizzle:@selector(application:didReceiveRemoteNotification:)
       implementation:(IMP)ApplicationDidReceiveRemoteNotification class:class];


        // application:didRegisterUserNotificationSettings:
        [self swizzle:@selector(application:didRegisterUserNotificationSettings:)
       implementation:(IMP)ApplicationDidRegisterUserNotificationSettings
                class:class];
    }
}

- (void)swizzleNotificationCenter {
    Class class = [UNUserNotificationCenter class];
    if (!class) {
        UA_LERR(@"UNUserNotificationCenter not available, unable to perform automatic setup.");
        return;
    }

    // setDelegate:
    [self swizzle:@selector(setDelegate:) implementation:(IMP)UserNotificationCenterSetDelegate class:class];

    id notificationCenterDelegate = [UNUserNotificationCenter currentNotificationCenter].delegate;
    if (notificationCenterDelegate) {
        [self swizzleNotificationCenterDelegate:notificationCenterDelegate];
    } else {
        [UNUserNotificationCenter currentNotificationCenter].delegate = instance_.dummyNotificationDelegate;
    }
}

- (void)swizzleNotificationCenterDelegate:(id<UNUserNotificationCenterDelegate>)delegate {
    Class class = [delegate class];
    if (!class) {
        UA_LERR(@"UNUserNotificationCenterDelegate not available, unable to perform automatic setup.");
        return;
    }

    [self swizzle:@selector(userNotificationCenter:willPresentNotification:withCompletionHandler:) implementation:(IMP)UserNotificationCenterWillPresentNotificationWithCompletionHandler class:class];
    [self swizzle:@selector(userNotificationCenter:didReceiveNotificationResponse:withCompletionHandler:) implementation:(IMP)UserNotificationCenterDidReceiveNotificationResponseWithCompletionHandler class:class];
}

-(void)unswizzleNotificationCenterDelegate:(id<UNUserNotificationCenterDelegate>)delegate {
    Class class = [delegate class];
    if (!class) {
        UA_LERR(@"UNUserNotificationCenterDelegate not available, unable to perform automatic setup.");
        return;
    }

    [self unswizzle:@selector(userNotificationCenter:willPresentNotification:withCompletionHandler:) class:class];
    [self unswizzle:@selector(userNotificationCenter:didReceiveNotificationResponse:withCompletionHandler:) class:class];
}

- (void)swizzle:(SEL)selector implementation:(IMP)implementation class:(Class)class {
    Method method = class_getInstanceMethod(class, selector);
    if (method) {
        UA_LDEBUG(@"Swizzling implementation for %@ class %@", NSStringFromSelector(selector), class);
        IMP existing = method_setImplementation(method, implementation);
        if (implementation != existing) {
            [self storeOriginalImplementation:existing selector:selector class:class];
        }
    } else {
        struct objc_method_description description = protocol_getMethodDescription(@protocol(UIApplicationDelegate), selector, NO, YES);
        UA_LDEBUG(@"Adding implementation for %@ class %@", NSStringFromSelector(selector), class);
        class_addMethod(class, selector, implementation, description.types);
    }
}

- (void)unswizzle:(SEL)selector class:(Class)class {

    Method method = class_getInstanceMethod(class, selector);
    IMP originalImplementation = [self originalImplementation:selector class:class];
    if (originalImplementation) {
        UA_LDEBUG(@"Unswizzling implementation for %@ class %@", NSStringFromSelector(selector), class);
        method_setImplementation(method, originalImplementation);
        [self.originalMethods[NSStringFromClass(class)] removeObjectForKey:NSStringFromSelector(selector)];
    } else {
        UA_LDEBUG(@"No original implementation to unswizzle for %@ class %@", NSStringFromSelector(selector), class);
    }
}

- (void)storeOriginalImplementation:(IMP)implementation selector:(SEL)selector class:(Class)class {
    NSString *selectorString = NSStringFromSelector(selector);
    NSString *classString = NSStringFromClass(class);

    if (!self.originalMethods[classString]) {
        self.originalMethods[classString] = [NSMutableDictionary dictionary];
    }

    self.originalMethods[classString][selectorString] = [NSValue valueWithPointer:implementation];
}

- (IMP)originalImplementation:(SEL)selector class:(Class)class {
    NSString *selectorString = NSStringFromSelector(selector);
    NSString *classString = NSStringFromClass(class);

    if (!self.originalMethods[classString]) {
        return nil;
    }

    NSValue *value = self.originalMethods[classString][selectorString];
    if (!value) {
        return nil;
    }

    IMP implementation;
    [value getValue:&implementation];
    return implementation;
}


#pragma mark -
#pragma mark UNUserNotificationCenterDelegate swizzled methods

void UserNotificationCenterWillPresentNotificationWithCompletionHandler(id self, SEL _cmd, UNUserNotificationCenter *notificationCenter, UNNotification *notification, void (^handler)(UNNotificationPresentationOptions)) {

    __block UNNotificationPresentationOptions mergedPresentationOptions;

    __block NSUInteger resultCount = 0;
    __block NSUInteger expectedCount = 1;


    IMP original = [instance_ originalImplementation:_cmd class:[self class]];
    if (original) {
        expectedCount = 2;

        __block BOOL completionHandlerCalled = NO;
        void (^completionHandler)(UNNotificationPresentationOptions) = ^(UNNotificationPresentationOptions options) {

            // Make sure the app's completion handler is called on the main queue
            dispatch_async(dispatch_get_main_queue(), ^{
                if (completionHandlerCalled) {
                    UA_LERR(@"Completion handler called multiple times.");
                    return;
                }

                mergedPresentationOptions |= options;

                completionHandlerCalled = YES;
                resultCount++;

                if (expectedCount == resultCount) {
                    handler(mergedPresentationOptions);
                }
            });
        };

        ((void(*)(id, SEL, UNUserNotificationCenter *, UNNotification *, void (^)(UNNotificationPresentationOptions)))original)(self, _cmd, notificationCenter, notification, completionHandler);
    }


    // Call UAPush
    [[UAirship push] userNotificationCenter:notificationCenter
                    willPresentNotification:notification
                      withCompletionHandler:^(UNNotificationPresentationOptions options) {

                          // Make sure the app's completion handler is called on the main queue
                          dispatch_async(dispatch_get_main_queue(), ^{
                              mergedPresentationOptions |= options;

                              resultCount++;
                              
                              if (expectedCount == resultCount) {
                                  handler(mergedPresentationOptions);
                              }
                          });
                      }];
}

void UserNotificationCenterDidReceiveNotificationResponseWithCompletionHandler(id self, SEL _cmd, UNUserNotificationCenter *notificationCenter, UNNotificationResponse *response, void (^handler)()) {

    __block NSUInteger resultCount = 0;
    __block NSUInteger expectedCount = 1;

    IMP original = [instance_ originalImplementation:_cmd class:[self class]];
    if (original) {
        expectedCount = 2;

        __block BOOL completionHandlerCalled = NO;
        void (^completionHandler)() = ^() {

            // Make sure the app's completion handler is called on the main queue
            dispatch_async(dispatch_get_main_queue(), ^{
                if (completionHandlerCalled) {
                    UA_LERR(@"Completion handler called multiple times.");
                    return;
                }


                completionHandlerCalled = YES;
                resultCount++;

                if (expectedCount == resultCount) {
                    handler();
                }
            });
        };

        ((void(*)(id, SEL, UNUserNotificationCenter *, UNNotificationResponse *, void (^)()))original)(self, _cmd, notificationCenter, response, completionHandler);
    }

    // Call UAPush
    [[UAirship push] userNotificationCenter:notificationCenter
                    didReceiveNotificationResponse:response
                      withCompletionHandler:^() {

                          // Make sure we call it on the main queue
                          dispatch_async(dispatch_get_main_queue(), ^{
                              resultCount++;

                              if (expectedCount == resultCount) {
                                  handler();
                              }
                          });
                      }];

}

#pragma mark -
#pragma mark UNUserNotificationCenter swizzled methods


void UserNotificationCenterSetDelegate(id self, SEL _cmd, id<UNUserNotificationCenterDelegate>delegate) {
    id previousDelegate = [UNUserNotificationCenter currentNotificationCenter].delegate;
    if (previousDelegate) {
        [instance_ unswizzleNotificationCenterDelegate:previousDelegate];
    }

    // Call through to original setter
    IMP original = [instance_ originalImplementation:_cmd class:[UNUserNotificationCenter class]];
    if (original) {
        ((void(*)(id, SEL, id))original)(self, _cmd, delegate);
    }

    if (!delegate) {
        // set our dummy delegate back
        [UNUserNotificationCenter currentNotificationCenter].delegate = instance_.dummyNotificationDelegate;
    } else {
        [instance_ swizzleNotificationCenterDelegate:delegate];
    }
}

#pragma mark -
#pragma mark App delegate (UIApplicationDelegate) swizzled methods

void ApplicationDidReceiveRemoteNotification(id self, SEL _cmd, UIApplication *application, NSDictionary *userInfo) {
    [[UAirship push] appReceivedRemoteNotification:userInfo applicationState:application.applicationState];

    IMP original = [instance_ originalImplementation:_cmd class:[self class]];
    if (original) {
        ((void(*)(id, SEL, UIApplication *, NSDictionary*))original)(self, _cmd, application, userInfo);
    }
}

void ApplicationDidRegisterForRemoteNotificationsWithDeviceToken(id self, SEL _cmd, UIApplication *application, NSData *deviceToken) {
    [[UAirship push] appRegisteredForRemoteNotificationsWithDeviceToken:deviceToken];

    IMP original = [instance_ originalImplementation:_cmd class:[self class]];
    if (original) {
        ((void(*)(id, SEL, UIApplication *, NSData*))original)(self, _cmd, application, deviceToken);
    }
}

void ApplicationDidRegisterUserNotificationSettings(id self, SEL _cmd, UIApplication *application, UIUserNotificationSettings *settings) {
    [[UAirship push] appRegisteredUserNotificationSettings];

    IMP original = [instance_ originalImplementation:_cmd class:[self class]];
    if (original) {
        ((void(*)(id, SEL, UIApplication *, UIUserNotificationSettings*))original)(self, _cmd, application, settings);
    }
}

void ApplicationDidFailToRegisterForRemoteNotificationsWithError(id self, SEL _cmd, UIApplication *application, NSError *error) {
    UA_LERR(@"Application failed to register for remote notifications with error: %@", error);

    IMP original = [instance_ originalImplementation:_cmd class:[self class]];
    if (original) {
        ((void(*)(id, SEL, UIApplication *, NSError*))original)(self, _cmd, application, error);
    }
}

void ApplicationDidReceiveRemoteNotificationFetchCompletionHandler(id self,
                                                                   SEL _cmd,
                                                                   UIApplication *application,
                                                                   NSDictionary *userInfo,
                                                                   void (^handler)(UIBackgroundFetchResult)) {

    __block NSUInteger resultCount = 0;
    __block NSUInteger expectedCount = 1;
    __block UIBackgroundFetchResult fetchResult = UIBackgroundFetchResultNoData;

    IMP original = [instance_ originalImplementation:_cmd class:[self class]];
    if (original) {
        expectedCount = 2;
        __block BOOL completionHandlerCalled = NO;

        void (^completionHandler)(UIBackgroundFetchResult) = ^(UIBackgroundFetchResult result) {

            // Make sure the app's completion handler is called on the main queue
            dispatch_async(dispatch_get_main_queue(), ^{
                if (completionHandlerCalled) {
                    UA_LERR(@"Completion handler called multiple times.");
                    return;
                }

                completionHandlerCalled = YES;
                resultCount++;

                // Merge the UIBackgroundFetchResults. If final fetchResult is not already UIBackgroundFetchResultNewData
                // and the current result is not UIBackgroundFetchResultNoData, then set the fetchResult to result
                // (should be either UIBackgroundFetchFailed or UIBackgroundFetchResultNewData)
                if (fetchResult != UIBackgroundFetchResultNewData && result != UIBackgroundFetchResultNoData) {
                    fetchResult = result;
                }

                if (expectedCount == resultCount) {
                    handler(fetchResult);
                }
            });
        };

        // Call the original implementation
        ((void(*)(id, SEL, UIApplication *, NSDictionary *, void (^)(UIBackgroundFetchResult)))original)(self, _cmd, application, userInfo, completionHandler);
    }

    // Our completion handler is called by the action framework on the main queue
    [[UAirship push] appReceivedRemoteNotification:userInfo
                                  applicationState:application.applicationState
                            fetchCompletionHandler:^(UIBackgroundFetchResult result) {
                                resultCount++;

                                // Merge the UIBackgroundFetchResults. If final fetchResult is not already UIBackgroundFetchResultNewData
                                // and the current result is not UIBackgroundFetchResultNoData, then set the fetchResult to result
                                // (should be either UIBackgroundFetchFailed or UIBackgroundFetchResultNewData)
                                if (fetchResult != UIBackgroundFetchResultNewData && result != UIBackgroundFetchResultNoData) {
                                    fetchResult = result;
                                }

                                if (expectedCount == resultCount) {
                                    handler(fetchResult);
                                }
                            }];
}


void ApplicationHandleActionWithIdentifierForRemoteNotificationCompletionHandler(id self,
                                                                                 SEL _cmd,
                                                                                 UIApplication *application,
                                                                                 NSString *identifier,
                                                                                 NSDictionary *userInfo,
                                                                                 void (^handler)()) {
    __block NSUInteger resultCount = 0;
    __block NSUInteger expectedCount = 1;

    IMP original = [instance_ originalImplementation:_cmd class:[self class]];
    if (original) {
        expectedCount = 2;

        __block BOOL completionHandlerCalled = NO;
        void (^completionHandler)() = ^() {

            // Make sure the app's completion handler is called on the main queue
            dispatch_async(dispatch_get_main_queue(), ^{
                if (completionHandlerCalled) {
                    UA_LERR(@"Completion handler called multiple times.");
                    return;
                }

                completionHandlerCalled = YES;
                resultCount++;

                if (expectedCount == resultCount) {
                    handler();
                }
            });

        };

        // Call the original implementation
        ((void(*)(id, SEL, UIApplication *, NSString *, NSDictionary *, void (^)()))original)(self, _cmd, application, identifier, userInfo, completionHandler);
    }

    // Our completion handler is called by the action framework on the main queue
    [[UAirship push] appReceivedActionWithIdentifier:identifier
                                        notification:userInfo
                                    applicationState:application.applicationState
                                   completionHandler:^{
                                       resultCount++;

                                       if (expectedCount == resultCount) {
                                           handler();
                                       }
                                   }];
}

void ApplicationHandleActionWithIdentifierForRemoteNotificationWithResponseInfoCompletionHandler(id self,
                                                                                                 SEL _cmd,
                                                                                                 UIApplication *application,
                                                                                                 NSString *identifier,
                                                                                                 NSDictionary *userInfo,
                                                                                                 NSDictionary *responseInfo,
                                                                                                 void (^handler)()) {
    __block NSUInteger resultCount = 0;
    __block NSUInteger expectedCount = 1;

    IMP original = [instance_ originalImplementation:_cmd class:[self class]];
    if (original) {
        expectedCount = 2;

        __block BOOL completionHandlerCalled = NO;
        void (^completionHandler)() = ^() {

            // Make sure the app's completion handler is called on the main queue
            dispatch_async(dispatch_get_main_queue(), ^{
                if (completionHandlerCalled) {
                    UA_LERR(@"Completion handler called multiple times.");
                    return;
                }

                completionHandlerCalled = YES;
                resultCount++;

                if (expectedCount == resultCount) {
                    handler();
                }
            });

        };

        // Call the original implementation
        ((void(*)(id, SEL, UIApplication *, NSString *, NSDictionary *, NSDictionary *, void (^)()))original)(self, _cmd, application, identifier, userInfo, responseInfo, completionHandler);
    }

    // Our completion handler is called by the action framework on the main queue
    [[UAirship push] appReceivedActionWithIdentifier:identifier
                                        notification:userInfo
                                        responseInfo:responseInfo
                                    applicationState:application.applicationState
                                   completionHandler:^{
                                       resultCount++;
                                       
                                       if (expectedCount == resultCount) {
                                           handler();
                                       }
                                   }];
}

@end
