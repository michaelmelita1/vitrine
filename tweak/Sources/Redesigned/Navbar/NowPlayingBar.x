// Spotify's now playing bar stays, unseen and untouchable, under the redesign's mini player (Redesigned/Navbar/
// SystemTabs.x): the mini player and the player page take its cover from it (SGRNowPlayingCover), and SystemTabs.x
// stands its tab bar just above it (sgr_nowPlayingRoot). Unseen, its paint is left as Spotify sets it.
//
// Tree (trees/home.txt): NowPlayingBarContainerViewController.view 402x56 > NowPlayingBarViewController.view
//   at {8,0} 386x56 > UIView 386x56 (the painted card) > artwork 40x40 r=4, title stack, progress line.
//
// The same bar class also stands at the top of Spotify's sheets (the DJ request one: Up next, device, play). That one is
// not the tab bar's and must not become the bar this file tracks.
#import "Core/SGCore.h"
#import "Navbar.h"

// The artwork on the bar: a 36 to 48 pt square with rounded corners that is not a button, outside Spotify's Jam strip
// (a "Jam by ..." hosting view of Jam_AttachmentsImpl over the track, whose faces are such squares too).
static __weak UIView *sg_artwork;

__weak UIView *sgr_nowPlayingRoot = nil;

static BOOL isStrip(UIView *view) {
    if (view.bounds.size.height > 60) return NO;
    if (SGClassNamed(view.class, @"AttachmentsImpl") && SGClassNamed(view.class, @"Hat")) return YES;
    UIResponder *next = view.nextResponder;
    if (![next isKindOfClass:UIViewController.class]) return NO;
    return SGClassNamed(next.class, @"Jam") && SGClassNamed(next.class, @"Hat");
}

static BOOL inStrip(UIView *view, UIView *root) {
    for (UIView *v = view; v && v != root; v = v.superview) if (isStrip(v)) return YES;
    return NO;
}

static BOOL inSheet(UIView *view) {
    for (UIView *v = view.superview; v; v = v.superview) {
        if ([v.accessibilityIdentifier isEqualToString:@"sheet-view"] || SGClassNamed(v.class, @"SheetImpl")) return YES;
    }
    return NO;
}

static UIView *artworkIn(UIView *bar) {
    __block UIView *found = nil;
    SGForEachView(bar, ^(UIView *v) {
        if (found) return;
        CGSize size = v.bounds.size;
        BOOL square = size.width >= 36 && size.width <= 48 && fabs(size.width - size.height) < 1;
        if (square && v.layer.cornerRadius > 0 && ![v isKindOfClass:UIControl.class] && !inStrip(v, bar)) found = v;
    });
    return found;
}

static void followBar(UIViewController *container) {
    UIView *view = container.viewIfLoaded;
    if (!view || inSheet(view)) return;
    UIView *bar = container.childViewControllers.firstObject.viewIfLoaded ?: view;
    sgr_nowPlayingRoot = bar;
    if (![sg_artwork isDescendantOfView:bar]) sg_artwork = artworkIn(bar);
    if (view.alpha > 0) view.alpha = 0;
    view.userInteractionEnabled = NO;
}

UIImage *SGRNowPlayingCover(void) {
    __block UIImage *cover = nil;
    UIView *artwork = sg_artwork ?: sgr_nowPlayingRoot;
    SGForEachView(artwork, ^(UIView *v) {
        if (cover || ![v isKindOfClass:UIImageView.class]) return;
        UIImage *image = ((UIImageView *)v).image;
        if (image.size.width >= 24 && fabs(image.size.width - image.size.height) < 2) cover = image;
    });
    return cover;
}

%hook _TtC18NowPlaying_BarImpl36NowPlayingBarContainerViewController
- (void)viewDidLayoutSubviews {
    %orig;
    followBar((UIViewController *)self);
}
%end

%hook _TtC18NowPlaying_BarImpl27NowPlayingBarViewController
- (void)viewDidLayoutSubviews {
    %orig;
    UIViewController *parent = ((UIViewController *)self).parentViewController;
    if (SGClassNamed(parent.class, @"NowPlayingBarContainer")) followBar(parent);
}
%end

// The page the bar stands in passed touches through everywhere but the bar; the bar unseen, it takes none. Its page's
// view stayed where the card had stood and took the touches there (its owner, 2026-10-31).
%hook _TtC22NowPlaying_BarPageImplP33_CCC0D2EEA6D4725EECD8965E8C38C86D20TouchPassthroughView
- (UIView *)hitTest:(CGPoint)point withEvent:(UIEvent *)event {
    return nil;
}
%end

%ctor {
    if (!SGRedesignedUI()) return;
    %init;
    SGRequireClasses(@[
        @"_TtC18NowPlaying_BarImpl36NowPlayingBarContainerViewController",
        @"_TtC18NowPlaying_BarImpl27NowPlayingBarViewController",
        @"_TtC22NowPlaying_BarPageImplP33_CCC0D2EEA6D4725EECD8965E8C38C86D20TouchPassthroughView",
    ]);
}
