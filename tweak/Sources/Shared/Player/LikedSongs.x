// Liked Songs: -addURL:showUIConfirmation:completion: of Spotify's collection platform, which for a track is Liked
// Songs. Spotify 9.1.78 has four classes with that selector and with -stateProvider (SPTCollectionPlatformImplementation,
// Collection_PlatformImpl's CollectionPlatformImpl and CollectionPlatformMigration, AlignedCuration's
// ACUCollectionPlatform); whichever the app last reached for is kept, weakly. The lock screen's like
// (LockScreenBaseRemoteControlPolicy's likeButtonPressedWithCompletion:identifier:) is not used: it toggles.
#import "Core/SGCore.h"
#import "Shared/Player/PlayerState.h"
#import "LikedSongs.h"

@protocol SGCollectionPlatform <NSObject>
- (void)addURL:(NSURL *)url showUIConfirmation:(BOOL)show completion:(id)completion;
@end

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

BOOL SGLikePlayingTrack(void) {
    NSString *uri = SGURIString(SGPlayerState().track.URI);
    id platform = SGCollectionPlatformKept();
    // Only a track: an episode is saved another way, and an ad is nothing to save.
    if (![uri hasPrefix:@"spotify:track:"] || !platform) return NO;
    BOOL inFront = UIApplication.sharedApplication.applicationState == UIApplicationStateActive;
    // A block that reads no arguments: whatever the completion is called with, it is safe to ignore.
    [(id<SGCollectionPlatform>)platform addURL:[NSURL URLWithString:uri] showUIConfirmation:inFront completion:^{}];
    return YES;
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
