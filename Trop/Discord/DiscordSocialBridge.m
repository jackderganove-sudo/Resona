//
//  DiscordSocialBridge.m
//  Resona
//
//  No-op replacement for Trop's Discord Social SDK bridge. The SDK is
//  proprietary and only available behind a download secret, so Resona builds
//  without it. Rich presence calls are accepted and ignored; authorization
//  reports a failure so the settings UI never hangs waiting for it.
//

#import "DiscordSocialBridge.h"

@implementation DiscordSocialBridge

+ (instancetype)shared {
    static DiscordSocialBridge *bridge;
    static dispatch_once_t onceToken;
    dispatch_once(&onceToken, ^{ bridge = [DiscordSocialBridge new]; });
    return bridge;
}

- (void)authorize {
    dispatch_async(dispatch_get_main_queue(), ^{
        [self.delegate discordSocialAuthorizationFailed:@"Discord is not available in this build."];
    });
}

- (void)connectWithAccessToken:(NSString *)accessToken {}

- (void)updateActivityWithName:(NSString *)name
                 activityType:(NSInteger)activityType
                       details:(NSString *)details
                          state:(NSString *)state
                    startTimeMs:(long long)startTimeMs
                      endTimeMs:(long long)endTimeMs
                    largeImage:(NSString *)largeImage
                     largeText:(NSString *)largeText
                    smallImage:(NSString *)smallImage
                     smallText:(NSString *)smallText
                       buttons:(NSArray<NSDictionary<NSString *, NSString *> *> *)buttons {}

- (void)clearActivity {}

- (void)disconnect {}

@end
