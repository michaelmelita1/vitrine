// Which of the two looks runs: Spotify's own screens with the mod's tweaks on them (Native/), or the
// redesign (Redesigned/), picked by Redesigned UI at the top of Mod Settings. What does not draw on Spotify's
// screens (Shared/) runs under both. The switch is read once, the first time anything asks, so the
// hooks, the flags and the pages see one answer for the whole launch and a change waits for the restart.
//
// Every hook file of Native/ starts its %ctor with `if (!SGNativeUI()) return;`, every one of
// Redesigned/ with `if (!SGRedesignedUI()) return;`: the two never run together, which is what lets
// each hook the same Spotify class in its own way.
// Threading: safe from any thread.
#import <Foundation/Foundation.h>

#define SGKeyRedesign @"spotifyglass.redesign"

// The redesign is Liquid Glass, and Liquid Glass is UIGlassEffect, which the system renders and which
// no older OS can be given, so the redesign is offered on iOS 26 and later only. Below 26 the native look
// runs whatever the stored switch says; a phone updated to 26 gets back the redesign it was last asked for.
// The warning once accepted to run it below 26 anyway (spotifyglass.redesign.untested) is no longer read.

// Whether this OS has the redesign's material: iOS 26 and up.
BOOL SGRedesignAvailable(void);

BOOL SGRedesignedUI(void);
BOOL SGNativeUI(void);
// The stored switch rather than the launch's, for settings pages opened after it was flipped: they show what the
// restart will bring. NO below iOS 26.
BOOL SGRedesignedUIStored(void);

// The redesign is what was once Native redesign, a switch of its own under it (spotifyglass.redesign.native): iOS's own
// tab bar, the mod's mini player in it and the mod's own player page (Redesigned/Navbar/SystemTabs.x, SystemPlayer.m).
// The glass tab bar, the glass now playing bar and the redesigned Spotify player it stood in for are gone, so the key is
// no longer read.
