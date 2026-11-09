// Native redesign (SystemPlayer.m's queue button): whether a Spotify Jam is on, and the faces of who is in it, read off Spotify's own Jam views, since its Jam is Swift
// alone and the player's state says nothing of it (the owner's Jam log, 2026-11-09: the context and the provider stay
// the album's and autoplay's throughout). While a Jam is on Spotify draws its Jam hat on the now playing bar
// (Jam_AttachmentsImpl's JamHatElement, a SwiftUI hosting view), and from the time someone joins an Encore facepile.
//
// Threading: main thread only.
#import <UIKit/UIKit.h>

// nil when no Jam is on; while one is, the faces Spotify has shown during it (up to `max`), or the user's own picture
// before any, or empty when there is neither.
NSArray<UIImage *> *SGRSystemJamFaces(NSUInteger max);
