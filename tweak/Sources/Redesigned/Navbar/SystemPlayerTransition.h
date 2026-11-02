// The system tab bar's player page (SystemPlayer.m) opened and closed by an animation of the mod's own, in place of
// UIKit's zoom (its owner, 2026-11-01). UIKit's zoom settled for up to 1.3 s after it looked done, and in that time it
// took no swipe close, made a tap on the mini player wait, and kept the mini player's capsule hidden (the phone's log);
// none of that could be shortened from outside. This one ends when it looks done, and either way can be turned back.
//
// The page grows out of the mini player's capsule as Sim Radio's player grows out of its mini player: a Liquid Glass card
// from the capsule's frame to the screen, its bottom held to the capsule's, the page cut to it and the mini player's row
// riding its top, over a dimming. The mini player stays where it is under it throughout. A swipe down on the page carries
// the card down with the finger and closes it into the capsule, or springs it back open; it can begin as soon as the page
// shows, the open included. A tap on the mini player while the page closes turns the close back.
//
// Threading: main thread only.
#import <UIKit/UIKit.h>

@interface SGRSystemPlayerTransition : NSObject <UIViewControllerTransitioningDelegate>
// The view the page opens from and closes into, asked at each open and close; nil gives the screen's bottom edge.
@property (nonatomic, copy) UIView *(^source)(void);
// A picture of the mini player's row (its cover, text and buttons, not its glass), to ride the card's top; nil for none.
@property (nonatomic, copy) UIView *(^row)(void);
// Set on `page` (kept by it) with its presentation style, so presenting it runs this. The settings are read here.
+ (instancetype)attachTo:(UIViewController *)page;
// The page's close running and not dragged: turned back, so the page opens again. NO when there is no such close.
- (BOOL)turnBackClose;
@end
