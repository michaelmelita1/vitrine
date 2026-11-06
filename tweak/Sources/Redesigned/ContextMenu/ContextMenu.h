// The redesign's ⋯ opens the system menu instead of Spotify's sheet, the way the Music app's does: the ⋯
// every redesigned entity page pins to its corner (playlist, album, artist and the pages that share their
// templates). Always on in the redesign; no setting. The player page's ⋯ is a menu of the mod's own
// (Redesigned/Player/SystemPlayer.m), since Spotify's song sheet comes only from Spotify's player.
//
//     ContextMenu.x   the takeover: Spotify's sheet presented unseen, its rows read into a UIMenu shown from
//                     the ⋯, a pick fired on the sheet, and the sheet itself as the fallback
//
// Spotify's rows come from Swift item factories with nothing to read them from but the cells they fill, so
// the sheet is still Spotify's and still made, unseen.
//
// A page's ⋯ opens Spotify's sheet with its tap, presented without animation in a container at alpha 0 from its
// first frame, and the menu opens over it from an invisible anchor button inside the ⋯, its rows a deferred
// element that waits for them. The Kit records the ⋯'s taps (SGRPinnedMoreRecentButton), so the ⋯ needs no call.
//
// A pick closes the menu and then selects that row on the sheet, so what it does stays Spotify's; a pick that
// leaves the sheet up (a row opening a page of its own) shows the sheet. Rows the mod puts in the sheet's
// header or footer (Sort and Mix on a playlist) are read the same way and fired the
// same way. Closing the menu without a pick dismisses the sheet.
//
// The anchor takes touches only while its menu is up, so every other tap reaches the ⋯ under it, and the
// menu is opened with -[UIControl performPrimaryAction] (iOS 17.4), else UIContextMenuInteraction's private
// _presentMenuAtLocation:, each checked with respondsToSelector:. When neither is there, or the menu does not
// come up, Spotify's sheet shows at once instead, with nothing waited out.
//
// Threading: main thread only.
#import <UIKit/UIKit.h>
