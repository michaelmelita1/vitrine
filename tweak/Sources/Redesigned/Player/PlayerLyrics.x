// Whether the playing track has lyrics for the player page (SystemPlayer.m, SystemLandscape.m), and
// the Lyrics page's choice of what fades while they play alone. The landscape player is told as the lines come in and
// as a track's grace ends without them (SGRSystemTurnLinesChanged): it has no timer of its own to look again by.
#import "Core/SGCore.h"
#import "Shared/Lyrics/Lyrics.h"
#import "Shared/Player/PlayerState.h"
#import "Player.h"
#import "SystemPlayer.h"

// A track that changes while the lines are up has this long to bring its own before it counts as having none. A
// look for them still running then is waited out, since a local file's sources are asked one after another, up to
// 6 s each, with a Musixmatch token fetched first the first time.
static const NSTimeInterval kLyricsGrace = 3;

SGRLyricsHide SGRLyricsHideMode(void) {
    NSInteger stored = SGInt(SGRKeyLyricsAutoHide, -1);
    return stored >= 0 ? stored : SGEnabled(SGRKeyLyricsAutoHide) ? SGRLyricsHideAll : SGRLyricsHideOff;
}

BOOL SGRPlayerLyricsAvailable(void) {
    NSString *track = SGKaraokePlayingTrack();
    return track != nil && SGKaraokeLinesForTrack(track) != nil;
}

@interface SGRPlayerLyricsWatcher : NSObject <SGPlayerStateObserver>
@end

@implementation SGRPlayerLyricsWatcher {
    NSString *_track;
    BOOL _graceOver;   // the track playing has had its kLyricsGrace
}

- (instancetype)init {
    if (!(self = [super init])) return nil;
    [NSNotificationCenter.defaultCenter addObserver:self selector:@selector(linesKept:) name:SGKaraokeLinesKeptNotification object:nil];
    return self;
}

// Lines kept for the track playing, or the look for them over with none.
- (void)linesKept:(NSNotification *)note {
    if ([note.object isEqual:SGKaraokePlayingTrack()]) SGRSystemTurnLinesChanged();
}

- (BOOL)none {
    return _graceOver && !SGRPlayerLyricsAvailable() && !SGKaraokeLooking(SGKaraokePlayingTrack());
}

- (void)playerStateDidChange:(SPTPlayerState *)state {
    NSString *track = SGURIString(state.track.URI);
    if (!track || [track isEqualToString:_track]) return;
    _track = track;
    _graceOver = NO;
    dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(kLyricsGrace * NSEC_PER_SEC)), dispatch_get_main_queue(), ^{
        if (![self->_track isEqualToString:track]) return;
        self->_graceOver = YES;
        SGRSystemTurnLinesChanged();
    });
}

@end

static SGRPlayerLyricsWatcher *sg_watcher;

BOOL SGRPlayerLyricsNone(void) {
    return [sg_watcher none];
}

%ctor {
    if (!SGRedesignedUI()) return;
    sg_watcher = [SGRPlayerLyricsWatcher new];
    SGAddPlayerStateObserver(sg_watcher);
}
