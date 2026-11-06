// The redesign's tab bar and mini player: iOS's own tab bar over Spotify's, which it mirrors, with the mod's mini player
// in it. The player page the mini player opens is Redesigned/Player/ (SystemPlayer.h).
//
//     SystemTabs.x         the UITabBarController over Spotify's tab area, the mini player as its bottomAccessory, and
//                          sheets presented from under the player page sent over it
//     TabBar.x             Spotify's own bar, unseen, read for its tabs at each of its passes
//     Navbar.x             the tabs composed from the redesign's own list, Spotify's and the mod's own
//     NavbarLayout.m       that list as stored
//     NavbarSettings.m     the Tab bar page: the tab editor
//     TabBarMinimize.x     the bar minimized and brought back by a page's scroll (MinimizeStep.h's rule)
//     NowPlayingBar.x      Spotify's now playing bar, unseen, the source of the cover
//     MiniPlayerSettings.m the Mini player page
//
// The list is ordered entries, each a dictionary. An entry with a URI is a tab of the mod's own; one without names
// one of Spotify's, by the label under its icon. No list at all is Spotify's order, all shown.
#import <UIKit/UIKit.h>

// Icons only on the tab bar. Off unless set; applies as soon as the bar lays out again.
#define SGRKeyNavbarHideLabels @"spotifyglass.redesign.navbar.hideLabels"

extern NSString *const SGRNavbarID;      // NSString, the entry's identity
extern NSString *const SGRNavbarTitle;   // NSString, the name in the settings list and under the icon
extern NSString *const SGRNavbarURI;     // NSString, the mod's own tabs only: what a tap opens
extern NSString *const SGRNavbarIcon;    // NSString, an SPTEncoreIcon class method such as "podcasts", or an SF Symbol
extern NSString *const SGRNavbarIconSet; // NSString, SGTabIconSetSymbols when the icon is an SF Symbol; none is Encore
extern NSString *const SGRNavbarHidden;  // NSNumber
NSArray<NSDictionary *> *SGRNavbarLayout(void);
void SGRSetNavbarLayout(NSArray<NSDictionary *> *layout);
// The glass bar's split tabs, stored in a list of their own, folded onto the end of SGRNavbarLayout's once and let go
// (NavbarLayout.m). Run at launch, so a settings backup from before, which an import writes back before it restarts,
// is folded too.
void SGRFoldNavbarSplit(void);
// Spotify's own tabs in Spotify's order, as Navbar.x last saw them on the bar.
NSArray<NSString *> *SGRNavbarStock(void);
void SGRSetNavbarStock(NSArray<NSString *> *stock);
// What a tab of the mod's own opens: its URI as typed or pasted, share links made spotify: URIs, and
// the URIs of presets that never opened (spotify:collection:playlists, up to 0.20) moved to the ones
// that replaced them, so a tab saved back then works without being added again.
NSURL *SGRNavbarTabURL(NSString *uri);

// Navbar.x, called from the tab bar's layout passes in TabBar.x.
void SGRComposeTabBar(UIView *tabBar);
// The tabs as composed, in the bar's order, the hidden ones left out; nil before the first pass.
NSArray<UIView *> *SGRNavbarOrder(UIView *tabBar);
// Lays the bar out again after the Navbar page changes something, so it does not wait for a touch.
void SGRRefreshTabBar(void);
// The tab of the mod's own whose page is on screen, which the tab bar shows selected; nil when none is.
UIView *SGRNavbarLitTab(void);

// The tab bar minimizes as a page scrolls down (TabBarMinimize.x, SystemTabs.x), the mini player moving into its row.
// On unless switched off (the Mini player page's Apple Music style); read as each scroll goes.
#define SGRKeyNavbarMinimize @"spotifyglass.redesign.navbar.minimize"

// A tab's glyph drawn white, filled when `active` (TabBar.x), for the Tab bar page.
UIImage *SGRNavbarGlyph(NSDictionary *entry, BOOL active);

UIViewController *SGRNavbarSettingsPage(void);   // the tab editor, in Mod Settings

// The redesign's tab bar (SystemTabs.x). A UITabBarController over Spotify's tab area, its tabs Spotify's own and
// the mod's mini player in its bottomAccessory, so UIKit minimizes the bar and moves the mini player into its row as the
// Music app does.
// A sideways swipe on the system tab bar's mini player pages to the next or previous track (SystemTabs.x). On until
// switched off on the Mini player page, read at each swipe.
#define SGRKeyMiniPlayerSwipe @"spotifyglass.redesign.navbar.miniPlayerSwipe"
// The next button beside play on the system tab bar's mini player (SystemTabs.x). On until switched off on the Mini player
// page, read at each of its layouts.
#define SGRKeyMiniPlayerNext @"spotifyglass.redesign.navbar.miniPlayerNext"
// The AirPlay button beside play on the system tab bar's mini player (SystemTabs.x), over the bar and in its row while the
// title keeps room. On until switched off on the Mini player page.
#define SGRKeyMiniPlayerAirPlay @"spotifyglass.redesign.navbar.miniPlayerAirPlay"
// The star beside play on the system tab bar's mini player (SystemTabs.x), saving the song to Liked Songs as the player's
// does, over the bar while the title keeps room. Off until switched on on the Mini player page (its owner, 2026-11-06).
#define SGRKeyMiniPlayerLike @"spotifyglass.redesign.navbar.miniPlayerLike"
// The mini player's buttons, left to right, as keys of SGRMiniPlayerButtons below: those on, in their order (the Mini player
// page's Buttons, its owner, 2026-11-06). Play is always on.
#define SGRKeyMiniPlayerOrder @"spotifyglass.redesign.navbar.miniPlayerOrder"
#define SGRMiniButtonAirPlay @"airplay"
#define SGRMiniButtonStar @"star"
#define SGRMiniButtonPlay @"play"
#define SGRMiniButtonNext @"next"
NSArray<NSString *> *SGRMiniPlayerButtons(void);
void SGRSetMiniPlayerButtons(NSArray<NSString *> *keys);
// Lays the system tab bar's mini player out again, for a setting of the Mini player page that changed; nothing without it.
void SGRRefreshMiniPlayer(void);
// The mini player's settings, a page of the redesign's Player page (App/Pages.m): Apple Music style, Swipe to skip and
// the buttons beside play (MiniPlayerSettings.m).
UIViewController *SGRMiniPlayerSettingsPage(void);

// Spotify's now playing bar, kept unseen under the mini player (NowPlayingBar.x): the cover it shows, for the mini player
// and the player page, nil before it has one; and the bar as last seen, which SystemTabs.x stands its tab bar above and in
// which the player page finds Spotify's Connect holder.
UIImage *SGRNowPlayingCover(void);
extern __weak UIView *sgr_nowPlayingRoot;
// TabBar.x hands it Spotify's tab items and the one on screen at each of Spotify's bar passes.
void SGRSystemTabsSync(UIViewController *container, UIView *stockBar, NSArray<UIView *> *sources, UIView *active);
// TabBarMinimize.x hands it the page's scroll view as it scrolls, for UIKit's minimize on scroll.
void SGRSystemTabsFollowScroll(UIScrollView *scrollView);
// TabBar.x's tab items, for SystemTabs.x: an item's glyph (filled when active), its name, and a tap passed on to it.
UIImage *SGRTabSourceGlyph(UIView *source, BOOL active);
// One of Spotify's tabs drawn from Spotify's Encore glyphs, its outline and its filled (-active) glyph, from the first
// launch; NO for a tab not known (one of the mod's own), which the bar draws from its item as it stands.
BOOL SGRTabSourceEncoreGlyphs(UIView *source, UIImage **outline, UIImage **filled);
// A tab of the mod's own's icon as its entry names it, an Encore glyph or an SF Symbol (Navbar.x); NO for Spotify's.
BOOL SGRTabItemIcon(UIView *item, NSString **name, BOOL *symbol);
NSString *SGRTabSourceTitle(UIView *source);
void SGRForwardTabTap(UIView *source);
// The system bar minimized and expanded by the mod's own rule (TabBarMinimize.x) through the controller's own setter,
// when this iOS has one (SGRSystemTabsCanMinimize); else UIKit's minimize on scroll stays.
BOOL SGRSystemTabsCanMinimize(void);
BOOL SGRSystemTabsMinimized(void);
void SGRSystemTabsSetMinimized(BOOL minimized);
