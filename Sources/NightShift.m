#import <Foundation/Foundation.h>
#import <objc/runtime.h>
#import "NightShift.h"

typedef struct { int hour; int minute; } WPClock;
typedef struct { WPClock from; WPClock to; } WPNightSchedule;
typedef struct {
    BOOL active;
    BOOL enabled;
    BOOL sunSchedulePermitted;
    int mode;
    WPNightSchedule schedule;
    unsigned long long disableFlags;
    BOOL available;
} WPBlueLightStatus;

@interface NSObject (WPNightShiftReader)
- (BOOL)supported;
- (BOOL)getBlueLightStatus:(WPBlueLightStatus *)status;
- (void)setStatusNotificationBlock:(void (^)(NSDictionary *))block;
- (void)enableNotifications;
@end

static id client(void) {
    static id instance;
    static dispatch_once_t once;
    dispatch_once(&once, ^{
        @try {
            NSBundle *bundle = [NSBundle bundleWithPath:@"/System/Library/PrivateFrameworks/CoreBrightness.framework"];
            if (![bundle load]) return;
            Class cls = NSClassFromString(@"CBBlueLightClient");
            Method method = class_getInstanceMethod(cls, @selector(getBlueLightStatus:));
            // Fail closed if Apple changes the private status structure's ABI.
            if (!method || strcmp(method_getTypeEncoding(method), "B24@0:8^{?=BBBi{?={?=ii}{?=ii}}QB}16") != 0) return;
            id candidate = [[cls alloc] init];
            if ([candidate respondsToSelector:@selector(supported)] && [candidate supported]) instance = candidate;
        } @catch (NSException *exception) { instance = nil; }
    });
    return instance;
}

int WPNightShiftActive(void) {
    @try {
        id reader = client();
        WPBlueLightStatus status = {0};
        if (!reader || ![reader getBlueLightStatus:&status]) return -1;
        return status.active ? 1 : 0;
    } @catch (NSException *exception) { return -1; }
}

void WPObserveNightShift(void (*callback)(void *), void *context) {
    @try {
        id reader = client();
        if (![reader respondsToSelector:@selector(setStatusNotificationBlock:)] ||
            ![reader respondsToSelector:@selector(enableNotifications)]) return;
        [reader setStatusNotificationBlock:^(NSDictionary *status) {
            dispatch_async(dispatch_get_main_queue(), ^{ callback(context); });
        }];
        [reader enableNotifications];
    } @catch (NSException *exception) { }
}
