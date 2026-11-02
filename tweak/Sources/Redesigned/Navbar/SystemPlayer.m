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
// Turned sideways with the lyrics up, the redesign's landscape lyrics screen comes up over the page, by its own rule
// (PlayerLandscape.x, told through SGRPlayerSetPageLyricsOpen); the page itself stays portrait (its owner, 2026-11-01:
// left to turn, it stretched into a broken landscape layout).
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
#import "Settings/SGMarquee.h"
#import "Shared/Player/SpeedPitch.h"
#import "Redesigned/Kit/SGRKit.h"
#import "Redesigned/Artist/Artist.h"
#import "Redesigned/Lyrics/SGRKaraokeView.h"
#import "Redesigned/Lyrics/SGRSingButton.h"
#import "Redesigned/NowPlayingBar/NowPlayingBar.h"
#import "Redesigned/Player/Player.h"
#import "Shared/Player/PlayerState.h"
#import "Shared/Player/SGLastTrack.h"
#import "Shared/Navigation/Links.h"
#import "Shared/Sing/Sing.h"
#import "SystemPlayer.h"
#import "SystemQueue.h"

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

// A light disc with `symbol` cut out of it, at the glyph buttons' 20 pt regular, hidden until shown.
static UIImageView *cutDisc(NSString *symbol) {
    CGFloat side = kQueueBubble;
    UIImageSymbolConfiguration *config = [UIImageSymbolConfiguration configurationWithPointSize:20 weight:UIImageSymbolWeightRegular];
    UIImage *glyph = [UIImage systemImageNamed:symbol withConfiguration:config];
    UIGraphicsImageRenderer *renderer = [[UIGraphicsImageRenderer alloc] initWithSize:CGSizeMake(side, side)];
    UIImage *disc = [renderer imageWithActions:^(UIGraphicsImageRendererContext *context) {
        [[UIColor colorWithWhite:1 alpha:kQueueBubbleWhite] setFill];
        [[UIBezierPath bezierPathWithOvalInRect:CGRectMake(0, 0, side, side)] fill];
        if (!glyph) return;
        CGSize size = glyph.size;
        [glyph drawInRect:CGRectMake(round((side - size.width) / 2), round((side - size.height) / 2), size.width, size.height)
                blendMode:kCGBlendModeDestinationOut alpha:1];
    }];
    UIImageView *view = [[UIImageView alloc] initWithImage:disc];
    view.userInteractionEnabled = NO;
    view.alpha = 0;
    return view;
}
// The bottom row's middle above the safe area's bottom, never less than the minimum above the screen's, and the route
// line's middle under it: the redesigned player's footer's (PlayerFooter.x's kRowAboveSafeArea, kRowMinBottom and
// kRouteLineDrop), which leave the line its room over the home indicator.
static const CGFloat kRowAboveSafeArea = 32, kRowMinBottom = 34, kRouteLineDrop = 32;
// The add button's glyph beside the title and artist, and its touch square.
static const CGFloat kAddGlyph = 28, kAddSide = 44;
// The layout from the bottom row up, the redesigned player's as its owner's screenshots of the two show it, on a 440x956
// screen (2026-11-01): the volume's middle above the row's, the controls' above the volume's, the times' above the
// controls', the progress bar's above the times'; the header's circles in from the sides and down from the safe area;
// previous and next out from the middle as a share of the width between the margins; the bottom row's glyphs at a
// fifth, half and four fifths of the width, as PlayerFooter.x places them (kLeading, kMiddle, kTrailing).
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

static char kCloseGlassKey, kMoreGlassKey, kConnectKey;

static BOOL isTrack(id track) {
    return [track isKindOfClass:NSClassFromString(@"SPTPlayerTrack")];
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

// The progress bar, drawn as the volume row is (PlayerVolume.m): a thin pill that grows while held, moved by the finger's
// travel from where it came down. The player seeks once the finger lets go.
@interface SGRSystemScrubber : UIControl
@property (nonatomic) CGFloat value;    // 0 to 1
@property (nonatomic, readonly) BOOL held;
@property (nonatomic, copy) void (^onMove)(CGFloat value);
@property (nonatomic, copy) void (^onRelease)(CGFloat value);
// The times under the bar, moved in with it at rest and out to its ends held (ElasticSlider's bottom labels).
@property (nonatomic, weak) UIView *leadingLabel, *trailingLabel;
- (void)letGoOfPans;
@end

@implementation SGRSystemScrubber {
    UIView *_track, *_fill;
    CGFloat _startValue, _startX;
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

- (BOOL)beginTrackingWithTouch:(UITouch *)touch withEvent:(UIEvent *)event {
    _startX = [touch locationInView:self].x;
    _startValue = _value;
    [self setHeld:YES];
    return YES;
}

- (BOOL)continueTrackingWithTouch:(UITouch *)touch withEvent:(UIEvent *)event {
    if (!_suspended && fabs([touch locationInView:self].x - _startX) > kScrubDragStart) {
        _suspended = suspendPansAbove(self);
        [self performSelector:@selector(checkSuspended) withObject:nil afterDelay:1];
    }
    self.value = _startValue + ([touch locationInView:self].x - _startX) / MAX(1, self.bounds.size.width);
    if (self.onMove) self.onMove(_value);
    return YES;
}

- (void)endTrackingWithTouch:(UITouch *)touch withEvent:(UIEvent *)event {
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

// The skip's step, the Music app's, measured frame by frame from its owner's 60 fps recording of it (2026-11-01), from the
// finger's lift. Animated over 0.9 of kForwardDuration, and no more often than once a
// length, the latest tap kept.
// Its length, its ease (the power its slowing takes), how soon the front glyph is away (a multiple of the step) and how
// far it drifts (a share of the arrow) are its owner's, tuned on the phone (2026-11-01).
static const NSTimeInterval kForwardDuration = 0.34;

#pragma mark - the skip's arrow

// The Music app's skip, as its frames show it: the double arrow's front glyph greys and shrinks away in place, drifting a
// little on; the back one slides at full size into the front's place; and a new back glyph grows out of a dot in the back
// place, greying in. At the end it is the double arrow again. Laid out by hand: three play.fill glyphs, each half the
// double arrow's width and `size` high, scaled about their own middles, in a box wider than the arrow so the front glyph
// can drift. Mirrored for previous. (It was f728743/AppleMusicStylePlayer's ForwardLabel, which squeezes the glyphs'
// widths instead; it read as another motion, too quick or too slow at any length.)
static const CGFloat kForwardBoxShare = 1.5, kForwardDrift = 0, kForwardEase = 1, kForwardAway = 3;

@interface SGRForwardLabel : UIView
@property (nonatomic) CGFloat size;
@property (nonatomic) CGFloat progress;
- (instancetype)initWithSize:(CGFloat)size tint:(UIColor *)tint;
@end

@implementation SGRForwardLabel {
    UIImageView *_back, *_middle, *_front;
}

- (instancetype)initWithSize:(CGFloat)size tint:(UIColor *)tint {
    if (!(self = [super initWithFrame:CGRectMake(0, 0, size * kForwardBoxShare, size)])) return nil;
    _size = size;
    self.userInteractionEnabled = NO;
    UIImage *glyph = [[UIImage systemImageNamed:@"play.fill" withConfiguration:[UIImageSymbolConfiguration configurationWithPointSize:size]]
                      imageWithRenderingMode:UIImageRenderingModeAlwaysTemplate];
    for (int i = 0; i < 3; i++) {
        UIImageView *view = [[UIImageView alloc] initWithImage:glyph];
        view.contentMode = UIViewContentModeScaleAspectFit;
        view.tintColor = tint;
        view.bounds = CGRectMake(0, 0, size / 2, size);
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
    // Eased out, as the frames slow to the end.
    CGFloat p = _progress, e = 1 - pow(1 - p, kForwardEase), size = _size;
    CGFloat left = (self.bounds.size.width - size) / 2, mid = self.bounds.size.height / 2;
    CGFloat backX = left + size / 4, frontX = left + size * 3 / 4;
    // The front glyph: away within the first two thirds, drifting on.
    CGFloat away = MIN(1, e * kForwardAway);
    _front.center = CGPointMake(frontX + kForwardDrift * size * e, mid);
    _front.transform = CGAffineTransformMakeScale(MAX(0.001, 1 - away), MAX(0.001, 1 - away));
    _front.alpha = 1 - away;
    // The back glyph to the front's place, whole.
    _middle.center = CGPointMake(backX + (frontX - backX) * e, mid);
    _middle.transform = CGAffineTransformIdentity;
    // The new back glyph out of a dot.
    _back.center = CGPointMake(backX, mid);
    _back.transform = CGAffineTransformMakeScale(MAX(0.001, e), MAX(0.001, e));
    _back.alpha = e;
}
@end

@interface SGRSystemControlButton : SGRGlyphButton
// The glyph's scale and opacity while held (shuffle and repeat).
@property (nonatomic) CGFloat heldScale, heldAlpha;
// Previous, play and pause, and next: PlayerButton.swift's press (above) instead.
@property (nonatomic) BOOL transport;
// Steps the double arrow along as ForwardLabel.swift does: 1 forward (next), -1 back (previous).
- (void)stepArrow:(NSInteger)direction;
// Play and pause turned the way SwiftUI's .replace (down-up) does in Sim Radio's PlayerButton.swift: the old symbol
// shrinks and fades into the middle while the new one grows out of it. Drawn on two plain pictures of the symbols, each
// its own size about the button's middle, not by UIKit's symbol replace, which on the phone drew the new symbol grown and
// 6 pt off the middle at the swap's start whatever variant it was asked for (its owner's recordings and the phone's log,
// 2026-11-02). The glyph itself waits out the swap unseen, at rest. The same symbol again is a no-op.
- (void)turnToSymbol:(NSString *)symbol animated:(BOOL)animated;

// On, the Music app's way for shuffle and repeat (its owner, 2026-11-01: the same color on and off was hard to tell
// apart): the glyph knocked out of a filled rounded square in `color`; off, the plain glyph in `plain`. The fill comes and
// goes with a fade and a small scale (the fade alone under Reduce Motion).
- (void)setLit:(BOOL)lit color:(UIColor *)color plain:(UIColor *)plain animated:(BOOL)animated;
@end

// The play and pause turn (turnToSymbol:): the scale the symbols leave to and come from, the old one's way out, the new
// one's spring in (SwiftUI's replace, about a third of a second, a little bounce) and how far into the way out it starts.
static const CGFloat kTurnScale = 0.2, kTurnBounce = 0.15;
static const NSTimeInterval kTurnOut = 0.14, kTurnIn = 0.32, kTurnDelay = 0.07;

// The fill's padding round the glyph, its corners, and the knocked out glyph's ink (dark enough on a pale cover color).
static const CGFloat kLitPadding = 7, kLitInkWhite = 0.08, kLitInkAlpha = 0.9, kLitEnterScale = 0.8;

@implementation SGRSystemControlButton {
    UIView *_halo, *_fill;
    NSUInteger _pressSerial;
    NSString *_turningTo;      // the symbol a running turn goes to
    NSUInteger _turnSerial;
    UIImageView *_turnOld, *_turnNew;
    BOOL _lit, _litSet;
    // The arrow's step: the label while it runs, its clock, when the last began and whether a tap waits for the window.
    SGRForwardLabel *_forward;
    CADisplayLink *_forwardLink;
    CFTimeInterval _forwardStart, _forwardLastBegan;
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
    [self insertSubview:_fill aboveSubview:_halo];
    return self;
}

- (void)setLit:(BOOL)lit color:(UIColor *)color plain:(UIColor *)plain animated:(BOOL)animated {
    if (![_fill.backgroundColor isEqual:color]) _fill.backgroundColor = color;
    static UIColor *litInk;
    if (!litInk) litInk = [UIColor colorWithWhite:kLitInkWhite alpha:kLitInkAlpha];
    UIColor *ink = lit ? litInk : plain;
    BOOL changed = !_litSet || lit != _lit;
    _lit = lit;
    _litSet = YES;
    SGRGlyphView *glyph = self.glyph;
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
// 0.9 of kForwardDuration, linearly (the curves are the label's own), and the glyph comes back at the end, where the label
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
    if (_forwardLink || now < next) {
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
    if (_forwardLink || !self.window) return;
    SGRGlyphView *glyph = self.glyph;
    // The label's size is the glyph's width: at rest its two glyphs, half that each, are the double arrow.
    CGFloat size = glyph.bounds.size.width;
    if (size <= 0) return;
    _forward = [[SGRForwardLabel alloc] initWithSize:size tint:glyph.tintColor ?: SGRPrimary()];
    _forward.center = glyph.center;
    _forward.transform = CGAffineTransformScale(glyph.transform, _forwardDirection < 0 ? -1 : 1, 1);
    [self addSubview:_forward];
    glyph.hidden = YES;
    _forwardLastBegan = _forwardStart = CACurrentMediaTime();
    _forwardLink = [CADisplayLink displayLinkWithTarget:self selector:@selector(forwardTicked:)];
    // The screen's full rate: a link that asks for none is held to 60 Hz on a 120 Hz screen, and the step looked slow and
    // stepped beside the press's springs (its owner, 2026-11-01). Spotify's Info.plist lets the app past 60
    // (CADisableMinimumFrameDurationOnPhone).
    _forwardLink.preferredFrameRateRange = CAFrameRateRangeMake(80, 120, 120);
    [_forwardLink addToRunLoop:NSRunLoop.mainRunLoop forMode:NSRunLoopCommonModes];
}

- (void)forwardTicked:(CADisplayLink *)link {
    CGFloat progress = (CACurrentMediaTime() - _forwardStart) / (kForwardDuration * 0.9);
    _forward.transform = CGAffineTransformScale(self.glyph.transform, _forwardDirection < 0 ? -1 : 1, 1);
    _forward.progress = progress;
    if (progress < 1 && self.window) return;
    [_forwardLink invalidate];
    _forwardLink = nil;
    [_forward removeFromSuperview];
    _forward = nil;
    self.glyph.hidden = NO;
}

- (void)didMoveToWindow {
    [super didMoveToWindow];
    if (self.window || !_forwardLink) return;
    [_forwardLink invalidate];
    _forwardLink = nil;
    [_forward removeFromSuperview];
    _forward = nil;
    self.glyph.hidden = NO;
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
    _glyph.tintColor = SGRPrimary();
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
    NSString *where = [place copy];
    button.onHold = ^{
        NSString *how = nil;
        BOOL asked = openSpotifyConnect(&how);
        SGLog(@"system player: held AirPlay on %@, Spotify's Connect sheet %@ by %@", where, asked ? @"asked for" : @"not asked for", how);
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

@interface SGRSystemPlayerPage () <SGPlayerStateObserver, UIGestureRecognizerDelegate>
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
    SGRGlyphButton *_close;
    UIButton *_more;
    UILabel *_context;
    UIView *_coverHolder;   // the shadow; scaled when paused
    UIImageView *_cover;
    SGMarqueeLabel *_title, *_artist;
    UIView *_titleBlock;                       // the title and artist, the swipe's page
    CAGradientLayer *_titleFade;
    SGMarqueeLabel *_besideTitle, *_besideArtist;   // the track the swipe brings in
    BOOL _titleSkipping;
    NSString *_titleSkipFrom;                  // the track the swipe skipped from
    BOOL _episode;                             // an episode or a chapter plays: 15 s skips, the speed in shuffle's place
    BOOL _volumeOff, _shuffleOff, _repeatOff;  // the Player page's Volume off, Hide on the player's Shuffle and Repeat
    UIButton *_speed;
    SGRGlyphButton *_add;
    id _savedWatch;
    NSString *_savedTrack;
    BOOL _savedShown;
    SGRSystemScrubber *_scrubber;
    UILabel *_elapsed, *_remaining;
    SGRSystemControlButton *_shuffle, *_previous, *_play, *_next, *_repeat;
    UIControl *_volume;
    SGRGlyphButton *_lyrics, *_queue;
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
    id _spotifyQueue;             // Spotify's queue as last fetched (SPTPlayerQueue), handed back with a track moved
    SGRSystemQueueView *_queueView;   // out of the page while closed
    UIImageView *_queueBubble;        // the queue button's light disc while the queue is open, the Music app's
    UIImageView *_lyricsBubble;       // the lyrics button's, while the lyrics are up
    BOOL _alone;      // the lines have the page to themselves
    NSTimer *_rest;
    SGRSystemTouchWatcher *_watcher;
    UITapGestureRecognizer *_wake;   // on while alone: the tap that brings the rest back
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
    NSString *_coverTrack;   // the track the cover last changed for, for the log
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
    // The add button beside the title, where Spotify's player has its own (InformationElementsUnit's
    // Components.UI.AddToButton, kept by the redesigned player): a plus while the track is not in Liked Songs, the
    // accent's filled tick once it is (a plain tick with Plain checkmark on, SGRPlainCheck.x).
    _add = [SGRGlyphButton buttonWithSymbol:@"plus.circle" pointSize:kAddGlyph title:@"Add to Liked Songs"];
    _add.glyph.tintColor = SGRPrimary();
    _add.onTap = ^{ [weakSelf toggleSaved]; };

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
        BOOL asked = openSpotifyConnect(&how);
        SGLog(@"system player: held AirPlay, Spotify's Connect sheet %@ by %@", asked ? @"asked for" : @"not asked for", how);
        // Whether it came up over the page, either way: a link taken that presents nothing says so too.
        [weakSelf noteSheetFor:@"Connect"];
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
    // A tap turns the page to its queue, as the Music app's does (its owner, 2026-11-02); a hold still opens Spotify's
    // queue sheet, for what the page's queue does not do (moving and removing tracks).
    _queue.onTap = ^{ [weakSelf toggleQueue]; };
    // Dim while the queue is closed; open, the Music app's way (its owner's screenshot, 2026-11-02): a light disc behind
    // it and the glyph dark on it.
    _queue.glyph.tintColor = SGRSecondary();
    _queueBubble = cutDisc(@"list.bullet");
    [_queue insertSubview:_queueBubble atIndex:0];
    _lyricsBubble = cutDisc(kLyricsSymbolOpen);
    [_lyrics insertSubview:_lyricsBubble atIndex:0];
    UILongPressGestureRecognizer *queueHold = [[UILongPressGestureRecognizer alloc] initWithTarget:self action:@selector(queueHeld:)];
    [_queue addGestureRecognizer:queueHold];
    _queueView = [SGRSystemQueueView new];
    _queueView.alpha = 0;
    _queueView.onReorder = ^(NSArray *upcoming) { [weakSelf handQueueBack:upcoming]; };
    _queueView.onPick = ^(SPTPlayerTrack *track) {
        id<SPTPlayer> player = (id<SPTPlayer>)SGPlayer();
        if ([player respondsToSelector:@selector(skipToNextTrackWithOptions:track:)]) [player skipToNextTrackWithOptions:nil track:track];
        SGLog(@"system player: queue track picked, %@", track.trackTitle);
    };

    // The lines, and in their place while they have none to show (the karaoke view fades its siblings out while it
    // has), the look for them or the word that there are none.
    _stage = [UIView new];
    _stage.alpha = 0;
    _lines = [[SGRKaraokeView alloc] initWithFrame:CGRectZero];
    _lines.autoresizingMask = UIViewAutoresizingFlexibleWidth | UIViewAutoresizingFlexibleHeight;
    // Sing's mic stays with the lines on their own, as in the redesigned player (PlayerLyrics.x).
    _lines.keepsSing = YES;
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

    for (UIView *sub in @[_close, _more, _context, _coverHolder, _titleBlock, _speed, _add, _scrubber, _elapsed, _remaining, _shuffle, _previous, _play,
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

// Portrait only. Sideways, the redesign's landscape lyrics screen comes up over the page in a window of its own while
// the lyrics are up (PlayerLandscape.x); the page itself, left to turn, laid its controls out stretched (its owner,
// 2026-11-01).
- (UIInterfaceOrientationMask)supportedInterfaceOrientations {
    return UIInterfaceOrientationMaskPortrait;
}

- (UIInterfaceOrientation)preferredInterfaceOrientationForPresentation {
    return UIInterfaceOrientationPortrait;
}

- (void)dealloc {
    [_timer invalidate];
    [_rest invalidate];
}

// The progress runs on a timer only while the page is up, four times a second: the times change by the second, and a
// display link would pin the zoom's frames to its rate.
- (void)viewWillAppear:(BOOL)animated {
    [super viewWillAppear:animated];
    [_timer invalidate];
    __weak typeof(self) weakSelf = self;
    _timer = [NSTimer timerWithTimeInterval:0.25 repeats:YES block:^(NSTimer *timer) { [weakSelf tick]; }];
    _timer.tolerance = 0.05;   // lets iOS fold the ticks into other wakes
    [NSRunLoop.mainRunLoop addTimer:_timer forMode:NSRunLoopCommonModes];
    [self tick];
    [self syncRouteLine];
    SGRPlayerSetPageLyricsOpen(_lyricsOpen);
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

// The open has landed (kTouchesAfter in, or viewDidAppear:): the bars' touches are let in.
- (void)openLanded {
    if (_appeared || !self.view.window || self.isBeingDismissed) return;
    _appeared = YES;
    _scrubber.userInteractionEnabled = _volume.userInteractionEnabled = YES;
}

- (void)viewDidAppear:(BOOL)animated {
    [super viewDidAppear:animated];
    [self openLanded];
    // Animated's clip is looked up only while the page is in a window (SGRPlayerMotionPreview).
    if (_background == SGRPlayerBackgroundAnimated && !_motion) [self syncClipAnimated:YES];
    [self restartRest];
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
    SGRPlayerSetPageLyricsOpen(NO);
    SGRPlayerShowLandscape(NO);
}

- (void)viewDidDisappear:(BOOL)animated {
    [super viewDidDisappear:animated];
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
    UIEdgeInsets safe = self.view.safeAreaInsets;
    CGFloat width = bounds.size.width, height = bounds.size.height, inner = MAX(0, width - 2 * kMargin);
    _backdrop.frame = bounds;
    _blur.frame = bounds;
    _shade.frame = bounds;
    _field.frame = bounds;
    _field.backdropHeight = height;
    _motion.frame = bounds;
    _visualiser.frame = bounds;

    // The header: the close button at the leading edge, the ⋯ its mirror at the trailing edge, the album between them.
    CGFloat top = safe.top + kHeaderDrop, button = SGRGlassCircleSize;
    _close.frame = CGRectMake(kHeaderSide, top, button, button);
    SGRGlassInside(_close, &kCloseGlassKey, SGRGlassCircleSize);
    _more.frame = CGRectMake(width - kHeaderSide - button, top, button, button);
    SGRGlassInside(_more, &kMoreGlassKey, SGRGlassCircleSize);
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
    CGFloat lineHeight = ceil(_routeLine.font.lineHeight);
    _routeLine.frame = CGRectMake(24, round(rowMid + kRouteLineDrop - lineHeight / 2), MAX(0, width - 48), lineHeight);
    CGFloat volumeMid = rowMid - kVolumeAboveRow;
    _volume.frame = CGRectMake(kMargin, volumeMid - 16, inner, 32);
    CGFloat controlsMid = _volumeOff ? rowMid - kControlsAboveRowAlone : volumeMid - kControlsAboveVolume;
    _play.bounds = CGRectMake(0, 0, 64, 64);
    _previous.bounds = _next.bounds = CGRectMake(0, 0, 56, 56);
    _shuffle.bounds = _repeat.bounds = CGRectMake(0, 0, 44, 44);
    _shuffle.center = CGPointMake(kMargin + 12, controlsMid);
    _previous.center = CGPointMake(round(width / 2 - inner * kSkipShare), controlsMid);
    _play.center = CGPointMake(width / 2, controlsMid);
    _next.center = CGPointMake(round(width / 2 + inner * kSkipShare), controlsMid);
    _repeat.center = CGPointMake(width - kMargin - 12, controlsMid);
    CGFloat timesHeight = ceil(_elapsed.font.lineHeight), timesMid = controlsMid - kTimesAboveControls, timesY = round(timesMid - timesHeight / 2);
    _elapsed.frame = CGRectMake(kMargin, timesY, inner / 2, timesHeight);
    _remaining.frame = CGRectMake(kMargin + inner / 2, timesY, inner / 2, timesHeight);
    CGFloat scrubberY = round(timesMid - kScrubberAboveTimes - kScrubberHeight / 2);
    _scrubber.frame = CGRectMake(kMargin, scrubberY, inner, kScrubberHeight);
    CGFloat titleHeight = ceil(_title.font.lineHeight), artistHeight = ceil(_artist.font.lineHeight);
    CGFloat artistY = scrubberY - 14 - artistHeight, titleY = artistY - titleHeight;

    // The cover takes the room left between the header and the title, as wide as the margins allow.
    CGFloat roomTop = headerBottom + 20, room = MAX(0, titleY - 28 - roomTop);
    CGFloat side = floor(MIN(inner, room));
    _coverHolder.bounds = CGRectMake(0, 0, side, side);
    _coverHolder.center = CGPointMake(width / 2, round(roomTop + room / 2));
    if (!CGRectEqualToRect(_shadowBounds, _coverHolder.bounds)) {
        _shadowBounds = _coverHolder.bounds;
        _coverHolder.layer.shadowPath = [UIBezierPath bezierPathWithRoundedRect:_shadowBounds cornerRadius:SGRRadiusArtwork].CGPath;
    }
    _cover.frame = _coverHolder.bounds;

    // With the lyrics up, the Music app's top row: the cover as a thumbnail under the header with the title and artist
    // beside it, and the lines from there down to the progress. The stage keeps its place either way, so the lines come
    // and go where they stand. On their own, the lines take the whole safe area, kAloneInset in at both ends (with
    // Keep the title, from where they stood down): aloneStage.
    CGRect thumb = CGRectMake(kMargin, headerBottom + 16, kThumbSide, kThumbSide);
    CGFloat stageTop = CGRectGetMaxY(thumb) + 8;
    CGRect stage = CGRectMake(0, stageTop, width, MAX(0, scrubberY - 8 - stageTop));
    _stage.frame = _alone ? [self aloneStageFrom:stage] : stage;
    _lyricsNote.frame = CGRectInset(_stage.bounds, kMargin, 0);
    _lyricsSpinner.frame = _stage.bounds;
    _queueView.frame = stage;
    // The add button at the trailing margin, its glyph's edge on it, centered on the title and artist; they end before it.
    CGFloat addInset = (kAddSide - kAddGlyph) / 2, textRight = width - kMargin - (_add.hidden ? 0 : kAddSide - addInset + 8);
    BOOL topRow = _lyricsOpen || _queueOpen;
    CGFloat textX = topRow ? CGRectGetMaxX(thumb) + kThumbGap : kMargin;
    CGFloat textY = topRow ? round(CGRectGetMidY(thumb) - (titleHeight + artistHeight) / 2) : titleY;
    CGFloat textWidth = MAX(0, textRight - textX);
    _titleBlock.frame = CGRectMake(textX - kTitleFade, textY, textWidth + 2 * kTitleFade, titleHeight + artistHeight);
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
    _add.center = CGPointMake(width - kMargin - kAddSide / 2 + addInset, round(textY + (titleHeight + artistHeight) / 2));
    _speed.bounds = CGRectMake(0, 0, 56, 44);
    _speed.center = _shuffle.center;
    _thumb = thumb;
    // The thumbnail is the cover moved and scaled by its transform, so its shadow and corners travel with it; the corners
    // are given back the thumbnail's radius at that scale.
    CGFloat scale = side > 0 ? kThumbSide / side : 1;
    _cover.layer.cornerRadius = topRow ? SGRRadiusThumb / scale : SGRRadiusArtwork;
    _coverHolder.transform = [self coverTransform];
    // The hold for 2× on the cover, as on the player's.
    SGRPlayerAttachCoverHold(_coverHolder);
}

// The thumbnail while the lyrics are up; otherwise full size, smaller while paused (held at full size under Reduce
// Motion, as in the redesigned player).
- (CGAffineTransform)coverTransform {
    CGFloat side = _coverHolder.bounds.size.width;
    if ((_lyricsOpen || _queueOpen) && side > 0) {
        CGFloat scale = kThumbSide / side;
        CGPoint center = _coverHolder.center;
        CGAffineTransform move = CGAffineTransformMakeTranslation(round(CGRectGetMidX(_thumb) - center.x), round(CGRectGetMidY(_thumb) - center.y));
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

// What the ⋯ can do without Spotify's player (the header comment says why its sheet is out of reach): Liked Songs and
// share, the album and the artist, then the player's own items.
- (NSArray<UIMenuElement *> *)menuItems {
    SPTPlayerTrack *track = isTrack(SGPlayerState().track) ? SGPlayerState().track : nil;
    NSString *uri = SGURIString(track.URI);
    NSArray<NSString *> *parts = [uri componentsSeparatedByString:@":"];
    NSString *kind = parts.count == 3 ? parts[1] : nil;
    NSMutableArray<UIMenuElement *> *first = [NSMutableArray array], *places = [NSMutableArray array];
    __weak typeof(self) weakSelf = self;
    if ([kind isEqualToString:@"track"]) {
        BOOL saved = _savedShown;
        UIAction *like = [UIAction actionWithTitle:saved ? @"Remove from Liked Songs" : @"Add to Liked Songs"
                                             image:[UIImage systemImageNamed:saved ? @"checkmark.circle.fill" : @"plus.circle"] identifier:nil
                                           handler:^(UIAction *action) { [weakSelf toggleSaved]; }];
        [first addObject:like];
    }
    // A share link for what has one on open.spotify.com: a track or an episode, by its id.
    if (([kind isEqualToString:@"track"] || [kind isEqualToString:@"episode"]) && parts[2].length) {
        NSURL *link = [NSURL URLWithString:[NSString stringWithFormat:@"https://open.spotify.com/%@/%@", kind, parts[2]]];
        [first addObject:[UIAction actionWithTitle:@"Share" image:[UIImage systemImageNamed:@"square.and.arrow.up"] identifier:nil
                                           handler:^(UIAction *action) { [weakSelf share:link]; }]];
    }
    // The album from the track's metadata (album_uri, beside the album_title the header reads; a key of the player's
    // metadata in the 9.1.90 binary) and the artist from the track itself (Headers/SPTPlayer.h's artistURI).
    id album = track.metadata[@"album_uri"];
    NSString *albumURI = [album isKindOfClass:NSString.class] && [album hasPrefix:@"spotify:album:"] ? album : nil;
    if (albumURI) {
        [places addObject:[UIAction actionWithTitle:@"Go to Album" image:[UIImage systemImageNamed:@"square.stack"] identifier:nil
                                            handler:^(UIAction *action) { [weakSelf closeAndOpen:albumURI]; }]];
    }
    NSString *artistURI = SGURIString(track.artistURI);
    if ([artistURI hasPrefix:@"spotify:artist:"]) {
        [places addObject:[UIAction actionWithTitle:@"Go to Artist" image:[UIImage systemImageNamed:@"music.microphone"] identifier:nil
                                            handler:^(UIAction *action) { [weakSelf closeAndOpen:artistURI]; }]];
    }
    NSMutableArray<UIMenuElement *> *menu = [NSMutableArray array];
    if (first.count) [menu addObject:inlineGroup(first)];
    if (places.count) [menu addObject:inlineGroup(places)];
    NSArray<UIMenuElement *> *own = SGRPlayerMenuPageItems(_more, ^{ [weakSelf reloadBackgroundAnimated:YES]; });
    if (own.count) [menu addObject:inlineGroup(own)];
    static int logged;
    if (logged++ < 3) SGLog(@"system player: the ⋯ menu for %@: %lu of the mod's items (album %@, artist %@); Spotify's own rows need its player",
                            uri, (unsigned long)(first.count + places.count + own.count), albumURI ? @"known" : @"unknown", artistURI.length ? @"known" : @"unknown");
    return menu;
}

- (void)share:(NSURL *)link {
    UIActivityViewController *share = [[UIActivityViewController alloc] initWithActivityItems:@[link] applicationActivities:nil];
    share.popoverPresentationController.sourceView = _more;
    share.popoverPresentationController.sourceRect = _more.bounds;
    SGPresentDark(share);
    [self presentViewController:share animated:YES completion:nil];
}

// A page of Spotify's opens in its navigation under the page, so the page closes first, as the Music app's player does
// for Go to Album.
- (void)closeAndOpen:(NSString *)uri {
    SGLog(@"system player: the page closes for %@", uri);
    [self dismissViewControllerAnimated:YES completion:^{
        if (!SGOpenSpotifyURI([NSURL URLWithString:uri])) SGLog(@"system player: %@ not opened (no link dispatcher)", uri);
    }];
}

#pragma mark - the add button

// The playing track's place in Liked Songs, from Spotify's collection state (Redesigned/Artist/Artist.h's
// SGRCollectionWatchURI, the state the artist page's Follow reads), watched from a track change on.
- (void)syncSaved {
    SPTPlayerTrack *track = isTrack(SGPlayerState().track) ? SGPlayerState().track : nil;
    NSString *uri = SGURIString(track.URI);
    BOOL saveable = [uri hasPrefix:@"spotify:track:"];
    if (_add.hidden == saveable) {
        _add.hidden = !saveable;
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
    NSString *symbol = !saved ? @"plus.circle" : SGRPlainCheckOn() ? @"checkmark" : @"checkmark.circle.fill";
    [_add.glyph setSymbol:symbol animated:animated && self.view.window];
    UIColor *tint = saved ? SGRPlayerLitColor() : SGRPrimary();
    if (![_add.glyph.tintColor isEqual:tint]) _add.glyph.tintColor = tint;
    _add.accessibilityLabel = saved ? @"Remove from Liked Songs" : @"Add to Liked Songs";
}

// Spotify's add button saves to Liked Songs, with its own confirmation; this one does that, and takes the track out
// again from the tick, where Spotify's opens its Add to playlist sheet, which nothing here can reach. The glyph turns at
// once and the collection's own answer follows.
- (void)toggleSaved {
    NSString *uri = _savedTrack;
    if (!uri) return;
    BOOL want = !_savedShown;
    if (!SGRCollectionSetSaved([NSURL URLWithString:uri], want)) return;
    [[[UIImpactFeedbackGenerator alloc] initWithStyle:UIImpactFeedbackStyleLight] impactOccurred];
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
            _visualiser.frame = self.view.bounds;
            [self.view insertSubview:_visualiser aboveSubview:_field];
            [self fadeIn:_visualiser animated:animated];
        }
        SGLog(@"system player: background %@", SGRPlayerBackgroundNames()[(NSUInteger)kind]);
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
    BOOL wanted = _background == SGRPlayerBackgroundAnimated && track;
    if (wanted && _motion && [track isEqualToString:_motionTrack]) return;
    UIView *clip = nil;
    if (wanted) {
        __weak typeof(self) weakSelf = self;
        void (^arrived)(void) = !self.view.window ? nil : ^{ [weakSelf syncClipAnimated:YES]; };
        clip = SGRPlayerMotionPreview(arrived);
    }
    if (!clip && !_motion) return;
    // The last track's clip, or a clip no longer wanted, goes; Fluid is under it.
    [self fadeOut:_motion animated:animated];
    _motion = clip;
    _motionTrack = clip ? track : nil;
    if (clip) {
        clip.userInteractionEnabled = NO;
        clip.frame = self.view.bounds;
        [self.view insertSubview:clip aboveSubview:_field];
        [self fadeIn:clip animated:animated];
    }
    SGLog(@"system player: animated artwork %@ for %@", clip ? @"shown" : @"none, Fluid shows", track);
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
    BOOL shown = (!_motion || _lyricsOpen || _queueOpen) && !(_alone && SGRLyricsHideMode() != SGRLyricsHideControls);
    CGFloat alpha = shown ? 1 : 0;
    if (_coverHolder.alpha == alpha) return;
    UIView *cover = _coverHolder;
    if (animated && self.view.window) SGRAnimate(SGRMotionFade, ^{ cover.alpha = alpha; }, nil);
    else cover.alpha = alpha;
}

- (void)syncFieldHeld {
    BOOL held = !SGPlayerState() || SGPlayerState().isPaused || _motion != nil || _visualiser != nil;
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

- (void)show:(SPTPlayerState *)state {
    SPTPlayerTrack *track = isTrack(state.track) ? state.track : nil;
    _title.text = track.trackTitle;
    _artist.text = artistLine(track);
    _context.text = contextTitle(state, track);
    if (_queueOpen) [self refreshQueue];
    [self syncEpisode:track];
    // The swipe settled on this track already: the labels, which now show it, go back to the middle.
    if (_titleSkipping && ![SGURIString(track.URI) isEqualToString:_titleSkipFrom]) [self endTitleSkip];
    BOOL paused = !state || state.isPaused;
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

- (void)showOptions:(SPTPlayerState *)state {
    SPTPlayerOptions *options = [state respondsToSelector:@selector(options)] ? state.options : nil;
    BOOL shuffling = options.shufflingContext, track = options.repeatingTrack, context = options.repeatingContext;
    // Lit as the redesigned player lights its controls (SGRPlayerLitColor); off, the color of every other control on the
    // page (its owner, 2026-11-01).
    UIColor *lit = SGRPlayerLitColor(), *plain = SGRPrimary();
    BOOL animated = _shownOnce && self.view.window;
    [_shuffle setLit:shuffling color:lit plain:plain animated:animated];
    [_repeat setLit:track || context color:lit plain:plain animated:animated];
    [_repeat.glyph setSymbol:track ? @"repeat.1" : @"repeat" animated:_shownOnce];
    _shuffle.accessibilityValue = shuffling ? @"On" : @"Off";
    _repeat.accessibilityValue = track ? @"Track" : context ? @"On" : @"Off";
}

- (void)tick {
    [self syncLyrics];
    if (_episode) [self syncEpisode:(isTrack(SGPlayerState().track) ? SGPlayerState().track : nil)];
    if (_scrubber.held) return;
    SPTPlayerState *state = SGPlayerState();
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
        SGLog(@"system player: lyrics of %@ %@", track, shown == SGRSystemLyricsLines ? @"in" : shown == SGRSystemLyricsNone ? @"none" : @"being looked for");
        _lyricsShown = shown;
        _lyricsTrack = track;
    }
    _lyricsNote.hidden = shown != SGRSystemLyricsNone;
    if (shown == SGRSystemLyricsLoading) [_lyricsSpinner startAnimating];
    else [_lyricsSpinner stopAnimating];

    // As the footer's: dimmed and off without lines, but always on while the lyrics are up, the way back to the cover.
    BOOL enabled = lines || _lyricsOpen;
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

- (void)queueHeld:(UILongPressGestureRecognizer *)hold {
    if (hold.state != UIGestureRecognizerStateBegan) return;
    BOOL sent = SGOpenSpotifyURI([NSURL URLWithString:@"spotify:now-playing:queue"]);
    SGLog(@"system player: Spotify's queue %@", sent ? @"asked for" : @"not asked for (no link dispatcher)");
    if (sent) [self noteSheetFor:@"the queue"];
}

- (void)toggleQueue {
    [self setQueueOpen:!_queueOpen];
}

// A track moved in the page's queue: Spotify's queue as fetched, its tracks to come in the new order, handed back to the
// player (setQueue:), then fetched again so the page shows what Spotify kept.
- (void)handQueueBack:(NSArray *)upcoming {
    id<SPTPlayer> player = (id<SPTPlayer>)SGPlayer();
    id queue = _spotifyQueue;
    if (!queue || ![queue respondsToSelector:@selector(setNextTracks:)] || ![player respondsToSelector:@selector(setQueue:)]) {
        SGLog(@"system player: queue move not handed back (queue %@, player %@)", queue ? NSStringFromClass([queue class]) : @"nil",
              player ? NSStringFromClass([player class]) : @"nil");
        return;
    }
    @try {
        [(id<SPTPlayerQueue>)queue setNextTracks:upcoming];
        [player setQueue:queue];
        SGLog(@"system player: queue moved, %lu tracks handed back", (unsigned long)upcoming.count);
    } @catch (NSException *e) {
        SGLog(@"system player: queue move failed: %@", e.reason);
    }
    __weak typeof(self) weakSelf = self;
    dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(0.6 * NSEC_PER_SEC)), dispatch_get_main_queue(), ^{
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
        static BOOL told;
        if (!told) {
            told = YES;
            SGLog(@"system player: Spotify's queue has %lu tracks to come (%@ first), the state %lu", (unsigned long)next.count,
                  next.count ? NSStringFromClass([next.firstObject class]) : @"none", (unsigned long)[SGPlayerState().future count]);
        }
        [me->_queueView showState:SGPlayerState() upcoming:next from:from];
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
}

// The queue comes in the lyrics' place in the same layout spring: the cover shrinks to the thumbnail as the title rises
// beside it and the queue fades in under them, over the same blur; the lyrics, if up, give way first. Out of the page
// once it has faded out.
- (void)setQueueOpen:(BOOL)open {
    if (open == _queueOpen) return;
    if (open && _lyricsOpen) [self setLyricsOpen:NO];
    _queueOpen = open;
    SGLog(@"system player: queue %@", open ? @"open" : @"closed");
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
    if (!_lyricsOpen && !SGRPlayerLyricsAvailable()) return;
    [self setLyricsOpen:!_lyricsOpen];
}

// The cover gives way to the lines and comes back in one layout spring: it shrinks to the thumbnail as the title and
// artist rise beside it and the lines fade in under them. The stage leaves the page once it has faded out, so the
// karaoke view's display link stops with it (it runs only while the view is in a window: SGRKaraokeView.m's
// scheduleLink), and the page's closing takes it down too.
- (void)setLyricsOpen:(BOOL)open {
    if (open == _lyricsOpen) return;
    // One or the other in the lyrics' place: the queue gives way to the lyrics.
    if (open && _queueOpen) [self setQueueOpen:NO];
    if (!open) [self setAlone:NO animated:NO];
    _lyricsOpen = open;
    SGLog(@"system player: lyrics %@", open ? @"open" : @"closed, the cover is back");
    if (self.view.window) SGRPlayerSetPageLyricsOpen(open);
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
    BOOL overClip = _motion && view.window && !SGRReduceMotion();
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
    if (SGRLyricsHideMode() != SGRLyricsHideControls) [views addObjectsFromArray:@[_close, _more, _context, _coverHolder, _titleBlock, _add]];
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
    return recognizer == _wake;
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
- (void)titleSwiped:(UIPanGestureRecognizer *)swipe {
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
            SGLog(@"system player: the title swiped to the %@ track", way < 0 ? @"next" : @"previous");
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
    NSString *identity = nil;
    UIImage *art = SGRNowPlayingArtwork(NULL, &identity);
    BOOL current = art && SGRNowPlayingArtworkCurrent();
    UIImage *image = current ? art : _cover.image ? nil : SGRNowPlayingCover() ?: art;
    NSString *playing = SGURIString(SGPlayerState().track.URI);
    if (playing && ![playing isEqualToString:_coverTrack] && (current || !_cover.image)) {
        _coverTrack = playing;
        SGLog(@"system player: cover of %@ from %@ (%.0fx%.0f)", playing, current ? @"the Kit" : @"the bar, until the Kit's comes", image.size.width, image.size.height);
    }
    // The field reads the Kit's picture by its identity, the same picture once.
    if (current) [_field setArtwork:art identity:identity animated:self.view.window != nil];
    if (!image || image == _cover.image) return;
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
    SGLog(@"system player: %@", episode ? @"an episode, 15 s skips and its speed" : @"a song, its skips, shuffle and repeat");
}

// Whether what Spotify was asked for came up over the page a moment later: a sheet it pushes somewhere under the page
// instead of presenting would not, and the log says so.
- (void)noteSheetFor:(NSString *)what {
    __weak typeof(self) weakSelf = self;
    dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(1.2 * NSEC_PER_SEC)), dispatch_get_main_queue(), ^{
        typeof(self) me = weakSelf;
        if (!me.view.window) return;
        UIViewController *over = me.presentedViewController;
        SGLog(@"system player: after %@, %@ over the page", what, over ? NSStringFromClass(over.class) : @"nothing");
    });
}

- (void)toggleShuffle {
    id<SPTPlayer> player = (id<SPTPlayer>)SGPlayer();
    SPTPlayerState *state = SGPlayerState();
    if (!player || !state) return;
    [player setShufflingContext:!state.options.shufflingContext];
}

// Off, then the playlist or album, then the track, then off again, the way Spotify's button goes (HeadGestures.x).
- (void)cycleRepeat {
    id<SPTPlayer> player = (id<SPTPlayer>)SGPlayer();
    SPTPlayerOptions *options = SGPlayerState().options;
    if (!player || !options) return;
    if (options.repeatingTrack) {
        [player setRepeatingTrack:NO];
        [player setRepeatingContext:NO];
    } else if (options.repeatingContext) {
        [player setRepeatingTrack:YES];
    } else {
        [player setRepeatingContext:YES];
    }
}
@end
