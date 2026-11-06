// Spotify's now playing bar under the redesign: kept unseen as the source of the cover the mini player and the player
// page show (NowPlayingBar.x), and the Mini player page of Mod Settings (NowPlayingBarSettings.m).
#import <UIKit/UIKit.h>

// The mini player's settings, a page of the redesign's Player page (App/Pages.m): Apple Music style, Swipe to skip and
// the buttons beside play (Redesigned/Navbar/SystemTabs.x).
UIViewController *SGRMiniPlayerSettingsPage(void);
// For the mini player and the player page (Redesigned/Navbar/SystemTabs.x, SystemPlayer.m): the cover Spotify's bar
// shows, nil before it has one.
UIImage *SGRNowPlayingCover(void);
// Spotify's bar as NowPlayingBar.x last saw it, unseen: SystemTabs.x stands its tab bar above it, and the player page
// finds Spotify's Connect holder in it.
extern __weak UIView *sgr_nowPlayingRoot;
