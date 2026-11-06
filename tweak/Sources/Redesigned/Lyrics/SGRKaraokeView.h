// The redesign's Apple Music style lyrics view, always on, over Spotify's full screen lyrics page
// (KaraokePage.x) and in the redesigned player itself (Redesigned/Player/PlayerLyrics.x). A track
// without synced lyrics keeps Spotify's own lines, where there are any next to it. The lines and the
// clock are Shared/Lyrics/Lyrics.h's.
//
// It takes the whole of whatever it is put in and dims every other view in there while it has lines
// to show, so a host it shares with anything else needs a view of its own for it.
#import <UIKit/UIKit.h>
#import "Shared/Lyrics/Lyrics.h"

@interface SGRKaraokeView : UIView
// The Lyrics page's preview: `lines` played on a clock of its own, round and round every `length` ms, in
// the look the page sets. It takes no touches and asks nothing of the player, the sources, Genius or Sing.
- (instancetype)initWithSampleLines:(NSArray<SGKaraokeLine *> *)lines length:(NSInteger)length;
// Hides Spotify's own lyrics next to this view while it has lyrics to show, and brings them back when not.
- (void)syncSiblings;
// Called as a finger starts to scroll the lines, for a host that hides its controls then. `onward` is a finger
// moving up, toward the lines still to come.
@property (nonatomic, copy) void (^browsingBegan)(BOOL onward);
// The pronunciation and translation button goes with the host's controls when they are hidden, and Sing's
// mic with it unless keepsSing is set.
@property (nonatomic) BOOL extrasHidden;
// The mic stays when the extras go, for a host that lets it take its own touches while its controls are
// hidden (the player's lines on their own, Redesigned/Player/PlayerLyrics.x), so Sing is always in reach.
@property (nonatomic) BOOL keepsSing;
// The mic and the extras button float over the lines rather than keep a clear row of their own under them, so the lines
// run to the view's foot (the landscape player, short of height; its owner, 2026-11-06).
@property (nonatomic) BOOL rowOverLines;
// How far down a tap on the lines seeks, from the view's top; 0 is all the way. Below it, and above
// seeksBelow, the tap is the host's (the player's lines on their own, over the controls that faded).
// The Lyrics page's size and spacing scaled for a host that sets its lines smaller (the landscape player, as the Music
// app's are there); 1 unless set, and set before the view has lines or at any time after.
@property (nonatomic) CGFloat lookScale;
@property (nonatomic) CGFloat seeksAbove;
@property (nonatomic) CGFloat seeksBelow;
// Whether a tap at point, in the view, seeks: on a timed line, inside the seeking band, and not on the credit
// or a line's explain bubble.
- (BOOL)tapSeeksAt:(CGPoint)point;
@end
