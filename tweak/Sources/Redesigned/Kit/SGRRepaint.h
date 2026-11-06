// The areas the redesign stripped and SGRRepaint.x keeps transparent when Spotify repaints them, each
// set by the part of the redesign that owns it.
#import <UIKit/UIKit.h>

// Redesigned/Playlist/PlaylistField.x, the playlist page. Only the base surface Spotify paints the page,
// its list and its rows with goes clear here: the artwork field is underneath, and the grays of a
// placeholder or a badge are what still has to read against it.
extern __weak UIView *sgr_playlistRoot;
// Redesigned/Album/AlbumField.x, the album page, kept clear the same way and for the same reason.
extern __weak UIView *sgr_albumRoot;
// Redesigned/Artist/ArtistField.x, the artist page, kept clear the same way and for the same reason.
extern __weak UIView *sgr_artistRoot;
