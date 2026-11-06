#import "Core/SGCore.h"
#import "Shared/Player/SleepTimer.h"
#import "Shared/AppIcon/AppIcon.h"
#import "Shared/Fonts/Fonts.h"
#import "Shared/LyricsTranslation/LyricsTranslation.h"
#import "Redesigned/Player/Player.h"
#import "Settings/SGModPage.h"
#import "Settings/SGPageStyle.h"
#import "Pages.h"
#import "Shared/ArtistBlock/ArtistBlock.h"
#import "Shared/Lyrics/Lyrics.h"
#import "Shared/LyricsMeanings/Meanings.h"
#import "Shared/Player/PlayerSettings.h"
#import "Shared/Sing/Sing.h"
#import "Redesigned/Lyrics/LyricsText.h"
#import "Redesigned/Lyrics/LyricsLook.h"
#import "Redesigned/Navbar/Navbar.h"
#import "Redesigned/Kit/SGRAccent.h"

// The redesign's own rows (accent, AMOLED), then the font and the app icon.
UIViewController *SGAppearancePage(void) {
    NSMutableArray<SGModRow *> *everywhere = [NSMutableArray arrayWithArray:SGAppFontRows()];
    SGModRow *icon = SGAppIconRow();
    if (icon) [everywhere addObject:icon];
    return [[SGModPage alloc] initWithTitle:@"Appearance" intro:SGRestartNote sections:@[
        SGSection(nil, SGRAppearanceRows()),
        SGSection(nil, everywhere),
    ] footer:nil];
}

UIViewController *SGNavbarPage(void) {
    return SGRNavbarSettingsPage();
}

static UIViewController *lyricsPage(void) {
    SGModRow *sing = SGPageRow(@"Karaoke", ^UIViewController *{ return SGSingSettingsPage(); });
    sing.value = ^NSString *{ return SGSingSummary(); };
    NSMutableArray<SGModSection *> *sections = [NSMutableArray arrayWithObjects:SGSection(nil, @[SGWithTile(sing, @"music.mic", UIColor.systemRedColor)]),
                                                SGLyricsSourcesSection(), nil];
    [sections addObjectsFromArray:@[
        SGSection(@"Display", @[SGRLyricsTextSizesRow(), SGLyricsWordTimingRow(), SGLyricsRomanisedRow(), SGLyricsRomanisedReplaceRow(),
            SGRLyricsHideRow()]),
        SGNotedSection(@"Timing", @[SGLyricsDelayRow()],
            @"Every line shows this much later than the song, for Bluetooth headphones that play a little behind the lyrics. Applies at once."),
        SGSection(@"Translation", [[[@[SGLyricsTranslationLanguageRow(), SGTranslateEverySongRow()] arrayByAddingObjectsFromArray:SGOnDeviceTranslatorRows()]
                                      arrayByAddingObjectsFromArray:SGAITranslatorRows()] arrayByAddingObject:SGSavedTranslationsRow()]),
        SGSection(nil, @[SGLyricsMeaningsRow()]),
        SGSection(nil, @[SGLockScreenLyricsRow(), SGLockScreenTranslationRow()]),
    ]];
    // The page leads with its lyrics playing in the look the page sets, and that look's presets.
    return SGRLyricsSettingsPage(@"Lyrics", @"The look applies at once. The settings below apply after you restart Spotify.", sections);
}

// Lyrics has its own row on Mod Settings' main page, beside Sing.
UIViewController *SGLyricsSettingsPage(void) {
    return lyricsPage();
}

UIViewController *SGPlayerSettingsPage(void) {
    SGModRow *blocked = SGPageRow(@"Blocked artists", ^UIViewController *{ return SGArtistBlockSettingsPage(); });
    blocked.value = ^NSString *{
        return SGFlag(SGKeyArtistBlock, NO) ? @(SGBlockedArtists().count).stringValue : @"Off";
    };

    // The lock screen widget and Vibrations have rows of their own on Mod Settings' main page.
    NSArray<SGModRow *> *pages = @[
        SGWithTile(SGPageRow(@"Mini player", ^UIViewController *{ return SGRMiniPlayerSettingsPage(); }), @"rectangle.bottomthird.inset.filled", UIColor.systemPinkColor),
        SGWithTile(blocked, @"person.crop.circle.badge.xmark", UIColor.systemRedColor),
    ];
    // Shuffle, Repeat and Switch to video are switches that show them in the Player page's Controls section
    // (Redesigned/Player/PlayerSettings.m). Landscape turns the whole app and the player page with the phone
    // (Redesigned/Player/SystemTurn.m; its owner, 2026-11-06).
    NSMutableArray<SGModSection *> *sections = [NSMutableArray arrayWithObjects:SGSection(nil, pages),
        SGSection(nil, @[SGSwitchRow(@"Landscape", @"Turn the app and the player with the phone", SGRKeyLyricsLandscape)]), nil];
    // Spotify's own sleep timer fade, a flag it built and did not ship (Shared/Player/SpotifySleepTimer.m stands aside
    // while it is on). The only one kept of the Labs page that was.
    // The sleep timer: how long the mod fades Spotify's own timer out (Shared/Player/SpotifySleepTimer.m), and Spotify's
    // own fade, a flag it built and did not ship (which the mod's stands aside for).
    NSArray<NSString *> *fades = SGSleepTimerFadeNames();
    SGModRow *fade = SGMenuRow(@"Fade out", fades, ^NSString *{ return fades[(NSUInteger)SGSleepTimerFadeChoice()]; },
                               ^(NSInteger index) { SGSetInt(SGKeySleepTimerFade, index); });
    [sections addObject:SGNotedSection(@"Sleep timer", @[fade, SGFlagRow(@"Spotify's own fade", @"ios-feature-sleeptimer.enable_fade_out")],
                                       @"Fade out is how long the sound fades before the sleep timer from the player's ⋯ pauses Spotify. "
                                       @"Spotify's own fade applies after you restart Spotify.")];

    // The page leads with a card of the player and the background's control, then its own rows.
    return SGRPlayerSettingsPage(sections);
}
