// The app's CMHeadphoneMotionManager, run while a feature listens. It sends nothing until headphones that track
// motion are in, so starting it with none costs nothing.
#import "Core/SGCore.h"
#import "HeadMotion.h"

static CMHeadphoneMotionManager *sg_manager;
static NSOperationQueue *sg_queue;   // serial: the handlers run on it
static BOOL sg_listening;
static NSMutableDictionary<NSString *, void (^)(CMDeviceMotion *)> *sg_listeners;   // by name, main thread
static NSArray<void (^)(CMDeviceMotion *)> *sg_queueListeners;                     // their handlers, on sg_queue

// The headphones taken out or off: the listeners hear that their motion stopped. Called on the motion's queue.
@interface SGHeadMotionDelegate : NSObject <CMHeadphoneMotionManagerDelegate>
@end

@implementation SGHeadMotionDelegate
- (void)headphoneMotionManagerDidDisconnect:(CMHeadphoneMotionManager *)manager {
    [sg_queue addOperationWithBlock:^{
        for (void (^handler)(CMDeviceMotion *) in sg_queueListeners) handler(nil);
    }];
}
@end

static CMHeadphoneMotionManager *manager(void) {
    static SGHeadMotionDelegate *delegate;   // the manager holds its delegate weakly
    if (!sg_manager) {
        sg_manager = [CMHeadphoneMotionManager new];
        sg_queue = [NSOperationQueue new];
        sg_queue.maxConcurrentOperationCount = 1;
        sg_queue.qualityOfService = NSQualityOfServiceUserInitiated;
        delegate = [SGHeadMotionDelegate new];
        sg_manager.delegate = delegate;
    }
    return sg_manager;
}

static void updateListening(void) {
    BOOL listen = sg_listeners.count > 0;
    if (listen == sg_listening) return;
    sg_listening = listen;
    if (!listen) {
        [sg_manager stopDeviceMotionUpdates];
        return;
    }
    [sg_manager startDeviceMotionUpdatesToQueue:sg_queue withHandler:^(CMDeviceMotion *motion, NSError *error) {
        if (!motion) return;
        for (void (^handler)(CMDeviceMotion *) in sg_queueListeners) handler(motion);
    }];
}

void SGHeadMotionListen(NSString *name, void (^handler)(CMDeviceMotion *motion)) {
    if (!sg_listeners) sg_listeners = [NSMutableDictionary dictionary];
    void (^old)(CMDeviceMotion *) = sg_listeners[name];
    if (!old && !handler) return;
    sg_listeners[name] = [handler copy];
    manager();
    NSArray<void (^)(CMDeviceMotion *)> *handlers = sg_listeners.allValues;
    [sg_queue addOperationWithBlock:^{
        sg_queueListeners = handlers;
        if (old) old(nil);
    }];
    updateListening();
}

void SGHeadMotionAskPermission(void) {
    // Motion's permission is asked the first time the manager starts. With nothing playing that would be the first
    // song, maybe from the lock screen, so a page asks while it is in front.
    if (sg_listening || CMHeadphoneMotionManager.authorizationStatus != CMAuthorizationStatusNotDetermined) return;
    [manager() startDeviceMotionUpdates];
    dispatch_after(dispatch_time(DISPATCH_TIME_NOW, NSEC_PER_SEC), dispatch_get_main_queue(), ^{
        if (!sg_listening) [sg_manager stopDeviceMotionUpdates];
    });
}

BOOL SGHeadMotionAvailable(void) {
    return manager().deviceMotionAvailable;
}
