// The player's settings that do not depend on the look: the lock screen widget's flags.
#import "Core/SGCore.h"
#import "Settings/SGModPage.h"
#import "PlayerSettings.h"
#import "Shared/AnimatedArtwork/AnimatedArtwork.h"
#import "Shared/Lyrics/Lyrics.h"

// Widget first: the line in place of the artist (on the Lyrics page too, the same switch) and Like and dislike,
// the one lock screen control a song gets. Spotify's flags for podcasts, audiobooks and its
// own lock screen artwork stay on the All flags page: the Artwork section is the mod's.
UIViewController *SGLockScreenWidgetPage(void) {
    SGModRow *likes = SGFlagRow(@"Like and dislike buttons", @"ios-feature-lockscreen.like_dislike_enabled");
    return [[SGModPage alloc] initWithTitle:@"Lock screen" intro:SGRestartNote sections:@[
        SGSection(@"Widget", @[SGLockScreenLyricsRow(), SGLockScreenTranslationRow(), likes]),
        SGSection(@"Artwork", SGLockScreenMotionRows()),
    ] footer:nil];
}
