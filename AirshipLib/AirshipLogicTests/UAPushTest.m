/*
 Copyright 2009-2015 Urban Airship Inc. All rights reserved.

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

#import <XCTest/XCTest.h>
#import <OCMock/OCMock.h>
#import <OCMock/OCMConstraint.h>
#import "UAPush+Internal.h"
#import "UAirship.h"
#import "UAAnalytics.h"
#import "UAirship+Internal.h"
#import "UAActionRunner+Internal.h"
#import "UAActionRegistry+Internal.h"
#import "UAUtils.h"
#import "UAUser.h"
#import "UAChannelRegistrationPayload.h"
#import "UAChannelRegistrar.h"
#import "UAEvent.h"
#import "NSObject+HideClass.h"
#import "UAInteractiveNotificationEvent.h"
#import "UAUserNotificationCategories+Internal.h"
#import "UAMutableUserNotificationAction.h"
#import "UAMutableUserNotificationCategory.h"
#import "UAPreferenceDataStore.h"
#import "UAConfig.h"
#import "UATagGroupsAPIClient.h"

@interface UAPushTest : XCTestCase
@property (nonatomic, strong) id mockedApplication;
@property (nonatomic, strong) id mockedChannelRegistrar;
@property (nonatomic, strong) id mockedAirship;
@property (nonatomic, strong) id mockedAnalytics;
@property (nonatomic, strong) id mockedPushDelegate;
@property (nonatomic, strong) id mockRegistrationDelegate;
@property (nonatomic, strong) id mockActionRunner;
@property (nonatomic, strong) id mockUAUtils;
@property (nonatomic, strong) id mockUAUser;
@property (nonatomic, strong) id mockUIUserNotificationSettings;
@property (nonatomic, strong) id mockDefaultUserNotificationCategories;
@property (nonatomic, strong) id mockTagGroupsAPIClient;

@property (nonatomic, strong) UAPush *push;
@property (nonatomic, strong) UAPreferenceDataStore *dataStore;

@property (nonatomic, strong) NSDictionary *notification;
@property (nonatomic, strong) NSMutableDictionary *addTagGroups;
@property (nonatomic, strong) NSMutableDictionary *removeTagGroups;
@property (nonatomic, strong) UAHTTPRequest *channelTagsFailureRequest;

@end

@implementation UAPushTest

NSString *validDeviceToken = @"0123456789abcdef0123456789abcdef0123456789abcdef0123456789abcdef0123456789abcdef";

void (^updateChannelTagsSuccessDoBlock)(NSInvocation *);
void (^updateChannelTagsFailureDoBlock)(NSInvocation *);

- (void)setUp {
    [super setUp];
    self.dataStore = [UAPreferenceDataStore preferenceDataStoreWithKeyPrefix:@"uapush.test."];
    self.push =  [UAPush pushWithConfig:[UAConfig defaultConfig] dataStore:self.dataStore];

    self.notification = @{
                          @"aps": @{
                                  @"alert": @"sample alert!",
                                  @"badge": @2,
                                  @"sound": @"cat",
                                  @"category": @"notificationCategory"
                                  },
                          @"com.urbanairship.interactive_actions": @{
                                  @"backgroundIdentifier": @{
                                          @"backgroundAction": @"backgroundActionValue"
                                          },
                                  @"foregroundIdentifier": @{
                                          @"foregroundAction": @"foregroundActionValue",
                                          @"otherForegroundAction": @"otherForegroundActionValue"

                                          },
                                  },
                          @"someActionKey": @"someActionValue",
                          };

    self.addTagGroups = [[NSMutableDictionary alloc] init];
    NSMutableDictionary *tagsToAdd = [NSMutableDictionary dictionary];
    NSArray *addTagsArray = @[@"tag1", @"tag2", @"tag3"];
    [tagsToAdd setValue:addTagsArray forKey:@"tag_group"];
    self.addTagGroups = tagsToAdd;

    self.removeTagGroups = [[NSMutableDictionary alloc] init];
    NSMutableDictionary *tagsToRemove = [NSMutableDictionary dictionary];
    NSArray *removeTagsArray = @[@"tag3", @"tag4", @"tag5"];
    [tagsToRemove setValue:removeTagsArray forKey:@"tag_group"];
    self.removeTagGroups = tagsToRemove;

    // Set up a mocked application
    self.mockedApplication = [OCMockObject niceMockForClass:[UIApplication class]];
    [[[self.mockedApplication stub] andReturn:self.mockedApplication] sharedApplication];

    // Set up mocked UIUserNotificationSettings
    self.mockUIUserNotificationSettings = [OCMockObject niceMockForClass:[UIUserNotificationSettings class]];

    // Set up a mocked device api client
    self.mockedChannelRegistrar = [OCMockObject niceMockForClass:[UAChannelRegistrar class]];
    self.push.channelRegistrar.delegate = nil;
    self.push.channelRegistrar = self.mockedChannelRegistrar;

    self.mockedAnalytics = [OCMockObject niceMockForClass:[UAAnalytics class]];

    self.mockedAirship =[OCMockObject niceMockForClass:[UAirship class]];
    [[[self.mockedAirship stub] andReturn:self.mockedAirship] shared];
    [[[self.mockedAirship stub] andReturn:self.mockedAnalytics] analytics];
    [[[self.mockedAirship stub] andReturn:self.dataStore] dataStore];

    self.mockedPushDelegate = [OCMockObject niceMockForProtocol:@protocol(UAPushNotificationDelegate)];
    self.push.pushNotificationDelegate = self.mockedPushDelegate;

    self.mockRegistrationDelegate = [OCMockObject mockForProtocol:@protocol(UARegistrationDelegate)];

    self.mockActionRunner = [OCMockObject mockForClass:[UAActionRunner class]];

    self.mockUAUtils = [OCMockObject niceMockForClass:[UAUtils class]];
    [[[self.mockUAUtils stub] andReturn:@"someDeviceID"] deviceID];

    self.mockUAUser = [OCMockObject niceMockForClass:[UAUser class]];
    [[[self.mockedAirship stub] andReturn:self.mockUAUser] inboxUser];
    [[[self.mockUAUser stub] andReturn:@"someUser"] username];

    self.mockDefaultUserNotificationCategories = [OCMockObject niceMockForClass:[UAUserNotificationCategories class]];

    self.push.registrationDelegate = self.mockRegistrationDelegate;

    self.mockTagGroupsAPIClient = [OCMockObject niceMockForClass:[UATagGroupsAPIClient class]];
    self.push.tagGroupsAPIClient = self.mockTagGroupsAPIClient;

    self.channelTagsFailureRequest = [[UAHTTPRequest alloc] init];

    updateChannelTagsSuccessDoBlock = ^(NSInvocation *invocation) {
        void *arg;
        [invocation getArgument:&arg atIndex:5];
        UATagGroupsAPIClientSuccessBlock successBlock = (__bridge UATagGroupsAPIClientSuccessBlock)arg;
        successBlock();
    };

    updateChannelTagsFailureDoBlock = ^(NSInvocation *invocation) {
        void *arg;
        [invocation getArgument:&arg atIndex:6];
        UATagGroupsAPIClientFailureBlock failureBlock = (__bridge UATagGroupsAPIClientFailureBlock)arg;
        failureBlock(self.channelTagsFailureRequest);
    };
}

- (void)tearDown {
    self.push.pushNotificationDelegate = nil;
    self.push.registrationDelegate = nil;

    [self.dataStore removeAll];

    [self.mockedApplication stopMocking];
    [self.mockedChannelRegistrar stopMocking];
    [self.mockedAnalytics stopMocking];
    [self.mockedAirship stopMocking];
    [self.mockedPushDelegate stopMocking];
    [self.mockRegistrationDelegate stopMocking];
    [self.mockActionRunner stopMocking];
    [self.mockUAUtils stopMocking];
    [self.mockUAUser stopMocking];
    [self.mockUIUserNotificationSettings stopMocking];
    [self.mockDefaultUserNotificationCategories stopMocking];
    [self.mockTagGroupsAPIClient stopMocking];

    // We hide this class in a few tests. Its only available on iOS8.
    [UIUserNotificationSettings revealClass];

    [super tearDown];
}

- (void)testSetDeviceToken {
    self.push.deviceToken = nil;

    self.push.deviceToken = @"invalid characters";

    XCTAssertNil(self.push.deviceToken, @"setDeviceToken should ignore device tokens with invalid characters.");


    self.push.deviceToken = validDeviceToken;
    XCTAssertEqualObjects(validDeviceToken, self.push.deviceToken, @"setDeviceToken should set tokens with valid characters");

    self.push.deviceToken = nil;
    XCTAssertNil(self.push.deviceToken,
                 @"setDeviceToken should allow a nil device token.");

    self.push.deviceToken = @"";
    XCTAssertEqualObjects(@"", self.push.deviceToken,
                          @"setDeviceToken should do nothing to an empty string");
}

- (void)testAutoBadgeEnabled {
    self.push.autobadgeEnabled = true;
    XCTAssertTrue(self.push.autobadgeEnabled, @"autobadgeEnabled should be enabled when set to YES");
    XCTAssertTrue([self.dataStore boolForKey:UAPushBadgeSettingsKey],
                  @"autobadgeEnabled should be stored in standardUserDefaults");

    self.push.autobadgeEnabled = NO;
    XCTAssertFalse(self.push.autobadgeEnabled, @"autobadgeEnabled should be disabled when set to NO");
    XCTAssertFalse([self.dataStore boolForKey:UAPushBadgeSettingsKey],
                   @"autobadgeEnabled should be stored in standardUserDefaults");
}

- (void)testAlias {
    self.push.alias = @"some-alias";
    XCTAssertEqualObjects(@"some-alias", self.push.alias, @"alias is not being set correctly");
    XCTAssertEqualObjects(@"some-alias", [self.dataStore stringForKey:UAPushAliasSettingsKey],
                          @"alias should be stored in standardUserDefaults");

    self.push.alias = nil;
    XCTAssertNil(self.push.alias, @"alias should be able to be cleared");
    XCTAssertNil([self.dataStore stringForKey:UAPushAliasSettingsKey],
                 @"alias should be able to be cleared in standardUserDefaults");

    self.push.alias = @"";
    XCTAssertEqualObjects(@"", self.push.alias, @"alias is not being set correctly");
    XCTAssertEqualObjects(@"", [self.dataStore stringForKey:UAPushAliasSettingsKey],
                          @"alias should be stored in standardUserDefaults");

    self.push.alias = @"   ";
    XCTAssertEqualObjects(@"", self.push.alias, @"alias is not being trimmed and set correctly");
    XCTAssertEqualObjects(@"", [self.dataStore stringForKey:UAPushAliasSettingsKey],
                          @"alias should be stored in standardUserDefaults");

    self.push.alias = @"   a   ";
    XCTAssertEqualObjects(@"a", self.push.alias, @"alias is not being trimmed and set correctly");
    XCTAssertEqualObjects(@"a", [self.dataStore stringForKey:UAPushAliasSettingsKey],
                          @"alias should be stored in standardUserDefaults");
}

- (void)testTags {
    NSArray *tags = @[@"tag-one", @"tag-two"];
    self.push.tags = tags;

    XCTAssertEqual((NSUInteger)2, self.push.tags.count, @"should of added 2 tags");
    XCTAssertEqualObjects(tags, self.push.tags, @"tags are not stored correctly");
    XCTAssertEqualObjects([self.dataStore valueForKey:UAPushTagsSettingsKey], self.push.tags,
                          @"tags are not stored correctly in standardUserDefaults");

    self.push.tags = @[];
    XCTAssertEqual((NSUInteger)0, self.push.tags.count, @"tags should return an empty array even when set to nil");
    XCTAssertEqual((NSUInteger)0, [[self.dataStore valueForKey:UAPushTagsSettingsKey] count],
                   @"tags are not being cleared in standardUserDefaults");
}

/**
 * Tests tag setting when tag contains white space
 */
- (void)testSetTagsWhitespaceRemoval {
    NSArray *tags = @[@"   tag-one   ", @"tag-two   "];
    NSArray *tagsNoSpaces = @[@"tag-one", @"tag-two"];
    [self.push setTags:tags];

    XCTAssertEqualObjects(tagsNoSpaces, self.push.tags, @"whitespace was not trimmed from tags");
}

/**
 * Tests tag setting when tag consists entirely of whitespace
 */
- (void)testSetTagWhitespaceOnly {
    NSArray *tags = @[@" "];
    [self.push setTags:tags];

    XCTAssertNotEqualObjects(tags, self.push.tags, @"tag with whitespace only should not set");
}

/**
 * Tests tag setting when tag has minimum acceptable length
 */
- (void)testSetTagsMinTagSize {
    NSArray *tags = @[@"1"];
    [self.push setTags:tags];

    XCTAssertEqualObjects(tags, self.push.tags, @"tag with minimum character should set");
}

/**
 * Tests tag setting when tag has maximum acceptable length
 */
- (void)testSetTagsMaxTagSize {
    NSArray *tags = @[[@"" stringByPaddingToLength:127 withString: @"." startingAtIndex:0]];
    [self.push setTags:tags];

    XCTAssertEqualObjects(tags, self.push.tags, @"tag with maximum characters should set");
}

/**
 * Tests tag setting when tag has multi-byte characters
 */
- (void)testSetTagsMultiByteCharacters {
    NSArray *tags = @[@"함수 목록"];
    [self.push setTags:tags];

    XCTAssertEqualObjects(tags, self.push.tags, @"tag with multi-byte characters should set");
}

/**
 * Tests tag setting when tag has multi-byte characters and minimum length
 */
- (void)testMinLengthMultiByteCharacters {
    NSArray *tags = @[@"함"];
    [self.push setTags:tags];

    XCTAssertEqualObjects(tags, self.push.tags, @"tag with minimum multi-byte characters should set");
}

/**
 * Tests tag setting when tag has multi-byte characters and maximum length
 */
- (void)testMaxLengthMultiByteCharacters {
    NSArray *tags = @[[@"" stringByPaddingToLength:127 withString: @"함" startingAtIndex:0]];;
    [self.push setTags:tags];

    XCTAssertEqualObjects(tags, self.push.tags, @"tag with maximum multi-byte characters should set");
}

/**
 * Tests tag setting when tag has greater than maximum acceptable length
 */
- (void)testSetTagsOverMaxTagSizeRemoval {
    NSArray *tags = @[[@"" stringByPaddingToLength:128 withString: @"." startingAtIndex:0]];
    [self.push setTags:tags];

    XCTAssertNotEqualObjects(tags, self.push.tags, @"tag with 128 characters should not set");
}

- (void)testAddTags {
    self.push.tags = @[];

    [self.push addTags:@[@"tag-one", @"tag-two"]];
    XCTAssertEqualObjects([NSSet setWithArray:(@[@"tag-one", @"tag-two"])], [NSSet setWithArray:self.push.tags],
                          @"Add tags to current device fails when no existing tags exist");

    // Try to add same tags again
    [self.push addTags:@[@"tag-one", @"tag-two"]];
    XCTAssertEqual((NSUInteger)2, self.push.tags.count, @"Add tags should not add duplicate tags");


    // Try to add a new set of tags, with one of the tags being unique
    [self.push addTags:@[@"tag-one", @"tag-three"]];

    XCTAssertEqual((NSUInteger)3, self.push.tags.count,
                   @"Add tags should add unique tags even if some of them are duplicate");

    XCTAssertEqualObjects([NSSet setWithArray:(@[@"tag-one", @"tag-two", @"tag-three"])], [NSSet setWithArray:self.push.tags],
                          @"Add tags should add unique tags even if some of them are duplicate");

    // Try to add an nil set of tags
    XCTAssertNoThrow([self.push addTags:[NSArray array]],
                     @"Should not throw when adding an empty tag array");
}

- (void)testAddTag {
    self.push.tags = @[];

    [self.push addTag:@"tag-one"];
    XCTAssertEqualObjects((@[@"tag-one"]), self.push.tags,
                          @"Add tag to current device fails when no existing tags exist");

    // Try to add same tag again
    [self.push addTag:@"tag-one"];
    XCTAssertEqual((NSUInteger)1, self.push.tags.count, @"Add tag should not add duplicate tags");

    // Add a new tag
    [self.push addTag:@"tag-two"];
    XCTAssertEqualObjects((@[@"tag-one", @"tag-two"]), self.push.tags,
                          @"Adding another tag to tags fails");
}

- (void)testRemoveTag {
    self.push.tags = @[];
    XCTAssertNoThrow([self.push removeTag:@"some-tag"],
                     @"Should not throw when removing a tag when tags are empty");

    self.push.tags = @[@"some-tag", @"some-other-tag"];
    XCTAssertNoThrow([self.push removeTag:@"some-not-found-tag"],
                     @"Should not throw when removing a tag that does not exist");

    [self.push removeTag:@"some-tag"];
    XCTAssertEqualObjects((@[@"some-other-tag"]), self.push.tags,
                          @"Remove tag from device should actually remove the tag");
}

- (void)testRemoveTags {
    self.push.tags = @[];

    XCTAssertNoThrow([self.push removeTags:@[@"some-tag"]],
                     @"Should not throw when removing tags when current tags are empty");

    self.push.tags = @[@"some-tag", @"some-other-tag"];
    XCTAssertNoThrow([self.push removeTags:@[@"some-not-found-tag"]],
                     @"Should not throw when removing tags that do not exist");

    [self.push removeTags:@[@"some-tag"]];
    XCTAssertEqualObjects((@[@"some-other-tag"]), self.push.tags,
                          @"Remove tags from device should actually remove the tag");
}

/**
 * Test enabling userPushNotificationsEnabled on < iOS8 saves its settings
 * to NSUserDefaults and updates apns registration.
 */
- (void)testUserPushNotificationsEnabled {
    [UIUserNotificationSettings hideClass];

    self.push.userPushNotificationsEnabled = NO;

    // Make sure push is set to NO
    XCTAssertFalse(self.push.userPushNotificationsEnabled, @"userPushNotificationsEnabled should default to NO");

    [[self.mockedApplication expect] registerForRemoteNotificationTypes:self.push.userNotificationTypes];

    self.push.userPushNotificationsEnabled = YES;

    XCTAssertTrue(self.push.userPushNotificationsEnabled,
                  @"userPushNotificationsEnabled should be enabled when set to YES");

    XCTAssertTrue([self.dataStore boolForKey:UAUserPushNotificationsEnabledKey],
                  @"userPushNotificationsEnabled should be stored in standardUserDefaults");

    XCTAssertNoThrow([self.mockedApplication verify],
                     @"userPushNotificationsEnabled should register for remote notifications");
}


/**
 * Test enabling userPushNotificationsEnabled on >= iOS8 saves its settings
 * to NSUserDefaults and updates apns registration.
 */
- (void)testUserPushNotificationsEnabledIOS8 {
    self.push.userPushNotificationsEnabled = NO;

    NSSet *expectedCategories = self.push.allUserNotificationCategories;

    // Make sure push is set to NO
    XCTAssertFalse(self.push.userPushNotificationsEnabled, @"userPushNotificationsEnabled should default to NO");

    UIUserNotificationSettings *expected = [UIUserNotificationSettings settingsForTypes:self.push.userNotificationTypes
                                                                             categories:expectedCategories];

    [[self.mockedApplication expect] registerUserNotificationSettings:expected];
    self.push.userPushNotificationsEnabled = YES;

    XCTAssertTrue(self.push.userPushNotificationsEnabled,
                  @"userPushNotificationsEnabled should be enabled when set to YES");

    XCTAssertTrue([self.dataStore boolForKey:UAUserPushNotificationsEnabledKey],
                  @"userPushNotificationsEnabled should be stored in standardUserDefaults");

    XCTAssertNoThrow([self.mockedApplication verify],
                     @"userPushNotificationsEnabled should register for remote notifications");
}

/**
 * Test disabling userPushNotificationsEnabled on < iOS8 saves its settings
 * to NSUserDefaults and updates registration.
 */
- (void)testUserPushNotificationsDisabled {
    [UIUserNotificationSettings hideClass];

    self.push.deviceToken = validDeviceToken;
    self.push.userPushNotificationsEnabled = YES;
    self.push.shouldUpdateAPNSRegistration = NO;


    [[self.mockedApplication expect] registerForRemoteNotificationTypes:UIRemoteNotificationTypeNone];
    [[[self.mockedApplication stub] andReturnValue:OCMOCK_VALUE((NSUInteger)30)] beginBackgroundTaskWithExpirationHandler:OCMOCK_ANY];


    self.push.userPushNotificationsEnabled = NO;

    XCTAssertFalse(self.push.userPushNotificationsEnabled,
                   @"userPushNotificationsEnabled should be disabled when set to NO");

    XCTAssertFalse([self.dataStore boolForKey:UAUserPushNotificationsEnabledKey],
                   @"userPushNotificationsEnabled should be stored in standardUserDefaults");

    XCTAssertNoThrow([self.mockedApplication verify],
                     @"userPushNotificationsEnabled should unregister for remote notifications");
}

/**
 * Test requireSettingsAppToDisableUserNotifications always returns NO on iOS7
 */
-(void)testRequireSettingsAppToDisableUserNotificationsIOS7 {
    // iOS7 registration
    [UIUserNotificationSettings hideClass];

    // Defaults to NO
    XCTAssertFalse(self.push.requireSettingsAppToDisableUserNotifications);

    // Try to set it to YES
    self.push.requireSettingsAppToDisableUserNotifications = YES;

    // Should still be NO
    XCTAssertFalse(self.push.requireSettingsAppToDisableUserNotifications);
}

/**
 * Test requireSettingsAppToDisableUserNotifications defaults to YES on
 * iOS8+ and prevents userPushNotificationsEnabled from being disabled,
 * once its enabled.
 */
-(void)testRequireSettingsAppToDisableUserNotificationsIOS8 {
    // Defaults to YES
    XCTAssertTrue(self.push.requireSettingsAppToDisableUserNotifications);

    // Verify it can be disabled
    self.push.requireSettingsAppToDisableUserNotifications = NO;
    XCTAssertFalse(self.push.requireSettingsAppToDisableUserNotifications);

    // Set up push for user notifications
    self.push.userPushNotificationsEnabled = YES;
    self.push.deviceToken = validDeviceToken;
    self.push.shouldUpdateAPNSRegistration = NO;

    // Prevent disabling userPushNotificationsEnabled
    self.push.requireSettingsAppToDisableUserNotifications = YES;

    // Verify we don't try to register when attempting to disable userPushNotificationsEnabled
    [[self.mockedApplication reject] registerUserNotificationSettings:OCMOCK_ANY];

    self.push.userPushNotificationsEnabled = NO;

    // Should still be YES
    XCTAssertTrue(self.push.userPushNotificationsEnabled);

    // Verify we did not update user notificaiton settings
    [self.mockedApplication verify];
}

/**
 * Test disabling userPushNotificationsEnabled on >= iOS8 saves its settings
 * to NSUserDefaults and updates registration.
 */
- (void)testUserPushNotificationsDisabledIOS8 {
    self.push.userPushNotificationsEnabled = YES;
    self.push.deviceToken = validDeviceToken;
    self.push.shouldUpdateAPNSRegistration = NO;

    // Make sure we have previously registered types
    UIUserNotificationSettings *settings = [UIUserNotificationSettings settingsForTypes:UIUserNotificationTypeBadge categories:nil];
    [[[self.mockedApplication stub] andReturn:settings] currentUserNotificationSettings];


    // Make sure push is set to YES
    XCTAssertTrue(self.push.userPushNotificationsEnabled, @"userPushNotificationsEnabled should default to YES");

    // Add a device token so we get a device api callback
    [[self.mockedChannelRegistrar expect] registerWithChannelID:OCMOCK_ANY
                                                channelLocation:OCMOCK_ANY
                                                    withPayload:OCMOCK_ANY
                                                     forcefully:NO];


    UIUserNotificationSettings *expected = [UIUserNotificationSettings settingsForTypes:UIUserNotificationTypeNone
                                                                             categories:nil];
    [[self.mockedApplication expect] registerUserNotificationSettings:expected];

    [[[self.mockedApplication stub] andReturnValue:OCMOCK_VALUE((NSUInteger)30)] beginBackgroundTaskWithExpirationHandler:OCMOCK_ANY];

    self.push.requireSettingsAppToDisableUserNotifications = NO;
    self.push.userPushNotificationsEnabled = NO;

    XCTAssertFalse(self.push.userPushNotificationsEnabled,
                   @"userPushNotificationsEnabled should be disabled when set to NO");

    XCTAssertFalse([self.dataStore boolForKey:UAUserPushNotificationsEnabledKey],
                   @"userPushNotificationsEnabled should be stored in standardUserDefaults");

    XCTAssertNoThrow([self.mockedApplication verify],
                     @"userPushNotificationsEnabled should unregister for remote notifications");
}

/**
 * Test enabling or disabling backgroundPushNotificationsEnabled saves its settings
 * to NSUserDefaults and triggers a channel registration update.
 */
- (void)testBackgroundPushNotificationsEnabled {
    self.push.userPushNotificationsEnabled = YES;
    self.push.backgroundPushNotificationsEnabled = NO;

    // Add a device token so we get a device api callback
    [[self.mockedChannelRegistrar expect] registerWithChannelID:OCMOCK_ANY
                                                channelLocation:OCMOCK_ANY
                                                    withPayload:OCMOCK_ANY
                                                     forcefully:NO];

    self.push.backgroundPushNotificationsEnabled = YES;

    XCTAssertTrue([self.dataStore boolForKey:UABackgroundPushNotificationsEnabledKey],
                  @"backgroundPushNotificationsEnabled should be stored in standardUserDefaults");

    self.push.backgroundPushNotificationsEnabled = NO;
    XCTAssertFalse([self.dataStore boolForKey:UABackgroundPushNotificationsEnabledKey],
                   @"backgroundPushNotificationsEnabled should be stored in standardUserDefaults");

}

/**
 * Test enabling or disabling pushTokenRegistrationEnabled saves its settings
 * to NSUserDefaults and triggers a channel registration update.
 */
- (void)testPushTokenRegistrationEnabled {
    self.push.pushTokenRegistrationEnabled = NO;

    // Add a device token so we get a device api callback
    [[self.mockedChannelRegistrar expect] registerWithChannelID:OCMOCK_ANY
                                                channelLocation:OCMOCK_ANY
                                                    withPayload:OCMOCK_ANY
                                                     forcefully:NO];

    self.push.pushTokenRegistrationEnabled = YES;

    XCTAssertTrue([self.dataStore boolForKey:UAPushTokenRegistrationEnabledKey],
                  @"pushTokenRegistrationEnabled should be stored in standardUserDefaults");

    self.push.pushTokenRegistrationEnabled = NO;
    XCTAssertFalse([self.dataStore boolForKey:UAPushTokenRegistrationEnabledKey],
                   @"pushTokenRegistrationEnabled should be stored in standardUserDefaults");
}

- (void)testSetQuietTime {
    [self.push setQuietTimeStartHour:12 startMinute:30 endHour:14 endMinute:58];

    NSDictionary *quietTime = self.push.quietTime;
    XCTAssertEqualObjects(@"12:30", [quietTime valueForKey:UAPushQuietTimeStartKey],
                          @"Quiet time start is not set correctly");

    XCTAssertEqualObjects(@"14:58", [quietTime valueForKey:UAPushQuietTimeEndKey],
                          @"Quiet time end is not set correctly");

    // Change the time zone
    self.push.timeZone = [NSTimeZone timeZoneForSecondsFromGMT:-3600*3];

    // Make sure the hour and minutes are still the same
    quietTime = self.push.quietTime;
    XCTAssertEqualObjects(@"12:30", [quietTime valueForKey:UAPushQuietTimeStartKey],
                          @"Quiet time start is not set correctly");

    XCTAssertEqualObjects(@"14:58", [quietTime valueForKey:UAPushQuietTimeEndKey],
                          @"Quiet time end is not set correctly");


    // Try to set it to an invalid start hour
    [self.push setQuietTimeStartHour:24 startMinute:30 endHour:14 endMinute:58];

    // Make sure the hour and minutes are still the same
    quietTime = self.push.quietTime;
    XCTAssertEqualObjects(@"12:30", [quietTime valueForKey:UAPushQuietTimeStartKey],
                          @"Quiet time start is not set correctly");

    XCTAssertEqualObjects(@"14:58", [quietTime valueForKey:UAPushQuietTimeEndKey],
                          @"Quiet time end is not set correctly");

    // Try to set it to an invalid end minute
    [self.push setQuietTimeStartHour:12 startMinute:30 endHour:14 endMinute:60];

    // Make sure the hour and minutes are still the same
    quietTime = self.push.quietTime;
    XCTAssertEqualObjects(@"12:30", [quietTime valueForKey:UAPushQuietTimeStartKey],
                          @"Quiet time start is not set correctly");

    XCTAssertEqualObjects(@"14:58", [quietTime valueForKey:UAPushQuietTimeEndKey],
                          @"Quiet time end is not set correctly");
}


- (void)testTimeZone {
    self.push.timeZone = [NSTimeZone timeZoneWithAbbreviation:@"EST"];

    XCTAssertEqualObjects([NSTimeZone timeZoneWithAbbreviation:@"EST"],
                          self.push.timeZone,
                          @"timezone is not being set correctly");

    XCTAssertEqualObjects([[NSTimeZone timeZoneWithAbbreviation:@"EST"] name],
                          [self.dataStore stringForKey:UAPushTimeZoneSettingsKey],
                          @"timezone should be stored in standardUserDefaults");

    // Clear the timezone from preferences
    [self.dataStore removeObjectForKey:UAPushTimeZoneSettingsKey];


    XCTAssertEqualObjects([self.push.defaultTimeZoneForQuietTime abbreviation],
                          [self.push.timeZone abbreviation],
                          @"Timezone should default to defaultTimeZoneForQuietTime");

    XCTAssertNil([self.dataStore stringForKey:UAPushTimeZoneSettingsKey],
                 @"timezone should be able to be cleared in standardUserDefaults");
}

/**
 * Test update apns registration when user notifications are enabled on < iOS8.
 */
- (void)testUpdateAPNSRegistrationUserNotificationsEnabled {

    [UIUserNotificationSettings hideClass];
    self.push.userPushNotificationsEnabled = YES;
    self.push.userNotificationTypes = UIUserNotificationTypeSound;
    self.push.shouldUpdateAPNSRegistration = YES;

    [[self.mockedApplication expect] registerForRemoteNotificationTypes:UIRemoteNotificationTypeSound];
    [self.push updateAPNSRegistration];

    XCTAssertNoThrow([self.mockedApplication verify],
                     @"should register for push notification types when push is enabled");

    XCTAssertFalse(self.push.shouldUpdateAPNSRegistration, @"Updating APNS registration should set shouldUpdateAPNSRegistration to NO");
}

/**s
 * Test update apns registration when user notifications are disabled on < iOS8.
 */
- (void)testUpdateAPNSRegistrationUserNotificationsDisabled {
    [UIUserNotificationSettings hideClass];
    self.push.userPushNotificationsEnabled = NO;
    self.push.userNotificationTypes = UIUserNotificationTypeNone;
    self.push.shouldUpdateAPNSRegistration = YES;

    [[[self.mockedApplication stub] andReturnValue:OCMOCK_VALUE((NSUInteger)30)] beginBackgroundTaskWithExpirationHandler:OCMOCK_ANY];

    [[self.mockedApplication reject] registerForRemoteNotificationTypes:UIRemoteNotificationTypeSound];

    // Add a device token so we get a device api callback
    [[self.mockedChannelRegistrar expect] registerWithChannelID:OCMOCK_ANY
                                                channelLocation:OCMOCK_ANY
                                                    withPayload:OCMOCK_ANY
                                                     forcefully:NO];

    [self.push updateAPNSRegistration];


    XCTAssertNoThrow([self.mockedApplication verify],
                     @"should not register for push notification types when push is disabled");

    XCTAssertNoThrow([self.mockedChannelRegistrar verify],
                     @"should update device registration");

    XCTAssertFalse(self.push.shouldUpdateAPNSRegistration, @"Updating APNS registration should set shouldUpdateAPNSRegistration to NO");
}

/**
 * Test update apns registration when user notifications are enabled on >= iOS8.
 */
- (void)testUpdateAPNSRegistrationUserNotificationsEnabledIOS8 {
    self.push.userPushNotificationsEnabled = YES;
    self.push.shouldUpdateAPNSRegistration = YES;
    [[[self.mockDefaultUserNotificationCategories stub] andReturn:[NSSet set]] defaultCategoriesWithRequireAuth:YES];

    self.push.userNotificationCategories = [NSSet setWithArray:@[[[UIUserNotificationCategory alloc] init]]];

    UIUserNotificationSettings *expected = [UIUserNotificationSettings settingsForTypes:self.push.userNotificationTypes
                                                                             categories:self.push.userNotificationCategories];

    [[self.mockedApplication expect] registerUserNotificationSettings:expected];
    [self.push updateAPNSRegistration];

    XCTAssertNoThrow([self.mockedApplication verify],
                     @"should register for user notification settings when push is enabled");

    XCTAssertFalse(self.push.shouldUpdateAPNSRegistration, @"Updating APNS registration should set shouldUpdateAPNSRegistration to NO");
}

/**
 * Test setting requireAuthorizationForDefaultCategories requests the correct
 * defaults user notification categories.
 */
- (void)testRequireAuthorizationForDefaultCategories {
    self.push.userNotificationCategories = [NSSet set];
    self.push.userPushNotificationsEnabled = YES;

    NSSet *defaultSet = [NSSet setWithArray:@[[[UIUserNotificationCategory alloc] init], [[UIUserNotificationCategory alloc] init]]];
    NSSet *requiredAuthorizationSet = [NSSet setWithArray:@[[[UIUserNotificationCategory alloc] init]]];
    [[[self.mockDefaultUserNotificationCategories stub] andReturn:defaultSet] defaultCategoriesWithRequireAuth:NO];
    [[[self.mockDefaultUserNotificationCategories stub] andReturn:requiredAuthorizationSet] defaultCategoriesWithRequireAuth:YES];


    self.push.requireAuthorizationForDefaultCategories = NO;

    UIUserNotificationSettings *expected = [UIUserNotificationSettings settingsForTypes:self.push.userNotificationTypes
                                                                             categories:defaultSet];

    [[self.mockedApplication expect] registerUserNotificationSettings:expected];
    [self.push updateAPNSRegistration];

    XCTAssertNoThrow([self.mockedApplication verify],
                     @"should register with default categories without requiring authorization");



    self.push.requireAuthorizationForDefaultCategories = YES;

    expected = [UIUserNotificationSettings settingsForTypes:self.push.userNotificationTypes
                                                 categories:requiredAuthorizationSet];

    [[self.mockedApplication expect] registerUserNotificationSettings:expected];
    [self.push updateAPNSRegistration];

    XCTAssertNoThrow([self.mockedApplication verify],
                     @"should register with requiredAuthorizationSet defaults categories");
}

/**
 * Test the user notification categories used to register is the union between
 * the default categories and the custom categories.
 */
- (void)testUserNotificationCategories {
    self.push.userPushNotificationsEnabled = YES;

    UIMutableUserNotificationCategory *defaultCategory = [[UIMutableUserNotificationCategory alloc] init];
    defaultCategory.identifier = @"defaultCategory";

    UIMutableUserNotificationCategory *customCategory = [[UIMutableUserNotificationCategory alloc] init];
    customCategory.identifier = @"customCategory";

    UIMutableUserNotificationCategory *anotherCustomCategory = [[UIMutableUserNotificationCategory alloc] init];
    anotherCustomCategory.identifier = @"anotherCustomCategory";

    NSSet *defaultSet = [NSSet setWithArray:@[defaultCategory]];
    NSSet *customSet = [NSSet setWithArray:@[customCategory, anotherCustomCategory]];

    [[[self.mockDefaultUserNotificationCategories stub] andReturn:defaultSet] defaultCategoriesWithRequireAuth:self.push.requireAuthorizationForDefaultCategories];
    self.push.userNotificationCategories = customSet;


    [[self.mockedApplication expect] registerUserNotificationSettings:[OCMArg checkWithBlock:^BOOL(id obj) {
        NSSet *categories = ((UIUserNotificationSettings *)obj).categories;

        // Should only have 3 categories - defaultCategory, customCategory, anotherCustomCategory.
        if (categories.count != 3) {
            return NO;
        }

        return YES;
    }]];

    [self.push updateAPNSRegistration];

    XCTAssertNoThrow([self.mockedApplication verify],
                     @"Registered categories should be the union of defaults and customs");
}


/**
 * Test update apns registration when user notifications are disabled on >= iOS8.
 */
- (void)testUpdateAPNSRegistrationUserNotificationsDisabledIOS8 {
    // Make sure we have previously registered types
    UIUserNotificationSettings *settings = [UIUserNotificationSettings settingsForTypes:UIUserNotificationTypeBadge categories:nil];
    [[[self.mockedApplication stub] andReturn:settings] currentUserNotificationSettings];

    self.push.userPushNotificationsEnabled = NO;
    UIUserNotificationSettings *expected = [UIUserNotificationSettings settingsForTypes:UIUserNotificationTypeNone
                                                                             categories:nil];

    [[self.mockedApplication expect] registerUserNotificationSettings:expected];
    [self.push updateAPNSRegistration];

    XCTAssertNoThrow([self.mockedApplication verify],
                     @"should register UIUserNotificationTypeNone types and nil categories");
}


/**
 * Test update apns does not register for 0 types if already is registered for none.
 */
- (void)testUpdateAPNSRegistrationPushAlreadyDisabledIOS8 {

    // Make sure we have previously registered types
    UIUserNotificationSettings *settings = [UIUserNotificationSettings settingsForTypes:UIUserNotificationTypeNone categories:nil];
    [[[self.mockedApplication stub] andReturn:settings] currentUserNotificationSettings];

    self.push.userPushNotificationsEnabled = NO;

    // Make sure we do not call registerUserNotificationSettings for none, if we are
    // already registered for none or it will prompt the user.
    [[self.mockedApplication reject] registerUserNotificationSettings:OCMOCK_ANY];

    [self.push updateAPNSRegistration];

    XCTAssertNoThrow([self.mockedApplication verify],
                     @"should register UIUserNotificationTypeNone types and nil categories");
}

- (void)testSetBadgeNumberAutoBadgeEnabled{
    // Set the right values so we can check if a device api client call was made or not
    self.push.userPushNotificationsEnabled = YES;
    self.push.autobadgeEnabled = YES;
    self.push.deviceToken = validDeviceToken;

    [[[self.mockedApplication stub] andReturnValue:OCMOCK_VALUE((NSInteger)30)] applicationIconBadgeNumber];
    [[[self.mockedApplication stub] andReturnValue:OCMOCK_VALUE((NSUInteger)30)] beginBackgroundTaskWithExpirationHandler:OCMOCK_ANY];

    [[self.mockedApplication expect] setApplicationIconBadgeNumber:15];
    [[self.mockedChannelRegistrar expect] registerWithChannelID:OCMOCK_ANY
                                                channelLocation:OCMOCK_ANY
                                                    withPayload:OCMOCK_ANY
                                                     forcefully:YES];

    [self.push setBadgeNumber:15];
    XCTAssertNoThrow([self.mockedApplication verify],
                     @"should update application icon badge number when its different");

    XCTAssertNoThrow([self.mockedChannelRegistrar verify],
                     @"should update registration so autobadge works");
}

- (void)testSetBadgeNumberNoChange {
    [[[self.mockedApplication stub] andReturnValue:OCMOCK_VALUE((NSInteger)30)] applicationIconBadgeNumber];
    [[self.mockedApplication reject] setApplicationIconBadgeNumber:30];

    [self.push setBadgeNumber:30];
    XCTAssertNoThrow([self.mockedApplication verify],
                     @"should not update application icon badge number if there is no change");
}

- (void)testSetBadgeNumberAutoBadgeDisabled {
    self.push.userPushNotificationsEnabled = YES;
    self.push.deviceToken = validDeviceToken;

    self.push.autobadgeEnabled = NO;

    [[[self.mockedApplication stub] andReturnValue:OCMOCK_VALUE((NSInteger)30)] applicationIconBadgeNumber];
    [[self.mockedApplication expect] setApplicationIconBadgeNumber:15];

    // Reject device api client registration because autobadge is not enabled
    [[self.mockedChannelRegistrar reject] registerWithChannelID:OCMOCK_ANY
                                                channelLocation:OCMOCK_ANY
                                                    withPayload:OCMOCK_ANY
                                                     forcefully:YES];
    [self.push setBadgeNumber:15];
    XCTAssertNoThrow([self.mockedApplication verify],
                     @"should update application icon badge number when its different");

    XCTAssertNoThrow([self.mockedChannelRegistrar verify],
                     @"should not update registration because autobadge is disabled");
}

/**
 * Test handleDeviceTokenRegistration sets the device token and updates channel
 * registration.
 */
- (void)testHandleDeviceTokenRegistration {
    [UIUserNotificationSettings hideClass];

    self.push.userNotificationTypes = UIUserNotificationTypeSound;
    self.push.userPushNotificationsEnabled = YES;
    self.push.deviceToken = nil;

    NSData *token = [@"some-token" dataUsingEncoding:NSASCIIStringEncoding];
    [[self.mockedAnalytics expect] addEvent:OCMOCK_ANY];

    [[self.mockedChannelRegistrar expect] registerWithChannelID:OCMOCK_ANY
                                                channelLocation:OCMOCK_ANY
                                                    withPayload:OCMOCK_ANY
                                                     forcefully:NO];

    [[[self.mockedApplication stub] andReturnValue:OCMOCK_VALUE((NSUInteger)30)] beginBackgroundTaskWithExpirationHandler:OCMOCK_ANY];

    [self.push appRegisteredForRemoteNotificationsWithDeviceToken:token];

    XCTAssertNoThrow([self.mockedAnalytics verify],
                     @"should add device registration event to analytics");

    XCTAssertNoThrow([self.mockedChannelRegistrar verify],
                     @"should update registration on registering device token");

    // 736f6d652d746f6b656e = "some-token" in hex
    XCTAssertEqualObjects(@"736f6d652d746f6b656e", self.push.deviceToken, @"Register device token should set the device token");
}

// testHandleDeviceTokenRegistrationIOS8


/**
 * Test registering a device token in the background does not
 * update registration if we already have a channel
 */
- (void)testHandleDeviceTokenRegistrationBackground {
    self.push.userNotificationTypes = UIUserNotificationTypeSound;
    self.push.userPushNotificationsEnabled = YES;
    self.push.deviceToken = nil;
    self.push.channelID = @"channel";

    [[[self.mockedApplication stub] andReturnValue:OCMOCK_VALUE(UIApplicationStateBackground)] applicationState];


    NSData *token = [@"some-token" dataUsingEncoding:NSASCIIStringEncoding];
    [[self.mockedAnalytics expect] addEvent:OCMOCK_ANY];

    [[self.mockedChannelRegistrar reject] registerWithChannelID:OCMOCK_ANY
                                                channelLocation:OCMOCK_ANY
                                                    withPayload:OCMOCK_ANY
                                                     forcefully:NO];

    [self.push appRegisteredForRemoteNotificationsWithDeviceToken:token];

    XCTAssertNoThrow([self.mockedAnalytics verify],
                     @"should add device registration event to analytics");

    XCTAssertNoThrow([self.mockedChannelRegistrar verify],
                     @"should not allow registration in background except for channel creation");

    // 736f6d652d746f6b656e = "some-token" in hex
    XCTAssertEqualObjects(@"736f6d652d746f6b656e", self.push.deviceToken, @"Register device token should set the device token");
}


/**
 * Test device token registration in the background updates registration for
 * channel creation.
 */
- (void)testHandleDeviceTokenRegistrationBackgroundChannelCreation {
    [UIUserNotificationSettings hideClass];

    self.push.userNotificationTypes = UIUserNotificationTypeSound;
    self.push.userPushNotificationsEnabled = YES;
    self.push.deviceToken = nil;
    self.push.channelID = nil;

    [[[self.mockedApplication stub] andReturnValue:OCMOCK_VALUE(UIApplicationStateBackground)] applicationState];
    [[[self.mockedApplication stub] andReturnValue:OCMOCK_VALUE((NSUInteger)30)] beginBackgroundTaskWithExpirationHandler:OCMOCK_ANY];


    NSData *token = [@"some-token" dataUsingEncoding:NSASCIIStringEncoding];
    [[self.mockedAnalytics expect] addEvent:OCMOCK_ANY];

    [[self.mockedChannelRegistrar expect] registerWithChannelID:OCMOCK_ANY
                                                channelLocation:OCMOCK_ANY
                                                    withPayload:OCMOCK_ANY
                                                     forcefully:NO];

    [self.push appRegisteredForRemoteNotificationsWithDeviceToken:token];

    XCTAssertNoThrow([self.mockedAnalytics verify],
                     @"should add device registration event to analytics");

    XCTAssertNoThrow([self.mockedChannelRegistrar verify],
                     @"should update registration on registering device token");

    // 736f6d652d746f6b656e = "some-token" in hex
    XCTAssertEqualObjects(@"736f6d652d746f6b656e", self.push.deviceToken, @"Register device token should set the device token");
}

/**
 * Test handleUserNotificationSettingsRegistration updates the channel registration.
 */
- (void)testHandleUserNotificationSettingsRegistration {
    self.push.userPushNotificationsEnabled = YES;
    self.push.channelID = @"channel ID";


    [[[self.mockedApplication stub] andReturnValue:OCMOCK_VALUE((NSUInteger)30)] beginBackgroundTaskWithExpirationHandler:OCMOCK_ANY];
    [[self.mockedApplication expect] registerForRemoteNotifications];

    [self.push appRegisteredUserNotificationSettings];

    XCTAssertNoThrow([self.mockedApplication verify],
                     @"Should reregister remote notifications.");
}

/**
 * Test handleUserNotificationSettingsRegistration does not allow background
 * registration if a channel exists.
 */
- (void)testHandleUserNotificationSettingsRegistrationBackgroundChannelCreated {
    self.push.userPushNotificationsEnabled = YES;
    self.push.channelID = @"channel";

    [[[self.mockedApplication stub] andReturnValue:OCMOCK_VALUE(UIApplicationStateBackground)] applicationState];


    [[self.mockedChannelRegistrar reject] registerWithChannelID:OCMOCK_ANY
                                                channelLocation:OCMOCK_ANY
                                                    withPayload:OCMOCK_ANY
                                                     forcefully:NO];

    [self.push appRegisteredUserNotificationSettings];

    XCTAssertNoThrow([self.mockedChannelRegistrar verify],
                     @"should not allow registration in background except for channel creation");
}

/**
 * Test quietTimeEnabled.
 */
- (void)testSetQuietTimeEnabled {
    [self.dataStore removeObjectForKey:UAPushQuietTimeEnabledSettingsKey];
    XCTAssertFalse(self.push.quietTimeEnabled, @"QuietTime should be disabled");

    self.push.quietTimeEnabled = YES;
    XCTAssertTrue(self.push.quietTimeEnabled, @"QuietTime should be enabled");

    self.push.quietTimeEnabled = NO;
    XCTAssertFalse(self.push.quietTimeEnabled, @"QuietTime should be disabled");
}

/**
 * Test setting the default userPushNotificationsEnabled value.
 */
- (void)testUserPushNotificationsEnabledByDefault {
    self.push.userPushNotificationsEnabledByDefault = YES;
    XCTAssertTrue(self.push.userPushNotificationsEnabled, @"default user notification value not taking affect.");

    self.push.userPushNotificationsEnabledByDefault = NO;
    XCTAssertFalse(self.push.userPushNotificationsEnabled, @"default user notification value not taking affect.");
}

/**
 * Test setting the default backgroundPushNotificationEnabled value.
 */
- (void)testBackgroundPushNotificationsEnabledByDefault {
    self.push.backgroundPushNotificationsEnabledByDefault = YES;
    XCTAssertTrue(self.push.backgroundPushNotificationsEnabled, @"default background notification value not taking affect.");

    self.push.backgroundPushNotificationsEnabledByDefault = NO;
    XCTAssertFalse(self.push.backgroundPushNotificationsEnabled, @"default background notification value not taking affect.");
}

/**
 * Test update registration when shouldUpdateAPNSRegistration is true, updates
 * apns registration and not channel registration.
 */
- (void)testUpdateRegistrationShouldUpdateAPNS {
    self.push.shouldUpdateAPNSRegistration = YES;

    // Reject any device registration
    [[self.mockedChannelRegistrar reject] registerWithChannelID:OCMOCK_ANY
                                                channelLocation:OCMOCK_ANY
                                                    withPayload:OCMOCK_ANY
                                                     forcefully:NO];

    // Update the registration
    [self.push updateRegistration];

    // Verify it reset the flag
    XCTAssertFalse(self.push.shouldUpdateAPNSRegistration, @"updateRegistration should handle APNS registration updates if shouldUpdateAPNSRegistration is YES.");
}

/**
 * Tests update registration when channel creation flag is disabled.
 */
- (void)testChannelCreationFlagDisabled {

    // Prevent beginRegistrationBackgroundTask early return
    [[[self.mockedApplication stub] andReturnValue:OCMOCK_VALUE((NSUInteger)30)] beginBackgroundTaskWithExpirationHandler:OCMOCK_ANY];

    // Test when channel creation is disabled
    self.push.channelCreationEnabled = NO;
    [[self.mockedChannelRegistrar reject] registerWithChannelID:OCMOCK_ANY channelLocation:OCMOCK_ANY withPayload:OCMOCK_ANY forcefully:NO];

    [self.push updateChannelRegistrationForcefully:NO];

    [self.mockedChannelRegistrar verify];
}

/**
 * Tests update registration when channel creation flag is enabled.
 */
- (void)testChannelCreationFlagEnabled {

    // Prevent beginRegistrationBackgroundTask early return
    [[[self.mockedApplication stub] andReturnValue:OCMOCK_VALUE((NSUInteger)30)] beginBackgroundTaskWithExpirationHandler:OCMOCK_ANY];

    // Test when channel creation is enabled
    self.push.channelCreationEnabled = YES;
    [[self.mockedChannelRegistrar expect] registerWithChannelID:OCMOCK_ANY channelLocation:OCMOCK_ANY withPayload:OCMOCK_ANY forcefully:NO];

    [self.push updateChannelRegistrationForcefully:NO];

    [self.mockedChannelRegistrar verify];
}

/**
 * Tests enabling channel delay after channel ID has been registered.
 */
- (void)testEnableChannelDelayWithChannelID {

    // Set channelCreationDelayEnabled to NO
    UAConfig *config = [UAConfig defaultConfig];
    config.channelCreationDelayEnabled = NO;

    // Init push
    self.push =  [UAPush pushWithConfig:config dataStore:self.dataStore];

    // Ensure channel creation enabled is YES
    XCTAssertTrue(self.push.channelCreationEnabled);

    // Set channelCreationDelayEnabled to YES
    config = [UAConfig defaultConfig];
    config.channelCreationDelayEnabled = YES;

    // Init push
    self.push =  [UAPush pushWithConfig:config dataStore:self.dataStore];

    // Ensure channel creation enabled is NO
    XCTAssertFalse(self.push.channelCreationEnabled);

    // Mock the datastore to populate a mock channel location and channel id in UAPush init
    id mockDataStore = [OCMockObject niceMockForClass:[UAPreferenceDataStore class]];
    [[[mockDataStore stub] andReturn:@"someChannelLocation"] stringForKey:UAPushChannelLocationKey];
    [[[mockDataStore stub] andReturn:@"someChannelID"] stringForKey:UAPushChannelIDKey];

    self.push =  [UAPush pushWithConfig:config dataStore:mockDataStore];

    // Ensure channel creation enabled is YES
    XCTAssertTrue(self.push.channelCreationEnabled);
}

- (void)testUpdateRegistrationForcefullyPushEnabled {
    self.push.userPushNotificationsEnabled = YES;
    self.push.deviceToken = validDeviceToken;

    // Check every app state.  We want to allow manual registration in any state.
    for(int i = UIApplicationStateActive; i < UIApplicationStateBackground; i++) {
        UIApplicationState state = (UIApplicationState)i;
        self.push.registrationBackgroundTask = UIBackgroundTaskInvalid;

        [[[self.mockedApplication stub] andReturnValue:OCMOCK_VALUE(state)] applicationState];

        [[self.mockedChannelRegistrar expect] registerWithChannelID:OCMOCK_ANY
                                                    channelLocation:OCMOCK_ANY
                                                        withPayload:OCMOCK_ANY
                                                         forcefully:YES];

        [[[self.mockedApplication expect] andReturnValue:OCMOCK_VALUE((NSUInteger)30)] beginBackgroundTaskWithExpirationHandler:OCMOCK_ANY];

        [self.push updateChannelRegistrationForcefully:YES];
        XCTAssertNoThrow([self.mockedChannelRegistrar verify],
                         @"updateRegistration should register with the channel registrar if push is enabled.");

        XCTAssertNoThrow([self.mockedApplication verify], @"A background task should be requested for every update");
    }
}


- (void)testUpdateRegistrationForcefullyPushDisabled {
    self.push.userPushNotificationsEnabled = NO;
    self.push.deviceToken = validDeviceToken;

    // Add a device token so we get a device api callback
    [[self.mockedChannelRegistrar expect] registerWithChannelID:OCMOCK_ANY
                                                channelLocation:OCMOCK_ANY
                                                    withPayload:OCMOCK_ANY
                                                     forcefully:YES];


    [[[self.mockedApplication expect] andReturnValue:OCMOCK_VALUE((NSUInteger)30)] beginBackgroundTaskWithExpirationHandler:OCMOCK_ANY];


    [self.push updateChannelRegistrationForcefully:YES];
    XCTAssertNoThrow([self.mockedChannelRegistrar verify],
                     @"updateRegistration should unregister with the channel registrar if push is disabled.");

    XCTAssertNoThrow([self.mockedApplication verify], @"A background task should be requested for every update");
}

- (void)testUpdateRegistrationInvalidBackgroundTask {
    self.push.userPushNotificationsEnabled = YES;
    self.push.deviceToken = validDeviceToken;

    [[[self.mockedApplication expect] andReturnValue:OCMOCK_VALUE((NSUInteger)UIBackgroundTaskInvalid)] beginBackgroundTaskWithExpirationHandler:OCMOCK_ANY];

    [[self.mockedChannelRegistrar reject] registerWithChannelID:OCMOCK_ANY
                                                channelLocation:OCMOCK_ANY
                                                    withPayload:OCMOCK_ANY
                                                     forcefully:YES];

    [self.push updateChannelRegistrationForcefully:YES];


    XCTAssertNoThrow([self.mockedChannelRegistrar verify],
                     @"updateRegistration should not call any registration without a valid background task");
}

- (void)testUpdateRegistrationExistingBackgroundTask {
    self.push.registrationBackgroundTask = 30;
    [[self.mockedApplication reject] beginBackgroundTaskWithExpirationHandler:OCMOCK_ANY];

    [self.push updateChannelRegistrationForcefully:YES];

    XCTAssertNoThrow([self.mockedApplication verify], @"A background task should not be requested if one already exists");
}

/**
 * Test registration payload when pushTokenRegistrationEnabled is YES include device token
 */
- (void)testRegistrationPayload {
    [UIUserNotificationSettings hideClass];

    // Set up UAPush to give a full, opted in payload
    self.push.pushTokenRegistrationEnabled = YES;
    self.push.deviceToken = validDeviceToken;
    self.push.alias = @"ALIAS";
    self.push.channelTagRegistrationEnabled = YES;
    self.push.tags = @[@"tag-one"];
    self.push.autobadgeEnabled = NO;
    self.push.quietTimeEnabled = YES;
    self.push.timeZone = [NSTimeZone timeZoneWithName:@"Pacific/Auckland"];
    [self.push setQuietTimeStartHour:12 startMinute:0 endHour:12 endMinute:0];

    // Opt in requirements
    self.push.userPushNotificationsEnabled = YES;
    [[[self.mockedApplication stub] andReturnValue:OCMOCK_VALUE(UIRemoteNotificationTypeAlert)] enabledRemoteNotificationTypes];

    UAChannelRegistrationPayload *expectedPayload = [[UAChannelRegistrationPayload alloc] init];
    expectedPayload.deviceID = @"someDeviceID";
    expectedPayload.userID = @"someUser";
    expectedPayload.pushAddress = validDeviceToken;
    expectedPayload.optedIn = true;
    expectedPayload.tags = @[@"tag-one"];
    expectedPayload.setTags = YES;
    expectedPayload.alias = @"ALIAS";
    expectedPayload.badge = nil;
    expectedPayload.quietTime = @{@"end":@"12:00", @"start":@"12:00"};
    expectedPayload.timeZone = @"Pacific/Auckland";

    BOOL (^checkPayloadBlock)(id obj) = ^(id obj) {
        UAChannelRegistrationPayload *payload = obj;
        return [payload isEqualToPayload:expectedPayload];
    };

    [[[self.mockedApplication stub] andReturnValue:OCMOCK_VALUE((NSUInteger)30)] beginBackgroundTaskWithExpirationHandler:OCMOCK_ANY];
    [[self.mockedChannelRegistrar expect] registerWithChannelID:OCMOCK_ANY
                                                channelLocation:OCMOCK_ANY
                                                    withPayload:[OCMArg checkWithBlock:checkPayloadBlock]
                                                     forcefully:YES];

    [self.push updateChannelRegistrationForcefully:YES];

    XCTAssertNoThrow([self.mockedChannelRegistrar verify],
                     @"payload is not being created with expected values");
}

/**
 * Test registration payload when pushTokenRegistrationEnabled is NO does not include device token
 */
- (void)testRegistrationPayloadPushTokenRegistrationEnabledNo {
    [UIUserNotificationSettings hideClass];

    // Set up UAPush to give a full, opted in payload
    self.push.pushTokenRegistrationEnabled = NO;
    self.push.deviceToken = validDeviceToken;
    self.push.alias = @"ALIAS";
    self.push.channelTagRegistrationEnabled = YES;
    self.push.tags = @[@"tag-one"];
    self.push.autobadgeEnabled = NO;
    self.push.quietTimeEnabled = YES;
    self.push.timeZone = [NSTimeZone timeZoneWithName:@"Pacific/Auckland"];
    [self.push setQuietTimeStartHour:12 startMinute:0 endHour:12 endMinute:0];

    // Opt in requirements
    self.push.userPushNotificationsEnabled = YES;
    [[[self.mockedApplication stub] andReturnValue:OCMOCK_VALUE(UIRemoteNotificationTypeAlert)] enabledRemoteNotificationTypes];

    BOOL (^checkPayloadBlock)(id obj) = ^BOOL(id obj) {
        UAChannelRegistrationPayload *payload = (UAChannelRegistrationPayload *)obj;
        return payload.pushAddress == nil;
    };

    [[[self.mockedApplication stub] andReturnValue:OCMOCK_VALUE((NSUInteger)30)] beginBackgroundTaskWithExpirationHandler:OCMOCK_ANY];
    [[self.mockedChannelRegistrar expect] registerWithChannelID:OCMOCK_ANY
                                                channelLocation:OCMOCK_ANY
                                                    withPayload:[OCMArg checkWithBlock:checkPayloadBlock]
                                                     forcefully:YES];

    [self.push updateChannelRegistrationForcefully:YES];

    XCTAssertNoThrow([self.mockedChannelRegistrar verify],
                     @"payload is not being created with expected values");
}

/**
 * Test when backgroundPushNotificationsAllowed is YES when running >= iOS8,
 * device token is available, remote-notification background mode is enabled,
 * backgroundRefreshStatus is allowed, backgroundPushNotificationsEnabled is
 * enabled and pushTokenRegistrationEnabled is YES.
 */
- (void)testBackgroundPushNotificationsAllowedIOS8 {
    self.push.deviceToken = validDeviceToken;
    self.push.backgroundPushNotificationsEnabled = YES;
    self.push.pushTokenRegistrationEnabled = YES;
    [[[self.mockedAirship stub] andReturnValue:OCMOCK_VALUE(YES)] remoteNotificationBackgroundModeEnabled];
    [[[self.mockedApplication stub] andReturnValue:@(UIBackgroundRefreshStatusAvailable)] backgroundRefreshStatus];
    [[[self.mockedApplication stub] andReturnValue:OCMOCK_VALUE(YES)] isRegisteredForRemoteNotifications];

    XCTAssertTrue(self.push.backgroundPushNotificationsAllowed,
                  @"BackgroundPushNotificationsAllowed should be YES");
}

/**
 * Test when backgroundPushNotificationsAllowed is YES when running on < iOS8,
 * device token is available, remote-notification background mode is enabled,
 * backgroundRefreshStatus is allowed, backgroundPushNotificationsEnabled is
 * enabled and pushTokenRegistrationEnabled is YES.
 */
- (void)testBackgroundPushNotificationsAllowed {
    [UIUserNotificationSettings hideClass];
    self.push.userPushNotificationsEnabled = YES;
    self.push.pushTokenRegistrationEnabled = YES;
    self.push.deviceToken = validDeviceToken;
    self.push.backgroundPushNotificationsEnabled = YES;
    [[[self.mockedAirship stub] andReturnValue:OCMOCK_VALUE(YES)] remoteNotificationBackgroundModeEnabled];
    [[[self.mockedApplication stub] andReturnValue:@(UIBackgroundRefreshStatusAvailable)] backgroundRefreshStatus];

    XCTAssertTrue(self.push.backgroundPushNotificationsAllowed,
                  @"BackgroundPushNotificationsAllowed should be YES");
}

/**
 * Test when backgroundPushNotificationsAllowed is NO when the device token is
 * missing.
 */
- (void)testBackgroundPushNotificationsDisallowedNoDeviceToken {
    self.push.userPushNotificationsEnabled = YES;
    self.push.backgroundPushNotificationsEnabled = YES;
    [[[self.mockedAirship stub] andReturnValue:OCMOCK_VALUE(YES)] remoteNotificationBackgroundModeEnabled];
    [[[self.mockedApplication stub] andReturnValue:OCMOCK_VALUE(YES)] isRegisteredForRemoteNotifications];
    [[[self.mockedApplication stub] andReturnValue:@(UIBackgroundRefreshStatusAvailable)] backgroundRefreshStatus];

    self.push.deviceToken = nil;
    XCTAssertFalse(self.push.backgroundPushNotificationsAllowed,
                   @"BackgroundPushNotificationsAllowed should be NO");
}

/**
 * Test when backgroundPushNotificationsAllowed is NO when backgroundPushNotificationsAllowed
 * is disabled.
 */
- (void)testBackgroundPushNotificationsDisallowedDisabled {
    self.push.userPushNotificationsEnabled = YES;
    [[[self.mockedAirship stub] andReturnValue:OCMOCK_VALUE(YES)] remoteNotificationBackgroundModeEnabled];
    [[[self.mockedApplication stub] andReturnValue:OCMOCK_VALUE(YES)] isRegisteredForRemoteNotifications];
    [[[self.mockedApplication stub] andReturnValue:@(UIBackgroundRefreshStatusAvailable)] backgroundRefreshStatus];
    self.push.deviceToken = validDeviceToken;


    self.push.backgroundPushNotificationsEnabled = NO;
    XCTAssertFalse(self.push.backgroundPushNotificationsAllowed,
                   @"BackgroundPushNotificationsAllowed should be NO");
}

/**
 * Test when backgroundPushNotificationsAllowed is NO when the application is not
 * configured with remote-notification background mode.
 */
- (void)testBackgroundPushNotificationsDisallowedBackgroundNotificationDisabled {
    self.push.userPushNotificationsEnabled = YES;
    self.push.backgroundPushNotificationsEnabled = YES;
    [[[self.mockedApplication stub] andReturnValue:OCMOCK_VALUE(YES)] isRegisteredForRemoteNotifications];
    [[[self.mockedApplication stub] andReturnValue:@(UIBackgroundRefreshStatusAvailable)] backgroundRefreshStatus];
    self.push.deviceToken = validDeviceToken;

    [[[self.mockedAirship stub] andReturnValue:OCMOCK_VALUE(NO)] remoteNotificationBackgroundModeEnabled];
    XCTAssertFalse(self.push.backgroundPushNotificationsAllowed,
                   @"BackgroundPushNotificationsAllowed should be NO");
}

/**
 * Test when backgroundPushNotificationsAllowed is NO when backgroundRefreshStatus is invalid.
 */
- (void)testBackgroundPushNotificationsDisallowedInvalidBackgroundRefreshStatus {
    self.push.userPushNotificationsEnabled = YES;
    self.push.backgroundPushNotificationsEnabled = YES;
    [[[self.mockedAirship stub] andReturnValue:OCMOCK_VALUE(YES)] remoteNotificationBackgroundModeEnabled];
    [[[self.mockedApplication stub] andReturnValue:OCMOCK_VALUE(YES)] isRegisteredForRemoteNotifications];
    self.push.deviceToken = validDeviceToken;

    [[[self.mockedApplication stub] andReturnValue:@(UIBackgroundRefreshStatusRestricted)] backgroundRefreshStatus];

    XCTAssertFalse(self.push.backgroundPushNotificationsAllowed,
                   @"BackgroundPushNotificationsAllowed should be NO");
}

/**
 * Test that backgroundPushNotificationsAllowed is NO when not registered for remote notifications.
 */
- (void)testBackgroundPushNotificationsDisallowedNotRegisteredForRemoteNotificationsIOS8 {
    self.push.backgroundPushNotificationsEnabled = YES;
    [[[self.mockedApplication stub] andReturnValue:@(UIBackgroundRefreshStatusAvailable)] backgroundRefreshStatus];
    [[[self.mockedAirship stub] andReturnValue:OCMOCK_VALUE(YES)] remoteNotificationBackgroundModeEnabled];
    self.push.deviceToken = validDeviceToken;

    [[[self.mockedApplication stub] andReturnValue:OCMOCK_VALUE(NO)] isRegisteredForRemoteNotifications];
    XCTAssertFalse(self.push.backgroundPushNotificationsAllowed,
                   @"BackgroundPushNotificationsAllowed should be NO");
}

/**
 * Test when backgroundPushNotificationsAllowed is NO when
 * pushTokenRegistrationEnabled is NO.
 */
- (void)testBackgroundPushNotificationsPushTokenRegistrationEnabledNo {
    self.push.deviceToken = validDeviceToken;
    self.push.backgroundPushNotificationsEnabled = YES;
    self.push.pushTokenRegistrationEnabled = NO;
    [[[self.mockedAirship stub] andReturnValue:OCMOCK_VALUE(YES)] remoteNotificationBackgroundModeEnabled];
    [[[self.mockedApplication stub] andReturnValue:@(UIBackgroundRefreshStatusAvailable)] backgroundRefreshStatus];
    [[[self.mockedApplication stub] andReturnValue:OCMOCK_VALUE(YES)] isRegisteredForRemoteNotifications];

    XCTAssertFalse(self.push.backgroundPushNotificationsAllowed,
                   @"BackgroundPushNotificationsAllowed should be NO");
}

/**
 * Test that backgroundPushNotificationsAllowed is NO when running on < iOS8. Background
 * push requires push to be opted in.
 */
- (void)testBackgroundPushNotificationsDisallowedNotOptedIn {
    [UIUserNotificationSettings hideClass];

    self.push.backgroundPushNotificationsEnabled = YES;
    [[[self.mockedApplication stub] andReturnValue:@(UIBackgroundRefreshStatusAvailable)] backgroundRefreshStatus];
    [[[self.mockedAirship stub] andReturnValue:OCMOCK_VALUE(YES)] remoteNotificationBackgroundModeEnabled];
    self.push.deviceToken = validDeviceToken;

    self.push.userPushNotificationsEnabled = NO;
    XCTAssertFalse(self.push.backgroundPushNotificationsAllowed,
                   @"BackgroundPushNotificationsAllowed should be NO");
}

/**
 * Test that UserPushNotificationallowed is YES on < iOS8.
 */
-(void)testUserPushNotificationsAllowed {
    [UIUserNotificationSettings hideClass];

    self.push.userPushNotificationsEnabled = YES;
    self.push.pushTokenRegistrationEnabled = YES;
    self.push.deviceToken = validDeviceToken;
    [[[self.mockedApplication stub] andReturnValue:OCMOCK_VALUE(UIRemoteNotificationTypeAlert)] enabledRemoteNotificationTypes];

    XCTAssertTrue(self.push.userPushNotificationsAllowed,
                  @"UserPushNotificationsAllowed should be YES");
}

/**
 * Test that UserPushNotificationallowed is NO on < iOS8 when pushTokenRegistrationEnabled is NO
 */
-(void)testUserPushNotificationsAllowedNo {
    [UIUserNotificationSettings hideClass];

    self.push.userPushNotificationsEnabled = YES;
    self.push.pushTokenRegistrationEnabled = NO;
    self.push.deviceToken = validDeviceToken;
    [[[self.mockedApplication stub] andReturnValue:OCMOCK_VALUE(UIRemoteNotificationTypeAlert)] enabledRemoteNotificationTypes];

    XCTAssertFalse(self.push.userPushNotificationsAllowed,
                  @"UserPushNotificationsAllowed should be NO");
}

/**
 * Test that UserPushNotificationallowed is YES on iOS 8
 */
-(void)testUserPushNotificationsAllowedIOS8 {
    self.push.userPushNotificationsEnabled = YES;
    self.push.pushTokenRegistrationEnabled = YES;
    self.push.deviceToken = validDeviceToken;
    [[[self.mockedApplication stub] andReturnValue:OCMOCK_VALUE(YES)] isRegisteredForRemoteNotifications];

    UIUserNotificationSettings *settings = [UIUserNotificationSettings settingsForTypes:UIUserNotificationTypeBadge categories:nil];
    [[[self.mockedApplication stub] andReturn:settings] currentUserNotificationSettings];

    XCTAssertTrue(self.push.userPushNotificationsAllowed,
                  @"UserPushNotificationsAllowed should be YES");
}

/**
 * Test that UserPushNotificationallowed is NO on iOS 8 when pushTokenRegistrationEnabled is NO
 */
-(void)testUserPushNotificationsAllowedIOS8No {
    self.push.userPushNotificationsEnabled = YES;
    self.push.pushTokenRegistrationEnabled = NO;
    self.push.deviceToken = validDeviceToken;
    [[[self.mockedApplication stub] andReturnValue:OCMOCK_VALUE(YES)] isRegisteredForRemoteNotifications];

    UIUserNotificationSettings *settings = [UIUserNotificationSettings settingsForTypes:UIUserNotificationTypeBadge categories:nil];
    [[[self.mockedApplication stub] andReturn:settings] currentUserNotificationSettings];

    XCTAssertFalse(self.push.userPushNotificationsAllowed,
                  @"UserPushNotificationsAllowed should be NO");
}

/**
 * Test that UserPushNotificationallowed is NO on iOS 8
 */
- (void)testRegistrationPayloadNoDeviceToken {
    // Set up UAPush to give minimum payload
    self.push.deviceToken = nil;
    self.push.alias = nil;
    self.push.channelTagRegistrationEnabled = NO;
    self.push.autobadgeEnabled = NO;
    self.push.quietTimeEnabled = NO;

    // Opt in requirements
    self.push.userPushNotificationsEnabled = YES;
    [[[self.mockedApplication stub] andReturnValue:OCMOCK_VALUE(UIRemoteNotificationTypeAlert)] enabledRemoteNotificationTypes];

    // Verify opt in is false when device token is nil
    UAChannelRegistrationPayload *expectedPayload = [[UAChannelRegistrationPayload alloc] init];
    expectedPayload.deviceID = @"someDeviceID";
    expectedPayload.userID = @"someUser";
    expectedPayload.optedIn = false;
    expectedPayload.setTags = NO;

    BOOL (^checkPayloadBlock)(id obj) = ^(id obj) {
        UAChannelRegistrationPayload *payload = obj;
        return [payload isEqualToPayload:expectedPayload];
    };

    [[[self.mockedApplication stub] andReturnValue:OCMOCK_VALUE((NSUInteger)30)] beginBackgroundTaskWithExpirationHandler:OCMOCK_ANY];
    [[self.mockedChannelRegistrar expect] registerWithChannelID:OCMOCK_ANY channelLocation:OCMOCK_ANY withPayload:[OCMArg checkWithBlock:checkPayloadBlock] forcefully:YES];

    [self.push updateChannelRegistrationForcefully:YES];

    XCTAssertNoThrow([self.mockedChannelRegistrar verify],
                     @"payload is not being created with expected values");

}

- (void)testRegistrationPayloadDeviceTagsDisabled {
    self.push.userPushNotificationsEnabled = YES;
    self.push.channelTagRegistrationEnabled = NO;
    self.push.tags = @[@"tag-one"];

    // Check that the payload setTags is NO and the tags is nil
    BOOL (^checkPayloadBlock)(id obj) = ^(id obj) {
        UAChannelRegistrationPayload *payload = obj;
        return (BOOL)(!payload.setTags && payload.tags == nil);
    };

    [[[self.mockedApplication stub] andReturnValue:OCMOCK_VALUE((NSUInteger)30)] beginBackgroundTaskWithExpirationHandler:OCMOCK_ANY];
    [[self.mockedChannelRegistrar expect] registerWithChannelID:OCMOCK_ANY
                                                channelLocation:OCMOCK_ANY
                                                    withPayload:[OCMArg checkWithBlock:checkPayloadBlock]
                                                     forcefully:YES];

    [self.push updateChannelRegistrationForcefully:YES];

    XCTAssertNoThrow([self.mockedChannelRegistrar verify],
                     @"payload is including tags when device tags is NO");

}

- (void)testRegistrationPayloadAutoBadgeEnabled {
    self.push.userPushNotificationsEnabled = YES;
    self.push.autobadgeEnabled = YES;
    [[[self.mockedApplication stub] andReturnValue:OCMOCK_VALUE((NSInteger)30)] applicationIconBadgeNumber];

    // Check that the payload setTags is NO and the tags is nil
    BOOL (^checkPayloadBlock)(id obj) = ^(id obj) {
        UAChannelRegistrationPayload *payload = obj;
        return (BOOL)([payload.badge integerValue] == 30);
    };

    [[[self.mockedApplication stub] andReturnValue:OCMOCK_VALUE((NSUInteger)30)] beginBackgroundTaskWithExpirationHandler:OCMOCK_ANY];
    [[self.mockedChannelRegistrar expect] registerWithChannelID:OCMOCK_ANY
                                                channelLocation:OCMOCK_ANY
                                                    withPayload:[OCMArg checkWithBlock:checkPayloadBlock]
                                                     forcefully:YES];

    [self.push updateChannelRegistrationForcefully:YES];

    XCTAssertNoThrow([self.mockedChannelRegistrar verify],
                     @"payload is not including the correct badge when auto badge is enabled");
}

- (void)testRegistrationPayloadNoQuietTime {
    self.push.userPushNotificationsEnabled = YES;
    self.push.quietTimeEnabled = NO;


    // Check that the payload does not include a quiet time
    BOOL (^checkPayloadBlock)(id obj) = ^(id obj) {
        UAChannelRegistrationPayload *payload = obj;
        return (BOOL)(payload.quietTime == nil);
    };

    [[[self.mockedApplication stub] andReturnValue:OCMOCK_VALUE((NSUInteger)30)] beginBackgroundTaskWithExpirationHandler:OCMOCK_ANY];
    [[self.mockedChannelRegistrar expect] registerWithChannelID:OCMOCK_ANY
                                                channelLocation:OCMOCK_ANY
                                                    withPayload:[OCMArg checkWithBlock:checkPayloadBlock]
                                                     forcefully:YES];

    [self.push updateChannelRegistrationForcefully:YES];

    XCTAssertNoThrow([self.mockedChannelRegistrar verify],
                     @"payload should not include quiet time if quiet time is disabled");
}


/**
 * Test handleNotification: and handleNotification:fetchCompletionHandler:
 * call the action runner with the correct arguments and report correctly to
 * analytics
 */
- (void)testHandleNotification {
    __block UASituation expectedSituation;
    __block UAActionFetchResult fetchResult = UAActionFetchResultNoData;

    BOOL (^handlerCheck)(id obj) = ^(id obj) {
        void (^handler)(UAActionResult *) = obj;
        if (handler) {
            handler([UAActionResult resultWithValue:nil withFetchResult:fetchResult]);
        }
        return YES;
    };

    // Create arrays of the expected results
    UAActionFetchResult fetchResults[] = {UAActionFetchResultFailed, UAActionFetchResultNewData, UAActionFetchResultNoData};
    UIApplicationState applicationStates[] = {UIApplicationStateBackground, UIApplicationStateInactive, UIApplicationStateActive};
    UASituation situations[] = {UASituationBackgroundPush, UASituationLaunchedFromPush, UASituationForegroundPush};

    // Expected actions payload
    NSMutableDictionary *expectedActionPayload = [NSMutableDictionary dictionaryWithDictionary:self.notification];
    expectedActionPayload[kUAIncomingPushActionRegistryName] = self.notification;

    for(NSInteger stateIndex = 0; stateIndex < 3; stateIndex++) {
        expectedSituation = situations[stateIndex];
        UIApplicationState applicationState = applicationStates[stateIndex];

        [[self.mockActionRunner expect]runActionsWithActionValues:expectedActionPayload
                                                        situation:expectedSituation
                                                         metadata: @{ UAActionMetadataPushPayloadKey: self.notification }
                                                completionHandler:[OCMArg checkWithBlock:handlerCheck]];

        [[self.mockedAnalytics expect] handleNotification:self.notification inApplicationState:applicationState];
        [self.push appReceivedRemoteNotification:self.notification applicationState:applicationState];

        XCTAssertNoThrow([self.mockActionRunner verify], @"handleNotification should run push actions with situation %ld", (long)expectedSituation);
        XCTAssertNoThrow([self.mockedAnalytics verify], @"analytics should be notified of the incoming notification");

        // Test handleNotification:fetchCompletionHandler: for every background fetch result
        for (int fetchResultIndex = 0; fetchResultIndex < 3; fetchResultIndex++) {
            __block BOOL completionHandlerCalled = NO;
            fetchResult = fetchResults[fetchResultIndex];

            [[self.mockActionRunner expect]runActionsWithActionValues:expectedActionPayload
                                                            situation:expectedSituation
                                                             metadata: @{ UAActionMetadataPushPayloadKey: self.notification }
                                                    completionHandler:[OCMArg checkWithBlock:handlerCheck]];

            [[self.mockedAnalytics expect] handleNotification:self.notification inApplicationState:applicationState];
            [self.push appReceivedRemoteNotification:self.notification applicationState:applicationState fetchCompletionHandler:^(UIBackgroundFetchResult result) {
                completionHandlerCalled = YES;

                // Relies on the fact that UAActionFetchResults cast correctly to UIBackgroundFetchResults
                XCTAssertEqual((NSUInteger)fetchResult, (NSUInteger)result, @"Unexpected fetch result");
            }];

            XCTAssertTrue(completionHandlerCalled, @"handleNotification should call fetch completion handler");
            XCTAssertNoThrow([self.mockActionRunner verify], @"handleNotification should run push actions with situation %ld", (long)expectedSituation);
            XCTAssertNoThrow([self.mockedAnalytics verify], @"analytics should be notified of the incoming notification");
        }
    }

    // UIApplicationStateActive, no completion handler
    expectedSituation = UASituationForegroundPush;

    [[self.mockActionRunner expect]runActionsWithActionValues:expectedActionPayload
                                                    situation:expectedSituation
                                                     metadata: @{ UAActionMetadataPushPayloadKey: self.notification }
                                            completionHandler:[OCMArg checkWithBlock:handlerCheck]];
}

/**
 * Test running actions for a push notification automatically adds a display inbox
 * action if the notification contains a message ID (_uamid).
 */
- (void)testPushActionsRunsInboxAction {

    NSDictionary *richPushNotification = @{@"_uamid": @"message_id", @"add_tags_action": @"tag"};

    // Expected actions payload
    NSMutableDictionary *expectedActionPayload = [NSMutableDictionary dictionaryWithDictionary:richPushNotification];

    // Should add the IncomingPushAction
    expectedActionPayload[kUAIncomingPushActionRegistryName] = richPushNotification;

    // Should add the DisplayInboxAction
    expectedActionPayload[kUADisplayInboxActionDefaultRegistryAlias] = @"message_id";

    [[self.mockActionRunner expect]runActionsWithActionValues:expectedActionPayload
                                                    situation:UASituationLaunchedFromPush
                                                     metadata:OCMOCK_ANY
                                            completionHandler:OCMOCK_ANY];

    [self.push appReceivedRemoteNotification:self.notification applicationState:UIApplicationStateInactive];
}

/**
 * Test running actions for a push notification does not add a inbox action if one is
 * already available.
 */
- (void)testPushActionsInboxActionAlreadyDefined {

    // Notification with a message ID and a Overlay Inbox Message Action
    NSDictionary *richPushNotification = @{@"_uamid": @"message_id", @"^mco": @"MESSAGE_ID"};

    // Expected actions payload
    NSMutableDictionary *expectedActionPayload = [NSMutableDictionary dictionaryWithDictionary:richPushNotification];

    // Should add the IncomingPushAction
    expectedActionPayload[kUAIncomingPushActionRegistryName] = richPushNotification;

    [[self.mockActionRunner expect]runActionsWithActionValues:expectedActionPayload
                                                    situation:UASituationLaunchedFromPush
                                                     metadata:OCMOCK_ANY
                                            completionHandler:OCMOCK_ANY];

    [self.push appReceivedRemoteNotification:self.notification applicationState:UIApplicationStateInactive];
}


/**
 * Test handleNotification when auto badge is disabled does
 * not set the badge on the application
 */
- (void)testHandleNotificationAutoBadgeDisabled {
    self.push.autobadgeEnabled = NO;
    [[self.mockedApplication reject] setApplicationIconBadgeNumber:2];
    [self.push appReceivedRemoteNotification:self.notification applicationState:UIApplicationStateActive];
    [self.push appReceivedRemoteNotification:self.notification applicationState:UIApplicationStateBackground];
    [self.push appReceivedRemoteNotification:self.notification applicationState:UIApplicationStateInactive];

    XCTAssertNoThrow([self.mockedApplication verify], @"Badge should only be updated if autobadge is enabled");
}

/**
 * Test handleNotification when auto badge is enabled sets the badge
 * only when a notification comes in while the app is in the foreground
 */
- (void)testHandleNotificationAutoBadgeEnabled {
    self.push.autobadgeEnabled = YES;

    [[self.mockedApplication expect] setApplicationIconBadgeNumber:2];
    [self.push appReceivedRemoteNotification:self.notification applicationState:UIApplicationStateActive];

    XCTAssertNoThrow([self.mockedApplication verify], @"Badge should be updated if app is in the foreground");

    [[self.mockedApplication reject] setApplicationIconBadgeNumber:2];
    [self.push appReceivedRemoteNotification:self.notification applicationState:UIApplicationStateBackground];
    [self.push appReceivedRemoteNotification:self.notification applicationState:UIApplicationStateInactive];

    XCTAssertNoThrow([self.mockedApplication verify], @"Badge should only be updated if app is in the foreground");
}

/**
 * Test handleNotification in an inactive state sets the launchNotification
 */
- (void)testHandleNotificationLaunchNotification {
    self.push.launchNotification = nil;
    [self.push appReceivedRemoteNotification:self.notification applicationState:UIApplicationStateActive];
    [self.push appReceivedRemoteNotification:self.notification applicationState:UIApplicationStateBackground];

    XCTAssertNil(self.push.launchNotification, @"Launch notification should only be set in an inactive state");

    [self.push appReceivedRemoteNotification:self.notification applicationState:UIApplicationStateInactive];
    XCTAssertNotNil(self.push.launchNotification, @"Launch notification should be set in an inactive state");
}

/**
 * Test applicationDidEnterBackground clears the notification and sets
 * the hasEnteredBackground flag
 */
- (void)testApplicationDidEnterBackground {
    self.push.launchNotification = self.notification;

    [self.push applicationDidEnterBackground];
    XCTAssertNil(self.push.launchNotification, @"applicationDidEnterBackground should clear the launch notification");
    XCTAssertTrue([self.dataStore boolForKey:UAPushChannelCreationOnForeground], @"applicationDidEnterBackground should set channelCreationOnForeground to true");
}

/**
 * Test update registration is called when the device enters a background and
 * we do not have a channel ID
 */
- (void)testApplicationDidEnterBackgroundCreatesChannel {
    self.push.channelID = nil;
    self.push.userPushNotificationsEnabled = YES;

    [[[self.mockedApplication stub] andReturnValue:OCMOCK_VALUE((NSUInteger)30)] beginBackgroundTaskWithExpirationHandler:OCMOCK_ANY];

    [[self.mockedChannelRegistrar expect] registerWithChannelID:OCMOCK_ANY
                                                channelLocation:OCMOCK_ANY
                                                    withPayload:OCMOCK_ANY
                                                     forcefully:NO];

    [self.push applicationDidEnterBackground];

    XCTAssertNoThrow([self.mockedChannelRegistrar verify], @"Channel registration should be called");
}

/**
 * Test channel created
 */
- (void)testChannelCreated {
    UAPush *push = self.push;

    [push channelCreated:@"someChannelID" channelLocation:@"someLocation" existing:YES];

    XCTAssertEqualObjects(push.channelID, @"someChannelID", @"The channel ID should be set on channel creation.");
    XCTAssertEqualObjects(push.channelLocation, @"someLocation", @"The channel location should be set on channel creation.");
}

/**
 * Test registration succeeded with channels and an up to date payload
 */
- (void)testRegistrationSucceeded {
    self.push.deviceToken = validDeviceToken;
    self.push.channelID = @"someChannelID";
    self.push.channelLocation = @"someChannelLocation";
    self.push.registrationBackgroundTask = 30;

    [[self.mockRegistrationDelegate expect] registrationSucceededForChannelID:@"someChannelID" deviceToken:validDeviceToken];

    [[self.mockedApplication expect] endBackgroundTask:30];

    [self.push registrationSucceededWithPayload:[self.push createChannelPayload]];
    XCTAssertNoThrow([self.mockRegistrationDelegate verify], @"Delegate should be called");
    XCTAssertNoThrow([self.mockedApplication verify], @"Should end the background task");
}

/**
 * Test registration succeeded with an out of date payload
 */
- (void)testRegistrationSucceededUpdateNeeded {
    self.push.deviceToken = validDeviceToken;
    self.push.channelID = @"someChannelID";
    self.push.channelLocation = @"someChannelLocation";
    self.push.registrationBackgroundTask = 30;

    [[self.mockRegistrationDelegate expect] registrationSucceededForChannelID:@"someChannelID" deviceToken:validDeviceToken];

    [[self.mockedChannelRegistrar expect] registerWithChannelID:OCMOCK_ANY
                                                channelLocation:OCMOCK_ANY
                                                    withPayload:OCMOCK_ANY
                                                     forcefully:NO];

    // Should not end the background task
    [[self.mockedApplication reject] endBackgroundTask:30];

    // Call with an empty payload.  Should be different then the UAPush generated payload
    [self.push registrationSucceededWithPayload:[[UAChannelRegistrationPayload alloc] init]];

    XCTAssertNoThrow([self.mockRegistrationDelegate verify], @"Delegate should be called");
    XCTAssertNoThrow([self.mockedApplication verify], @"Should not end the background task");
}


/**
 * Test registration failed
 */
- (void)testRegistrationFailed {
    self.push.registrationBackgroundTask = 30;

    [[self.mockRegistrationDelegate expect] registrationFailed];
    [[self.mockedApplication expect] endBackgroundTask:30];

    [self.push registrationFailedWithPayload:[[UAChannelRegistrationPayload alloc] init]];
    XCTAssertNoThrow([self.mockRegistrationDelegate verify], @"Delegate should be called");
    XCTAssertNoThrow([self.mockedApplication verify], @"Should end the background task");
}

/**
 * Test setting the channel ID generates the device registration event with the
 * channel ID.
 */
- (void)testSetChannelID {
    self.push.channelID = @"someChannelID";
    self.push.channelLocation = @"someChannelLocation";

    XCTAssertEqualObjects(@"someChannelID", self.push.channelID, @"Channel ID is not being set properly");
}

/**
 * Test setting the channel ID without a channel location returns nil.
 */
- (void)testSetChannelIDNoLocation {
    self.push.channelID = @"someChannelID";
    self.push.channelLocation = nil;

    XCTAssertNil(self.push.channelID, @"Channel ID should be nil without location.");
}

/**
 * Test migrating the userNotificationEnabled key no ops when its already set on
 * >= iOS8.
 */
- (void)testMigrateNewRegistrationFlowAlreadySetIOS8 {
    // Set the UAUserPushNotificationsEnabledKey setting to NO
    [self.dataStore setBool:NO forKey:UAUserPushNotificationsEnabledKey];


    UIUserNotificationSettings *settings = [UIUserNotificationSettings settingsForTypes:UIUserNotificationTypeAlert categories:nil];
    [[[self.mockedApplication stub] andReturn:settings] currentUserNotificationSettings];

    // Force a migration
    [self.dataStore removeObjectForKey:UAPushEnabledSettingsMigratedKey];
    [self.push migratePushSettings];

    // Verify its still NO
    XCTAssertFalse([self.dataStore boolForKey:UAUserPushNotificationsEnabledKey]);
}
/**
 * Test migrating the userNotificationEnabled key does not set if the
 * current notification types is none on >= iOS8.
 */
- (void)testMigrateNewRegistrationFlowDisabledIOS8 {
    // Clear the UAUserPushNotificationsEnabledKey setting
    [self.dataStore removeObjectForKey:UAUserPushNotificationsEnabledKey];
    [self.dataStore removeObjectForKey:UAPushEnabledSettingsMigratedKey];

    UIUserNotificationSettings *settings = [UIUserNotificationSettings settingsForTypes:UIUserNotificationTypeNone categories:nil];
    [[[self.mockedApplication stub] andReturn:settings] currentUserNotificationSettings];

    [self.push migratePushSettings];

    // Verify it was not set
    XCTAssertNil([self.dataStore objectForKey:UAUserPushNotificationsEnabledKey]);
}

/**
 * Test migrating the userNotificationEnabled key does set to YES if the
 * current notification types is not none on >= iOS8.
 */
- (void)testMigrateNewRegistrationFlowEnabledIOS8 {
    // Clear the UAUserPushNotificationsEnabledKey setting
    [self.dataStore removeObjectForKey:UAUserPushNotificationsEnabledKey];
    [self.dataStore removeObjectForKey:UAPushEnabledSettingsMigratedKey];

    UIUserNotificationSettings *settings = [UIUserNotificationSettings settingsForTypes:UIUserNotificationTypeAlert categories:nil];
    [[[self.mockedApplication stub] andReturn:settings] currentUserNotificationSettings];

    [self.push migratePushSettings];

    // Verify it was set to YES
    XCTAssertTrue([self.dataStore boolForKey:UAUserPushNotificationsEnabledKey]);
}


/**
 * Test migrating the userNotificationEnabled key no ops when its already set
 * on < iOS8.
 */
- (void)testMigrateNewRegistrationFlowAlreadySet {
    [UIUserNotificationSettings hideClass];

    // Clear any previous migration values in standard user defaults
    [[NSUserDefaults standardUserDefaults] removeObjectForKey:UAPushEnabledSettingsMigratedKey];
    [[NSUserDefaults standardUserDefaults] removeObjectForKey:UAUserPushNotificationsEnabledKey];

    // Set the UAUserPushNotificationsEnabledKey setting to NO
    [self.dataStore setBool:NO forKey:UAUserPushNotificationsEnabledKey];
    [self.dataStore removeObjectForKey:UAPushEnabledSettingsMigratedKey];

    [[[self.mockedApplication stub] andReturnValue:OCMOCK_VALUE(UIRemoteNotificationTypeAlert)] enabledRemoteNotificationTypes];

    [self.push migratePushSettings];

    // Verify its still NO
    XCTAssertFalse([self.dataStore boolForKey:UAUserPushNotificationsEnabledKey]);
}

/**
 * Test migrating the userNotificationEnabled key does not set if the
 * current notification types is none on < iOS8.
 */
- (void)testMigrateNewRegistrationFlowDisabled {
    [UIUserNotificationSettings hideClass];

    // Clear the UAUserPushNotificationsEnabledKey setting
    [self.dataStore removeObjectForKey:UAUserPushNotificationsEnabledKey];
    [self.dataStore removeObjectForKey:UAPushEnabledSettingsMigratedKey];

    [[[self.mockedApplication stub] andReturnValue:OCMOCK_VALUE(UIRemoteNotificationTypeNone)] enabledRemoteNotificationTypes];


    [self.push migratePushSettings];

    // Verify it was not set
    XCTAssertNil([self.dataStore objectForKey:UAUserPushNotificationsEnabledKey]);
}

/**
 * Test migrating the userNotificationEnabled key does set to YES if the
 * current notification types is not none on < iOS8.
 */
- (void)testMigrateNewRegistrationFlowEnabled {
    [UIUserNotificationSettings hideClass];


    // Clear the UAUserPushNotificationsEnabledKey setting
    [self.dataStore removeObjectForKey:UAUserPushNotificationsEnabledKey];
    [self.dataStore removeObjectForKey:UAPushEnabledSettingsMigratedKey];

    [[[self.mockedApplication stub] andReturnValue:OCMOCK_VALUE(UIRemoteNotificationTypeAlert)] enabledRemoteNotificationTypes];

    [self.push migratePushSettings];

    // Verify it was set to YES
    XCTAssertTrue([self.dataStore boolForKey:UAUserPushNotificationsEnabledKey]);
}

/**
 * Test migrating only performs once.
 */
- (void)testMigrateNewRegistrationFlowOnlyOnce {
    // Clear the UAUserPushNotificationsEnabledKey setting
    [self.dataStore removeObjectForKey:UAUserPushNotificationsEnabledKey];
    [self.dataStore removeObjectForKey:UAPushEnabledSettingsMigratedKey];

    UIUserNotificationSettings *settings = [UIUserNotificationSettings settingsForTypes:UIUserNotificationTypeAlert categories:nil];
    [[[self.mockedApplication stub] andReturn:settings] currentUserNotificationSettings];

    [self.push migratePushSettings];

    // Verify it was set to YES
    XCTAssertTrue([self.dataStore boolForKey:UAUserPushNotificationsEnabledKey]);
    XCTAssertTrue([self.dataStore boolForKey:UAPushEnabledSettingsMigratedKey]);

    // Clear the UAUserPushNotificationsEnabledKey setting
    [self.dataStore removeObjectForKey:UAUserPushNotificationsEnabledKey];

    [self.push migratePushSettings];

    // Should not enable it the second time
    XCTAssertFalse([self.dataStore boolForKey:UAUserPushNotificationsEnabledKey]);
}

/**
 * Test handling receiving notification actions triggered with an identifier for
 * background activation mode.
 */
- (void)testOnReceiveActionWithIdentifierBackground {
    UIMutableUserNotificationAction *foregroundAction = [[UIMutableUserNotificationAction alloc] init];
    foregroundAction.activationMode = UIUserNotificationActivationModeForeground;
    foregroundAction.identifier = @"foregroundIdentifier";

    UIMutableUserNotificationAction *backgroundAction = [[UIMutableUserNotificationAction alloc] init];
    backgroundAction.activationMode = UIUserNotificationActivationModeBackground;
    backgroundAction.identifier = @"backgroundIdentifier";

    UIMutableUserNotificationCategory *category = [[UIMutableUserNotificationCategory alloc] init];
    [category setActions:@[foregroundAction, backgroundAction] forContext:UIUserNotificationActionContextMinimal];
    category.identifier = @"notificationCategory";

    UIUserNotificationSettings *settings = [UIUserNotificationSettings settingsForTypes:0 categories:[NSSet setWithArray:@[category]]];
    [[[self.mockedApplication stub] andReturn:settings] currentUserNotificationSettings];

    __block BOOL completionHandlerCalled = NO;

    BOOL (^handlerCheck)(id obj) = ^(id obj) {
        void (^handler)(UAActionResult *) = obj;
        if (handler) {
            handler([UAActionResult emptyResult]);
        }
        return YES;
    };

    // Expected actions payload
    NSMutableDictionary *expectedActionPayload = [NSMutableDictionary dictionary];
    [expectedActionPayload addEntriesFromDictionary:self.notification[@"com.urbanairship.interactive_actions"][@"backgroundIdentifier"]];
    expectedActionPayload[kUAIncomingPushActionRegistryName] = self.notification;

    [[self.mockActionRunner expect]runActionsWithActionValues:expectedActionPayload
                                                    situation:UASituationBackgroundInteractiveButton
                                                     metadata: @{ UAActionMetadataUserNotificationActionIDKey: @"backgroundIdentifier",
                                                                  UAActionMetadataPushPayloadKey: self.notification }
                                            completionHandler:[OCMArg checkWithBlock:handlerCheck]];


    [[self.mockedAnalytics expect] handleNotification:self.notification inApplicationState:UIApplicationStateBackground];
    [[self.mockedAnalytics expect] addEvent:[OCMArg checkWithBlock:^BOOL(id obj) {
        return [obj isKindOfClass:[UAInteractiveNotificationEvent class]];
    }]];

    [self.push appReceivedActionWithIdentifier:@"backgroundIdentifier"
                                  notification:self.notification
                              applicationState:UIApplicationStateBackground
                             completionHandler:^{
                                 completionHandlerCalled = YES;
                             }];


    XCTAssertNoThrow([self.mockActionRunner verify],
                     @"Actions should run for notification action button");

    XCTAssertNoThrow([self.mockedAnalytics verify],
                     @"Analytics should be notified of the incoming notification");

    XCTAssertTrue(completionHandlerCalled, @"Completion handler should be called.");
}

/**
 * Test handling receiving notification actions triggered with an identifier and responseInfo for
 * background activation mode.
 */
- (void)testOnReceiveActionWithIdentifierResponseInfoBackground {
    UIMutableUserNotificationAction *foregroundAction = [[UIMutableUserNotificationAction alloc] init];
    foregroundAction.activationMode = UIUserNotificationActivationModeForeground;
    foregroundAction.identifier = @"foregroundIdentifier";

    UIMutableUserNotificationAction *backgroundAction = [[UIMutableUserNotificationAction alloc] init];
    backgroundAction.activationMode = UIUserNotificationActivationModeBackground;
    backgroundAction.identifier = @"backgroundIdentifier";

    NSDictionary *expectedResponseInfo;
    NSDictionary *expectedMetadata;

    // TODO: remove this conditional behavior once we start building with Xcode 7
    if ([[UIDevice currentDevice].systemVersion floatValue] >= 9.0) {
        // backgroundAction.behavior = UIUserNotificationActionBehaviorTextInput
        [backgroundAction setValue:@(1) forKey:@"behavior"];

        expectedResponseInfo = @{@"UIUserNotificationActionResponseTypedTextKey":@"howdy"};
        expectedMetadata = @{ UAActionMetadataUserNotificationActionIDKey: @"backgroundIdentifier",
                              UAActionMetadataPushPayloadKey: self.notification,
                              UAActionMetadataResponseInfoKey: expectedResponseInfo};
    } else {
        expectedMetadata = @{ UAActionMetadataUserNotificationActionIDKey: @"backgroundIdentifier",
                              UAActionMetadataPushPayloadKey: self.notification };
    }

    UIMutableUserNotificationCategory *category = [[UIMutableUserNotificationCategory alloc] init];
    [category setActions:@[foregroundAction, backgroundAction] forContext:UIUserNotificationActionContextMinimal];
    category.identifier = @"notificationCategory";

    UIUserNotificationSettings *settings = [UIUserNotificationSettings settingsForTypes:0 categories:[NSSet setWithArray:@[category]]];
    [[[self.mockedApplication stub] andReturn:settings] currentUserNotificationSettings];

    __block BOOL completionHandlerCalled = NO;

    BOOL (^handlerCheck)(id obj) = ^(id obj) {
        void (^handler)(UAActionResult *) = obj;
        if (handler) {
            handler([UAActionResult emptyResult]);
        }
        return YES;
    };

    // Expected actions payload
    NSMutableDictionary *expectedActionPayload = [NSMutableDictionary dictionary];
    [expectedActionPayload addEntriesFromDictionary:self.notification[@"com.urbanairship.interactive_actions"][@"backgroundIdentifier"]];
    expectedActionPayload[kUAIncomingPushActionRegistryName] = self.notification;

    [[self.mockActionRunner expect]runActionsWithActionValues:expectedActionPayload
                                                    situation:UASituationBackgroundInteractiveButton
                                                     metadata:expectedMetadata
                                            completionHandler:[OCMArg checkWithBlock:handlerCheck]];


    [[self.mockedAnalytics expect] handleNotification:self.notification inApplicationState:UIApplicationStateBackground];
    [[self.mockedAnalytics expect] addEvent:[OCMArg checkWithBlock:^BOOL(id obj) {
        return [obj isKindOfClass:[UAInteractiveNotificationEvent class]];
    }]];

    [self.push appReceivedActionWithIdentifier:@"backgroundIdentifier"
                                  notification:self.notification
                                  responseInfo:expectedResponseInfo
                              applicationState:UIApplicationStateBackground
                             completionHandler:^{
                                 completionHandlerCalled = YES;
                             }];


    XCTAssertNoThrow([self.mockActionRunner verify],
                     @"Actions should run for notification action button");

    XCTAssertNoThrow([self.mockedAnalytics verify],
                     @"Analytics should be notified of the incoming notification");

    XCTAssertTrue(completionHandlerCalled, @"Completion handler should be called.");
}

/**
 * Test handling receiving notification actions triggered with an identifier for
 * foreground activation mode.
 */
- (void)testOnReceiveActionWithIdentifierForeground {
    UIMutableUserNotificationAction *foregroundAction = [[UIMutableUserNotificationAction alloc] init];
    foregroundAction.activationMode = UIUserNotificationActivationModeForeground;
    foregroundAction.identifier = @"foregroundIdentifier";

    UIMutableUserNotificationAction *backgroundAction = [[UIMutableUserNotificationAction alloc] init];
    backgroundAction.activationMode = UIUserNotificationActivationModeBackground;
    backgroundAction.identifier = @"backgroundIdentifier";

    UIMutableUserNotificationCategory *category = [[UIMutableUserNotificationCategory alloc] init];
    [category setActions:@[foregroundAction, backgroundAction] forContext:UIUserNotificationActionContextMinimal];
    category.identifier = @"notificationCategory";

    UIUserNotificationSettings *settings = [UIUserNotificationSettings settingsForTypes:0 categories:[NSSet setWithArray:@[category]]];
    [[[self.mockedApplication stub] andReturn:settings] currentUserNotificationSettings];

    __block BOOL completionHandlerCalled = NO;

    BOOL (^handlerCheck)(id obj) = ^(id obj) {
        void (^handler)(UAActionResult *) = obj;
        if (handler) {
            handler([UAActionResult emptyResult]);
        }
        return YES;
    };


    // Expected actions payload
    NSMutableDictionary *expectedActionPayload = [NSMutableDictionary dictionary];
    [expectedActionPayload addEntriesFromDictionary:self.notification[@"com.urbanairship.interactive_actions"][@"foregroundIdentifier"]];
    expectedActionPayload[kUAIncomingPushActionRegistryName] = self.notification;

    [[self.mockActionRunner expect]runActionsWithActionValues:expectedActionPayload
                                                    situation:UASituationForegroundInteractiveButton
                                                     metadata: @{ UAActionMetadataUserNotificationActionIDKey: @"foregroundIdentifier",
                                                                  UAActionMetadataPushPayloadKey: self.notification }
                                            completionHandler:[OCMArg checkWithBlock:handlerCheck]];


    [[self.mockedAnalytics expect] handleNotification:self.notification inApplicationState:UIApplicationStateActive];
    [[self.mockedAnalytics expect] addEvent:[OCMArg checkWithBlock:^BOOL(id obj) {
        return [obj isKindOfClass:[UAInteractiveNotificationEvent class]];
    }]];

    [self.push appReceivedActionWithIdentifier:@"foregroundIdentifier"
                                  notification:self.notification
                              applicationState:UIApplicationStateActive
                             completionHandler:^{
                                 completionHandlerCalled = YES;
                             }];


    XCTAssertNoThrow([self.mockActionRunner verify],
                     @"Actions should run for notification action button");

    XCTAssertNoThrow([self.mockedAnalytics verify],
                     @"Analytics should be notified of the incoming notification");

    XCTAssertTrue(completionHandlerCalled, @"Completion handler should be called.");

}

/**
 * Test receiving a notification action with an unknown category does not run
 * any actions.
 */
- (void)testNotificationActionButtonUnknownCategory {
    __block BOOL completionHandlerCalled = NO;

    [[self.mockActionRunner reject] runActionsWithActionValues:OCMOCK_ANY
                                                     situation:UASituationForegroundInteractiveButton
                                                      metadata:OCMOCK_ANY
                                             completionHandler:OCMOCK_ANY];

    [[self.mockActionRunner reject] runActionsWithActionValues:OCMOCK_ANY
                                                     situation:UASituationBackgroundInteractiveButton
                                                      metadata:OCMOCK_ANY
                                             completionHandler:OCMOCK_ANY];

    [[self.mockedAnalytics expect] handleNotification:self.notification inApplicationState:UIApplicationStateActive];
    [[self.mockedAnalytics reject] addEvent:[OCMArg checkWithBlock:^BOOL(id obj) {
        return [obj isKindOfClass:[UAInteractiveNotificationEvent class]];
    }]];

    [self.push appReceivedActionWithIdentifier:@"foregroundIdentifier"
                                  notification:self.notification
                              applicationState:UIApplicationStateActive
                             completionHandler:^{
                                 completionHandlerCalled = YES;
                             }];


    XCTAssertNoThrow([self.mockActionRunner verify],
                     @"Actions should not run any actions if its unable to find the category");

    XCTAssertNoThrow([self.mockedAnalytics verify],
                     @"Analytics should be notified of the incoming notification");

    XCTAssertTrue(completionHandlerCalled, @"Completion handler should be called.");
}

/**
 * Test receiving a notification action with an unknown action does not run
 * any UA actions.
 */
- (void)testNotificationActionButtonUnknownIdentifier {
    UIMutableUserNotificationAction *foregroundAction = [[UIMutableUserNotificationAction alloc] init];
    foregroundAction.activationMode = UIUserNotificationActivationModeForeground;
    foregroundAction.identifier = @"foregroundIdentifier";

    UIMutableUserNotificationAction *backgroundAction = [[UIMutableUserNotificationAction alloc] init];
    backgroundAction.activationMode = UIUserNotificationActivationModeBackground;
    backgroundAction.identifier = @"backgroundIdentifier";

    UIMutableUserNotificationCategory *category = [[UIMutableUserNotificationCategory alloc] init];
    [category setActions:@[foregroundAction, backgroundAction] forContext:UIUserNotificationActionContextMinimal];
    category.identifier = @"notificationCategory";

    UIUserNotificationSettings *settings = [UIUserNotificationSettings settingsForTypes:0 categories:[NSSet setWithArray:@[category]]];
    [[[self.mockedApplication stub] andReturn:settings] currentUserNotificationSettings];

    __block BOOL completionHandlerCalled = NO;

    [[self.mockActionRunner reject] runActionsWithActionValues:OCMOCK_ANY
                                                     situation:UASituationForegroundInteractiveButton
                                                      metadata:OCMOCK_ANY
                                             completionHandler:OCMOCK_ANY];

    [[self.mockActionRunner reject] runActionsWithActionValues:OCMOCK_ANY
                                                     situation:UASituationBackgroundInteractiveButton
                                                      metadata:OCMOCK_ANY
                                             completionHandler:OCMOCK_ANY];

    [[self.mockedAnalytics expect] handleNotification:self.notification inApplicationState:UIApplicationStateActive];
    [[self.mockedAnalytics reject] addEvent:[OCMArg checkWithBlock:^BOOL(id obj) {
        return [obj isKindOfClass:[UAInteractiveNotificationEvent class]];
    }]];

    [self.push appReceivedActionWithIdentifier:@"unknown!"
                                  notification:self.notification
                              applicationState:UIApplicationStateActive
                             completionHandler:^{
                                 completionHandlerCalled = YES;
                             }];


    XCTAssertNoThrow([self.mockActionRunner verify],
                     @"Actions should not run any actions if its unable to find the category");

    XCTAssertNoThrow([self.mockedAnalytics verify],
                     @"Analytics should be notified of the incoming notification");

    XCTAssertTrue(completionHandlerCalled, @"Completion handler should be called.");
}

/**
 * Test that UAUserNotificationCategory is converted UIUserNotificationCategory iff iOS >= 8.
 */
- (void)testNormalizeCategories {

    UAMutableUserNotificationCategory *uaCategory = [[UAMutableUserNotificationCategory alloc] init];
    uaCategory.identifier = @"uaCategory";

    UIMutableUserNotificationCategory *uiCategory = [[UIMutableUserNotificationCategory alloc] init];
    uiCategory.identifier = @"uiCategory";

    UIMutableUserNotificationCategory *otherUICategory = [[UIMutableUserNotificationCategory alloc] init];
    otherUICategory.identifier = @"otherUICategory";

    NSSet *mixedSet = [NSSet setWithArray:@[uaCategory, uiCategory, otherUICategory]];
    NSSet *normalizedSet = [self.push normalizeCategories:mixedSet];

    // All should be the UI variant
    for (UIUserNotificationCategory *category in normalizedSet) {
        XCTAssertTrue([category isKindOfClass:[UIUserNotificationCategory class]]);
    }

    // Count should match
    XCTAssertEqual(mixedSet.count, normalizedSet.count);

    id iOS7Push = [OCMockObject partialMockForObject:self.push];

    // iOS < 8
    [[[iOS7Push stub] andReturnValue:OCMOCK_VALUE(NO)] shouldUseUIUserNotificationCategories];

    UAMutableUserNotificationCategory *otherUACategory = [[UAMutableUserNotificationCategory alloc] init];
    otherUACategory.identifier = @"otherUACategory";

    // UIUserNotificationCategory is not available at runtime on iOS 7 and below
    NSSet *uaSet = [NSSet setWithArray:@[uaCategory, otherUACategory]];
    normalizedSet = [iOS7Push normalizeCategories:uaSet];

    // All should be the UA variant
    for (UIUserNotificationCategory *category in normalizedSet) {
        XCTAssertTrue([category isKindOfClass:[UAUserNotificationCategory class]]);
    }

    // Count should match
    XCTAssertEqual(uaSet.count, normalizedSet.count);

    [iOS7Push stopMocking];
}

/**
 * Test setting user notification categories sanitizes category types according to OS version, 
 * and filters out any category with the reserved prefix "ua_".
 */
- (void)testSetUserNotificationCategories {
    id mockPush = [OCMockObject partialMockForObject:self.push];

    UIMutableUserNotificationCategory *uaCategory = [[UIMutableUserNotificationCategory alloc] init];
    uaCategory.identifier = @"ua_category";

    UIMutableUserNotificationCategory *customCategory = [[UIMutableUserNotificationCategory alloc] init];
    customCategory.identifier = @"customCategory";

    UIMutableUserNotificationCategory *anotherCustomCategory = [[UIMutableUserNotificationCategory alloc] init];
    anotherCustomCategory.identifier = @"anotherCustomCategory";

    NSSet *categories = [NSSet setWithArray:@[uaCategory, customCategory, anotherCustomCategory]];
    [[[mockPush expect] andReturn:categories] normalizeCategories:categories];

    // Recast for convenience
    UAPush *push = mockPush;

    push.userNotificationCategories = categories;

    [mockPush verify];

    XCTAssertEqual(2, push.userNotificationCategories.count, @"Should filter out any categories with prefix ua_");
    XCTAssertFalse([push.userNotificationCategories containsObject:uaCategory], @"Should filter out any categories with prefix ua_");
    XCTAssertTrue([push.userNotificationCategories containsObject:customCategory], @"Should not filter out categories without prefix ua_");
    XCTAssertTrue([push.userNotificationCategories containsObject:anotherCustomCategory], @"Should filter out any categories with prefix ua_");
    XCTAssertTrue(push.shouldUpdateAPNSRegistration, "Any APNS changes should update the flag.");

    [mockPush stopMocking];
}

/**
 * Test that setting all user notification categories sanitizes
 * category types.
 */
- (void)testSetAllUserNotificationCategories {
    id mockPush = [OCMockObject partialMockForObject:self.push];

    UIMutableUserNotificationCategory *customCategory = [[UIMutableUserNotificationCategory alloc] init];
    customCategory.identifier = @"customCategory";

    UIMutableUserNotificationCategory *anotherCustomCategory = [[UIMutableUserNotificationCategory alloc] init];
    anotherCustomCategory.identifier = @"anotherCustomCategory";

    NSSet *categories = [NSSet setWithArray:@[customCategory, anotherCustomCategory]];

    [[[mockPush expect] andReturn:categories] normalizeCategories:categories];

    ((UAPush *)mockPush).allUserNotificationCategories = categories;

    [mockPush verify];
    [mockPush stopMocking];
}

/**
 * Test that updating all user notification categories results in unioning the
 * default categories with the user supplied categories.
 */
- (void)testUpdateAllUserNotificationCategories {

    id mockPush = [OCMockObject partialMockForObject:self.push];
    // Recast for convenience
    UAPush *push = mockPush;

    UIMutableUserNotificationCategory *customCategory = [[UIMutableUserNotificationCategory alloc] init];
    customCategory.identifier = @"customCategory";

    UIMutableUserNotificationCategory *anotherCustomCategory = [[UIMutableUserNotificationCategory alloc] init];
    anotherCustomCategory.identifier = @"anotherCustomCategory";

    NSSet *userCategories = [NSSet setWithArray:@[customCategory, anotherCustomCategory]];
    NSSet *defaultCategories = [UAUserNotificationCategories defaultCategoriesWithRequireAuth:push.requireAuthorizationForDefaultCategories];

    push.userNotificationCategories = userCategories;

    NSMutableSet *allCategories = [NSMutableSet setWithSet:push.userNotificationCategories];
    NSSet *normalizedDefaultCategories = [push normalizeCategories:defaultCategories];
    [allCategories unionSet:normalizedDefaultCategories];

    [[mockPush expect] setAllUserNotificationCategories:[OCMArg any]];
    [push updateAllUserNotificationCategories];

    XCTAssertEqual(allCategories.count, push.allUserNotificationCategories.count,
                   @"allCategories and push.allUserNotificationCategories should have the same count");

    [mockPush verify];
    [mockPush stopMocking];
}

/**
 * Test when allowUnregisteringUserNotificationTypes is NO it prevents UAPush from
 * unregistering user notification types.
 */
- (void)testDisallowUnregisteringUserNotificationTypes {
    self.push.userPushNotificationsEnabled = YES;
    self.push.deviceToken = validDeviceToken;
    self.push.shouldUpdateAPNSRegistration = NO;
    self.push.requireSettingsAppToDisableUserNotifications = NO;

    // Turn off allowing unregistering user notification types
    self.push.allowUnregisteringUserNotificationTypes = NO;

    // Make sure we have previously registered types
    UIUserNotificationSettings *settings = [UIUserNotificationSettings settingsForTypes:UIUserNotificationTypeBadge categories:nil];
    [[[self.mockedApplication stub] andReturn:settings] currentUserNotificationSettings];

    [[[self.mockedApplication stub] andReturnValue:OCMOCK_VALUE((NSUInteger)30)] beginBackgroundTaskWithExpirationHandler:OCMOCK_ANY];

    // Add a device token so we get a device api callback
    [[self.mockedChannelRegistrar expect] registerWithChannelID:OCMOCK_ANY
                                                channelLocation:OCMOCK_ANY
                                                    withPayload:OCMOCK_ANY
                                                     forcefully:NO];


    // The flag allowUnregisteringUserNotificationTypes should prevent unregistering notification types
    [[self.mockedApplication reject] registerUserNotificationSettings:OCMOCK_ANY];


    self.push.userPushNotificationsEnabled = NO;

    XCTAssertFalse(self.push.userPushNotificationsEnabled,
                   @"userPushNotificationsEnabled should be disabled when set to NO");

    XCTAssertFalse([self.dataStore boolForKey:UAUserPushNotificationsEnabledKey],
                   @"userPushNotificationsEnabled should be stored in standardUserDefaults");

    XCTAssertNoThrow([self.mockedApplication verify],
                     @"userPushNotificationsEnabled should unregister for remote notifications");
}

/**
 * Test channel ID is returned when both channel ID and channel location exist.
 */
- (void)testChannelID {
    [self.dataStore setValue:@"channel ID" forKey:@"UAChannelID"];
    [self.dataStore setValue:@"channel Location" forKey:@"UAChannelLocation"];

    XCTAssertEqualObjects(self.push.channelID, @"channel ID", @"Should return channel ID");
}

/**
 * Test channelID returns nil when channel ID does not exist.
 */
- (void)testChannelIDNoChannel {
    [self.dataStore removeObjectForKey:@"UAChannelID"];
    [self.dataStore setValue:@"channel Location" forKey:@"UAChannelLocation"];

    XCTAssertNil(self.push.channelID, @"Channel ID should be nil");
}

/**
 * Test channelID returns nil when channel location does not exist.
 */
- (void)testChannelIDNoLocation {
    [self.dataStore setValue:@"channel ID" forKey:@"UAChannelID"];
    [self.dataStore removeObjectForKey:@"UAChannelLocation"];

    XCTAssertNil(self.push.channelID, @"Channel ID should be nil");
}

/**
 * Test channel location is returned when both channel ID and channel location exist.
 */
- (void)testChannelLocation {
    [self.dataStore setValue:@"channel ID" forKey:@"UAChannelID"];
    [self.dataStore setValue:@"channel Location" forKey:@"UAChannelLocation"];

    XCTAssertEqualObjects(self.push.channelLocation, @"channel Location", @"Should return channel location");
}

/**
 * Test channelLocation returns nil when channel ID does not exist.
 */
- (void)testChannelLocationNoChannel {
    [self.dataStore removeObjectForKey:@"UAChannelID"];
    [self.dataStore setValue:@"channel Location" forKey:@"UAChannelLocation"];

    XCTAssertNil(self.push.channelLocation, @"Channel location should be nil");
}

/**
 * Test channelLocation returns nil when channel location does not exist.
 */
- (void)testChannelLocationNoLocation {
    [self.dataStore setValue:@"channel ID" forKey:@"UAChannelID"];
    [self.dataStore removeObjectForKey:@"UAChannelLocation"];

    XCTAssertNil(self.push.channelLocation, @"Channel location should be nil");
}

/**
 * Tests tag group addition when tag group contains white space
 */
- (void)testAddTagGroupWhitespaceRemoval {
    NSArray *tags = @[@"   tag-one   ", @"tag-two   "];
    NSArray *tagsNoSpaces = @[@"tag-one", @"tag-two"];
    NSString *groupID = @"test_group_id";

    [self.push addTags:tags group:groupID];

    XCTAssertEqualObjects(tagsNoSpaces, [self.push.pendingAddTags valueForKey:groupID], @"whitespace was not trimmed from tags");

    NSArray *moreTags = @[@"   tag-two   ", @"tag-three   "];

    [self.push addTags:moreTags group:groupID];

    NSMutableArray *combinedTags = [NSMutableArray arrayWithArray:@[@"tag-one", @"tag-two", @"tag-three"]];

    [combinedTags removeObjectsInArray:[self.push.pendingAddTags valueForKey:groupID]];

    XCTAssertTrue(combinedTags.count == 0, @"whitespace was not trimmed from tags");
}

/**
 * Tests tag group removal when tag group contains white space
 */
- (void)testRemoveTagGroupWhitespaceRemoval {
    NSArray *tags = @[@"   tag-one   ", @"tag-two   "];
    NSArray *tagsNoSpaces = @[@"tag-one", @"tag-two"];
    NSString *groupID = @"test_group_id";

    [self.push removeTags:tags group:groupID];

    XCTAssertEqualObjects(tagsNoSpaces, [self.push.pendingRemoveTags valueForKey:groupID], @"whitespace was not trimmed from tags");

    NSArray *moreTags = @[@"   tag-two   ", @"tag-three   "];

    [self.push removeTags:moreTags group:groupID];

    NSMutableArray *combinedTags = [NSMutableArray arrayWithArray:@[@"tag-one", @"tag-two", @"tag-three"]];

    [combinedTags removeObjectsInArray:[self.push.pendingRemoveTags valueForKey:groupID]];

    XCTAssertTrue(combinedTags.count == 0, @"whitespace was not trimmed from tags");
}

/**
 * Test pendingAddTags.
 */
- (void)testPendingAddTags {
    self.push.pendingAddTags = self.addTagGroups;

    XCTAssertEqual((NSUInteger)1, self.push.pendingAddTags.count, @"should contain 1 tag group");
    XCTAssertEqualObjects(self.addTagGroups, self.push.pendingAddTags, @"pendingAddTags are not stored correctly");
    XCTAssertEqualObjects([self.dataStore valueForKey:UAPushAddTagGroupsSettingsKey], self.push.pendingAddTags,
                          @"pendingAddTags are not stored correctly in standardUserDefaults");

    // test addTags
    NSArray *tags = @[@"tag1", @"tag2", @"tag3"];
    [self.push addTags:tags group:@"another-tag-group"];

    XCTAssertEqual((NSUInteger)2, self.push.pendingAddTags.count, @"should contain 2 tag groups");

    // test addTags with overlapping tags in same group
    NSArray *tags2 = @[@"tag3", @"tag4", @"tag5"];
    [self.push addTags:tags2 group:@"another-tag-group"];
    XCTAssertEqual((NSUInteger)2, self.push.pendingAddTags.count, @"should contain 2 tag groups");
    NSArray *anotherTagArray = [self.push.pendingAddTags objectForKey:@"another-tag-group"];
    XCTAssertEqual((NSUInteger)5, anotherTagArray.count, @"should contain 5 tags in array");

    // test addTags with empty tags
    NSArray *emptyTagsArray = @[];
    [self.push addTags:emptyTagsArray group:@"some-tag-group"];
    XCTAssertEqual((NSUInteger)2, self.push.pendingAddTags.count, @"should still contain 2 tag groups");

    // test addTags with an empty group ID
    [self.push addTags:tags2 group:@""];
    XCTAssertEqual((NSUInteger)2, self.push.pendingAddTags.count, @"should still contain 2 tag groups");

    // test addTags with tags with whitespace
    NSArray *whitespaceTags = @[@"tag1", @"tag2", @" tag6 "];
    [self.push addTags:whitespaceTags group:@"another-tag-group"];
    XCTAssertEqual((NSUInteger)2, self.push.pendingAddTags.count, @"should contain 2 tag groups");
    anotherTagArray = [self.push.pendingAddTags objectForKey:@"another-tag-group"];
    XCTAssertEqual((NSUInteger)6, anotherTagArray.count, @"should contain 6 tags in array");

    self.push.pendingAddTags = nil;
    XCTAssertEqual((NSUInteger)0, self.push.pendingAddTags.count, @"pendingAddTags should return an empty dictionary when set to nil");
    XCTAssertEqual((NSUInteger)0, [[self.dataStore valueForKey:UAPushAddTagGroupsSettingsKey] count],
                   @"pendingAddTags not being cleared in standardUserDefaults");
}

/**
 * Test pendingAddTags when pendingRemoveTags overlap.
 */
- (void)testAddTagGroupsOverlap {
    self.push.pendingAddTags = nil;
    self.push.pendingRemoveTags = self.removeTagGroups;
    NSArray *removeTagsArray = [self.push.pendingRemoveTags objectForKey:@"tag_group"];
    XCTAssertEqual((NSUInteger)3, removeTagsArray.count, @"should contain 3 tags in array");

    NSArray *tags = @[@"tag1", @"tag2", @"tag3"];
    [self.push addTags:tags group:@"tag_group"];
    NSArray *updatedRemoveTagsArray = [self.push.pendingRemoveTags objectForKey:@"tag_group"];
    XCTAssertEqual((NSUInteger)2, updatedRemoveTagsArray.count, @"should contain 2 tags in array");

    NSArray *addTagsArray = [self.push.pendingAddTags objectForKey:@"tag_group"];
    XCTAssertEqual((NSUInteger)3, addTagsArray.count, @"should contain 3 tags in array");
}

/**
 * Test pendingRemoveTags.
 */
- (void)testRemoveTagGroups {
    self.push.pendingRemoveTags = self.removeTagGroups;

    XCTAssertEqual((NSUInteger)1, self.push.pendingRemoveTags.count, @"should contain 1 tag group");
    XCTAssertEqualObjects(self.removeTagGroups, self.push.pendingRemoveTags, @"pendingRemoveTags are not stored correctly");
    XCTAssertEqualObjects([self.dataStore valueForKey:UAPushRemoveTagGroupsSettingsKey], self.push.pendingRemoveTags,
                          @"pendingRemoveTags are not stored correctly in standardUserDefaults");

    // test removeTags
    NSArray *tags = @[@"tag1", @"tag2", @"tag3"];
    [self.push removeTags:tags group:@"another-tag-group"];

    XCTAssertEqual((NSUInteger)2, self.push.pendingRemoveTags.count, @"should contain 2 tag groups");

    // test removeTags with overlapping tags in same group
    NSArray *tags2 = @[@"tag3", @"tag4", @"tag5"];
    [self.push removeTags:tags2 group:@"another-tag-group"];
    XCTAssertEqual((NSUInteger)2, self.push.pendingRemoveTags.count, @"should contain 2 tag groups");
    NSArray *anotherTagArray = [self.push.pendingRemoveTags objectForKey:@"another-tag-group"];
    XCTAssertEqual((NSUInteger)5, anotherTagArray.count, @"should contain 5 tags");

    // test removeTags with empty tags
    NSArray *emptyTagsArray = @[];
    [self.push removeTags:emptyTagsArray group:@"some-tag-group"];
    XCTAssertEqual((NSUInteger)2, self.push.pendingRemoveTags.count, @"should still contain 2 tag groups");

    // test removeTags with empty group ID
    [self.push addTags:tags2 group:@""];
    XCTAssertEqual((NSUInteger)2, self.push.pendingRemoveTags.count, @"should still contain 2 tag groups");

    self.push.pendingRemoveTags = nil;
    XCTAssertEqual((NSUInteger)0, self.push.pendingRemoveTags.count, @"pendingRemoveTags should return an empty dictionary when set to nil");
    XCTAssertEqual((NSUInteger)0, [[self.dataStore valueForKey:UAPushRemoveTagGroupsSettingsKey] count],
                   @"pendingRemoveTags not being cleared in standardUserDefaults");
}

/**
 * Test pendingRemoveTags when pendingAddTags overlap.
 */
- (void)testRemoveTagGroupsOverlap {
    self.push.pendingRemoveTags = nil;
    self.push.pendingAddTags = self.addTagGroups;
    NSArray *addTagsArray = [self.push.pendingAddTags objectForKey:@"tag_group"];
    XCTAssertEqual((NSUInteger)3, addTagsArray.count, @"should contain 3 tags in array");

    NSArray *tags = @[@"tag3", @"tag4", @"tag5"];
    [self.push removeTags:tags group:@"tag_group"];
    NSArray *updatedAddTagsArray = [self.push.pendingAddTags objectForKey:@"tag_group"];
    XCTAssertEqual((NSUInteger)2, updatedAddTagsArray.count, @"should contain 2 tags in array");

    NSArray *removeTagsArray = [self.push.pendingRemoveTags objectForKey:@"tag_group"];
    XCTAssertEqual((NSUInteger)3, removeTagsArray.count, @"should contain 3 tags in array");
}

/**
 * Test pending tags intersect.
 */
- (void)testRemoveTagGroupsIntersect {
    self.push.pendingRemoveTags = nil;
    self.push.pendingAddTags = nil;

    NSArray *tags = @[@"tag1", @"tag2", @"tag3"];

    [self.push addTags:tags group:@"tagGroup"];

    NSArray *addTags = [self.push.pendingAddTags objectForKey:@"tagGroup"];
    XCTAssertEqual((NSUInteger)3, addTags.count, @"should contain 3 tags in array");

    [self.push removeTags:tags group:@"tagGroup"];
    XCTAssertNil([self.push.pendingAddTags objectForKey:@"tagGroup"], @"tags should be nil");
    NSArray *removeTags = [self.push.pendingRemoveTags objectForKey:@"tagGroup"];
    XCTAssertEqual((NSUInteger)3, removeTags.count, @"should contain 3 tags in array");

    [self.push addTags:tags group:@"tagGroup"];
    XCTAssertNil([self.push.pendingRemoveTags objectForKey:@"tagGroup"], @"tags should be nil");
    addTags = [self.push.pendingAddTags objectForKey:@"tagGroup"];
    XCTAssertEqual((NSUInteger)3, addTags.count, @"should contain 3 tags in array");
}

/**
 * Test adding and removing tags to device tag group pass when channelTagRegistrationEnabled is false.
 */
- (void)testChannelTagReigstrationDisabled {
    self.push.channelTagRegistrationEnabled = NO;
    self.push.pendingAddTags = nil;
    self.push.pendingRemoveTags = nil;

    NSArray *tagsToAdd = @[@"tag1", @"tag2", @"tag3"];
    [self.push addTags:tagsToAdd group:@"device"];

    NSArray *addTags = [self.push.pendingAddTags objectForKey:@"device"];
    XCTAssertEqual((NSUInteger)3, addTags.count, @"should contain 3 tags in array");

    NSArray *tagsToRemove = @[@"tag4", @"tag5", @"tag6"];
    [self.push removeTags:tagsToRemove group:@"device"];

    NSArray *removeTags = [self.push.pendingRemoveTags objectForKey:@"device"];
    XCTAssertEqual((NSUInteger)3, removeTags.count, @"should contain 3 tags in array");
}

/**
 * Test adding and removing tags to device tag group fails when channelTagRegistrationEnabled is true.
 */
- (void)testChannelTagRegistrationEnabled {
    self.push.channelTagRegistrationEnabled = YES;
    self.push.pendingAddTags = nil;
    self.push.pendingRemoveTags = nil;

    NSArray *tagsToAdd = @[@"tag1", @"tag2", @"tag3"];
    [self.push addTags:tagsToAdd group:@"device"];
    XCTAssertNil([self.push.pendingAddTags objectForKey:@"device"], @"tags should be nil");

    NSArray *tagsToRemove = @[@"tag4", @"tag5", @"tag6"];
    [self.push removeTags:tagsToRemove group:@"device"];
    XCTAssertNil([self.push.pendingRemoveTags objectForKey:@"device"], @"tags should be nil");
}

/**
 * Test successful update channel tags.
 */
- (void)testUpdateChannelTags {
    self.push.channelID = @"AAAAAAAA-BBBB-CCCC-DDDD-EEEEEEEEEEEE";
    self.push.pendingAddTags = self.addTagGroups;
    self.push.pendingRemoveTags = self.removeTagGroups;

    // Expect the tagGroupsAPIClient to update channel tags and call the success block
    [[[self.mockTagGroupsAPIClient expect] andDo:updateChannelTagsSuccessDoBlock] updateChannelTags:OCMOCK_ANY
                                                                                                add:OCMOCK_ANY
                                                                                             remove:OCMOCK_ANY
                                                                                          onSuccess:OCMOCK_ANY
                                                                                          onFailure:OCMOCK_ANY];

    // Mock background task so background task check passes
    [[[self.mockedApplication stub] andReturnValue:OCMOCK_VALUE((NSUInteger)1)] beginBackgroundTaskWithExpirationHandler:OCMOCK_ANY];

    [self.push updateRegistration];

    XCTAssertNoThrow([self.mockTagGroupsAPIClient verify], @"Update channel tag groups should succeed.");
    XCTAssertEqual((NSUInteger)0, self.push.pendingAddTags.count, @"pendingAddTags should return an empty dictionary");
    XCTAssertEqual((NSUInteger)0, self.push.pendingRemoveTags.count, @"pendingRemoveTags should return an empty dictionary");
}

/**
 * Test update channel tags fails and restores original pending tags.
 */
- (void)testUpdateChannelTagGroupsFails {
    self.push.channelID = nil;
    self.push.pendingAddTags = self.addTagGroups;
    self.push.pendingRemoveTags = self.removeTagGroups;

    // Expect the tagGroupsAPIClient to fail to update channel tags and call the failure block
    [[[self.mockTagGroupsAPIClient expect] andDo:updateChannelTagsFailureDoBlock] updateChannelTags:OCMOCK_ANY
                                                                                                add:OCMOCK_ANY
                                                                                             remove:OCMOCK_ANY
                                                                                          onSuccess:OCMOCK_ANY
                                                                                          onFailure:OCMOCK_ANY];

    // Mock background task so background task check passes
    [[[self.mockedApplication stub] andReturnValue:OCMOCK_VALUE((NSUInteger)1)] beginBackgroundTaskWithExpirationHandler:OCMOCK_ANY];

    [self.push updateRegistration];

    XCTAssertNoThrow([self.mockTagGroupsAPIClient verify], @"Update channel tag groups should fail.");
    XCTAssertEqual((NSUInteger)1, self.push.pendingAddTags.count, @"should contain 1 tag group");
    XCTAssertEqual((NSUInteger)1, self.push.pendingRemoveTags.count, @"should contain 1 tag group");
}

/**
 * Test failed update channel tags restores original pending tags and current pending tags.
 */
- (void)testUpdateChannelTagGroupsFailsPendingTags {
    self.push.channelID = @"AAAAAAAA-BBBB-CCCC-DDDD-EEEEEEEEEEEE";
    self.push.pendingAddTags = self.addTagGroups;
    self.push.pendingRemoveTags = self.removeTagGroups;

    // Expect the tagGroupsAPIClient to fail to update channel tags and call the failure block
    [[[self.mockTagGroupsAPIClient expect] andDo:updateChannelTagsFailureDoBlock] updateChannelTags:OCMOCK_ANY
                                                                                                add:OCMOCK_ANY
                                                                                             remove:OCMOCK_ANY
                                                                                          onSuccess:OCMOCK_ANY
                                                                                          onFailure:OCMOCK_ANY];

    // Mock background task so background task check passes
    [[[self.mockedApplication stub] andReturnValue:OCMOCK_VALUE((NSUInteger)1)] beginBackgroundTaskWithExpirationHandler:OCMOCK_ANY];

    NSArray *tags = @[@"tag2", @"tag4", @"tag5"];
    [self.push updateRegistration];
    [self.push removeTags:tags group:@"tag_group"]; // move code to handle before failure block is called


    XCTAssertNoThrow([self.mockTagGroupsAPIClient verify], @"Update channel tag groups should fail.");
    XCTAssertEqual((NSUInteger)1, self.push.pendingAddTags.count, @"should contain 1 tag group");
    XCTAssertEqual((NSUInteger)1, self.push.pendingRemoveTags.count, @"should contain 1 tag group");
}

/**
 * Test update channel tags with both empty add and remove tags skips request.
 */
- (void)testUpdateChannelTagGroupsEmptyTags {
    self.push.channelID = @"AAAAAAAA-BBBB-CCCC-DDDD-EEEEEEEEEEEE";

    // Should not call updateChannelTagGroups
    [[self.mockTagGroupsAPIClient reject] updateChannelTags:OCMOCK_ANY
                                                        add:OCMOCK_ANY
                                                     remove:OCMOCK_ANY
                                                  onSuccess:OCMOCK_ANY
                                                  onFailure:OCMOCK_ANY];

    [self.push updateRegistration];

    XCTAssertNoThrow([self.mockTagGroupsAPIClient verify], @"Should skip updateChannelTags request.");
}

/**
 * Test update channel tags with empty add tags still makes request.
 */
- (void)testUpdateChannelTagGroupsEmptyAddTags {
    self.push.channelID = @"AAAAAAAA-BBBB-CCCC-DDDD-EEEEEEEEEEEE";
    self.push.pendingAddTags = self.addTagGroups;

    // Call updateChannelTagGroups
    [[self.mockTagGroupsAPIClient expect] updateChannelTags:OCMOCK_ANY
                                                        add:OCMOCK_ANY
                                                     remove:OCMOCK_ANY
                                                  onSuccess:OCMOCK_ANY
                                                  onFailure:OCMOCK_ANY];

    // Mock background task so background task check passes
    [[[self.mockedApplication stub] andReturnValue:OCMOCK_VALUE((NSUInteger)1)] beginBackgroundTaskWithExpirationHandler:OCMOCK_ANY];

    [self.push updateRegistration];

    XCTAssertNoThrow([self.mockTagGroupsAPIClient verify], @"Should call updateChannelTags request.");
}

/**
 * Test update channel tags with empty remove tags still makes request.
 */
- (void)testUpdateChannelTagGroupsEmptyRemoveTags {
    self.push.channelID = @"AAAAAAAA-BBBB-CCCC-DDDD-EEEEEEEEEEEE";
    self.push.pendingRemoveTags = self.removeTagGroups;

    // Call updateChannelTagGroups
    [[self.mockTagGroupsAPIClient expect] updateChannelTags:OCMOCK_ANY
                                                        add:OCMOCK_ANY
                                                     remove:OCMOCK_ANY
                                                  onSuccess:OCMOCK_ANY
                                                  onFailure:OCMOCK_ANY];

    // Mock background task so background task check passes
    [[[self.mockedApplication stub] andReturnValue:OCMOCK_VALUE((NSUInteger)1)] beginBackgroundTaskWithExpirationHandler:OCMOCK_ANY];

    [self.push updateRegistration];

    XCTAssertNoThrow([self.mockTagGroupsAPIClient verify], @"Should call updateChannelTags request.");
}

@end
