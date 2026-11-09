// The system tab bar's player page's queue (SystemPlayer.m), in the page as the Music app has its queue (its owner's
// recording, 2026-11-02) rather than Spotify's queue sheet: the AutoMix and Crossfade chips (Mod Settings'
// AutoMix switch and style; its owner, 2026-11-02: no shuffle or repeat there) over the tracks to come, in the
// order the player reports them, grouped as Spotify groups them by where each came from (the hand queue, the album or
// playlist playing, autoplay), each with its cover, title and artist. A tap on a track plays it.
//
// Threading: main thread only.
#import <UIKit/UIKit.h>

@class SPTPlayerState, SPTPlayerTrack;

// Whether Spotify lets shuffle (repeat NO) or repeat (YES) be changed now: none of the state's restrictions' reasons
// against it, as Spotify's own Connect menu reads them (autoplay and radio give some; with Spoof Premium,
// Shared/AdBlock/RadioModes.m lifts those). Allowed when the state has no restrictions to read.
BOOL SGRSystemOptionAllowed(SPTPlayerState *state, BOOL repeat);

@interface SGRSystemQueueView : UIView
@property (nonatomic, copy) void (^onPick)(SPTPlayerTrack *track);
// A track dragged to another place in its group: the whole list of tracks to come in its new order, to hand Spotify.
// Only the tracks shown from Spotify's queue move (showState:upcoming:from:); the state's few alone do not.
@property (nonatomic, copy) void (^onReorder)(NSArray *upcoming);
// Shuffle and Repeat chips beside AutoMix, for when the Player page's Hide on the player takes them off the controls
// (its owner, 2026-11-02), as the Music app's queue has them; all chips go to glyphs alone then. Their taps run these,
// and the next state's read from Spotify's state (showState:).
@property (nonatomic) BOOL showsShuffle, showsRepeat;
@property (nonatomic, copy) void (^onShuffle)(void);
@property (nonatomic, copy) void (^onRepeat)(void);
// A Jam chip at the row's end (its owner, 2026-11-09): its tap runs onJam; lit while a Jam is on (jamOn, set by the page).
@property (nonatomic, copy) void (^onJam)(void);
@property (nonatomic) BOOL jamOn;
// A track lifted to be moved (YES) and let go (NO): the page puts its controls away meanwhile, as the Music app does.
@property (nonatomic, copy) void (^onDragging)(BOOL dragging);
// The page's controls over the foot of the list: the list runs on under them, its last track resting just above them
// (blank room that tall ends the list), and is faded out there. The list is never resized for a drag, so nothing in it
// moves when the controls go: only `controlsCover` goes to 0, and the rows under them show (its owner, 2026-11-03).
@property (nonatomic) CGFloat controlsHeight;
- (void)setControlsCover:(CGFloat)cover animated:(BOOL)animated;
// Room above the chips for the page's head (the landscape player's title row): the chips start that far down and the
// list scrolls them up, 1:1, until they reach the top, as the Music app's landscape queue pushes its title row out;
// `onHeadPush` hears how far, 0 to headRoom. Touches above the chips go through. 0, the portrait page's, leaves all as it was.
@property (nonatomic) CGFloat headRoom;
// How far the page's head is pushed: up to headRoom as the list scrolls on, and below 0, down, as History is pulled into
// view over it.
@property (nonatomic, copy) void (^onHeadPush)(CGFloat push);
// How much of the page's head shows, 0 to 1: all of it but as History pulls it down to where the list fades out over
// the controls. Read in onHeadPush.
@property (nonatomic, readonly) CGFloat headShown;
// A track of History tapped: the track itself, and how many tracks back it lies.
@property (nonatomic, copy) void (^onPickPast)(SPTPlayerTrack *track, NSInteger steps);
// The state's tracks to come, with the name of what it plays from for the main group's note; the chip read again.
- (void)showState:(SPTPlayerState *)state from:(NSString *)contextTitle;
// The same with the whole queue's tracks to come, from Spotify's queue (SPTPlayerQueue's nextTracks), in place of the
// state's few.
- (void)showState:(SPTPlayerState *)state upcoming:(NSArray *)upcoming from:(NSString *)contextTitle;
// Back to the top of the list, for a fresh look as the queue opens.
- (void)scrollToTop;
// History from Spotify's whole queue (SPTPlayerQueue's prevTracks), in place of the state's two or three, oldest first.
- (void)showPast:(NSArray *)past;
@end
