// Keeps the areas the redesign stripped transparent when Spotify repaints them.
#import "Core/SGCore.h"
#import "SGRRepaint.h"

__weak UIView *sgr_playlistRoot = nil;
__weak UIView *sgr_albumRoot = nil;
__weak UIView *sgr_artistRoot = nil;

// One walk up from the view says whether it is inside one of the roots, the way SGIsInside would for each: not past a
// visual effect view.

%hook CALayer
- (void)setBackgroundColor:(CGColorRef)color {
    if (!color) {
        %orig;
        return;
    }
    UIView *playlist = sgr_playlistRoot, *album = sgr_albumRoot, *artist = sgr_artistRoot;
    // A page only ever loses the base surface.
    if (!SGIsBaseSurface(color)) {
        %orig;
        return;
    }
    if (playlist || album || artist) {
        UIView *view = (UIView *)self.delegate;
        if ([view isKindOfClass:UIView.class] && view.layer == self && !SGKeepsColor(view)) {
            for (UIView *v = view; v; v = v.superview) {
                if ([v isKindOfClass:UIVisualEffectView.class]) break;
                if (v == playlist || v == album || v == artist) {
                    color = NULL;
                    break;
                }
            }
        }
    }
    %orig(color);
}
%end

%ctor {
    if (!SGRedesignedUI()) return;
    %init;
}
