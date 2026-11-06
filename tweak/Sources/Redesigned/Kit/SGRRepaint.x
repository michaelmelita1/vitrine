// Keeps the areas the redesign stripped transparent when Spotify repaints them.
#import "Core/SGCore.h"
#import "SGRRepaint.h"

__weak UIView *sgr_nowPlayingRoot = nil;
__weak UIView *sgr_lyricsPageRoot = nil;
__weak UIView *sgr_playlistRoot = nil;
__weak UIView *sgr_albumRoot = nil;
__weak UIView *sgr_artistRoot = nil;

// One walk up from the view says which roots it is inside, the way SGIsInside would for each: not past a
// visual effect view. The roots are then taken in their order, not in the order the walk meets them.
enum { kInNowPlaying = 1, kInLyrics = 2, kInPage = 4 };

%hook CALayer
- (void)setBackgroundColor:(CGColorRef)color {
    if (!color) {
        %orig;
        return;
    }
    UIView *nowPlaying = sgr_nowPlayingRoot, *lyrics = sgr_lyricsPageRoot;
    UIView *playlist = sgr_playlistRoot, *album = sgr_albumRoot, *artist = sgr_artistRoot;
    // A page only ever loses the base surface, so another color asks after the player and the lyrics alone.
    if ((playlist || album || artist) && !SGIsBaseSurface(color)) playlist = album = artist = nil;
    if (nowPlaying || lyrics || playlist || album || artist) {
        UIView *view = (UIView *)self.delegate;
        if ([view isKindOfClass:UIView.class] && view.layer == self && !SGKeepsColor(view)) {
            NSUInteger inside = 0;
            for (UIView *v = view; v && !(inside & kInNowPlaying); v = v.superview) {
                if ([v isKindOfClass:UIVisualEffectView.class]) break;
                if (v == nowPlaying) inside |= kInNowPlaying;
                if (v == lyrics) inside |= kInLyrics;
                if (v == playlist || v == album || v == artist) inside |= kInPage;
            }
            if (inside) color = NULL;
        }
    }
    %orig(color);
}
%end

%ctor {
    if (!SGRedesignedUI()) return;
    %init;
}
