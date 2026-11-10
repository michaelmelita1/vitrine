// Prototype: the system tab bar. A UITabBarController of the mod's over Spotify's tab area, so UIKit itself minimizes
// the bar on scroll and moves the mini player between its place over the bar and the bar's row, the Music app's way
// (UITabBarController's tabBarMinimizeBehavior and bottomAccessory, iOS 26). Spotify's tab bar container is no
// UITabBarController (TabBar.x), so this one stands over it:
//
// - its tabs are Spotify's own, read from Spotify's bar at each of its passes (TabBar.x hands them over), and a tap on
//   one is passed on to Spotify's item; Spotify's bar stays, unseen, as their source;
// - its pages are empty and let every touch through to Spotify's page under them; the host view takes only the bar's
//   and the accessory's touches;
// - its minimize follows the page Spotify shows: each page's content scroll view is set to the scroll view the page is
//   scrolling (TabBarMinimize.x hands it over);
// - its accessory is a mini player of the mod's (SGRSystemMiniPlayer), from the player's state and the cover on
//   Spotify's own bar, which stays unseen; a tap on it brings up the mod's own player (SystemPlayer.m) with UIKit's zoom.
#import <objc/runtime.h>
#import <objc/message.h>
#import "Core/SGCore.h"
#import "Redesigned/Kit/SGRKit.h"
#import "Redesigned/NowPlayingBar/NowPlayingBar.h"
#import "Shared/Player/PlayerState.h"
#import "Shared/Haptics/Haptics.h"
#import "Navbar.h"
#import "SystemPlayer.h"
#import "SystemPlayerTransition.h"
#import "Redesigned/Kit/SGRRepaint.h"
#import "Settings/SGPage.h"
#import "Redesigned/Artist/Artist.h"


BOOL SGRSystemTabsOn(void) {
    static BOOL on;
    static dispatch_once_t once;
    dispatch_once(&once, ^{
        on = SGNativeRedesign();
    });
    return on;
}

#pragma mark - the mini player

static UIViewController *systemTabsController(void);
static void buildReadyPage(void);

API_AVAILABLE(ios(26.0))
// TODO (its owner, 2026-11-01, "aim to add at some point"): no like on it yet, so the Mini player page's Hide the like
// button reaches only the glass bar.
@interface SGRSystemMiniPlayer : UIView <SGPlayerStateObserver, UIGestureRecognizerDelegate>
@property (nonatomic, readonly) UIImageView *cover;
@end

// Swiped sideways, the card pages through the tracks as the Music app's mini player does (its owner's recording,
// 2026-10-31): the cover stays, and the two lines are one of three side by side, the track before, this one and the next,
// moved with the finger and cut at the card's text area. Far or fast enough it settles on the neighbour and the player
// skips to it; short of that it springs back. A track changed some other way (next, the player) pages across the same way.
static const CGFloat kSwipeDistance = 0.28, kSwipeSpeed = 600, kPageGap = 24;
// The text area fades out over this much at each side, so a page going off or coming in softens there rather than being
// cut (its owner, 2026-10-31).
static const CGFloat kTextFade = 14;
// The cover's gap to the capsule's edge, all round.
static const CGFloat kCoverInset = 6;
// The least room the title keeps beside the buttons: short of it the device button goes.
static const CGFloat kDeviceRoom = 80;

// One track's two lines.
@interface SGRMiniTrackText : UIView
@property (nonatomic, readonly) UILabel *title, *artist;
@property (nonatomic) BOOL titleOnly;
@end

@implementation SGRMiniTrackText
- (instancetype)initWithFrame:(CGRect)frame {
    if (!(self = [super initWithFrame:frame])) return nil;
    _title = [UILabel new];
    _title.font = SGRFont(UIFontTextStyleSubheadline, UIFontWeightSemibold, UIContentSizeCategoryLarge);
    _title.textColor = UIColor.labelColor;
    _artist = [UILabel new];
    _artist.font = SGRFont(UIFontTextStyleFootnote, UIFontWeightRegular, UIContentSizeCategoryLarge);
    // A plain grey of the secondary label's look, not the system's secondary color: that one is drawn through the capsule's
    // glass, so it was missing from the picture the player page's card carries down and came back a beat after the title
    // when the card landed (its owner, 2026-11-01).
    _artist.textColor = [UIColor colorWithDynamicProvider:^UIColor *(UITraitCollection *traits) {
        return traits.userInterfaceStyle == UIUserInterfaceStyleDark ? [UIColor colorWithWhite:1 alpha:0.6] : [UIColor colorWithWhite:0 alpha:0.5];
    }];
    [self addSubview:_title];
    [self addSubview:_artist];
    return self;
}

- (void)setTrack:(SPTPlayerTrack *)track {
    _title.text = [track isKindOfClass:NSClassFromString(@"SPTPlayerTrack")] ? track.trackTitle : nil;
    _artist.text = [track isKindOfClass:NSClassFromString(@"SPTPlayerTrack")] ? track.artistName : nil;
    [self setNeedsLayout];
}

- (void)layoutSubviews {
    [super layoutSubviews];
    CGSize size = self.bounds.size;
    CGFloat titleHeight = ceil(_title.font.lineHeight), artistHeight = ceil(_artist.font.lineHeight);
    _artist.hidden = self.titleOnly || !_artist.text.length;
    if (_artist.hidden) {
        _title.frame = CGRectMake(0, round((size.height - titleHeight) / 2), size.width, titleHeight);
    } else {
        CGFloat top = round((size.height - titleHeight - artistHeight + 2) / 2);
        _title.frame = CGRectMake(0, top, size.width, titleHeight);
        _artist.frame = CGRectMake(0, top + titleHeight - 2, size.width, artistHeight);
    }
}
@end

@implementation SGRSystemMiniPlayer {
    UIView *_text;      // the text area, which cuts the pages
    UIView *_strip;     // the three pages, moved together
    SGRMiniTrackText *_previous, *_current, *_following;
    CAGradientLayer *_fade;
    SGRGlyphButton *_play, *_next;
    UIView *_device;    // the output's device: a tap the AirPlay picker, a hold Spotify's Connect sheet
    SGRGlyphButton *_like;   // the star (SGRKeyMiniPlayerLike): the song in Liked Songs or not
    id _savedWatch;          // Spotify's collection state for the song shown (Artist.h's SGRCollectionWatchURI)
    NSString *_savedURI;
    BOOL _saved;
    NSString *_shownURI;
    BOOL _skipping;     // a swipe settled on a neighbour; the track it asked for has not come yet
    BOOL _swipePast;    // the swipe is past where letting go skips
    BOOL _hadTrack, _emptyPending;  // a track shown, and a look again pending before Not Playing
}

- (instancetype)initWithFrame:(CGRect)frame {
    if (!(self = [super initWithFrame:frame])) return nil;
    _cover = [UIImageView new];
    _cover.contentMode = UIViewContentModeScaleAspectFill;
    _cover.clipsToBounds = YES;
    _cover.layer.cornerCurve = kCACornerCurveContinuous;
    _cover.backgroundColor = [UIColor colorWithWhite:1 alpha:0.1];
    _text = [UIView new];
    _text.clipsToBounds = YES;
    _fade = [CAGradientLayer layer];
    UIColor *whole = UIColor.blackColor, *none = UIColor.clearColor;
    _fade.colors = @[(id)none.CGColor, (id)whole.CGColor, (id)whole.CGColor, (id)none.CGColor];
    _fade.startPoint = CGPointMake(0, 0.5);
    _fade.endPoint = CGPointMake(1, 0.5);
    _text.layer.mask = _fade;
    _strip = [UIView new];
    _previous = [SGRMiniTrackText new];
    _current = [SGRMiniTrackText new];
    _following = [SGRMiniTrackText new];
    for (UIView *page in @[_previous, _current, _following]) [_strip addSubview:page];
    [_text addSubview:_strip];
    __weak typeof(self) weakSelf = self;
    _play = [SGRGlyphButton buttonWithSymbol:@"play.fill" pointSize:20 title:@"Play"];
    _play.onTap = ^{ [weakSelf togglePlay]; };
    _next = [SGRGlyphButton buttonWithSymbol:@"forward.fill" pointSize:20 title:@"Next"];
    _next.onTap = ^{
        SGPlayFeedback(SGFeedbackSkip);
        [(id)SGPlayer() skipToNextTrackWithOptions:nil];
    };
    // The Mini player page's Device button (its owner, 2026-11-01): the player page's AirPlay button, its glyph the
    // output's device, beside play.
    _device = SGRSystemMakeRouteButton(18, @"the mini player");
    _like = [SGRGlyphButton buttonWithSymbol:@"star" pointSize:18 title:@"Add to Liked Songs"];
    _like.onTap = ^{ [weakSelf toggleSaved]; };
    for (UIView *view in @[_cover, _text, _device, _like, _play, _next]) [self addSubview:view];
    UITapGestureRecognizer *open = [[UITapGestureRecognizer alloc] initWithTarget:self action:@selector(opened)];
    open.delegate = self;
    [self addGestureRecognizer:open];
    // Each close's end: the next page built a moment later, once the open a tap waited on has had its turn. The first page
    // is built a little after launch the same way, and the next one once each open is over (opened).
    static dispatch_once_t once;
    dispatch_once(&once, ^{
        [NSNotificationCenter.defaultCenter addObserverForName:SGRSystemPlayerPageDidCloseNotification object:nil queue:NSOperationQueue.mainQueue
                                                    usingBlock:^(NSNotification *note) {
            dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(0.1 * NSEC_PER_SEC)), dispatch_get_main_queue(), ^{ buildReadyPage(); });
        }];
        dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(2 * NSEC_PER_SEC)), dispatch_get_main_queue(), ^{ buildReadyPage(); });
    });
    UIPanGestureRecognizer *swipe = [[UIPanGestureRecognizer alloc] initWithTarget:self action:@selector(swiped:)];
    swipe.delegate = self;
    [self addGestureRecognizer:swipe];
    self.isAccessibilityElement = NO;
    SGAddPlayerStateObserver(self);
    [self registerForTraitChanges:@[UITraitTabAccessoryEnvironment.class] withAction:@selector(environmentChanged)];
    [self show:SGPlayerState()];
    return self;
}

// The song's place in Liked Songs, from Spotify's collection state, watched from a track change on (the player page's way).
- (void)syncSaved {
    NSString *uri = _shownURI;
    BOOL saveable = [uri hasPrefix:@"spotify:track:"];
    if (!saveable) {
        if (_savedURI) [self setNeedsLayout];
        _savedWatch = nil;
        _savedURI = nil;
        return;
    }
    if (![uri isEqualToString:_savedURI]) {
        if (!_savedURI) [self setNeedsLayout];
        _savedURI = uri;
        __weak typeof(self) weakSelf = self;
        _savedWatch = SGRCollectionWatchURI([NSURL URLWithString:uri], ^{ [weakSelf syncSaved]; });
        [self showSaved:NO];
    }
    BOOL saved = NO;
    if (SGRCollectionWatchSaved(_savedWatch, &saved)) [self showSaved:saved];
}

- (void)showSaved:(BOOL)saved {
    _saved = saved;
    [_like.glyph setSymbol:saved ? @"star.fill" : @"star" animated:self.window != nil];
    _like.accessibilityLabel = saved ? @"Remove from Liked Songs" : @"Add to Liked Songs";
}

- (void)toggleSaved {
    if (!_savedURI || !SGRCollectionSetSaved([NSURL URLWithString:_savedURI], !_saved)) return;
    SGPlayFeedback(SGFeedbackAdd);
    [self showSaved:!_saved];
}

- (void)environmentChanged {
    [self setNeedsLayout];
}

- (BOOL)inline_ {
    return self.traitCollection.tabAccessoryEnvironment == UITabAccessoryEnvironmentInline;
}

- (CGFloat)pageStep {
    return _text.bounds.size.width + kPageGap;
}

- (void)layoutSubviews {
    [super layoutSubviews];
    CGSize size = self.bounds.size;
    BOOL inlined = [self inline_];
    // The Music app's: cover, two lines, play and next over the bar; cover, title and play alone in the row. The cover is
    // concentric with the capsule's rounded end, kCoverInset in from it all round: placed by this view's own bounds, which
    // are not the capsule's, it filled the capsule's height against its edge (its owner's screenshot, 2026-10-31).
    UIView *capsule = self.superview;
    CGRect shape = capsule ? [self convertRect:capsule.bounds fromView:capsule] : self.bounds;
    if (shape.size.height < 20 || shape.size.height > size.height + 40) shape = self.bounds;
    CGFloat side = MAX(20, shape.size.height - 2 * kCoverInset);
    CGPoint middle = CGPointMake(CGRectGetMinX(shape) + shape.size.height / 2, CGRectGetMidY(shape));
    _cover.frame = CGRectMake(round(middle.x - side / 2), round(middle.y - side / 2), side, side);
    // Round over the bar too, as in the row (its owner, 2026-10-31).
    _cover.layer.cornerRadius = side / 2;
    CGFloat button = 36, right = size.width - 6;
    CGFloat textX = CGRectGetMaxX(_cover.frame) + 10;
    // The buttons in the Mini player page's order, laid from the right edge in (its owner, 2026-11-06). In the bar's row,
    // play alone as the Music app has it; the AirPlay button and the star go first while the title would be left short.
    NSArray<NSString *> *order = inlined ? @[SGRMiniButtonPlay] : SGRMiniPlayerButtons();
    NSDictionary<NSString *, UIView *> *views = @{SGRMiniButtonAirPlay: _device, SGRMiniButtonStar: _like,
                                                  SGRMiniButtonPlay: _play, SGRMiniButtonNext: _next};
    NSMutableSet<NSString *> *shown = [NSMutableSet set];
    // Room for the must-haves first (play, next), then the rest while the title keeps kDeviceRoom.
    NSInteger fixed = 0;
    for (NSString *key in order) if ([key isEqualToString:SGRMiniButtonPlay] || [key isEqualToString:SGRMiniButtonNext]) fixed++;
    CGFloat room = right - fixed * button - 4 - textX;
    for (NSString *key in order) {
        if ([key isEqualToString:SGRMiniButtonPlay] || [key isEqualToString:SGRMiniButtonNext]) {
            [shown addObject:key];
            continue;
        }
        if ([key isEqualToString:SGRMiniButtonStar] && ![_savedURI hasPrefix:@"spotify:track:"]) continue;
        if (room - button < kDeviceRoom) continue;
        room -= button;
        [shown addObject:key];
    }
    for (NSString *key in order.reverseObjectEnumerator) {
        if (![shown containsObject:key]) continue;
        views[key].frame = CGRectMake(right - button, round((size.height - button) / 2), button, button);
        right -= button;
    }
    for (NSString *key in views) views[key].hidden = ![shown containsObject:key];
    right -= 4;
    CGFloat width = MAX(0, right - textX);
    // The text area starts the fade's width before the text, so the fade lies over nothing at rest: laid over the text,
    // it faded the title's first letter (its owner's screenshot, 2026-10-31).
    _text.frame = CGRectMake(textX - kTextFade, 0, width + kTextFade, size.height);
    [CATransaction begin];
    [CATransaction setDisableActions:YES];
    _fade.frame = _text.bounds;
    CGFloat edge = width > 0 ? MIN(0.25, kTextFade / (width + kTextFade)) : 0;
    _fade.locations = @[@0, @(edge), @(1 - edge), @1];
    [CATransaction commit];
    CGFloat step = width + kPageGap;
    _strip.bounds = CGRectMake(0, 0, width, size.height);
    _strip.center = CGPointMake(kTextFade + width / 2, size.height / 2);
    NSArray<SGRMiniTrackText *> *pages = @[_previous, _current, _following];
    for (NSUInteger i = 0; i < pages.count; i++) {
        // Both lines in the row too, as over the bar (its owner, 2026-10-31).
        pages[i].titleOnly = NO;
        pages[i].frame = CGRectMake(((CGFloat)i - 1) * step, 0, width, size.height);
    }
}

- (void)show:(SPTPlayerState *)state {
    // A moment with no track between two (a new playlist loading) is not Not Playing: looked at again after a moment
    // before the card says so, as the page does (SystemPlayer.m).
    BOOL hasTrack = [state.track isKindOfClass:NSClassFromString(@"SPTPlayerTrack")];
    if (hasTrack) {
        _hadTrack = YES;
    } else if (_hadTrack) {
        if (!_emptyPending) {
            _emptyPending = YES;
            __weak typeof(self) weakSelf = self;
            dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(0.6 * NSEC_PER_SEC)), dispatch_get_main_queue(), ^{
                typeof(self) me = weakSelf;
                if (!me) return;
                me->_emptyPending = NO;
                if ([SGPlayerState().track isKindOfClass:NSClassFromString(@"SPTPlayerTrack")]) return;
                me->_hadTrack = NO;
                [me show:SGPlayerState()];
            });
        }
        return;
    }
    NSString *uri = SGURIString(state.track.URI);
    BOOL changed = uri && _shownURI && ![uri isEqualToString:_shownURI];
    // Which way the track moved, when it moved: to the one that was next, or back to the one before.
    NSInteger moved = 0;
    if (changed) {
        // On unless the track left is now among those to come: a jump to a track in neither (a new context) reads as on.
        moved = SGRTrackMoved(state, _shownURI) < 0 ? -1 : 1;
    }
    _shownURI = uri;
    _current.track = state.track;
    [self syncSaved];
    // Nothing playing, the Music app's way (its owner's screenshot, 2026-11-02): "Not Playing" by the note, next dimmed.
    BOOL empty = !hasTrack;
    if (empty) _current.title.text = @"Not Playing";
    _next.glyph.alpha = empty ? 0.35 : 1;
    _next.userInteractionEnabled = !empty;
    _previous.track = SGRPreviousTrack(state);
    _following.track = state.future.firstObject;
    if (changed) {
        CGFloat step = [self pageStep];
        if (_skipping) {
            // The strip settled on this track already: it is now the middle page.
            _skipping = NO;
            [UIView performWithoutAnimation:^{ self->_strip.transform = CGAffineTransformIdentity; }];
        } else if (step > 0) {
            // Changed elsewhere: the strip starts on the track it left and pages across to this one.
            [UIView performWithoutAnimation:^{ self->_strip.transform = CGAffineTransformMakeTranslation(moved * step, 0); }];
            [UIView animateWithDuration:0.38 delay:0 usingSpringWithDamping:0.9 initialSpringVelocity:0 options:UIViewAnimationOptionAllowUserInteraction animations:^{
                self->_strip.transform = CGAffineTransformIdentity;
            } completion:nil];
        }
    }
    BOOL paused = !state || state.isPaused || empty;
    [_play.glyph setSymbol:paused ? @"play.fill" : @"pause.fill" animated:YES];
    _play.accessibilityLabel = paused ? @"Play" : @"Pause";
    [self refreshCover];
    // Spotify's bar takes the new track's cover a moment after the state says so.
    for (NSNumber *delay in @[@0.4, @1.2]) {
        __weak typeof(self) weakSelf = self;
        dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(delay.doubleValue * NSEC_PER_SEC)), dispatch_get_main_queue(), ^{
            [weakSelf refreshCover];
        });
    }
    [self setNeedsLayout];
}

- (void)refreshCover {
    BOOL playing = [SGPlayerState().track isKindOfClass:NSClassFromString(@"SPTPlayerTrack")];
    if (!playing && _hadTrack) return;
    UIImage *cover = playing ? SGRNowPlayingCover() : SGRSystemNotPlayingArt();
    if (cover && cover != _cover.image) _cover.image = cover;
}

- (BOOL)gestureRecognizerShouldBegin:(UIGestureRecognizer *)recognizer {
    if (![recognizer isKindOfClass:UIPanGestureRecognizer.class]) return YES;
    // Swipe to skip on the Mini player page (Navbar.h), read at each swipe.
    if (!SGEnabled(SGRKeyMiniPlayerSwipe)) return NO;
    CGPoint velocity = [(UIPanGestureRecognizer *)recognizer velocityInView:self];
    return fabs(velocity.x) > fabs(velocity.y);
}

- (void)swiped:(UIPanGestureRecognizer *)swipe {
    CGFloat step = [self pageStep], x = [swipe translationInView:self].x;
    // No neighbour on a side, the strip only gives a little that way.
    BOOL hasNext = _following.title.text.length > 0, hasPrevious = _previous.title.text.length > 0;
    switch (swipe.state) {
        case UIGestureRecognizerStateChanged: {
            CGFloat moved = ((x < 0 && !hasNext) || (x > 0 && !hasPrevious)) ? x / 4 : x;
            _strip.transform = CGAffineTransformMakeTranslation(moved, 0);
            // A tick as the drag passes where letting go skips (Vibrations > Controls).
            BOOL past = ((x < 0 && hasNext) || (x > 0 && hasPrevious)) && fabs(x) > step * kSwipeDistance;
            if (past != _swipePast) {
                _swipePast = past;
                if (past) SGPlayFeedback(SGFeedbackDetent);
            }
            break;
        }
        case UIGestureRecognizerStateEnded:
        case UIGestureRecognizerStateCancelled: {
            _swipePast = NO;
            CGFloat speed = [swipe velocityInView:self].x;
            // The way the finger went, or for a short flick the way it was moving; flicked back against the drag, none.
            NSInteger way = fabs(x) > 12 ? (x < 0 ? -1 : 1) : (speed < 0 ? -1 : 1);
            BOOL against = (way < 0 && speed > kSwipeSpeed / 2) || (way > 0 && speed < -kSwipeSpeed / 2);
            BOOL possible = way < 0 ? hasNext : hasPrevious;
            BOOL skip = swipe.state == UIGestureRecognizerStateEnded && step > kPageGap && !against && possible
                && (fabs(x) > step * kSwipeDistance || fabs(speed) > kSwipeSpeed);
            if (!skip) {
                [UIView animateWithDuration:0.35 delay:0 usingSpringWithDamping:0.85 initialSpringVelocity:0 options:UIViewAnimationOptionAllowUserInteraction animations:^{
                    self->_strip.transform = CGAffineTransformIdentity;
                } completion:nil];
                break;
            }
            _skipping = YES;
            [UIView animateWithDuration:0.3 delay:0 usingSpringWithDamping:0.95 initialSpringVelocity:0 options:UIViewAnimationOptionAllowUserInteraction animations:^{
                self->_strip.transform = CGAffineTransformMakeTranslation(way * step, 0);
            } completion:nil];
            id player = SGPlayer();
            if (way < 0) [player skipToNextTrackWithOptions:nil];
            else [player skipToPreviousTrackWithOptions:nil];
            // A skip that changes nothing (back from a track already under way only restarts it) brings the strip back.
            __weak typeof(self) weakSelf = self;
            dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(1.2 * NSEC_PER_SEC)), dispatch_get_main_queue(), ^{
                typeof(self) me = weakSelf;
                if (!me || !me->_skipping) return;
                me->_skipping = NO;
                [UIView animateWithDuration:0.35 delay:0 usingSpringWithDamping:0.85 initialSpringVelocity:0 options:0 animations:^{
                    me->_strip.transform = CGAffineTransformIdentity;
                } completion:nil];
            });
            break;
        }
        default:
            break;
    }
}

// The card's tap opens the player, but not over its buttons: it took their touches, so play and next did nothing (its
// owner, 2026-10-31).
- (BOOL)gestureRecognizer:(UIGestureRecognizer *)recognizer shouldReceiveTouch:(UITouch *)touch {
    for (UIView *v = touch.view; v && v != self; v = v.superview) if ([v isKindOfClass:UIControl.class]) return NO;
    return YES;
}

- (void)playerStateDidChange:(SPTPlayerState *)state {
    [self show:state];
}

- (void)togglePlay {
    id player = SGPlayer();
    SPTPlayerState *state = SGPlayerState();
    if (!player) return;
    SGPlayFeedback(state.isPaused ? SGFeedbackPlay : SGFeedbackPause);
    if (state.isPaused) [player resume:nil];
    else [player pause:nil];
}

// The player, a page of the mod's (SystemPlayer.m), presented by UIKit's zoom, the Music app's way: its open, its swipe
// down and its close are the mod's own (SystemPlayerTransition.m), out of the capsule and back into it. Spotify's own
// player is not asked for: held in
// the page, it brought its own pulls and closes, and UIKit's swipe close lost to them, where a page of the mod's alone
// closed every time (its owner, 2026-11-01).
// The next page, built while the shown one is up and after each close, so the next tap has only to present it (a page
// took 15 to 60 ms to build, 115 the first time; the phone's log, 2026-11-01). A tap during a close waits for the close's
// end whatever is done: UIKit refuses to present until then, and the phone's log (2026-11-01) showed nothing of the mod's
// could end it sooner. Its container's layer time sped up changed nothing; its animator already reports itself done
// (1.00) when such a tap comes; and taking the container's animations off ended nothing sooner and took the glass with
// it. So the page is at least ready before it. Kept kReadyFor at most: the page reads some settings
// as it is built.
static const CFTimeInterval kReadyFor = 20;
static SGRSystemPlayerPage *sg_readyPage;
static CFTimeInterval sg_readyAt;

static void buildReadyPage(void) {
    UIViewController *presenter = systemTabsController();
    if (sg_readyPage || !presenter.view.window) return;
    SGRSystemPlayerPage *page = [SGRSystemPlayerPage new];
    [page loadViewIfNeeded];
    sg_readyPage = page;
    sg_readyAt = CACurrentMediaTime();
    dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(kReadyFor * NSEC_PER_SEC)), dispatch_get_main_queue(), ^{
        if (sg_readyPage == page) sg_readyPage = nil;
    });
}

static SGRSystemPlayerPage *takePage(void) {
    SGRSystemPlayerPage *page = sg_readyPage && !sg_readyPage.outOfDate && CACurrentMediaTime() - sg_readyAt < kReadyFor ? sg_readyPage : nil;
    sg_readyPage = nil;
    return page ?: [SGRSystemPlayerPage new];
}

- (void)opened {
    // A safety: an open within a moment of the last is let go (two taps during a close both opened, 16 ms
    // apart, before only one was let wait; the phone's log, 2026-11-01).
    static CFTimeInterval lastOpen;
    CFTimeInterval now = CACurrentMediaTime();
    if (now - lastOpen < 0.3) return;
    UIViewController *presenter = systemTabsController();
    // A tap while the page is still closing: UIKit refuses a presentation until the close is over, so it opens then
    // instead of being dropped (its owner, 2026-11-01: a second before it could be opened again).
    UIViewController *presented = presenter.presentedViewController;
    // One open at most waits: a second tap during the same close keeps the one waiting (the phone's log, 2026-11-01: two
    // taps during a close each waited and both opened, 16 ms apart).
    static BOOL queued;
    if ([presented isKindOfClass:SGRSystemPlayerPage.class] && presented.isBeingDismissed) {
        // The mod's own close turns back, the page opening again from where it is.
        SGRSystemPlayerTransition *running = (SGRSystemPlayerTransition *)presented.transitioningDelegate;
        if ([running isKindOfClass:SGRSystemPlayerTransition.class] && [running turnBackClose]) return;
        if (queued) return;
        queued = YES;
        __weak typeof(self) weakSelf = self;
        __block id observer = [NSNotificationCenter.defaultCenter addObserverForName:SGRSystemPlayerPageDidCloseNotification object:nil queue:nil
                                                                         usingBlock:^(NSNotification *note) {
            [NSNotificationCenter.defaultCenter removeObserver:observer];
            observer = nil;
            dispatch_async(dispatch_get_main_queue(), ^{
                queued = NO;
                [weakSelf opened];
            });
        }];
        return;
    }
    if (!presenter.view.window || presented) return;
    lastOpen = now;
    SGRSystemPlayerPage *page = takePage();
    __weak UIView *capsule = self.superview ?: self;
    // Opened and closed by the mod's own move (SystemPlayerTransition.m), out of the capsule and back into it.
    SGRSystemPlayerTransition *transition = [SGRSystemPlayerTransition attachTo:page];
    transition.source = ^UIView *{ return capsule; };
    __weak typeof(self) weakMini = self;
    // Drawn rather than snapshotted: the capsule over it is hidden while the page is open, and a hidden view's snapshot
    // comes out blank.
    transition.row = ^UIView *{
        typeof(self) mini = weakMini;
        if (!mini || mini.bounds.size.width < 1) return nil;
        UIGraphicsImageRenderer *renderer = [[UIGraphicsImageRenderer alloc] initWithBounds:mini.bounds];
        UIImage *picture = [renderer imageWithActions:^(UIGraphicsImageRendererContext *context) {
            [mini drawViewHierarchyInRect:mini.bounds afterScreenUpdates:YES];
        }];
        return [[UIImageView alloc] initWithImage:picture];
    };
    [presenter presentViewController:page animated:YES completion:^{ buildReadyPage(); }];
}
@end

#pragma mark - the controller

// An empty page: Spotify's page under it shows through and takes the touches.
@interface SGRSystemTabsPage : UIViewController
@end

@implementation SGRSystemTabsPage
- (void)loadView {
    UIView *view = [UIView new];
    view.backgroundColor = UIColor.clearColor;
    view.userInteractionEnabled = NO;
    self.view = view;
}
@end

// Over the whole of Spotify's container, taking only the bar's and the accessory's touches.
@interface SGRSystemTabsHost : UIView
@property (nonatomic, weak) UITabBarController *controller;
@property (nonatomic, weak) UIView *accessoryContent;
@end

@implementation SGRSystemTabsHost
- (UIView *)hitTest:(CGPoint)point withEvent:(UIEvent *)event {
    return [self taken:[super hitTest:point withEvent:event]];
}

- (UIView *)taken:(UIView *)hit {
    UITabBarController *controller = self.controller;
    if (!hit || !controller) return nil;
    if ([hit isDescendantOfView:controller.tabBar]) return hit;
    // The accessory's own card: the content and the views round it up to its glass, card sized. Not the container above
    // them, which covers the screen: kept, it took every touch where the card had stood over the bar once it moved into
    // the row (its owner, 2026-10-31).
    UIView *card = nil;
    for (UIView *v = self.accessoryContent; v && v != controller.viewIfLoaded; v = v.superview) {
        if (v.bounds.size.height > 140) break;
        card = v;
    }
    return card && !card.hidden && card.alpha > 0.01 && [hit isDescendantOfView:card] ? hit : nil;
}
@end

static void clearBackdrops(UITabBarController *controller);

API_AVAILABLE(ios(26.0))
@interface SGRSystemTabs : NSObject <UITabBarControllerDelegate, UIGestureRecognizerDelegate>
@property (nonatomic, strong) UITabBarController *controller;
@property (nonatomic, strong) SGRSystemTabsHost *host;
@property (nonatomic, strong) SGRSystemMiniPlayer *mini;
@property (nonatomic, copy) NSArray<UIView *> *sources;
@property (nonatomic, copy) NSString *titles;
// Each tab's outline and filled glyph by its name, each read off Spotify's item while it was in that state.
@property (nonatomic, strong) NSMutableDictionary<NSString *, UIImage *> *outlines, *filleds;
@property (nonatomic) CFTimeInterval heldUntil;
// The glyphs last put on the tabs, outline and filled, and the tab under a finger dragging the selection bubble (NSNotFound
// while none is): that tab shows its filled glyph as its image while the bubble is over it (dragged:).
@property (nonatomic, copy) NSArray<UIImage *> *shownGlyphs, *shownSelectedGlyphs;
@property (nonatomic) NSUInteger dragIndex;
@end

@implementation SGRSystemTabs
- (BOOL)tabBarController:(UITabBarController *)controller shouldSelectTab:(UITab *)tab {
    // The tap a hold ends in is no tab change: passed on to Spotify, it switched tabs and shut Mod Settings the moment the
    // hold had opened it (its owner's recording, 2026-10-31).
    if (CACurrentMediaTime() < self.heldUntil) return NO;
    NSUInteger index = [controller.tabs indexOfObject:tab];
    if (index < self.sources.count) SGRForwardTabTap(self.sources[index]);
    return YES;
}

- (void)tabBarController:(UITabBarController *)controller didSelectTab:(UITab *)tab previousTab:(UITab *)previous {
    clearBackdrops(controller);
}

// Holding the first tab opens Mod Settings, as on the glass bar (TabBar.x): a little longer than iOS's own press for a
// menu, with a firm tap when it opens.
// The tab buttons have recognizers of their own: the hold runs beside them, or it never began (the phone's log).
- (BOOL)gestureRecognizer:(UIGestureRecognizer *)recognizer shouldRecognizeSimultaneouslyWithGestureRecognizer:(UIGestureRecognizer *)other {
    return YES;
}

// UIKit draws a tab under the sliding selection bubble with its image, tinted, and puts its selectedImage on only once the
// finger lifts, so the filled glyph came in at the release (its owner's recording, 2026-11-02). The finger is followed
// beside UIKit's own recognizers, and the tab under it shows its filled glyph as its image until the finger moves on or
// lifts, so the bubble fills each tab as it passes, as the Music app's does.
- (void)dragged:(UILongPressGestureRecognizer *)drag {
    UITabBar *bar = self.controller.tabBar;
    NSUInteger under = NSNotFound;
    UIGestureRecognizerState state = drag.state;
    // Not on the minimized bar, which has no bubble to drag. (The pale flash of a minimized circle tapped from Search is
    // UIKit's own glass selection moving into it, there with or without this: its owner's test, 2026-11-02.)
    if ((state == UIGestureRecognizerStateBegan || state == UIGestureRecognizerStateChanged) && !SGRSystemTabsMinimized()) {
        NSMutableArray<UIView *> *buttons = [NSMutableArray array];
        SGForEachView(bar, ^(UIView *v) {
            if ([NSStringFromClass(v.class) containsString:@"TabButton"] && v.bounds.size.width > 20) [buttons addObject:v];
        });
        [buttons sortUsingComparator:^NSComparisonResult(UIView *a, UIView *b) {
            return [@([a convertPoint:CGPointZero toView:bar].x) compare:@([b convertPoint:CGPointZero toView:bar].x)];
        }];
        CGFloat x = [drag locationInView:bar].x, nearest = CGFLOAT_MAX;
        for (NSUInteger i = 0; i < buttons.count; i++) {
            CGRect frame = [buttons[i] convertRect:buttons[i].bounds toView:bar];
            CGFloat distance = fabs(CGRectGetMidX(frame) - x);
            if (distance < nearest) {
                nearest = distance;
                under = i;
            }
        }
    }
    if (under == self.dragIndex) return;
    self.dragIndex = under;
    [self showDragGlyphs];
}

- (void)showDragGlyphs {
    NSArray<UITab *> *shown = self.controller.tabs;
    NSArray<UIImage *> *glyphs = self.shownGlyphs, *filled = self.shownSelectedGlyphs;
    for (NSUInteger i = 0; i < shown.count && i < glyphs.count && i < filled.count; i++) {
        UIImage *image = i == self.dragIndex ? filled[i] : glyphs[i];
        if (shown[i].image != image) shown[i].image = image;
    }
}

- (void)held:(UILongPressGestureRecognizer *)hold {
    if (hold.state != UIGestureRecognizerStateBegan || !self.sources.count) return;
    UITabBar *bar = self.controller.tabBar;
    NSMutableArray<UIView *> *buttons = [NSMutableArray array];
    SGForEachView(bar, ^(UIView *v) {
        if ([NSStringFromClass(v.class) containsString:@"TabButton"] && v.bounds.size.width > 20) [buttons addObject:v];
    });
    [buttons sortUsingComparator:^NSComparisonResult(UIView *a, UIView *b) {
        return [@([a convertPoint:CGPointZero toView:bar].x) compare:@([b convertPoint:CGPointZero toView:bar].x)];
    }];
    UIView *first = buttons.firstObject;
    CGPoint point = [hold locationInView:bar];
    BOOL onFirst = first ? CGRectContainsPoint([first convertRect:first.bounds toView:bar], point) : point.x < bar.bounds.size.width / 4;
    if (!onFirst) return;
    self.heldUntil = CACurrentMediaTime() + 2;
    [[[UIImpactFeedbackGenerator alloc] initWithStyle:UIImpactFeedbackStyleMedium] impactOccurred];
    SGOpenModSettings(self.sources.firstObject);
}
@end

static SGRSystemTabs *sg_tabs API_AVAILABLE(ios(26.0));

static UIViewController *systemTabsController(void) {
    if (@available(iOS 26.0, *)) return sg_tabs.controller;
    return nil;
}

// UIKit paints the controller's own view, and the views between it and the pages, in the system background: the first
// try covered all of Spotify in white (its owner's recording, 2026-10-31). Everything but the bar and the accessory is
// made clear, so Spotify's page shows through.
static void clearBackdrops(UITabBarController *controller) {
    UIView *root = controller.viewIfLoaded;
    if (!root) return;
    if (root.backgroundColor != UIColor.clearColor) root.backgroundColor = UIColor.clearColor;
    UIView *bar = controller.tabBar;
    for (UIView *sub in root.subviews) {
        if (sub == bar || [bar isDescendantOfView:sub]) continue;
        if ([NSStringFromClass(sub.class) containsString:@"Transition"] || [NSStringFromClass(sub.class) containsString:@"Wrapper"]) {
            sub.backgroundColor = UIColor.clearColor;
            // The pages' layer takes no touches: it stood in front of the accessory over the bar and took every touch on
            // it (the phone's log, 2026-10-31: taps on the card hit UIViewControllerWrapperView), so they went to Spotify.
            if (sub.userInteractionEnabled) sub.userInteractionEnabled = NO;
            for (UIView *inner in sub.subviews) if (inner.backgroundColor) inner.backgroundColor = UIColor.clearColor;
        }
    }
}

// The direct child of `view` that holds `inner`, or nil.
static UIView *childHolding(UIView *view, UIView *inner) {
    for (UIView *v = inner; v; v = v.superview) if (v.superview == view) return v;
    return nil;
}

static UIScrollView *pageScrollView(UIViewController *container, UIView *host);

// A tab glyph drawn in white as it is, not tinted, kept on the glyph so each pass hands back the same image.
static UIImage *plainGlyph(UIImage *glyph) {
    static char kPlainKey;
    if (!glyph.size.width) return glyph;
    UIImage *plain = objc_getAssociatedObject(glyph, &kPlainKey);
    if (!plain) {
        plain = [glyph imageWithTintColor:UIColor.whiteColor renderingMode:UIImageRenderingModeAlwaysOriginal];
        objc_setAssociatedObject(glyph, &kPlainKey, plain, OBJC_ASSOCIATION_RETAIN_NONATOMIC);
    }
    return plain;
}

void SGRSystemTabsSync(UIViewController *container, UIView *stockBar, NSArray<UIView *> *sources, UIView *active) {
    if (@available(iOS 26.0, *)) {
        UIView *view = container.viewIfLoaded;
        if (!view || !sources.count) return;
        SGRSystemTabs *tabs = sg_tabs;
        if (!tabs) {
            tabs = sg_tabs = [SGRSystemTabs new];
            UITabBarController *controller = [UITabBarController new];
            controller.delegate = tabs;
            controller.overrideUserInterfaceStyle = UIUserInterfaceStyleDark;
            controller.tabBarMinimizeBehavior = UITabBarMinimizeBehaviorOnScrollDown;
            tabs.controller = controller;
            SGRSystemTabsHost *host = [[SGRSystemTabsHost alloc] initWithFrame:view.bounds];
            // Dark on every view it draws: set on the controller alone, the bar's glass and the accessory came out light
            // (its owner, 2026-10-31), taking the appearance of Spotify's container they sit in.
            host.overrideUserInterfaceStyle = UIUserInterfaceStyleDark;
            controller.view.overrideUserInterfaceStyle = UIUserInterfaceStyleDark;
            controller.tabBar.overrideUserInterfaceStyle = UIUserInterfaceStyleDark;
            UILongPressGestureRecognizer *hold = [[UILongPressGestureRecognizer alloc] initWithTarget:tabs action:@selector(held:)];
            hold.minimumPressDuration = 0.8;
            hold.delegate = tabs;
            [controller.tabBar addGestureRecognizer:hold];
            tabs.dragIndex = NSNotFound;
            UILongPressGestureRecognizer *drag = [[UILongPressGestureRecognizer alloc] initWithTarget:tabs action:@selector(dragged:)];
            drag.minimumPressDuration = 0;
            drag.allowableMovement = CGFLOAT_MAX;
            drag.cancelsTouchesInView = NO;
            drag.delaysTouchesBegan = NO;
            drag.delaysTouchesEnded = NO;
            drag.delegate = tabs;
            [controller.tabBar addGestureRecognizer:drag];
            host.autoresizingMask = UIViewAutoresizingFlexibleWidth | UIViewAutoresizingFlexibleHeight;
            host.controller = controller;
            tabs.host = host;
            SGRSystemMiniPlayer *mini = [SGRSystemMiniPlayer new];
            mini.overrideUserInterfaceStyle = UIUserInterfaceStyleDark;
            tabs.mini = mini;
            controller.bottomAccessory = [[UITabAccessory alloc] initWithContentView:mini];
            host.accessoryContent = mini;
        }
        UITabBarController *controller = tabs.controller;
        SGRSystemTabsHost *host = tabs.host;
        if (controller.parentViewController != container) {
            [container addChildViewController:controller];
            controller.view.frame = host.bounds;
            controller.view.autoresizingMask = UIViewAutoresizingFlexibleWidth | UIViewAutoresizingFlexibleHeight;
            [host addSubview:controller.view];
            [controller didMoveToParentViewController:container];
        }
        // Just above Spotify's bar and its mini player, not over everything: Spotify puts its player in this same
        // container, and the host brought to the front each pass stood over the player as it opened (the phone's log,
        // 2026-10-31: the player opened, out of sight).
        UIView *below = nil;
        for (UIView *inner in @[stockBar ?: UIView.new, sgr_nowPlayingRoot ?: UIView.new]) {
            UIView *child = childHolding(view, inner);
            if (child && child != host && (!below || [view.subviews indexOfObject:child] > [view.subviews indexOfObject:below])) below = child;
        }
        if (host.superview != view) host.frame = view.bounds;
        NSUInteger hostIndex = host.superview == view ? [view.subviews indexOfObject:host] : NSNotFound;
        NSUInteger belowIndex = below ? [view.subviews indexOfObject:below] : NSNotFound;
        if (below && hostIndex != belowIndex + 1) [view insertSubview:host aboveSubview:below];
        else if (!below && host.superview != view) [view addSubview:host];
        clearBackdrops(controller);
        // Apple Music style off (the Mini player page) holds the bar at full size: the mod's own minimize reads the switch
        // as each scroll goes (TabBarMinimize.x), and UIKit's, where it stands in, is told never (its owner, 2026-11-01).
        UITabBarMinimizeBehavior minimize = SGEnabled(SGRKeyNavbarMinimize) ? UITabBarMinimizeBehaviorOnScrollDown : UITabBarMinimizeBehaviorNever;
        if (controller.tabBarMinimizeBehavior != minimize) controller.tabBarMinimizeBehavior = minimize;
        // The redesign's accent on the selected tab, as on the glass bar (its owner, 2026-10-31).
        UIColor *accent = SGRAccent();
        if (![controller.tabBar.tintColor isEqual:accent]) controller.tabBar.tintColor = accent;
        if (![controller.view.tintColor isEqual:accent]) controller.view.tintColor = accent;

        // The tabs again only when Spotify's items or their names changed; their glyphs follow in place at every pass.
        // Icons only on the Tab bar page (SGRKeyNavbarHideLabels, as the glass bar reads it in TabBar.x): each tab without
        // a name, which UIKit draws as its glyph alone (its owner, 2026-11-01: the system tab bar kept its names). Part of
        // what is compared, so switching it builds the tabs again at the next pass, which the page's SGRRefreshTabBar asks for.
        BOOL namesHidden = SGHidden(SGRKeyNavbarHideLabels);
        NSMutableString *titles = [NSMutableString stringWithString:namesHidden ? @"icons only\n" : @"names\n"];
        for (UIView *source in sources) [titles appendFormat:@"%@\n", SGRTabSourceTitle(source)];
        // Each tab's outline and filled glyph, as the glass bar draws Spotify's item (TabBar.x): Spotify swaps the item's icon
        // itself between the two as the item becomes active, so the glyph read at a pass is filed as the filled one when the
        // item is active then, else as the outline, and kept by the tab's name. UIKit draws the outline unselected and the
        // filled one selected and under its selection bubble as it slides (its owner, 2026-11-01: the same icon for both left
        // the bubble nothing to fill; a pair built once from the tab active then kept that tab filled unselected and the
        // others never filled). A tab seen in one state only uses that glyph for both until it is seen in the other, and a
        // glyph read again replaces its state's, so they follow the tab editor.
        if (!tabs.outlines) tabs.outlines = [NSMutableDictionary dictionary];
        if (!tabs.filleds) tabs.filleds = [NSMutableDictionary dictionary];
        NSMutableArray<UIImage *> *glyphs = [NSMutableArray arrayWithCapacity:sources.count];
        NSMutableArray<UIImage *> *selectedGlyphs = [NSMutableArray arrayWithCapacity:sources.count];
        // Spotify's own tabs from Spotify's Encore glyphs, outline and filled, known from the first launch (TabBar.x's
        // SGRTabSourceEncoreGlyphs), so the bubble fills each as it passes from the start (its owner, 2026-11-02). A tab of
        // the mod's own, one picture either way, is drawn from its item as it stands.
        for (UIView *source in sources) {
            NSString *name = SGRTabSourceTitle(source) ?: @"";
            UIImage *encoreOutline = nil, *encoreFilled = nil;
            if (SGRTabSourceEncoreGlyphs(source, &encoreOutline, &encoreFilled)) {
                tabs.outlines[name] = encoreOutline;
                tabs.filleds[name] = encoreFilled;
            } else {
                UIImage *picture = SGRTabSourceGlyph(source, NO);
                if (picture) tabs.outlines[name] = tabs.filleds[name] = picture;
            }
            UIImage *outline = tabs.outlines[name] ?: tabs.filleds[name], *filled = tabs.filleds[name] ?: tabs.outlines[name];
            [glyphs addObject:outline ?: [UIImage new]];
            [selectedGlyphs addObject:filled ?: outline ?: [UIImage new]];
        }
        if (![sources isEqualToArray:tabs.sources] || ![titles isEqualToString:tabs.titles]) {
            // The last tab, whichever the editor put there, stands on its own at the trailing end as the Music app's Search
            // does (its owner, 2026-10-31, as the glass bar's trailing circle was): UIKit gives that place to a search tab,
            // so the last tab is one, with its own name and glyph in place of the magnifier.
            NSUInteger searchIndex = sources.count > 1 ? sources.count - 1 : NSNotFound;
            NSMutableArray<UITab *> *items = [NSMutableArray array];
            UIViewController *(^page)(UITab *) = ^UIViewController *(UITab *tab) { return [SGRSystemTabsPage new]; };
            [sources enumerateObjectsUsingBlock:^(UIView *source, NSUInteger i, BOOL *stop) {
                NSString *name = SGRTabSourceTitle(source) ?: @"", *title = namesHidden ? @"" : name;
                NSString *identifier = [NSString stringWithFormat:@"spotifyglass.systemTab.%lu", (unsigned long)i];
                UITab *tab;
                if (i == searchIndex) {
                    tab = [[UISearchTab alloc] initWithViewControllerProvider:page];
                    tab.title = title;
                    tab.image = glyphs[i];
                } else {
                    tab = [[UITab alloc] initWithTitle:title image:glyphs[i] identifier:identifier viewControllerProvider:page];
                }
                if (@available(iOS 26.1, *)) tab.selectedImage = selectedGlyphs[i];
                [items addObject:tab];
            }];
            controller.tabs = items;
            tabs.sources = sources;
            tabs.titles = titles;
        }
        NSUInteger index = active ? [sources indexOfObject:active] : NSNotFound;
        // The trailing search tab, while another tab is the one shown, keeps its outline in white whatever UIKit asks of it:
        // minimized, UIKit drew it in the selected look, filled and in the accent, beside the tab really shown (its owner's
        // recording, 2026-11-01). Drawn as it is rather than tinted, and the same image for both states, until it is picked.
        // Only while minimized: expanded, it keeps its outline and filled glyph, so the selection bubble fills and colors it
        // as it slides over it like every other tab (its owner's recording, 2026-11-02).
        NSUInteger searchAt = sources.count > 1 ? sources.count - 1 : NSNotFound;
        if (searchAt != NSNotFound && index != searchAt && searchAt < glyphs.count && SGRSystemTabsMinimized()) {
            UIImage *plain = plainGlyph(glyphs[searchAt]);
            glyphs[searchAt] = selectedGlyphs[searchAt] = plain;
        }
        // The glyphs in place, only where one changed: the same image again is the same object (TabBar.x caches each icon).
        // The tab under a dragging finger keeps its filled glyph (dragged:).
        tabs.shownGlyphs = glyphs;
        tabs.shownSelectedGlyphs = selectedGlyphs;
        NSArray<UITab *> *shown = controller.tabs;
        for (NSUInteger i = 0; i < shown.count && i < glyphs.count; i++) {
            UITab *tab = shown[i];
            UIImage *image = i == tabs.dragIndex ? selectedGlyphs[i] : glyphs[i];
            if (tab.image != image) tab.image = image;
            if (@available(iOS 26.1, *)) {
                if (tab.selectedImage != selectedGlyphs[i]) tab.selectedImage = selectedGlyphs[i];
            }
        }
        if (index != NSNotFound && index < controller.tabs.count && controller.selectedTab != controller.tabs[index]) controller.selectedTab = controller.tabs[index];
        // UIKit watches the selected page's scroll view from when it is handed over: handed over only once a scroll had
        // begun, a page just switched to took a few scrolls before the bar minimized (its owner, 2026-10-31). So the shown
        // page's scroll view is handed over at each pass, before any scroll.
        // Not when the mod's rule minimizes the bar (SGRSystemTabsCanMinimize): UIKit's own would answer the same scroll.
        UIScrollView *scroll = SGRSystemTabsCanMinimize() ? nil : pageScrollView(container, host);
        if (scroll) SGRSystemTabsFollowScroll(scroll);
    }
}

// The scroll view of the page Spotify shows: the tallest one that scrolls up and down, outside the host.
static UIScrollView *pageScrollView(UIViewController *container, UIView *host) {
    UIViewController *page = nil;
    @try { page = [container valueForKey:@"selectedViewController"]; } @catch (NSException *e) {}
    UIView *root = page.viewIfLoaded ?: container.viewIfLoaded;
    __block UIScrollView *best = nil;
    SGForEachView(root, ^(UIView *v) {
        if (![v isKindOfClass:UIScrollView.class] || [v isDescendantOfView:host] || !v.window || v.hidden || v.alpha < 0.01) return;
        UIScrollView *scroll = (UIScrollView *)v;
        if (scroll.contentSize.height <= scroll.bounds.size.height + 1 || scroll.bounds.size.height < 300) return;
        if (!best || scroll.bounds.size.height * scroll.bounds.size.width > best.bounds.size.height * best.bounds.size.width) best = scroll;
    });
    return best;
}

void SGRSystemTabsFollowScroll(UIScrollView *scrollView) {
    if (@available(iOS 26.0, *)) {
        UIViewController *page = sg_tabs.controller.selectedViewController;
        if (!page || [page contentScrollViewForEdge:NSDirectionalRectEdgeBottom] == scrollView) return;
        [page setContentScrollView:scrollView forEdge:NSDirectionalRectEdgeBottom];
        [page setContentScrollView:scrollView forEdge:NSDirectionalRectEdgeTop];
    }
}

#pragma mark - minimizing by the mod's rule

// UIKit's minimize on scroll took several tab switches to start following a page, and brought the bar back only at the
// top of the list (its owner, 2026-10-31). The page's scroll is judged by the glass bar's rule instead (MinimizeStep.h,
// TabBarMinimize.x: down 24 pt minimizes, back up as much expands, anywhere), and the bar is told. UIKit keeps
// -[UITabBar _setMinimized:] and -_isMinimized to apps it approves ("This can only be called by an approved app", which
// crashed Spotify: its owner, 2026-10-31), so the bar's visual provider, which draws it, is told instead
// (-[_UITabBarVisualProvider setMinimized:], found in UIKit on iOS 27.2), and the state is read from where the accessory
// sits. A provider that is missing or throws is given up for UIKit's own minimize on scroll.
static BOOL sg_providerRefused;

static id visualProvider(UITabBar *bar) {
    if (!bar) return nil;
    Ivar ivar = class_getInstanceVariable(UITabBar.class, "_visualProvider");
    id provider = ivar ? object_getIvar(bar, ivar) : nil;
    return [provider respondsToSelector:NSSelectorFromString(@"setMinimized:")] ? provider : nil;
}

BOOL SGRSystemTabsCanMinimize(void) {
    if (@available(iOS 26.0, *)) {
        UITabBar *bar = sg_tabs.controller.tabBar;
        if (!bar || sg_providerRefused) return NO;
        return visualProvider(bar) != nil;
    }
    return NO;
}

// Minimized when the accessory sits in the bar's row.
BOOL SGRSystemTabsMinimized(void) {
    if (@available(iOS 26.0, *)) return [sg_tabs.mini inline_];
    return NO;
}

void SGRSystemTabsSetMinimized(BOOL minimized) {
    if (@available(iOS 26.0, *)) {
        UITabBar *bar = sg_tabs.controller.tabBar;
        if (!SGRSystemTabsCanMinimize() || SGRSystemTabsMinimized() == minimized) return;
        @try {
            ((void (*)(id, SEL, BOOL))objc_msgSend)(visualProvider(bar), NSSelectorFromString(@"setMinimized:"), minimized);
        } @catch (NSException *e) {
            sg_providerRefused = YES;
            return;
        }
        // The tabs' glyphs again once the accessory has moved: Search is drawn plain only while the bar is minimized.
        dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(0.4 * NSEC_PER_SEC)), dispatch_get_main_queue(), ^{ SGRRefreshTabBar(); });
    }
}

#pragma mark - Spotify's sheets over the player page

// Spotify presents its queue and its Connect sheet from controllers of its own, which stand under the player page: from
// there UIKit refuses them (that controller, or the one presenting the page, already presents) and nothing opens, as the
// owner's recording showed for Connect (2026-11-01). So while the page is up, a presentation started from under it goes up
// from the top of what stands over the page instead, and the page stays where it is. The page's own presentation, one
// from the page or from anything over it, and one from another window (the context menu's hidden host, ContextMenu.x)
// are left alone, and so is one asked for while the page is still zooming in or out, which UIKit would refuse anyway.
static UIViewController *playerPageUp(void) {
    UIViewController *page = systemTabsController().presentedViewController;
    if (![page isKindOfClass:SGRSystemPlayerPage.class] || page.isBeingPresented || page.isBeingDismissed || !page.viewIfLoaded.window) return nil;
    return page;
}

static UIViewController *presenterOverPage(UIViewController *from, UIViewController *presented) {
    if ([presented isKindOfClass:SGRSystemPlayerPage.class]) return nil;
    UIViewController *page = playerPageUp();
    if (!page) return nil;
    for (UIViewController *over = from; over; over = over.presentingViewController) {
        if (over == page) return nil;
    }
    UIWindow *window = from.viewIfLoaded.window;
    if (window && window != page.view.window) return nil;
    UIViewController *top = page;
    while (top.presentedViewController && !top.presentedViewController.isBeingDismissed) top = top.presentedViewController;
    if (top.isBeingPresented || top == presented) return nil;
    return top;
}

// The sheet a controller under the page asked for and the page's top presented instead, kept weakly on the asker: a
// dismissal Spotify sends that asker later is the sheet's (the review, 2026-11-04). Sent on as it was, it found nothing
// presented there, so the sheet stayed up, or the asker, if presented itself, closed instead.
@interface SGRRedirectedSheet : NSObject
@property (nonatomic, weak) UIViewController *sheet;
@end
@implementation SGRRedirectedSheet
@end

static char kRedirectedKey;

// Spotify's own player, which Spotify presents itself when the AI DJ starts or its DJ card on Home is tapped (its owner's
// recordings, 2026-11-09): the mod's page opens in its place, as from the mini player.
// Spotify presents it in its overlay container (NowPlaying_ViewPageImpl.NowPlayingOverlayContainer, from Spotify's chrome
// or from under the page: the owner's log, 2026-11-09), never the player's own controller. Spotify presents the same
// overlay to play a music video, which plays in the mod's page too, on a video surface of Spotify's own (SystemPlayer.m).
static BOOL isSpotifyPlayer(UIViewController *controller) {
    NSString *name = NSStringFromClass(controller.class);
    return [name containsString:@"NowPlayingOverlayContainer"] || [name hasPrefix:@"NowPlaying_ViewImpl."];
}

API_AVAILABLE(ios(26.0)) static SGRSystemMiniPlayer *miniPlayerIn(UIView *root) {
    if ([root isKindOfClass:SGRSystemMiniPlayer.class]) return (SGRSystemMiniPlayer *)root;
    for (UIView *sub in root.subviews) {
        SGRSystemMiniPlayer *found = miniPlayerIn(sub);
        if (found) return found;
    }
    return nil;
}

%hook UIViewController
- (void)presentViewController:(UIViewController *)presented animated:(BOOL)animated completion:(void (^)(void))completion {
    if (@available(iOS 26.0, *)) if (presented && isSpotifyPlayer(presented)) {
        UIViewController *tabs = systemTabsController();
        SGRSystemMiniPlayer *mini = miniPlayerIn(tabs.view.window ?: tabs.view);
        if (mini) {
            if (![tabs.presentedViewController isKindOfClass:SGRSystemPlayerPage.class]) [mini opened];
            if (completion) completion();
            return;
        }
    }
    UIViewController *top = presented ? presenterOverPage((UIViewController *)self, presented) : nil;
    if (!top) {
        %orig;
        return;
    }
    SGRRedirectedSheet *box = [SGRRedirectedSheet new];
    box.sheet = presented;
    objc_setAssociatedObject(self, &kRedirectedKey, box, OBJC_ASSOCIATION_RETAIN_NONATOMIC);
    [top presentViewController:presented animated:animated completion:completion];
}

- (void)dismissViewControllerAnimated:(BOOL)animated completion:(void (^)(void))completion {
    SGRRedirectedSheet *box = objc_getAssociatedObject(self, &kRedirectedKey);
    if (!box) {
        %orig;
        return;
    }
    UIViewController *sheet = box.sheet;
    UIViewController *presenter = sheet.presentingViewController;
    // Only while the sheet is still up and the asker has nothing of its own presented, which it would mean instead.
    if (!presenter || sheet.isBeingDismissed || ((UIViewController *)self).presentedViewController) {
        objc_setAssociatedObject(self, &kRedirectedKey, nil, OBJC_ASSOCIATION_RETAIN_NONATOMIC);
        %orig;
        return;
    }
    objc_setAssociatedObject(self, &kRedirectedKey, nil, OBJC_ASSOCIATION_RETAIN_NONATOMIC);
    [presenter dismissViewControllerAnimated:animated completion:completion];
}
%end

// Sideways, Spotify sets the whole app in a card 8pt in from every edge with 16pt corners (MainUI_TabBarUIImpl's
// InnerContainer in its PrimaryContentContainer: the album dump of 2026-11-08), room its own landscape chrome is drawn
// in. iOS's tab bar floats over the page instead, so the card only left black bars round every screen (its owner,
// 2026-11-08): it fills its container again, square, after Spotify's pass. Upright Spotify does not inset it.
// The views inside keep the card's inset size, laid out by Spotify's own containers on their passes (the page stayed
// 940x412 in the 956x440 card, black down the right and along the bottom: 2026-11-08). Down the chain of full-size
// containers, any that is short of its parent by no more than the card's inset is laid to its parent's bounds; run from
// each container's pass, since each lays out the one under it again.
static void sgr_fillChain(UIView *outer) {
    UIWindow *window = outer.window;
    if (!window || window.bounds.size.width <= window.bounds.size.height) return;
    for (NSInteger depth = 0; depth < 6 && outer; depth++) {
        UIView *inner = nil;
        CGSize room = outer.bounds.size;
        for (UIView *v in outer.subviews) {
            CGRect f = v.frame;
            CGFloat dw = room.width - f.size.width, dh = room.height - f.size.height;
            if (CGPointEqualToPoint(f.origin, CGPointZero) && dw >= -0.5 && dh >= -0.5 && dw <= 32.5 && dh <= 32.5
                && f.size.width > room.width * 0.8) {
                inner = v;
                break;
            }
        }
        if (!inner) break;
        if (!CGRectEqualToRect(inner.frame, outer.bounds)) inner.frame = outer.bounds;
        outer = inner;
    }
}

%group SGRFullBleedCard
%hook _TtC19MainUI_TabBarUIImpl23PrimaryContentContainer
- (void)viewDidLayoutSubviews {
    %orig;
    UIView *host = ((UIViewController *)self).view;
    for (UIViewController *child in ((UIViewController *)self).childViewControllers) {
        if (![NSStringFromClass(child.class) hasSuffix:@"InnerContainer"]) continue;
        UIView *card = child.viewIfLoaded;
        if (card.superview != host) continue;
        if (!CGRectEqualToRect(card.frame, host.bounds)) {
            card.frame = host.bounds;
        }
        if (card.layer.cornerRadius > 0) card.layer.cornerRadius = 0;
        sgr_fillChain(card);
    }
}
%end
%end

%group SGRFullBleedInner
%hook _TtC19MainUI_TabBarUIImpl14InnerContainer
- (void)viewDidLayoutSubviews {
    %orig;
    sgr_fillChain(((UIViewController *)self).view);
}
%end
%end

%group SGRFullBleedMain
%hook _TtC19MainUI_TabBarUIImpl15MainUIContainer
- (void)viewDidLayoutSubviews {
    %orig;
    sgr_fillChain(((UIViewController *)self).view);
}
%end
%end

// And the tab bar container under them, which keeps the page short of the card by the room Spotify's own tab bar takes
// (the navigation controller stayed 940x412 when the rest was 956x440: 2026-11-08).
%group SGRFullBleedTabs
%hook _TtC23NavigationUI_TabBarImpl19TabBarContainerImpl
- (void)viewDidLayoutSubviews {
    %orig;
    sgr_fillChain(((UIViewController *)self).view);
}
%end
%end

%ctor {
    if (!SGRedesignedUI()) return;
    if (!SGRSystemTabsOn()) return;
    %init;
    if (NSClassFromString(@"_TtC23NavigationUI_TabBarImpl19TabBarContainerImpl")) %init(SGRFullBleedTabs);
    if (NSClassFromString(@"_TtC19MainUI_TabBarUIImpl14InnerContainer")) %init(SGRFullBleedInner);
    if (NSClassFromString(@"_TtC19MainUI_TabBarUIImpl15MainUIContainer")) %init(SGRFullBleedMain);
    if (NSClassFromString(@"_TtC19MainUI_TabBarUIImpl23PrimaryContentContainer")) %init(SGRFullBleedCard);
}

void SGRRefreshMiniPlayer(void) {
    if (@available(iOS 26.0, *)) [sg_tabs.mini setNeedsLayout];
}


NSArray<NSString *> *SGRMiniPlayerButtons(void) {
    NSArray *stored = SGArray(SGRKeyMiniPlayerOrder);
    NSArray<NSString *> *all = @[SGRMiniButtonAirPlay, SGRMiniButtonStar, SGRMiniButtonPlay, SGRMiniButtonNext];
    if (![stored isKindOfClass:NSArray.class]) {
        // Before any order was set: the switches that were (AirPlay and Skip on unless switched off, the star off).
        NSMutableArray<NSString *> *on = [NSMutableArray array];
        if (SGEnabled(SGRKeyMiniPlayerAirPlay)) [on addObject:SGRMiniButtonAirPlay];
        if (SGFlag(SGRKeyMiniPlayerLike, NO)) [on addObject:SGRMiniButtonStar];
        [on addObject:SGRMiniButtonPlay];
        if (SGEnabled(SGRKeyMiniPlayerNext)) [on addObject:SGRMiniButtonNext];
        return on;
    }
    NSMutableArray<NSString *> *on = [NSMutableArray array];
    for (id key in stored) if ([key isKindOfClass:NSString.class] && [all containsObject:key] && ![on containsObject:key]) [on addObject:key];
    if (![on containsObject:SGRMiniButtonPlay]) [on addObject:SGRMiniButtonPlay];
    return on;
}

void SGRSetMiniPlayerButtons(NSArray<NSString *> *keys) {
    NSMutableArray<NSString *> *on = [keys mutableCopy] ?: [NSMutableArray array];
    // Play cannot be put away.
    if (![on containsObject:SGRMiniButtonPlay]) [on addObject:SGRMiniButtonPlay];
    [NSUserDefaults.standardUserDefaults setObject:on forKey:SGRKeyMiniPlayerOrder];
    SGPrefsChanged();
    SGRRefreshMiniPlayer();
}
