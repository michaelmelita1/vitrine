// Native redesign's player page (SystemPlayer.m): its volume row, a copy of the redesigned player's (Redesigned/Player/
// PlayerVolume.m) with Sim Radio's elastic slider: the pill grows on a spring while held, stretches past either end like a
// rubber band, and the speaker glyphs bounce at the ends. The redesigned player keeps its own row as it was.
// Under it sits a hidden MPVolumeView whose slider the row reads and moves, so it is the system's volume: the hardware
// buttons move it. A Connect device's own volume reaches Spotify, not iOS, so the row does not show it.
#import <AVFoundation/AVFoundation.h>
#import <MediaPlayer/MediaPlayer.h>
#import <QuartzCore/QuartzCore.h>
#import <objc/runtime.h>
#import "Core/SGCore.h"
#import "Shared/Haptics/Haptics.h"
#import "Redesigned/Kit/SGRKit.h"
#import "Redesigned/Player/Player.h"
#import "SystemPlayer.h"

// The row's height (the touch area) and the glyphs' point size and gap to the track.
static const CGFloat kRowHeight = 32, kGlyphSize = 13, kGlyphGap = 10;
// How far a finger has to move sideways on the row before the pans above it are turned off: a touch that only comes down
// on it, or the touch that opened the system tab bar's player page landing on it as the page appears, turns nothing off
// (the phone's log, 2026-11-01: UIKit's zoom swipe close was turned off that way as the page opened).
static const CGFloat kDragStart = 6;
// While the pans are off, how often the row checks that a finger is still tracking it, and turns them back on if not.
static const NSTimeInterval kSuspendCheck = 1;
// After f728743/Sim-Radio-SwiftUI's ElasticSlider.swift and its .volume config (MIT, Copyright (c) 2025 Alexey Vorobyov;
// its owner's pick, 2026-11-01): the track 7 high at rest and 17 held, growing 9 past each end while held with the glyphs
// moving out as far (each clamped to the room the row has on that side), on SwiftUI's .smooth(duration: 0.3,
// extraBounce: 0.3) both ways. Dragged past an end it stretches that way up to kMaxStretch, the other end pulling in by
// kPullStretch of it and the track narrowing by up to kStretchNarrowing, the full stretch a finger's kMaxStretch /
// kPushStretch past the end; it springs back on the let go. The speaker at an end bounces as the volume reaches it.
static const CGFloat kTrackRest = 7, kTrackHeld = 17, kStretch = 9, kGlyphShift = 9, kGlyphHeldScale = 1;
static const CGFloat kMaxStretch = 10, kPushStretch = 0.2, kPullStretch = 0.5, kStretchNarrowing = 4;
static const NSTimeInterval kHeldSpring = 0.3;
static const CGFloat kHeldBounce = 0.3;
// White's opacity: the fill at rest and held, the empty part, the glyphs at rest (held they are full white).
static const CGFloat kFillRest = 0.65, kFillHeld = 1, kEmpty = 0.24, kGlyphRest = 0.68;

static char kSessionContext;

// Vibrations > Controls, as the progress bar has them (SystemPlayer.m): a tick at each of the sixteen steps the volume
// buttons move by, a firmer one at either end. A step counts once the value is a little past it.
static const CGFloat kVolumeSteps = 16, kVolumeHysteresis = 0.004;

static UIImageView *glyph(NSString *symbol) {
    UIImageSymbolConfiguration *configuration =
        [UIImageSymbolConfiguration configurationWithPointSize:kGlyphSize weight:UIImageSymbolWeightSemibold];
    UIImageView *view = [[UIImageView alloc] initWithImage:[UIImage systemImageNamed:symbol withConfiguration:configuration]];
    view.tintColor = UIColor.whiteColor;
    view.alpha = kGlyphRest;
    view.contentMode = UIViewContentModeCenter;
    view.isAccessibilityElement = NO;
    return view;
}

@interface SGRSystemVolumeRow : UIControl
- (UISlider *)systemSlider;
- (void)systemSliderSet;
@end

// MPVolumeView makes its slider when it lays out and may make another later, for example after a route change, so the
// row looks for it again after each of its layouts.
@interface SGRSystemVolumeView : MPVolumeView
@end

@implementation SGRSystemVolumeView

- (void)layoutSubviews {
    [super layoutSubviews];
    [(SGRSystemVolumeRow *)self.superview systemSlider];
}

@end

@implementation SGRSystemVolumeRow {
    MPVolumeView *_system;
    UISlider *_systemSlider;
    UIView *_track, *_fill;
    UIImageView *_quiet, *_loud;
    CGFloat _value, _startValue, _startX, _trackMin, _trackMax;
    CGFloat _stretch;   // -1 to 1: how far a drag past the low (negative) or high end stretches the track
    BOOL _held;
    NSInteger _step;   // the step the row was last felt in
    BOOL _atEnd;
    CFTimeInterval _lastPush;
    NSHashTable<UIGestureRecognizer *> *_suspended;
}

- (instancetype)initWithFrame:(CGRect)frame {
    if (!(self = [super initWithFrame:frame])) return nil;
    // Only plumbing: the slider inside moves the system's volume, nobody sees or touches the view.
    _system = [SGRSystemVolumeView new];
#pragma clang diagnostic push
#pragma clang diagnostic ignored "-Wdeprecated-declarations"
    _system.showsRouteButton = NO;
#pragma clang diagnostic pop
    _system.alpha = 0.01;
    _system.userInteractionEnabled = NO;
    [self addSubview:_system];

    _track = [UIView new];
    _track.clipsToBounds = YES;
    _track.userInteractionEnabled = NO;
    _track.layer.cornerCurve = kCACornerCurveContinuous;
    _track.backgroundColor = [UIColor colorWithWhite:1 alpha:kEmpty];
    _fill = [UIView new];
    _fill.userInteractionEnabled = NO;
    [_track addSubview:_fill];
    [self addSubview:_track];

    _quiet = glyph(@"speaker.fill");
    _loud = glyph(@"speaker.wave.3.fill");
    [self addSubview:_quiet];
    [self addSubview:_loud];

    _value = AVAudioSession.sharedInstance.outputVolume;
    [AVAudioSession.sharedInstance addObserver:self forKeyPath:@"outputVolume" options:NSKeyValueObservingOptionNew
                                       context:&kSessionContext];
    [NSNotificationCenter.defaultCenter addObserver:self selector:@selector(refreshFromSystem)
                                               name:UIApplicationDidBecomeActiveNotification object:nil];

    self.isAccessibilityElement = YES;
    self.accessibilityLabel = @"Volume";
    self.accessibilityTraits = UIAccessibilityTraitAdjustable;
    return self;
}

- (void)dealloc {
    [self restoreAncestorGestures];
    [NSNotificationCenter.defaultCenter removeObserver:self];
    [AVAudioSession.sharedInstance removeObserver:self forKeyPath:@"outputVolume" context:&kSessionContext];
}

// The volume view builds its slider itself and may replace it, so the one it has now is looked for each time.
- (UISlider *)systemSlider {
    UISlider *current = nil;
    for (UIView *view in _system.subviews) {
        if (![view isKindOfClass:UISlider.class]) continue;
        current = (UISlider *)view;
        break;
    }
    if (current == _systemSlider) return current;

    _systemSlider = current;
    // Hide the system slider's visible artwork.
    current.thumbTintColor = UIColor.clearColor;
    current.minimumTrackTintColor = UIColor.clearColor;
    current.maximumTrackTintColor = UIColor.clearColor;
    return current;
}

- (void)observeValueForKeyPath:(NSString *)keyPath ofObject:(id)object change:(NSDictionary *)change context:(void *)context {
    if (context != &kSessionContext) {
        [super observeValueForKeyPath:keyPath ofObject:object change:change context:context];
        return;
    }
    // The hidden slider takes the new volume a moment after the session reports it, and read at once it still says the old
    // one, which refreshFromSystem prefers: read again once it has caught up. The slider's own catching up reaches the row
    // through the UISlider hook (SGRPlayerVolumeSliderSet) only where that hook is installed.
    __weak SGRSystemVolumeRow *weakSelf = self;
    dispatch_async(dispatch_get_main_queue(), ^{ [weakSelf refreshFromSystem]; });
    dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(0.25 * NSEC_PER_SEC)), dispatch_get_main_queue(), ^{ [weakSelf refreshFromSystem]; });
}

// Our own pushVolume sets the slider too, and refreshFromSystem skips that echo.
- (void)systemSliderSet {
    [self refreshFromSystem];
}

- (void)refreshFromSystem {
    // Not while the finger is on it, nor just after it let go: the system settles on its own steps a moment later.
    if (_held || CACurrentMediaTime() - _lastPush < 0.6) return;
    UISlider *slider = [self systemSlider];
    CGFloat system = slider ? slider.value : AVAudioSession.sharedInstance.outputVolume;
    if (fabs(system - _value) > 0.002) [self setValue:system fromUser:NO];
}

// The KVO the system sends as it settles falls inside the guard above, so the row reads it once the guard has passed.
- (void)refreshAfterPush {
    __weak SGRSystemVolumeRow *weakSelf = self;
    dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(0.65 * NSEC_PER_SEC)), dispatch_get_main_queue(), ^{
        [weakSelf refreshFromSystem];
    });
}

- (void)pushVolume {
    UISlider *slider = [self systemSlider];
    if (!slider) return;
    _lastPush = CACurrentMediaTime();
    [slider setValue:_value animated:NO];
    [slider sendActionsForControlEvents:UIControlEventValueChanged];
}

// The room the row has to either side inside its stack: what the held track and glyphs may grow into.
- (CGFloat)roomLeft { return MAX(0, CGRectGetMinX(self.frame)); }

- (CGFloat)roomRight {
    UIView *stack = self.superview;
    return stack ? MAX(0, stack.bounds.size.width - CGRectGetMaxX(self.frame)) : 0;
}

// ElasticSlider's leadingStretch and trailingStretch: the low end out by the stretch when pushed past it, else in by
// kPullStretch of it; the high end the same way round.
- (CGFloat)lowStretch {
    CGFloat stretch = fabs(_stretch) * kMaxStretch;
    return _stretch < 0 ? stretch : -stretch * kPullStretch;
}

- (CGFloat)highStretch {
    CGFloat stretch = fabs(_stretch) * kMaxStretch;
    return _stretch > 0 ? stretch : -stretch * kPullStretch;
}

// The track's frame for the state it is in: it grows past both ends while held, and stretches past one as it is pushed.
- (void)syncTrack {
    CGFloat height = _held ? kTrackHeld - fabs(_stretch) * kStretchNarrowing : kTrackRest;
    CGFloat left = (_held ? MIN(kStretch, [self roomLeft]) : 0) + [self lowStretch];
    CGFloat right = (_held ? MIN(kStretch, [self roomRight]) : 0) + [self highStretch];
    CGFloat scale = self.traitCollection.displayScale ?: 3;
    CGFloat top = round((CGRectGetMidY(self.bounds) - height / 2) * scale) / scale;
    _track.frame = CGRectMake(_trackMin - left, top, MAX(0, _trackMax - _trackMin + left + right), height);
    _track.layer.cornerRadius = height / 2;
    [self syncFill];
}

// The fill is a plain rectangle the pill's clipping rounds, so its right edge stays straight, as in Music: the value's
// share of the track unstretched, carried with a stretch (ElasticSlider's fillWidth).
- (void)syncFill {
    CGSize size = _track.bounds.size;
    CGFloat base = size.width - [self lowStretch] - [self highStretch];
    CGFloat width = MIN(size.width, MAX(0, base * _value + [self highStretch] + ([self lowStretch] > 0 ? 0 : [self lowStretch])));
    if (_value <= 0 && _stretch < 0) width = 0;
    _fill.frame = CGRectMake(0, 0, width, size.height);
}

- (void)syncStyle {
    _fill.backgroundColor = [UIColor colorWithWhite:1 alpha:_held ? kFillHeld : kFillRest];
    CGFloat scale = _held ? kGlyphHeldScale : 1;
    CGFloat left = (_held ? MIN(kGlyphShift, [self roomLeft]) : 0) + [self lowStretch];
    CGFloat right = (_held ? MIN(kGlyphShift, [self roomRight]) : 0) + [self highStretch];
    CGAffineTransform grown = CGAffineTransformMakeScale(scale, scale);
    _quiet.transform = CGAffineTransformConcat(grown, CGAffineTransformMakeTranslation(-left, 0));
    _loud.transform = CGAffineTransformConcat(grown, CGAffineTransformMakeTranslation(right, 0));
    _quiet.alpha = _loud.alpha = _held ? 1 : kGlyphRest;
}

- (void)layoutSubviews {
    [super layoutSubviews];
    CGRect bounds = self.bounds;
    CGFloat side = kRowHeight, middle = CGRectGetMidY(bounds), glyphWidth = side / 2 + kGlyphSize / 2;
    _system.frame = CGRectMake(0, 0, MAX(140, bounds.size.width), side);
    [_system layoutIfNeeded];
    [self systemSlider];
    CGFloat loudMin = CGRectGetMaxX(bounds) - side / 2 - kGlyphSize;
    _quiet.bounds = CGRectMake(0, 0, glyphWidth, side);
    _loud.bounds = CGRectMake(0, 0, glyphWidth, side);
    _quiet.center = CGPointMake(glyphWidth / 2, middle);
    _loud.center = CGPointMake(loudMin + glyphWidth / 2, middle);
    _trackMin = glyphWidth + kGlyphGap;
    _trackMax = loudMin - kGlyphGap;
    [self syncTrack];
    [self syncStyle];
}

- (void)didMoveToWindow {
    [super didMoveToWindow];
    if (!self.window) {
        // A lock or a call can take the row off screen mid-drag, and then end or cancel tracking may not come.
        [self setHeld:NO];
        return;
    }
    [self systemSlider];
    [self refreshFromSystem];
    // A row made afresh (the system tab bar's player page makes one each time it opens, SystemPlayer.m) meets a hidden
    // slider made out of a window, which holds a value of its own until the volume view, now in one, brings it up to
    // date: the row is told after it moves to the window, before its slider is (its owner, 2026-11-01). Read again then.
    __weak SGRSystemVolumeRow *weakSelf = self;
    dispatch_async(dispatch_get_main_queue(), ^{ [weakSelf refreshFromSystem]; });
    dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(0.3 * NSEC_PER_SEC)), dispatch_get_main_queue(), ^{ [weakSelf refreshFromSystem]; });
}

// Prevent the player from stealing volume swipe gesture.
- (void)suspendAncestorGestures {
    if (_suspended) return;
    _suspended = [NSHashTable weakObjectsHashTable];
    for (UIView *view = self.superview; view; view = view.superview) {
        for (UIGestureRecognizer *recognizer in view.gestureRecognizers) {
            BOOL pan = [recognizer isKindOfClass:UIPanGestureRecognizer.class];
            if (!pan || [recognizer isKindOfClass:UIScreenEdgePanGestureRecognizer.class] || !recognizer.enabled) continue;
            recognizer.enabled = NO;
            [_suspended addObject:recognizer];
        }
    }
    [self performSelector:@selector(checkSuspended) withObject:nil afterDelay:kSuspendCheck];
}

// A safety: should neither end nor cancel come, the pans above are never left off once no finger tracks the row.
- (void)checkSuspended {
    if (!_suspended) return;
    if (self.isTracking && self.window) {
        [self performSelector:@selector(checkSuspended) withObject:nil afterDelay:kSuspendCheck];
        return;
    }
    [self restoreAncestorGestures];
}

- (void)restoreAncestorGestures {
    [NSObject cancelPreviousPerformRequestsWithTarget:self selector:@selector(checkSuspended) object:nil];
    for (UIGestureRecognizer *recognizer in _suspended) recognizer.enabled = YES;
    _suspended = nil;
}

- (void)setValue:(CGFloat)value fromUser:(BOOL)fromUser {
    value = MIN(1, MAX(0, value));
    _value = value;
    if (!fromUser && !_held && self.window) {
        UIViewAnimationOptions options = UIViewAnimationOptionBeginFromCurrentState | UIViewAnimationOptionAllowUserInteraction |
                                         UIViewAnimationOptionCurveEaseOut;
        [UIView animateWithDuration:0.15 delay:0 options:options animations:^{ [self syncFill]; } completion:nil];
    } else {
        [self syncFill];
    }
    if (fromUser) [self pushVolume];
}

- (void)setHeld:(BOOL)held {
    if (_held == held) return;
    _held = held;
    // The pans above go off only once the finger drags (continueTrackingWithTouch:), and come back on with the let go.
    if (!held) {
        [self restoreAncestorGestures];
        [self refreshAfterPush];
    }
    // The stretch springs back with the let go.
    if (!held) _stretch = 0;
    void (^apply)(void) = ^{ [self syncTrack]; [self syncStyle]; };
    UIViewAnimationOptions options = UIViewAnimationOptionBeginFromCurrentState | UIViewAnimationOptionAllowUserInteraction;
    if (@available(iOS 17.0, *)) {
        [UIView animateWithSpringDuration:kHeldSpring bounce:kHeldBounce initialSpringVelocity:0 delay:0 options:options animations:apply completion:nil];
    } else {
        [UIView animateWithDuration:kHeldSpring delay:0 usingSpringWithDamping:1 - kHeldBounce initialSpringVelocity:0 options:options
                         animations:apply completion:nil];
    }
}

- (BOOL)beginTrackingWithTouch:(UITouch *)touch withEvent:(UIEvent *)event {
    _startX = [touch locationInView:self].x;
    _startValue = _value;
    _step = (NSInteger)floor(_value * kVolumeSteps);
    _atEnd = _value <= 0 || _value >= 1;
    SGPlayFeedback(SGFeedbackGrab);
    SGPrepareFeedback(SGFeedbackDetent);
    [self setHeld:YES];
    return YES;
}

- (void)feelValue {
    BOOL end = _value <= 0 || _value >= 1;
    if (end != _atEnd) {
        _atEnd = end;
        if (end) SGPlayFeedback(SGFeedbackEdge);
    }
    NSInteger step = (NSInteger)floor(_value * kVolumeSteps);
    if (step != _step && fabs(_value * kVolumeSteps - MAX(step, _step)) > kVolumeHysteresis * kVolumeSteps) {
        _step = step;
        if (!end) SGPlayFeedback(SGFeedbackDetent);
    }
}

// Relative to where the finger came down: the value moves by the finger's travel over the track's length.
- (BOOL)continueTrackingWithTouch:(UITouch *)touch withEvent:(UIEvent *)event {
    if (!_suspended && fabs([touch locationInView:self].x - _startX) > kDragStart) [self suspendAncestorGestures];
    CGFloat span = MAX(1, _trackMax - _trackMin + 2 * kStretch);
    CGFloat wanted = _startValue + ([touch locationInView:self].x - _startX) / span, before = _value;
    [self setValue:wanted fromUser:YES];
    [self feelValue];
    // Past an end, the stretch (ElasticSlider's normalizedStretchingValue): the overshoot over kMaxStretch / kPushStretch.
    CGFloat over = wanted < 0 ? wanted : wanted > 1 ? wanted - 1 : 0, most = kMaxStretch / span / kPushStretch;
    CGFloat stretch = MIN(most, MAX(-most, over)) / most;
    if (stretch != _stretch) {
        _stretch = stretch;
        [self syncTrack];
        [self syncStyle];
    }
    // The speaker at the end the volume has just reached bounces (VolumeSlider's symbolEffect(.bounce)).
    if (@available(iOS 17.0, *)) {
        if (_value <= 0 && before > 0) [_quiet addSymbolEffect:[NSSymbolBounceEffect effect]];
        if (_value >= 1 && before < 1) [_loud addSymbolEffect:[NSSymbolBounceEffect effect]];
    }
    return YES;
}

- (void)endTrackingWithTouch:(UITouch *)touch withEvent:(UIEvent *)event {
    SGPlayFeedback(SGFeedbackRelease);
    [self setHeld:NO];
}
- (void)cancelTrackingWithEvent:(UIEvent *)event { [self setHeld:NO]; }

- (NSString *)accessibilityValue { return [NSString stringWithFormat:@"%d%%", (int)round(_value * 100)]; }
- (void)accessibilityIncrement {
    [self setValue:_value + 0.0625 fromUser:YES];
    [self refreshAfterPush];
}

- (void)accessibilityDecrement {
    [self setValue:_value - 0.0625 fromUser:YES];
    [self refreshAfterPush];
}

@end

UIControl *SGRPlayerMakeVolumeRow(void) {
    return [SGRSystemVolumeRow new];
}

void SGRPlayerVolumeRowLetGo(UIControl *row) {
    if (![row isKindOfClass:SGRSystemVolumeRow.class]) return;
    [(SGRSystemVolumeRow *)row restoreAncestorGestures];
}

// An outside change of the system slider's (AirPlay, Connect), from the redesigned player's UISlider hook
// (PlayerVolume.m's SGRPlayerVolumeSliderSet), which sends neither KVO nor ValueChanged.
void SGRSystemVolumeSliderSet(UISlider *slider) {
    UIView *row = slider.superview.superview;
    if (![slider.superview isKindOfClass:SGRSystemVolumeView.class] || ![row isKindOfClass:SGRSystemVolumeRow.class]) return;
    if (slider != ((SGRSystemVolumeRow *)row).systemSlider) return;
    dispatch_async(dispatch_get_main_queue(), ^{ [(SGRSystemVolumeRow *)row systemSliderSet]; });
}
