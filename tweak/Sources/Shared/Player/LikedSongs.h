// Liked Songs through Spotify's collection platform: the player page's ★ (Redesigned/Artist/ArtistFollow.x) and the
// Live Activity's Like shortcut.
#import <Foundation/Foundation.h>

// Adds the playing track to Liked Songs, never takes it out. NO when what plays is no track or no platform was
// reached yet. Spotify's toast shows only with Spotify in front.
BOOL SGLikePlayingTrack(void);
// The collection platform the app last reached for, nil until it has: for another feature that saves to Liked Songs.
id SGCollectionPlatformKept(void);
