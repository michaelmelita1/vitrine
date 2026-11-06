#import "Core/SGCore.h"
#import "Shared/AppIcon/AppIcon.h"
#import "Shared/Fonts/Fonts.h"
#import "Shared/LyricsTranslation/LyricsTranslation.h"
#import "Redesigned/Player/Player.h"
#import "Settings/SGModPage.h"
#import "Settings/SGPageStyle.h"
#import "Pages.h"
#import "Shared/ArtistBlock/ArtistBlock.h"
#import "Shared/Gestures/Gestures.h"
#import "Shared/Lyrics/Lyrics.h"
#import "Shared/LyricsMeanings/Meanings.h"
#import "Shared/Player/PlayerSettings.h"
#import "Shared/Sing/Sing.h"
#import "Native/Appearance/Appearance.h"
#import "Native/Navbar/Navbar.h"
#import "Native/NowPlayingBar/NowPlayingBar.h"
#import "Native/Player/NowPlaying.h"
#import "Shared/LiveActivity/LiveActivity.h"
#import "Shared/Lossless/SGLossless.h"
#import "Redesigned/Lyrics/LyricsText.h"
#import "Redesigned/Lyrics/LyricsLook.h"
#import "Redesigned/Navbar/Navbar.h"
#import "Redesigned/NowPlayingBar/NowPlayingBar.h"
#import "Redesigned/Kit/SGRAccent.h"

NSString *const SGRedesignedUIInfo = @"The newest version of Vitrine, leaning toward Apple Music's style. It is not compatible with the legacy look's settings.\n\nThe legacy look gives you more freedom, yet still looks like Spotify.";

void SGSetRedesignedUI(BOOL on) {
    SGSetEnabled(SGKeyRedesign, on);
}

// The whole look changes hands at launch, so the switch asks for the restart straight away rather than
// leaving Spotify half in the old look.
static void offerRestart(BOOL on) {
    UIAlertController *alert = [UIAlertController alertControllerWithTitle:@"Restart Spotify"
        message:on ? @"The redesign takes over when Spotify starts again. Spotify closes now; open it again to see it." : @"Spotify's own look comes back when Spotify starts again. Spotify closes now; open it again to see it."
        preferredStyle:UIAlertControllerStyleAlert];
    [alert addAction:[UIAlertAction actionWithTitle:@"Later" style:UIAlertActionStyleCancel handler:nil]];
    [alert addAction:[UIAlertAction actionWithTitle:@"Restart now" style:UIAlertActionStyleDefault handler:^(UIAlertAction *action) { SGRestartSpotify(); }]];
    [SGTopController() presentViewController:alert animated:YES completion:nil];
}

// iOS 26 and later only: below it the native look is the only one, and the row is not shown.
SGModRow *SGRedesignedUIRow(void) {
    SGModRow *redesign = SGOptionRow(@"Redesigned UI", nil, SGKeyRedesign);
    redesign.glows = YES;
    redesign.info = SGRedesignedUIInfo;
    redesign.visible = ^BOOL { return SGRedesignAvailable(); };
    redesign.changed = ^(BOOL on) {
        SGSetRedesignedUI(on);
        offerRestart(on);
    };
    return SGWithTile(redesign, @"sparkles", UIColor.systemIndigoColor);
}

// The stored look's own rows, then the font and the app icon, which work under either look on any iOS.
// Redesigned UI itself leads Mod Settings' main page.
UIViewController *SGAppearancePage(void) {
    NSMutableArray<SGModRow *> *everywhere = [NSMutableArray arrayWithArray:SGAppFontRows()];
    SGModRow *icon = SGAppIconRow();
    if (icon) [everywhere addObject:icon];
    return [[SGModPage alloc] initWithTitle:@"Appearance" intro:SGRestartNote sections:@[
        SGSection(nil, SGRedesignedUIStored() ? SGRAppearanceRows() : SGNativeAppearanceRows()),
        SGSection(nil, everywhere),
    ] footer:nil];
}

UIViewController *SGNavbarPage(void) {
    return SGRedesignedUIStored() ? SGRNavbarSettingsPage() : SGNavbarSettingsPage();
}

// Pronunciation, romanized lines, translation, word sweeping and line meanings exist only in the redesign's lyrics view.
static UIViewController *lyricsPage(void) {
    BOOL redesigned = SGRedesignedUIStored();
    NSMutableArray<SGModRow *> *more = [NSMutableArray arrayWithObjects:SGLockScreenLyricsRow(), SGLockScreenTranslationRow(), nil];
    if (!redesigned) [more insertObject:SGGlassLyricsRow() atIndex:0];
    SGModRow *sing = SGPageRow(@"Karaoke", ^UIViewController *{ return SGSingSettingsPage(); });
    sing.value = ^NSString *{ return SGSingSummary(); };
    NSMutableArray<SGModSection *> *sections = [NSMutableArray arrayWithObjects:SGSection(nil, @[SGWithTile(sing, @"music.mic", UIColor.systemRedColor)]),
                                                SGLyricsSourcesSection(redesigned), nil];
    SGModSection *timing = SGNotedSection(@"Timing", @[SGLyricsDelayRow()],
        @"Every line shows this much later than the song, for Bluetooth headphones that play a little behind the lyrics. Applies at once.");
    if (redesigned) {
        [sections addObjectsFromArray:@[
            SGSection(@"Display", @[SGRLyricsTextSizesRow(), SGLyricsWordTimingRow(), SGLyricsRomanisedRow(), SGLyricsRomanisedReplaceRow(),
                SGRLyricsHideRow()]),
            timing,
            SGSection(@"Translation", [[[@[SGLyricsTranslationLanguageRow(), SGTranslateEverySongRow()] arrayByAddingObjectsFromArray:SGOnDeviceTranslatorRows()]
                                          arrayByAddingObjectsFromArray:SGAITranslatorRows()] arrayByAddingObject:SGSavedTranslationsRow()]),
            SGSection(nil, @[SGLyricsMeaningsRow()]),
        ]];
    } else {
        [sections addObject:timing];
    }
    [sections addObject:SGSection(nil, more)];
    // The redesign's page leads with its lyrics playing in the look the page sets, and that look's presets.
    if (redesigned) return SGRLyricsSettingsPage(@"Lyrics", @"The look applies at once. The settings below apply after you restart Spotify.", sections);
    return [[SGModPage alloc] initWithTitle:@"Lyrics" intro:SGRestartNote sections:sections footer:nil];
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
    BOOL native = !SGRedesignedUIStored();

    // AirPods gestures, the lock screen widget and Vibrations have rows of their own on Mod Settings' main page.
    NSMutableArray<SGModRow *> *pages = [NSMutableArray array];
    // Gestures act on Spotify's own player, which the native look keeps; the redesign's player page is the mod's own.
    if (native) [pages addObject:SGWithTile(SGPageRow(@"Gestures", ^UIViewController *{ return SGGesturesSettingsPage(); }), @"hand.tap", UIColor.systemBlueColor)];
    else [pages addObject:SGWithTile(SGPageRow(@"Mini player", ^UIViewController *{ return SGRMiniPlayerSettingsPage(); }),
                                     @"rectangle.bottomthird.inset.filled", UIColor.systemPinkColor)];
    [pages addObject:SGWithTile(blocked, @"person.crop.circle.badge.xmark", UIColor.systemRedColor)];
    NSMutableArray<SGModSection *> *sections = [NSMutableArray arrayWithObject:SGSection(nil, pages)];
    if (native) {
        [sections addObject:SGSection(nil, @[
            SGWithTile(SGPageRow(@"Now playing bar", ^UIViewController *{ return SGNowPlayingBarSettingsPage(); }), @"rectangle.bottomthird.inset.filled", UIColor.systemPinkColor),
            SGWithTile(SGPageRow(@"Queue & devices", ^UIViewController *{ return SGQueueSettingsPage(); }), @"text.line.first.and.arrowtriangle.forward", UIColor.systemIndigoColor),
        ])];
        [sections addObjectsFromArray:SGNativePlayerScreenSections()];
        // Spotify's own chip over the title, and a tap on the cover opening it full screen, where it turns a little with
        // the phone. The native look's Shuffle and Repeat rows are in its Hide on the player section, with their own keys.
        [sections addObject:SGSection(nil, @[
            SGHideRow(@"Switch to video", @"The chip over the title of a song with a music video", SGKeyHideVideoSwitch),
            SGHideRow(@"Full screen cover", @"What a tap on the cover opens", SGKeyHideFullScreenCover),
        ])];
    } else {
        // The redesign's Shuffle, Repeat and Switch to video are switches that show them in the Player page's Controls
        // section (Redesigned/Player/PlayerSettings.m). Landscape turns the whole app and the player page with the phone
        // (Redesigned/Navbar/SystemTurn.m; its owner, 2026-11-06).
        [sections addObject:SGSection(nil, @[SGSwitchRow(@"Landscape", @"Turn the app and the player with the phone", SGRKeyLyricsLandscape)])];
    }

    [sections addObject:SGNotedSection(@"Lossless", @[
        SGOptionRow(@"Lossless files", @"Your own FLACs in place of Spotify's stream", SGKeyLossless),
    ], @"Put FLAC or ALAC files in Files › Spotify › Lossless. A file plays when its title and length match the song "
       @"and its sound matches what Spotify plays, from about 4 s after the song starts or you seek. Spotify still "
       @"streams its own copy, at its lowest quality while the next song has a file. Karaoke and speeds other than "
       @"1x keep Spotify's sound. Applies after you restart Spotify.")];

    // The redesign's page leads with a card of its player and the background's control, then its own rows.
    if (!native) return SGRPlayerSettingsPage(sections);
    return [[SGModPage alloc] initWithTitle:@"Player" intro:SGRestartNote sections:sections footer:nil];
}
