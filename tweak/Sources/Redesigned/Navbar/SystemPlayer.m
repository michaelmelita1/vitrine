// Prototype: the system tab bar's player, a page of the mod's own (its owner, 2026-11-01). Spotify's player held in the
// page brought its own pulls and closes, and UIKit's swipe close lost to them; a page of the mod's alone opened and
// closed by the zoom every time. So the player is drawn here from the player's state, the Music app's layout from top
// to bottom: the cover blurred behind everything, a close button, the cover, the title and artist, the progress, the
// controls, the volume and a row of lyrics, AirPlay and the queue. The queue and Spotify's Connect sheet open over the
// page, which stays: Spotify presents them from its own controllers under the page, and SystemTabs.x sends those
// presentations to the page instead (its owner, 2026-11-01; closing the page first left Connect opening nothing).
//
// The lyrics glyph trades the cover for the redesign's Apple Music style lines (Redesigned/Lyrics/SGRKaraokeView.h), as
// the Music app does: the cover shrinks to a thumbnail at the top with the title and artist beside it, and the lines
// take the room between them and the progress. The lines, their timing, the clock, the follow and the pause after a
// scroll by hand, and the seek of a tap on a line are the view's own, the same as in the redesigned player.
//
// Nothing else here pans up and down or scrolls: UIKit's zoom close is a drag down anywhere on the page, and a vertical
// recognizer of the page's would compete with it. The lines' scroll view is the one exception, which the zoom's close
// works with as with any scroll view at its top: the view lays the lines out for an offset of 0, so it is at its top
// whenever it follows the song. The progress and the volume, the two sideways drags, turn the pans above them off
// while a finger is on them, as the redesigned player's volume does (PlayerVolume.m).
//
// The header's ⋯ (its owner, 2026-11-01) cannot open the redesigned player's menu: that menu is Spotify's own ⋯ sheet read
// into a system menu (Redesigned/ContextMenu), and the sheet comes only from the ⋯ action of Spotify's player, which is
// never up under this page. No other way to that sheet is proven: Spotify's track menu presenters are Swift services
// handed out by its dependency graph, the ObjC factory selectors in the binary (contextMenuPresenterForTrackWithTrackURI:
// and its thirteen more arguments) need a factory nothing of the mod's holds, spotify:context-menu is a URI kind with
// fixed subpages (audio settings, DJ feedback...) rather than a menu for a track, and the now playing bar has no menu.
// So the ⋯ opens a system menu of what is proven without Spotify's player: Liked Songs (the collection platform, as the
// add button), share, the album and the artist, then the player's own Speed, Pitch & Reverb and Lyrics Source
// (Player.h's SGRPlayerMenuPageItems). Spotify's own rows (add to playlist, the queue, radio...) are not in it.
//
// While the lines play, the rest of the page gives way to them as in the redesigned player (PlayerLyrics.x's setAlone,
// its owner, 2026-11-01): a scroll on through the lines, or kRest without a touch while the song plays, fades the
// header, the thumbnail and title, and every control, and the lines take the whole safe area (with Hide the controls
// set to Keep the title, the header, thumbnail and title stay and the lines grow down only); a tap where nothing
// seeks, a scroll back, a pause or VoiceOver brings it all back. The recognizers for that are taps and a watcher that
// never recognizes, so the zoom's close keeps the only vertical drag.
//
// Turned sideways with the app (SystemTurn.m), the page holds the landscape player (SystemLandscape.m, iOS 27.3's) over
// everything of its own, on its lyrics or queue if the page's are up, and comes back on what it showed.
//
// The Player page's settings reach it too (its owner, 2026-11-01): Volume (the row goes and the controls close up, read at
// each open), Hide on the player's Shuffle and Repeat (by alpha in their slots, as PlayerControls.x hides them), the hold
// on the cover for 2× (PlayerArtwork.x's, SGRPlayerAttachCoverHold). TODO ("aim to add at some point"): Switch to video is
// not honoured here yet; the page has no video chip, and its row stays as it is meanwhile.
//
// The commands are the ones the mod already sends (Headers/SPTPlayer.h): pause:/resume:, skipToNextTrackWithOptions:
// and skipToPreviousTrackWithOptions: (the mini player, the Live Activity), seekTo: (Shared/Lyrics/KaraokeSource.x,
// Shared/HeadGestures/HeadGestures.x), setShufflingContext:, setRepeatingContext: and setRepeatingTrack: (both again).
#import <AVKit/AVKit.h>
#import <objc/runtime.h>
#import <objc/message.h>
#import "Core/SGCore.h"
#import "Redesigned/Kit/SGRRepaint.h"
#import "Shared/Player/SleepTimer.h"
#import "Shared/Haptics/Haptics.h"
#import "Settings/SGMarquee.h"
#import "Shared/Player/SpeedPitch.h"
#import "Redesigned/Kit/SGRKit.h"
#import "Redesigned/Artist/Artist.h"
#import "Redesigned/Lyrics/SGRKaraokeView.h"
#import "Redesigned/Lyrics/SGRSingButton.h"
#import "Redesigned/NowPlayingBar/NowPlayingBar.h"
#import "Redesigned/Player/Player.h"
#import "Shared/Player/PlayerState.h"
#import "Shared/Player/PlayerSettings.h"
#import "Shared/Player/SGLastTrack.h"
#import "SystemJam.h"
#import "Shared/Navigation/Links.h"
#import "Shared/Sing/Sing.h"
#import "SystemPlayer.h"
#import "SystemQueue.h"
#import "SystemHistory.h"
#import "SystemDJRing.h"

// The page's side margin, the Music app's.
static const CGFloat kMargin = 28;
// The queue button's disc while open: its side, its white, and the glyph's dark on it (the Music app's, from its owner's
// screenshot, 2026-11-02).
// The lyrics' and the queue's look while up, the Music app's (its owner's screenshots, 2026-11-02): a light disc with the
// glyph cut out of it, the page showing through.
static const CGFloat kQueueBubble = 40, kQueueBubbleWhite = 0.62;
// Over animated artwork, the cover's fade as the lyrics close (quick, at the start of the move), and as they open (late,
// as the thumbnail settles).
static const NSTimeInterval kCoverToClipOut = 0.12, kCoverToThumbIn = 0.18, kCoverToThumbDelay = 0.16;
// How far into the open the progress bar and the volume take touches (_appeared): the zoom has the page in place by
// then, though UIKit's own end comes 1 to 1.4 s after the tap (the phone's log, 2026-11-01).
static const CFTimeInterval kTouchesAfter = 0.45;
// How long a skip keeps the last track's clip up while the new track's is looked up (syncClipAnimated:).
static const CFTimeInterval kClipHold = 1.2;
// How long a new track's small stand-in cover is kept off the page while its full one is fetched (refreshCover).
static const CFTimeInterval kCoverWait = 0.6;
// How long a state without a track is waited out before the page and the mini player say Not Playing.
static const CFTimeInterval kEmptyWait = 0.6;
// The cover rests at the redesigned player's paused size (PlayerArtwork.x's kPausedScale).
static const CGFloat kPausedScale = 0.84;
// The progress bar after f728743/Sim-Radio-SwiftUI's ElasticSlider.swift and its .playbackProgress config (MIT,
// Copyright (c) 2025 Alexey Vorobyov; its owner's pick, 2026-11-01): 7 high at rest and kScrubGrowth in from each end, 17
// held and the full width, the times moving out with it, on SwiftUI's .smooth(duration: 0.3, extraBounce: 0.3) both
// ways; no stretch past the ends. And its touch area.
static const CGFloat kTrackRest = 7, kTrackHeld = 17, kScrubGrowth = 9, kScrubberHeight = 28;
static const NSTimeInterval kScrubSpring = 0.3;
static const CGFloat kScrubBounce = 0.3;
// White's opacity: the progress fill at rest and held, and the part still to play.
static const CGFloat kFillRest = 0.65, kFillHeld = 1, kEmpty = 0.24;
// After a seek the state still reports the old place for a moment: the bar holds the new one meanwhile, so it does not
// jump back and forth.
static const CFTimeInterval kSeekHold = 1.5;
// How far a finger moves along the bar before the pans above it go off (PlayerVolume.m's kDragStart).
static const CGFloat kScrubDragStart = 6;
// The cover as the thumbnail it shrinks to while the lyrics are up, and the gap between it and the title beside it.
static const CGFloat kThumbSide = 60, kThumbGap = 14;
// The lyrics glyph, the redesigned player's footer's (PlayerFooter.x).
static NSString *const kLyricsSymbol = @"quote.bubble", *const kLyricsSymbolOpen = @"quote.bubble.fill";

// A light disc `side` across with `symbol` in `config` cut out of it.
static UIImage *cutDiscImage(NSString *symbol, UIImageSymbolConfiguration *config, CGFloat side) {
    UIImage *glyph = symbol ? [UIImage systemImageNamed:symbol withConfiguration:config] : nil;
    UIGraphicsImageRenderer *renderer = [[UIGraphicsImageRenderer alloc] initWithSize:CGSizeMake(side, side)];
    UIImage *disc = [renderer imageWithActions:^(UIGraphicsImageRendererContext *context) {
        [[UIColor colorWithWhite:1 alpha:kQueueBubbleWhite] setFill];
        [[UIBezierPath bezierPathWithOvalInRect:CGRectMake(0, 0, side, side)] fill];
        if (!glyph) return;
        CGSize size = glyph.size;
        [glyph drawInRect:CGRectMake(round((side - size.width) / 2), round((side - size.height) / 2), size.width, size.height)
                blendMode:kCGBlendModeDestinationOut alpha:1];
    }];
    return disc;
}

// A light disc with `symbol` cut out of it, at the glyph buttons' 20 pt regular, hidden until shown.
static UIImageView *cutDisc(NSString *symbol) {
    UIImageSymbolConfiguration *config = [UIImageSymbolConfiguration configurationWithPointSize:20 weight:UIImageSymbolWeightRegular];
    UIImageView *view = [[UIImageView alloc] initWithImage:cutDiscImage(symbol, config, kQueueBubble)];
    view.userInteractionEnabled = NO;
    view.alpha = 0;
    return view;
}

UIImageView *SGRSystemCutDisc(NSString *symbol) {
    return cutDisc(symbol);
}
// The bottom row's middle above the safe area's bottom, never less than the minimum above the screen's, and the route
// line's middle under it: the redesigned player's footer's (PlayerFooter.x's kRowAboveSafeArea, kRowMinBottom and
// kRouteLineDrop), which leave the line its room over the home indicator.
static const CGFloat kRowAboveSafeArea = 32, kRowMinBottom = 34, kRouteLineDrop = 32;
// The add button's glyph beside the title and artist, and its touch square.
static const CGFloat kAddGlyph = 22, kAddSide = 44;
// The layout from the bottom row up, the redesigned player's as its owner's screenshots of the two show it, on a 440x956
// screen (2026-11-01): the volume's middle above the row's, the controls' above the volume's, the times' above the
// controls', the progress bar's above the times'; the header's circles in from the sides and down from the safe area;
// previous and next out from the middle as a share of the width between the margins; the bottom row's glyphs at a
// fifth, half and four fifths of the width, as PlayerFooter.x places them (kLeading, kMiddle, kTrailing). The first three
// gaps are times controlsSpacing() (below).
static const CGFloat kVolumeAboveRow = 38, kControlsAboveVolume = 58, kTimesAboveControls = 46, kScrubberAboveTimes = 17;
static const CGFloat kHeaderSide = 16, kHeaderDrop = 2, kSkipShare = 0.25, kSkipGlyph = 32, kPlayGlyph = 44;
// An episode's skips go back and forward this far, as Spotify's episode player's 15 s buttons do.
static const double kEpisodeSkip = 15;
// With the volume row off, the controls' middle above the bottom row's: they close up into its room.
static const CGFloat kControlsAboveRowAlone = 72;
// The title's swipe pages to the track before or after as the mini player's does (SystemTabs.x's kSwipeDistance,
// kSwipeSpeed and kPageGap): far enough as a share of the text's width, or fast enough, and the gap between pages.
static const CGFloat kTitleSwipeDistance = 0.28, kTitleSwipeSpeed = 600, kTitlePageGap = 24;
// The soft edge at each side of the title's column, the mini player's (SystemTabs.x's kTextFade).
static const CGFloat kTitleFade = 14;
// The lines on their own: the controls fade after this long without a touch, and the lines keep this far from the safe
// area's ends (PlayerLyrics.x's kRest and kLyricsBottom).
static const NSTimeInterval kRest = 4;
static const CGFloat kAloneInset = 8;
// Spotify's Connect device picker by link: a URI kind in the 9.1.90 binary (SpotifyURI's table, beside
// spotify:connect-context-menu), opened only when the link dispatcher's registry says a handler takes it.
static NSString *const kConnectURI = @"spotify:connect-device-picker";

// Where the lyrics stand for the track playing: their lines in, still being looked for, or none (the redesigned player's
// verdict, after its grace: Player.h's SGRPlayerLyricsNone).
typedef NS_ENUM(NSInteger, SGRSystemLyrics) { SGRSystemLyricsUnknown, SGRSystemLyricsLines, SGRSystemLyricsLoading, SGRSystemLyricsNone };

// The lyrics were up when the page last closed: the next one opens on them, as the Music app does.
static BOOL sgr_lyricsLeftOpen;

static char kConnectKey;

// Keeps the borrowed surface the size of the cover: Spotify's bar lays it out again to its own size, and laid out to nothing it
// came off the video (attached 0, eligible 0, 0x0 two seconds in: the owner's log, 2026-11-09).
@interface SGRFrameKeeper : NSObject
@property (nonatomic, weak) UIView *view;
@property (nonatomic) BOOL busy;
@property (nonatomic) CFTimeInterval windowStart, restUntil;
@property (nonatomic) NSInteger corrections;
@end

@implementation SGRFrameKeeper
// Put back without animation, and not more than 20 times a second: Spotify moves the surface on its own changes too, and
// the two answering each other kept the main thread busy until the watchdog killed the app at launch (2026-11-10). Past
// that it lets go for two seconds.
- (void)keep {
    UIView *view = self.view, *holder = view.superview;
    if (!view || !holder || self.busy) return;
    if (CGRectEqualToRect(view.frame, holder.bounds) && CGAffineTransformIsIdentity(view.transform)) return;
    CFTimeInterval now = CACurrentMediaTime();
    if (now < self.restUntil) return;
    if (now - self.windowStart > 1) {
        self.windowStart = now;
        self.corrections = 0;
    }
    if (++self.corrections > 20) {
        self.restUntil = now + 2;
        return;
    }
    self.busy = YES;
    [UIView performWithoutAnimation:^{
        view.transform = CGAffineTransformIdentity;
        view.frame = holder.bounds;
    }];
    self.busy = NO;
}

- (void)observeValueForKeyPath:(NSString *)keyPath ofObject:(id)object change:(NSDictionary *)change context:(void *)context {
    [self keep];
}
@end

// The video's own drawing layer in a surface, an AVSampleBufferDisplayLayer if Spotify's renderer draws into one, which is
// what Picture in Picture can be run from.
static AVSampleBufferDisplayLayer *sampleLayerIn(CALayer *layer) {
    if ([layer isKindOfClass:AVSampleBufferDisplayLayer.class]) return (AVSampleBufferDisplayLayer *)layer;
    for (CALayer *sub in layer.sublayers) {
        AVSampleBufferDisplayLayer *found = sampleLayerIn(sub);
        if (found) return found;
    }
    return nil;
}

// A music video: the player plays it on a video surface (media.type and track_player video: the owner's log, 2026-11-09).
static BOOL isVideoTrack(SPTPlayerTrack *track) {
    NSDictionary *metadata = [track.metadata isKindOfClass:NSDictionary.class] ? track.metadata : nil;
    return [metadata[@"track_player"] isEqual:@"video"] || [metadata[@"media.type"] isEqual:@"video"];
}

// Whether the item playing is the AI DJ talking: its own item, with no length (the owner's DJ log, 2026-11-09:
// is_narration and suppress_progress true, provider narration/acknowledgment, "Up next" by "DJ X").
static BOOL isNarration(SPTPlayerTrack *track) {
    NSDictionary *metadata = [track.metadata isKindOfClass:NSDictionary.class] ? track.metadata : nil;
    return [metadata[@"is_narration"] isEqual:@"true"] || [metadata[@"suppress_progress"] isEqual:@"true"]
        || ([track respondsToSelector:@selector(provider)] && [track.provider hasPrefix:@"narration"]);
}



// The other of a song and its music video, from the track's metadata (the ⋯ menu's Switch to Video / Audio).
static NSString *otherVersionURI(SPTPlayerTrack *track) {
    NSString *videoURI = [track.metadata[@"video_association"] isKindOfClass:NSString.class] ? track.metadata[@"video_association"] : nil;
    NSString *audioURI = [track.metadata[@"audio_association"] isKindOfClass:NSString.class] ? track.metadata[@"audio_association"] : nil;
    return isVideoTrack(track) ? audioURI : videoURI;
}

static BOOL isTrack(id track) {
    return [track isKindOfClass:NSClassFromString(@"SPTPlayerTrack")];
}

BOOL SGRSystemIsTrack(id track) { return isTrack(track); }
BOOL SGRSystemIsNarration(id track) { return isTrack(track) && isNarration(track); }

UIImage *SGRSystemNotPlayingArt(void) {
    static UIImage *art;
    if (art) return art;
    CGFloat side = 600;
    UIImageSymbolConfiguration *config = [UIImageSymbolConfiguration configurationWithPointSize:side * 0.36 weight:UIImageSymbolWeightRegular];
    UIImage *note = [[UIImage systemImageNamed:@"music.note" withConfiguration:config] imageWithTintColor:[UIColor colorWithWhite:0.39 alpha:1]
                                                                                             renderingMode:UIImageRenderingModeAlwaysOriginal];
    UIGraphicsImageRenderer *renderer = [[UIGraphicsImageRenderer alloc] initWithSize:CGSizeMake(side, side)];
    art = [renderer imageWithActions:^(UIGraphicsImageRendererContext *context) {
        [[UIColor colorWithWhite:0.29 alpha:1] setFill];
        UIRectFill(CGRectMake(0, 0, side, side));
        CGSize size = note.size;
        [note drawInRect:CGRectMake((side - size.width) / 2, (side - size.height) / 2, size.width, size.height)];
    }];
    return art;
}

// A paused state's position would run on from when it was made; positionAsOfTimestamp holds still (HeadGestures.x).
static double positionOf(SPTPlayerState *state) {
    if (!state) return 0;
    double position = state.isPaused ? state.positionAsOfTimestamp : state.position;
    if (!isfinite(position) || position < 0) return 0;
    return state.duration > 0 ? MIN(position, state.duration) : position;
}

static NSInteger wholeSeconds(double seconds) {
    return isfinite(seconds) && seconds > 0 ? (NSInteger)floor(seconds) : 0;
}

static NSString *timeText(double seconds) {
    NSInteger whole = wholeSeconds(seconds);
    NSInteger hours = whole / 3600, minutes = whole / 60 % 60, rest = whole % 60;
    if (hours) return [NSString stringWithFormat:@"%ld:%02ld:%02ld", (long)hours, (long)minutes, (long)rest];
    return [NSString stringWithFormat:@"%ld:%02ld", (long)minutes, (long)rest];
}

// The pans above `view` turned off while a finger is on it, and back on after: the zoom's swipe close among them, which
// would otherwise take a drag along the bar that strays downwards. Screen edge pans are left alone.
static NSHashTable<UIGestureRecognizer *> *suspendPansAbove(UIView *view) {
    NSHashTable<UIGestureRecognizer *> *suspended = [NSHashTable weakObjectsHashTable];
    for (UIView *v = view.superview; v; v = v.superview) {
        for (UIGestureRecognizer *recognizer in v.gestureRecognizers) {
            if (![recognizer isKindOfClass:UIPanGestureRecognizer.class] || [recognizer isKindOfClass:UIScreenEdgePanGestureRecognizer.class] || !recognizer.enabled) continue;
            recognizer.enabled = NO;
            [suspended addObject:recognizer];
        }
    }
    return suspended;
}

static void restorePans(NSHashTable<UIGestureRecognizer *> *suspended) {
    for (UIGestureRecognizer *recognizer in suspended) recognizer.enabled = YES;
}

// What the redesigned player's header says over the cover (Spotify's own header row, kept there): "Playing recommended
// tracks" while autoplay plays (its owner's screenshot, 2026-11-01), told the way Shared/Player/SleepTimer.m tells it (the
// track's provider "autoplay", or its autoplay.is_autoplay metadata); else the name of what it plays from, the player
// context's context_description (contextMetadata, an NSDictionary property of the 9.1.90 player state's, asked for only
// where the state answers to it); else the album, from the track's metadata (as Shared/Player/SGLastTrack.m reads it).
static NSString *contextTitle(SPTPlayerState *state, SPTPlayerTrack *track) {
    if (!track) return nil;
    id provider = [track respondsToSelector:@selector(provider)] ? track.provider : nil;
    id autoplay = track.metadata[@"autoplay.is_autoplay"];
    if (([provider isKindOfClass:NSString.class] && [provider isEqualToString:@"autoplay"])
        || [[autoplay description] isEqualToString:@"true"]) return @"Playing recommended tracks";
    SEL metadata = NSSelectorFromString(@"contextMetadata");
    NSDictionary *context = [state respondsToSelector:metadata] ? ((id (*)(id, SEL))objc_msgSend)(state, metadata) : nil;
    id description = [context isKindOfClass:NSDictionary.class] ? context[@"context_description"] : nil;
    if ([description isKindOfClass:NSString.class] && [description length]) return description;
    id album = track.metadata[@"album_title"];
    return [album isKindOfClass:NSString.class] ? album : nil;
}

// The artist, or for an episode whose state names none, its show (the album_title the header falls back to).
static NSString *artistLine(SPTPlayerTrack *track) {
    if (track.artistName.length) return track.artistName;
    id show = track.metadata[@"album_title"];
    return [show isKindOfClass:NSString.class] ? show : nil;
}

#pragma mark - neighbours

NSNotificationName const SGRSystemPlayerPageDidCloseNotification = @"spotifyglass.redesign.systemPlayerPageDidClose";

id SGRPreviousTrack(SPTPlayerState *state) {
    id reverse = [state respondsToSelector:@selector(reverse)] ? state.reverse : nil;
    id track = [reverse isKindOfClass:NSArray.class] ? [reverse lastObject] : nil;
    return isTrack(track) ? track : nil;
}

NSInteger SGRTrackMoved(SPTPlayerState *state, NSString *from) {
    if (!from) return 0;
    BOOL (^holds)(id) = ^BOOL(id list) {
        for (id track in [list isKindOfClass:NSArray.class] ? list : @[]) {
            if (isTrack(track) && [SGURIString([(SPTPlayerTrack *)track URI]) isEqualToString:from]) return YES;
        }
        return NO;
    };
    if (holds(state.reverse)) return 1;
    if (holds(state.future)) return -1;
    return 0;
}

#pragma mark - the progress


// How close to either end the bar is at it, and how far past a tenth it has to be to have passed it.
static const CGFloat kScrubEdge = 0.005, kScrubHysteresis = 0.004;

@implementation SGRSystemScrubber {
    UIView *_track, *_fill;
    CGFloat _startValue, _startX;
    NSInteger _tenth;   // the tenth of the song the bar was last felt in
    BOOL _atEdge;
    NSHashTable<UIGestureRecognizer *> *_suspended;
}

- (instancetype)initWithFrame:(CGRect)frame {
    if (!(self = [super initWithFrame:frame])) return nil;
    _track = [UIView new];
    _track.clipsToBounds = YES;
    _track.userInteractionEnabled = NO;
    _track.layer.cornerCurve = kCACornerCurveContinuous;
    _track.backgroundColor = [UIColor colorWithWhite:1 alpha:kEmpty];
    _fill = [UIView new];
    _fill.userInteractionEnabled = NO;
    [_track addSubview:_fill];
    [self addSubview:_track];
    self.isAccessibilityElement = YES;
    self.accessibilityLabel = @"Track position";
    self.accessibilityTraits = UIAccessibilityTraitAdjustable;
    [self syncStyle];
    return self;
}

- (void)setValue:(CGFloat)value {
    _value = MIN(1, MAX(0, isfinite(value) ? value : 0));
    [self syncFill];
}

- (void)syncTrack {
    CGFloat height = _held ? kTrackHeld : kTrackRest, inset = _held ? 0 : kScrubGrowth;
    _track.frame = CGRectMake(inset, round(CGRectGetMidY(self.bounds) - height / 2), MAX(0, self.bounds.size.width - 2 * inset), height);
    _track.layer.cornerRadius = height / 2;
    self.leadingLabel.transform = CGAffineTransformMakeTranslation(inset, 0);
    self.trailingLabel.transform = CGAffineTransformMakeTranslation(-inset, 0);
    [self syncFill];
}

- (void)syncFill {
    CGSize size = _track.bounds.size;
    _fill.frame = CGRectMake(0, 0, size.width * _value, size.height);
}

- (void)syncStyle {
    _fill.backgroundColor = [UIColor colorWithWhite:1 alpha:_held ? kFillHeld : kFillRest];
}

- (void)layoutSubviews {
    [super layoutSubviews];
    [self syncTrack];
}

- (void)setHeld:(BOOL)held {
    if (_held == held) return;
    _held = held;
    // The pans above go off only once the finger drags (continueTrackingWithTouch:), as the volume row's do, and come
    // back on with the let go.
    if (!held) {
        [self letGoOfPans];
    }
    void (^apply)(void) = ^{
        [self syncTrack];
        [self syncStyle];
    };
    UIViewAnimationOptions options = UIViewAnimationOptionBeginFromCurrentState | UIViewAnimationOptionAllowUserInteraction;
    if (@available(iOS 17.0, *)) [UIView animateWithSpringDuration:kScrubSpring bounce:kScrubBounce initialSpringVelocity:0 delay:0 options:options animations:apply completion:nil];
    else [UIView animateWithDuration:kScrubSpring delay:0 usingSpringWithDamping:1 - kScrubBounce initialSpringVelocity:0 options:options animations:apply completion:nil];
}

// Vibrations > Controls (Shared/Haptics): a tap as the finger takes the bar, a tick at every tenth of the song it
// passes, a firmer one at either end, a soft one as it lets go, as Spotify's scrubber had them (ControlHaptics.x).
- (BOOL)beginTrackingWithTouch:(UITouch *)touch withEvent:(UIEvent *)event {
    _startX = [touch locationInView:self].x;
    _startValue = _value;
    _tenth = (NSInteger)floor(_value * 10);
    _atEdge = _value <= kScrubEdge || _value >= 1 - kScrubEdge;
    SGPlayFeedback(SGFeedbackGrab);
    SGPrepareFeedback(SGFeedbackDetent);
    [self setHeld:YES];
    return YES;
}

- (void)feelValue {
    BOOL edge = _value <= kScrubEdge || _value >= 1 - kScrubEdge;
    if (edge != _atEdge) {
        _atEdge = edge;
        if (edge) SGPlayFeedback(SGFeedbackEdge);
    }
    // A tenth counts once the bar is a little past it, so a finger resting on one ticks once.
    NSInteger tenth = (NSInteger)floor(_value * 10);
    if (tenth != _tenth && fabs(_value * 10 - MAX(tenth, _tenth)) > kScrubHysteresis * 10) {
        _tenth = tenth;
        if (!edge) SGPlayFeedback(SGFeedbackDetent);
    }
}

- (BOOL)continueTrackingWithTouch:(UITouch *)touch withEvent:(UIEvent *)event {
    if (!_suspended && fabs([touch locationInView:self].x - _startX) > kScrubDragStart) {
        _suspended = suspendPansAbove(self);
        [self performSelector:@selector(checkSuspended) withObject:nil afterDelay:1];
    }
    self.value = _startValue + ([touch locationInView:self].x - _startX) / MAX(1, self.bounds.size.width);
    [self feelValue];
    if (self.onMove) self.onMove(_value);
    return YES;
}

- (void)endTrackingWithTouch:(UITouch *)touch withEvent:(UIEvent *)event {
    SGPlayFeedback(SGFeedbackRelease);
    [self setHeld:NO];
    if (self.onRelease) self.onRelease(_value);
}

- (void)cancelTrackingWithEvent:(UIEvent *)event {
    // Cancelled (a call, a lock) is no seek: the next tick puts the bar back where the song is.
    [self setHeld:NO];
}

- (void)didMoveToWindow {
    [super didMoveToWindow];
    if (!self.window) [self setHeld:NO];
}

- (void)dealloc {
    restorePans(_suspended);
}

- (void)letGoOfPans {
    [NSObject cancelPreviousPerformRequestsWithTarget:self selector:@selector(checkSuspended) object:nil];
    restorePans(_suspended);
    _suspended = nil;
}

// A safety, as the volume row's: the pans above are never left off once no finger tracks the bar.
- (void)checkSuspended {
    if (!_suspended) return;
    if (self.isTracking && self.window) {
        [self performSelector:@selector(checkSuspended) withObject:nil afterDelay:1];
        return;
    }
    [self letGoOfPans];
}

- (void)accessibilityIncrement {
    self.value = _value + 0.05;
    if (self.onRelease) self.onRelease(_value);
}

- (void)accessibilityDecrement {
    self.value = _value - 0.05;
    if (self.onRelease) self.onRelease(_value);
}
@end

#pragma mark - the controls' press

// The controls' press. Shuffle and repeat: a soft white circle comes up behind the button at the touch and stays a moment
// after the release before it fades, the glyph dimmed and a little smaller while held. Previous, play and pause, and next
// press as f728743/AppleMusicStylePlayer's PlayerButton.swift does (MIT, Copyright (c) 2025 Alexey Vorobyov; its owner,
// 2026-11-01): the glyph at 0.9 and the whole button at 0.85 while held, on a circle of its tint that shows at the touch
// and goes 0.25 s after the release (the Music app's timing, below), on SwiftUI's default spring (0.5 s, no bounce, kTransportSpring); the glyph is
// not dimmed. Previous and next step their double arrow as that project's ForwardLabel.swift does (SGRForwardLabel,
// below). Under Reduce Motion only the circle fades: nothing scales or steps. The tap's command runs at once; none of this
// delays it.
static const CGFloat kHaloWhite = 0.12, kHaloShare = 0.9;
static const NSTimeInterval kHaloIn = 0.1, kHaloHold = 0.15, kHaloOut = 0.3;
// PlayerButton.swift's scales: the label's and the button's while pressed. The circle's tint, its fade in and out and its
// hold after the release are the Music app's, measured frame by frame from its owner's 60 fps recording of it (2026-11-01):
// the circle lifts the background as white 0.784 at 0.15 does, comes in over 0.1 s, stays 0.25 s after the finger lifts,
// and goes over 0.12 s.
static const CGFloat kTransportLabelScale = 0.9, kTransportButtonScale = 0.85, kTransportTintWhite = 0.784, kTransportTintAlpha = 0.15;
static const NSTimeInterval kTransportCircleHold = 0.25, kTransportCircleIn = 0.1, kTransportCircleOut = 0.12;
// SwiftUI's default animation (iOS 17: a smooth spring of about half a second, no bounce).
static const NSTimeInterval kTransportSpring = 0.5;

// The skip's step, the Music app's, measured frame by frame from its owner's 60 fps recording of it (2026-11-02), from the
// finger's lift: the arrows move over the first kForwardMoveShare of kForwardDuration and the new back one brightens over
// the rest. No more often than once a length, the latest tap kept.
// Its length, its ease (the power the slide's slowing takes), how soon the front glyph is away (a multiple of the move)
// and how far it drifts (a share of the double arrow): its owner's, tuned on the phone from the Music app's (2026-11-02,
// the length 2026-11-04).
static const NSTimeInterval kForwardDuration = 0.6;
static const CGFloat kForwardEase = 2.2, kForwardAway = 6.02, kForwardDrift = 0.23;
static const CGFloat kForwardMoveShare = 0.52, kForwardBackStart = 0.15, kForwardBackGray = 0.5;
// The gaps from the bottom row up to the times, times the redesigned player's (kVolumeAboveRow and the rest), fixed by the
// phone's size (its owner, 2026-11-06): 1.3 on a Plus or Pro Max (926 pt tall and up), 1.1 on a mini or smaller (812 pt
// and less), 1.2 between. No longer set from the ⋯ menu.
static CGFloat controlsSpacing(void) {
    CGSize screen = UIScreen.mainScreen.bounds.size;
    CGFloat tall = MAX(screen.width, screen.height);
    return tall >= 926 ? 1.3 : tall <= 812 ? 1.1 : 1.2;
}

#pragma mark - the skip's arrow

// The Music app's skip, as its frames show it (2026-11-02): the double arrow's front glyph greys and shrinks away, drifting
// on by about half its width; the back one slides at full size into the front's place, slowing to it; and a new back glyph
// grows out of a dot at the back place's flat side, gray, then brightens to white once the arrows have stopped. At the end
// it is the double arrow again. Laid out by hand: three copies of one whole triangle taken from the button's own double
// arrow picture, scaled about their own middles, in a box wider than the arrow so the front one can drift. Mirrored for
// previous. Taken from the button's own picture, so the label at rest is the glyph and the swap back at the end does not
// jump. (It was f728743/AppleMusicStylePlayer's ForwardLabel, which squeezes the glyphs' widths instead; it read as another
// motion, too quick or too slow at any length.)
static const CGFloat kForwardBoxShare = 1.5;

@interface SGRForwardLabel : UIView
@property (nonatomic) CGFloat size;
@property (nonatomic) CGFloat progress;
// `arrow` is the double arrow's picture, drawn `size` across (the glyph's bounds).
- (instancetype)initWithArrow:(UIImage *)arrow size:(CGSize)size tint:(UIColor *)tint;
// The progress from 0 to 1 over `duration`, linearly, run by Core Animation: the steps are worked out up front and played
// by the render server, so a busy main thread (Spotify's track change) can't stall them as it did a display link's (its
// owner, 2026-11-04). The label is left at 1, which is the glyph; `done` comes after.
- (void)runOver:(NSTimeInterval)duration done:(void (^)(void))done;
@end

@implementation SGRForwardLabel {
    UIImageView *_back, *_middle, *_front;
    CGFloat _step, _triangle;   // how far the front triangle sits from the back one, and one triangle's width
    CGFloat _arrowLeft;         // the back triangle's flat side in the arrow's picture
}

// Where each triangle starts in the double arrow drawn `width` points across in `drawn`, read off its pixels on a row near
// the top, where the two triangles are apart: the back one's flat side is the first coverage (the picture has empty
// room before it, which put the back triangle a few points left of the glyph's: its owner's recording, 2026-11-02), and
// the front one's the first coverage after a gap (forward.fill's triangles overlap at the middle, so a cut down the
// middle took the back one's tip off and gave the front one a nub). The picture's edge and half the width if not found.
static CGFloat frontTriangleStart(UIImage *arrow, CGRect drawn, CGFloat width, CGFloat *backStart) {
    *backStart = CGRectGetMinX(drawn);
    CGFloat scale = 4;
    size_t pixelsWide = (size_t)ceil(width * scale), pixelsHigh = (size_t)ceil(CGRectGetMaxY(drawn) * scale);
    if (!pixelsWide || !pixelsHigh) return width / 2;
    NSMutableData *data = [NSMutableData dataWithLength:pixelsWide * pixelsHigh];
    CGContextRef context = CGBitmapContextCreate(data.mutableBytes, pixelsWide, pixelsHigh, 8, pixelsWide, NULL, (CGBitmapInfo)kCGImageAlphaOnly);
    if (!context) return width / 2;
    UIGraphicsPushContext(context);
    CGContextTranslateCTM(context, 0, pixelsHigh);
    CGContextScaleCTM(context, scale, -scale);
    [arrow drawInRect:drawn];
    UIGraphicsPopContext();
    CGContextRelease(context);
    const uint8_t *alpha = data.bytes;
    size_t row = (size_t)((CGRectGetMinY(drawn) + drawn.size.height * 0.2) * scale);
    BOOL seenCover = NO, seenGap = NO;
    CGFloat first = CGRectGetMinX(drawn);
    for (size_t x = 0; x < pixelsWide; x++) {
        BOOL covered = alpha[row * pixelsWide + x] > 127;
        if (covered && seenGap) {
            *backStart = first;
            return x / scale;
        }
        if (covered && !seenCover) first = x / scale;
        if (covered) seenCover = YES;
        else if (seenCover) seenGap = YES;
    }
    return width / 2;
}

- (instancetype)initWithArrow:(UIImage *)arrow size:(CGSize)arrowSize tint:(UIColor *)tint {
    CGFloat size = arrowSize.width, height = arrowSize.height;
    if (!(self = [super initWithFrame:CGRectMake(0, 0, size * kForwardBoxShare, height)])) return nil;
    _size = size;
    self.userInteractionEnabled = NO;
    // The arrow drawn as the glyph draws it (fitted, in the middle). Its front triangle, whole, is every triangle of the
    // step: the back one lies inside it where they overlap, so the front's picture is a clean single triangle, and two of
    // them `_step` apart are the glyph again.
    // Measured and cut once per picture and size, the next skips reusing it.
    static NSMapTable<UIImage *, NSArray *> *cut;
    if (!cut) cut = [NSMapTable weakToStrongObjectsMapTable];
    NSArray *known = [cut objectForKey:arrow];
    if (!known || !CGSizeEqualToSize([known[0] CGSizeValue], arrowSize)) {
        CGSize image = arrow.size;
        CGFloat fit = image.width > 0 && image.height > 0 ? MIN(size / image.width, height / image.height) : 1;
        CGRect drawn = CGRectMake((size - image.width * fit) / 2, (height - image.height * fit) / 2, image.width * fit, image.height * fit);
        CGFloat backStart;
        CGFloat start = frontTriangleStart(arrow, drawn, size, &backStart);
        CGFloat width = CGRectGetMaxX(drawn) - start;
        UIGraphicsImageRenderer *renderer = [[UIGraphicsImageRenderer alloc] initWithSize:CGSizeMake(width, height)
                                                                                   format:[UIGraphicsImageRendererFormat preferredFormat]];
        UIImage *picture = [[renderer imageWithActions:^(UIGraphicsImageRendererContext *context) {
            [arrow drawInRect:CGRectOffset(drawn, -start, 0)];
        }] imageWithRenderingMode:UIImageRenderingModeAlwaysTemplate];
        known = @[[NSValue valueWithCGSize:arrowSize], picture, @(start - backStart), @(width), @(backStart)];
        [cut setObject:known forKey:arrow];
    }
    UIImage *triangle = known[1];
    _step = [known[2] doubleValue];
    _triangle = [known[3] doubleValue];
    _arrowLeft = [known[4] doubleValue];
    for (int i = 0; i < 3; i++) {
        UIImageView *view = [[UIImageView alloc] initWithImage:triangle];
        view.tintColor = tint;
        view.bounds = CGRectMake(0, 0, _triangle, height);
        [self addSubview:view];
        if (i == 0) _back = view;
        else if (i == 1) _middle = view;
        else _front = view;
    }
    self.progress = 0;
    return self;
}

- (void)setProgress:(CGFloat)progress {
    _progress = MIN(1, MAX(0, progress));
    CGFloat p = _progress, size = _size, triangle = _triangle;
    // The move, then the brightening.
    CGFloat move = MIN(1, p / kForwardMoveShare), brighten = MAX(0, (p - kForwardMoveShare) / (1 - kForwardMoveShare));
    CGFloat slide = 1 - pow(1 - move, kForwardEase);
    CGFloat left = (self.bounds.size.width - size) / 2 + _arrowLeft, mid = self.bounds.size.height / 2;
    CGFloat backX = left + triangle / 2, frontX = backX + _step;
    // The front glyph: away early in the move, drifting on as it goes.
    CGFloat away = MIN(1, move * kForwardAway), awayEased = 1 - pow(1 - away, 2);
    _front.center = CGPointMake(frontX + kForwardDrift * size * awayEased, mid);
    _front.transform = CGAffineTransformMakeScale(MAX(0.001, 1 - away), MAX(0.001, 1 - away));
    _front.alpha = (1 - away) * (1 - 0.4 * away);
    // The back glyph to the front's place, whole and white.
    _middle.center = CGPointMake(backX + (frontX - backX) * slide, mid);
    _middle.transform = CGAffineTransformIdentity;
    // The new back glyph out of a dot at its flat side, gray while it grows, white after; drawn under the middle one,
    // which covers where they overlap, as the glyph's front triangle does.
    CGFloat grow = MIN(1, MAX(0, (move - kForwardBackStart) / (1 - kForwardBackStart)));
    CGFloat scale = 1 - pow(1 - grow, 1.5);
    _back.center = CGPointMake(backX - triangle / 2 * (1 - scale), mid);
    _back.transform = CGAffineTransformMakeScale(MAX(0.001, scale), MAX(0.001, scale));
    CGFloat lit = brighten * brighten * (3 - 2 * brighten);
    _back.alpha = kForwardBackGray * MIN(1, grow * 3) + (1 - kForwardBackGray) * lit;
}

- (void)runOver:(NSTimeInterval)duration done:(void (^)(void))done {
    // One step a frame at 120 Hz, played straight between them.
    NSUInteger steps = MAX(2, (NSUInteger)ceil(duration * 120));
    NSArray<UIImageView *> *views = @[_back, _middle, _front];
    NSMutableArray<NSMutableArray *> *positions = [NSMutableArray array], *transforms = [NSMutableArray array], *opacities = [NSMutableArray array];
    for (NSUInteger i = 0; i < views.count; i++) {
        [positions addObject:[NSMutableArray array]];
        [transforms addObject:[NSMutableArray array]];
        [opacities addObject:[NSMutableArray array]];
    }
    for (NSUInteger step = 0; step <= steps; step++) {
        self.progress = (CGFloat)step / steps;
        for (NSUInteger i = 0; i < views.count; i++) {
            CALayer *layer = views[i].layer;
            [positions[i] addObject:[NSValue valueWithCGPoint:layer.position]];
            [transforms[i] addObject:[NSValue valueWithCATransform3D:layer.transform]];
            [opacities[i] addObject:@(layer.opacity)];
        }
    }
    [CATransaction begin];
    [CATransaction setDisableActions:YES];
    [CATransaction setCompletionBlock:done];
    for (NSUInteger i = 0; i < views.count; i++) {
        NSArray *values[] = {positions[i], transforms[i], opacities[i]};
        NSString *paths[] = {@"position", @"transform", @"opacity"};
        for (int k = 0; k < 3; k++) {
            CAKeyframeAnimation *animation = [CAKeyframeAnimation animationWithKeyPath:paths[k]];
            animation.values = values[k];
            animation.duration = duration;
            animation.calculationMode = kCAAnimationLinear;
            [views[i].layer addAnimation:animation forKey:[@"step." stringByAppendingString:paths[k]]];
        }
    }
    [CATransaction commit];
}
@end


// The play and pause turn (turnToSymbol:): the scale the symbols leave to and come from, the old one's way out, the new
// one's spring in (SwiftUI's replace, about a third of a second, a little bounce) and how far into the way out it starts.
static const CGFloat kTurnScale = 0.2, kTurnBounce = 0.15;
static const NSTimeInterval kTurnOut = 0.14, kTurnIn = 0.32, kTurnDelay = 0.07;

// The fill's padding round the glyph, its corners, and the knocked out glyph's ink (dark enough on a pale cover color).
static const CGFloat kLitPadding = 7, kLitEnterScale = 0.8;

@implementation SGRSystemControlButton {
    UIView *_halo, *_fill;
    NSUInteger _pressSerial;
    NSString *_turningTo;      // the symbol a running turn goes to
    NSUInteger _turnSerial;
    UIImageView *_turnOld, *_turnNew;
    BOOL _lit, _litSet;
    NSString *_cutSymbol;      // the symbol cut out of the lit disc
    UIImage *_flippedFrom, *_flipped;   // previous's picture and its mirror, for the step
    // The arrow's step: the label while it runs, its clock, when the last began and whether a tap waits for the window.
    SGRForwardLabel *_forward;
    CFTimeInterval _forwardLastBegan;
    NSInteger _forwardDirection;
    BOOL _forwardWaiting;
}

- (void)setTransport:(BOOL)transport {
    _transport = transport;
    _halo.backgroundColor = transport ? [UIColor colorWithWhite:kTransportTintWhite alpha:kTransportTintAlpha] : [UIColor colorWithWhite:1 alpha:kHaloWhite];
}

- (instancetype)initWithFrame:(CGRect)frame {
    if (!(self = [super initWithFrame:frame])) return nil;
    _heldScale = 0.9;
    _heldAlpha = 0.5;
    _halo = [UIView new];
    _halo.userInteractionEnabled = NO;
    _halo.backgroundColor = [UIColor colorWithWhite:1 alpha:kHaloWhite];
    _halo.alpha = 0;
    [self insertSubview:_halo atIndex:0];
    _fill = [UIView new];
    _fill.userInteractionEnabled = NO;
    _fill.alpha = 0;
    _fill.layer.contentsGravity = kCAGravityCenter;
    _fill.layer.contentsScale = UIScreen.mainScreen.scale;
    [self insertSubview:_fill aboveSubview:_halo];
    return self;
}

- (void)setLit:(BOOL)lit plain:(UIColor *)plain animated:(BOOL)animated {
    SGRGlyphView *glyph = self.glyph;
    NSString *symbol = glyph.symbol;
    if (lit && ![symbol isEqualToString:_cutSymbol]) {
        _cutSymbol = symbol;
        _fill.layer.contents = (__bridge id)cutDiscImage(symbol, glyph.preferredSymbolConfiguration, kQueueBubble).CGImage;
    }
    UIColor *ink = lit ? UIColor.clearColor : plain;
    BOOL changed = !_litSet || lit != _lit;
    _lit = lit;
    _litSet = YES;
    if (!changed) {
        if (![glyph.tintColor isEqual:ink]) glyph.tintColor = ink;
        return;
    }
    UIView *fill = _fill;
    BOOL move = animated && self.window && !SGRReduceMotion();
    if (lit && move) fill.transform = CGAffineTransformMakeScale(kLitEnterScale, kLitEnterScale);
    void (^apply)(void) = ^{
        fill.alpha = lit ? 1 : 0;
        fill.transform = lit || !move ? CGAffineTransformIdentity : CGAffineTransformMakeScale(kLitEnterScale, kLitEnterScale);
    };
    if (animated && self.window) {
        SGRAnimate(SGRMotionPress, apply, nil);
        [UIView transitionWithView:glyph duration:SGRCrossfade options:UIViewAnimationOptionTransitionCrossDissolve | UIViewAnimationOptionAllowUserInteraction
                        animations:^{ glyph.tintColor = ink; } completion:nil];
    } else {
        apply();
        glyph.tintColor = ink;
    }
}

- (void)layoutSubviews {
    [super layoutSubviews];
    // The transport buttons' circle fills the button, as PlayerButton.swift's ellipse fills its frame.
    CGFloat side = round(MAX(40, MIN(self.bounds.size.width, self.bounds.size.height) * (_transport ? 1 : kHaloShare)));
    _halo.bounds = CGRectMake(0, 0, side, side);
    _halo.center = CGPointMake(CGRectGetMidX(self.bounds), CGRectGetMidY(self.bounds));
    _halo.layer.cornerRadius = side / 2;
    if (self.subviews.firstObject != _halo) [self sendSubviewToBack:_halo];
    // The fill's size is the glyph's at rest (its transform left out), padded; it presses with the glyph's own transform.
    CGSize glyphSize = self.glyph.bounds.size;
    // Round, the lyrics' and the queue's bubble's size (its owner, 2026-11-02), never tighter than the glyph allows.
    CGFloat fillSide = MAX(kQueueBubble, ceil(MAX(glyphSize.width, glyphSize.height) + 2 * kLitPadding));
    _fill.bounds = CGRectMake(0, 0, fillSide, fillSide);
    _fill.layer.cornerRadius = fillSide / 2;
    _fill.center = _halo.center;
    if ([self.subviews indexOfObject:_fill] != 1) [self insertSubview:_fill aboveSubview:_halo];
}

// Held, the circle comes at once; let go, it stays kHaloHold and fades, unless a new touch has come since.
- (void)setHighlighted:(BOOL)highlighted {
    BOOL was = self.highlighted;
    [super setHighlighted:highlighted];
    if (was == highlighted) return;
    UIView *halo = _halo, *glyph = self.glyph;
    NSUInteger serial = ++_pressSerial;
    if (_transport) {
        [self transportPressed:highlighted serial:serial];
        return;
    }
    if (highlighted) {
        [UIView animateWithDuration:kHaloIn delay:0 options:UIViewAnimationOptionBeginFromCurrentState | UIViewAnimationOptionAllowUserInteraction
                         animations:^{ halo.alpha = 1; } completion:nil];
    } else {
        __weak typeof(self) weakSelf = self;
        dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(kHaloHold * NSEC_PER_SEC)), dispatch_get_main_queue(), ^{
            typeof(self) me = weakSelf;
            if (!me || me->_pressSerial != serial) return;
            [UIView animateWithDuration:kHaloOut delay:0 options:UIViewAnimationOptionBeginFromCurrentState | UIViewAnimationOptionAllowUserInteraction
                             animations:^{ halo.alpha = 0; } completion:nil];
        });
    }
    // The Kit's press (SGRGlyphPress, run by super) with this control's own depth, on the same spring.
    CGFloat scale = highlighted && !SGRReduceMotion() ? _heldScale : 1, alpha = highlighted ? _heldAlpha : 1;
    UIView *fill = _fill;
    BOOL lit = _lit;
    SGRAnimate(SGRMotionPress, ^{
        glyph.alpha = alpha;
        glyph.transform = CGAffineTransformMakeScale(scale, scale);
        if (lit) fill.transform = CGAffineTransformMakeScale(scale, scale);
    }, nil);
}

// PlayerButton.swift's press: both scales with the touch and back with the release on SwiftUI's default animation, a smooth
// spring of kTransportSpring with no bounce (its owner, 2026-11-01: the Kit's quicker spring felt stiff); the circle fades
// in with the touch and out kTransportCircleHold after the release. The Kit's own press (super's SGRGlyphPress) is put
// back to no dimming at once.
- (void)transportPressed:(BOOL)pressed serial:(NSUInteger)serial {
    UIView *halo = _halo, *glyph = self.glyph;
    BOOL move = !SGRReduceMotion();
    UIViewAnimationOptions options = UIViewAnimationOptionBeginFromCurrentState | UIViewAnimationOptionAllowUserInteraction;
    [glyph.layer removeAllAnimations];
    // Unseen while a turn of its symbol runs (turnToSymbol:).
    glyph.alpha = _turningTo ? 0 : 1;
    if (move) {
        void (^scale)(void) = ^{
            glyph.transform = pressed ? CGAffineTransformMakeScale(kTransportLabelScale, kTransportLabelScale) : CGAffineTransformIdentity;
            // A running skip step stands in for the glyph, mirrored for previous.
            self->_forward.transform = CGAffineTransformScale(glyph.transform, self->_forwardDirection < 0 ? -1 : 1, 1);
            self.transform = pressed ? CGAffineTransformMakeScale(kTransportButtonScale, kTransportButtonScale) : CGAffineTransformIdentity;
        };
        if (@available(iOS 17.0, *)) {
            [UIView animateWithSpringDuration:kTransportSpring bounce:0 initialSpringVelocity:0 delay:0 options:options animations:scale completion:nil];
        } else {
            [UIView animateWithDuration:kTransportSpring delay:0 usingSpringWithDamping:1 initialSpringVelocity:0 options:options animations:scale completion:nil];
        }
    }
    if (pressed) {
        [UIView animateWithDuration:kTransportCircleIn delay:0 options:options | UIViewAnimationOptionCurveEaseOut
                         animations:^{ halo.alpha = 1; } completion:nil];
        return;
    }
    __weak typeof(self) weakSelf = self;
    dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(kTransportCircleHold * NSEC_PER_SEC)), dispatch_get_main_queue(), ^{
        typeof(self) me = weakSelf;
        if (!me || me->_pressSerial != serial) return;
        [UIView animateWithDuration:kTransportCircleOut delay:0 options:options | UIViewAnimationOptionCurveEaseInOut
                         animations:^{ halo.alpha = 0; } completion:nil];
    });
}

// ForwardLabel.swift's AnimatedForwardLabel: the label stands in for the glyph while its progress runs from 0 to 1 over
// kForwardDuration, linearly (the curves are the label's own), and the glyph comes back at the end, where the label
// looks as it did at 0. Taps closer together than kForwardDuration are thrown to the end of it, the latest kept, as the
// project throttles them.
// A plain picture of `symbol` at the glyph's size, in its ink, about the button's middle.
- (UIImageView *)pictureOfSymbol:(NSString *)symbol {
    SGRGlyphView *glyph = self.glyph;
    UIImage *image = [UIImage systemImageNamed:symbol withConfiguration:glyph.preferredSymbolConfiguration];
    if (glyph.withoutBaseline) image = image.imageWithoutBaseline;
    UIImageView *picture = [[UIImageView alloc] initWithImage:[image imageWithRenderingMode:UIImageRenderingModeAlwaysTemplate]];
    picture.tintColor = glyph.tintColor;
    picture.userInteractionEnabled = NO;
    picture.bounds = (CGRect){CGPointZero, image.size};
    picture.center = CGPointMake(CGRectGetMidX(self.bounds), CGRectGetMidY(self.bounds));
    [self insertSubview:picture aboveSubview:glyph];
    return picture;
}

- (void)turnToSymbol:(NSString *)symbol animated:(BOOL)animated {
    SGRGlyphView *glyph = self.glyph;
    NSString *target = _turningTo ?: glyph.symbol;
    if (!symbol || [symbol isEqualToString:target]) return;
    NSString *from = target;
    [_turnOld removeFromSuperview];
    [_turnNew removeFromSuperview];
    _turnOld = _turnNew = nil;
    if (!animated || SGRReduceMotion() || !self.window) {
        _turningTo = nil;
        glyph.alpha = 1;
        [self restGlyphOn:symbol];
        return;
    }
    NSUInteger serial = ++_turnSerial;
    _turningTo = [symbol copy];
    UIImageView *old = [self pictureOfSymbol:from], *fresh = [self pictureOfSymbol:symbol];
    _turnOld = old;
    _turnNew = fresh;
    glyph.alpha = 0;
    fresh.transform = CGAffineTransformMakeScale(kTurnScale, kTurnScale);
    fresh.alpha = 0;
    UIViewAnimationOptions options = UIViewAnimationOptionBeginFromCurrentState | UIViewAnimationOptionAllowUserInteraction;
    [UIView animateWithDuration:kTurnOut delay:0 options:options | UIViewAnimationOptionCurveEaseIn animations:^{
        old.transform = CGAffineTransformMakeScale(kTurnScale, kTurnScale);
        old.alpha = 0;
    } completion:nil];
    void (^grow)(void) = ^{
        fresh.transform = CGAffineTransformIdentity;
        fresh.alpha = 1;
    };
    __weak typeof(self) weakSelf = self;
    void (^done)(BOOL) = ^(BOOL finished) {
        typeof(self) me = weakSelf;
        if (!me || me->_turnSerial != serial) return;
        [me restGlyphOn:symbol];
        me->_turningTo = nil;
        me.glyph.alpha = 1;
        [old removeFromSuperview];
        [fresh removeFromSuperview];
        me->_turnOld = me->_turnNew = nil;
    };
    if (@available(iOS 17.0, *)) [UIView animateWithSpringDuration:kTurnIn bounce:kTurnBounce initialSpringVelocity:0 delay:kTurnDelay options:options animations:grow completion:done];
    else [UIView animateWithDuration:kTurnIn delay:kTurnDelay usingSpringWithDamping:1 - kTurnBounce initialSpringVelocity:0 options:options animations:grow completion:done];
}

// The glyph given its symbol with any press scale set aside, so it is measured at rest (a symbol set while it was
// scaled drew it huge once).
- (void)restGlyphOn:(NSString *)symbol {
    SGRGlyphView *glyph = self.glyph;
    CGAffineTransform scale = glyph.transform;
    [UIView performWithoutAnimation:^{
        glyph.transform = CGAffineTransformIdentity;
        [glyph setSymbol:symbol animated:NO];
        [self setNeedsLayout];
        [self layoutIfNeeded];
        glyph.transform = scale;
    }];
}

- (void)stepArrow:(NSInteger)direction {
    if (SGRReduceMotion() || !self.window || !self.glyph.image) return;
    _forwardDirection = direction;
    CFTimeInterval now = CACurrentMediaTime(), next = _forwardLastBegan + kForwardDuration;
    if (_forward || now < next) {
        if (_forwardWaiting) return;
        _forwardWaiting = YES;
        __weak typeof(self) weakSelf = self;
        dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(MAX(0.01, next - now) * NSEC_PER_SEC)), dispatch_get_main_queue(), ^{
            typeof(self) me = weakSelf;
            if (!me) return;
            me->_forwardWaiting = NO;
            [me beginForward];
        });
        return;
    }
    [self beginForward];
}

- (void)beginForward {
    if (_forward || !self.window) return;
    SGRGlyphView *glyph = self.glyph;
    // The label is the glyph's picture at the glyph's size: at rest its two halves are the double arrow.
    CGSize size = glyph.bounds.size;
    if (size.width <= 0 || size.height <= 0) return;
    // Drawn pointing forward and flipped for previous: previous's picture is mirrored first.
    // The mirrored picture kept, so its cut is reused (SGRForwardLabel).
    if (_forwardDirection < 0 && _flippedFrom != glyph.image) {
        _flippedFrom = glyph.image;
        _flipped = glyph.image.imageWithHorizontallyFlippedOrientation;
    }
    UIImage *arrow = _forwardDirection < 0 ? _flipped : glyph.image;
    _forward = [[SGRForwardLabel alloc] initWithArrow:arrow size:size tint:glyph.tintColor ?: SGRPrimary()];
    _forward.center = glyph.center;
    _forward.transform = CGAffineTransformScale(glyph.transform, _forwardDirection < 0 ? -1 : 1, 1);
    [self addSubview:_forward];
    glyph.hidden = YES;
    _forwardLastBegan = CACurrentMediaTime();
    SGRForwardLabel *label = _forward;
    __weak typeof(self) weakSelf = self;
    [label runOver:kForwardDuration done:^{
        typeof(self) me = weakSelf;
        if (me && me->_forward == label) [me endForward];
    }];
}

- (void)endForward {
    [_forward removeFromSuperview];
    _forward = nil;
    self.glyph.hidden = NO;
}

- (void)didMoveToWindow {
    [super didMoveToWindow];
    if (!self.window && _forward) [self endForward];
}
@end

#pragma mark - AirPlay and Connect

// Spotify's Connect sheet. The first way is Spotify's own link to its device picker (kConnectURI), sent only when the
// dispatcher's registry says a handler takes it (Shared/Navigation/Links.h's SGSpotifyURIRoute asks every handler as the
// dispatcher would, so a link nothing takes never ends in Spotify's "Couldn't open link"). The second is the redesigned
// player's footer's (PlayerFooter.x): the tap recognizer on Spotify's Connect holder is sent the tap a finger would have
// made, as Spotify opens its sheet from that recognizer rather than from its button's actions (the phone's log,
// 2026-10-30). The page has no Spotify footer, so that holder is the now playing bar's, which under the system tab bar
// is at alpha 0 and takes no touches (NowPlayingBar.x), and can be missing altogether: the bar tucks its Connect item
// away (hidden) when it goes to the tab bar's row, and has none while Spotify shows no device button. A hold on the
// AirPlay glyph did not open Connect on the phone (its owner, 2026-11-01), which is why the link comes first now and
// each way says in the log why it was or was not taken. `how` says which way was taken, or why none was.
static BOOL openSpotifyConnect(NSString **how) {
    NSURL *link = [NSURL URLWithString:kConnectURI];
    NSString *via = nil;
    SGLinkRoute route = SGSpotifyURIRoute(link, &via);
    if (route == SGLinkRouteOpens && SGOpenSpotifyURI(link)) {
        *how = [NSString stringWithFormat:@"%@ sent (taken by %@)", kConnectURI, via];
        return YES;
    }
    NSString *linkNote = route == SGLinkRouteNone ? @"no handler takes it" : route == SGLinkRouteUnknown ? @"the registry could not be asked" : @"the dispatcher is not up";
    UIView *bar = sgr_nowPlayingRoot;
    UIView *holder = bar ? SGRFindByIdentifier(bar, @"Components.ConnectButtonOutputSwitcher", &kConnectKey) : nil;
    if (!holder) {
        *how = [NSString stringWithFormat:@"nothing: %@ (%@), and the now playing bar %@", kConnectURI, linkNote,
                bar ? (bar.window ? @"has no Connect holder" : @"is out of the window") : @"is not known"];
        return NO;
    }
    BOOL tucked = NO;
    for (UIView *v = holder; v && v != bar; v = v.superview) tucked = tucked || v.hidden;
    for (UIGestureRecognizer *tap in holder.gestureRecognizers) {
        if (![tap isKindOfClass:UITapGestureRecognizer.class] || !tap.enabled) continue;
        NSArray *targets = nil;
        @try { targets = [tap valueForKey:@"targets"]; } @catch (NSException *e) {}
        BOOL sent = NO;
        for (id entry in targets) {
            Ivar targetIvar = class_getInstanceVariable(object_getClass(entry), "_target");
            Ivar actionIvar = class_getInstanceVariable(object_getClass(entry), "_action");
            if (!targetIvar || !actionIvar) continue;
            id target = object_getIvar(entry, targetIvar);
            SEL action = *(SEL *)((char *)(__bridge void *)entry + ivar_getOffset(actionIvar));
            if (!target || !action) continue;
            ((void (*)(id, SEL, id))objc_msgSend)(target, action, tap);
            sent = YES;
        }
        if (sent) {
            *how = [NSString stringWithFormat:@"the bar's Connect tap (%@, %@; the link: %@)", NSStringFromClass(holder.class), tucked ? @"tucked away" : @"in place", linkNote];
            return YES;
        }
    }
    // No recognizer to send to: fired as a tap would fire its control (SGRActivate), which for an Encore control with
    // no actions ends in an accessibility activation that may do nothing.
    SGRActivate(holder);
    *how = [NSString stringWithFormat:@"the bar's Connect holder fired, no tap recognizer on it (%@, %lu recognizers, %@; the link: %@)", NSStringFromClass(holder.class),
            (unsigned long)holder.gestureRecognizers.count, tucked ? @"tucked away" : @"in place", linkNote];
    return YES;
}

// A tap opens the system's AirPlay picker, the Music app's; a press held opens Spotify's Connect sheet with a haptic, as
// in the redesigned player's footer (its owner, 2026-10-30). The picker's own glyph is always the plain AirPlay one, so it
// is drawn clear and the glyph over it is the output's device, the footer's (PlayerFooter.x's SGRPlayerOutputSymbol:
// AirPods by model, a HomePod, a Mac, EarPods...), drawn again as the footer says the output changed, and pressed as the
// footer's is while a finger is on it (its owner, 2026-11-01).
@interface SGRSystemRouteButton : AVRoutePickerView
@property (nonatomic, copy) void (^onHold)(void);
- (void)setGlyphPointSize:(CGFloat)size;
- (void)setGlyphTint:(UIColor *)tint;
@end

@implementation SGRSystemRouteButton {
    SGRGlyphView *_glyph;
}

- (instancetype)initWithFrame:(CGRect)frame {
    if (!(self = [super initWithFrame:frame])) return nil;
    self.tintColor = UIColor.clearColor;
    self.activeTintColor = UIColor.clearColor;
    self.prioritizesVideoDevices = NO;
    self.accessibilityLabel = @"AirPlay";
    // The lyrics and queue glyphs' size and weight (SGRGlyphButton at 20pt), in the row's color: the Music app's device
    // glyph is not lit for another device, and neither is the footer's.
    _glyph = [[SGRGlyphView alloc] initWithSymbol:@"airplayaudio" pointSize:20 weight:UIImageSymbolWeightRegular];
    _glyph.userInteractionEnabled = NO;
    _glyph.isAccessibilityElement = NO;
    // The page's row: the lyrics and queue glyphs' see-through white (its owner, 2026-11-04). The mini player's is white.
    _glyph.tintColor = SGRSecondary();
    [self addSubview:_glyph];
    UILongPressGestureRecognizer *hold = [[UILongPressGestureRecognizer alloc] initWithTarget:self action:@selector(held:)];
    hold.minimumPressDuration = 0.4;
    [self addGestureRecognizer:hold];
    SGRPlayerPressGlyphOnTouch(self);
    // Posted on the main queue (Player.h).
    [NSNotificationCenter.defaultCenter addObserver:self selector:@selector(syncOutput) name:SGRPlayerOutputDidChangeNotification object:nil];
    [self syncOutput];
    return self;
}

- (void)setGlyphTint:(UIColor *)tint {
    _glyph.tintColor = tint;
}

- (void)setGlyphPointSize:(CGFloat)size {
    _glyph.preferredSymbolConfiguration = [UIImageSymbolConfiguration configurationWithPointSize:size weight:UIImageSymbolWeightRegular];
    _glyph.image = nil;
    [self syncOutput];
}

- (void)syncOutput {
    NSString *want = SGRPlayerOutputSymbol();
    if (![_glyph.symbol isEqualToString:want]) [_glyph setSymbol:want animated:self.window != nil];
    // From the system's catalogue, as the footer draws it: iOS 27's names that systemImageNamed: lacks.
    UIImage *image = SGRPlayerOutputImage(want, _glyph.preferredSymbolConfiguration);
    if (image && image != _glyph.image) _glyph.image = image;
    [self setNeedsLayout];
}

- (void)didMoveToWindow {
    [super didMoveToWindow];
    if (self.window) [self syncOutput];
}

- (void)layoutSubviews {
    [super layoutSubviews];
    // The picker lays out its own button under the glyph; the glyph stays on top of it, centered.
    if (self.subviews.lastObject != _glyph) [self bringSubviewToFront:_glyph];
    _glyph.bounds = (CGRect){CGPointZero, _glyph.intrinsicContentSize};
    _glyph.center = CGPointMake(CGRectGetMidX(self.bounds), CGRectGetMidY(self.bounds));
}

- (void)held:(UILongPressGestureRecognizer *)hold {
    if (hold.state != UIGestureRecognizerStateBegan) return;
    [[[UIImpactFeedbackGenerator alloc] initWithStyle:UIImpactFeedbackStyleMedium] impactOccurred];
    if (self.onHold) self.onHold();
}

- (NSString *)accessibilityValue {
    return SGRPlayerOutputName();
}

- (NSArray<UIAccessibilityCustomAction *> *)accessibilityCustomActions {
    __weak typeof(self) weakSelf = self;
    return @[[[UIAccessibilityCustomAction alloc] initWithName:@"Spotify Connect" actionHandler:^BOOL(UIAccessibilityCustomAction *action) {
        typeof(self) me = weakSelf;
        if (me.onHold) me.onHold();
        return me != nil;
    }]];
}
@end

UIView *SGRSystemMakeRouteButton(CGFloat pointSize, NSString *place) {
    SGRSystemRouteButton *button = [[SGRSystemRouteButton alloc] initWithFrame:CGRectMake(0, 0, 36, 36)];
    [button setGlyphPointSize:pointSize];
    [button setGlyphTint:SGRPrimary()];
    button.onHold = ^{
        NSString *how = nil;
        openSpotifyConnect(&how);
    };
    return button;
}

#pragma mark - the lines on their own

// Sees every touch on the page and takes none, as the redesigned player's watcher does (PlayerLyrics.x's
// SGRPlayerTouchWatcher): it holds the clock while a finger is down and starts it once the last one lifts. It never
// recognizes, so it stands in no one's way, the zoom's close included.
@interface SGRSystemTouchWatcher : UIGestureRecognizer <UIGestureRecognizerDelegate>
@property (nonatomic, readonly) BOOL touching;
@property (nonatomic, copy) void (^down)(void);
@property (nonatomic, copy) void (^lifted)(void);
@end

@implementation SGRSystemTouchWatcher {
    BOOL _touching;
}
- (instancetype)init {
    if (!(self = [super initWithTarget:nil action:nil])) return nil;
    self.delegate = self;
    self.cancelsTouchesInView = NO;
    self.delaysTouchesBegan = NO;
    self.delaysTouchesEnded = NO;
    return self;
}
- (BOOL)gestureRecognizer:(UIGestureRecognizer *)recognizer shouldRecognizeSimultaneouslyWithGestureRecognizer:(UIGestureRecognizer *)other {
    return YES;
}
- (BOOL)canBePreventedByGestureRecognizer:(UIGestureRecognizer *)other {
    return NO;
}
- (BOOL)canPreventGestureRecognizer:(UIGestureRecognizer *)other {
    return NO;
}
- (void)touchesBegan:(NSSet<UITouch *> *)touches withEvent:(UIEvent *)event {
    _touching = YES;
    if (self.down) self.down();
}
- (void)touchesEnded:(NSSet<UITouch *> *)touches withEvent:(UIEvent *)event {
    [self liftedIn:event];
}
- (void)touchesCancelled:(NSSet<UITouch *> *)touches withEvent:(UIEvent *)event {
    [self liftedIn:event];
}
- (void)liftedIn:(UIEvent *)event {
    for (UITouch *touch in [event touchesForGestureRecognizer:self]) {
        if (touch.phase != UITouchPhaseEnded && touch.phase != UITouchPhaseCancelled) return;
    }
    self.state = UIGestureRecognizerStateFailed;
}
- (void)reset {
    [super reset];
    if (!_touching) return;
    _touching = NO;
    if (self.lifted) self.lifted();
}
@end

#pragma mark - the page

@interface SGRSystemPlayerPage () <SGPlayerStateObserver, UIGestureRecognizerDelegate, SGRSystemTurnPage, AVPictureInPictureSampleBufferPlaybackDelegate, AVPictureInPictureControllerDelegate>
@end

@implementation SGRSystemPlayerPage {
    UIImageView *_backdrop;
    UIVisualEffectView *_blur;
    UIView *_shade;
    SGRArtworkField *_field;      // the redesigned player's background, for every choice but Still
    UIView *_motion, *_visualiser; // Animated's clip and the Visualizer's hills over it, the Player page's previews
    SGRPlayerBackgroundKind _background;
    BOOL _backgroundSet;
    NSString *_motionTrack;       // the track _motion is the clip of
    NSString *_clipHoldTrack;     // the new track the last clip waits on (syncClipAnimated:), and until when
    CFTimeInterval _clipHoldUntil;
    NSString *_smallCoverTrack;   // the track whose small stand-in cover is waited out (refreshCover), and until when
    CFTimeInterval _smallCoverUntil;
    BOOL _hadTrack, _emptyPending;  // a track shown, and a look again pending before Not Playing (show:)
    SGRGlyphButton *_close;
    UIButton *_more;
    UILabel *_context;
    UIView *_coverHolder;   // the shadow; scaled when paused
    UIImageView *_cover;
    BOOL _narrating;   // the AI DJ talking
    SGRDJRingView *_djRing;   // drawn over the cover while it talks
    UIView *_videoSurface;   // over the cover while a music video plays
    UIView *_videoBlank;     // black under it, over the album's cover, while the track is a video
    __weak UIView *_videoHome;   // where the borrowed surface came from
    CGRect _videoHomeFrame;
    UIViewAutoresizing _videoHomeMask;
    BOOL _wantsVideo;
    NSString *_videoURI;     // the video the borrowed surface was taken for
    __weak UIView *_nextSurface;            // the new one the clock found, to take next
    SGRFrameKeeper *_videoKeeper;
    UIColor *_videoHomeColor;
    AVPictureInPictureController *_pip;
    SGMarqueeLabel *_title, *_artist;
    UIView *_titleBlock;                       // the title and artist, the swipe's page
    CAGradientLayer *_titleFade;
    SGMarqueeLabel *_besideTitle, *_besideArtist;   // the track the swipe brings in
    BOOL _titleSkipping;
    NSString *_titleSkipFrom;                  // the track the swipe skipped from
    BOOL _titlePast;                           // the swipe is past where letting go skips
    BOOL _episode;                             // an episode or a chapter plays: 15 s skips, the speed in shuffle's place
    BOOL _volumeOff, _shuffleOff, _repeatOff;  // the Player page's Volume off, Hide on the player's Shuffle and Repeat
    UIButton *_speed;
    SGRGlyphButton *_add;
    SGRGlyphButton *_switchVideo;   // Switch to Video / Audio, beside the star when the song has the other
    SGRGlyphButton *_djButton;      // the DJ's sheet, beside them while the DJ plays
    id _savedWatch;
    NSString *_savedTrack;
    BOOL _savedShown;
    SGRSystemScrubber *_scrubber;
    UILabel *_elapsed, *_remaining;
    SGRSystemControlButton *_shuffle, *_previous, *_play, *_next, *_repeat;
    UIControl *_volume;
    SGRGlyphButton *_lyrics, *_queue;
    // While a Spotify Jam is on (SystemJam.h): the queue button in a capsule with the faces of who is in it, as the
    // Music app shows SharePlay (its owner's screenshot, 2026-11-09). The glyph still opens the page's queue; the queue's
    // Jam chip opens the Jam's details.
    UIView *_jamCapsule;
    NSArray<UIImage *> *_jamFaces;
    NSTimer *_jamTimer;
    SGRSystemRouteButton *_route;
    UILabel *_routeLine;
    UIView *_stage;   // the lines' own view, since the karaoke view dims every sibling it has; out of the page while closed
    SGRKaraokeView *_lines;
    UILabel *_lyricsNote;
    UIActivityIndicatorView *_lyricsSpinner;
    SGRSystemLyrics _lyricsShown;
    NSString *_lyricsTrack;
    BOOL _lyricsOpen;
    BOOL _queueOpen;              // the queue in the page in the lyrics' place (SystemQueue.m), the Music app's way
    BOOL _queueDragging;          // a track of the queue lifted: the controls away and the queue down to the foot
    NSMapTable<UIView *, NSArray *> *_dragAlphas;
    NSUInteger _dragReturn;       // the latest let go's, so an older one's delayed return is dropped   // each control's alpha and touches before, put back as it is let go
    id _spotifyQueue;             // Spotify's queue as last fetched (SPTPlayerQueue), handed back with a track moved
    NSArray<NSString *> *_spotifyQueueKey;   // the playing track's and the tracks to come's URIs at that fetch
    SGRSystemQueueView *_queueView;   // out of the page while closed
    UIView *_optionBadge;             // shuffle or repeat on the queue button, while on and hidden from the controls
    UIViewController *_landscapeScreen;   // the landscape player over the page while the app is turned
    CGFloat _headPush;                // how far the queue's scroll has pushed the thumbnail row up, 0 to its headRoom
    CGFloat _shownAlpha;              // the alpha placeHeadPush last gave the row
    UIImageView *_queueBubble;        // the queue button's light disc while the queue is open, the Music app's
    UIImageView *_lyricsBubble;       // the lyrics button's, while the lyrics are up
    BOOL _alone;      // the lines have the page to themselves
    NSTimer *_rest;
    SGRSystemTouchWatcher *_watcher;
    UITapGestureRecognizer *_wake;   // on while alone: the tap that brings the rest back
    UILongPressGestureRecognizer *_titlePress; // the title and artist pressing in while a tap on them opens the album
    BOOL _titlePressed;
    NSTimer *_timer;
    double _seekTarget;
    CFTimeInterval _seekUntil;
    // The whole seconds the times show, so the timer's four ticks a second redraw them only when a second turns over.
    NSInteger _shownElapsed, _shownLeft, _shownTotal;
    // What the cover's shadow path and the title's fade were last made for.
    CGRect _shadowBounds;
    CGFloat _titleEdge;
    BOOL _pausedShown, _shownOnce;
    // The open has landed: until then the progress bar and the volume take no touch, so the touch that opened the page
    // cannot turn UIKit's swipe close off. Set kTouchesAfter into the open, or at viewDidAppear: if sooner: UIKit's zoom
    // settles its spring 1 to 1.4 s after the tap, long after the page looks open (the phone's log, 2026-11-01).
    BOOL _appeared;
    BOOL _builtWithLyrics;   // sgr_lyricsLeftOpen as the page was built
    // Counts the opens, so a landing timed for an earlier open does not land a later one.
    NSUInteger _openCount;
    CGRect _thumb;   // where the cover goes while the lyrics are up
}

- (BOOL)outOfDate {
    return self.isViewLoaded && _builtWithLyrics != sgr_lyricsLeftOpen;
}

- (void)viewDidLoad {
    [super viewDidLoad];
    self.overrideUserInterfaceStyle = UIUserInterfaceStyleDark;
    UIView *view = self.view;
    view.backgroundColor = [UIColor colorWithWhite:0.11 alpha:1];
    view.clipsToBounds = YES;

    // Still: the cover, small and drawn large under a dark blur, a wash of its colors rather than a picture. Every other
    // choice of the redesigned player's background is that player's own field over it (reloadBackground).
    _backdrop = [UIImageView new];
    _backdrop.contentMode = UIViewContentModeScaleAspectFill;
    _blur = [[UIVisualEffectView alloc] initWithEffect:[UIBlurEffect effectWithStyle:UIBlurEffectStyleDark]];
    _shade = [UIView new];
    _shade.backgroundColor = [UIColor colorWithWhite:0 alpha:0.3];
    for (UIView *layer in @[_backdrop, _blur, _shade]) {
        layer.userInteractionEnabled = NO;
        [view addSubview:layer];
    }
    _field = [[SGRArtworkField alloc] initWithFrame:view.bounds];
    _field.showsBackdrop = YES;
    _field.userInteractionEnabled = NO;
    _field.hidden = YES;
    [view addSubview:_field];

    __weak typeof(self) weakSelf = self;
    _close = [SGRGlyphButton buttonWithSymbol:@"chevron.down" pointSize:17 title:@"Close"];
    _close.onTap = ^{
        [weakSelf dismissViewControllerAnimated:YES completion:nil];
    };
    _more = [self makeMoreButton];
    _context = [UILabel new];
    // What the redesigned player's header says, in its weight and white (contextTitle).
    _context.font = SGRFont(UIFontTextStyleSubheadline, UIFontWeightBold, UIContentSizeCategoryLarge);
    _context.textColor = SGRPrimary();
    _context.textAlignment = NSTextAlignmentCenter;

    _coverHolder = [UIView new];
    _coverHolder.layer.shadowColor = UIColor.blackColor.CGColor;
    _coverHolder.layer.shadowOpacity = 0.35;
    _coverHolder.layer.shadowRadius = 24;
    _coverHolder.layer.shadowOffset = CGSizeMake(0, 12);
    _cover = [UIImageView new];
    _cover.contentMode = UIViewContentModeScaleAspectFill;
    _cover.clipsToBounds = YES;
    _cover.layer.cornerRadius = SGRRadiusArtwork;
    _cover.layer.cornerCurve = kCACornerCurveContinuous;
    _cover.backgroundColor = [UIColor colorWithWhite:1 alpha:0.08];
    _cover.isAccessibilityElement = NO;
    [_coverHolder addSubview:_cover];

    // A long title or artist glides to its end and back, its edge faded, as the redesigned player's title does (Spotify's
    // own marquee there; the mod's SGMarqueeLabel, the Music app's timing, here and on the glass bar). The two sit in one
    // block that a sideways swipe pages through the tracks (titleSwiped:), with the track coming in beside them.
    _titleBlock = [UIView new];
    // Cut at the column's sides through a soft edge, as the mini player's lines are (SystemTabs.x's kTextFade): the block
    // reaches kTitleFade past the text on either side, so at rest the fade lies over nothing.
    _titleBlock.clipsToBounds = YES;
    _titleFade = [CAGradientLayer layer];
    _titleFade.startPoint = CGPointMake(0, 0.5);
    _titleFade.endPoint = CGPointMake(1, 0.5);
    _titleFade.colors = @[(id)UIColor.clearColor.CGColor, (id)UIColor.blackColor.CGColor, (id)UIColor.blackColor.CGColor, (id)UIColor.clearColor.CGColor];
    _titleBlock.layer.mask = _titleFade;
    _title = [SGMarqueeLabel new];
    _artist = [SGMarqueeLabel new];
    _besideTitle = [SGMarqueeLabel new];
    _besideArtist = [SGMarqueeLabel new];
    for (SGMarqueeLabel *label in @[_title, _besideTitle]) {
        label.font = SGRFont(UIFontTextStyleTitle2, UIFontWeightBold, UIContentSizeCategoryExtraLarge);
        label.textColor = SGRPrimary();
    }
    for (SGMarqueeLabel *label in @[_artist, _besideArtist]) {
        label.font = SGRFont(UIFontTextStyleBody, UIFontWeightRegular, UIContentSizeCategoryExtraLarge);
        label.textColor = SGRSecondary();
    }
    _besideTitle.hidden = _besideArtist.hidden = YES;
    // Each reaches kTitleFade before the text column with a faded zone there, so a long line scrolls out through a soft
    // edge on the left as on the right; the column's start stays crisp at rest (its owner, 2026-11-01: the block's own
    // edge, where the text started, cut it hard).
    for (SGMarqueeLabel *label in @[_title, _artist, _besideTitle, _besideArtist]) label.leadingFade = kTitleFade;
    _besideTitle.isAccessibilityElement = _besideArtist.isAccessibilityElement = NO;
    for (UIView *label in @[_title, _artist, _besideTitle, _besideArtist]) [_titleBlock addSubview:label];
    UIPanGestureRecognizer *swipe = [[UIPanGestureRecognizer alloc] initWithTarget:self action:@selector(titleSwiped:)];
    swipe.delegate = self;
    [_titleBlock addGestureRecognizer:swipe];
    // An episode's speed, where a song's shuffle is, as Spotify's episode player has it; it opens the speed panel the ⋯'s
    // Speed, Pitch & Reverb opens (Shared/Player/SpeedPitch.h).
    _speed = [UIButton buttonWithType:UIButtonTypeCustom];
    _speed.titleLabel.font = SGRMonospacedDigitsFont(SGRFont(UIFontTextStyleSubheadline, UIFontWeightBold, UIContentSizeCategoryLarge));
    [_speed setTitleColor:SGRPrimary() forState:UIControlStateNormal];
    _speed.accessibilityLabel = @"Playback speed";
    _speed.hidden = YES;
    [_speed addTarget:self action:@selector(speedTapped) forControlEvents:UIControlEventTouchUpInside];
    // A tap on the title and the artist opens the album (SGRKeyPlayerTitleAlbum).
    UITapGestureRecognizer *titleTap = [[UITapGestureRecognizer alloc] initWithTarget:self action:@selector(titleTapped)];
    [titleTap requireGestureRecognizerToFail:swipe];
    [_titleBlock addGestureRecognizer:titleTap];
    // Pressed, they press in as the star beside them does (its owner, 2026-11-10: "make the title click in"); alongside the
    // tap and the swipe, which let go of it as it starts.
    _titlePress = [[UILongPressGestureRecognizer alloc] initWithTarget:self action:@selector(titlePressed:)];
    _titlePress.minimumPressDuration = 0;
    _titlePress.cancelsTouchesInView = NO;
    _titlePress.delegate = self;
    [_titleBlock addGestureRecognizer:_titlePress];
    // The add button beside the title, where Spotify's player has its own (InformationElementsUnit's
    // Components.UI.AddToButton, kept by the redesigned player): the Music app's star, as the landscape player has it,
    // filled once the track is in Liked Songs (its owner, 2026-11-06: the star in place of the tick).
    _add = [SGRGlyphButton buttonWithSymbol:@"star" pointSize:kAddGlyph title:@"Add to Liked Songs"];
    _add.glyph.tintColor = SGRPrimary();
    _add.onTap = ^{ [weakSelf toggleSaved]; };
    // Beside the star, leftwards (its owner, 2026-11-10: next to the star and the ⋯, the top tried and put back): Switch to
    // Video for a song with a music video, under the Switch to video setting, and the DJ's sheet while the DJ plays.
    _switchVideo = [SGRGlyphButton buttonWithSymbol:@"music.note.tv" pointSize:kAddGlyph title:@"Music Video"];
    _switchVideo.glyph.tintColor = SGRPrimary();
    _switchVideo.hidden = YES;
    _switchVideo.onTap = ^{ [weakSelf switchVideoTapped]; };
    _djButton = [SGRGlyphButton buttonWithSymbol:@"waveform" pointSize:kAddGlyph title:@"DJ X"];
    _djButton.glyph.tintColor = SGRPrimary();
    _djButton.glyph.image = SGRDJGlyphImage(kAddGlyph);
    _djButton.hidden = YES;
    _djButton.onTap = ^{ SGRSystemOpenDJ(); };

    _scrubber = [SGRSystemScrubber new];
    _scrubber.onMove = ^(CGFloat value) { [weakSelf scrubbedTo:value]; };
    _scrubber.onRelease = ^(CGFloat value) { [weakSelf seekTo:value]; };
    UIFont *times = SGRMonospacedDigitsFont(SGRFont(UIFontTextStyleCaption1, UIFontWeightSemibold, UIContentSizeCategoryLarge));
    _elapsed = [UILabel new];
    _remaining = [UILabel new];
    _remaining.textAlignment = NSTextAlignmentRight;
    _scrubber.leadingLabel = _elapsed;
    _scrubber.trailingLabel = _remaining;
    for (UILabel *label in @[_elapsed, _remaining]) {
        label.font = times;
        label.textColor = SGRSecondary();
        label.isAccessibilityElement = NO;
    }

    _shuffle = [SGRSystemControlButton buttonWithSymbol:@"shuffle" pointSize:19 title:@"Shuffle"];
    _shuffle.onTap = ^{ [weakSelf toggleShuffle]; };
    // The command first, then the step: the animation never holds the skip up.
    _previous = [SGRSystemControlButton buttonWithSymbol:@"backward.fill" pointSize:kSkipGlyph title:@"Previous"];
    _previous.transport = YES;
    _previous.onTap = ^{ [weakSelf skip:-1]; };
    _play = [SGRSystemControlButton buttonWithSymbol:@"play.fill" pointSize:kPlayGlyph title:@"Play"];
    _play.transport = YES;
    // Without the symbols' baseline: pressed and swapped, play and pause sank towards it and drifted off the circle's
    // middle (its owner's recordings and the phone's log, 2026-11-01: glyph, circle and button all centered alike).
    _play.glyph.withoutBaseline = YES;
    _play.glyph.image = [UIImage systemImageNamed:@"play.fill" withConfiguration:_play.glyph.preferredSymbolConfiguration].imageWithoutBaseline;
    _play.onTap = ^{ [weakSelf togglePlay]; };
    _next = [SGRSystemControlButton buttonWithSymbol:@"forward.fill" pointSize:kSkipGlyph title:@"Next"];
    _next.transport = YES;
    _next.onTap = ^{ [weakSelf skip:1]; };
    // Without the symbols' baseline, as play's: the glyph is then its picture fitted to it, as the step draws it, so the
    // step hands back to it in place (its owner's recordings, 2026-11-02: the glyph sat lower than the step, and jumped).
    for (SGRSystemControlButton *skip in @[_previous, _next]) {
        skip.glyph.withoutBaseline = YES;
        skip.glyph.image = [UIImage systemImageNamed:skip.glyph.symbol withConfiguration:skip.glyph.preferredSymbolConfiguration].imageWithoutBaseline;
    }
    _repeat = [SGRSystemControlButton buttonWithSymbol:@"repeat" pointSize:19 title:@"Repeat"];
    _repeat.onTap = ^{ [weakSelf cycleRepeat]; };

    _volume = SGRPlayerMakeVolumeRow();
    // The Player page's switches, read at each open: Volume off takes the row away; Shuffle and Repeat hidden stay in
    // their slots, unseen and untouchable.
    _volumeOff = !SGEnabled(SGRKeyPlayerVolume);
    _volume.hidden = _volumeOff;
    _shuffleOff = SGHidden(SGRKeyPlayerHideShuffle);
    _repeatOff = SGHidden(SGRKeyPlayerHideRepeat);
    for (SGRSystemControlButton *button in @[_shuffle, _repeat]) {
        BOOL off = button == _shuffle ? _shuffleOff : _repeatOff;
        if (!off) continue;
        button.alpha = 0;
        button.userInteractionEnabled = NO;
        button.accessibilityElementsHidden = YES;
    }

    // Dimmed until the track's lines are in, as the redesigned player's footer glyph is (PlayerFooter.x): syncLyrics.
    _lyrics = [SGRGlyphButton buttonWithSymbol:kLyricsSymbol pointSize:20 title:@"Lyrics"];
    _lyrics.glyph.tintColor = SGRSecondary();
    _lyrics.enabled = NO;
    _lyrics.onTap = ^{ [weakSelf toggleLyrics]; };
    _route = [[SGRSystemRouteButton alloc] initWithFrame:CGRectMake(0, 0, 44, 44)];
    // Spotify's sheet goes up over the page (SystemTabs.x sends a presentation from under the page to the page), so the
    // page stays where it is.
    _route.onHold = ^{
        NSString *how = nil;
        openSpotifyConnect(&how);
    };
    // The output's name under the glyph, as the redesigned player's footer draws it (PlayerFooter.x's
    // SGRPlayerPlaceRoute): the Music app's 15pt at about 68% white, semibold to read as its blended regular does, and
    // nothing on the phone's own speaker (its owner, 2026-11-01: "missing the text under the AirPlay icon").
    _routeLine = [UILabel new];
    _routeLine.font = SGRFont(UIFontTextStyleSubheadline, UIFontWeightSemibold, UIContentSizeCategoryLarge);
    _routeLine.textColor = [UIColor colorWithWhite:1 alpha:SGRIncreaseContrast() ? 0.8 : 0.68];
    _routeLine.textAlignment = NSTextAlignmentCenter;
    _routeLine.userInteractionEnabled = NO;
    _routeLine.isAccessibilityElement = NO;   // read as the picker's value
    _queue = [SGRGlyphButton buttonWithSymbol:@"list.bullet" pointSize:20 title:@"Queue"];
    // A tap turns the page to its queue, as the Music app's does (its owner, 2026-11-02). No hold: Spotify's own queue sheet
    // is not opened from the page any more (its owner, 2026-11-02).
    _queue.onTap = ^{ [weakSelf toggleQueue]; };
    // Dim while the queue is closed; open, the Music app's way (its owner's screenshot, 2026-11-02): a light disc behind
    // it and the glyph dark on it.
    _queue.glyph.tintColor = SGRSecondary();
    _queueBubble = cutDisc(@"list.bullet");
    [_queue insertSubview:_queueBubble atIndex:0];
    _optionBadge = SGRSystemMakeOptionBadge(_queue);
    _lyricsBubble = cutDisc(kLyricsSymbolOpen);
    [_lyrics insertSubview:_lyricsBubble atIndex:0];
    _queueView = [SGRSystemQueueView new];
    _queueView.alpha = 0;
    _queueView.onReorder = ^(NSArray *upcoming) { [weakSelf handQueueBack:upcoming]; };
    _queueView.onJam = ^{ [weakSelf startOrOpenJam]; };
    // Shuffle and Repeat hidden from the controls on the Player page show in the queue's row instead (its owner, 2026-11-02).
    _queueView.showsShuffle = _shuffleOff;
    _queueView.showsRepeat = _repeatOff;
    _queueView.onShuffle = ^{ [weakSelf toggleShuffle]; };
    _queueView.onRepeat = ^{ [weakSelf cycleRepeat]; };
    _queueView.onDragging = ^(BOOL dragging) { [weakSelf setQueueDragging:dragging]; };
    _queueView.onHeadPush = ^(CGFloat push) { [weakSelf pushHead:push]; };
    _queueView.onPickPast = ^(SPTPlayerTrack *track, NSInteger steps) {
        if (SGRSystemHistoryOn()) SGRSystemPlayPast(track);
        else SGRSystemStepBack(track, steps);
    };
    _queueView.onPick = ^(SPTPlayerTrack *track) {
        id<SPTPlayer> player = (id<SPTPlayer>)SGPlayer();
        if ([player respondsToSelector:@selector(skipToNextTrackWithOptions:track:)]) [player skipToNextTrackWithOptions:nil track:track];
    };

    // The lines, and in their place while they have none to show (the karaoke view fades its siblings out while it
    // has), the look for them or the word that there are none.
    _stage = [UIView new];
    _stage.alpha = 0;
    _lines = [[SGRKaraokeView alloc] initWithFrame:CGRectZero];
    _lines.autoresizingMask = UIViewAutoresizingFlexibleWidth | UIViewAutoresizingFlexibleHeight;
    // Sing's mic stays with the lines on their own, as in the redesigned player (PlayerLyrics.x).
    _lines.keepsSing = YES;
    // The mic over the lines, not a clear row of its own under them, as the landscape player has it (its owner, 2026-11-06).
    _lines.rowOverLines = YES;
    // As the redesigned player's lines: a scroll on through them leaves them on their own, not under VoiceOver, which
    // keeps the controls up, nor under a sheet; a scroll back brings the rest back (PlayerLyrics.x's browsingBegan).
    _lines.browsingBegan = ^(BOOL onward) {
        typeof(self) me = weakSelf;
        if (!onward) [me setAlone:NO animated:YES];
        else if (!UIAccessibilityIsVoiceOverRunning() && !me.presentedViewController) [me setAlone:YES animated:YES];
    };
    _lyricsNote = [UILabel new];
    _lyricsNote.text = @"No lyrics for this song";
    _lyricsNote.font = SGRFont(UIFontTextStyleTitle3, UIFontWeightSemibold, UIContentSizeCategoryExtraLarge);
    _lyricsNote.textColor = SGRSecondary();
    _lyricsNote.textAlignment = NSTextAlignmentCenter;
    _lyricsNote.numberOfLines = 0;
    _lyricsNote.hidden = YES;
    _lyricsSpinner = [[UIActivityIndicatorView alloc] initWithActivityIndicatorStyle:UIActivityIndicatorViewStyleMedium];
    _lyricsSpinner.color = SGRSecondary();
    _lyricsSpinner.hidesWhenStopped = YES;
    for (UIView *sub in @[_lyricsNote, _lyricsSpinner]) {
        sub.autoresizingMask = UIViewAutoresizingFlexibleWidth | UIViewAutoresizingFlexibleHeight;
        [_stage addSubview:sub];
    }
    [_stage addSubview:_lines];

    for (UIView *sub in @[_close, _more, _context, _coverHolder, _titleBlock, _speed, _add, _switchVideo, _djButton, _scrubber, _elapsed, _remaining, _shuffle, _previous, _play,
                          _next, _repeat, _volume, _lyrics, _route, _routeLine, _queue]) {
        [view addSubview:sub];
    }

    // The touch watcher and the wake tap, the redesigned player's (PlayerLyrics.x): neither pans.
    _watcher = [SGRSystemTouchWatcher new];
    _watcher.down = ^{ [weakSelf stopRest]; };
    _watcher.lifted = ^{
        typeof(self) me = weakSelf;
        if (me && !me->_alone) [me restartRest];
    };
    [view addGestureRecognizer:_watcher];
    _wake = [[UITapGestureRecognizer alloc] initWithTarget:self action:@selector(woke)];
    _wake.delegate = self;
    _wake.cancelsTouchesInView = NO;
    _wake.delaysTouchesEnded = NO;
    _wake.enabled = NO;
    [view addGestureRecognizer:_wake];

    SGAddPlayerStateObserver(self);
    [NSNotificationCenter.defaultCenter addObserver:self selector:@selector(artworkChanged) name:SGRNowPlayingArtworkDidChangeNotification object:nil];
    // Posted on the main queue (Shared/Lyrics/Lyrics.h) as a track's lines are kept, or its look ends with none.
    [NSNotificationCenter.defaultCenter addObserver:self selector:@selector(linesKept:) name:SGKaraokeLinesKeptNotification object:nil];
    // Posted on the main queue (Player.h).
    [NSNotificationCenter.defaultCenter addObserver:self selector:@selector(syncRouteLine) name:SGRPlayerOutputDidChangeNotification object:nil];
    // Posted on the main queue (Player.h).
    [NSNotificationCenter.defaultCenter addObserver:self selector:@selector(motionChanged) name:SGRPlayerMotionDidChangeNotification object:nil];
    // Posted on the main queue by UIKit. In the background, or with VoiceOver turned on, the rest comes back, as in the
    // redesigned player; back in front the clock starts again.
    [NSNotificationCenter.defaultCenter addObserver:self selector:@selector(resignedActive) name:UIApplicationWillResignActiveNotification object:nil];
    [NSNotificationCenter.defaultCenter addObserver:self selector:@selector(restartRest) name:UIApplicationDidBecomeActiveNotification object:nil];
    [NSNotificationCenter.defaultCenter addObserver:self selector:@selector(voiceOverChanged) name:UIAccessibilityVoiceOverStatusDidChangeNotification object:nil];
    [self show:SGPlayerState()];
    [self syncRouteLine];
    [self reloadBackgroundAnimated:NO];
    _builtWithLyrics = sgr_lyricsLeftOpen;
    if (sgr_lyricsLeftOpen && SGRPlayerLyricsAvailable()) [self setLyricsOpen:YES];
}

- (UIStatusBarStyle)preferredStatusBarStyle {
    return UIStatusBarStyleLightContent;
}

// Turned by iOS with the rest of the app (SystemTurn.m), the landscape player standing in the page while it is sideways
// (its owner, 2026-11-06); portrait alone with the landscape player switched off, as its stretched controls are no look.
- (UIInterfaceOrientationMask)supportedInterfaceOrientations {
    return SGEnabled(SGRKeyLyricsLandscape) ? UIInterfaceOrientationMaskAllButUpsideDown : UIInterfaceOrientationMaskPortrait;
}

- (void)viewWillTransitionToSize:(CGSize)size withTransitionCoordinator:(id<UIViewControllerTransitionCoordinator>)coordinator {
    [super viewWillTransitionToSize:size withTransitionCoordinator:coordinator];
    [self syncLandscapeFor:size coordinator:coordinator];
}

// Sideways, the landscape player in the page over everything of its own, crossfaded in as iOS turns the scene, with the
// page's lyrics or queue up in it; upright again, out the same way, the page left on what it showed.
- (void)syncLandscapeFor:(CGSize)size coordinator:(id<UIViewControllerTransitionCoordinator>)coordinator {
    BOOL sideways = size.width > size.height && SGEnabled(SGRKeyLyricsLandscape);
    UIViewController *screen = _landscapeScreen;
    if (sideways && !screen) {
        screen = SGRSystemMakeLandscape(_lyricsOpen, _queueOpen);
        [self addChildViewController:screen];
        screen.view.frame = (CGRect){CGPointZero, size};
        screen.view.autoresizingMask = UIViewAutoresizingFlexibleWidth | UIViewAutoresizingFlexibleHeight;
        [self.view addSubview:screen.view];
        [screen didMoveToParentViewController:self];
        _landscapeScreen = screen;
        SGRSystemTurnSetEmbedded(screen);
        __weak typeof(self) weakSelf = self;
        void (^hold)(void) = ^{
            typeof(self) page = weakSelf;
            if (page && page->_landscapeScreen == screen) [page holdUnderLandscape:YES];
        };
        if (coordinator) {
            screen.view.alpha = 0;
            [coordinator animateAlongsideTransition:^(id<UIViewControllerTransitionCoordinatorContext> context) { screen.view.alpha = 1; }
                                         completion:^(id<UIViewControllerTransitionCoordinatorContext> context) { hold(); }];
        } else hold();
    } else if (!sideways && screen) {
        BOOL lyrics = NO, queue = NO;
        SGRSystemLandscapeShowing(screen, &lyrics, &queue);
        _landscapeScreen = nil;
        SGRSystemTurnSetEmbedded(nil);
        [self holdUnderLandscape:NO];
        [self landscapeLeftShowingLyrics:lyrics queue:queue];
        void (^remove)(void) = ^{
            [screen willMoveToParentViewController:nil];
            [screen.view removeFromSuperview];
            [screen removeFromParentViewController];
        };
        if (coordinator) {
            [coordinator animateAlongsideTransition:^(id<UIViewControllerTransitionCoordinatorContext> context) { screen.view.alpha = 0; }
                                         completion:^(id<UIViewControllerTransitionCoordinatorContext> context) { remove(); }];
        } else remove();
    }
}

- (void)dealloc {
    [_timer invalidate];
    [_rest invalidate];
}

// The progress runs on a timer only while the page is up, four times a second: the times change by the second, and a
// display link would pin the zoom's frames to its rate.
- (void)viewWillAppear:(BOOL)animated {
    [super viewWillAppear:animated];
    [self updateJamAnimated:NO];
    [self paintAccent];
    [self startTicking];
    __weak typeof(self) weakSelf = self;
    [self syncRouteLine];
    SGRSystemTurnSetLyrics(_lyricsOpen);
    SGRSystemTurnSetQueue(_queueOpen);
    // The progress bar and the volume take no touch until the open has landed, so the touch that opened the page, still
    // down or landing on them as it appears, cannot turn UIKit's swipe close off (the phone's log, 2026-11-01). Only the
    // open: back from a swipe close let go, or from what covered it, the page takes touches at once.
    if (!self.isBeingPresented) return;
    _scrubber.userInteractionEnabled = _volume.userInteractionEnabled = NO;
    _appeared = NO;
    NSUInteger open = ++_openCount;
    dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(kTouchesAfter * NSEC_PER_SEC)), dispatch_get_main_queue(), ^{
        typeof(self) page = weakSelf;
        if (page && page->_openCount == open) [page openLanded];
    });
}

// None while the landscape player covers the page: it keeps its own times.
- (void)startTicking {
    [_timer invalidate];
    _timer = nil;
    if (_landscapeScreen) return;
    __weak typeof(self) weakSelf = self;
    _timer = [NSTimer timerWithTimeInterval:0.25 repeats:YES block:^(NSTimer *timer) { [weakSelf tick]; }];
    _timer.tolerance = 0.05;   // lets iOS fold the ticks into other wakes
    [NSRunLoop.mainRunLoop addTimer:_timer forMode:NSRunLoopCommonModes];
    [self tick];
}

// Under the landscape player the page is out of sight: its clip, hills, colours and timer stop until it is back, and
// start again as the landscape player begins to leave.
- (void)holdUnderLandscape:(BOOL)held {
    _motion.hidden = _visualiser.hidden = held;
    [self syncFieldHeld];
    if (held) {
        [_timer invalidate];
        _timer = nil;
    } else if (self.view.window) [self startTicking];
}

// The open has landed (kTouchesAfter in, or viewDidAppear:): the bars' touches are let in.
- (void)openLanded {
    if (_appeared || !self.view.window || self.isBeingDismissed) return;
    _appeared = YES;
    _scrubber.userInteractionEnabled = _volume.userInteractionEnabled = YES;
}

#pragma mark - the Jam

static const CGFloat kJamFace = 28, kJamFaceStep = 18, kJamInset = 8;

// Spotify's Jam details sheet (Invite others, who is in it, Auto-invite, End Jam, Guest settings: its owner's screenshot,
// 2026-11-09), by the link Spotify's own list names for it; if Spotify takes no such link, its Jam queue sheet, whose
// gear leads there.
- (void)openJamSettings {
    if (SGOpenSpotifyURI([NSURL URLWithString:@"spotify:internal:jam-manage-participants-sheet"])) return;
    SGOpenSpotifyURI([NSURL URLWithString:@"spotify:now-playing:queue"]);
}

// The queue's Jam chip: while a Jam is on, its sheet; otherwise Spotify's own link that starts one with what plays
// (spotify:jam:play, from Spotify's link list; untested 2026-11-09), and if Spotify takes no such link, its queue sheet,
// which has its own Start a Jam.
- (void)startOrOpenJam {
    if (_jamFaces || SGOpenSpotifyURI([NSURL URLWithString:@"spotify:jam:play"])) {
        if (_jamFaces) [self openJamSettings];
        return;
    }
    [self openJamSettings];
}

// Looked for while the page is in a window: when it opens, on each change of the player, and every two seconds, since
// joining and leaving change nothing the player reports.
- (void)updateJam {
    [self updateJamAnimated:YES];
}

// Before the page opens it is drawn in place, still (its owner's recording, 2026-11-09: it faded in once the page was up).
- (void)updateJamAnimated:(BOOL)animated {
    NSArray<UIImage *> *faces = SGRSystemJamFaces(3);
    if ((!faces && !_jamFaces) || [faces isEqualToArray:_jamFaces]) return;
    _jamFaces = faces;
    _queueView.jamOn = faces != nil;
    if (!faces) {
        // Back into the queue button: the capsule shrinks onto it as the glyph slides home, the faces fading first.
        [self.view setNeedsLayout];
        void (^close)(void) = ^{
            [self.view layoutIfNeeded];
            self->_jamCapsule.frame = self->_queue.frame;
            for (UIView *face in self->_jamCapsule.subviews) face.alpha = 0;
        };
        if (!animated) {
            [UIView performWithoutAnimation:close];
            _jamCapsule.alpha = 0;
            return;
        }
        [UIView animateWithDuration:0.5 delay:0 usingSpringWithDamping:0.86 initialSpringVelocity:0
                            options:UIViewAnimationOptionBeginFromCurrentState animations:close completion:^(BOOL finished) {
            if (!self->_jamFaces) self->_jamCapsule.alpha = 0;
        }];
        return;
    }
    if (!_jamCapsule) {
        _jamCapsule = [UIView new];
        _jamCapsule.backgroundColor = [UIColor colorWithWhite:1 alpha:0.14];
        _jamCapsule.layer.cornerCurve = kCACornerCurveContinuous;
        _jamCapsule.clipsToBounds = YES;
        _jamCapsule.alpha = 0;
        _jamCapsule.accessibilityElementsHidden = YES;
        // The faces show who is in it and nothing more (its owner, 2026-11-09): the queue's Jam chip opens the Jam.
        _jamCapsule.userInteractionEnabled = NO;
    }
    if (_jamCapsule.superview != _queue.superview) [_queue.superview insertSubview:_jamCapsule belowSubview:_queue];
    for (UIView *old in _jamCapsule.subviews.copy) [old removeFromSuperview];
    // The faces overlap, the first on top; before anyone has joined, two figures in their place.
    NSArray<UIImage *> *shown = faces.count ? faces : @[[UIImage systemImageNamed:@"person.2.fill"]];
    for (NSInteger i = shown.count - 1; i >= 0; i--) {
        UIImageView *face = [[UIImageView alloc] initWithImage:shown[i]];
        face.contentMode = faces.count ? UIViewContentModeScaleAspectFill : UIViewContentModeScaleAspectFit;
        face.tintColor = SGRSecondary();
        face.clipsToBounds = YES;
        face.layer.cornerRadius = kJamFace / 2;
        face.tag = i;
        [_jamCapsule addSubview:face];
    }
    [self.view setNeedsLayout];
    if (animated && _jamCapsule.alpha < 1) {
        // Out of the queue button: the capsule starts as the button, grows to the left with a spring while the glyph
        // slides to its right end, and the faces come in as it opens (its owner, 2026-11-09).
        [UIView performWithoutAnimation:^{
            self->_jamCapsule.frame = self->_queue.frame;
            self->_jamCapsule.alpha = 1;
            for (UIView *face in self->_jamCapsule.subviews) {
                face.bounds = CGRectMake(0, 0, kJamFace, kJamFace);
        face.center = CGPointMake(kJamInset + face.tag * kJamFaceStep + kJamFace / 2, 22);
                face.alpha = 0;
                face.transform = CGAffineTransformMakeScale(0.6, 0.6);
            }
        }];
        [UIView animateWithDuration:0.55 delay:0 usingSpringWithDamping:0.8 initialSpringVelocity:0
                            options:UIViewAnimationOptionBeginFromCurrentState animations:^{
            [self.view layoutIfNeeded];
        } completion:nil];
        [UIView animateWithDuration:0.35 delay:0.12 options:UIViewAnimationOptionCurveEaseOut animations:^{
            for (UIView *face in self->_jamCapsule.subviews) {
                face.alpha = 1;
                face.transform = CGAffineTransformIdentity;
            }
        } completion:nil];
    } else {
        [UIView performWithoutAnimation:^{
            self->_jamCapsule.alpha = 1;
            [self.view layoutIfNeeded];
        }];
    }
}

// The capsule stands centred where the queue button stands (its owner, 2026-11-09), the faces on its left and the queue
// glyph moved to its right end.
- (void)layoutJamAround:(CGFloat)rowMid {
    if (!_jamCapsule || !_jamFaces) return;
    NSUInteger count = MAX(1, _jamFaces.count);
    CGFloat faces = kJamFace + (count - 1) * kJamFaceStep;
    CGFloat middle = _queue.center.x, width = kJamInset + faces + 4 + 44;
    _jamCapsule.frame = CGRectMake(round(middle - width / 2), round(rowMid - 22), width, 44);
    _queue.center = CGPointMake(CGRectGetMaxX(_jamCapsule.frame) - 22, rowMid);
    _jamCapsule.layer.cornerRadius = 22;
    for (UIView *face in _jamCapsule.subviews) {
        face.bounds = CGRectMake(0, 0, kJamFace, kJamFace);
        face.center = CGPointMake(kJamInset + face.tag * kJamFaceStep + kJamFace / 2, 22);
    }
}

- (void)viewDidAppear:(BOOL)animated {
    [super viewDidAppear:animated];
    [self attachVideoIfShown];
    if (!_jamTimer) {
        __weak typeof(self) weakSelf = self;
        _jamTimer = [NSTimer scheduledTimerWithTimeInterval:2 repeats:YES block:^(NSTimer *timer) {
            if (!weakSelf) [timer invalidate];
            else if (weakSelf.viewIfLoaded.window) [weakSelf updateJam];
        }];
    }
    [self openLanded];
    // Animated's clip is looked up only while the page is in a window (SGRPlayerMotionPreview).
    if (_background == SGRPlayerBackgroundAnimated && !_motion) [self syncClipAnimated:YES];
    [self restartRest];
    // Up: turning the phone brings the landscape player (SystemTurn.m), as the Music app's does from iOS 27.3.
    SGRSystemTurnSetPage(self);
}

- (void)viewWillDisappear:(BOOL)animated {
    [super viewWillDisappear:animated];
    // A swipe close let go back ends the close too: a tap on the mini player waiting on it (SystemTabs.x's opened) is let
    // go, rather than left waiting to open the page at the next close.
    [self.transitionCoordinator animateAlongsideTransition:nil completion:^(id<UIViewControllerTransitionCoordinatorContext> context) {
        if (context.isCancelled) [NSNotificationCenter.defaultCenter postNotificationName:SGRSystemPlayerPageDidCloseNotification object:nil];
    }];
    // The page closes with its controls up, and the landscape screen does not outlive it, as it does not the player
    // (PlayerLyrics.x's viewWillDisappear:).
    [self setAlone:NO animated:NO];
    [self stopRest];
    // Never a pan above left off as the page goes: UIKit's swipe close among them.
    [_scrubber letGoOfPans];
    SGRPlayerVolumeRowLetGo(_volume);
    SGRSystemTurnSetLyrics(NO);
    SGRSystemTurnSetQueue(NO);
    SGRSystemTurnSetEmbedded(nil);
    SGRSystemTurnSetPage(nil);
}

// The cover for the turn onto the landscape player (SystemTurn.m): the holder, with its shadow, hidden while a copy
// flies. None while the clip stands in its place or nothing is in it.
- (void)landscapeLeftShowingLyrics:(BOOL)lyrics queue:(BOOL)queue {
    // At once: the turn back draws the page next.
    [UIView performWithoutAnimation:^{
        if (queue) [self setQueueOpen:YES];
        else if (lyrics && SGRPlayerLyricsAvailable()) [self setLyricsOpen:YES];
        else {
            [self setQueueOpen:NO];
            [self setLyricsOpen:NO];
        }
        [self.view layoutIfNeeded];
    }];
}

- (void)viewDidDisappear:(BOOL)animated {
    [super viewDidDisappear:animated];
    // The video back in the bar once the page has gone, not as a close starts: a swipe begun and let go back is a close
    // cancelled, the page stays, and the video handed back at its start was gone from it (its owner, 2026-11-10: "if i
    // slightly swipe on the whole page it breaks").
    [self returnVideo];
    // The close is over: a tap on the mini player during it opens the page now (SystemTabs.x's opened). A turn later, so
    // UIKit has finished with this presentation.
    dispatch_async(dispatch_get_main_queue(), ^{
        [NSNotificationCenter.defaultCenter postNotificationName:SGRSystemPlayerPageDidCloseNotification object:nil];
    });
    [_timer invalidate];
    _timer = nil;
    // The page goes only by closing (a new one is made for each open: SystemTabs.x), so this is where it was left.
    sgr_lyricsLeftOpen = _lyricsOpen;
}

- (void)viewDidLayoutSubviews {
    [super viewDidLayoutSubviews];
    CGRect bounds = self.view.bounds;
    // Opened with the phone already sideways, or a size that came without a transition: the landscape player as it is.
    [self syncLandscapeFor:bounds.size coordinator:nil];
    if (_landscapeScreen) {
        _landscapeScreen.view.frame = bounds;
        [self.view bringSubviewToFront:_landscapeScreen.view];
    }
    UIEdgeInsets safe = self.view.safeAreaInsets;
    CGFloat width = bounds.size.width, height = bounds.size.height, inner = MAX(0, width - 2 * kMargin);
    _backdrop.frame = bounds;
    _blur.frame = bounds;
    _shade.frame = bounds;
    _field.frame = bounds;
    _field.backdropHeight = height;
    _motion.frame = bounds;
    _visualiser.frame = bounds;

    // The header: the album alone. No close button (its owner, 2026-11-06: the chevron off; the page closes with a swipe
    // down, as the Music app's), and the ⋯ beside the star in the title's row, below.
    CGFloat top = safe.top + kHeaderDrop, button = SGRGlassCircleSize;
    _close.frame = CGRectMake(kHeaderSide, top, button, button);
    _close.hidden = YES;
    _context.frame = CGRectMake(kHeaderSide + button + 8, top, MAX(0, width - 2 * (kHeaderSide + button + 8)), button);
    CGFloat headerBottom = top + button;

    // From the bottom up: the row of three with the route line under it, the volume, the controls, the progress, the
    // two lines. The row stands where the redesigned player's footer puts it (PlayerFooter.x's SGRPlayerLowerRow).
    CGFloat rowMid = height - MAX(safe.bottom + kRowAboveSafeArea, kRowMinBottom);
    NSArray<UIView *> *row = @[_lyrics, _route, _queue];
    static const CGFloat shares[] = {0.2, 0.5, 0.8};
    for (NSUInteger i = 0; i < row.count; i++) {
        row[i].bounds = CGRectMake(0, 0, 44, 44);
        row[i].center = CGPointMake(round(width * shares[i]), rowMid);
    }
    _queueBubble.center = _lyricsBubble.center = CGPointMake(22, 22);
    [self layoutJamAround:rowMid];
    CGFloat lineHeight = ceil(_routeLine.font.lineHeight);
    _routeLine.frame = CGRectMake(24, round(rowMid + kRouteLineDrop - lineHeight / 2), MAX(0, width - 48), lineHeight);
    CGFloat spacing = controlsSpacing();
    CGFloat volumeMid = rowMid - round(kVolumeAboveRow * spacing);
    _volume.frame = CGRectMake(kMargin, volumeMid - 16, inner, 32);
    CGFloat controlsMid = _volumeOff ? rowMid - round(kControlsAboveRowAlone * spacing) : volumeMid - round(kControlsAboveVolume * spacing);
    _play.bounds = CGRectMake(0, 0, 64, 64);
    _previous.bounds = _next.bounds = CGRectMake(0, 0, 56, 56);
    _shuffle.bounds = _repeat.bounds = CGRectMake(0, 0, 44, 44);
    _shuffle.center = CGPointMake(kMargin + 12, controlsMid);
    _previous.center = CGPointMake(round(width / 2 - inner * kSkipShare), controlsMid);
    _play.center = CGPointMake(width / 2, controlsMid);
    _next.center = CGPointMake(round(width / 2 + inner * kSkipShare), controlsMid);
    _repeat.center = CGPointMake(width - kMargin - 12, controlsMid);
    CGFloat timesHeight = ceil(_elapsed.font.lineHeight), timesMid = controlsMid - round(kTimesAboveControls * spacing), timesY = round(timesMid - timesHeight / 2);
    _elapsed.frame = CGRectMake(kMargin, timesY, inner / 2, timesHeight);
    _remaining.frame = CGRectMake(kMargin + inner / 2, timesY, inner / 2, timesHeight);
    CGFloat scrubberY = round(timesMid - kScrubberAboveTimes - kScrubberHeight / 2);
    _scrubber.frame = CGRectMake(kMargin, scrubberY, inner, kScrubberHeight);
    CGFloat titleHeight = ceil(_title.font.lineHeight), artistHeight = ceil(_artist.font.lineHeight);
    CGFloat artistY = scrubberY - 14 - artistHeight, titleY = artistY - titleHeight;

    // The cover takes the room left between the header and the title, as wide as the margins allow.
    CGFloat roomTop = headerBottom + 20, room = MAX(0, titleY - 28 - roomTop);
    CGFloat side = floor(MIN(inner, room));
    CGSize art = CGSizeMake(side, side);
    // A music video: 16:9, as wide as the page, edge to edge, and no taller than the room (its owner, 2026-11-09: "shrink to
    // the size of the video and make it as big as possible"), from the moment the track is a video, before Spotify's surface
    // is in. One shape throughout, not the picture's own: that one is read off the area it is laid out in, and following it
    // the area jumped between sizes as the video came in (its owner, 2026-11-10: "portrait music videos dont need to resize").
    BOOL video = _videoSurface != nil || _wantsVideo;
    _videoBlank.hidden = !video;
    if (video) {
        CGFloat aspect = 16.0 / 9.0;
        CGFloat w = width, h = round(w / aspect);
        if (h > room) {
            h = floor(room);
            w = round(h * aspect);
        }
        art = CGSizeMake(w, h);
    }
    CGFloat corner = video ? 0 : SGRRadiusArtwork;
    _coverHolder.bounds = CGRectMake(0, 0, art.width, art.height);
    _coverHolder.center = CGPointMake(width / 2, round(roomTop + room / 2));
    if (_cover.layer.cornerRadius != corner) _cover.layer.cornerRadius = corner;
    if (!CGRectEqualToRect(_shadowBounds, _coverHolder.bounds)) {
        _shadowBounds = _coverHolder.bounds;
        _coverHolder.layer.shadowPath = [UIBezierPath bezierPathWithRoundedRect:_shadowBounds cornerRadius:corner].CGPath;
    }
    _cover.frame = _coverHolder.bounds;
    [_videoKeeper keep];

    // With the lyrics up, the Music app's top row: the cover as a thumbnail under the header with the title and artist
    // beside it, and the lines from there down to the progress. The stage keeps its place either way, so the lines come
    // and go where they stand. On their own, the lines take the whole safe area, kAloneInset in at both ends (with
    // Keep the title, from where they stood down): aloneStage.
    CGRect thumb = CGRectMake(kMargin, headerBottom + 16, kThumbSide, kThumbSide);
    CGFloat stageTop = CGRectGetMaxY(thumb) + 8;
    CGRect stage = CGRectMake(0, stageTop, width, MAX(0, scrubberY - 8 - stageTop));
    _stage.frame = _alone ? [self aloneStageFrom:stage] : stage;
    // Laid out again when only the stage moved, so a scroll by hand keeps its lines where they are (SGRKaraokeView.m).
    [_lines setNeedsLayout];
    _lyricsNote.frame = CGRectInset(_stage.bounds, kMargin, 0);
    _lyricsSpinner.frame = _stage.bounds;
    // While a track is moved the queue runs down to the foot of the screen, the controls away (setQueueDragging:).
    // The queue runs down behind the controls, its last track resting just above them (SGRSystemQueueView's
    // controlsHeight), so a drag that puts the controls away resizes nothing and the list never jumps (its owner,
    // 2026-11-03).
    // It starts at the thumbnail row's top, that row's room above its chips, which its scroll pushes up into as the Music
    // app's queue pushes its row out (its owner's recording, 2026-11-06).
    CGFloat headTop = CGRectGetMinY(thumb) - 6;
    CGRect whole = CGRectMake(0, headTop, width, MAX(0, height - safe.bottom - headTop));
    _queueView.controlsHeight = MAX(0, CGRectGetMaxY(whole) - CGRectGetMaxY(stage));
    _queueView.frame = whole;
    _queueView.headRoom = stageTop - headTop;
    [_queueView setControlsCover:_queueDragging ? 0 : _queueView.controlsHeight animated:self.view.window != nil];
    // The add button at the trailing margin, its glyph's edge on it, centered on the title and artist; they end before it.
    // The ⋯ at the trailing margin, the star before it, as the Music app's row has them (its owner, 2026-11-06).
    CGFloat addInset = (kAddSide - kAddGlyph) / 2, moreRight = width - kMargin + (kAddSide - 20) / 2;
    CGFloat addRight = moreRight - kAddSide + 4;
    // Switch to Video and the DJ's button leftwards of the star, a star's step apart.
    CGFloat nextRight = _add.hidden ? addRight : addRight - kAddSide + 4;
    CGFloat switchRight = nextRight;
    if (!_switchVideo.hidden) nextRight -= kAddSide - 4;
    CGFloat djRight = nextRight;
    if (!_djButton.hidden) nextRight -= kAddSide - 4;
    CGFloat textRight = nextRight + addInset - 8;
    BOOL topRow = _lyricsOpen || _queueOpen;
    CGFloat textX = topRow ? CGRectGetMaxX(thumb) + kThumbGap : kMargin;
    CGFloat textY = topRow ? round(CGRectGetMidY(thumb) - (titleHeight + artistHeight) / 2) : titleY;
    CGFloat textWidth = MAX(0, textRight - textX);
    // By bounds and center, not frame: the queue's push moves the block by its transform, which a frame set over it undid,
    // leaving the title behind as History pushed the row down (its owner's recording, 2026-11-06).
    CGRect titleRect = CGRectMake(textX - kTitleFade, textY, textWidth + 2 * kTitleFade, titleHeight + artistHeight);
    _titleBlock.bounds = (CGRect){CGPointZero, titleRect.size};
    _titleBlock.center = CGPointMake(CGRectGetMidX(titleRect), CGRectGetMidY(titleRect));
    _title.frame = _besideTitle.frame = CGRectMake(0, 0, textWidth + kTitleFade, titleHeight);
    _artist.frame = _besideArtist.frame = CGRectMake(0, titleHeight, textWidth + kTitleFade, artistHeight);
    [CATransaction begin];
    [CATransaction setDisableActions:YES];
    _titleFade.frame = _titleBlock.bounds;
    CGFloat titleEdge = _titleBlock.bounds.size.width > 0 ? MIN(0.25, kTitleFade / _titleBlock.bounds.size.width) : 0;
    if (titleEdge != _titleEdge || !_titleFade.locations) {
        _titleEdge = titleEdge;
        _titleFade.locations = @[@0, @(titleEdge), @(1 - titleEdge), @1];
    }
    [CATransaction commit];
    _add.bounds = CGRectMake(0, 0, kAddSide, kAddSide);
    CGFloat titleMid = round(textY + (titleHeight + artistHeight) / 2);
    _add.center = CGPointMake(addRight - kAddSide / 2, titleMid);
    _more.bounds = CGRectMake(0, 0, kAddSide, kAddSide);
    _more.center = CGPointMake(moreRight - kAddSide / 2, titleMid);
    _speed.bounds = CGRectMake(0, 0, 56, 44);
    _speed.center = _shuffle.center;
    _switchVideo.bounds = _djButton.bounds = CGRectMake(0, 0, kAddSide, kAddSide);
    _switchVideo.center = CGPointMake(switchRight - kAddSide / 2, titleMid);
    _djButton.center = CGPointMake(djRight - kAddSide / 2, titleMid);
    _thumb = thumb;
    // The thumbnail is the cover moved and scaled by its transform, so its shadow and corners travel with it; the corners
    // are given back the thumbnail's radius at that scale.
    CGFloat scale = side > 0 ? kThumbSide / side : 1;
    _cover.layer.cornerRadius = topRow ? SGRRadiusThumb / scale : SGRRadiusArtwork;
    _coverHolder.transform = [self coverTransform];
    [self placeHeadPush];
    // The hold for 2× on the cover, as on the player's.
    SGRPlayerAttachCoverHold(_coverHolder);
    [self placeDJRing];
}

// The thumbnail while the lyrics are up; otherwise full size, smaller while paused (held at full size under Reduce
// Motion, as in the redesigned player).
- (CGAffineTransform)coverTransform {
    CGFloat side = _coverHolder.bounds.size.width;
    if ((_lyricsOpen || _queueOpen) && side > 0) {
        CGFloat scale = kThumbSide / side;
        CGPoint center = _coverHolder.center;
        CGFloat push = _queueOpen ? _headPush : 0;
        CGAffineTransform move = CGAffineTransformMakeTranslation(round(CGRectGetMidX(_thumb) - center.x), round(CGRectGetMidY(_thumb) - center.y - push));
        return CGAffineTransformScale(move, scale, scale);
    }
    CGFloat scale = _pausedShown && !SGRReduceMotion() ? kPausedScale : 1;
    return CGAffineTransformMakeScale(scale, scale);
}


#pragma mark - the header's ⋯

// A pull-down button, the HIG's, as the redesigned player's ⋯ is (ContextMenu.x's SGRMenuFront): the menu opens on touch
// down, made afresh as it opens. The glyph presses as the footer's do.
- (UIButton *)makeMoreButton {
    UIButton *more = [UIButton buttonWithType:UIButtonTypeCustom];
    more.showsMenuAsPrimaryAction = YES;
    more.overrideUserInterfaceStyle = UIUserInterfaceStyleDark;
    more.accessibilityLabel = @"More";
    SGRGlyphView *glyph = [[SGRGlyphView alloc] initWithSymbol:@"ellipsis" pointSize:17 weight:UIImageSymbolWeightRegular];
    glyph.tintColor = SGRPrimary();
    glyph.userInteractionEnabled = NO;
    glyph.autoresizingMask = UIViewAutoresizingFlexibleLeftMargin | UIViewAutoresizingFlexibleRightMargin | UIViewAutoresizingFlexibleTopMargin
                           | UIViewAutoresizingFlexibleBottomMargin;
    more.frame = CGRectMake(0, 0, SGRGlassCircleSize, SGRGlassCircleSize);
    glyph.bounds = (CGRect){CGPointZero, glyph.intrinsicContentSize};
    glyph.center = CGPointMake(SGRGlassCircleSize / 2, SGRGlassCircleSize / 2);
    [more addSubview:glyph];
    SGRPlayerPressGlyphOnTouch(more);
    __weak typeof(self) weakSelf = self;
    UIDeferredMenuElement *items = [UIDeferredMenuElement elementWithUncachedProvider:^(void (^completion)(NSArray<UIMenuElement *> *)) {
        typeof(self) me = weakSelf;
        completion(me ? [me menuItems] : @[]);
    }];
    more.menu = [UIMenu menuWithChildren:@[items]];
    return more;
}

static UIMenu *inlineGroup(NSArray<UIMenuElement *> *children) {
    return [UIMenu menuWithTitle:@"" image:nil identifier:nil options:UIMenuOptionsDisplayInline children:children];
}

// The ⋯, from its foot: a row of Share, Sleep Timer and Music Video (or Song); DJ X; a section of Go to Album, Go to
// Artist, Go to Artist Concerts and (with the star off) Add to Playlist; the Artwork submenu and More, with Speed, Pitch
// & Reverb and Lyrics Source, at the top (its owner, 2026-11-06 and 2026-11-10). Before (its
// owner's screenshots and picks, 2026-11-02). Spotify's player is not behind the page, so its sheet's rows are not
// read here. Add to Playlist, Add to Queue, Start a Jam, SongDNA and Song credits come from that sheet alone: its links
// are refused and its mini player has no menu to read (the phone's log, 2026-11-02), so they are left out for now.
- (NSArray<UIMenuElement *> *)menuItems {
    return [self menuItemsFrom:_more presenter:self landscape:NO changed:nil];
}

// The landscape player's ⋯ (SystemLandscape.m) shows the same, from its own button and screen: Share and the sheets
// come up over it and Go to opens once the page has turned back.
- (NSArray<UIMenuElement *> *)landscapeMenuItemsFrom:(UIView *)anchor presenter:(UIViewController *)presenter changed:(void (^)(void))changed {
    // Its ⋯ is high on the screen, so its menu opens downwards and is read from the top: the same groups the other way
    // round, so it reads as the page's does (the code review, 2026-11-10).
    return [self menuItemsFrom:anchor presenter:presenter landscape:YES changed:changed].reverseObjectEnumerator.allObjects;
}

- (NSArray<UIMenuElement *> *)menuItemsFrom:(UIView *)anchor presenter:(UIViewController *)presenter landscape:(BOOL)landscape
                                    changed:(void (^)(void))landscapeChanged {
    SPTPlayerTrack *track = isTrack(SGPlayerState().track) ? SGPlayerState().track : nil;
    NSString *uri = SGURIString(track.URI);
    NSArray<NSString *> *parts = [uri componentsSeparatedByString:@":"];
    NSString *kind = parts.count == 3 ? parts[1] : nil;
    BOOL song = [kind isEqualToString:@"track"];
    __weak typeof(self) weakSelf = self;
    NSMutableArray<UIMenuElement *> *menu = [NSMutableArray array];

    // The menu opens upwards from the ⋯, so its first group is at the foot and its last at the top. At the foot a row of
    // Share and Sleep Timer; over it one section of the Go tos, Album, Artist and Concerts, with Add to Playlist when the
    // star is off the page (its owner, 2026-11-10: "share and sleep timer" in the row, the star and Add to Playlist doing
    // the same thing, the Go tos and Add to Playlist in one section).
    NSMutableArray<UIMenuElement *> *actions = [NSMutableArray array];
    if ((song || [kind isEqualToString:@"episode"]) && parts[2].length) {
        NSURL *link = [NSURL URLWithString:[NSString stringWithFormat:@"https://open.spotify.com/%@/%@", kind, parts[2]]];
        [actions addObject:[UIAction actionWithTitle:@"Share" image:[UIImage systemImageNamed:@"square.and.arrow.up"] identifier:nil
                                             handler:^(UIAction *action) { [weakSelf share:link from:presenter]; }]];
    }
    [actions addObject:[self sleepTimerMenu]];
    // Music Video / Song: a song and its music video are two tracks, each naming the other in its metadata
    // (video_association on the song: the owner's log, 2026-11-10). Spotify's own switch goes through its playback
    // settings service, out of reach, so the other is played instead, from the same place, and the context goes on after
    // it. In the row (its owner, 2026-11-10: "move music video into the bottom of the menu").
    NSString *otherURI = otherVersionURI(track);
    if (otherURI.length) {
        BOOL toVideo = !isVideoTrack(track);
        [actions addObject:[UIAction actionWithTitle:toVideo ? @"Music\nVideo" : @"Song"
                                               image:[UIImage systemImageNamed:toVideo ? @"music.note.tv" : @"music.note"] identifier:nil
                                             handler:^(UIAction *action) { SGRSystemSwitchTo(otherURI, toVideo); }]];
    }
    UIMenu *row = [UIMenu menuWithTitle:@"" image:nil identifier:nil options:UIMenuOptionsDisplayInline children:actions];
    row.preferredElementSize = UIMenuElementSizeMedium;
    [menu addObject:row];

    // The AI DJ, next up (its owner, 2026-11-10): Spotify's own DJ sheet, what the DJ button on its player opens ("What can
    // I play for you?", a request typed or spoken, Let DJ pick), by the one DJ link Spotify takes from outside (its owner's
    // link tests, 2026-11-09). Spotify's song menu and its video settings were tried the same way and refused. With the
    // DJ's icon, as its button.
    [menu addObject:inlineGroup(@[[UIAction actionWithTitle:@"DJ X" image:SGRDJGlyphImage(20) identifier:nil
                                      handler:^(UIAction *action) { SGRSystemOpenDJ(); }]])];

    // The album from the track's metadata (album_uri, beside the album_title the header reads; a key of the player's
    // metadata in the 9.1.90 binary) and the artist from the track itself (Headers/SPTPlayer.h's artistURI).
    NSMutableArray<UIMenuElement *> *goTos = [NSMutableArray array];
    id album = track.metadata[@"album_uri"];
    NSString *albumURI = [album isKindOfClass:NSString.class] && [album hasPrefix:@"spotify:album:"] ? album : nil;
    if (albumURI && !SGEnabled(SGRKeyPlayerTitleAlbum)) {
        [goTos addObject:[UIAction actionWithTitle:@"Go to Album" image:[UIImage systemImageNamed:@"square.stack"] identifier:nil
                                           handler:^(UIAction *action) { [weakSelf closeAndOpen:albumURI landscape:landscape]; }]];
    }
    NSString *artistURI = SGURIString(track.artistURI);
    if ([artistURI hasPrefix:@"spotify:artist:"]) {
        [goTos addObject:[UIAction actionWithTitle:@"Go to Artist" image:[UIImage systemImageNamed:@"music.microphone"] identifier:nil
                                           handler:^(UIAction *action) { [weakSelf closeAndOpen:artistURI landscape:landscape]; }]];
        // The artist's concerts ("spotify:artist:%s%cconcerts" in the 9.1.90 binary), in the menu itself (its owner,
        // 2026-11-06: no More submenu).
        NSString *concerts = [artistURI stringByAppendingString:@":concerts"];
        [goTos addObject:[UIAction actionWithTitle:@"Go to Artist Concerts" image:[UIImage systemImageNamed:@"ticket"] identifier:nil
                                           handler:^(UIAction *action) { [weakSelf closeAndOpen:concerts landscape:landscape]; }]];
    }
    // Add to Playlist: Spotify's own sheet, by its link with the song as `entities`, the parameter its page requires
    // ("ATP needs 'entities', 'listEntity', 'transitionBlob', or 'defaultSaveLocationCategory'" in the 9.1.90 binary;
    // uris= was taken and showed nothing: its owner's link tests, 2026-11-09).
    if (song && SGHidden(SGRKeyPlayerHideAdd)) {
        NSString *entities = [uri stringByAddingPercentEncodingWithAllowedCharacters:NSCharacterSet.alphanumericCharacterSet];
        NSString *link = [@"spotify:add-to-playlist?entities=" stringByAppendingString:entities];
        [goTos addObject:[UIAction actionWithTitle:@"Add to Playlist" image:[UIImage systemImageNamed:@"text.badge.plus"] identifier:nil
                                           handler:^(UIAction *action) { SGOpenSpotifyURI([NSURL URLWithString:link]); }]];
    }
    if (goTos.count) [menu addObject:inlineGroup(goTos)];

    // The player's own: the backgrounds.
    void (^changed)(void) = ^{
        [weakSelf reloadBackgroundAnimated:YES];
        if (landscapeChanged) landscapeChanged();
    };
    NSMutableArray<UIMenuElement *> *own = [NSMutableArray array];
    UIMenu *artwork = SGRPlayerMenuArtwork(changed);
    if (artwork) [own addObject:artwork];
    // More: Speed, Pitch & Reverb and Lyrics Source (the player's page items, Player.h's SGRPlayerMenuPageItems).
    NSArray<UIMenuElement *> *more = SGRPlayerMenuPageItems(anchor, changed);
    if (more.count) [own addObject:[UIMenu menuWithTitle:@"More" image:[UIImage systemImageNamed:@"ellipsis.circle"] identifier:nil options:0 children:more]];
    if (own.count) [menu addObject:inlineGroup(own)];
    return menu;
}

// The mod's sleep timer (Shared/Player/SleepTimer.h), what it is set to under its name.
- (UIMenu *)sleepTimerMenu {
    SGSleepTimerMode mode = SGSleepTimerCurrentMode();
    NSMutableArray<UIMenuElement *> *items = [NSMutableArray array];
    for (NSNumber *minutes in @[@5, @10, @15, @30, @45, @60]) {
        NSString *title = minutes.integerValue == 60 ? @"1 Hour" : [NSString stringWithFormat:@"%@ Minutes", minutes];
        [items addObject:[UIAction actionWithTitle:title image:nil identifier:nil handler:^(UIAction *action) {
            SGSetSleepTimer(SGSleepTimerAtTime, minutes.doubleValue * 60);
        }]];
    }
    UIAction *track = [UIAction actionWithTitle:@"End of Song" image:nil identifier:nil handler:^(UIAction *action) { SGSetSleepTimer(SGSleepTimerEndOfTrack, 0); }];
    if (mode == SGSleepTimerEndOfTrack) track.state = UIMenuElementStateOn;
    UIAction *album = [UIAction actionWithTitle:@"End of Album or Playlist" image:nil identifier:nil handler:^(UIAction *action) { SGSetSleepTimer(SGSleepTimerEndOfAlbum, 0); }];
    if (mode == SGSleepTimerEndOfAlbum) album.state = UIMenuElementStateOn;
    [items addObjectsFromArray:@[track, album]];
    if (mode != SGSleepTimerOff) {
        [items addObject:[UIAction actionWithTitle:@"Turn Off Timer" image:[UIImage systemImageNamed:@"xmark"] identifier:nil
                                           handler:^(UIAction *action) { SGSetSleepTimer(SGSleepTimerOff, 0); }]];
    }
    UIMenu *menu = [UIMenu menuWithTitle:@"Sleep\nTimer" image:[UIImage systemImageNamed:@"moon.zzz"] identifier:nil options:0 children:items];
    NSDate *end = SGSleepTimerEnd();
    if (mode == SGSleepTimerAtTime && end) {
        NSInteger left = MAX(0, (NSInteger)ceil(end.timeIntervalSinceNow / 60));
        menu.subtitle = [NSString stringWithFormat:@"%ld min left", (long)left];
    } else if (mode == SGSleepTimerEndOfTrack) menu.subtitle = @"End of song";
    else if (mode == SGSleepTimerEndOfAlbum) menu.subtitle = @"End of album or playlist";
    return menu;
}

- (void)share:(NSURL *)link {
    [self share:link from:self];
}

- (void)share:(NSURL *)link from:(UIViewController *)presenter {
    UIActivityViewController *share = [[UIActivityViewController alloc] initWithActivityItems:@[link] applicationActivities:nil];
    // A sheet from the foot of the screen, as the Music app's Share is (its owner's screenshot, 2026-11-02), not a
    // popover off the ⋯: no anchor on a phone, the screen's middle elsewhere, where a popover needs one.
    if (self.traitCollection.userInterfaceIdiom == UIUserInterfaceIdiomPad) {
        share.popoverPresentationController.sourceView = self.view;
        share.popoverPresentationController.sourceRect = CGRectMake(CGRectGetMidX(self.view.bounds), CGRectGetMaxY(self.view.bounds), 1, 1);
    }
    SGPresentDark(share);
    [presenter presentViewController:share animated:YES completion:nil];
}

// A page of Spotify's opens in its navigation under the page, so the page closes first, as the Music app's player does
// for Go to Album.
// The album of the track playing, from the title (SGRKeyPlayerTitleAlbum): the album_uri the ⋯'s Go to Album reads.
- (void)titleTapped {
    if (!SGEnabled(SGRKeyPlayerTitleAlbum)) return;
    id album = SGPlayerState().track.metadata[@"album_uri"];
    if ([album isKindOfClass:NSString.class] && [album hasPrefix:@"spotify:album:"]) [self closeAndOpen:album];
}

- (void)closeAndOpen:(NSString *)uri landscape:(BOOL)landscape {
    if (!landscape) {
        [self closeAndOpen:uri];
        return;
    }
    // From the landscape player: turned back to the page first, then closed as from the page.
    SGRSystemTurnBack();
    __weak typeof(self) weakSelf = self;
    dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(0.7 * NSEC_PER_SEC)), dispatch_get_main_queue(), ^{
        [weakSelf closeAndOpen:uri];
    });
}

- (void)closeAndOpen:(NSString *)uri {
    [self dismissViewControllerAnimated:YES completion:^{ SGOpenSpotifyURI([NSURL URLWithString:uri]); }];
}

#pragma mark - Switch to Video and the DJ beside the star


// Whether the DJ is what plays: its playlist the context (Shared/AdBlock/DJ.x), the context called DJ, or the DJ talking.
static BOOL djPlaying(SPTPlayerState *state, SPTPlayerTrack *track) {
    NSString *context = SGURIString(state.contextURI);
    return [context containsString:@"37i9dQZF1EYkqdzj48dyYq"] || [contextTitle(state, track) isEqualToString:@"DJ"]
        || (track && isNarration(track));
}

// Which of the two show for what plays now, shared with the landscape player (SystemPlayer.h).
void SGRSystemRowButtons(BOOL *switchShown, BOOL *djShown, BOOL *video) {
    SPTPlayerState *state = SGPlayerState();
    SPTPlayerTrack *track = isTrack(state.track) ? state.track : nil;
    BOOL dj = djPlaying(state, track);
    // Not both: while the DJ's button shows, the switch stays in the ⋯ menu (its owner, 2026-11-10).
    if (switchShown) *switchShown = track && !dj && !SGHidden(SGKeyHideVideoSwitch) && otherVersionURI(track).length > 0;
    if (djShown) *djShown = dj;
    if (video) *video = track && isVideoTrack(track);
}

void SGRSystemSwitchVideo(void) {
    SPTPlayerTrack *track = isTrack(SGPlayerState().track) ? SGPlayerState().track : nil;
    NSString *other = track ? otherVersionURI(track) : nil;
    if (other.length) SGRSystemSwitchTo(other, !isVideoTrack(track));
}

void SGRSystemOpenDJ(void) {
    SGOpenSpotifyURI([NSURL URLWithString:@"spotify:internal:aidj:interactivity-container"]);
}

void SGRSystemSyncRowButtons(SGRGlyphButton *switchVideo, SGRGlyphButton *dj, UIView *layout) {
    BOOL switchShown, djShown, video;
    SGRSystemRowButtons(&switchShown, &djShown, &video);
    if (switchShown) {
        [switchVideo.glyph setSymbol:video ? @"music.note" : @"music.note.tv" animated:NO];
        switchVideo.accessibilityLabel = video ? @"Song" : @"Music Video";
    }
    if (switchVideo.hidden == switchShown || dj.hidden == djShown) {
        switchVideo.hidden = !switchShown;
        dj.hidden = !djShown;
        [layout setNeedsLayout];
    }
}

- (void)syncRowButtons {
    SGRSystemSyncRowButtons(_switchVideo, _djButton, self.view);
}

- (void)switchVideoTapped {
    SGRSystemSwitchVideo();
}

#pragma mark - the add button

// The playing track's place in Liked Songs, from Spotify's collection state (Redesigned/Artist/Artist.h's
// SGRCollectionWatchURI, the state the artist page's Follow reads), watched from a track change on.
- (void)syncSaved {
    SPTPlayerTrack *track = isTrack(SGPlayerState().track) ? SGPlayerState().track : nil;
    NSString *uri = SGURIString(track.URI);
    BOOL saveable = [uri hasPrefix:@"spotify:track:"];
    BOOL shown = saveable && !SGHidden(SGRKeyPlayerHideAdd);
    if (_add.hidden == shown) {
        _add.hidden = !shown;
        [self.view setNeedsLayout];
    }
    if (!saveable) {
        _savedWatch = nil;
        _savedTrack = nil;
        return;
    }
    if (![uri isEqualToString:_savedTrack]) {
        _savedTrack = uri;
        __weak typeof(self) weakSelf = self;
        _savedWatch = SGRCollectionWatchURI([NSURL URLWithString:uri], ^{ [weakSelf syncSaved]; });
        [self showSaved:NO animated:NO];
    }
    BOOL saved = NO;
    if (SGRCollectionWatchSaved(_savedWatch, &saved)) [self showSaved:saved animated:_shownOnce];
}

- (void)showSaved:(BOOL)saved animated:(BOOL)animated {
    _savedShown = saved;
    [_add.glyph setSymbol:saved ? @"star.fill" : @"star" animated:animated && self.view.window];
    UIColor *tint = SGRPrimary();
    if (![_add.glyph.tintColor isEqual:tint]) _add.glyph.tintColor = tint;
    _add.accessibilityLabel = saved ? @"Remove from Liked Songs" : @"Add to Liked Songs";
}

// Spotify's add button saves to Liked Songs, with its own confirmation; this one does that, and takes the track out
// again from the filled star, where Spotify's opens its Add to playlist sheet, which nothing here can reach. The glyph turns at
// once and the collection's own answer follows.
- (void)toggleSaved {
    NSString *uri = _savedTrack;
    if (!uri) return;
    BOOL want = !_savedShown;
    if (!SGRCollectionSetSaved([NSURL URLWithString:uri], want)) return;
    SGPlayFeedback(SGFeedbackAdd);
    [self showSaved:want animated:YES];
}

#pragma mark - the route line

- (void)syncRouteLine {
    NSString *text = SGRPlayerOutputName() ?: @"";
    if (![_routeLine.text isEqualToString:text]) _routeLine.text = text;
    _routeLine.hidden = text.length == 0;
}

#pragma mark - the background

// The redesigned player's background on the Player page's choice (Player.h's SGRPlayerBackground), drawn as the Player
// page's showcase draws it (PlayerSettings.m): Colors and Fluid are the player's field, and the Visualizer the hills over
// Fluid held still (SGRPlayerVisualiserPreview). Animated is Fluid with the playing track's clip over it once there is
// one (syncClip), as in the redesigned player (PlayerMotion.x). Still is the page's own blurred cover, the look that
// choice stands for. The field and the hills move only under the field's own rules (a window, Spotify in front, Reduce
// Motion and Low Power Mode off), and a paused song, the clip or the hills hold the field still. The ⋯ switches between
// Fluid, Animated and the Visualizer, and the page follows at once.
- (void)reloadBackgroundAnimated:(BOOL)animated {
    SGRPlayerBackgroundKind kind = SGRPlayerBackground();
    if (kind != _background || !_backgroundSet) {
        _background = kind;
        _backgroundSet = YES;
        _field.hidden = kind == SGRPlayerBackgroundStill;
        _field.flows = kind == SGRPlayerBackgroundColours;
        _field.fluid = kind >= SGRPlayerBackgroundFluid;
        if (kind != SGRPlayerBackgroundVisualiser) {
            [self fadeOut:_visualiser animated:animated];
            _visualiser = nil;
        } else if (!_visualiser) {
            _visualiser = SGRPlayerVisualiserPreview();
            _visualiser.userInteractionEnabled = NO;
            _visualiser.hidden = _landscapeScreen != nil;
            _visualiser.frame = self.view.bounds;
            [self.view insertSubview:_visualiser aboveSubview:_field];
            [self fadeIn:_visualiser animated:animated];
        }
    }
    [self syncClipAnimated:animated];
    [self syncFieldHeld];
    [self blurBackground:_lyricsOpen || _queueOpen animated:NO];
}

// Animated's clip, as the redesigned player keeps its own (PlayerMotion.x): Fluid while the track has none, while it is
// looked up or after none was found, the clip crossing in over it once it is in, and on a skip Fluid again until the
// next track's is ready. The clip is the Player page's preview of the playing track's (SGRPlayerMotionPreview: the
// player's own clip when it is this track's, else one looked up while the page is in a window), asked again on every
// track and whenever the player's clip comes or goes (SGRPlayerMotionDidChangeNotification).
- (void)syncClipAnimated:(BOOL)animated {
    NSString *track = SGShownTrackNow().uri;
    // None on a music video: the picture is the page's then, and the clip went over it (its owner, 2026-11-10: Fluid
    // under music videos).
    BOOL wanted = _background == SGRPlayerBackgroundAnimated && track && !_wantsVideo;
    if (wanted && _motion && [track isEqualToString:_motionTrack]) return;
    UIView *clip = nil;
    if (wanted) {
        __weak typeof(self) weakSelf = self;
        void (^arrived)(void) = !self.view.window ? nil : ^{ [weakSelf syncClipAnimated:YES]; };
        clip = SGRPlayerMotionPreview(arrived);
    }
    if (!clip && !_motion) return;
    // On a skip the last track's clip stays up for a moment while the new one's is looked up, and the new one crosses in
    // over it, rather than the cover and Fluid showing between them (its owner's recording, 2026-11-02: the next clip
    // came a tenth of a second to a second later). A track with none, or one too slow, has Fluid after kClipHold.
    if (!clip && wanted && _motion && ![track isEqualToString:_motionTrack] && !SGRPlayerMotionNoneFor(track)) {
        CFTimeInterval now = CACurrentMediaTime();
        if (![track isEqualToString:_clipHoldTrack]) {
            _clipHoldTrack = [track copy];
            _clipHoldUntil = now + kClipHold;
            __weak typeof(self) weakSelf = self;
            dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(kClipHold * NSEC_PER_SEC)), dispatch_get_main_queue(), ^{
                [weakSelf syncClipAnimated:YES];
            });
        }
        if (now < _clipHoldUntil) return;
    }
    // Waited out or answered: a later skip back to this track waits afresh.
    _clipHoldTrack = nil;
    // The last track's clip, or a clip no longer wanted, goes; Fluid is under it.
    [self fadeOut:_motion animated:animated];
    _motion = clip;
    _motionTrack = clip ? track : nil;
    if (clip) {
        clip.userInteractionEnabled = NO;
        clip.hidden = _landscapeScreen != nil;
        clip.frame = self.view.bounds;
        [self.view insertSubview:clip aboveSubview:_field];
        [self fadeIn:clip animated:animated];
    }
    [self syncFieldHeld];
    [self blurBackground:_lyricsOpen || _queueOpen animated:NO];
    [self syncCoverShownAnimated:animated];
}

- (void)motionChanged {
    [self syncClipAnimated:self.view.window != nil];
}

// With the fade Reduce Motion keeps: only these views fade, as a crossfade of the whole page would take the blur over the
// Still backdrop with it.
- (void)fadeIn:(UIView *)view animated:(BOOL)animated {
    if (!view || !animated || !self.view.window) return;
    view.alpha = 0;
    SGRAnimate(SGRMotionFade, ^{ view.alpha = 1; }, nil);
}

- (void)fadeOut:(UIView *)view animated:(BOOL)animated {
    if (!view) return;
    if (!animated || !self.view.window) {
        [view removeFromSuperview];
        return;
    }
    SGRAnimate(SGRMotionFade, ^{ view.alpha = 0; }, ^(BOOL finished) { [view removeFromSuperview]; });
}

// The cover gives way to a clip, as the redesigned player's does (PlayerMotion.x's setCoverShown, a fade over
// SGRCrossfade): hidden while a clip plays, back when there is none. With the lyrics up the thumbnail stays over the
// clip, as the player's does (PlayerLyrics.x keeps its thumbnail shown with the lyrics open). On their own, the lines
// hide it as they hide the rest (fadingViews).
- (void)syncCoverShownAnimated:(BOOL)animated {
    BOOL shown = (!_motion || _lyricsOpen || _queueOpen) && !(_alone && SGRLyricsHideMode() != SGRLyricsHideControls)
        && !(_narrating && !_lyricsOpen && !_queueOpen);
    CGFloat alpha = shown ? 1 : 0;
    if (_coverHolder.alpha == alpha) return;
    UIView *cover = _coverHolder;
    if (animated && self.view.window) SGRAnimate(SGRMotionFade, ^{ cover.alpha = alpha; }, nil);
    else cover.alpha = alpha;
}

- (void)syncFieldHeld {
    BOOL held = !SGPlayerState() || SGPlayerState().isPaused || _motion != nil || _visualiser != nil || _landscapeScreen != nil;
    if (_field.motionHeld != held) _field.motionHeld = held;
}

// The clip and the hills blur behind the lyrics, as in the redesigned player (PlayerMotion.x and PlayerVisualiser.m:
// -setBlurred:animated:, which both of the previews' views have).
- (void)blurBackground:(BOOL)blurred animated:(BOOL)animated {
    SEL blur = NSSelectorFromString(@"setBlurred:animated:");
    for (UIView *view in @[_motion ?: NSNull.null, _visualiser ?: NSNull.null]) {
        if (![view respondsToSelector:blur]) continue;
        ((void (*)(id, SEL, BOOL, BOOL))objc_msgSend)(view, blur, blurred, animated);
    }
}

#pragma mark - state

- (void)playerStateDidChange:(SPTPlayerState *)state {
    [self show:state];
    [self updateJam];
    // A pause brings the rest back and keeps it; playing again starts the clock (PlayerLyrics.x).
    if (!state || state.isPaused) {
        [self setAlone:NO animated:YES];
        [self stopRest];
    } else if (!_rest && !_alone) {
        [self restartRest];
    }
}

// Repeat is no change to the state's observers (PlayerState.x tells shuffle only), so the options are read at every report.
- (void)playerStateDidReport:(SPTPlayerState *)state {
    [self showOptions:state];
}

// A music video plays over the cover, as Spotify's player shows it (its owner, 2026-11-09). Its controls are the page's.
- (void)showVideo:(BOOL)on {
    BOOL changed = on != _wantsVideo;
    if (changed) [self.view setNeedsLayout];
    _wantsVideo = on;
    if (changed && self.isViewLoaded) [self syncClipAnimated:YES];
    // Black over the cover from the start, not the album's cover until the picture comes (its owner, 2026-11-10); the
    // surface goes over it.
    if (on && !_videoBlank) {
        _videoBlank = [[UIView alloc] initWithFrame:_cover.bounds];
        _videoBlank.backgroundColor = UIColor.blackColor;
        _videoBlank.autoresizingMask = UIViewAutoresizingFlexibleWidth | UIViewAutoresizingFlexibleHeight;
        _videoBlank.userInteractionEnabled = NO;
        [_cover insertSubview:_videoBlank atIndex:0];
    }
    _videoBlank.hidden = !on;
    if (!on) {
        [self returnVideo];
        return;
    }
    [self attachVideoIfShown];
}

// Spotify's video surfaces on screen.
static void collectSurfaces(UIView *view, NSMutableArray<UIView *> *found) {
    if ([NSStringFromClass(view.class) containsString:@"VideoSurface"]) [found addObject:view];
    for (UIView *sub in view.subviews) collectSurfaces(sub, found);
}

// The surface Spotify draws the video on for its now playing bar (identifier now-playing-bar), which is attached and drawing
// while a video plays (the owner's log, 2026-11-09); a surface of the mod's own was made and eligible but never attached,
// its manager out of reach. The redesign hides that bar, so its surface is borrowed: moved over the cover while the page
// shows the video, and put back where it was when the page closes or the video ends.
// Every surface a page has held, across pages: a page is made for each open, and one kept per page took a surface an
// earlier page had handed back for the next video's, dropping the attached one (the code review, 2026-11-10). Weak, so
// Spotify's discarded surfaces go.
static NSHashTable<UIView *> *usedSurfaces(void) {
    static NSHashTable<UIView *> *used;
    if (!used) used = [NSHashTable weakObjectsHashTable];
    return used;
}

// The bar's surfaces on screen (identifier now-playing-bar), oldest first as the views are laid out.
static NSArray<UIView *> *barVideoSurfaces(void) {
    NSMutableArray<UIView *> *surfaces = [NSMutableArray array];
    for (UIScene *scene in UIApplication.sharedApplication.connectedScenes) {
        if (![scene isKindOfClass:UIWindowScene.class]) continue;
        for (UIWindow *window in ((UIWindowScene *)scene).windows) collectSurfaces(window, surfaces);
    }
    return [surfaces filteredArrayUsingPredicate:[NSPredicate predicateWithBlock:^BOOL(UIView *surface, id bindings) {
        return [surface.description containsString:@"identifier:now-playing-bar"];
    }]];
}

// The attached one, else the first: the next video gets a surface of its own and the last one is let go (attached:0),
// which held, the next video never showed (the owner's two videos in a row, 2026-11-10).
static UIView *barVideoSurface(void) {
    NSArray<UIView *> *surfaces = barVideoSurfaces();
    for (UIView *surface in surfaces) if ([surface.description containsString:@"attached:1"]) return surface;
    return surfaces.firstObject;
}

- (void)attachVideoIfShown {
    // Only the page that is up: a page made ahead and never presented is in a window too, its cover laid out to nothing,
    // and taken into it the surface went to 0x0, Spotify let the video go and the picture stayed black (the phone's log,
    // 2026-11-10: two pages, the hidden one holding the surface).
    if (!_wantsVideo || _videoSurface || !self.viewIfLoaded.window || !self.presentingViewController || self.isBeingDismissed) return;
    if (_cover.bounds.size.width < 1 || _cover.bounds.size.height < 1) {
        [self.view setNeedsLayout];
        __weak typeof(self) weakSelf = self;
        dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(0.2 * NSEC_PER_SEC)), dispatch_get_main_queue(), ^{ [weakSelf attachVideoIfShown]; });
        return;
    }
    UIView *surface = _nextSurface.window ? _nextSurface : barVideoSurface();
    _nextSurface = nil;
    if (!surface) {
        // The bar may build its surface a moment after the video starts.
        __weak typeof(self) weakSelf = self;
        dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(0.5 * NSEC_PER_SEC)), dispatch_get_main_queue(), ^{ [weakSelf attachVideoIfShown]; });
        return;
    }
    _videoHome = surface.superview;
    _videoHomeFrame = surface.frame;
    _videoHomeMask = surface.autoresizingMask;
    // Laid out by its frame while it is held: Spotify's surface is an Auto Layout view, and moved into the cover with no
    // constraints of its own there a layout pass sized it to nothing, Spotify let the video go and every video after the
    // first stayed black (the phone's log, 2026-11-10: translatesAutoresizingMaskIntoConstraints 0, 0x0 once held).
    surface.translatesAutoresizingMaskIntoConstraints = YES;
    _videoSurface = surface;
    [usedSurfaces() addObject:surface];
    [_cover addSubview:surface];
    surface.autoresizingMask = UIViewAutoresizingFlexibleWidth | UIViewAutoresizingFlexibleHeight;
    // Black, not clear: Spotify attaches the video only to a surface it counts as visible, and a clear one went unattached
    // (eligibleForAttachment 0) and the next video never showed (2026-11-10). The cover is not to show round the picture
    // either (its owner, 2026-11-09).
    _videoHomeColor = surface.backgroundColor;
    surface.backgroundColor = UIColor.blackColor;
    // No tap on the picture to take it full screen (its owner, 2026-11-10: "i dont like the tap to open fullscreen");
    // turned sideways it fills the screen (SystemLandscape.m).
    [self setUpPictureInPictureFor:surface];
    _videoKeeper = [SGRFrameKeeper new];
    _videoKeeper.view = surface;
    for (NSString *key in @[@"frame", @"bounds", @"center"]) [surface addObserver:_videoKeeper forKeyPath:key options:0 context:NULL];
    [_videoKeeper keep];
    [UIView animateWithDuration:0.35 animations:^{
        [self.view setNeedsLayout];
        [self.view layoutIfNeeded];
    }];
}

// The landscape player holds the video while it is up (SystemLandscape.m); the keeper keeps it filling that holder.
- (UIView *)landscapeVideoSurface {
    return _videoSurface;
}

- (void)landscapeVideoReturned {
    UIView *surface = _videoSurface;
    if (!surface || surface.superview == _cover) return;
    [_cover addSubview:surface];
    surface.frame = _cover.bounds;
    if (self.isViewLoaded) [self.view setNeedsLayout];
}

#pragma mark - the video in Picture in Picture

// Picture in Picture from the surface's own drawing layer, when Spotify's renderer draws into an AVSampleBufferDisplayLayer
// (iOS's sample buffer Picture in Picture); its play, pause and skips go to Spotify's player.
- (void)setUpPictureInPictureFor:(UIView *)surface {
    if (_pip || !AVPictureInPictureController.isPictureInPictureSupported) return;
    AVSampleBufferDisplayLayer *layer = sampleLayerIn(surface.layer);
    if (!layer) return;
    AVPictureInPictureControllerContentSource *source = [[AVPictureInPictureControllerContentSource alloc] initWithSampleBufferDisplayLayer:layer playbackDelegate:self];
    _pip = [[AVPictureInPictureController alloc] initWithContentSource:source];
    _pip.delegate = self;
    _pip.canStartPictureInPictureAutomaticallyFromInline = YES;
    SGRSystemVideoSetPiP(YES, NO);
}

- (void)pictureInPictureControllerDidStartPictureInPicture:(AVPictureInPictureController *)controller {
    SGRSystemVideoSetPiP(YES, YES);
}

- (void)pictureInPictureControllerDidStopPictureInPicture:(AVPictureInPictureController *)controller {
    SGRSystemVideoSetPiP(_videoSurface != nil, NO);
}

- (void)startPictureInPicture {
    if (!_pip) return;
    [_pip startPictureInPicture];
}

- (void)pictureInPictureController:(AVPictureInPictureController *)controller setPlaying:(BOOL)playing {
    id<SPTPlayer> player = (id<SPTPlayer>)SGPlayer();
    if (playing) [player resume:nil];
    else [player pause:nil];
}

// Spotify's clock is its own, so the window shows no scrubber: the range is open.
- (CMTimeRange)pictureInPictureControllerTimeRangeForPlayback:(AVPictureInPictureController *)controller {
    return CMTimeRangeMake(kCMTimeNegativeInfinity, kCMTimePositiveInfinity);
}

- (BOOL)pictureInPictureControllerIsPlaybackPaused:(AVPictureInPictureController *)controller {
    return SGPlayerState().isPaused;
}

- (void)pictureInPictureController:(AVPictureInPictureController *)controller didTransitionToRenderSize:(CMVideoDimensions)newRenderSize {
}

- (void)pictureInPictureController:(AVPictureInPictureController *)controller skipByInterval:(CMTime)skipInterval completionHandler:(void (^)(void))completionHandler {
    SPTPlayerState *state = SGPlayerState();
    [(id<SPTPlayer>)SGPlayer() seekTo:MAX(0, positionOf(state) + CMTimeGetSeconds(skipInterval))];
    completionHandler();
}

// The borrowed surface back in the bar.
- (void)returnVideo {
    UIView *surface = _videoSurface;
    _videoSurface = nil;
    if (!surface) return;
    if (_videoKeeper) {
        for (NSString *key in @[@"frame", @"bounds", @"center"]) [surface removeObserver:_videoKeeper forKeyPath:key];
        _videoKeeper = nil;
    }
    surface.backgroundColor = _videoHomeColor;
    if (!_pip.isPictureInPictureActive) {
        _pip = nil;
        SGRSystemVideoSetPiP(NO, NO);
    }
    if (self.isViewLoaded) [UIView animateWithDuration:0.35 animations:^{
        [self.view setNeedsLayout];
        [self.view layoutIfNeeded];
    }];
    UIView *home = _videoHome;
    if (home) {
        surface.autoresizingMask = _videoHomeMask;
        surface.frame = _videoHomeFrame;
        // Left laid out by its frame, at the bar's size: put back to Auto Layout it had no constraints there any more (they
        // went as it left), was laid out to nothing, and Spotify let the video go, which broke playback after the page was
        // swiped away and Picture in Picture with it (its owner, 2026-11-10).
        [home addSubview:surface];
    } else {
        [surface removeFromSuperview];
    }
}

// While the AI DJ talks: the bar empty and the times dashed, as with nothing playing (tick), since the talk has no
// length, and the bar not to be dragged. The cover is Spotify's DJ picture. Spotify's DJ animation is drawn live from
// the voice's loudness inside its own DJ screens (Endless_AIDJVisualizationKit), so there is none to show here (its
// owner, 2026-11-09).
// The ring fills the page, centred where the cover is and as large as Spotify's against it (a radius of 0.27 of the
// cover's side: Spotify's is 87 points on a 375 point screen, the cover there 319).
- (void)placeDJRing {
    if (!_djRing.superview) return;
    _djRing.frame = self.view.bounds;
    // The holder's place untransformed: with the lyrics or the queue up it is the thumbnail by its transform alone, and
    // the ring stays where the large cover stands.
    CGSize side = _coverHolder.bounds.size;
    _djRing.ringCentre = [self.view convertPoint:_coverHolder.center fromView:_coverHolder.superview];
    _djRing.ringRadius = round(MIN(side.width, side.height) * 0.27);
}

- (void)showNarration:(BOOL)on {
    if (on == _narrating) return;
    _narrating = on;
    // Our own DJ ring while it talks (SystemDJRing.h), since Spotify's cannot be borrowed: the page's background, DJ blue
    // throughout with the ring where the cover was, and the cover away, as on Spotify's own DJ screen (its owner,
    // 2026-11-10: "it doesn't need to be in its own cover, it can be in the background like Spotify's").
    if (on && !_djRing) _djRing = [[SGRDJRingView alloc] initWithFrame:self.view.bounds];
    if (on && _djRing.superview != self.view) {
        _djRing.alpha = 0;
        [self.view insertSubview:_djRing aboveSubview:_field];
        [self placeDJRing];
    }
    _djRing.moving = on;
    SGRDJRingView *ring = _djRing;
    if (self.view.window) SGRAnimate(SGRMotionFade, ^{ ring.alpha = on ? 1 : 0; }, nil);
    else ring.alpha = on ? 1 : 0;
    // The lyrics and the queue closed and their buttons off while the DJ talks: the ring is the page then (its owner,
    // 2026-11-10: the queue over the ring).
    if (on) {
        [self setLyricsOpen:NO];
        [self setQueueOpen:NO];
    }
    _queue.enabled = !on;
    [self syncCoverShownAnimated:YES];
    _scrubber.userInteractionEnabled = !on;
    [self tick];
    [self syncLyrics];
}

- (void)show:(SPTPlayerState *)state {
    SPTPlayerTrack *track = isTrack(state.track) ? state.track : nil;
    // A moment with no track between two (a new playlist loading) is not Not Playing: the page waits kEmptyWait and
    // looks again before it says so.
    if (track) {
        _hadTrack = YES;
    } else if (_hadTrack) {
        if (!_emptyPending) {
            _emptyPending = YES;
            __weak typeof(self) weakSelf = self;
            dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(kEmptyWait * NSEC_PER_SEC)), dispatch_get_main_queue(), ^{
                typeof(self) me = weakSelf;
                if (!me) return;
                me->_emptyPending = NO;
                if (isTrack(SGPlayerState().track)) return;
                me->_hadTrack = NO;
                [me show:SGPlayerState()];
            });
        }
        return;
    }
    // Nothing playing, the Music app's way (its owner's screenshot, 2026-11-02): "Not Playing", no artist or context,
    // the note for a cover, empty times, and previous and next dimmed.
    _title.text = track ? track.trackTitle : @"Not Playing";
    _artist.text = artistLine(track);
    _context.text = contextTitle(state, track);
    [self showNarration:track && isNarration(track)];
    // A new video: the surface taken for the last one goes back and the bar's is taken again once Spotify has the new one
    // on it -- kept, the next video played on a surface no longer on screen (its owner, 2026-11-10).
    BOOL video = track && isVideoTrack(track);
    NSString *uri = video ? SGURIString(track.URI) : nil;
    if (video && _videoSurface && _videoURI && ![uri isEqualToString:_videoURI]) [self returnVideo];
    if (video) _videoURI = uri;
    [self showVideo:video];
    if (_pip) [_pip invalidatePlaybackState];
    for (SGRSystemControlButton *skip in @[_previous, _next]) {
        skip.glyph.alpha = track ? 1 : 0.35;
        skip.userInteractionEnabled = track != nil;
    }
    if (_queueOpen) [self refreshQueue];
    [self syncEpisode:track];
    // The swipe settled on this track already: the labels, which now show it, go back to the middle.
    if (_titleSkipping && ![SGURIString(track.URI) isEqualToString:_titleSkipFrom]) [self endTitleSkip];
    BOOL paused = !state || state.isPaused || !track;
    [_play turnToSymbol:paused ? @"play.fill" : @"pause.fill" animated:_shownOnce];
    _play.accessibilityLabel = paused ? @"Play" : @"Pause";
    [self showPaused:paused animated:_shownOnce];
    [self showOptions:state];
    [self syncFieldHeld];
    [self tick];
    // The cover, the background's clip and Liked Songs, at once (its owner, 2026-11-01: holding them back for the controls'
    // animation was not needed, the stutter was the phone's).
    [self showHeavy];
    _shownOnce = YES;
}

- (void)showHeavy {
    [self syncSaved];
    [self syncRowButtons];
    if (_shownOnce) [self syncClipAnimated:YES];
    [self refreshCover];
    // Spotify's bar and the Kit's fetch take the new track's cover a moment after the state says so.
    for (NSNumber *delay in @[@0.4, @1.2]) {
        __weak typeof(self) weakSelf = self;
        dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(delay.doubleValue * NSEC_PER_SEC)), dispatch_get_main_queue(), ^{
            [weakSelf refreshCover];
        });
    }
}

// Smaller while paused, with the redesigned player's spring; held at full size under Reduce Motion, as there, and at the
// thumbnail's size while the lyrics are up.
- (void)showPaused:(BOOL)paused animated:(BOOL)animated {
    if (_shownOnce && paused == _pausedShown) return;
    _pausedShown = paused;
    CGAffineTransform transform = [self coverTransform];
    if (!animated || SGRReduceMotion() || _lyricsOpen) {
        _coverHolder.transform = transform;
        return;
    }
    [UIView animateWithDuration:0.6 delay:0 usingSpringWithDamping:0.72 initialSpringVelocity:0
                        options:UIViewAnimationOptionBeginFromCurrentState | UIViewAnimationOptionAllowUserInteraction
                     animations:^{ self->_coverHolder.transform = transform; } completion:nil];
}

// The title, play and pause, and previous and next in the open lyrics' and queue's see-through white, or white (Match the
// lyrics button on the Player page, SGRKeyPlayerSoftControls, its owner, 2026-11-02).
- (void)paintAccent {
    UIColor *ink = SGHidden(SGRKeyPlayerSoftControls) ? [UIColor colorWithWhite:1 alpha:kQueueBubbleWhite] : SGRPrimary();
    _title.textColor = _besideTitle.textColor = ink;
    for (SGRSystemControlButton *button in @[_previous, _play, _next]) button.glyph.tintColor = ink;
}

- (void)showOptions:(SPTPlayerState *)state {
    SPTPlayerOptions *options = [state respondsToSelector:@selector(options)] ? state.options : nil;
    // Spotify's own say on whether they can change now, as its Connect menu follows it (its owner, 2026-11-02: autoplay
    // left them lit and stuck): not allowed, unlit, dimmed and untouchable.
    BOOL shuffleAllowed = SGRSystemOptionAllowed(state, NO), repeatAllowed = SGRSystemOptionAllowed(state, YES);
    BOOL shuffling = shuffleAllowed && options.shufflingContext;
    BOOL track = repeatAllowed && options.repeatingTrack, context = repeatAllowed && options.repeatingContext;
    // Lit as the lyrics and the queue are, a light disc with the glyph cut out (its owner, 2026-11-02); off, the color of
    // every other control on the page (its owner, 2026-11-01). The symbol first, so repeat's disc cuts the one shown.
    BOOL animated = _shownOnce && self.view.window;
    [_repeat.glyph setSymbol:track ? @"repeat.1" : @"repeat" animated:_shownOnce];
    [_shuffle setLit:shuffling plain:shuffleAllowed ? SGRPrimary() : SGRTertiary() animated:animated];
    [_repeat setLit:track || context plain:repeatAllowed ? SGRPrimary() : SGRTertiary() animated:animated];
    // Not by enabled: the Kit's button sets its alpha with it, which brought them back mid-drag and showed a Shuffle hidden
    // by its setting (its owner's recording, 2026-11-02). Their taps ask SGRSystemOptionAllowed instead.
    for (UIView *button in @[_shuffle, _repeat]) {
        BOOL allowed = button == _shuffle ? shuffleAllowed : repeatAllowed;
        button.accessibilityTraits = allowed ? UIAccessibilityTraitButton : UIAccessibilityTraitButton | UIAccessibilityTraitNotEnabled;
    }
    _shuffle.accessibilityValue = shuffling ? @"On" : @"Off";
    _repeat.accessibilityValue = track ? @"Track" : context ? @"On" : @"Off";
    [self syncOptionBadge];
}

// The badge on the queue button, not while the queue is open: its chips show the same.
- (void)syncOptionBadge {
    NSString *symbol = _queueOpen ? nil : SGRSystemOptionBadgeSymbol(SGPlayerState(), _shuffleOff, _repeatOff);
    SGRSystemShowOptionBadge(_optionBadge, symbol, _shownOnce && self.view.window);
}

- (void)tick {
    // The surface held put back to the cover's size from the clock too: Spotify's bar laid it out to nothing in a way no
    // observer saw, and at 0x0 Spotify let the video go from it and the picture stayed black (Switch to Audio and back:
    // the phone's log, 2026-11-10).
    [_videoKeeper keep];
    // A new surface for the next video: Spotify makes one in the bar for each video and attaches it only once it is
    // visible, while the last one stays attached, so waiting for the held one to let go could wait for ever (a skip
    // through music videos: the phone's log, 2026-11-10). Any bar surface never held before is taken at once, the old one
    // dropped rather than put back: put back, the bar took it up again and the two were swapped on every tick until the
    // app hung (2026-11-10). One held is never taken again.
    if (_videoSurface) {
        UIView *fresh = nil;
        for (UIView *surface in barVideoSurfaces()) {
            if (surface != _videoSurface && ![usedSurfaces() containsObject:surface]) fresh = surface;
        }
        if (fresh) {
            UIView *old = _videoSurface;
            if (_videoKeeper) {
                for (NSString *key in @[@"frame", @"bounds", @"center"]) [old removeObserver:_videoKeeper forKeyPath:key];
                _videoKeeper = nil;
            }
            [old removeFromSuperview];
            _videoSurface = nil;
            if (!_pip.isPictureInPictureActive) {
                _pip = nil;
                SGRSystemVideoSetPiP(NO, NO);
            }
            _nextSurface = fresh;
            [self attachVideoIfShown];
        }
    }
    [self syncLyrics];
    if (_episode) [self syncEpisode:(isTrack(SGPlayerState().track) ? SGPlayerState().track : nil)];
    if (_scrubber.held) return;
    SPTPlayerState *state = SGPlayerState();
    // Nothing playing, or the AI DJ talking, which has no length: the bar empty and the times dashed, as Not Playing
    // (its owner, 2026-11-09).
    if (!isTrack(state.track) || _narrating) {
        if (!_narrating && _hadTrack) return;
        _scrubber.value = 0;
        _elapsed.text = _remaining.text = @"--:--";
        _shownTotal = -1;
        return;
    }
    double duration = state.duration, position = positionOf(state);
    if (CACurrentMediaTime() < _seekUntil) {
        if (fabs(position - _seekTarget) > 1.5) position = _seekTarget;
        else _seekUntil = 0;
    }
    _scrubber.value = duration > 0 ? position / duration : 0;
    [self showTimesAt:position of:duration];
}

- (void)showTimesAt:(double)position of:(double)duration {
    NSInteger elapsed = wholeSeconds(position), left = wholeSeconds(MAX(0, duration - position)), total = wholeSeconds(duration);
    if (elapsed == _shownElapsed && left == _shownLeft && total == _shownTotal && _elapsed.text) return;
    _shownElapsed = elapsed;
    _shownLeft = left;
    _shownTotal = total;
    _elapsed.text = timeText(position);
    _remaining.text = [@"-" stringByAppendingString:timeText(MAX(0, duration - position))];
    _scrubber.accessibilityValue = [NSString stringWithFormat:@"%@ of %@", timeText(position), timeText(duration)];
}

- (void)scrubbedTo:(CGFloat)value {
    double duration = SGPlayerState().duration;
    [self showTimesAt:value * duration of:duration];
}

- (void)seekTo:(CGFloat)value {
    id<SPTPlayer> player = (id<SPTPlayer>)SGPlayer();
    double duration = SGPlayerState().duration;
    if (![player respondsToSelector:@selector(seekTo:)] || duration <= 0) return;
    _seekTarget = MIN(duration, MAX(0, value * duration));
    _seekUntil = CACurrentMediaTime() + kSeekHold;
    [player seekTo:_seekTarget];
    [self tick];
}

#pragma mark - the lyrics

- (void)linesKept:(NSNotification *)note {
    if ([note.object isEqual:SGKaraokePlayingTrack()]) [self syncLyrics];
}

// The glyph and the stage follow where the track's lyrics stand, from the page's timer and as lines are kept. The
// lines themselves, a new track's included, are the karaoke view's, which reads them from the same store.
- (void)syncLyrics {
    if (!_lyrics) return;
    NSString *track = SGKaraokePlayingTrack();
    BOOL lines = SGRPlayerLyricsAvailable(), none = !lines && SGRPlayerLyricsNone();
    // Spotify asks for a track's lyrics only while a page of its own shows them, and none is up under this one, so
    // they are asked for here, as the lock screen's and the Live Activity's are (LockScreenLyrics.x, LiveActivity.x).
    // A track asked for already or kept returns at once.
    if (!lines && !none && track && self.view.window) SGKaraokeRequestLyrics(track);
    SGRSystemLyrics shown = lines ? SGRSystemLyricsLines : none ? SGRSystemLyricsNone : SGRSystemLyricsLoading;
    if (shown != _lyricsShown || !(track == _lyricsTrack || [track isEqualToString:_lyricsTrack])) {
        _lyricsShown = shown;
        _lyricsTrack = track;
    }
    _lyricsNote.hidden = shown != SGRSystemLyricsNone;
    if (shown == SGRSystemLyricsLoading) [_lyricsSpinner startAnimating];
    else [_lyricsSpinner stopAnimating];

    // As the footer's: dimmed and off without lines, but always on while the lyrics are up, the way back to the cover.
    BOOL enabled = (lines || _lyricsOpen) && !_narrating;
    NSString *symbol = _lyricsOpen ? kLyricsSymbolOpen : kLyricsSymbol;
    if (_lyrics.enabled == enabled && [_lyrics.glyph.symbol isEqualToString:symbol]) return;
    BOOL animated = _shownOnce && self.view.window;
    [_lyrics.glyph setSymbol:symbol animated:animated];
    SGRGlyphButton *glyph = _lyrics;
    BOOL open = _lyricsOpen;
    UIView *bubble = _lyricsBubble;
    void (^mark)(void) = ^{
        glyph.enabled = enabled;
        // Clear while up: the button sets its glyph's alpha itself, and a glyph drawn would fill the disc's cut.
        glyph.glyph.tintColor = open ? UIColor.clearColor : SGRSecondary();
        bubble.alpha = open ? 1 : 0;
        bubble.transform = open ? CGAffineTransformIdentity : CGAffineTransformMakeScale(0.8, 0.8);
    };
    if (animated) SGRAnimate(SGRMotionFade, mark, nil);
    else mark();
    glyph.accessibilityValue = open ? @"Shown" : nil;
}

#pragma mark - the queue


// A track lifted in the queue: the progress, the controls, the volume and the row under them fade and drop away and the
// list takes their room, back as it is let go (the Music app's, its owner's recording, 2026-11-02).
- (void)setQueueDragging:(BOOL)dragging {
    if (dragging == _queueDragging) return;
    // Back a moment after the let go, not at once (its owner, 2026-11-02); a new lift meanwhile keeps them away.
    if (!dragging) {
        NSUInteger token = ++_dragReturn;
        __weak typeof(self) weakSelf = self;
        dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(0.45 * NSEC_PER_SEC)), dispatch_get_main_queue(), ^{
            typeof(self) me = weakSelf;
            if (me && token == me->_dragReturn) [me showControlsAfterDrag];
        });
        return;
    }
    ++_dragReturn;
    [self moveControlsForDrag:YES];
}

- (void)showControlsAfterDrag {
    if (!_queueDragging) return;
    [self moveControlsForDrag:NO];
}

- (void)moveControlsForDrag:(BOOL)dragging {
    if (dragging == _queueDragging) return;
    _queueDragging = dragging;
    NSArray<UIView *> *controls = @[_scrubber, _elapsed, _remaining, _shuffle, _previous, _play, _next, _repeat, _volume, _lyrics, _route, _routeLine, _queue];
    // What each was before, a control hidden by its setting (Shuffle off, an episode's) staying hidden after.
    if (dragging) {
        _dragAlphas = [NSMapTable weakToStrongObjectsMapTable];
        for (UIView *view in controls) [_dragAlphas setObject:@[@(view.alpha), @(view.userInteractionEnabled)] forKey:view];
    }
    NSMapTable<UIView *, NSArray *> *before = (NSMapTable *)_dragAlphas;
    // The Music app's (its owner's recording, 2026-11-02): the controls go as one block, falling well down as they fade
    // quickly, and come back up from below on a spring, fading in as they rise.
    void (^fade)(void) = ^{
        for (UIView *view in controls) {
            NSArray *was = [before objectForKey:view];
            view.alpha = dragging ? 0 : (was ? [was[0] doubleValue] : 1);
        }
    };
    void (^move)(void) = ^{
        CGAffineTransform away = dragging ? CGAffineTransformMakeTranslation(0, 160) : CGAffineTransformIdentity;
        for (UIView *view in controls) view.transform = away;
        [self.view setNeedsLayout];
        [self.view layoutIfNeeded];
    };
    UIViewAnimationOptions options = UIViewAnimationOptionBeginFromCurrentState | UIViewAnimationOptionAllowUserInteraction;
    if (SGRReduceMotion()) {
        move();
        [UIView animateWithDuration:0.25 delay:0 options:options animations:fade completion:nil];
    } else if (dragging) {
        [UIView animateWithDuration:0.3 delay:0 options:options | UIViewAnimationOptionCurveEaseIn animations:move completion:nil];
        [UIView animateWithDuration:0.18 delay:0 options:options | UIViewAnimationOptionCurveLinear animations:fade completion:nil];
    } else {
        [UIView animateWithDuration:0.55 delay:0 usingSpringWithDamping:0.9 initialSpringVelocity:0 options:options animations:move completion:nil];
        [UIView animateWithDuration:0.35 delay:0.05 options:options | UIViewAnimationOptionCurveEaseOut animations:fade completion:nil];
    }
    for (UIView *view in controls) {
        NSArray *was = [before objectForKey:view];
        view.userInteractionEnabled = dragging ? NO : (was ? [was[1] boolValue] : YES);
    }
    // Previous and next as the track has them now, not as at the lift: it may have ended meanwhile (Not Playing).
    if (!dragging) for (UIView *skip in @[_previous, _next]) skip.userInteractionEnabled = isTrack(SGPlayerState().track);
}

// The queue's scroll pushes the thumbnail row (the thumbnail, the title and artist, the add button) up and out, fading
// as it goes, as far as it has pushed its chips; closed, the row is in place.
- (void)pushHead:(CGFloat)push {
    _headPush = push;
    _coverHolder.transform = [self coverTransform];
    [self placeHeadPush];
}

- (void)placeHeadPush {
    CGFloat push = _queueOpen ? _headPush : 0, room = MAX(1, _queueView.headRoom);
    // Pushed up, the row fades as it goes; pulled down by History, it fades as it reaches the list's foot.
    CGFloat shown = MIN(1, MAX(0, 1 - push / (room * 0.7))) * (_queueOpen ? _queueView.headShown : 1);
    CGAffineTransform up = CGAffineTransformMakeTranslation(0, -push);
    _titleBlock.transform = up;
    _add.transform = up;
    _more.transform = up;
    _switchVideo.transform = up;
    _djButton.transform = up;
    // Only the queue's: the lyrics' rest fades the row by its own alpha (fadingViews), the thumbnail's own staying put.
    if (_queueOpen || shown != _shownAlpha) {
        _titleBlock.alpha = shown;
        _add.alpha = shown;
        _more.alpha = shown;
        _switchVideo.alpha = shown;
        _djButton.alpha = shown;
    }
    _shownAlpha = shown;
    _cover.alpha = shown;
    // The shadow, which is the holder's, goes with the thumbnail, or it stayed behind as a dark square as the row went
    // (its owner's recording, 2026-11-06).
    _coverHolder.layer.shadowOpacity = 0.35f * (float)MIN(1, shown);
}

- (void)toggleQueue {
    if (_narrating && !_queueOpen) return;
    [self setQueueOpen:!_queueOpen];
}

// What a queue was made from: the playing track's URI, then each track to come's.
static NSArray<NSString *> *queueKey(NSArray *next) {
    NSMutableArray<NSString *> *key = [NSMutableArray arrayWithObject:SGURIString(SGPlayerState().track.URI) ?: @""];
    for (id item in next) [key addObject:[item respondsToSelector:@selector(URI)] ? (SGURIString([item URI]) ?: @"") : @""];
    return key;
}

NSString *SGRSystemContextTitle(SPTPlayerState *state) {
    return contextTitle(state, isTrack(state.track) ? state.track : nil);
}

NSArray<NSString *> *SGRSystemQueueKey(NSArray *next) {
    return queueKey(next);
}

// A track moved or taken out in a queue (the page's or the landscape player's): Spotify's queue fetched again, and only if
// it is still the one the queue showed (`shown`: the same track playing and the same tracks to come, in the same order),
// its tracks to come in the new order handed back (setQueue:). The track can change during a drag or a swipe, and a queue
// from before it played a track again or skipped one (the review, 2026-11-04); then nothing goes back. `handed` gets the
// new order's key, for the next move to be checked against; `done` runs a moment later either way, to show what Spotify
// kept.
void SGRSystemHandQueueBack(NSArray<NSString *> *shown, NSArray *upcoming, void (^handed)(NSArray<NSString *> *key), void (^done)(void)) {
    id<SPTPlayer> player = (id<SPTPlayer>)SGPlayer();
    if (!shown || ![player respondsToSelector:@selector(fetchQueue:on:)] || ![player respondsToSelector:@selector(setQueue:)]) return;
    [player fetchQueue:^(id queue) {
        NSArray *next = [queue respondsToSelector:@selector(nextTracks)] ? [(id<SPTPlayerQueue>)queue nextTracks] : nil;
        if ([next isKindOfClass:NSArray.class] && [queueKey(next) isEqualToArray:shown] && [queue respondsToSelector:@selector(setNextTracks:)]) {
            // Spotify's own object: its tracks go back as they were if the hand-back throws.
            @try {
                [(id<SPTPlayerQueue>)queue setNextTracks:upcoming];
                [player setQueue:queue];
                if (handed) handed(queueKey(upcoming));
            } @catch (NSException *e) {
                @try { [(id<SPTPlayerQueue>)queue setNextTracks:next]; } @catch (NSException *again) {}
            }
        }
        if (done) dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(0.6 * NSEC_PER_SEC)), dispatch_get_main_queue(), done);
    } on:dispatch_get_main_queue()];
}

- (void)handQueueBack:(NSArray *)upcoming {
    __weak typeof(self) weakSelf = self;
    SGRSystemHandQueueBack(_spotifyQueueKey, upcoming, ^(NSArray<NSString *> *key) {
        // The next change, before the fetch below, is checked against this one.
        typeof(self) me = weakSelf;
        if (me) me->_spotifyQueueKey = key;
    }, ^{
        // Fetched again, so the page shows what Spotify kept.
        typeof(self) me = weakSelf;
        if (me && me->_queueOpen) [me refreshQueue];
    });
}

// The queue shown from the state at once, then from Spotify's whole queue as it comes (its owner, 2026-11-02: the
// state's future held only the next two tracks).
- (void)refreshQueue {
    SPTPlayerState *state = SGPlayerState();
    NSString *from = contextTitle(state, isTrack(state.track) ? state.track : nil);
    [_queueView showState:state from:from];
    id<SPTPlayer> player = (id<SPTPlayer>)SGPlayer();
    if (![player respondsToSelector:@selector(fetchQueue:on:)]) return;
    __weak typeof(self) weakSelf = self;
    [player fetchQueue:^(id queue) {
        typeof(self) me = weakSelf;
        id answer = [queue respondsToSelector:@selector(nextTracks)] ? [(id<SPTPlayerQueue>)queue nextTracks] : nil;
        if (!me || !me->_queueOpen) return;
        me->_spotifyQueue = queue;
        NSArray *next = answer;
        if (![next isKindOfClass:NSArray.class]) return;
        me->_spotifyQueueKey = queueKey(next);
        [me->_queueView showState:SGPlayerState() upcoming:next from:from];
        // History: the mod's own, the songs listened to (SystemHistory.h), or with its switch off Spotify's prevTracks.
        NSArray *own = SGRSystemHistoryTracks();
        if (own) [me->_queueView showPast:own];
        else if ([queue respondsToSelector:@selector(prevTracks)]) [me->_queueView showPast:[(id<SPTPlayerQueue>)queue prevTracks]];
    } on:dispatch_get_main_queue()];
}

// The queue lit while open, as the lyrics' glyph is.
- (void)syncQueueButton {
    BOOL open = _queueOpen;
    SGRGlyphButton *button = _queue;
    UIView *bubble = _queueBubble;
    void (^mark)(void) = ^{
        button.glyph.tintColor = open ? UIColor.clearColor : SGRSecondary();
        bubble.alpha = open ? 1 : 0;
        bubble.transform = open ? CGAffineTransformIdentity : CGAffineTransformMakeScale(0.8, 0.8);
    };
    if (_shownOnce && self.view.window) SGRAnimate(SGRMotionFade, mark, nil);
    else mark();
    button.accessibilityValue = open ? @"Shown" : nil;
    [self syncOptionBadge];
}

// The queue comes in the lyrics' place in the same layout spring: the cover shrinks to the thumbnail as the title rises
// beside it and the queue fades in under them, over the same blur; the lyrics, if up, give way first. Out of the page
// once it has faded out.
- (void)setQueueOpen:(BOOL)open {
    if (open == _queueOpen) return;
    // Straight from the lyrics: they close as if the queue were up already, so the thumbnail stays the thumbnail rather
    // than growing back toward the cover for a moment (its owner's recording, 2026-11-06).
    if (open && _lyricsOpen) {
        _queueOpen = YES;
        [self setLyricsOpen:NO];
        _queueOpen = NO;
    }
    _queueOpen = open;
    _headPush = 0;
    if (self.view.window) SGRSystemTurnSetQueue(open);
    UIView *view = self.view, *queue = _queueView;
    if (open) {
        [self refreshQueue];
        if (queue.superview != view) {
            queue.alpha = 0;
            [view insertSubview:queue belowSubview:_coverHolder];
        }
        [_queueView scrollToTop];
    }
    [self blurBackground:open || _lyricsOpen animated:view.window != nil];
    [self syncQueueButton];
    void (^change)(void) = ^{
        [view setNeedsLayout];
        [view layoutIfNeeded];
        queue.alpha = open ? 1 : 0;
    };
    // Over a clip, the cover as the lyrics have it: gone at once as the queue closes, in late as it opens.
    BOOL overClip = _motion && view.window && !SGRReduceMotion() && !_lyricsOpen;
    if (overClip) {
        UIView *cover = _coverHolder;
        CGFloat alpha = open ? 1 : 0;
        [UIView animateWithDuration:open ? kCoverToThumbIn : kCoverToClipOut delay:open ? kCoverToThumbDelay : 0
                            options:UIViewAnimationOptionBeginFromCurrentState | (open ? UIViewAnimationOptionCurveEaseOut : UIViewAnimationOptionCurveEaseIn)
                         animations:^{ cover.alpha = alpha; } completion:nil];
    } else {
        [self syncCoverShownAnimated:view.window != nil];
    }
    void (^done)(BOOL) = ^(BOOL finished) {
        if (!self->_queueOpen) [queue removeFromSuperview];
    };
    if (view.window) SGRAnimateLayout(view, change, done);
    else {
        change();
        done(YES);
    }
}

- (void)toggleLyrics {
    if (!_lyricsOpen && (!SGRPlayerLyricsAvailable() || _narrating)) return;
    [self setLyricsOpen:!_lyricsOpen];
}

// The cover gives way to the lines and comes back in one layout spring: it shrinks to the thumbnail as the title and
// artist rise beside it and the lines fade in under them. The stage leaves the page once it has faded out, so the
// karaoke view's display link stops with it (it runs only while the view is in a window: SGRKaraokeView.m's
// scheduleLink), and the page's closing takes it down too.
- (void)setLyricsOpen:(BOOL)open {
    if (open == _lyricsOpen) return;
    // One or the other in the lyrics' place: the queue gives way to the lyrics.
    // Straight from the queue, the same way.
    if (open && _queueOpen) {
        _lyricsOpen = YES;
        [self setQueueOpen:NO];
        _lyricsOpen = NO;
    }
    if (!open) [self setAlone:NO animated:NO];
    _lyricsOpen = open;
    if (self.view.window) SGRSystemTurnSetLyrics(open);
    [self blurBackground:open || _queueOpen animated:self.view.window != nil];
    if (open) [self restartRest];
    else [self stopRest];
    UIView *view = self.view, *stage = _stage;
    if (open && stage.superview != view) {
        stage.alpha = 0;
        [view insertSubview:stage belowSubview:_coverHolder];
    }
    [self syncLyrics];
    void (^change)(void) = ^{
        [view setNeedsLayout];
        [view layoutIfNeeded];
        stage.alpha = open ? 1 : 0;
    };
    // Over a clip the cover only shows as the thumbnail: it goes at once as the lyrics close, rather than growing back to
    // full size before the clip takes over, and comes in only as it settles into the thumbnail's place as they open (its
    // owner's recording, 2026-11-01: the cover's way to the animated artwork was awkward).
    BOOL overClip = _motion && view.window && !SGRReduceMotion() && !_queueOpen;
    if (overClip) {
        UIView *cover = _coverHolder;
        CGFloat alpha = open ? 1 : 0;
        [UIView animateWithDuration:open ? kCoverToThumbIn : kCoverToClipOut delay:open ? kCoverToThumbDelay : 0
                            options:UIViewAnimationOptionBeginFromCurrentState | (open ? UIViewAnimationOptionCurveEaseOut : UIViewAnimationOptionCurveEaseIn)
                         animations:^{ cover.alpha = alpha; } completion:nil];
    } else {
        [self syncCoverShownAnimated:view.window != nil];
    }
    void (^done)(BOOL) = ^(BOOL finished) {
        if (!self->_lyricsOpen) [stage removeFromSuperview];
    };
    if (view.window) SGRAnimateLayout(view, change, done);
    else {
        change();
        done(YES);
    }
}

#pragma mark - the lines on their own

// Where the lines go on their own (PlayerLyrics.x's aloneStage): the whole safe area, kAloneInset in at both ends, or
// with Keep the title from where they stood down.
- (CGRect)aloneStageFrom:(CGRect)stage {
    CGRect safe = UIEdgeInsetsInsetRect(self.view.bounds, self.view.safeAreaInsets);
    CGFloat top = SGRLyricsHideMode() == SGRLyricsHideControls ? CGRectGetMinY(stage) : CGRectGetMinY(safe) + kAloneInset;
    return CGRectMake(CGRectGetMinX(stage), top, stage.size.width, MAX(0, CGRectGetMaxY(safe) - kAloneInset - top));
}

// What fades (PlayerLyrics.x's fadingViews): the header, the thumbnail, the title row and every control, or with Keep
// the title, the controls under the title row alone.
- (NSArray<UIView *> *)fadingViews {
    NSMutableArray<UIView *> *views = [NSMutableArray arrayWithArray:@[_scrubber, _elapsed, _remaining, _speed, _previous, _play, _next,
                                                                       _volume, _lyrics, _route, _routeLine, _queue]];
    // Hidden on the Player page, they stay unseen when the rest comes back.
    if (!_shuffleOff) [views addObject:_shuffle];
    if (!_repeatOff) [views addObject:_repeat];
    if (SGRLyricsHideMode() != SGRLyricsHideControls) [views addObjectsFromArray:@[_close, _more, _context, _coverHolder, _titleBlock, _add, _switchVideo, _djButton]];
    return views;
}

// The lines on their own, or the rest back, as the redesigned player's setAlone (PlayerLyrics.x): the stage grows or
// shrinks in the layout spring with the lines laid out in it, so the sung line rides with it, and the rest fades with the
// slow fade going and answers at once coming back. Alone, a tap seeks only where the lines reached with the rest up;
// coming back, nowhere until a turn later, so the tap that brought the rest back is no seek.
- (void)setAlone:(BOOL)alone animated:(BOOL)animated {
    if (alone == _alone || (alone && !_lyricsOpen)) return;
    UIView *view = self.view;
    CGRect before = _stage.frame;
    _alone = alone;
    if (alone) {
        [self stopRest];
        CGRect after = [self aloneStageFrom:before];
        _lines.seeksBelow = CGRectGetMinY(before) - CGRectGetMinY(after);
        _lines.seeksAbove = CGRectGetMaxY(before) - CGRectGetMinY(after);
    } else {
        _lines.seeksBelow = CGFLOAT_MAX;
        SGRKaraokeView *lines = _lines;
        __weak typeof(self) weakSelf = self;
        dispatch_async(dispatch_get_main_queue(), ^{
            typeof(self) me = weakSelf;
            if (me && !me->_alone) lines.seeksAbove = 0;   // alone again since
        });
    }
    _wake.enabled = alone;
    void (^move)(void) = ^{
        [view setNeedsLayout];
        [view layoutIfNeeded];
        [self->_lines layoutIfNeeded];
    };
    NSArray<UIView *> *fading = [self fadingViews];
    void (^fade)(void) = ^{
        self->_lines.extrasHidden = alone;
        for (UIView *each in fading) each.alpha = alone ? 0 : 1;
    };
    if (animated && view.window) {
        SGRAnimateLayout(view, move, nil);
        SGRAnimate(alone ? SGRMotionFade : SGRMotionRespond, fade, nil);
    } else {
        move();
        fade();
    }
}

// Whether the clock runs (PlayerLyrics.x's mayCount): the lines up with the rest, the song playing with the app in front,
// no finger on the page, VoiceOver off and the choice not Off.
- (BOOL)mayCount {
    SPTPlayerState *state = SGPlayerState();
    return SGRLyricsHideMode() != SGRLyricsHideOff && _lyricsOpen && !_alone && !_watcher.touching && self.view.window && state && !state.isPaused
        && !UIAccessibilityIsVoiceOverRunning() && UIApplication.sharedApplication.applicationState == UIApplicationStateActive;
}

- (void)stopRest {
    [_rest invalidate];
    _rest = nil;
}

// Run out while something keeps the rest up (a sheet over the page, Sing getting ready), it starts over.
- (void)restartRest {
    [self stopRest];
    if (![self mayCount]) return;
    __weak typeof(self) weakSelf = self;
    _rest = [NSTimer scheduledTimerWithTimeInterval:kRest repeats:NO block:^(NSTimer *timer) {
        typeof(self) me = weakSelf;
        if (!me) return;
        me->_rest = nil;
        if ([me mayCount] && !me.presentedViewController && SGSingCurrentState() != SGSingStatePreparing) [me setAlone:YES animated:YES];
        if (!me->_alone) [me restartRest];
    }];
}

- (void)woke {
    [self setAlone:NO animated:YES];
    [self restartRest];
}

// The wake tap takes nothing from anything under it (PlayerLyrics.x's SGRPlayerWake): Sing's mic and a line the lines'
// own tap would seek to keep their touches.
- (BOOL)gestureRecognizer:(UIGestureRecognizer *)recognizer shouldReceiveTouch:(UITouch *)touch {
    if (recognizer != _wake) return YES;
    for (UIView *v = touch.view; v; v = v.superview) {
        if ([v isKindOfClass:SGRSingButton.class]) return NO;
        if (v == _lines) return ![_lines tapSeeksAt:[touch locationInView:_lines]];
    }
    return YES;
}

- (BOOL)gestureRecognizer:(UIGestureRecognizer *)recognizer shouldRecognizeSimultaneouslyWithGestureRecognizer:(UIGestureRecognizer *)other {
    return recognizer == _wake || recognizer == _titlePress || other == _titlePress;
}

// The title's swipe is sideways only: a drag that starts more down than across is never its, so UIKit's swipe close
// takes it, as the mini player's swipe leaves its taps (SystemTabs.x's gestureRecognizerShouldBegin:).
- (BOOL)gestureRecognizerShouldBegin:(UIGestureRecognizer *)recognizer {
    if (recognizer.view != _titleBlock || ![recognizer isKindOfClass:UIPanGestureRecognizer.class]) return YES;
    CGPoint velocity = [(UIPanGestureRecognizer *)recognizer velocityInView:_titleBlock];
    return fabs(velocity.x) > fabs(velocity.y) * 1.2;
}

#pragma mark - the title's swipe

// The track the swipe brings in from `way` (-1 the next, from the right; 1 the one before, from the left), or nil.
- (SPTPlayerTrack *)trackFrom:(NSInteger)way {
    SPTPlayerState *state = SGPlayerState();
    id track = way < 0 ? state.future.firstObject : SGRPreviousTrack(state);
    return isTrack(track) ? track : nil;
}

// Moved sideways the title and artist go with the finger and the next or previous track's come in beside them, as the
// mini player's lines do (SystemTabs.x's swiped:): far or fast enough it settles on that track and skips to it, short of
// that it springs back. Left is the next track, right the one before, episodes the same.
// In while the finger is down on them and a tap opens the album (SGRKeyPlayerTitleAlbum), each scaled from its leading
// edge, where its text starts, and dimmed, as SGRGlyphPress does the star; out again on letting go or as a swipe starts.
- (void)titlePressed:(UILongPressGestureRecognizer *)press {
    BOOL down = press.state == UIGestureRecognizerStateBegan || press.state == UIGestureRecognizerStateChanged;
    if (down && press.state == UIGestureRecognizerStateChanged) return;
    [self pressTitle:down && SGEnabled(SGRKeyPlayerTitleAlbum)];
}

- (void)pressTitle:(BOOL)pressed {
    if (pressed == _titlePressed) return;
    _titlePressed = pressed;
    static const CGFloat scale = 0.95;
    SGRAnimate(SGRMotionPress, ^{
        for (UIView *label in @[self->_title, self->_artist]) {
            CGFloat shift = -label.bounds.size.width * (1 - scale) / 2;
            label.transform = pressed ? CGAffineTransformScale(CGAffineTransformMakeTranslation(shift, 0), scale, scale) : CGAffineTransformIdentity;
            label.alpha = pressed ? 0.5 : 1;
        }
    }, nil);
}

- (void)titleSwiped:(UIPanGestureRecognizer *)swipe {
    if (swipe.state == UIGestureRecognizerStateBegan && _titlePressed) {
        _titlePressed = NO;
        for (UIView *label in @[_title, _artist]) {
            [label.layer removeAllAnimations];
            label.transform = CGAffineTransformIdentity;
            label.alpha = 1;
        }
    }
    CGFloat step = _titleBlock.bounds.size.width - 2 * kTitleFade + kTitlePageGap, x = [swipe translationInView:_titleBlock].x;
    NSInteger way = x < 0 ? -1 : 1;
    SPTPlayerTrack *beside = [self trackFrom:way];
    switch (swipe.state) {
        case UIGestureRecognizerStateBegan:
        case UIGestureRecognizerStateChanged: {
            _besideTitle.text = beside.trackTitle ?: @"";
            _besideArtist.text = artistLine(beside) ?: @"";
            _besideTitle.hidden = _besideArtist.hidden = !beside;
            CGFloat moved = beside ? x : x / 4;
            [self placeTitlePagesAt:moved way:way step:step];
            // A tick as the drag passes where letting go skips, as Spotify's cover swipe had (Vibrations > Controls).
            BOOL past = beside && fabs(x) > step * kTitleSwipeDistance;
            if (swipe.state == UIGestureRecognizerStateBegan) _titlePast = NO;
            if (past != _titlePast) {
                _titlePast = past;
                if (past) SGPlayFeedback(SGFeedbackDetent);
            }
            break;
        }
        case UIGestureRecognizerStateEnded:
        case UIGestureRecognizerStateCancelled: {
            CGFloat speed = [swipe velocityInView:_titleBlock].x;
            way = fabs(x) > 12 ? way : (speed < 0 ? -1 : 1);
            beside = [self trackFrom:way];
            BOOL against = (way < 0 && speed > kTitleSwipeSpeed / 2) || (way > 0 && speed < -kTitleSwipeSpeed / 2);
            BOOL skip = swipe.state == UIGestureRecognizerStateEnded && step > kTitlePageGap && !against && beside
                && (fabs(x) > step * kTitleSwipeDistance || fabs(speed) > kTitleSwipeSpeed);
            if (!skip) {
                [UIView animateWithDuration:0.35 delay:0 usingSpringWithDamping:0.85 initialSpringVelocity:0 options:UIViewAnimationOptionAllowUserInteraction
                                 animations:^{ [self placeTitlePagesAt:0 way:way step:step]; } completion:nil];
                break;
            }
            _titleSkipping = YES;
            _titleSkipFrom = SGURIString(SGPlayerState().track.URI);
            [UIView animateWithDuration:0.3 delay:0 usingSpringWithDamping:0.95 initialSpringVelocity:0 options:UIViewAnimationOptionAllowUserInteraction
                             animations:^{ [self placeTitlePagesAt:way * step way:way step:step]; } completion:nil];
            id<SPTPlayer> player = (id<SPTPlayer>)SGPlayer();
            if (way < 0) [player skipToNextTrackWithOptions:nil];
            else [player skipToPreviousTrackWithOptions:nil];
            // A skip that changes nothing (back from a track under way only restarts it) brings the title back.
            __weak typeof(self) weakSelf = self;
            dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(1.2 * NSEC_PER_SEC)), dispatch_get_main_queue(), ^{
                typeof(self) me = weakSelf;
                if (!me || !me->_titleSkipping) return;
                me->_titleSkipping = NO;
                [UIView animateWithDuration:0.35 delay:0 usingSpringWithDamping:0.85 initialSpringVelocity:0 options:0
                                 animations:^{ [me placeTitlePagesAt:0 way:way step:step]; } completion:^(BOOL finished) {
                    me->_besideTitle.hidden = me->_besideArtist.hidden = YES;
                }];
            });
            break;
        }
        default:
            break;
    }
}

// The current pair `offset` along, and the pair coming in one step behind it on the side `way` brings it from.
- (void)placeTitlePagesAt:(CGFloat)offset way:(NSInteger)way step:(CGFloat)step {
    CGAffineTransform current = CGAffineTransformMakeTranslation(offset, 0);
    CGAffineTransform beside = CGAffineTransformMakeTranslation(offset - way * step, 0);
    _title.transform = _artist.transform = current;
    _besideTitle.transform = _besideArtist.transform = beside;
}

// The track changed to the one the swipe settled on: the labels, which now show it, take the middle at once.
- (void)endTitleSkip {
    _titleSkipping = NO;
    [UIView performWithoutAnimation:^{
        self->_title.transform = self->_artist.transform = CGAffineTransformIdentity;
        self->_besideTitle.hidden = self->_besideArtist.hidden = YES;
    }];
}

- (void)resignedActive {
    [self setAlone:NO animated:NO];
    [self stopRest];
}

- (void)voiceOverChanged {
    [self setAlone:NO animated:YES];
    [self restartRest];
}

#pragma mark - the cover

- (void)artworkChanged {
    [self refreshCover];
}

// The Kit's artwork once it is the playing track's picture (SGRNowPlayingArtworkCurrent: fetched full size, or read off a
// screen and believed until the fetch lands, SGRBridges.h). Until then the cover stays what it was, and only a page with
// no cover yet takes the bar's 40pt one: the Kit publishes the bar's cover itself as soon as it believes it is the new
// track's, and the fetch's full size one after it, each with the change notification, however late. The page used to
// judge the Kit's artwork by the track URI it was published with, which a track of the same album as the last never
// changes (its picture is the same, so nothing new is published): the page took it for stale and stretched the bar's
// 40pt cover, blurred, for the whole track (its owner, 2026-11-01).
- (void)refreshCover {
    if (!isTrack(SGPlayerState().track)) {
        if (_hadTrack) return;
        UIImage *art = SGRSystemNotPlayingArt();
        if (_cover.image != art) {
            _cover.image = art;
            _backdrop.image = [self washOf:art];
        }
        return;
    }
    NSString *identity = nil;
    UIImage *art = SGRNowPlayingArtwork(NULL, &identity);
    BOOL current = art && SGRNowPlayingArtworkCurrent();
    UIImage *image = current ? art : _cover.image ? nil : SGRNowPlayingCover() ?: art;
    NSString *playing = SGURIString(SGPlayerState().track.URI);
    // The field reads the Kit's picture by its identity, the same picture once.
    if (current) [_field setArtwork:art identity:identity animated:self.view.window != nil];
    if (!image || image == _cover.image) return;
    // The bar's small picture stands in for the full one until its fetch lands, a few hundredths to a few tenths of a
    // second later (the phone's log, 2026-11-02): drawn large it showed low resolution for that moment. The page keeps
    // the cover it has until the full one comes, kCoverWait at most, and crosses straight to it.
    if (image.size.width < 200 && _cover.image && _cover.image.size.width >= 200) {
        CFTimeInterval now = CACurrentMediaTime();
        if (![playing isEqualToString:_smallCoverTrack]) {
            _smallCoverTrack = [playing copy];
            _smallCoverUntil = now + kCoverWait;
            __weak typeof(self) weakSelf = self;
            dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(kCoverWait * NSEC_PER_SEC)), dispatch_get_main_queue(), ^{
                [weakSelf refreshCover];
            });
        }
        if (now < _smallCoverUntil) return;
    }
    _smallCoverTrack = nil;
    UIImage *wash = [self washOf:image];
    BOOL fade = _cover.image != nil && self.view.window;
    if (!fade) {
        _cover.image = image;
        _backdrop.image = wash;
        return;
    }
    // Each image view crossfades on its own: a crossfade of the whole page left the blur over the backdrop showing the
    // last track's colors under the new cover (its owner, 2026-11-01).
    UIViewAnimationOptions options = UIViewAnimationOptionTransitionCrossDissolve | UIViewAnimationOptionAllowUserInteraction;
    UIImageView *cover = _cover, *backdrop = _backdrop;
    [UIView transitionWithView:cover duration:SGRCrossfade options:options animations:^{ cover.image = image; } completion:nil];
    [UIView transitionWithView:backdrop duration:SGRCrossfade options:options animations:^{ backdrop.image = wash; } completion:nil];
}

// The cover at 48 pixels: drawn large under the blur, it is its colors alone.
- (UIImage *)washOf:(UIImage *)image {
    UIGraphicsImageRendererFormat *format = [UIGraphicsImageRendererFormat preferredFormat];
    format.scale = 1;
    UIGraphicsImageRenderer *renderer = [[UIGraphicsImageRenderer alloc] initWithSize:CGSizeMake(48, 48) format:format];
    return [renderer imageWithActions:^(UIGraphicsImageRendererContext *context) {
        [image drawInRect:CGRectMake(0, 0, 48, 48)];
    }];
}

#pragma mark - commands

// The symbol turns at the tap rather than a beat later when the state reports (that report then finds it already turned,
// or turns it back), with SF Symbols' replace at its own pace, as f728743/Sim-Radio-SwiftUI's PlayerButton.swift has it
// (MIT; its .contentTransition(.symbolEffect(.replace)); its owner's pick, 2026-11-01).
- (void)togglePlay {
    id<SPTPlayer> player = (id<SPTPlayer>)SGPlayer();
    if (!player) return;
    BOOL resume = SGPlayerState().isPaused;
    SGPlayFeedback(resume ? SGFeedbackPlay : SGFeedbackPause);
    if (resume) [player resume:nil];
    else [player pause:nil];
    [_play turnToSymbol:resume ? @"pause.fill" : @"play.fill" animated:YES];
    _play.accessibilityLabel = resume ? @"Pause" : @"Play";
}

- (void)stepSkip:(NSInteger)direction {
    [(direction < 0 ? _previous : _next) stepArrow:direction];
}

// The command first, then the step: the animation never holds the skip up. An episode goes back or on kEpisodeSkip
// seconds through the same seekTo: the progress bar sends, kept inside the episode.
- (void)skip:(NSInteger)direction {
    SGPlayFeedback(SGFeedbackSkip);
    if (_episode) {
        SPTPlayerState *state = SGPlayerState();
        id<SPTPlayer> player = (id<SPTPlayer>)SGPlayer();
        if (![player respondsToSelector:@selector(seekTo:)] || state.duration <= 0) return;
        double target = MIN(state.duration, MAX(0, positionOf(state) + direction * kEpisodeSkip));
        _seekTarget = target;
        _seekUntil = CACurrentMediaTime() + kSeekHold;
        [player seekTo:target];
        [self tick];
        return;
    }
    id<SPTPlayer> player = (id<SPTPlayer>)SGPlayer();
    if (direction < 0) [player skipToPreviousTrackWithOptions:nil];
    else [player skipToNextTrackWithOptions:nil];
    [self stepSkip:direction];
}

- (void)speedTapped {
    SGPlayerShowSpeedPitchPanel(_speed);
}

// An episode's speed as the ⋯ menu writes it (PlayerMenu.m's speedText): 1×, 1.5×, 0.75×.
static NSString *speedLabel(double speed) {
    NSString *text = [NSString stringWithFormat:@"%.2f", speed];
    while ([text hasSuffix:@"0"]) text = [text substringToIndex:text.length - 1];
    if ([text hasSuffix:@"."]) text = [text substringToIndex:text.length - 1];
    return [text stringByAppendingString:@"×"];
}

// Episode or song: the skips' glyphs, shuffle and repeat or the speed. An episode or an audiobook's chapter is told by its
// URI (spotify:episode:…, spotify:chapter:…), as the ⋯ menu tells a podcast's sheet from a song's (PlayerMenu.m's
// sheetKind).
- (void)syncEpisode:(SPTPlayerTrack *)track {
    NSArray<NSString *> *parts = [SGURIString(track.URI) componentsSeparatedByString:@":"];
    NSString *kind = parts.count > 2 ? parts[1] : @"";
    BOOL episode = [kind isEqualToString:@"episode"] || [kind isEqualToString:@"chapter"];
    BOOL speed = episode && SGPlayerSpeedAllowed();
    NSString *title = speedLabel(SGPlayerSpeed());
    if (speed && ![[_speed titleForState:UIControlStateNormal] isEqualToString:title]) {
        [_speed setTitle:title forState:UIControlStateNormal];
        _speed.accessibilityValue = title;
    }
    if (episode == _episode && _shownOnce) {
        _speed.hidden = !speed;
        return;
    }
    _episode = episode;
    BOOL animated = _shownOnce && self.view.window;
    [_previous.glyph setSymbol:episode ? @"gobackward.15" : @"backward.fill" animated:animated];
    [_next.glyph setSymbol:episode ? @"goforward.15" : @"forward.fill" animated:animated];
    _previous.accessibilityLabel = episode ? @"Back 15 seconds" : @"Previous";
    _next.accessibilityLabel = episode ? @"Forward 15 seconds" : @"Next";
    _shuffle.hidden = _repeat.hidden = episode;
    _speed.hidden = !speed;
    [_previous setNeedsLayout];
    [_next setNeedsLayout];
}

- (void)toggleShuffle {
    SGRSystemToggleShuffle();
}

- (void)cycleRepeat {
    SGRSystemCycleRepeat();
}
@end

void SGRSystemToggleShuffle(void) {
    id<SPTPlayer> player = (id<SPTPlayer>)SGPlayer();
    SPTPlayerState *state = SGPlayerState();
    if (!player || !state || !SGRSystemOptionAllowed(state, NO)) return;
    SGPlayFeedback(SGFeedbackToggle);
    [player setShufflingContext:!state.options.shufflingContext];
}

// Off, then the playlist or album, then the track, then off again, the way Spotify's button goes (HeadGestures.x).
void SGRSystemCycleRepeat(void) {
    id<SPTPlayer> player = (id<SPTPlayer>)SGPlayer();
    SPTPlayerOptions *options = SGPlayerState().options;
    if (!player || !options || !SGRSystemOptionAllowed(SGPlayerState(), YES)) return;
    SGPlayFeedback(SGFeedbackToggle);
    if (options.repeatingTrack) {
        [player setRepeatingTrack:NO];
        [player setRepeatingContext:NO];
    } else if (options.repeatingContext) {
        [player setRepeatingTrack:YES];
    } else {
        [player setRepeatingContext:YES];
    }
}

// Without Spotify's skip back to a track, one back at a time, each once the last has landed: told by how many tracks
// lie behind the playing one (the queue's prevTracks), not by its URI, which History can hold twice. Two seconds at most
// for each.
static void stepBackOne(NSUInteger behind, NSInteger steps);

static void stepBackWait(NSUInteger target, NSInteger left, NSInteger waited) {
    id<SPTPlayer> player = (id<SPTPlayer>)SGPlayer();
    if (!player || waited >= 20) return;
    [player fetchQueue:^(id queue) {
        NSArray *past = [queue respondsToSelector:@selector(prevTracks)] ? [(id<SPTPlayerQueue>)queue prevTracks] : nil;
        if (![past isKindOfClass:NSArray.class]) return;
        if (past.count > target) {
            dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(0.1 * NSEC_PER_SEC)), dispatch_get_main_queue(), ^{
                stepBackWait(target, left, waited + 1);
            });
        } else if (left > 0) stepBackOne(past.count, left);
    } on:dispatch_get_main_queue()];
}

static void stepBackOne(NSUInteger behind, NSInteger steps) {
    if (steps <= 0 || behind == 0) return;
    [(id<SPTPlayer>)SGPlayer() skipToPreviousTrackWithOptions:nil];
    stepBackWait(behind - 1, steps - 1, 0);
}

void SGRSystemStepBack(SPTPlayerTrack *track, NSInteger steps) {
    id<SPTPlayer> player = (id<SPTPlayer>)SGPlayer();
    if (!player || steps <= 0) return;
    // Straight to the track, as the skip ahead to one of the tracks to come (skipToNextTrackWithOptions:track:): nothing
    // between plays, and a track History holds twice is the one picked.
    SEL toTrack = @selector(skipToPreviousTrackWithOptions:track:);
    if (track && [player respondsToSelector:toTrack]) {
        ((id (*)(id, SEL, id, id))objc_msgSend)(player, toTrack, nil, track);
        return;
    }
    // Without it, back one at a time from the playing track's start, or the first back only restarts a track under way.
    [player seekTo:0];
    [player fetchQueue:^(id queue) {
        NSArray *past = [queue respondsToSelector:@selector(prevTracks)] ? [(id<SPTPlayerQueue>)queue prevTracks] : nil;
        if (![past isKindOfClass:NSArray.class] || past.count < (NSUInteger)steps) return;
        stepBackOne(past.count, steps);
    } on:dispatch_get_main_queue()];
}

// A song of the mod's History tapped: back to it in Spotify's queue when it is still behind the playing one (the nearest
// time it is there), or else Spotify's own link for it.
// After a switch: the same second sought once `target` is the track playing, tried for five seconds. Only the target: a
// slow switch let the song end, and the next track was sought instead (the code review, 2026-11-10).
static void SGRSwitchSeek(NSString *target, double position, NSInteger tries) {
    SPTPlayerState *state = SGPlayerState();
    NSString *now = SGURIString(state.track.URI);
    if ([now isEqualToString:target] && !state.isPaused) {
        if (position > 2) [(id<SPTPlayer>)SGPlayer() seekTo:position];
        return;
    }
    if (tries >= 20) {
        return;
    }
    dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(0.25 * NSEC_PER_SEC)), dispatch_get_main_queue(), ^{
        SGRSwitchSeek(target, position, tries + 1);
    });
}

// The navigation stack the page was opened over: the selected tab's, in the key window.
static UINavigationController *SGRSwitchNavigation(void) {
    UIWindow *key = nil;
    for (UIScene *scene in UIApplication.sharedApplication.connectedScenes) {
        if (![scene isKindOfClass:UIWindowScene.class]) continue;
        for (UIWindow *w in ((UIWindowScene *)scene).windows) if (w.isKeyWindow) key = w;
    }
    __block UINavigationController *found = nil;
    __block void (^walk)(UIViewController *) = nil;
    void (^__block __weak weakWalk)(UIViewController *);
    walk = ^(UIViewController *vc) {
        if (found || !vc) return;
        if ([vc isKindOfClass:UITabBarController.class]) { weakWalk(((UITabBarController *)vc).selectedViewController); return; }
        if ([vc isKindOfClass:UINavigationController.class] && vc.viewIfLoaded.window) { found = (UINavigationController *)vc; return; }
        for (UIViewController *child in vc.childViewControllers) weakWalk(child);
    };
    weakWalk = walk;
    walk(key.rootViewController);
    return found;
}

// Whether the player page is presented over `nav`'s window.
static BOOL SGRSwitchPageUp(UINavigationController *nav) {
    for (UIViewController *vc = nav.view.window.rootViewController.presentedViewController; vc; vc = vc.presentedViewController) {
        if ([vc isKindOfClass:SGRSystemPlayerPage.class]) return YES;
    }
    return NO;
}

// The track `uri` (a song's music video, or a video's song) played in place of the one playing, from the same second.
void SGRSystemSwitchTo(NSString *uri, BOOL toVideo) {
    NSURL *url = [NSURL URLWithString:uri];
    if (!url) return;
    double position = positionOf(SGPlayerState());
    // To a video: by its link, the one way Spotify plays it as a video (played as a context or put in the queue, the song
    // played instead, 2026-11-10); the album page the link pushes under the player is taken off again at once.
    if (toVideo) {
        UINavigationController *navigation = SGRSwitchNavigation();
        NSArray<UIViewController *> *before = navigation.viewControllers;
        SGOpenSpotifyURI(url);
        __weak UINavigationController *weakNavigation = navigation;
        // Only while the player page is still up over it: a page opened from the player (Go to Artist, the title) closes
        // the player first, and was taken off with the link's (the code review, 2026-11-10).
        for (NSNumber *after in @[@0.4, @1.0, @2.0]) {
            dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(after.doubleValue * NSEC_PER_SEC)), dispatch_get_main_queue(), ^{
                UINavigationController *nav = weakNavigation;
                if (!nav || !before || nav.viewControllers.count <= before.count || !SGRSwitchPageUp(nav)) return;
                [nav setViewControllers:before animated:NO];
            });
        }
        SGRSwitchSeek(uri, position, 0);
        return;
    }
    // To the song: its link played as a context (SPTPlayerContext contextForURI:, then playContext:options:), which plays it
    // with no page; put next in the queue and skipped to, Spotify played another track in its place, and a context of a
    // bare track (contextWithTracks:) stopped playback (2026-11-10).
    id player = SGPlayer();
    Class contextClass = NSClassFromString(@"SPTPlayerContext");
    SEL forURI = NSSelectorFromString(@"contextForURI:"), play = NSSelectorFromString(@"playContext:options:");
    if (![contextClass respondsToSelector:forURI] || ![player respondsToSelector:play]) return;
    @try {
        id context = ((id (*)(id, SEL, id))objc_msgSend)(contextClass, forURI, url);
        ((id (*)(id, SEL, id, id))objc_msgSend)(player, play, context, nil);
    } @catch (NSException *e) {
        return;
    }
    SGRSwitchSeek(uri, position, 0);
}

// The music video's own shape, width over height: the picture's rectangle in Spotify's display view inside the surface
// (SPTVideoDisplayView's or BMVideoDisplayView's videoRect), 16:9 until it has one (its owner, 2026-11-10: the video
// area to follow the video's aspect ratio).
CGFloat SGRSystemVideoAspect(UIView *surface) {
    __block CGFloat aspect = 0;
    SEL rect = NSSelectorFromString(@"videoRect");
    SGForEachView(surface, ^(UIView *v) {
        if (aspect > 0 || ![v respondsToSelector:rect]) return;
        CGRect r = ((CGRect (*)(id, SEL))objc_msgSend)(v, rect);
        if (r.size.width > 1 && r.size.height > 1) aspect = r.size.width / r.size.height;
    });
    return aspect > 0.2 && aspect < 5 ? aspect : 16.0 / 9.0;
}

void SGRSystemPlayPast(SPTPlayerTrack *track) {
    NSString *uri = SGURIString(track.URI);
    id<SPTPlayer> player = (id<SPTPlayer>)SGPlayer();
    if (!uri || !player) return;
    void (^open)(void) = ^{ SGOpenSpotifyURI([NSURL URLWithString:uri]); };
    if (![player respondsToSelector:@selector(fetchQueue:on:)]) {
        open();
        return;
    }
    [player fetchQueue:^(id queue) {
        NSArray *past = [queue respondsToSelector:@selector(prevTracks)] ? [(id<SPTPlayerQueue>)queue prevTracks] : nil;
        if ([past isKindOfClass:NSArray.class]) {
            for (NSInteger i = (NSInteger)past.count - 1; i >= 0; i--) {
                SPTPlayerTrack *behind = past[i];
                if (![behind respondsToSelector:@selector(URI)] || ![SGURIString(behind.URI) isEqualToString:uri]) continue;
                SGRSystemStepBack(behind, (NSInteger)past.count - i);
                return;
            }
        }
        open();
    } on:dispatch_get_main_queue()];
}

UIView *SGRSystemMakeOptionBadge(UIView *button) {
    CGFloat side = 21;
    UIView *badge = [[UIView alloc] initWithFrame:CGRectMake(0, 0, side, side)];
    badge.backgroundColor = UIColor.clearColor;
    badge.layer.cornerRadius = side / 2;
    badge.userInteractionEnabled = NO;
    badge.isAccessibilityElement = NO;
    badge.alpha = 0;
    UIImageView *glyph = [UIImageView new];
    glyph.tintColor = UIColor.whiteColor;
    glyph.contentMode = UIViewContentModeCenter;
    glyph.frame = badge.bounds;
    glyph.tag = 1;
    [badge addSubview:glyph];
    // Over the glyph's top right, as the Music app has it.
    badge.center = CGPointMake(22 + 20.5, 22 - 17.5);
    badge.autoresizingMask = UIViewAutoresizingFlexibleLeftMargin | UIViewAutoresizingFlexibleBottomMargin;
    button.clipsToBounds = NO;
    [button addSubview:badge];
    return badge;
}

void SGRSystemShowOptionBadge(UIView *badge, NSString *symbol, BOOL animated) {
    UIImageView *glyph = [badge viewWithTag:1];
    if (symbol) {
        UIImageSymbolConfiguration *look = [UIImageSymbolConfiguration configurationWithPointSize:10 weight:UIImageSymbolWeightBold];
        // Lit as the lyrics and queue buttons are: their light disc with the glyph cut out (its owner, 2026-11-06).
        glyph.image = cutDiscImage(symbol, look, badge.bounds.size.width);
    }
    CGFloat alpha = symbol ? 1 : 0;
    if (badge.alpha == alpha) return;
    void (^change)(void) = ^{
        badge.alpha = alpha;
        badge.transform = symbol ? CGAffineTransformIdentity : CGAffineTransformMakeScale(0.6, 0.6);
    };
    if (animated) SGRAnimate(SGRMotionRespond, change, nil);
    else change();
}

NSString *SGRSystemOptionBadgeSymbol(SPTPlayerState *state, BOOL shuffleHidden, BOOL repeatHidden) {
    SPTPlayerOptions *options = [state respondsToSelector:@selector(options)] ? state.options : nil;
    if (shuffleHidden && SGRSystemOptionAllowed(state, NO) && options.shufflingContext) return @"shuffle";
    if (repeatHidden && SGRSystemOptionAllowed(state, YES)) {
        if (options.repeatingTrack) return @"repeat.1";
        if (options.repeatingContext) return @"repeat";
    }
    return nil;
}
