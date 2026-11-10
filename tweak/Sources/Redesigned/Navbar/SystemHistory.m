#import "SystemHistory.h"
#import "Core/SGCore.h"
#import "Shared/Player/PlayerState.h"

NSString *const SGRSystemHistoryDidChange = @"SGRSystemHistoryDidChange";
static NSString *const kHistoryStore = @"spotifyglass.redesign.history.played";
static const NSUInteger kHistoryMax = 50;
static const double kAfterSeconds[] = {0, 5, 10, 20, 30};
static const NSInteger kAfterDefault = 4;

NSArray<NSString *> *SGRSystemHistoryAfterChoices(void) {
    return @[@"As soon as it plays", @"5 seconds", @"10 seconds", @"20 seconds", @"30 seconds"];
}

// The seconds a song plays before it counts, from the Player page's choice.
static double countsAfter(void) {
    NSInteger index = SGInt(SGRKeyHistoryAfter, kAfterDefault);
    if (index < 0 || index > kAfterDefault) index = kAfterDefault;
    return kAfterSeconds[index];
}

// A song of the mod's History as the queue's rows read a track.
@interface SGRPlayedTrack : NSObject
@property (nonatomic, copy) NSString *URI, *trackTitle, *artistName;
@property (nonatomic, copy) NSDictionary *metadata;
@end
@implementation SGRPlayedTrack
@end

BOOL SGRSystemHistoryOn(void) {
    return SGEnabled(SGRKeyOwnHistory);
}

static NSArray<NSDictionary *> *stored(void) {
    NSArray *list = [NSUserDefaults.standardUserDefaults arrayForKey:kHistoryStore];
    return [list isKindOfClass:NSArray.class] ? list : @[];
}

void SGRSystemHistoryClear(void) {
    [NSUserDefaults.standardUserDefaults removeObjectForKey:kHistoryStore];
    [NSNotificationCenter.defaultCenter postNotificationName:SGRSystemHistoryDidChange object:nil];
}

NSArray *SGRSystemHistoryTracks(void) {
    if (!SGRSystemHistoryOn()) return nil;
    NSString *playing = SGURIString(SGPlayerState().track.URI);
    NSMutableArray *tracks = [NSMutableArray array];
    NSArray<NSDictionary *> *list = stored();
    [list enumerateObjectsUsingBlock:^(NSDictionary *entry, NSUInteger i, BOOL *stop) {
        // The song playing now is the page's, not History's, once it has counted.
        if (i == list.count - 1 && [entry[@"uri"] isEqualToString:playing]) return;
        SGRPlayedTrack *track = [SGRPlayedTrack new];
        track.URI = entry[@"uri"];
        track.trackTitle = entry[@"title"];
        track.artistName = entry[@"artist"];
        NSMutableDictionary *metadata = [NSMutableDictionary dictionary];
        if (entry[@"album"]) metadata[@"album_title"] = entry[@"album"];
        if (entry[@"image"]) metadata[@"image_url"] = entry[@"image"];
        track.metadata = metadata;
        [tracks addObject:track];
    }];
    return tracks;
}

static void record(SPTPlayerTrack *track) {
    NSString *uri = SGURIString(track.URI);
    if (!uri.length || [uri hasPrefix:@"spotify:ad:"]) return;
    NSDictionary *metadata = [track.metadata isKindOfClass:NSDictionary.class] ? track.metadata : @{};
    NSMutableDictionary *entry = [NSMutableDictionary dictionaryWithObject:uri forKey:@"uri"];
    if (track.trackTitle.length) entry[@"title"] = track.trackTitle;
    if (track.artistName.length) entry[@"artist"] = track.artistName;
    if ([metadata[@"album_title"] isKindOfClass:NSString.class]) entry[@"album"] = metadata[@"album_title"];
    for (NSString *field in @[@"image_url", @"image_large_url"]) {
        if ([metadata[field] isKindOfClass:NSString.class]) { entry[@"image"] = metadata[field]; break; }
    }
    NSMutableArray *list = [stored() mutableCopy];
    [list addObject:entry];
    while (list.count > kHistoryMax) [list removeObjectAtIndex:0];
    [NSUserDefaults.standardUserDefaults setObject:list forKey:kHistoryStore];
    [NSNotificationCenter.defaultCenter postNotificationName:SGRSystemHistoryDidChange object:nil];
}

// Each song is counted once per time it starts: from when it comes on, by how far it has played.
@interface SGRHistoryObserver : NSObject <SGPlayerStateObserver>
@property (nonatomic, copy) NSString *current;
@property (nonatomic) BOOL counted;
@property (nonatomic, copy) NSString *waiting;   // the song a wait is already set for
@end

@implementation SGRHistoryObserver
- (void)playerStateDidChange:(SPTPlayerState *)state {
    [self playerStateDidReport:state];
}

- (void)playerStateDidReport:(SPTPlayerState *)state {
    if (!SGRSystemHistoryOn()) return;
    NSString *uri = SGURIString(state.track.URI);
    if (![uri isEqualToString:self.current]) {
        self.current = uri;
        self.counted = NO;
    }
    if (self.counted || !uri || state.isPaused) return;
    // Seconds (Headers/SPTPlayer.h); the player reports only on changes, so the moment it counts is waited for.
    // The state is the one last reported, its position as of then: run on by the time since, while it plays.
    double duration = state.duration, position = state.positionAsOfTimestamp;
    if (state.isPlaying && state.timestamp) position += MAX(0, -state.timestamp.timeIntervalSinceNow) * (state.playbackSpeed > 0 ? state.playbackSpeed : 1);
    double after = countsAfter();
    double needed = duration > 0 ? MIN(after, duration * 0.5) : after;
    if (position >= needed) {
        self.counted = YES;
        record(state.track);
        return;
    }
    if ([self.waiting isEqualToString:uri]) return;
    self.waiting = uri;
    NSString *waitingFor = uri;
    __weak typeof(self) weakSelf = self;
    dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)((needed - position + 0.5) * NSEC_PER_SEC)), dispatch_get_main_queue(), ^{
        SPTPlayerState *now = SGPlayerState();
        if ([weakSelf.waiting isEqualToString:waitingFor]) weakSelf.waiting = nil;
        if (weakSelf && [weakSelf.current isEqualToString:waitingFor] && [SGURIString(now.track.URI) isEqualToString:waitingFor])
            [weakSelf playerStateDidReport:now];
    });
}
@end

static SGRHistoryObserver *sg_historyObserver;

__attribute__((constructor)) static void historyAtLaunch(void) {
    if (!SGRedesignedUI() || !SGNativeRedesign()) return;
    [NSNotificationCenter.defaultCenter addObserverForName:UIApplicationDidFinishLaunchingNotification object:nil queue:nil
                                                usingBlock:^(NSNotification *note) {
        dispatch_async(dispatch_get_main_queue(), ^{
            sg_historyObserver = [SGRHistoryObserver new];
            SGAddPlayerStateObserver(sg_historyObserver);
        });
    }];
}
