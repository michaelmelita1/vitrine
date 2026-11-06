// The redesign's navbar: the glass tab bar (TabBar.x) over Spotify's own, composed from its own list
// (Navbar.x, NavbarLayout.m), which the redesign keeps apart from the native look's: an ordered list of
// entries, each a dictionary. An entry with a URI is a tab of the mod's own; one without names
// one of Spotify's, by the label under its icon. No list at all is Spotify's order, all shown.
#import <UIKit/UIKit.h>

#define SGRKeyNavbar @"spotifyglass.redesign.navbar"
// Icons only on the glass bar. Off unless set; applies as soon as the bar lays out again.
#define SGRKeyNavbarHideLabels @"spotifyglass.redesign.navbar.hideLabels"

extern NSString *const SGRNavbarID;      // NSString, the entry's identity
extern NSString *const SGRNavbarTitle;   // NSString, the name in the settings list and under the icon
extern NSString *const SGRNavbarURI;     // NSString, the mod's own tabs only: what a tap opens
extern NSString *const SGRNavbarIcon;    // NSString, an SPTEncoreIcon class method such as "podcasts", or an SF Symbol
extern NSString *const SGRNavbarIconSet; // NSString, SGTabIconSetSymbols when the icon is an SF Symbol; none is Encore
extern NSString *const SGRNavbarHidden;  // NSNumber
NSArray<NSDictionary *> *SGRNavbarLayout(void);
void SGRSetNavbarLayout(NSArray<NSDictionary *> *layout);
// The tabs set apart at the trailing end of the bar (Split tabs): a list of entries of their own, apart from
// SGRNavbarLayout's. A tab of the mod's own here is independent of the bar's; one of Spotify's can stand in one
// place only, so it leaves the bar's list while it is here.
NSArray<NSDictionary *> *SGRNavbarSplit(void);
void SGRSetNavbarSplit(NSArray<NSDictionary *> *split);
// The split tabs as they were stored before they had a list of their own (.split, the identities of entries of the
// bar's list) moved over to that list, once: when .split is there and the list is not. Run at launch, so a settings
// backup from before, which an import writes back before it restarts, is moved over too.
void SGRMigrateNavbarSplit(void);
// Spotify's own tabs in Spotify's order, as Navbar.x last saw them on the bar.
NSArray<NSString *> *SGRNavbarStock(void);
void SGRSetNavbarStock(NSArray<NSString *> *stock);
// What a tab of the mod's own opens: its URI as typed or pasted, share links made spotify: URIs, and
// the URIs of presets that never opened (spotify:collection:playlists, up to 0.20) moved to the ones
// that replaced them, so a tab saved back then works without being added again.
NSURL *SGRNavbarTabURL(NSString *uri);

// Navbar.x, called from the tab bar's layout passes in TabBar.x.
void SGRComposeTabBar(UIView *tabBar);
void SGRLogTabBarRow(UIView *tabBar);
// Lays the bar out again after the Navbar page changes something, so it does not wait for a touch.
void SGRRefreshTabBar(void);

// TabBarRoom.m. The hold on Spotify's Home that opens Mod Settings, added once.
void SGRHoldHomeForModSettings(UIView *stockBar);
// The room made under Spotify's bar for the taller bar of the mod's (see "room for the glass bar" there): the bottom
// safe area `container` (TabBarContainerImpl) is given, and what UIKit's `bar` asks for with no room made.
CGFloat SGRTabBarRoom(void);
CGFloat SGRTabBarGlassHeight(UITabBar *bar, UIView *stockBar);
void SGRMakeTabBarRoom(UIViewController *container, UIView *stockBar, UITabBar *bar);
// Whether a tab of the composed row is one of the split tabs at its trailing end, for TabBar.x's second bar.
BOOL SGRTabIsApart(UIView *item);
// The tab of the mod's own whose page is on screen, which the glass bar shows selected; nil when none is.
UIView *SGRNavbarLitTab(void);
// A tap on one of Spotify's tabs: no tab of the mod's own is lit any more.
void SGRNavbarForgetTab(void);

// The glass bar minimizes as a page scrolls down (TabBarMinimize.x): it shrinks to two of its tabs, the
// now playing card coming down between them. On unless switched off; read as each scroll goes.
#define SGRKeyNavbarMinimize @"spotifyglass.redesign.navbar.minimize"
BOOL SGRTabBarMinimized(void);
// TabBar.x lays both bars out for it, the now playing bar in the same animation, at once; asked for inside an
// animation, on the main queue's next turn (SGRTabBarMinimized changes then too). `animated` NO is a cut, made
// at once.
void SGRSetTabBarMinimized(BOOL minimized, BOOL animated);
// The room between the minimized bar's two tabs, `height` high and centered on them, in `host`'s
// coordinates: where the now playing card goes. CGRectNull while the bar is not minimized or not on screen.
CGRect SGRTabBarInlineSlot(UIView *host, CGFloat height);
// The expanded bar's glass from the leading edge of its first platter to the trailing edge of its last, in `host`'s
// coordinates (x only counts): the now playing card above the bar takes these edges, as the Music app's mini
// player stands as wide as its tab bar. CGRectNull out of a window or in a regular width, where Spotify's bar is not
// the glass row.
CGRect SGRTabBarGlassRow(UIView *host);

// A tab's glyph as the glass bar draws it, white, filled when `active` (TabBar.x), for the Tab bar page.
UIImage *SGRNavbarGlyph(NSDictionary *entry, BOOL active);
// Lets a laid out bar's titles shrink a little before UIKit cuts them short (TabBar.x), for the page's preview too.
void SGRShrinkTabTitles(UIView *bar);

UIViewController *SGRNavbarSettingsPage(void);   // the tab editor, in Mod Settings
UIViewController *SGRNavbarEditorPage(void);     // the tab editor alone, for the welcome tour

// Native redesign's tab bar (SystemTabs.x). A UITabBarController over Spotify's tab area, its tabs Spotify's own and
// the mod's mini player in its bottomAccessory, so UIKit minimizes the bar and moves the mini player into its row as the
// Music app does. On with Native redesign (Core/SGUIMode.h's SGNativeRedesign), read once at launch.
BOOL SGRSystemTabsOn(void);
// A sideways swipe on the system tab bar's mini player pages to the next or previous track (SystemTabs.x). On until
// switched off on the Mini player page, read at each swipe.
#define SGRKeyMiniPlayerSwipe @"spotifyglass.redesign.navbar.miniPlayerSwipe"
// The next button beside play on the system tab bar's mini player (SystemTabs.x). On until switched off on the Mini player
// page, read at each of its layouts.
#define SGRKeyMiniPlayerNext @"spotifyglass.redesign.navbar.miniPlayerNext"
// The AirPlay button beside play on the system tab bar's mini player (SystemTabs.x), over the bar and in its row while the
// title keeps room. On until switched off on the Mini player page; its own key, apart from the glass bar's device button.
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
// Whether Spotify's item is the active tab now, read off its own label as the glass bar reads it: Spotify swaps the item's
// icon to the filled one while it is, so the glyph read then is the filled one.
BOOL SGRTabSourceIsActive(UIView *source);
void SGRForwardTabTap(UIView *source);
// The system bar minimized and expanded by the mod's own rule (TabBarMinimize.x) through the controller's own setter,
// when this iOS has one (SGRSystemTabsCanMinimize); else UIKit's minimize on scroll stays.
BOOL SGRSystemTabsCanMinimize(void);
BOOL SGRSystemTabsMinimized(void);
void SGRSystemTabsSetMinimized(BOOL minimized);
