// A line of text that scrolls side to side when it does not fit, the way the Music app's titles do: it
// rests at its start, glides to show its end, rests, and glides back, its overflowing edge faded. Text
// that fits stands still. Under Reduce Motion it ends in "…" instead.
//
// Threading: main thread only.
#import <UIKit/UIKit.h>

@interface SGMarqueeLabel : UIView
@property (nonatomic, copy) NSString *text;
@property (nonatomic, strong) UIFont *font;
@property (nonatomic, strong) UIColor *textColor;
// A faded zone this wide before the text, as the mini player's lines have (SystemTabs.x's kTextFade): the text starts this
// far in, crisp at rest, and as it scrolls it passes out through the zone softly rather than being cut at the view's
// edge, the way the Music app's titles do (the system tab bar's player page, its owner, 2026-11-01). 0, the default, is
// none: the text starts at the edge and only its trailing end fades.
@property (nonatomic) CGFloat leadingFade;
@end
