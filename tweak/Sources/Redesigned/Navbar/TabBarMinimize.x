// What minimizes the system tab bar (SystemTabs.x) and what brings it back: a page scrolled down by a finger or the
// fling after it, and scrolled back up or to its top (MinimizeStep.h). After the bar changes some other way (a tab, the
// player), only a new touch minimizes it again: the fling still running would otherwise undo it at once. The bar is told
// through the controller's own setter where this iOS has one (SGRSystemTabsCanMinimize); else UIKit's own minimize on
// scroll stands in, from the page's scroll view handed to it.
//
// Only a page's own scroll views count: those inside Spotify's tab bar container. The player and the now
// playing bar are outside it, and a shelf scrolling sideways has nothing to scroll down.
#import "Core/SGCore.h"
#import "Navbar.h"
#import "MinimizeStep.h"

static Class sg_containerClass;
static __weak UIScrollView *sg_page, *sg_other;
static SGRMinimizeTrack sg_track;
static BOOL sg_waitForTouch;

static BOOL inContainer(UIView *view) {
    for (UIResponder *r = view.nextResponder; r; r = r.nextResponder) if ([r isKindOfClass:sg_containerClass]) return YES;
    return NO;
}

static void scrolled(UIScrollView *scrollView) {
    if ((!scrollView.isTracking && !scrollView.isDecelerating) || scrollView == sg_other) return;
    if (!SGRSystemTabsCanMinimize()) {
        if (inContainer(scrollView)) SGRSystemTabsFollowScroll(scrollView);
        else sg_other = scrollView;
        return;
    }
    CGFloat offset = scrollView.contentOffset.y;
    if (scrollView != sg_page) {
        if (!inContainer(scrollView)) {
            sg_other = scrollView;
            return;
        }
        sg_page = scrollView;
        sg_track = (SGRMinimizeTrack){offset, SGRSystemTabsMinimized()};
    }
    BOOL now = SGRSystemTabsMinimized();
    // The bar changed some other way (a tab, the player): the scroll counts from here.
    if (sg_track.minimized != now) {
        sg_track = (SGRMinimizeTrack){offset, now};
        sg_waitForTouch = YES;
    }
    if (scrollView.isTracking) sg_waitForTouch = NO;
    UIEdgeInsets inset = scrollView.adjustedContentInset;
    CGFloat top = -inset.top, bottom = scrollView.contentSize.height + inset.bottom - scrollView.bounds.size.height;
    BOOL minimized = SGRMinimizeStep(&sg_track, offset, top, bottom);
    if (minimized == now || (minimized && !SGEnabled(SGRKeyNavbarMinimize))) return;
    if (minimized && sg_waitForTouch) return;
    SGRSystemTabsSetMinimized(minimized);
}

%hook UIScrollView
- (void)setContentOffset:(CGPoint)offset {
    %orig;
    scrolled(self);
}
%end

%ctor {
    if (!SGRedesignedUI()) return;
    sg_containerClass = NSClassFromString(@"_TtC23NavigationUI_TabBarImpl19TabBarContainerImpl");
    if (!sg_containerClass) return;
    %init;
}
