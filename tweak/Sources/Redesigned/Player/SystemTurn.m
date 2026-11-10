// The redesign's landscape: the whole app turns with the phone, as iOS turns any app that allows it (its owner,
// 2026-11-06: "force the Spotify app to support landscape everywhere and just have it happen natively"), and the system
// tab bar's player page (SystemPlayer.m) holds its landscape player (SystemLandscape.m) while it is sideways. The turn is
// the system's own; this file only lets it happen and carries what the page shows to the landscape player.
//
// Spotify's iPhone Info.plist allows portrait alone. UIKit asks the app delegate's
// -application:supportedInterfaceOrientationsForWindow: in its place, so the delegate answers every way but upside down,
// and Spotify's own controllers that answer for themselves answer the same, while the turn is on. The Player page's
// Landscape switch (SGRKeyLyricsLandscape) turns it off, and Exit Full Screen until the phone has stood upright; then the
// delegate's and each controller's own answers, kept, are called, so a screen Spotify lets turn (a video) still does.
//
// Threading: main thread only.
#import <objc/runtime.h>
#import "Core/SGCore.h"
#import "Redesigned/Kit/SGRKit.h"
#import "Player.h"
#import "SystemPlayer.h"

static __weak UIViewController<SGRSystemTurnPage> *sg_page;
// The landscape player in the page while the app is turned, which the page's lyrics and queue reach.
static __weak UIViewController *sg_embedded;
// Shut from the landscape player (Exit Full Screen): portrait until the phone has stood upright.
static BOOL sg_shut;

UIView *SGRSystemTurnVideoSurface(void) {
    return [sg_page respondsToSelector:@selector(landscapeVideoSurface)] ? [sg_page landscapeVideoSurface] : nil;
}

void SGRSystemTurnVideoReturned(void) {
    if ([sg_page respondsToSelector:@selector(landscapeVideoReturned)]) [sg_page landscapeVideoReturned];
}

static BOOL turnsSideways(void) {
    return !sg_shut && SGEnabled(SGRKeyLyricsLandscape);
}

#pragma mark - the answer

// The delegate's own answer, or none (the Info.plist's portrait), for while the turn is off: kept and called, so a
// window Spotify lets turn (a video) still does (PR #199's review, 2026-11-06).
static UIInterfaceOrientationMask (*sg_delegateAnswer)(id, SEL, UIApplication *, UIWindow *);

static UIInterfaceOrientationMask orientationsFor(id self, SEL _cmd, UIApplication *application, UIWindow *window) {
    if (turnsSideways()) return UIInterfaceOrientationMaskAllButUpsideDown;
    return sg_delegateAnswer ? sg_delegateAnswer(self, _cmd, application, window) : UIInterfaceOrientationMaskPortrait;
}

static void unlockClass(Class cls) {
    static NSMutableSet<NSString *> *done;
    if (!done) done = [NSMutableSet set];
    for (Class c = cls; c && c != UIViewController.class; c = class_getSuperclass(c)) {
        NSString *name = NSStringFromClass(c);
        if ([done containsObject:name]) continue;
        [done addObject:name];
        // Only a class's own answers, not those it inherits, which a class above it has or UIKit's default gives.
        unsigned count = 0;
        Method *methods = class_copyMethodList(c, &count);
        for (unsigned i = 0; i < count; i++) {
            SEL selector = method_getName(methods[i]);
            // Each answers every way but upside down while the turn is on, and its own answer, kept, otherwise.
            if (selector == @selector(supportedInterfaceOrientations)) {
                UIInterfaceOrientationMask (*own)(id, SEL) = (UIInterfaceOrientationMask (*)(id, SEL))method_getImplementation(methods[i]);
                method_setImplementation(methods[i], imp_implementationWithBlock(^UIInterfaceOrientationMask(id me) {
                    return turnsSideways() ? UIInterfaceOrientationMaskAllButUpsideDown : own(me, selector);
                }));
            } else if (selector == @selector(shouldAutorotate)) {
                BOOL (*own)(id, SEL) = (BOOL (*)(id, SEL))method_getImplementation(methods[i]);
                method_setImplementation(methods[i], imp_implementationWithBlock(^BOOL(id me) {
                    return turnsSideways() || own(me, selector);
                }));
            }
        }
        free(methods);
    }
}

static void unlockControllers(void) {
    for (UIScene *scene in UIApplication.sharedApplication.connectedScenes) {
        if (![scene isKindOfClass:UIWindowScene.class]) continue;
        for (UIWindow *window in ((UIWindowScene *)scene).windows) {
            for (UIViewController *controller = window.rootViewController; controller; controller = controller.presentedViewController) {
                unlockClass(controller.class);
                for (UIViewController *child in controller.childViewControllers) unlockClass(child.class);
            }
        }
    }
}

// Asked again of every window's controllers, after the answer has changed.
static void askAgain(void) {
    if (@available(iOS 16.0, *)) {
        for (UIScene *scene in UIApplication.sharedApplication.connectedScenes) {
            if (![scene isKindOfClass:UIWindowScene.class]) continue;
            for (UIWindow *window in ((UIWindowScene *)scene).windows) {
                for (UIViewController *controller = window.rootViewController; controller; controller = controller.presentedViewController) {
                    [controller setNeedsUpdateOfSupportedInterfaceOrientations];
                }
            }
        }
    }
}

// The delegate's answer is this file's, in place of its own or of none (the Info.plist's portrait).
static void answerForOrientations(void) {
    static BOOL done;
    id delegate = UIApplication.sharedApplication.delegate;
    if (done || !delegate) return;
    done = YES;
    SEL selector = @selector(application:supportedInterfaceOrientationsForWindow:);
    Method method = class_getInstanceMethod([delegate class], selector);
    if (method) sg_delegateAnswer = (UIInterfaceOrientationMask (*)(id, SEL, UIApplication *, UIWindow *))method_setImplementation(method, (IMP)orientationsFor);
    else class_addMethod([delegate class], selector, (IMP)orientationsFor, "Q@:@@");
}

static UIWindowScene *activeScene(void) {
    for (UIScene *scene in UIApplication.sharedApplication.connectedScenes) {
        if ([scene isKindOfClass:UIWindowScene.class] && scene.activationState == UISceneActivationStateForegroundActive) return (UIWindowScene *)scene;
    }
    id scene = UIApplication.sharedApplication.connectedScenes.anyObject;
    return [scene isKindOfClass:UIWindowScene.class] ? scene : nil;
}

// The phone standing upright lets the app turn again after Exit Full Screen.
static void orientationChanged(void) {
    if (UIDevice.currentDevice.orientation == UIDeviceOrientationPortrait && sg_shut) {
        sg_shut = NO;
        askAgain();
    }
}

#pragma mark - the page and its landscape player

void SGRSystemTurnSetPage(UIViewController<SGRSystemTurnPage> *page) {
    static BOOL watching;
    if (!watching && page) {
        watching = YES;
        [UIDevice.currentDevice beginGeneratingDeviceOrientationNotifications];
        // Posted on the main queue by UIKit.
        [NSNotificationCenter.defaultCenter addObserverForName:UIDeviceOrientationDidChangeNotification object:nil queue:nil
                                                    usingBlock:^(NSNotification *note) { orientationChanged(); }];
    }
    sg_page = page;
    answerForOrientations();
    unlockControllers();
    askAgain();
}

void SGRSystemTurnSetEmbedded(UIViewController *screen) {
    sg_embedded = screen;
}

void SGRSystemTurnSetLyrics(BOOL open) {
    SGRSystemLandscapeSetLyrics(sg_embedded, open, sg_embedded.view.window != nil);
}

void SGRSystemTurnSetQueue(BOOL open) {
    SGRSystemLandscapeSetQueue(sg_embedded, open, sg_embedded.view.window != nil);
}

void SGRSystemTurnLinesChanged(void) {
    SGRSystemLandscapeLinesChanged(sg_embedded);
}

NSArray<UIMenuElement *> *SGRSystemTurnMenuItems(UIView *anchor, UIViewController *presenter, void (^changed)(void)) {
    UIViewController<SGRSystemTurnPage> *page = sg_page;
    return page ? [page landscapeMenuItemsFrom:anchor presenter:presenter changed:changed] : @[];
}

// Exit Full Screen: back to portrait, held there until the phone has stood upright.
void SGRSystemTurnBack(void) {
    sg_shut = YES;
    askAgain();
    UIWindowScene *scene = activeScene();
    if (@available(iOS 16.0, *)) {
        if (!scene) return;
        UIWindowSceneGeometryPreferencesIOS *preferences = [[UIWindowSceneGeometryPreferencesIOS alloc] initWithInterfaceOrientations:UIInterfaceOrientationMaskPortrait];
        [scene requestGeometryUpdateWithPreferences:preferences errorHandler:^(NSError *error) {
            SGLog(@"system player: the scene did not turn back: %@", error.localizedDescription);
        }];
    }
}

// The unlock as Spotify starts, so its first screens turn too, not only once the player page has been up.
__attribute__((constructor)) static void unlockAtLaunch(void) {
    if (!SGRedesignedUI()) return;
    [NSNotificationCenter.defaultCenter addObserverForName:UIApplicationDidFinishLaunchingNotification object:nil queue:nil
                                                usingBlock:^(NSNotification *note) {
        dispatch_async(dispatch_get_main_queue(), ^{
            answerForOrientations();
            unlockControllers();
            askAgain();
        });
    }];
    [NSNotificationCenter.defaultCenter addObserverForName:UIApplicationDidBecomeActiveNotification object:nil queue:nil
                                                usingBlock:^(NSNotification *note) {
        dispatch_async(dispatch_get_main_queue(), ^{ unlockControllers(); });
    }];
}
