// The player page's background (SystemPlayer.m), chosen on the Player page (PlayerSettings.m), and
// Spotify's Canvas kept to the mod's own drawing of it.
#import "Core/SGCore.h"
#import "Player.h"
#import "Shared/AnimatedArtwork/AnimatedArtwork.h"

SGRPlayerBackgroundKind SGRPlayerBackground(void) {
    NSInteger kind = SGInt(SGRKeyPlayerBackground, SGEnabled(SGRKeyPlayerMotion) ? SGRPlayerBackgroundColours : SGRPlayerBackgroundStill);
    return kind >= SGRPlayerBackgroundStill && kind <= SGRPlayerBackgroundVisualiser ? kind : SGRPlayerBackgroundColours;
}

NSArray<NSString *> *SGRPlayerBackgroundNames(void) {
    return @[@"Still", @"Colors", @"Fluid", @"Animated", @"Visualizer"];
}

#pragma mark - Canvas

// The mod draws the Canvas itself (PlayerMotion.x), so Spotify's own is kept off: Spotify makes
// its Canvas cell (CanvasNowPlayingCell) only for a track whose metadata names a Canvas, so the keys move under
// SGMotionHiddenCanvas. ios-feature-canvas.canvas_enabled stays on: forced off, it also took the Canvas off the
// share sheet's story card (issue #87), which finds it without these keys.
static char kTrackMetadataKey;

%hook SPTPlayerTrack
- (NSDictionary *)metadata {
    NSDictionary *metadata = %orig;
    if (!metadata) return nil;
    // Read for every track many times a second, so the stripped copy is kept beside the dictionary it copies,
    // as LyricsHook.x does. A local file's edit (LocalFileInfo.x) hands out a new one, which is looked at again.
    NSArray *cached = objc_getAssociatedObject(self, &kTrackMetadataKey);
    if (cached.firstObject == metadata) return cached.lastObject;
    NSMutableDictionary *stripped = nil;
    for (NSString *key in metadata) {
        if (![key hasPrefix:@"canvas."]) continue;
        if (!stripped) stripped = [metadata mutableCopy];
        stripped[[SGMotionHiddenCanvas stringByAppendingString:key]] = metadata[key];
        [stripped removeObjectForKey:key];
    }
    NSDictionary *result = stripped ? [stripped copy] : metadata;   // handed out again, so unchangeable
    objc_setAssociatedObject(self, &kTrackMetadataKey, @[metadata, result], OBJC_ASSOCIATION_RETAIN);
    return result;
}
%end

%ctor {
    if (!SGRedesignedUI()) return;
    %init;
}
