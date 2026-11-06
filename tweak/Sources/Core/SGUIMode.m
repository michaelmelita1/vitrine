#import <UIKit/UIKit.h>
#import "SGUIMode.h"
#import "SGLog.h"

BOOL SGRedesignAvailable(void) {
    if (@available(iOS 26.0, *)) return YES;
    return NO;
}

BOOL SGRedesignedUI(void) {
    static BOOL on;
    static dispatch_once_t once;
    dispatch_once(&once, ^{
        on = SGRedesignAvailable();
        SGLog(@"ui: %@", on ? @"redesigned" : @"Spotify's own (the redesign needs iOS 26)");
    });
    return on;
}
