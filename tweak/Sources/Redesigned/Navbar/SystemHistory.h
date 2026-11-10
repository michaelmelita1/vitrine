// The player page's History, the mod's own (its owner, 2026-11-09): the songs actually listened to, newest last, rather
// than Spotify's queue's prevTracks, which counts every song skipped over when a song far down the queue is picked as
// played. A song counts once it has played 30 seconds, or half of a song shorter than a minute, as Spotify counts a
// play; up to 50 are kept across launches (about 300 bytes each: its address, title, artist, album and cover address).
//
// The Player page's History switch (SGRKeyOwnHistory, on until switched off) turns it off, and History is Spotify's list
// again; Clear History empties it.
//
// Threading: main thread only.
#import <UIKit/UIKit.h>
@class SPTPlayerTrack;

#define SGRKeyOwnHistory @"spotifyglass.redesign.history.own"
// How long a song plays before it counts (its owner, 2026-11-09): an index into SGRSystemHistoryAfterChoices, 30 seconds
// unless set.
#define SGRKeyHistoryAfter @"spotifyglass.redesign.history.after"
NSArray<NSString *> *SGRSystemHistoryAfterChoices(void);

// Whether History is the mod's own.
BOOL SGRSystemHistoryOn(void);
// The songs listened to, oldest first, as objects the queue's rows read as tracks (URI, trackTitle, artistName,
// metadata), leaving out the one playing now; nil while the switch is off.
NSArray *SGRSystemHistoryTracks(void);
// Empties it.
void SGRSystemHistoryClear(void);
// Posted on the main queue when it changes.
extern NSString *const SGRSystemHistoryDidChange;
