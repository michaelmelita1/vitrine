// Prototype: the system tab bar's player (SystemPlayer.m), a page of the mod's own that the mini player
// (SystemTabs.x) presents with a move of the mod's own (SystemPlayerTransition.m). Spotify's player is not in it: it is drawn from the player's state and
// drives the player through the commands the mod already sends (Headers/SPTPlayer.h).
//
// Threading: main thread only.
#import <UIKit/UIKit.h>

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
