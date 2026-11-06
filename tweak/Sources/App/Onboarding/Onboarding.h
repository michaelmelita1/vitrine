// The install's environment (Environment.m) and the Spotify versions Vitrine knows.
#import <UIKit/UIKit.h>

// Environment.m: what about the install can work against the mod. Said once per install state, a few
// seconds after Spotify comes up and behind the tour, What's new and the signing sheet, and kept as
// warning rows at the top of Mod Settings while it lasts.
// The Spotify versions Vitrine knows. Supported ones are tested as long as the one it is made for, which comes
// first and whose flag table it reads. Likely ones ran cleanly in a short test. Neither gets the install
// warning, and About notes "likely works" after the second. A new version goes in one list, and the warning's
// text and About follow.
#define SGSpotifyMadeFor @"9.1.78"
#define SGSpotifySupportedVersions @[SGSpotifyMadeFor, @"9.1.88", @"9.1.90"]
#define SGSpotifyLikelyWorksVersions @[]
@class SGModRow;
// SGEeveeSpotifyInjected() is Shared/Lyrics/Lyrics.h's.
NSString *SGSpotifyVersion(void);
NSArray<SGModRow *> *SGEnvironmentWarningRows(void);
void SGCheckEnvironmentOnce(void);
