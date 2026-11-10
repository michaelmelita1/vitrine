// The redesign's player: a page of the mod's own in place of Spotify's player, which the mini player
// (Redesigned/Navbar/SystemTabs.x) opens. The page and its parts are SystemPlayer.h's; this header is what they take
// from the rest of the folder: the background and its Mod Settings page, the Animated artwork clip, the Visualizer, the
// lyrics' state, the ⋯ menu's own items and hold to play faster on the cover.
//
//     SystemPlayer.m           the page: cover, title, progress, controls, volume, lyrics, AirPlay and the queue
//     SystemPlayerTransition.m its open from the mini player's capsule and its close back into it
//     SystemQueue.m            the queue in place of the lyrics, edited the Music app's way
//     SystemLandscape.m        the landscape player the page holds while the app is turned
//     SystemTurn.m             the whole app let turn with the phone, and the page told
//     SystemMotion.m           the Animated background drawn as the lock screen draws it
//     SystemVolume.x           the volume row, Sim Radio's elastic slider over the system's
//     SystemOutput.x           the output's device glyph and name for the AirPlay buttons
//     PlayerField.x            the background chosen, and Spotify's Canvas kept to the mod's drawing of it
//     PlayerArtwork.x          hold either side of the cover to play at 2x
//     PlayerLyrics.x           whether the track has lyrics, or none, and what fades while they play alone
//     PlayerMotion.x           Animated artwork: the Canvas or Apple Music's animated cover, looked up for the page
//     PlayerVisualiser.m       the Visualizer background: a calm spectrum of the song in the cover's colors, read
//                              through SGRSpectrum.m from the audio effects' tap on Spotify's output
//     PlayerMenu.m             the ⋯'s Artwork submenu
//     PlayerSettings.m         the Player page in Mod Settings, led by a showcase of the player
//
// Threading: main thread only.
#import <UIKit/UIKit.h>

// What is behind the player, chosen on the Player page (PlayerSettings.m).
// SGRKeyPlayerMotion is the switch the choice replaced: until a choice is stored, it picks Still or Colors.
#define SGRKeyPlayerBackground @"spotifyglass.redesign.player.background"
#define SGRKeyPlayerMotion @"spotifyglass.redesign.player.movingBackground"
typedef NS_ENUM(NSInteger, SGRPlayerBackgroundKind) {
    SGRPlayerBackgroundStill,      // the artwork blurred and held still
    SGRPlayerBackgroundColours,    // the artwork's colors drifting (SGRFlow.h)
    SGRPlayerBackgroundFluid,      // the artwork itself blurred and turning (SGRFluid.h)
    SGRPlayerBackgroundAnimated,   // the track's Canvas or Apple Music's animated cover, over Fluid (PlayerMotion.x)
    SGRPlayerBackgroundVisualiser, // a spectrum of the song over Fluid held still (PlayerVisualiser.m)
};
// The player's ⋯ menu switches between the last three, which share the Fluid field, without a restart.
SGRPlayerBackgroundKind SGRPlayerBackground(void);
// The names of the choices, in order.
NSArray<NSString *> *SGRPlayerBackgroundNames(void);

// Holding either side of `cover` plays at 2× until the finger lifts, with the 2× badge on it (PlayerArtwork.x). Once per view.
void SGRPlayerAttachCoverHold(UIView *cover);

#pragma mark - the lyrics (PlayerLyrics.x)

// Whether the playing track has lyrics the player can show.
BOOL SGRPlayerLyricsAvailable(void);
// Whether the playing track has none: its grace is over and nothing is looking for them any more.
BOOL SGRPlayerLyricsNone(void);
// What fades a few seconds after the last touch while the lyrics play, as the lines grow into the room: nothing,
// everything but the lines, or the controls under the title row alone. The key was a switch first: its NO and YES are
// the first two indexes, and unset reads as the switch did.
#define SGRKeyLyricsAutoHide @"spotifyglass.redesign.lyrics.autoHide"
typedef NS_ENUM(NSInteger, SGRLyricsHide) { SGRLyricsHideOff, SGRLyricsHideAll, SGRLyricsHideControls };
SGRLyricsHide SGRLyricsHideMode(void);
@class SGModRow;
// The Lyrics page's choice of it (PlayerSettings.m).
SGModRow *SGRLyricsHideRow(void);

#pragma mark - the page's switches

// A volume slider under the controls, the system's: this iPhone's, or the Connect device's. On until switched off.
#define SGRKeyPlayerVolume @"spotifyglass.redesign.player.volume"
// Shuffle and repeat left out of the controls, each on its own switch (shown as Shuffle and Repeat under Controls).
#define SGRKeyPlayerHideShuffle @"spotifyglass.redesign.player.hideShuffle"
#define SGRKeyPlayerHideRepeat @"spotifyglass.redesign.player.hideRepeat"
// The star beside the title left out, Add to Playlist taking its place in the ⋯ beside Go to Artist (shown as Like button
// under Controls; its owner, 2026-11-10: the star and Add to Playlist do the same thing, so one or the other).
#define SGRKeyPlayerHideAdd @"spotifyglass.redesign.player.hideAdd"
// A tap on the title and the artist opens the album, and Go to Album leaves the ⋯ (its owner, 2026-11-10). On until
// switched off.
#define SGRKeyPlayerTitleAlbum @"spotifyglass.redesign.player.titleAlbum"
// The app and the player page turn with the phone (SystemTurn.m). On until switched off. The key is
// the redesigned player's landscape lyrics', which it took over.
#define SGRKeyLyricsLandscape @"spotifyglass.redesign.lyrics.landscape"

#pragma mark - Animated artwork (PlayerMotion.x)

// A view playing the shown track's clip, drawn as the page draws it (SystemMotion.m's SGRSystemMotionPreviewOf). While
// the follower has no clip for the track the page looks it up itself, by the player's sources and Low Data Mode, into
// the store the follower reads too: nil until it is in, and with `arrived` given the lookup starts, and `arrived` runs
// once on the main queue when a call would return it, or when nothing was found (never when the track changed).
// Without `arrived` it only answers with a clip already in.
UIView *SGRPlayerMotionPreview(void (^arrived)(void));
// The clip in for the shown track, and its first frame: NO while there is none (the landscape player,
// SystemLandscape.m, plays it itself).
BOOL SGRPlayerMotionFile(NSURL **file, UIImage **poster);
// YES when the page's lookup found no clip for `track` a moment ago: `arrived` runs then too, and the page shows Fluid at
// once instead of keeping the last track's clip up while it waits (SystemPlayer.m's syncClipAnimated:).
BOOL SGRPlayerMotionNoneFor(NSString *track);
// Posted on the main queue as the follower's clip comes in or goes (a new track's clip found, none for it, switched off):
// a page showing SGRPlayerMotionPreview asks it again.
extern NSNotificationName const SGRPlayerMotionDidChangeNotification;

#pragma mark - the Visualizer (PlayerVisualiser.m)

// A view of its own drawing the hills, for the page and the Player page's showcase. It moves only in a window.
UIView *SGRPlayerVisualiserPreview(void);
// Switches the background to `kind` from the ⋯ menu, at once: Fluid, Animated or Visualizer, while it is one of
// them (SGPlayerMenuOffersAnimatedArtwork); nothing otherwise.
void SGRPlayerMenuSetBackground(SGRPlayerBackgroundKind kind);

#pragma mark - Mod Settings (PlayerSettings.m)

// The redesign's Player page: a card of the player over the background chosen and the control that picks it, the
// background's rows and the Controls section, then `more`, from App/Pages.m.
UIViewController *SGRPlayerSettingsPage(NSArray *more);

#pragma mark - the ⋯ menu (PlayerMenu.m)

// The backgrounds the ⋯ switches between at once (Fluid, Animated, Visualizer) as one submenu, the one shown checked and
// named under it; nil while the background is not one of them. `changed` runs after a switch.
UIMenu *SGRPlayerMenuArtwork(void (^changed)(void));

// The redesign's Animated artwork, switched from the player page's ⋯ (Redesigned/Player/PlayerMenu.m): whether the
// switch is offered (the redesign is running and its background is Fluid, Animated or Visualizer, the three that
// share a field), and switching it, which applies at once and is stored as the Background choice
// (off is Fluid, and from the Visualizer changes nothing). Defined by Redesigned/Player/PlayerMotion.x.
BOOL SGPlayerMenuOffersAnimatedArtwork(void);
void SGPlayerMenuSetAnimatedArtwork(BOOL on);

// The output's spectrum read while `need` is on (SGRSpectrum.h), counted, so the Visualizer and the DJ's ring share it.
void SGRSpectrumNeedReader(BOOL need);

