// Native redesign's turn: the system tab bar's player page (SystemPlayer.m) turning sideways onto its landscape player
// (SystemLandscape.m), and back. Its own window, its own answer to which way that window may face, and its own
// animation, apart from the redesigned player's landscape lyrics (Redesigned/Player/PlayerLandscape.x).
//
// The turn is drawn here rather than left to the system, which on the phone could turn the scene with no animation at
// all (its owner's recording, 2026-11-04: the portrait page, then the landscape screen whole the next frame). The
// window comes up over the page with a picture of it, so nothing moves yet. The scene then turns with UIKit's animations
// off, and the picture is turned against it the same instant (the coordinator's targetTransform inverted), so it still
// stands where it stood on the glass. From there one spring turns the picture a quarter turn and fades it out while the
// landscape screen turns in from the same angle, and the cover flies on its own from its place on the page to its place
// on the screen, as the Music app's does. Turning back is the same the other way, the cover flying back onto the page.
// With Reduce Motion the screens only cross-fade.
//
// Spotify's iPhone Info.plist allows portrait only, and UIKit asks the app delegate's
// -application:supportedInterfaceOrientationsForWindow: in its place, so the delegate answers for this window too.
//
// Threading: main thread only.
#import <objc/runtime.h>
#import "Core/SGCore.h"
#import "Redesigned/Kit/SGRKit.h"
#import "Redesigned/Player/Player.h"
#import "SystemPlayer.h"

static const NSTimeInterval kTurn = 0.55, kTurnFade = 0.28, kTurnWait = 0.8;
static const CGFloat kTurnDamping = 0.92;

// The landscape player's window: it sets the turn's parts against the scene as its size changes (place, below).
@interface SGRSystemTurnWindow : UIWindow
@end

static UIWindow *sg_window;
static __weak UIViewController<SGRSystemTurnPage> *sg_page;
static BOOL sg_lyrics, sg_queue;   // what the page shows, for the screen to open on
// Shut from the screen (Exit Full Screen): turning the phone again does not reopen it until it has stood upright.
static BOOL sg_shut;
// On its way back to portrait: the screen lets the scene face portrait then.
static BOOL sg_leaving;
// The screen made ahead while the page is up, its colors read before the phone turns: made only as the phone turned,
// it came up over black for about half a second (its owner's recording, 2026-11-04).
static UIViewController *sg_ready;
// The landscape player in the page while the app is turned (SystemPlayer.m), which the page's lyrics and queue reach.
static __weak UIViewController *sg_embedded;

// One turn's parts: the picture of what was on the glass, the cover flying, and what is hidden while it flies.
static UIView *sg_picture;
static UIImageView *sg_flier;
static CGFloat sg_flierRadius;
static BOOL sg_flierFadesIn;     // a cover leaving the clip, which shows none: it comes out of it as it flies
static __weak UIView *sg_pageCover, *sg_screenCover;
static BOOL sg_awaiting;         // a turn asked for and its transition not come yet
static NSUInteger sg_turnCount;  // which turn the waits belong to
static BOOL sg_placed;           // the parts set against the scene's turn (place)
static CGSize sg_fromSize;       // the window's size before it
static CGAffineTransform sg_turn;
static UIInterfaceOrientation sg_landscapeSide;   // the side the screen faced, for the turn back

#pragma mark - the delegate's answer

static UIInterfaceOrientationMask (*sg_origOrientations)(id, SEL, UIApplication *, UIWindow *);

// The whole app turns, as iOS turns any app that allows it (its owner, 2026-11-06: "force the Spotify app to support
// landscape everywhere and just have it happen natively"): Spotify's Info.plist allows its iPhone portrait alone, and the
// delegate's answer stands in for it. Portrait alone after Exit Full Screen, until the phone stands upright again.
static UIInterfaceOrientationMask orientationsFor(id self, SEL _cmd, UIApplication *application, UIWindow *window) {
    if (window && window == sg_window) return sg_leaving ? UIInterfaceOrientationMaskPortrait : UIInterfaceOrientationMaskLandscape;
    return sg_shut || !SGEnabled(SGRKeyLyricsLandscape) ? UIInterfaceOrientationMaskPortrait : UIInterfaceOrientationMaskAllButUpsideDown;
}

// Spotify's own controllers that answer portrait alone for themselves are made to answer every way but upside down, as
// UIKit's default does on a phone: each class once, found from the windows' roots and what they present.
static UIInterfaceOrientationMask anyWay(id self, SEL _cmd) {
    return sg_shut || !SGEnabled(SGRKeyLyricsLandscape) ? UIInterfaceOrientationMaskPortrait : UIInterfaceOrientationMaskAllButUpsideDown;
}

static BOOL turnsAnyWay(id self, SEL _cmd) {
    return YES;
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
            if (selector == @selector(supportedInterfaceOrientations)) {
                method_setImplementation(methods[i], (IMP)anyWay);
                SGLog(@"system player: %@ turns now", name);
            } else if (selector == @selector(shouldAutorotate)) {
                method_setImplementation(methods[i], (IMP)turnsAnyWay);
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

// The delegate's own answer stays for every other window (the redesigned player's landscape lyrics answer through it
// too); one that has none answers portrait, which is what the Info.plist said.
static void answerForOrientations(void) {
    static BOOL done;
    id delegate = UIApplication.sharedApplication.delegate;
    if (done || !delegate) return;
    done = YES;
    SEL selector = @selector(application:supportedInterfaceOrientationsForWindow:);
    Method method = class_getInstanceMethod([delegate class], selector);
    if (method) sg_origOrientations = (void *)method_setImplementation(method, (IMP)orientationsFor);
    else class_addMethod([delegate class], selector, (IMP)orientationsFor, "Q@:@@");
}

UIInterfaceOrientationMask SGRSystemTurnMask(UIViewController *screen) {
    return sg_window.rootViewController == screen && !sg_leaving ? UIInterfaceOrientationMaskLandscape : UIInterfaceOrientationMaskPortrait;
}

#pragma mark - the turn

static UIWindowScene *activeScene(void) {
    for (UIScene *scene in UIApplication.sharedApplication.connectedScenes) {
        if ([scene isKindOfClass:UIWindowScene.class] && scene.activationState == UISceneActivationStateForegroundActive) return (UIWindowScene *)scene;
    }
    id scene = UIApplication.sharedApplication.connectedScenes.anyObject;
    return [scene isKindOfClass:UIWindowScene.class] ? scene : nil;
}

static void requestOrientations(UIWindowScene *scene, UIInterfaceOrientationMask mask) {
    if (@available(iOS 16.0, *)) {
        // Off until the turn is placed (startTurn) or given up on (fadeInstead): the scene then turns without the system's
        // own rotation, which this file draws instead.
        if (sg_awaiting) [UIView setAnimationsEnabled:NO];
        [sg_window.rootViewController setNeedsUpdateOfSupportedInterfaceOrientations];
        UIWindowSceneGeometryPreferencesIOS *preferences = [[UIWindowSceneGeometryPreferencesIOS alloc] initWithInterfaceOrientations:mask];
        [scene requestGeometryUpdateWithPreferences:preferences errorHandler:^(NSError *error) {
            SGLog(@"system player: the scene did not turn: %@", error.localizedDescription);
        }];
    }
}

static UIWindow *pageWindow(void) {
    return sg_page.view.window;
}

// The page's cover in its window's points, its image and its corners there; NO while it shows none.
static BOOL pageCover(UIView **view, UIImage **image, CGRect *frame, CGFloat *radius) {
    UIViewController<SGRSystemTurnPage> *page = sg_page;
    UIImage *art = nil;
    UIView *cover = [page respondsToSelector:@selector(landscapeTurnCover:)] ? [page landscapeTurnCover:&art] : nil;
    if (!cover || !art || !cover.window || cover.hidden || cover.alpha < 0.01) return NO;
    CGRect rect = [cover convertRect:cover.bounds toView:nil];
    CGFloat scale = cover.bounds.size.width > 0 ? rect.size.width / cover.bounds.size.width : 1;
    *view = cover;
    *image = art;
    *frame = rect;
    *radius = SGRRadiusArtwork * scale;
    return YES;
}

static void clearTurn(void) {
    [sg_picture removeFromSuperview];
    [sg_flier removeFromSuperview];
    sg_picture = nil;
    sg_flier = nil;
    sg_pageCover.hidden = NO;
    sg_screenCover.hidden = NO;
    sg_pageCover = nil;
    sg_screenCover = nil;
    SGRSystemLandscapeSetTurning(sg_window.rootViewController, NO);
}

static UIImageView *makeFlier(UIImage *image, CGRect frame, CGFloat radius) {
    UIImageView *flier = [[UIImageView alloc] initWithImage:image];
    flier.contentMode = UIViewContentModeScaleAspectFill;
    flier.clipsToBounds = YES;
    flier.layer.cornerCurve = kCACornerCurveContinuous;
    flier.layer.cornerRadius = radius;
    flier.bounds = CGRectMake(0, 0, frame.size.width, frame.size.height);
    flier.center = CGPointMake(CGRectGetMidX(frame), CGRectGetMidY(frame));
    return flier;
}

// A point of the picture's (laid out at `from` size, centered in `to`) where it lands turned by `turn`.
static CGPoint turned(CGPoint point, CGSize from, CGSize to, CGAffineTransform turn) {
    CGPoint offset = CGPointApplyAffineTransform(CGPointMake(point.x - from.width / 2, point.y - from.height / 2), turn);
    return CGPointMake(to.width / 2 + offset.x, to.height / 2 + offset.y);
}

// The screen's view and the window's backing, as they stand before anything turns.
static void hold(UIViewController *screen) {
    screen.view.alpha = 0;
    sg_window.backgroundColor = UIColor.blackColor;
}

// No transition came for the turn (the scene already faced that way, or would not turn): the screen comes up or goes
// with a plain fade.
static void fadeInstead(BOOL in) {
    UIWindow *window = sg_window;
    UIViewController *screen = window.rootViewController;
    sg_awaiting = NO;
    [UIView setAnimationsEnabled:YES];
    SGRAnimate(SGRMotionFade, ^{
        if (in) screen.view.alpha = 1;
        else window.alpha = 0;
        sg_picture.alpha = 0;
        sg_flier.alpha = 0;
    }, ^(BOOL finished) {
        clearTurn();
        if (!in) {
            window.hidden = YES;
            if (sg_window == window) sg_window = nil;
            [pageWindow() makeKeyWindow];
        }
    });
}

static void waitForTransition(BOOL in) {
    sg_awaiting = YES;
    sg_placed = NO;
    sg_fromSize = sg_window.bounds.size;
    NSUInteger turn = ++sg_turnCount;
    dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(kTurnWait * NSEC_PER_SEC)), dispatch_get_main_queue(), ^{
        if (sg_turnCount == turn && sg_awaiting && sg_window) fadeInstead(in);
    });
}

static void prepare(void);

static void showScreen(void) {
    UIWindowScene *scene = activeScene();
    if (!scene || sg_window || !sg_page) return;
    answerForOrientations();
    clearTurn();

    // What the page shows now, and its cover apart from it, before anything covers it.
    UIWindow *page = pageWindow();
    UIView *coverView = nil;
    UIImage *art = nil;
    CGRect coverFrame = CGRectZero;
    CGFloat coverRadius = 0;
    BOOL cover = pageCover(&coverView, &art, &coverFrame, &coverRadius);
    UIView *picture = [page snapshotViewAfterScreenUpdates:NO];

    sg_window = [[SGRSystemTurnWindow alloc] initWithWindowScene:scene];
    sg_window.windowLevel = UIWindowLevelNormal + 1;
    // The window is the mod's own, so what it presents (Sing's alerts, a line's meanings) is dark too.
    sg_window.overrideUserInterfaceStyle = UIUserInterfaceStyleDark;
    UIViewController *screen = sg_ready ?: SGRSystemMakeLandscape(sg_lyrics, sg_queue);
    sg_ready = nil;
    sg_window.rootViewController = screen;
    // Still and flat while it turns: the clip waits and the screen is drawn once, not its blur again every frame.
    SGRSystemLandscapeSetTurning(screen, YES);
    hold(screen);
    if (picture) {
        picture.frame = page.bounds;
        sg_picture = picture;
        [sg_window addSubview:picture];
    }
    if (cover) {
        sg_flier = makeFlier(art, coverFrame, coverRadius);
        sg_flierRadius = coverRadius;
        [sg_window addSubview:sg_flier];
    }
    [sg_window makeKeyAndVisible];
    // The page's own cover hides under the flier from now on. The picture keeps a copy of it, which turns away with the
    // picture and fades: pictured again without it, the page took over half a second to draw (16 Pro Max Simulator,
    // 2026-11-06), and the phone waited that long before it turned.
    if (cover) {
        coverView.hidden = YES;
        sg_pageCover = coverView;
    }
    sg_leaving = NO;
    waitForTransition(YES);
    requestOrientations(scene, UIInterfaceOrientationMaskLandscape);
    SGLog(@"system player: the page turns sideways");
}

static void hideScreen(BOOL animated) {
    UIWindowScene *scene = activeScene();
    UIWindow *window = sg_window;
    if (!window) return;
    UIViewController *screen = window.rootViewController;
    [screen dismissViewControllerAnimated:NO completion:nil];
    // The page comes back on what the screen showed, before anything of it is drawn for the turn.
    BOOL lyrics = NO, queue = NO;
    SGRSystemLandscapeShowing(screen, &lyrics, &queue);
    [sg_page landscapeLeftShowingLyrics:lyrics queue:queue];
    window.userInteractionEnabled = NO;
    sg_leaving = YES;
    if (!animated || !scene) {
        clearTurn();
        sg_window = nil;
        window.hidden = YES;
        if (scene) requestOrientations(scene, UIInterfaceOrientationMaskPortrait);
        sg_leaving = NO;
        return;
    }
    clearTurn();
    sg_landscapeSide = UIInterfaceOrientationIsLandscape(scene.interfaceOrientation) ? scene.interfaceOrientation : UIInterfaceOrientationLandscapeRight;
    // What the screen shows now, and its cover apart from it.
    UIImageView *cover = nil;
    CGRect target = CGRectZero;
    BOOL shown = SGRSystemLandscapeTurnCover(screen, &cover, &target);
    sg_flierFadesIn = NO;
    if (cover.image && !SGRReduceMotion()) {
        // From the cover, or with the clip up from the clip's middle, where it comes out of it.
        CGRect frame = shown ? [cover convertRect:cover.bounds toView:nil] : target;
        CGFloat radius = shown ? cover.layer.cornerRadius : 0;
        sg_flier = makeFlier(cover.image, frame, radius);
        sg_flierRadius = radius;
        if (shown) {
            cover.hidden = YES;
            sg_screenCover = cover;
        } else {
            sg_flier.alpha = 0;
            sg_flierFadesIn = YES;
        }
    }
    UIView *picture = [screen.view snapshotViewAfterScreenUpdates:sg_screenCover != nil];
    if (picture) {
        picture.frame = window.bounds;
        sg_picture = picture;
        [window addSubview:picture];
    }
    if (sg_flier) [window addSubview:sg_flier];
    screen.view.alpha = 0;
    window.backgroundColor = UIColor.clearColor;
    waitForTransition(NO);
    requestOrientations(scene, UIInterfaceOrientationMaskPortrait);
    SGLog(@"system player: the page turns back");
}

// After the scene has turned with animations off: the picture turns away and the new side turns in. `in` is the turn
// to landscape; `turn` is what holds the picture where it stood on the glass.
static void runTurn(BOOL in, CGAffineTransform turn) {
    UIWindow *window = sg_window;
    if (!window) return;
    UIViewController *screen = window.rootViewController;
    CGSize size = window.bounds.size;
    [screen.view layoutIfNeeded];
    UIView *picture = sg_picture;
    UIImageView *flier = sg_flier;
    // UIKit puts the screen's own view in front as the scene turns: the turn's parts go back over it.
    if (picture) [window bringSubviewToFront:picture];
    if (flier) [window bringSubviewToFront:flier];
    CGFloat pictureFit = picture.bounds.size.height > 0 ? MIN(size.width, size.height) / MAX(picture.bounds.size.width, picture.bounds.size.height) : 1;
    BOOL reduce = SGRReduceMotion();

    // Where the cover lands: the screen's, or the page's, pictured again without it.
    UIView *incoming = nil;
    CGRect target = CGRectZero;
    CGFloat targetRadius = 0;
    BOOL fadeFlier = NO;
    if (in) {
        incoming = screen.view;
        UIImageView *cover = nil;
        BOOL shown = SGRSystemLandscapeTurnCover(screen, &cover, &target);
        if (flier) {
            if (shown) {
                cover.hidden = YES;
                sg_screenCover = cover;
                targetRadius = cover.layer.cornerRadius;
            } else {
                fadeFlier = YES;   // the clip stands where the cover would: the flier melts into it
                targetRadius = 0;
            }
        }
    } else {
        UIView *coverView = nil;
        UIImage *art = nil;
        CGFloat radius = 0;
        UIWindow *page = pageWindow();
        BOOL shown = pageCover(&coverView, &art, &target, &radius);
        // Hidden only for a cover flying back onto it; none flies from the clip.
        if (shown && flier) {
            coverView.hidden = YES;
            sg_pageCover = coverView;
            targetRadius = radius;
        } else fadeFlier = YES;
        UIView *pageNow = [page snapshotViewAfterScreenUpdates:YES];
        if (pageNow) {
            pageNow.frame = window.bounds;
            UIView *above = picture ?: flier;
            if (above) [window insertSubview:pageNow belowSubview:above];
            else [window addSubview:pageNow];
            incoming = pageNow;
        }
        if (flier && !shown) target = CGRectMake(flier.center.x - flier.bounds.size.width / 2, flier.center.y - flier.bounds.size.height / 2,
                                                 flier.bounds.size.width, flier.bounds.size.height);
    }

    // The new side starts turned as the picture is, at the size that fits it there, and clear.
    CGFloat incomingFit = MAX(size.width, size.height) > 0 ? MIN(size.width, size.height) / MAX(size.width, size.height) : 1;
    if (!reduce) incoming.transform = CGAffineTransformScale(turn, incomingFit, incomingFit);
    incoming.alpha = 0;
    window.backgroundColor = UIColor.blackColor;

    void (^done)(void) = ^{
        incoming.transform = CGAffineTransformIdentity;
        if (in) {
            clearTurn();
            return;
        }
        // The page's cover is shown again first, and the window goes a frame later, once the page has drawn it.
        sg_pageCover.hidden = NO;
        if (sg_window == window) sg_window = nil;
        sg_leaving = NO;
        dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(0.05 * NSEC_PER_SEC)), dispatch_get_main_queue(), ^{
            clearTurn();
            [incoming removeFromSuperview];
            window.hidden = YES;
            [pageWindow() makeKeyWindow];
            prepare();
        });
    };
    if (reduce) {
        [UIView animateWithDuration:kTurnFade * 1.4 animations:^{
            incoming.alpha = 1;
            picture.alpha = 0;
            flier.alpha = 0;
        } completion:^(BOOL finished) { done(); }];
        return;
    }
    [UIView animateWithDuration:kTurn delay:0 usingSpringWithDamping:kTurnDamping initialSpringVelocity:0
                        options:UIViewAnimationOptionBeginFromCurrentState animations:^{
        incoming.transform = CGAffineTransformIdentity;
        picture.transform = CGAffineTransformMakeScale(pictureFit, pictureFit);
        if (flier) {
            flier.transform = CGAffineTransformIdentity;
            flier.bounds = CGRectMake(0, 0, target.size.width, target.size.height);
            flier.center = CGPointMake(CGRectGetMidX(target), CGRectGetMidY(target));
            flier.layer.cornerRadius = targetRadius;
        }
    } completion:^(BOOL finished) { done(); }];
    [UIView animateWithDuration:kTurnFade delay:0 options:UIViewAnimationOptionCurveEaseOut animations:^{
        incoming.alpha = 1;
        picture.alpha = 0;
    } completion:nil];
    if (sg_flierFadesIn && !fadeFlier) {
        [UIView animateWithDuration:kTurnFade delay:0 options:UIViewAnimationOptionCurveEaseOut animations:^{
            flier.alpha = 1;
        } completion:nil];
    }
    if (fadeFlier) {
        [UIView animateWithDuration:kTurnFade delay:kTurn - kTurnFade - 0.05 options:UIViewAnimationOptionCurveEaseIn animations:^{
            flier.alpha = 0;
        } completion:nil];
    }
}

// Sets the picture and the cover against the scene's turn, so they stand where they stood on the glass: once, from the
// screen's transition, or from the window's layout at its turned size should that come first. Either is in the same pass
// as the turned window's first frame (logged frame by frame in the Simulator, 2026-11-06). The turn then runs on the
// next pass of the main queue, with the system's own rotation of the window taken off.

static void startTurn(UIWindow *window, BOOL in) {
    dispatch_async(dispatch_get_main_queue(), ^{
        [UIView setAnimationsEnabled:YES];
        if (sg_window != window || !sg_awaiting) return;
        sg_awaiting = NO;
        // An animated transition turns the window itself from the old side to the new; the picture already stands
        // against it, so that rotation is taken off and the window stands turned at once.
        [window.layer removeAllAnimations];
        for (CALayer *layer in window.layer.sublayers) [layer removeAllAnimations];
        runTurn(in, sg_turn);
    });
}

static void place(UIWindow *window, CGSize size, CGAffineTransform turn) {
    if (sg_placed || !sg_awaiting || window != sg_window) return;
    BOOL in = size.width > size.height;
    if (in == sg_leaving) return;
    sg_placed = YES;
    sg_turn = turn;
    [UIView setAnimationsEnabled:NO];
    if (sg_picture) {
        sg_picture.center = CGPointMake(size.width / 2, size.height / 2);
        sg_picture.transform = turn;
    }
    if (sg_flier) {
        sg_flier.center = turned(sg_flier.center, sg_fromSize, size, turn);
        sg_flier.transform = turn;
    }
    startTurn(window, in);
}

// The quarter turn that undoes the scene's, from which way it faces: landscape right is the content turned a quarter
// anticlockwise from portrait (UIKit's targetTransform for it, inverted, in the Simulator on iOS 27.2).
static CGAffineTransform turnFor(UIInterfaceOrientation landscape, BOOL in) {
    CGFloat angle = landscape == UIInterfaceOrientationLandscapeLeft ? -M_PI_2 : M_PI_2;
    return CGAffineTransformMakeRotation(in ? angle : -angle);
}

@implementation SGRSystemTurnWindow
- (void)turnedTo:(CGSize)size {
    if (sg_placed || !sg_awaiting || self != sg_window) return;
    if (CGSizeEqualToSize(size, sg_fromSize) || size.width <= 0 || size.height <= 0) return;
    BOOL in = size.width > size.height;
    UIInterfaceOrientation side = in ? self.windowScene.interfaceOrientation : sg_landscapeSide;
    if (in && !UIInterfaceOrientationIsLandscape(side)) return;
    place(self, size, turnFor(side, in));
}
- (void)layoutSubviews {
    [super layoutSubviews];
    [self turnedTo:self.bounds.size];
}
@end

void SGRSystemTurnWillTransition(UIViewController *screen, CGSize size, id<UIViewControllerTransitionCoordinator> coordinator) {
    UIWindow *window = sg_window;
    if (!window || window.rootViewController != screen) return;
    // What holds the picture where it stood on the glass once the scene has turned: the turn undone.
    CGAffineTransform target = coordinator.targetTransform;
    BOOL in = size.width > size.height;
    if (!CGAffineTransformIsIdentity(target)) place(window, size, CGAffineTransformInvert(target));
    else place(window, size, turnFor(in ? UIInterfaceOrientationLandscapeRight : sg_landscapeSide, in));
}

#pragma mark - when it comes up

static BOOL pageUp(void) {
    return sg_page != nil && sg_page.view.window != nil;
}

static void prepare(void) {
    if (!pageUp() || !SGEnabled(SGRKeyLyricsLandscape)) {
        sg_ready = nil;
        return;
    }
    if (sg_ready || sg_window) return;
    sg_ready = SGRSystemMakeLandscape(sg_lyrics, sg_queue);
    CGSize screen = UIScreen.mainScreen.bounds.size;
    sg_ready.view.frame = CGRectMake(0, 0, MAX(screen.width, screen.height), MIN(screen.width, screen.height));
    [sg_ready.view layoutIfNeeded];
}

void SGRSystemTurnShow(BOOL show) {
    if (show) showScreen();
    else hideScreen(YES);
}

// Exit Full Screen: back to portrait, held there until the phone has stood upright.
void SGRSystemTurnBack(void) {
    sg_shut = YES;
    askAgain();
    UIWindowScene *scene = activeScene();
    if (scene) requestOrientations(scene, UIInterfaceOrientationMaskPortrait);
}

// Swiped down in landscape: the player page closes, the app staying as the phone is held.
void SGRSystemTurnClose(void) {
    [sg_page dismissViewControllerAnimated:YES completion:nil];
}

// The scene turns itself now (orientationsFor); the phone standing upright only lets it turn again after Exit Full Screen.
static void orientationChanged(void) {
    UIDeviceOrientation orientation = UIDevice.currentDevice.orientation;
    if (orientation == UIDeviceOrientationPortrait && sg_shut) {
        sg_shut = NO;
        askAgain();
    }
}

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
    // The screen does not outlive the page.
    if (!page) {
        hideScreen(NO);
        sg_lyrics = sg_queue = NO;
    }
}

void SGRSystemTurnSetLyrics(BOOL open) {
    sg_lyrics = open;
    SGRSystemLandscapeSetLyrics(sg_embedded, open, sg_embedded.view.window != nil);
}

void SGRSystemTurnLinesChanged(void) {
    SGRSystemLandscapeLinesChanged(sg_embedded);
}

void SGRSystemTurnSetEmbedded(UIViewController *screen) {
    sg_embedded = screen;
}

NSArray<UIMenuElement *> *SGRSystemTurnMenuItems(UIView *anchor, UIViewController *presenter, void (^changed)(void)) {
    UIViewController<SGRSystemTurnPage> *page = sg_page;
    return page ? [page landscapeMenuItemsFrom:anchor presenter:presenter changed:changed] : @[];
}

void SGRSystemTurnSetQueue(BOOL open) {
    sg_queue = open;
    SGRSystemLandscapeSetQueue(sg_embedded, open, sg_embedded.view.window != nil);
}

// The unlock as Spotify starts, so its first screens turn too, not only once the player page has been up.
__attribute__((constructor)) static void unlockAtLaunch(void) {
    if (!SGNativeRedesign()) return;
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
