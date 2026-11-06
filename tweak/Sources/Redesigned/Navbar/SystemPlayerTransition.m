#import "SystemPlayerTransition.h"
#import <objc/runtime.h>
#import "Core/SGCore.h"
#import "Core/SGGlass.h"
#import "Navbar.h"

// After f728743/Sim-Radio-SwiftUI's ExpandableNowPlaying.swift and NowPlayingBackground.swift (MIT, Copyright (c) 2025
// Alexey Vorobyov), its owner's pick (2026-11-01): its playerExpandAnimation, SwiftUI's .smooth(duration: 0.3,
// extraBounce: 0), a spring of 0.3 s with no bounce; its drag's let go, closing past 30% of the screen with a fifth of the
// speed counted in; and its card (in Liquid Glass here, see below), clipped to half the compact height shut, to the screen's corners
// while it moves open, and square once open.
static const NSTimeInterval kMoveDuration = 0.3;
static const CGFloat kDragCloses = 0.3, kDragSpeedShare = 0.2;
// The dimming behind the card, as dark as the old zoom's default was.
static const CGFloat kDim = 0.5;

static char kTransitionKey;

static CGFloat screenCornerRadius(void) {
    static CGFloat radius;
    static dispatch_once_t once;
    dispatch_once(&once, ^{
        @try { radius = [[UIScreen.mainScreen valueForKey:@"_displayCornerRadius"] doubleValue]; } @catch (NSException *e) {}
        if (radius <= 0) radius = 55;
    });
    return radius;
}

static UIViewPropertyAnimator *makeAnimator(void) {
    UISpringTimingParameters *spring = nil;
    if (@available(iOS 17.0, *)) spring = [[UISpringTimingParameters alloc] initWithDuration:kMoveDuration bounce:0 initialVelocity:CGVectorMake(0, 0)];
    else spring = [[UISpringTimingParameters alloc] initWithDampingRatio:1];
    return [[UIViewPropertyAnimator alloc] initWithDuration:kMoveDuration timingParameters:spring];
}

@interface SGRSystemPlayerTransition () <UIViewControllerAnimatedTransitioning, UIViewControllerInteractiveTransitioning, UIGestureRecognizerDelegate>
@end

@implementation SGRSystemPlayerTransition {
    __weak UIViewController *_page;
    __weak UIView *_hiddenSource;   // the mini player's capsule, hidden while the card stands in for it
    id<UIViewControllerContextTransitioning> _context;
    UIViewPropertyAnimator *_animator;
    BOOL _presenting;      // the running move is the open
    BOOL _dragStarts;      // the next close is a drag's, started paused
    BOOL _dragging;        // a finger carries the card
    UIView *_host;         // the card: its material, the page and the row, moved down together by a drag
    UIVisualEffectView *_material;
    UIView *_dimView, *_mask, *_rowView;
    CGRect _sourceRect, _fullRect;
}

+ (instancetype)attachTo:(UIViewController *)page {
    SGRSystemPlayerTransition *transition = [self new];
    transition->_page = page;
    page.modalPresentationStyle = UIModalPresentationOverFullScreen;
    page.modalPresentationCapturesStatusBarAppearance = YES;
    page.transitioningDelegate = transition;   // weak in UIKit: the page keeps it
    objc_setAssociatedObject(page, &kTransitionKey, transition, OBJC_ASSOCIATION_RETAIN_NONATOMIC);
    UIPanGestureRecognizer *pull = [[UIPanGestureRecognizer alloc] initWithTarget:transition action:@selector(pulled:)];
    pull.delegate = transition;
    [page.view addGestureRecognizer:pull];
    return transition;
}

#pragma mark - UIViewControllerTransitioningDelegate

- (id<UIViewControllerAnimatedTransitioning>)animationControllerForPresentedController:(UIViewController *)presented
                                                                  presentingController:(UIViewController *)presenting
                                                                      sourceController:(UIViewController *)source {
    return self;
}

- (id<UIViewControllerAnimatedTransitioning>)animationControllerForDismissedController:(UIViewController *)dismissed {
    return self;
}

// Both ways run as interactive transitions, a drag's or not, so either can be turned back
// (UIViewControllerContextTransitioning's pause and cancel).
- (id<UIViewControllerInteractiveTransitioning>)interactionControllerForPresentation:(id<UIViewControllerAnimatedTransitioning>)animator {
    return self;
}

- (id<UIViewControllerInteractiveTransitioning>)interactionControllerForDismissal:(id<UIViewControllerAnimatedTransitioning>)animator {
    return self;
}

#pragma mark - the move

- (NSTimeInterval)transitionDuration:(id<UIViewControllerContextTransitioning>)context {
    return kMoveDuration;
}

- (void)animateTransition:(id<UIViewControllerContextTransitioning>)context {
    [self startInteractiveTransition:context];
}

- (BOOL)wantsInteractiveStart {
    return _dragStarts;
}

- (id<UIViewImplicitlyAnimating>)interruptibleAnimatorForTransition:(id<UIViewControllerContextTransitioning>)context {
    return _animator;
}

- (CGRect)sourceRectIn:(UIView *)container {
    UIView *view = self.source ? self.source() : nil;
    if (view.window) return [container convertRect:view.bounds fromView:view];
    CGRect bounds = container.bounds;
    return CGRectMake(bounds.size.width * 0.1, bounds.size.height, bounds.size.width * 0.8, 60);
}

// The card shut on the source or open over the screen, as ExpandableNowPlaying's frame goes (its height the compact
// height or the screen's, its bottom and sides on the source's or the screen's): its material clipped to the card with
// the corners NowPlayingBackground gives it, the page moved down with the card's top and cut to it, fading in as the
// mini player's row on the card's top fades out (CompactNowPlaying's opacity and RegularNowPlaying's).
- (void)showShut:(BOOL)shut {
    UIViewController *page = _page;
    UIView *view = page.view;
    CGRect card = shut ? _sourceRect : _fullRect;
    CGFloat radius = shut ? _sourceRect.size.height / 2 : screenCornerRadius();
    _material.frame = card;
    _material.layer.cornerRadius = radius;
    view.transform = CGAffineTransformMakeTranslation(0, CGRectGetMinY(card) - CGRectGetMinY(_fullRect));
    _mask.frame = CGRectMake(CGRectGetMinX(card) - CGRectGetMinX(_fullRect), 0, card.size.width, card.size.height);
    _mask.layer.cornerRadius = radius;
    view.alpha = shut ? 0 : 1;
    _rowView.frame = CGRectMake(CGRectGetMinX(card), CGRectGetMinY(card), _sourceRect.size.width, _sourceRect.size.height);
    _rowView.alpha = shut ? 1 : 0;
    _dimView.alpha = shut ? 0 : 1;
}

- (void)startInteractiveTransition:(id<UIViewControllerContextTransitioning>)context {
    UIViewController *to = [context viewControllerForKey:UITransitionContextToViewControllerKey];
    _presenting = to == _page;
    _context = context;
    BOOL dragged = _dragStarts;
    _dragStarts = NO;
    UIView *container = context.containerView;
    UIViewController *page = _page;
    UIView *view = page.view;
    _fullRect = _presenting ? [context finalFrameForViewController:page] : [context initialFrameForViewController:page];
    if (CGRectIsEmpty(_fullRect)) _fullRect = container.bounds;
    if (_presenting) {
        _dimView = [[UIView alloc] initWithFrame:container.bounds];
        _dimView.backgroundColor = [UIColor colorWithWhite:0 alpha:kDim];
        _dimView.autoresizingMask = UIViewAutoresizingFlexibleWidth | UIViewAutoresizingFlexibleHeight;
        [container addSubview:_dimView];
        _host = [[UIView alloc] initWithFrame:container.bounds];
        _host.autoresizingMask = UIViewAutoresizingFlexibleWidth | UIViewAutoresizingFlexibleHeight;
        [container addSubview:_host];
        // Liquid Glass, as the capsule it lands on (its owner, 2026-11-01: Sim Radio's thick material landing on the glass
        // capsule was jarring).
        _material = [[UIVisualEffectView alloc] initWithEffect:SGGlassEffect()];
        _material.overrideUserInterfaceStyle = UIUserInterfaceStyleDark;
        _material.clipsToBounds = YES;
        _material.layer.cornerCurve = kCACornerCurveContinuous;
        [_host addSubview:_material];
        view.transform = CGAffineTransformIdentity;
        view.frame = _fullRect;
        [_host addSubview:view];
    } else if (view.superview != _host && _host) {
        [_host addSubview:view];
    }
    // Closing, what lies under the page is laid out now, before the card moves: the app turned under the page lays it
    // out only once it shows, and the first close in landscape went over black (its owner's recording, 2026-11-06).
    if (!_presenting) {
        UIView *under = [context viewForKey:UITransitionContextToViewKey] ?: [context viewControllerForKey:UITransitionContextToViewControllerKey].view;
        [under setNeedsLayout];
        [under layoutIfNeeded];
    }
    if (!_mask) {
        _mask = [UIView new];
        _mask.backgroundColor = UIColor.blackColor;
        _mask.layer.cornerCurve = kCACornerCurveContinuous;
    }
    view.maskView = _mask;
    _material.hidden = NO;
    _sourceRect = [self sourceRectIn:container];
    // The card is the mini player while it moves (its owner, 2026-11-01: the card over the capsule read as a separate view
    // on top of it): the capsule hidden from the move's start, and shown again on the frame the card lands on it (ended:).
    UIView *capsule = self.source ? self.source() : nil;
    if (capsule.window) {
        capsule.alpha = 0;
        _hiddenSource = capsule;
    }
    [_rowView removeFromSuperview];
    _rowView = self.row ? self.row() : nil;
    _rowView.userInteractionEnabled = NO;
    if (_rowView) [_host addSubview:_rowView];
    [self showShut:_presenting];

    UIViewPropertyAnimator *animator = makeAnimator();
    __weak typeof(self) weakSelf = self;
    BOOL presenting = _presenting;
    [animator addAnimations:^{ [weakSelf showShut:!presenting]; }];
    [animator addCompletion:^(UIViewAnimatingPosition position) {
        [weakSelf ended:position == UIViewAnimatingPositionEnd presenting:presenting];
    }];
    _animator = animator;
    if (!dragged) [animator startAnimation];
}

- (void)ended:(BOOL)done presenting:(BOOL)presenting {
    id<UIViewControllerContextTransitioning> context = _context;
    UIViewController *page = _page;
    UIView *view = page.view;
    [_rowView removeFromSuperview];
    _rowView = nil;
    _host.transform = CGAffineTransformIdentity;
    // Open: the page whole and square, its material under it no longer needed; shut: gone with its card and dimming. A
    // move turned back stands as it began.
    if (presenting == done) {
        view.maskView = nil;
        view.transform = CGAffineTransformIdentity;
        view.frame = _fullRect;
        view.alpha = 1;
        _material.hidden = YES;
    } else {
        _hiddenSource.alpha = 1;
        _hiddenSource = nil;
        [view removeFromSuperview];
        [_host removeFromSuperview];
        [_dimView removeFromSuperview];
        _host = nil;
        _material = nil;
        _dimView = nil;
    }
    _animator = nil;
    _context = nil;
    _dragging = NO;
    [context completeTransition:done];
}

- (BOOL)turnBackClose {
    id<UIViewControllerContextTransitioning> context = _context;
    UIViewPropertyAnimator *animator = _animator;
    if (!context || !animator || _presenting || _dragging) return NO;
    [context pauseInteractiveTransition];
    [animator pauseAnimation];
    animator.reversed = !animator.reversed;
    [context cancelInteractiveTransition];
    [animator continueAnimationWithTimingParameters:nil durationFactor:1];
    return YES;
}

#pragma mark - the drag

// ExpandableNowPlaying's PanGesture: a drag down on the page while it shows, more down than across; not one a list under
// the finger would take back up, not on a list row's grip, and not while the progress bar or the volume is dragged (they turn the pans above them
// off).
- (BOOL)gestureRecognizerShouldBegin:(UIPanGestureRecognizer *)pull {
    UIViewController *page = _page;
    if (!page.presentingViewController) return NO;
    CGPoint speed = [pull velocityInView:pull.view];
    if (speed.y <= 0 || fabs(speed.y) < fabs(speed.x)) return NO;
    UIView *hit = [pull.view hitTest:[pull locationInView:pull.view] withEvent:nil];
    for (UIView *v = hit; v && v != pull.view; v = v.superview) {
        // A row's grip (the queue's), which moves the row up or down.
        if ([NSStringFromClass([v class]) containsString:@"ReorderControl"]) return NO;
        if (![v isKindOfClass:UIScrollView.class]) continue;
        UIScrollView *list = (UIScrollView *)v;
        if (list.scrollEnabled && list.contentSize.height > list.bounds.size.height
            && list.contentOffset.y > -list.adjustedContentInset.top + 1) return NO;
    }
    return YES;
}

// As ExpandableNowPlaying's handleGestureChange and handleGestureEnd: the card follows the finger down whole (its
// offsetY); let go past kDragCloses of the screen, a fifth of the speed counted in, it closes, its offset going back to
// nothing in the same spring as it shuts on the mini player; else it springs back. A drag while the page still opens
// rides the open, and its close turns the open back.
- (void)pulled:(UIPanGestureRecognizer *)pull {
    UIViewController *page = _page;
    UIView *screen = page.view.window ?: page.view;
    CGFloat down = MAX(0, [pull translationInView:screen].y);
    switch (pull.state) {
        case UIGestureRecognizerStateBegan:
            _dragging = YES;
            // Open and still: a close of the drag's, started paused until the let go.
            if (!_animator) {
                _dragStarts = YES;
                [page dismissViewControllerAnimated:YES completion:nil];
            }
            break;
        case UIGestureRecognizerStateChanged:
            _host.transform = CGAffineTransformMakeTranslation(0, down);
            break;
        case UIGestureRecognizerStateEnded:
        case UIGestureRecognizerStateCancelled:
        case UIGestureRecognizerStateFailed: {
            _dragging = NO;
            CGFloat speed = [pull velocityInView:screen].y;
            BOOL close = pull.state == UIGestureRecognizerStateEnded && down + speed * kDragSpeedShare > screen.bounds.size.height * kDragCloses;
            UIViewPropertyAnimator *animator = _animator;
            id<UIViewControllerContextTransitioning> context = _context;
            UIView *host = _host;
            if (!animator || !context) {
                UIViewPropertyAnimator *back = makeAnimator();
                [back addAnimations:^{ host.transform = CGAffineTransformIdentity; }];
                [back startAnimation];
                break;
            }
            // The offset goes back in the move's own spring.
            UIViewPropertyAnimator *offset = makeAnimator();
            [offset addAnimations:^{ host.transform = CGAffineTransformIdentity; }];
            if (_presenting) {
                if (close) {
                    // The open turned back: the card shuts from where it is.
                    [context pauseInteractiveTransition];
                    [animator pauseAnimation];
                    animator.reversed = YES;
                    [context cancelInteractiveTransition];
                    [animator continueAnimationWithTimingParameters:nil durationFactor:1];
                }
            } else if (close) {
                [context finishInteractiveTransition];
                [animator startAnimation];
            } else {
                // The drag's close never moved: turned back where it stands.
                animator.reversed = YES;
                [context cancelInteractiveTransition];
                [animator startAnimation];
            }
            [offset startAnimation];
            break;
        }
        default:
            break;
    }
}
@end
