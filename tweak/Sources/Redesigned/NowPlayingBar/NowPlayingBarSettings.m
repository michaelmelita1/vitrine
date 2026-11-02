// The now playing bar's rows of the redesign, the Mini player section of the Player page
// (Redesigned/Player/PlayerSettings.m puts them there).
#import "Core/SGCore.h"
#import "Settings/SGModPage.h"
#import "Redesigned/Navbar/Navbar.h"
#import "NowPlayingBar.h"

NSArray<SGModRow *> *SGRNowPlayingBarRows(void) {
    // The tab bar reads the switch as each scroll goes; a bar minimized when it goes off grows back at once.
    SGModRow *minimize = SGSwitchRow(@"Apple Music style", @"Between two tabs as a page scrolls down", SGRKeyNavbarMinimize);
    minimize.changed = ^(BOOL on) {
        if (!on) SGRSetTabBarMinimized(NO, NO);
        SGRRefreshTabBar();
    };
    SGModRow *inlineConnect = SGOptionRow(@"Device button", @"Kept on the bar between the tabs", SGRKeyBarInlineConnect);
    inlineConnect.waitsOn = SGRKeyNavbarMinimize;
    return @[
        minimize,
        inlineConnect,
        SGHideRow(@"Hide the device button", @"On the full now playing bar", SGRHideBarConnect),
        // Spotify's own flag for the bar's save button, forced off: Spotify leaves the button out.
        SGKillRow(@"Hide the like button", @"ios-feature-nowplayingbar.add_button"),
    ];
}

// Native redesign's mini player (Redesigned/Navbar/SystemTabs.x): Apple Music style (UIKit's tab bar minimizes as a page
// scrolls), the swipe and the Skip button, and the AirPlay button beside play, stored as the glass bar's device button's
// hide key (shown until switched off). The glass bar's rows are left out: that bar is not up then.
UIViewController *SGRMiniPlayerSettingsPage(void) {
    SGModRow *minimize = SGSwitchRow(@"Apple Music style", @"The tab bar shrinks as a page scrolls down", SGRKeyNavbarMinimize);
    SGModRow *swipe = SGSwitchRow(@"Swipe to skip", @"Sideways on the mini player", SGRKeyMiniPlayerSwipe);
    // The mini player lays out again at the next pass of the tab bar, which these ask for.
    SGModRow *skip = SGSwitchRow(@"Skip button", @"Next to play on the mini player", SGRKeyMiniPlayerNext);
    skip.changed = ^(BOOL on) { SGRRefreshMiniPlayer(); };
    SGModRow *airPlay = SGShownRow(@"AirPlay button", @"On the mini player", SGRHideBarConnect);
    airPlay.changed = ^(BOOL on) { SGRRefreshMiniPlayer(); };
    return [[SGModPage alloc] initWithTitle:@"Mini player" intro:nil sections:@[
        SGNotedSection(nil, @[minimize, swipe, skip, airPlay],
                       @"Apple Music style moves the mini player into the tab bar's row as you scroll down. Swipe to skip pages to the "
                       @"next or previous song; on the player, a sideways swipe on the title does the same."),
    ] footer:nil];
}
