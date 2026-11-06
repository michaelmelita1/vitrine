// Whether the redesign runs: the mod's own look (Redesigned/), iOS's own tab bar, the mod's mini player and its player
// page, from a clean sheet. It is Liquid Glass, which the system draws from iOS 26 on and no older OS can be given, so
// it runs on iOS 26 and later and nowhere else: below 26 nothing of Redesigned/ installs, Spotify keeps its own look,
// and what does not draw on Spotify's screens (Shared/: ads, lyrics sources, Sing, the
// Live Activity...) and Mod Settings still run. There is no switch: the Redesigned UI switch
// (spotifyglass.redesign) and the native look it picked between are gone, and the key is no longer read.
//
// Every hook file of Redesigned/ starts its %ctor with `if (!SGRedesignedUI()) return;`.
// Threading: safe from any thread.
#import <Foundation/Foundation.h>

// Whether this OS has the redesign's material: iOS 26 and up.
BOOL SGRedesignAvailable(void);
// The redesign runs this launch: SGRedesignAvailable(), logged once.
BOOL SGRedesignedUI(void);
