// The Mini player page, a page of the Player page (App/Pages.m).
#import "Settings/SGSourcesPage.h"
#import "Core/SGCore.h"
#import "Settings/SGModPage.h"
#import "Navbar.h"

// The mini player (Redesigned/Navbar/SystemTabs.x): Apple Music style (the tab bar minimizes as a page scrolls), the
// swipe, and the buttons beside play, each on a key of its own.
UIViewController *SGRMiniPlayerSettingsPage(void) {
    SGModRow *minimize = SGSwitchRow(@"Apple Music style", @"The tab bar shrinks as a page scrolls down", SGRKeyNavbarMinimize);
    SGModRow *swipe = SGSwitchRow(@"Swipe to skip", @"Sideways on the mini player", SGRKeyMiniPlayerSwipe);
    // The buttons beside the title, dragged into their order, the ones below the line off (Settings/SGSourcesPage.h; its
    // owner, 2026-11-06). Play stays on.
    SGModRow *buttons = SGPageRow(@"Buttons", ^UIViewController *{
        NSArray<SGSource *> *all = @[
            [SGSource sourceWithKey:SGRMiniButtonAirPlay name:@"AirPlay" detail:@"The output's device"],
            [SGSource sourceWithKey:SGRMiniButtonStar name:@"Star" detail:@"Add to Liked Songs"],
            [SGSource sourceWithKey:SGRMiniButtonPlay name:@"Play" detail:@"Always shown"],
            [SGSource sourceWithKey:SGRMiniButtonNext name:@"Skip" detail:@"The next song"],
        ];
        return SGSourcesPageMake(@"Buttons", @"Left to right on the mini player, beside the title. Drag to reorder; the ones "
                                             @"below the line are off. AirPlay and Star step aside while the title would be "
                                             @"left too short; in the tab bar's row only play shows.",
                                 all, ^NSArray<NSString *> * { return SGRMiniPlayerButtons(); },
                                 ^(NSArray<NSString *> *keys) { SGRSetMiniPlayerButtons(keys); });
    });
    buttons.value = ^NSString * { return [NSString stringWithFormat:@"%lu", (unsigned long)SGRMiniPlayerButtons().count]; };
    return [[SGModPage alloc] initWithTitle:@"Mini player" intro:nil sections:@[
        SGNotedSection(nil, @[minimize, swipe, buttons],
                       @"Apple Music style moves the mini player into the tab bar's row as you scroll down. Swipe to skip pages to the "
                       @"next or previous song; on the player, a sideways swipe on the title does the same."),
    ] footer:nil];
}
