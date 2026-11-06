// Liked Songs: Spotify's collection platform, whose -addURL:showUIConfirmation:completion: saves a track to Liked
// Songs (Redesigned/Artist/ArtistFollow.x calls it). Spotify 9.1.78 has four classes with that selector and with -stateProvider (SPTCollectionPlatformImplementation,
// Collection_PlatformImpl's CollectionPlatformImpl and CollectionPlatformMigration, AlignedCuration's
// ACUCollectionPlatform); whichever the app last reached for is kept, weakly. The lock screen's like
// (LockScreenBaseRemoteControlPolicy's likeButtonPressedWithCompletion:identifier:) is not used: it toggles.
#import "Core/SGCore.h"
#import "LikedSongs.h"

static __weak id sg_platform;

// Spotify's platforms wrap one another, so the one kept can change often. Spotify asks for its state provider from any
// thread.
static void keepPlatform(id platform) {
    if (platform == sg_platform || ![platform respondsToSelector:@selector(addURL:showUIConfirmation:completion:)]) return;
    @synchronized (NSObject.class) {
        sg_platform = platform;
    }
}

id SGCollectionPlatformKept(void) {
    @synchronized (NSObject.class) {
        return sg_platform;
    }
}

%hook SPTCollectionPlatformImplementation
- (id)stateProvider {
    keepPlatform(self);
    return %orig;
}
%end

%hook _TtC23Collection_PlatformImpl22CollectionPlatformImpl
- (id)stateProvider {
    keepPlatform(self);
    return %orig;
}
%end

%hook _TtC23Collection_PlatformImpl27CollectionPlatformMigration
- (id)stateProvider {
    keepPlatform(self);
    return %orig;
}
%end

%hook _TtC26AlignedCuration_CommonImpl21ACUCollectionPlatform
- (id)stateProvider {
    keepPlatform(self);
    return %orig;
}
%end

%ctor {
    %init;
    SGRequireClasses(@[@"SPTCollectionPlatformImplementation", @"_TtC23Collection_PlatformImpl22CollectionPlatformImpl"]);
}
