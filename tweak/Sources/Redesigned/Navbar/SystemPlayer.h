// Prototype: the system tab bar's player (SystemPlayer.m), a page of the mod's own that the mini player
// (SystemTabs.x) presents with a move of the mod's own (SystemPlayerTransition.m). Spotify's player is not in it: it is drawn from the player's state and
// drives the player through the commands the mod already sends (Headers/SPTPlayer.h).
//
// Threading: main thread only.
#import <UIKit/UIKit.h>
#import "Redesigned/Kit/SGRGlyph.h"

@interface SGRSystemPlayerPage : UIViewController
// Built with the lyrics up or not as the last page was left, read as it is built: a page built ahead (SystemTabs.x)
// while another was up is out of date once that one closes another way.
@property (nonatomic, readonly) BOOL outOfDate;
@end

// The page's AirPlay button for another place (the system tab bar's mini player, SystemTabs.x): the output's device
// glyph at `pointSize`, followed as the output changes; a tap opens the system's AirPlay picker, a hold Spotify's Connect
// sheet, with the footer's press feel. `place` names it in the log.
UIView *SGRSystemMakeRouteButton(CGFloat pointSize, NSString *place);
// The cover while nothing plays, the Music app's (its owner's screenshots, 2026-11-02): a gray square with a lighter gray
// note in it. The page and the mini player both show it, under "Not Playing".
UIImage *SGRSystemNotPlayingArt(void);
// Whether the item is a track (not nil, not an empty state), and whether it is the AI DJ talking (no length): the
// page's tests, for the sideways page to say Not Playing and dash its times by the same rules.
BOOL SGRSystemIsTrack(id track);
BOOL SGRSystemIsNarration(id track);

// Posted on the main queue when the page's close is over, gone or let go back by a swipe: a tap on the mini player during
// the close, which UIKit would refuse while the page is still presented, opens it then if it has gone (SystemTabs.x).
extern NSNotificationName const SGRSystemPlayerPageDidCloseNotification;


@class SPTPlayerState;
// The track just before the playing one: the last of the state's played tracks, which run oldest first (the mini player
// took the first for it, and paged the wrong way on a skip, its owner's recording, 2026-11-01). nil when there is none.
id SGRPreviousTrack(SPTPlayerState *state);
// Which way the player moved from the track `from`: 1 on (it is among the played tracks now), -1 back (among those to
// come), 0 when it is in neither.
NSInteger SGRTrackMoved(SPTPlayerState *state, NSString *from);

// The output's device for the page's and the mini player's AirPlay button (SystemOutput.x, PR #192's glyph, which the
// redesigned player does not draw): its SF Symbol's name (airplayaudio on the phone, the AirPods by model, a HomePod, a
// Mac, EarPods...), that symbol as the system's catalogue draws it (iOS 27's names included, which systemImageNamed:
// lacks), and the device's name, nil on the phone's speaker.
NSString *SGRPlayerOutputSymbol(void);
UIImage *SGRPlayerOutputImage(NSString *symbol, UIImageConfiguration *config);
NSString *SGRPlayerOutputName(void);
// Posted on the main queue whenever the output may have changed: ask SGRPlayerOutputSymbol again.
extern NSNotificationName const SGRPlayerOutputDidChangeNotification;
// A finger's stay on `control` presses the first SGRGlyphView inside it and lets go as it lifts.
void SGRPlayerPressGlyphOnTouch(UIView *control);
// The page's Animated background (SystemMotion.m): a clip and its poster drawn as #192 drew them, playing. PlayerMotion.x's
// SGRPlayerMotionPreview builds it under Native redesign.
UIView *SGRSystemMotionPreviewOf(NSURL *file, UIImage *poster);

// The page's volume row (SystemVolume.m, Sim Radio's elastic slider, which the redesigned player does not have), 32 pt
// high, as wide as it is laid out; the pans above it turned back on, should it have any off, for a page that is closing;
// and an outside change of the system's slider, which the redesigned player's UISlider hook passes on.
UIControl *SGRPlayerMakeVolumeRow(void);
void SGRPlayerVolumeRowLetGo(UIControl *row);
void SGRSystemVolumeSliderSet(UISlider *slider);

// The page's progress bar, shared with the landscape player (SystemLandscape.m), drawn as the volume
// row is (PlayerVolume.m): a thin pill that grows while held, moved by the finger's travel from where it came down. The
// player seeks once the finger lets go.
@interface SGRSystemScrubber : UIControl
@property (nonatomic) CGFloat value;    // 0 to 1
@property (nonatomic, readonly) BOOL held;
@property (nonatomic, copy) void (^onMove)(CGFloat value);
@property (nonatomic, copy) void (^onRelease)(CGFloat value);
// The times under the bar, moved in with it at rest and out to its ends held (ElasticSlider's bottom labels).
@property (nonatomic, weak) UIView *leadingLabel, *trailingLabel;
- (void)letGoOfPans;
@end

// Native redesign's landscape player (SystemLandscape.m), which the page holds while the app is turned: made in the lines'
// view, the queue's or the player's, switched between them, and told the track's lines came in or are none.
UIViewController *SGRSystemMakeLandscape(BOOL lyrics, BOOL queue);
void SGRSystemLandscapeSetLyrics(UIViewController *screen, BOOL lyrics, BOOL animated);
// The queue up in the landscape player or not, as the page's is.
void SGRSystemLandscapeSetQueue(UIViewController *screen, BOOL queue, BOOL animated);
// What the landscape player shows: its lyrics, its queue, or neither (its player view).
void SGRSystemLandscapeShowing(UIViewController *screen, BOOL *lyrics, BOOL *queue);
void SGRSystemLandscapeLinesChanged(UIViewController *screen);

// The page's control button, shared with the landscape player (SystemLandscape.m): its press, play and pause's turn,
// the skips' step and the lit disc.
@interface SGRSystemControlButton : SGRGlyphButton
// The glyph's scale and opacity while held (shuffle and repeat).
@property (nonatomic) CGFloat heldScale, heldAlpha;
// Previous, play and pause, and next: PlayerButton.swift's press (above) instead.
@property (nonatomic) BOOL transport;
// Steps the double arrow along as ForwardLabel.swift does: 1 forward (next), -1 back (previous).
- (void)stepArrow:(NSInteger)direction;
// Play and pause turned the way SwiftUI's .replace (down-up) does in Sim Radio's PlayerButton.swift: the old symbol
// shrinks and fades into the middle while the new one grows out of it. Drawn on two plain pictures of the symbols, each
// its own size about the button's middle, not by UIKit's symbol replace, which on the phone drew the new symbol grown and
// 6 pt off the middle at the swap's start whatever variant it was asked for (its owner's recordings and the phone's log,
// 2026-11-02). The glyph itself waits out the swap unseen, at rest. The same symbol again is a no-op.
- (void)turnToSymbol:(NSString *)symbol animated:(BOOL)animated;

// On, the lyrics' and the queue's look (its owner, 2026-11-02): the glyph cut out of a light disc, the page showing
// through; off, the plain glyph in `plain`. The disc comes and goes with a fade and a small scale (the fade alone under
// Reduce Motion). A new symbol on the glyph (repeat's one) is cut again by the next call.
- (void)setLit:(BOOL)lit plain:(UIColor *)plain animated:(BOOL)animated;
@end

// For the landscape player's queue: what the track plays from, for the queue's note; what a queue was made from (the
// playing track's URI, then each track to come's); and a move in it handed back to Spotify only while Spotify's queue is
// still `shown`, in the same order. `handed` gets the new order's key; `done` runs a moment later either way, to show
// what Spotify kept.
@class SPTPlayerState;
NSString *SGRSystemContextTitle(SPTPlayerState *state);
NSArray<NSString *> *SGRSystemQueueKey(NSArray *next);
void SGRSystemHandQueueBack(NSArray<NSString *> *shown, NSArray *upcoming, void (^handed)(NSArray<NSString *> *key), void (^done)(void));
// Shuffle on or off, and repeat through off, the playlist or album, the track, as the page's buttons do; the landscape
// player's queue chips run them too.
void SGRSystemToggleShuffle(void);
// The Music app's badge on the queue button (its owner's screenshots, 2026-11-06): a small lit disc (the lyrics and queue buttons' light disc, glyph cut out) at its top right with
// shuffle or repeat in it while one is on and hidden from the controls. Shown with a symbol, hidden with nil; placed on
// `button` (a 44 pt square), whose subview it is.
UIView *SGRSystemMakeOptionBadge(UIView *button);
void SGRSystemShowOptionBadge(UIView *badge, NSString *symbol, BOOL animated);
// Which to show: shuffle first (its owner, 2026-11-06), then repeat (repeat.1 for the track), each only when hidden.
NSString *SGRSystemOptionBadgeSymbol(SPTPlayerState *state, BOOL shuffleHidden, BOOL repeatHidden);
// Back to `track`, one of the queue's History `steps` tracks behind the playing one: straight to it through Spotify's
// skip back to a track, else one back at a time from the playing track's start, each once the last has landed.
@class SPTPlayerTrack;
void SGRSystemStepBack(SPTPlayerTrack *track, NSInteger steps);
// A song of the mod's own History (SystemHistory.h): back to it in Spotify's queue if it is still there, or its link.
void SGRSystemPlayPast(SPTPlayerTrack *track);
// The track `uri` (a song's music video or a video's song) played in place of the one playing, from the same second.
void SGRSystemSwitchTo(NSString *uri, BOOL toVideo);
// The buttons beside the star: Switch to Video / Audio (under the Switch to video setting, for a song with the other) and
// the DJ's sheet (while the DJ plays), never both. Sync shows or hides each and lays `layout` out again on a change.
void SGRSystemRowButtons(BOOL *switchShown, BOOL *djShown, BOOL *video);
@class SGRGlyphButton;
void SGRSystemSyncRowButtons(SGRGlyphButton *switchVideo, SGRGlyphButton *dj, UIView *layout);
void SGRSystemSwitchVideo(void);
void SGRSystemOpenDJ(void);
// The music video's width over its height, from Spotify's display view in `surface`; 16:9 until it has frames.
CGFloat SGRSystemVideoAspect(UIView *surface);
void SGRSystemCycleRepeat(void);

// A light disc with `symbol` cut out of it, hidden until shown: the page's lyrics and queue buttons' lit state, and the
// landscape player's lyrics button's.
UIImageView *SGRSystemCutDisc(NSString *symbol);

// The app's landscape (SystemTurn.m): the whole app turning with the phone, and the page's landscape player reached from
// the page. The page says when it is up (nil as it goes), whether its lyrics or queue are, and which landscape player it
// holds.
@protocol SGRSystemTurnPage
// The page's ⋯ items for the landscape player's ⋯: their sheets and popovers from `anchor` and `presenter`, and
// `changed` run after the ⋯ switches the background.
- (NSArray<UIMenuElement *> *)landscapeMenuItemsFrom:(UIView *)anchor presenter:(UIViewController *)presenter changed:(void (^)(void))changed;
@optional
// The music video's surface the page has borrowed (SystemPlayer.m's attachVideoIfShown), for the landscape player to
// hold while it is up; nil with no video. The page keeps it filling whatever holds it, and takes it back with
// landscapeVideoReturned.
- (UIView *)landscapeVideoSurface;
- (void)landscapeVideoReturned;
@end
UIView *SGRSystemTurnVideoSurface(void);
// SystemVideoKeep.x: the page's Picture in Picture ready to start (armed) or up (active), so Spotify keeps the video on
// behind it rather than playing the sound alone.
void SGRSystemVideoSetPiP(BOOL armed, BOOL active);
void SGRSystemTurnVideoReturned(void);
// The page's ⋯ items for the landscape player, empty with no page up.
NSArray<UIMenuElement *> *SGRSystemTurnMenuItems(UIView *anchor, UIViewController *presenter, void (^changed)(void));
void SGRSystemTurnSetPage(UIViewController<SGRSystemTurnPage> *page);
void SGRSystemTurnSetLyrics(BOOL open);
void SGRSystemTurnSetQueue(BOOL open);
// The landscape player the page holds while the app is turned, or nil.
void SGRSystemTurnSetEmbedded(UIViewController *screen);
void SGRSystemTurnLinesChanged(void);
// Exit Full Screen: back to portrait, held there until the phone has stood upright.
void SGRSystemTurnBack(void);
