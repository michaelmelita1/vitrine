// Animated artwork: the track's Canvas or Apple Music's animated cover, looked up for the player page
// (SystemPlayer.m), which draws it its own way (SystemMotion.m), and for the landscape player
// (SystemLandscape.m). A follower walks each track as it plays (SGMotionFollower) while the background is Animated,
// so the next track's clip is often in the store before it is asked for; a page asking for a track the follower has
// no clip for looks it up itself (SGRPlayerMotionPreview). The ⋯ menu switches between Animated and Fluid at once
// (Player.h). Under Reduce Motion and in Low Power Mode no clip is looked up.
#import "Core/SGCore.h"
#import "Redesigned/Kit/SGRKit.h"
#import "Shared/AnimatedArtwork/AnimatedArtwork.h"
#import "Shared/Player/PlayerState.h"
#import "Shared/Player/SGLastTrack.h"
#import "Player.h"
#import "SystemPlayer.h"

static NSString *sg_track;   // the track playing
static NSString *sg_shown;   // the track sg_motionFile is the clip of
static NSUInteger sg_begun;   // counts the walks begun, so a poster read for an earlier one is dropped
// The follower's clip and its poster.
static NSURL *sg_motionFile;
static UIImage *sg_motionPoster;

// The playing track's clip a page looked up itself while the follower had none, and its poster; the
// file is nil while the walk is out or after it found nothing. The walk is the player's (SGMotionClipFor, at
// the size SGMotionFollower asks for), so its file lands in the store, where the player's own walk finds it.
// With no track playing, the track is the last one played (Shared/Player/SGLastTrack.h).
static NSString *sg_previewTrack;
static NSURL *sg_previewFile;
static UIImage *sg_previewPoster;
static void (^sg_previewArrived)(void);
// The last track the page's walk found no clip for, and when: asked again within kNoneKept, it is not walked again.
static NSString *sg_noneTrack;
static CFTimeInterval sg_noneAt;
static const CFTimeInterval kNoneKept = 30;

BOOL SGRPlayerMotionFile(NSURL **file, UIImage **poster) {
    NSString *track = SGShownTrackNow().uri;
    NSURL *found = nil;
    UIImage *picture = nil;
    if (sg_motionFile && (!track || [track isEqualToString:sg_shown])) {
        found = sg_motionFile;
        picture = sg_motionPoster;
    } else if (sg_previewFile && track && [track isEqualToString:sg_previewTrack]) {
        found = sg_previewFile;
        picture = sg_previewPoster;
    }
    if (file) *file = found;
    if (poster) *poster = picture;
    return found != nil;
}

BOOL SGRPlayerMotionNoneFor(NSString *track) {
    return track && [track isEqualToString:sg_noneTrack] && CACurrentMediaTime() - sg_noneAt < kNoneKept;
}

UIView *SGRPlayerMotionPreview(void (^arrived)(void)) {
    SGShownTrack *shown = SGShownTrackNow();
    NSString *track = shown.uri;
    // The follower's clip only while it is the shown track's: asked right after a skip, before the follower has heard of
    // it, the last track's clip was handed out and stayed on the page for the new track (its owner, 2026-11-01).
    if (sg_motionFile && (!track || [track isEqualToString:sg_shown])) return SGRSystemMotionPreviewOf(sg_motionFile, sg_motionPoster);
    if (!track) return nil;
    BOOL asked = [track isEqualToString:sg_previewTrack];
    if (asked && sg_previewFile) return SGRSystemMotionPreviewOf(sg_previewFile, sg_previewPoster);
    if (!arrived) return nil;
    if (SGRPlayerMotionNoneFor(track)) return nil;
    // The newest page's to be told; a walk already out for this track is waited on rather than asked again.
    sg_previewArrived = [arrived copy];
    if (asked) return nil;
    sg_previewTrack = track;
    sg_previewFile = nil;
    sg_previewPoster = nil;
    SGLog(@"redesign player: the Player page looks up the clip of %@%@", track, shown.current ? @"" : @", the last played");
    SGMotionClipFor(track, shown.canvasURL, shown.artist, shown.album, SGMotionTall, SGMotionPixels(),
                    ^(NSURL *file, NSString *source) {
        if (![track isEqualToString:sg_previewTrack]) return;
        // Nothing found is kept a little while (SGRPlayerMotionNoneFor), and the page told, so it shows Fluid at once
        // rather than waiting out its hold (its owner, 2026-11-02: Animated to Fluid lagged).
        if (!file) {
            void (^done)(void) = sg_previewArrived;
            sg_previewTrack = nil;
            sg_previewArrived = nil;
            sg_noneTrack = track;
            sg_noneAt = CACurrentMediaTime();
            if (done) done();
            return;
        }
        SGMotionPoster(file, ^(UIImage *poster) {
            if (![track isEqualToString:sg_previewTrack]) return;
            void (^done)(void) = sg_previewArrived;
            sg_previewArrived = nil;
            if (!poster || poster.size.width <= 0) {
                sg_previewTrack = nil;
                return;
            }
            sg_previewFile = file;
            sg_previewPoster = poster;
            SGLog(@"redesign player: the Player page's clip from %@, %@", source, file.lastPathComponent);
            if (done) done();
        });
    });
    return nil;
}

static SGMotionFollower *sg_follower;

// Reduce Motion asks for no looping clip, and Low Power Mode for no video decoding behind the player.
static BOOL motionAllowed(void) {
    return !SGRReduceMotion() && !NSProcessInfo.processInfo.lowPowerModeEnabled;
}

NSNotificationName const SGRPlayerMotionDidChangeNotification = @"spotifyglass.redesign.playerMotionDidChange";

static void postMotionChanged(void) {
    [NSNotificationCenter.defaultCenter postNotificationName:SGRPlayerMotionDidChangeNotification object:nil];
}

static void clear(void) {
    BOOL had = sg_motionFile != nil;
    sg_shown = nil;
    sg_motionFile = nil;
    sg_motionPoster = nil;
    if (had) postMotionChanged();
}

static void show(NSString *track, NSURL *file) {
    if (!file || ![track isEqualToString:sg_track]) return;
    NSUInteger begun = sg_begun;
    SGMotionPoster(file, ^(UIImage *poster) {
        // A walk begun while the poster was read (a skip, switched off) has the say.
        if (!poster || poster.size.width <= 0 || begun != sg_begun) return;
        sg_shown = track;
        sg_motionFile = file;
        sg_motionPoster = poster;
        SGLog(@"redesign player: animated artwork %@, %.0fx%.0f", file.lastPathComponent, poster.size.width, poster.size.height);
        postMotionChanged();
    });
}

// The same track walked again (its Canvas came late) keeps its clip until the new one comes; another track lets it go.
static BOOL beginTrack(NSString *track) {
    sg_track = track;
    sg_begun++;
    // Read on every track, since the ⋯ menu switches it.
    BOOL wanted = SGRPlayerBackground() == SGRPlayerBackgroundAnimated && motionAllowed();
    if (wanted && [track isEqualToString:sg_shown]) return YES;
    clear();
    return wanted;
}

#pragma mark - the ⋯ menu's switch (Player.h)

// Fluid, Animated and the Visualizer share the field, so the menu moves between them without a restart. The
// other backgrounds are a field of another kind, chosen on the Player page (PlayerSettings.m).
BOOL SGPlayerMenuOffersAnimatedArtwork(void) {
    return sg_follower && SGRPlayerBackground() >= SGRPlayerBackgroundFluid;
}

static BOOL animatedArtworkOn(void) {
    return SGRPlayerBackground() == SGRPlayerBackgroundAnimated;
}

void SGPlayerMenuSetAnimatedArtwork(BOOL on) {
    if (!SGPlayerMenuOffersAnimatedArtwork() || on == animatedArtworkOn()) return;
    SGSetInt(SGRKeyPlayerBackground, on ? SGRPlayerBackgroundAnimated : SGRPlayerBackgroundFluid);
    SGLog(@"redesign player: animated artwork switched %@ from the menu", on ? @"on" : @"off");
    // The playing track is let go, and looked up again when switched on.
    clear();
    [sg_follower restart];
}

%ctor {
    if (!SGRedesignedUI()) return;
    SGRPlayerBackgroundKind background = SGRPlayerBackground();
    if (background < SGRPlayerBackgroundFluid) return;
    // The track is walked again as either changes. The power state is reported off the main thread, which must not
    // wait for main (AGENTS.md), so the observer takes it where it is posted and hops.
    __block BOOL allowed = motionAllowed();
    for (NSNotificationName name in @[NSProcessInfoPowerStateDidChangeNotification, UIAccessibilityReduceMotionStatusDidChangeNotification]) {
        [NSNotificationCenter.defaultCenter addObserverForName:name object:nil queue:nil usingBlock:^(NSNotification *note) {
            dispatch_async(dispatch_get_main_queue(), ^{
                if (motionAllowed() == allowed) return;
                allowed = !allowed;
                SGLog(@"redesign player: animated artwork %@", allowed ? @"allowed again, the clip looked up" : @"held off by Reduce Motion or Low Power Mode, Fluid shows");
                [sg_follower restart];
            });
        }];
    }
    sg_follower = [[SGMotionFollower alloc] initWithBegin:^BOOL(NSString *uri, SPTPlayerState *state) {
        return beginTrack(uri);
    } found:^(NSString *uri, NSURL *file) {
        if (file) show(uri, file);
        else clear();
    }];
}
