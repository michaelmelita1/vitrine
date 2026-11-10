// Native redesign's landscape player (iOS 27.3's): the screen the system tab bar's player page (SystemPlayer.m) turns
// sideways to, laid out as the Music app's iPhone landscape player is from iOS 27.3 (its owner's recordings, 2026-11-05).
// On the left the track's Animated clip, carried on past its edges mirrored, stretched and blurred as the page's foot is
// (SystemMotion.m), or without one the square cover inset on a darkened field; on the right a column headed by the title,
// the artist, ★ (Liked Songs) and ⋯ (Exit Full Screen), then either the player (the progress bar and its times, previous,
// play and next, the volume) or the lines, and at its foot lyrics, AirPlay with the output's name under it, and the
// queue. The lyrics button changes between the two; the lines' view fades the column's head and foot after a few seconds
// without a touch, as the page's lyrics do, and a tap on a clear shield brings them back without seeking.
// The page (SystemPlayer.m) holds it while the app is sideways; the turn itself is SystemTurn.m's.
//
// Threading: main thread only.
#import <AVFoundation/AVFoundation.h>
#import "Core/SGCore.h"
#import "Redesigned/Kit/SGRKit.h"
#import "Redesigned/Lyrics/SGRKaraokeView.h"
#import "Shared/Lyrics/Lyrics.h"
#import "Shared/Player/PlayerState.h"
#import "Shared/Haptics/Haptics.h"
#import "Redesigned/Player/Player.h"
#import "Redesigned/Artist/Artist.h"
#import "SystemPlayer.h"
#import "SystemDJRing.h"
#import "SystemQueue.h"
#import "SystemHistory.h"

@interface CAFilter : NSObject
+ (instancetype)filterWithType:(NSString *)type;
@end

static const CGFloat kControlSide = 44;
static const NSTimeInterval kLandscapeRest = 4;
// The portrait page's foot turned sideways (Redesigned/Navbar/SystemMotion.m; its owner, 2026-11-06): past the clip's
// trailing edge it goes on mirrored and stretched kClipStretch times across the rest of the screen (its owner's pick,
// 2026-11-06), and one variable blur, at the foot's radius, starts at nothing on the mirror line, so the line never shows, and grows slowly over the
// reflection (kSideBlur). Before a tall clip's leading edge its mirror is lightly blurred, as the portrait band is. The column is dimmed for its text from kBlurFrom (a share of the clip's width), and the field behind a cover.
static const CGFloat kClipStretch = 4.5, kBlurFrom = 0.86, kBlurRadius = 72;
// The foot's blur steps (SystemMotion.m's kFootBlur) measured from the mirror line instead of down the screen: how far
// past the clip's trailing edge, as shares of its width (the portrait cover's width standing in for its height), and the
// share of the whole radius there.
// Heavier sooner than the foot's (its owner, 2026-11-06: the reflection needed more blur over it, as the Music app's).
static const CGFloat kSideBlur[][2] = {{0, 0}, {0.05, 0.06}, {0.12, 0.2}, {0.22, 0.45}, {0.36, 0.75}, {0.55, 1}};
// Before a tall clip's leading edge, the portrait band's light blur (SystemMotion.m's kTopBlur...): this much at the
// screen's edge, this much at the clip's, gone this share of the clip's width inside it.
// None at the mirror line itself or inside the clip (its owner, 2026-11-06: "make it start blurring at the mirror line").
static const CGFloat kLeadBlurEdge = 0.6, kLeadBlurAtClip = 0, kLeadBlurInside = 0;
// The Music app keeps the clip sharp to about 42% of the screen and the column's colors deep, a dark slate over a dark
// brown where a plain dim drew gray (its owner's screenshot, 2026-11-05): the column is saturated this much again,
// from where the dim starts.
static const CGFloat kWashSaturation = 1.5;
static const CGFloat kWashDim = 0.55, kWashDimRamp = 120, kFieldDim = 0.35;
// The Music app shows a square clip a little larger than the screen is tall, so its edges are off the screen. It shows
// the tall one (3:4), which has none, larger still: 1.16 times as tall as the screen, its top at the screen's, its middle
// a quarter of the way across, and the strip before it its mirror, sharp (its owner's recording, 2026-11-06: no blur on
// the left).
static const CGFloat kClipZoom = 1.08, kTallHeight = 1.16, kTallTop = -0.015, kTallCentre = 0.255, kTallFrom = 1.1;
// iOS 27.3's places, as shares of the screen (its owner's recordings, 2026-11-05, measured on an iPhone 17 Pro): the
// column's edges, the cover's, and the middles of each row of the column in the player's view and the lines'.
static const CGFloat kColumnLeft = 0.495, kColumnRight = 0.944;
static const CGFloat kCoverLeft = 0.076, kCoverTop = 0.084, kCoverHeight = 0.82;
static const CGFloat kHeadMid = 0.222, kHeadMidLines = 0.135, kBarMid = 0.372, kTimesTop = 0.405, kTransportMid = 0.524;
static const CGFloat kVolumeMid = 0.675, kFootMid = 0.862, kRouteNameMid = 0.934, kLinesTop = 0.235, kLinesBottom = 0.815;
// The lines' top and foot while the controls rest.
static const CGFloat kLinesTopResting = 0.06, kLinesBottomResting = 0.95;
static const CGFloat kStarCentre = 0.876, kMoreCentre = 0.927, kPreviousCentre = 0.607, kNextCentre = 0.831;
static const CGFloat kLyricsCentre = 0.514, kRouteCentre = 0.719, kQueueCentre = 0.924;
// The lines at the portrait page's size, whatever the Lyrics page sets it to (its owner, 2026-11-06).
static const CGFloat kLinesScale = 1;
// The cover's size while paused: the page's (SystemPlayer.m's kPausedScale).
static const CGFloat kPausedScale = 0.84;
// The title's swipe, as the portrait page's (SystemPlayer.m): how far or fast it skips, the gap between the two tracks'
// titles, and the soft edge the block cuts them through.
static const CGFloat kTitleSwipeDistance = 0.28, kTitleSwipeSpeed = 600, kTitlePageGap = 24, kTitleFade = 14;

// A layer for views that takes no touch of its own, only its subviews'.
@interface SGRSystemPassView : UIView
@end
@implementation SGRSystemPassView
- (UIView *)hitTest:(CGPoint)point withEvent:(UIEvent *)event {
    UIView *hit = [super hitTest:point withEvent:event];
    return hit == self ? nil : hit;
}
@end

// The rest's shield: over everything but `passing`, where the touches go to what is under it (the lines, which a drag
// scrolls whatever the controls are doing; its owner's recording, 2026-11-06: a drag on the lines at rest woke the
// controls instead, so scrolling worked one time in two).
@interface SGRSystemShieldView : UIView
@property (nonatomic, weak) UIView *passing;
@end

@implementation SGRSystemShieldView
- (UIView *)hitTest:(CGPoint)point withEvent:(UIEvent *)event {
    UIView *passing = self.passing;
    if (passing.window && passing.alpha > 0.01 && !passing.hidden
        && CGRectContainsPoint([passing convertRect:passing.bounds toView:self], point)) return nil;
    return [super hitTest:point withEvent:event];
}
@end

@interface SGRSystemLandscapeController : UIViewController <SGPlayerStateObserver, UIGestureRecognizerDelegate>
- (void)setLyricsMode:(BOOL)lyrics animated:(BOOL)animated;
- (void)setQueueMode:(BOOL)queue animated:(BOOL)animated;
- (void)showingLyrics:(BOOL *)lyrics queue:(BOOL *)queue;
- (void)updateBare:(BOOL)mayGoBare;
@end

@implementation SGRSystemLandscapeController {
    SGRArtworkField *_field;
    UIImageView *_cover;
    SGRDJRingView *_djRing;          // the DJ's blue page and ring, as the portrait page's, while the DJ talks
    BOOL _narrating;
    SGMarqueeLabel *_title, *_artist;
    UIView *_controls;               // previous, play and next
    SGRSystemControlButton *_previous, *_play, *_next;
    UIButton *_close;
    UIView *_stage;   // the lines' own view: the karaoke view dims every sibling it has
    SGRKaraokeView *_lyrics;
    NSTimer *_rest;
    UITapGestureRecognizer *_hide;   // only while the controls are up
    SGRSystemShieldView *_shield;    // only while they are not: the touch that brings them back, but on the lines
    BOOL _bare;                      // the track playing has no lines: the cover takes the screen
    // The clip, when the track has one: sharp on the left, and again under a blur behind the column (one player for both).
    UIView *_clip;
    CAReplicatorLayer *_clipCopy;    // the clip and its mirrored, stretched copy past its trailing edge
    CAReplicatorLayer *_clipLead;    // inside that, a tall clip's copy before its leading edge
    CGFloat _clipAspect;             // the clip's height over its width
    AVPlayerLayer *_clipLayer;       // under the blur: the clip with its mirrored copies
    CAGradientLayer *_clipDim;       // over the column, for its text
    UIView *_clipTint;               // over that, the column's colors deepened (a backdrop with a saturation filter)
    CAGradientLayer *_clipTintMask;
    UIVisualEffectView *_clipBlur;   // only on an OS without the variable blur
    CAGradientLayer *_clipBlurMask;
    NSString *_blurKey;              // the stops the variable blur's mask was drawn for
    AVQueuePlayer *_clipPlayer;
    AVPlayerLooper *_clipLooper;
    NSURL *_clipFile;
    NSArray<NSString *> *_queueKey;   // the queue Spotify's list was shown from, which a move is checked against
    BOOL _clipped;
    // The column (iOS 27.3's): the head's ★, the player's view, and the foot.
    UIView *_fieldDim;
    SGRSystemScrubber *_scrubber;
    UILabel *_elapsed, *_remaining, *_routeName;
    UIControl *_volume;
    SGRSystemControlButton *_lyricsButton, *_queueButton, *_star;
    SGRSystemControlButton *_switchVideo, *_djButton;   // beside the star, as on the page (SGRSystemSyncRowButtons)
    UIImageView *_lyricsDisc, *_queueDisc;   // the buttons' light discs while lit, the page's (SystemPlayer.m)
    SGRSystemQueueView *_queue;      // the queue's view, in the column in the lines' place
    BOOL _queueMode;
    BOOL _resting;                // the controls away (setControlsShown:): the lines take the room they leave
    UIPanGestureRecognizer *_wakePan;       // the rest's shield's, which leaves the page's swipe down its pan
    SGRSystemControlButton *_shuffle, *_repeat;   // either side of the transport, as the page's
    BOOL _shuffleOff, _repeatOff;                 // the Player page's Hide on the player, read at each open
    UIView *_optionBadge;                          // shuffle or repeat on the queue button, as the page has it
    UIView *_head;                // the title row (title, artist, ★, ⋯), which the queue's scroll pushes out
    UIView *_titleBlock;          // the title and artist, which a sideways swipe pages through the tracks, as the page's
    CAGradientLayer *_titleFade;
    SGMarqueeLabel *_besideTitle, *_besideArtist;   // the track the swipe brings in
    BOOL _titleSkipping;
    BOOL _titlePast;   // the swipe is past where letting go skips
    NSString *_titleSkipFrom;
    CGFloat _headPush;            // how far it has, 0 to the queue's headRoom
    BOOL _queueDragging;          // a track lifted in the queue: the foot is away and the list runs to the screen's foot
    NSUInteger _dragReturn;       // the latest let go, so an earlier one's delayed return does not bring the foot back
    BOOL _pausedShown;
    UIView *_videoHolder;           // the music video, borrowed from the page while it plays (SGRSystemTurnVideoSurface)
    __weak UIView *_videoShown;     // the surface in it
    UIView *_videoDim;              // over the full screen video while the controls are up
    BOOL _hadTrack, _emptyPending;  // a track shown, and a look again pending before Not Playing (as the page's show:)
    UIView *_route;
    NSTimer *_tick;
    BOOL _lyricsMode;
    id _savedWatch;
    NSString *_savedTrack;
    BOOL _saved;
}

- (BOOL)prefersStatusBarHidden {
    return YES;
}

- (BOOL)prefersHomeIndicatorAutoHidden {
    return YES;
}

// A glyph in a 44pt square, so the touch is as large as the default control whatever the glyph's size.
static UIButton *controlButton(NSString *symbol, CGFloat size, NSString *label, SEL action, id target) {
    UIButton *button = [UIButton buttonWithType:UIButtonTypeSystem];
    [button setImage:[UIImage systemImageNamed:symbol withConfiguration:
        [UIImageSymbolConfiguration configurationWithPointSize:size weight:UIImageSymbolWeightBold]] forState:UIControlStateNormal];
    button.tintColor = UIColor.whiteColor;
    button.accessibilityLabel = label;
    [button addTarget:target action:action forControlEvents:UIControlEventTouchUpInside];
    [button.widthAnchor constraintEqualToConstant:kControlSide].active = YES;
    [button.heightAnchor constraintEqualToConstant:kControlSide].active = YES;
    return button;
}

// The title and the artist at the phone's text size, capped where the column still holds a cover.
- (void)applyFonts {
    _title.font = _besideTitle.font = SGRFont(UIFontTextStyleTitle3, UIFontWeightBold, UIContentSizeCategoryExtraExtraExtraLarge);
    _artist.font = _besideArtist.font = SGRFont(UIFontTextStyleCallout, UIFontWeightRegular, UIContentSizeCategoryExtraExtraExtraLarge);
}

- (void)traitCollectionDidChange:(UITraitCollection *)previous {
    [super traitCollectionDidChange:previous];
    [self applyFonts];
    [self.view setNeedsLayout];
}

- (void)viewDidLoad {
    [super viewDidLoad];
    self.view.backgroundColor = UIColor.blackColor;

    // The player's own field behind the screen, so the colors carry over from the portrait player.
    _field = [[SGRArtworkField alloc] initWithFrame:self.view.bounds];
    _field.autoresizingMask = UIViewAutoresizingFlexibleWidth | UIViewAutoresizingFlexibleHeight;
    _field.showsBackdrop = YES;
    _field.fluid = YES;
    NSString *identity = nil;
    UIImage *art = SGRNowPlayingArtwork(NULL, &identity);
    if (art) [_field setArtwork:art identity:identity animated:NO];
    [self.view addSubview:_field];
    _fieldDim = [UIView new];
    _fieldDim.backgroundColor = [UIColor colorWithWhite:0 alpha:kFieldDim];
    _fieldDim.userInteractionEnabled = NO;
    [self.view addSubview:_fieldDim];

    _clip = [[UIView alloc] initWithFrame:self.view.bounds];
    _clip.clipsToBounds = YES;
    _clip.alpha = 0;
    _clip.userInteractionEnabled = NO;
    _clipLayer = [AVPlayerLayer layer];
    _clipLayer.videoGravity = AVLayerVideoGravityResizeAspectFill;
    // Anchored at its origin, so the copy's transform is made about a point in the clip's own terms. One player layer
    // drawn twice, so the copy always shows the very frame the clip does.
    _clipCopy = [CAReplicatorLayer layer];
    _clipCopy.anchorPoint = CGPointZero;
    _clipCopy.instanceCount = 2;
    _clipLead = [CAReplicatorLayer layer];
    _clipLead.anchorPoint = CGPointZero;
    [_clipLead addSublayer:_clipLayer];
    [_clipCopy addSublayer:_clipLead];
    [_clip.layer addSublayer:_clipCopy];
    _clipDim = [CAGradientLayer layer];
    _clipDim.startPoint = CGPointMake(0, 0.5);
    _clipDim.endPoint = CGPointMake(1, 0.5);
    _clipDim.colors = @[(id)UIColor.clearColor.CGColor, (id)[UIColor colorWithWhite:0 alpha:kWashDim].CGColor];
    [_clip.layer addSublayer:_clipDim];
    if (![NSClassFromString(@"CAFilter") filterWithType:@"variableBlur"]) {
        _clipBlur = [[UIVisualEffectView alloc] initWithEffect:[UIBlurEffect effectWithStyle:UIBlurEffectStyleSystemUltraThinMaterialDark]];
        UIView *mask = [UIView new];
        _clipBlurMask = [CAGradientLayer layer];
        _clipBlurMask.startPoint = CGPointMake(0, 0.5);
        _clipBlurMask.endPoint = CGPointMake(1, 0.5);
        _clipBlurMask.colors = @[(id)UIColor.clearColor.CGColor, (id)UIColor.blackColor.CGColor];
        [mask.layer addSublayer:_clipBlurMask];
        _clipBlur.maskView = mask;
        [_clip addSubview:_clipBlur];
    }
    [self.view addSubview:_clip];
    _clipTint = [UIView new];
    _clipTint.alpha = 0;
    _clipTint.userInteractionEnabled = NO;
    Class backdrop = NSClassFromString(@"CABackdropLayer");
    id saturate = [NSClassFromString(@"CAFilter") filterWithType:@"colorSaturate"];
    if (backdrop && saturate) {
        [saturate setValue:@(kWashSaturation) forKey:@"inputAmount"];
        CALayer *layer = [backdrop layer];
        layer.filters = @[saturate];
        layer.name = @"tint";
        [_clipTint.layer addSublayer:layer];
        _clipTintMask = [CAGradientLayer layer];
        _clipTintMask.startPoint = CGPointMake(0, 0.5);
        _clipTintMask.endPoint = CGPointMake(1, 0.5);
        _clipTintMask.colors = @[(id)UIColor.clearColor.CGColor, (id)UIColor.blackColor.CGColor];
        _clipTint.layer.mask = _clipTintMask;
    }
    [self.view addSubview:_clipTint];

    _cover = [UIImageView new];
    _cover.contentMode = UIViewContentModeScaleAspectFill;
    _cover.clipsToBounds = YES;
    _cover.layer.cornerRadius = SGRRadiusArtwork;
    _cover.layer.cornerCurve = kCACornerCurveContinuous;
    _cover.image = art ?: (SGRSystemIsTrack(SGPlayerState().track) ? nil : SGRSystemNotPlayingArt());
    [self.view addSubview:_cover];

    // A title or artist too long for the column scrolls, as the player's own do.
    _title = [SGMarqueeLabel new];
    _title.textColor = UIColor.whiteColor;
    _artist = [SGMarqueeLabel new];
    _artist.textColor = [UIColor colorWithWhite:1 alpha:0.6];
    [self applyFonts];
    _head = [SGRSystemPassView new];
    [self.view addSubview:_head];
    // The title and artist in a block cut through a soft edge, which a sideways swipe pages through the tracks with the
    // track coming in beside them, as the portrait page's (SystemPlayer.m's titleSwiped:).
    _titleBlock = [UIView new];
    _titleBlock.clipsToBounds = YES;
    _titleFade = [CAGradientLayer layer];
    _titleFade.startPoint = CGPointMake(0, 0.5);
    _titleFade.endPoint = CGPointMake(1, 0.5);
    _titleFade.colors = @[(id)UIColor.clearColor.CGColor, (id)UIColor.blackColor.CGColor, (id)UIColor.blackColor.CGColor, (id)UIColor.clearColor.CGColor];
    _titleBlock.layer.mask = _titleFade;
    _besideTitle = [SGMarqueeLabel new];
    _besideTitle.textColor = _title.textColor;
    _besideArtist = [SGMarqueeLabel new];
    _besideArtist.textColor = _artist.textColor;
    _besideTitle.hidden = _besideArtist.hidden = YES;
    _besideTitle.isAccessibilityElement = _besideArtist.isAccessibilityElement = NO;
    for (SGMarqueeLabel *label in @[_title, _artist, _besideTitle, _besideArtist]) {
        label.leadingFade = kTitleFade;
        [_titleBlock addSubview:label];
    }
    [self applyFonts];
    UIPanGestureRecognizer *swipe = [[UIPanGestureRecognizer alloc] initWithTarget:self action:@selector(titleSwiped:)];
    swipe.delegate = self;
    [_titleBlock addGestureRecognizer:swipe];
    [_head addSubview:_titleBlock];
    // The Music app's ⋯, holding the way back to the player for a phone that is not turned back.
    _close = controlButton(@"ellipsis", 20, @"More", NULL, self);
    _close.menu = [self moreMenu];
    _close.showsMenuAsPrimaryAction = YES;
    [_head addSubview:_close];
    __weak SGRSystemLandscapeController *buttonSelf = self;
    _star = [SGRSystemControlButton buttonWithSymbol:@"star" pointSize:22 title:@"Add to Liked Songs"];
    _star.glyph.tintColor = UIColor.whiteColor;
    _star.onTap = ^{ [buttonSelf toggleSaved]; };
    [_head addSubview:_star];
    // Switch to Video and the DJ's sheet beside the star, leftwards, as on the portrait page (its owner, 2026-11-10: none
    // of the new buttons in landscape).
    _switchVideo = [SGRSystemControlButton buttonWithSymbol:@"music.note.tv" pointSize:22 title:@"Music Video"];
    _switchVideo.glyph.tintColor = UIColor.whiteColor;
    _switchVideo.hidden = YES;
    _switchVideo.onTap = ^{ SGRSystemSwitchVideo(); };
    _djButton = [SGRSystemControlButton buttonWithSymbol:@"waveform" pointSize:22 title:@"DJ X"];
    _djButton.glyph.image = SGRDJGlyphImage(22);
    _djButton.glyph.tintColor = UIColor.whiteColor;
    _djButton.hidden = YES;
    _djButton.onTap = ^{ SGRSystemOpenDJ(); };
    [_head addSubview:_switchVideo];
    [_head addSubview:_djButton];

    // The player's view: the progress bar with its times, the controls and the volume.
    _scrubber = [SGRSystemScrubber new];
    __weak SGRSystemLandscapeController *barSelf = self;
    _scrubber.onMove = ^(CGFloat value) { [barSelf showTimesAt:value * SGPlayerState().duration]; };
    _scrubber.onRelease = ^(CGFloat value) { [barSelf seekTo:value]; };
    [self.view addSubview:_scrubber];
    _elapsed = [UILabel new];
    _remaining = [UILabel new];
    _remaining.textAlignment = NSTextAlignmentRight;
    for (UILabel *label in @[_elapsed, _remaining]) {
        label.font = [UIFont monospacedDigitSystemFontOfSize:13 weight:UIFontWeightSemibold];
        label.textColor = [UIColor colorWithWhite:1 alpha:0.6];
        [self.view addSubview:label];
    }
    _scrubber.leadingLabel = _elapsed;
    _scrubber.trailingLabel = _remaining;
    _volume = SGRPlayerMakeVolumeRow();
    [self.view addSubview:_volume];

    // The foot: lyrics, AirPlay with the output's name under it, and the queue.
    // The lyrics button as the page draws its own: the glyph, and in the lines' view a light disc with the filled glyph
    // cut out of it (its owner, 2026-11-06: it should look the same as in portrait).
    _lyricsButton = [SGRSystemControlButton buttonWithSymbol:@"quote.bubble" pointSize:20 title:@"Lyrics"];
    _lyricsButton.glyph.tintColor = UIColor.whiteColor;
    _lyricsButton.onTap = ^{ [buttonSelf toggleLyricsMode]; };
    _lyricsDisc = SGRSystemCutDisc(@"quote.bubble.fill");
    [_lyricsButton insertSubview:_lyricsDisc atIndex:0];
    // The queue opens in the column, in the lines' place, as the page's opens in its own (its owner, 2026-11-06: turning
    // back to portrait for it looked like it had not worked).
    _queueButton = [SGRSystemControlButton buttonWithSymbol:@"list.bullet" pointSize:20 title:@"Queue"];
    _queueButton.glyph.tintColor = UIColor.whiteColor;
    _queueButton.onTap = ^{ [buttonSelf toggleQueueMode]; };
    _queueDisc = SGRSystemCutDisc(@"list.bullet");
    [_queueButton insertSubview:_queueDisc atIndex:0];
    _optionBadge = SGRSystemMakeOptionBadge(_queueButton);
    _route = SGRSystemMakeRouteButton(20, @"the landscape player");
    _routeName = [UILabel new];
    _routeName.font = [UIFont systemFontOfSize:13 weight:UIFontWeightSemibold];
    _routeName.textColor = [UIColor colorWithWhite:1 alpha:0.7];
    _routeName.textAlignment = NSTextAlignmentCenter;
    for (UIView *view in @[_lyricsButton, _route, _routeName, _queueButton]) [self.view addSubview:view];
    [self syncRouteName];
    [NSNotificationCenter.defaultCenter addObserver:self selector:@selector(syncRouteName) name:SGRPlayerOutputDidChangeNotification object:nil];

    // Previous, play and next as the page's (SystemPlayer.m): their press, play and pause's turn, the skips' step.
    _controls = [UIView new];
    _previous = [SGRSystemControlButton buttonWithSymbol:@"backward.fill" pointSize:28 title:@"Previous"];
    _previous.onTap = ^{ [buttonSelf previous]; };
    _play = [SGRSystemControlButton buttonWithSymbol:@"pause.fill" pointSize:36 title:@"Pause"];
    _play.onTap = ^{ [buttonSelf togglePlay]; };
    _next = [SGRSystemControlButton buttonWithSymbol:@"forward.fill" pointSize:28 title:@"Next"];
    _next.onTap = ^{ [buttonSelf next]; };
    for (SGRSystemControlButton *button in @[_previous, _play, _next]) {
        button.transport = YES;
        button.glyph.tintColor = UIColor.whiteColor;
        // Without the symbols' baseline, as the page's, so a press or a turn keeps the glyph's middle.
        button.glyph.withoutBaseline = YES;
        button.glyph.image = [UIImage systemImageNamed:button.glyph.symbol withConfiguration:button.glyph.preferredSymbolConfiguration].imageWithoutBaseline;
        [_controls addSubview:button];
    }
    [self.view addSubview:_controls];
    // Shuffle and Repeat at the column's edges on the transport's row, as the portrait page has them, under the same
    // switches (its owner, 2026-11-06): hidden there, they are not here either, and the queue's chips carry them instead.
    _shuffle = [SGRSystemControlButton buttonWithSymbol:@"shuffle" pointSize:19 title:@"Shuffle"];
    _shuffle.onTap = ^{ SGRSystemToggleShuffle(); };
    _repeat = [SGRSystemControlButton buttonWithSymbol:@"repeat" pointSize:19 title:@"Repeat"];
    _repeat.onTap = ^{ SGRSystemCycleRepeat(); };
    _shuffleOff = SGHidden(SGRKeyPlayerHideShuffle);
    _repeatOff = SGHidden(SGRKeyPlayerHideRepeat);
    for (SGRSystemControlButton *button in @[_shuffle, _repeat]) {
        button.glyph.tintColor = UIColor.whiteColor;
        button.accessibilityElementsHidden = button == _shuffle ? _shuffleOff : _repeatOff;
        [self.view addSubview:button];
    }

    _stage = [UIView new];
    [self.view addSubview:_stage];
    _lyrics = [[SGRKaraokeView alloc] initWithFrame:CGRectZero];
    _lyrics.autoresizingMask = UIViewAutoresizingFlexibleWidth | UIViewAutoresizingFlexibleHeight;
    _lyrics.lookScale = kLinesScale;
    // Sing's mic over the lines, not a row of its own: the screen is short (its owner, 2026-11-06).
    _lyrics.rowOverLines = YES;
    [_stage addSubview:_lyrics];
    __weak SGRSystemLandscapeController *weakSelf = self;
    _lyrics.browsingBegan = ^(BOOL onward) { [weakSelf rest]; };
    _queue = [SGRSystemQueueView new];
    _queue.alpha = 0;
    _queue.onPick = ^(SPTPlayerTrack *track) {
        id<SPTPlayer> player = (id<SPTPlayer>)SGPlayer();
        if ([player respondsToSelector:@selector(skipToNextTrackWithOptions:track:)]) [player skipToNextTrackWithOptions:nil track:track];
    };
    _queue.onReorder = ^(NSArray *upcoming) {
        SGRSystemLandscapeController *me = weakSelf;
        if (!me) return;
        SGRSystemHandQueueBack(me->_queueKey, upcoming, ^(NSArray<NSString *> *key) {
            SGRSystemLandscapeController *again = weakSelf;
            if (again) again->_queueKey = key;
        }, ^{ [weakSelf refreshQueue]; });
    };
    // As the portrait page's queue (SystemPlayer.m): the screen has no Shuffle or Repeat of its own, so the queue's
    // chips carry them, as the Music app's landscape queue does; a lift puts the foot away while a track is moved.
    _queue.showsShuffle = _shuffleOff;
    _queue.showsRepeat = _repeatOff;
    _queue.onShuffle = ^{ SGRSystemToggleShuffle(); };
    _queue.onRepeat = ^{ SGRSystemCycleRepeat(); };
    _queue.onDragging = ^(BOOL dragging) { [weakSelf setQueueDragging:dragging]; };
    _queue.onHeadPush = ^(CGFloat push) { [weakSelf pushHead:push]; };
    _queue.onPickPast = ^(SPTPlayerTrack *track, NSInteger steps) {
        if (SGRSystemHistoryOn()) SGRSystemPlayPast(track);
        else SGRSystemStepBack(track, steps);
    };
    // Under the foot, as the list now runs on behind it.
    [self.view insertSubview:_queue belowSubview:_lyricsButton];


    _hide = [[UITapGestureRecognizer alloc] initWithTarget:self action:@selector(rest)];
    // Never a button's touch: on the phone the tap to rest took the lyrics button's (its owner, 2026-11-06).
    _hide.delegate = self;
    [self.view addGestureRecognizer:_hide];
    _shield = [[SGRSystemShieldView alloc] initWithFrame:self.view.bounds];
    _shield.passing = _stage;
    _shield.autoresizingMask = UIViewAutoresizingFlexibleWidth | UIViewAutoresizingFlexibleHeight;
    _shield.accessibilityElementsHidden = YES;
    [_shield addGestureRecognizer:[[UITapGestureRecognizer alloc] initWithTarget:self action:@selector(wake)]];
    // A pan wakes the controls, alongside the page's swipe down, which closes the player at rest too.
    _wakePan = [[UIPanGestureRecognizer alloc] initWithTarget:self action:@selector(wake)];
    _wakePan.delegate = self;
    [_shield addGestureRecognizer:_wakePan];
    [self updateBare:YES];
    SGAddPlayerStateObserver(self);
    [self playerStateDidChange:SGPlayerState()];
    [NSNotificationCenter.defaultCenter addObserver:self selector:@selector(artworkChanged)
                                               name:SGRNowPlayingArtworkDidChangeNotification object:nil];
    [NSNotificationCenter.defaultCenter addObserver:self selector:@selector(updateClip)
                                               name:SGRPlayerMotionDidChangeNotification object:nil];
    for (NSNotificationName name in @[UIApplicationDidBecomeActiveNotification, UIApplicationWillResignActiveNotification,
                                      NSProcessInfoPowerStateDidChangeNotification]) {
        [NSNotificationCenter.defaultCenter addObserver:self selector:@selector(syncClipPlayingSoon) name:name object:nil];
    }
    [self updateClip];
    // The shield is hidden from VoiceOver, so turning it on brings the controls back and keeps them.
    [NSNotificationCenter.defaultCenter addObserver:self selector:@selector(wake)
                                               name:UIAccessibilityVoiceOverStatusDidChangeNotification object:nil];
}

- (void)dealloc {
    [NSNotificationCenter.defaultCenter removeObserver:self];
    [_rest invalidate];
    [_tick invalidate];
}

// The track's clip in, a new one, or none: the layout follows (viewDidLayoutSubviews), crossing over on the field's clock.
- (void)updateClip {
    NSURL *file = nil;
    UIImage *poster = nil;
    BOOL has = SGRPlayerMotionFile(&file, &poster) && !SGRReduceMotion();
    if (has && ![file isEqual:_clipFile]) {
        _clipFile = file;
        _clipAspect = poster.size.width > 0 ? poster.size.height / poster.size.width : 0;
        // Without a poster, square until the asset's track has loaded, off the main thread.
        if (_clipAspect <= 0) {
            _clipAspect = 1;
            __weak typeof(self) weakSelf = self;
            [[AVURLAsset assetWithURL:file] loadTracksWithMediaType:AVMediaTypeVideo completionHandler:^(NSArray<AVAssetTrack *> *tracks, NSError *error) {
                AVAssetTrack *track = tracks.firstObject;
                if (!track) return;
                CGSize size = CGSizeApplyAffineTransform(track.naturalSize, track.preferredTransform);
                if (fabs(size.width) <= 0) return;
                CGFloat aspect = fabs(size.height / size.width);
                dispatch_async(dispatch_get_main_queue(), ^{
                    typeof(self) screen = weakSelf;
                    if (!screen || ![screen->_clipFile isEqual:file]) return;
                    screen->_clipAspect = aspect;
                    [screen.view setNeedsLayout];
                });
            }];
        }
        [self.view setNeedsLayout];
        _clipPlayer = [AVQueuePlayer new];
        _clipPlayer.muted = YES;
        _clipPlayer.preventsDisplaySleepDuringVideoPlayback = NO;
        _clipLooper = [AVPlayerLooper playerLooperWithPlayer:_clipPlayer templateItem:[AVPlayerItem playerItemWithURL:file]];
        _clipLayer.player = _clipPlayer;
        [self syncClipPlaying];
    } else if (!has && _clipFile) {
        _clipFile = nil;
        [_clipPlayer pause];
        _clipPlayer = nil;
        _clipLooper = nil;
    }
    if (has == _clipped) return;
    _clipped = has;
    [self.view setNeedsLayout];
    BOOL animated = self.view.window != nil;
    void (^swap)(void) = ^{
        self->_clip.alpha = has ? 1 : 0;
        self->_clipTint.alpha = has ? 1 : 0;
        self->_field.alpha = has ? 0 : 1;
        [self.view layoutIfNeeded];
    };
    if (animated) [UIView animateWithDuration:SGRCrossfade animations:swap];
    else swap();
}

// The page's clip's checks (SystemMotion.m's updateMotion): in a window, in front, not in Low Power Mode and the song
// playing.
- (void)syncClipPlaying {
    BOOL front = UIApplication.sharedApplication.applicationState == UIApplicationStateActive;
    if (_clipPlayer && self.view.window && front && !NSProcessInfo.processInfo.lowPowerModeEnabled && !SGPlayerState().isPaused) [_clipPlayer play];
    else [_clipPlayer pause];
}

// The power state is reported off the main thread.
- (void)syncClipPlayingSoon {
    dispatch_async(dispatch_get_main_queue(), ^{ [self syncClipPlaying]; });
}

- (void)viewWillAppear:(BOOL)animated {
    [super viewWillAppear:animated];
    // Laid out again: the screen may have been made ahead at another size.
    [self.view setNeedsLayout];
    [self updateClip];
    [self syncClipPlaying];
}

- (void)viewDidDisappear:(BOOL)animated {
    [super viewDidDisappear:animated];
    // The video back to the page upright.
    for (UIView *sub in _videoHolder.subviews.copy) [sub removeFromSuperview];
    [_videoHolder removeFromSuperview];
    SGRSystemTurnVideoReturned();
    [_clipPlayer pause];
    [_tick invalidate];
    _tick = nil;
    [_scrubber letGoOfPans];
    SGRPlayerVolumeRowLetGo(_volume);
}

// The places of iOS 27.3's player as shares of the screen (the constants above), the screen being the window's bounds:
// the Music app lays its landscape player out across the whole screen, the camera's side included.
static CGRect centred(CGFloat x, CGFloat y, CGFloat width, CGFloat height) {
    return CGRectMake(round(x - width / 2), round(y - height / 2), width, height);
}

// The variable blur on the clip and its copies, by kSideBlur from the mirror line at `edge` (Core Animation's variableBlur,
// its strength read from a mask, as SystemMotion.m's variableBlur:), none before it. The mask, a point a pixel, is drawn
// again only when the line, the clip's width or the size change.
- (void)sideBlurFrom:(CGFloat)edge lead:(CGFloat)lead width:(CGFloat)width size:(CGSize)size {
    if (size.width < 1 || size.height < 1) return;
    NSString *key = [NSString stringWithFormat:@"%.0fx%.0f %.0f %.0f %.0f", size.width, size.height, edge, lead, width];
    if ([key isEqualToString:_blurKey]) return;
    _blurKey = key;
    NSMutableArray *colors = [NSMutableArray array];
    CGFloat locations[16];
    NSUInteger n = 0;
    if (lead > 0) {
        CGFloat leadStops[3][2] = {{0, kLeadBlurEdge}, {lead, kLeadBlurAtClip}, {lead + width * kLeadBlurInside, 0}};
        for (int i = 0; i < 3; i++, n++) {
            [colors addObject:(id)[UIColor colorWithWhite:0 alpha:leadStops[i][1]].CGColor];
            locations[n] = MIN(1, MAX(0, leadStops[i][0] / size.width));
        }
    }
    NSUInteger count = sizeof(kSideBlur) / sizeof(kSideBlur[0]);
    for (NSUInteger i = 0; i < count && n < 15; i++, n++) {
        [colors addObject:(id)[UIColor colorWithWhite:0 alpha:kSideBlur[i][1]].CGColor];
        locations[n] = MIN(1, MAX(0, (edge + width * kSideBlur[i][0]) / size.width));
    }
    const CGFloat *at = locations;
    UIGraphicsImageRendererFormat *format = [UIGraphicsImageRendererFormat preferredFormat];
    format.scale = 1;
    format.opaque = NO;
    UIImage *mask = [[[UIGraphicsImageRenderer alloc] initWithSize:size format:format] imageWithActions:^(UIGraphicsImageRendererContext *context) {
        CGColorSpaceRef space = CGColorSpaceCreateDeviceGray();
        CGGradientRef gradient = CGGradientCreateWithColors(space, (__bridge CFArrayRef)colors, at);
        CGContextDrawLinearGradient(context.CGContext, gradient, CGPointZero, CGPointMake(size.width, 0),
                                    kCGGradientDrawsBeforeStartLocation | kCGGradientDrawsAfterEndLocation);
        CGGradientRelease(gradient);
        CGColorSpaceRelease(space);
    }];
    id blur = [NSClassFromString(@"CAFilter") filterWithType:@"variableBlur"];
    [blur setValue:@(kBlurRadius) forKey:@"inputRadius"];
    [blur setValue:(__bridge id)mask.CGImage forKey:@"inputMaskImage"];
    [blur setValue:@YES forKey:@"inputNormalizeEdges"];
    _clip.layer.filters = blur ? @[blur] : nil;
}

- (void)viewDidLayoutSubviews {
    [super viewDidLayoutSubviews];
    CGRect bounds = self.view.bounds;
    CGFloat W = bounds.size.width, H = bounds.size.height;
    if (W <= 0 || H <= 0) return;
    _fieldDim.frame = bounds;

    // The left: the clip full height, or the cover inset on the field.
    // The clip's place: a square one full height from the leading edge, zoomed about its middle; a tall one larger,
    // a quarter of the way across. Its copies are flipped about its edges, so they meet it row for row, and a point d
    // inside an edge lands the stretch times d past it.
    BOOL tall = _clipAspect > kTallFrom;
    CGRect clipRect;
    if (tall) {
        CGFloat height = round(H * kTallHeight), width = round(height / _clipAspect);
        clipRect = CGRectMake(round(W * kTallCentre - width / 2), round(H * kTallTop), width, height);
    } else {
        CGFloat side = MIN(H, round(W * kColumnLeft)), bleed = side * (kClipZoom - 1) / 2;
        clipRect = CGRectMake(-bleed, -bleed, side + 2 * bleed, H + 2 * bleed);
    }
    CGFloat clipLeft = MAX(0, CGRectGetMinX(clipRect)), clipRight = tall ? CGRectGetMaxX(clipRect) : MIN(H, round(W * kColumnLeft));
    CGFloat clipWidth = clipRight - clipLeft;
    _clip.frame = bounds;
    [CATransaction begin];
    [CATransaction setDisableActions:YES];
    _clipCopy.frame = bounds;
    _clipLead.frame = bounds;
    _clipLayer.frame = clipRect;
    CATransform3D flip = CATransform3DMakeTranslation(-clipRight, 0, 0);
    flip = CATransform3DConcat(flip, CATransform3DMakeScale(-kClipStretch, 1, 1));
    _clipCopy.instanceTransform = CATransform3DConcat(flip, CATransform3DMakeTranslation(clipRight, 0, 0));
    _clipLead.instanceCount = clipLeft > 0 ? 2 : 1;
    CATransform3D lead = CATransform3DMakeTranslation(-clipLeft, 0, 0);
    lead = CATransform3DConcat(lead, CATransform3DMakeScale(-1, 1, 1));
    _clipLead.instanceTransform = CATransform3DConcat(lead, CATransform3DMakeTranslation(clipLeft, 0, 0));
    _clipDim.frame = bounds;
    _clipTint.frame = bounds;
    _clipTint.layer.sublayers.firstObject.frame = bounds;
    _clipTintMask.frame = bounds;
    CGFloat dimFrom = clipLeft + clipWidth * kBlurFrom;
    _clipTintMask.locations = @[@(dimFrom / W), @(MIN(1, (dimFrom + kWashDimRamp) / W))];
    _clipDim.locations = @[@(dimFrom / W), @(MIN(1, (dimFrom + kWashDimRamp) / W))];
    CGFloat count = sizeof(kSideBlur) / sizeof(kSideBlur[0]);
    if (_clipBlur) {
        _clipBlur.frame = bounds;
        _clipBlur.maskView.frame = bounds;
        _clipBlurMask.frame = bounds;
        _clipBlurMask.locations = @[@(MIN(1, (clipRight + clipWidth * kSideBlur[4][0]) / W)), @(MIN(1, (clipRight + clipWidth * kSideBlur[(int)count - 1][0]) / W))];
    } else {
        [self sideBlurFrom:clipRight lead:clipLeft width:clipWidth size:bounds.size];
    }
    [CATransaction commit];
    CGFloat side = round(H * kCoverHeight);
    CGRect coverRect = CGRectMake(round(W * kCoverLeft), round(H * kCoverTop), side, side);
    _cover.bounds = CGRectMake(0, 0, side, side);
    _cover.center = CGPointMake(CGRectGetMidX(coverRect), CGRectGetMidY(coverRect));
    // A music video in the cover's place, 16:9 across the cover's width and on its middle; the cover and the clip
    // give way to it (its owner, 2026-11-09: the sideways player showed the clip, not the video).
    // Without the lyrics or the queue up, the video fills the screen and the column fades over it, then away (its
    // owner, 2026-11-09: as the Music app and YouTube show a video sideways).
    BOOL video = _videoShown.superview == _videoHolder && _videoHolder.superview;
    BOOL full = video && [self videoFull];
    if (video) {
        CGFloat aspect = SGRSystemVideoAspect(_videoShown), videoHeight = MIN(side, round(side / aspect));
        _videoHolder.frame = full ? bounds : CGRectMake(CGRectGetMinX(coverRect), round(CGRectGetMidY(coverRect) - videoHeight / 2), side, videoHeight);
        _videoHolder.layer.cornerRadius = full ? 0 : SGRRadiusArtwork;
    }
    _videoDim.frame = bounds;
    _videoDim.hidden = !full;
    _cover.alpha = _clipped || video || _narrating ? 0 : 1;
    if (_djRing) {
        _djRing.frame = bounds;
        _djRing.ringCentre = _cover.center;
        _djRing.ringRadius = round(side * 0.27);
    }
    _fieldDim.alpha = _clipped ? 0 : 1;
    _clip.hidden = video;
    (void)coverRect;

    // The column's head: the title and the artist, ★ and ⋯, higher in the lines' view.
    CGFloat left = round(W * kColumnLeft), right = round(W * kColumnRight), width = right - left;
    CGFloat headMid = round(H * (_lyricsMode || _queueMode ? kHeadMidLines : kHeadMid));
    CGFloat titleHeight = ceil(_title.font.lineHeight), artistHeight = ceil(_artist.font.lineHeight);
    // Each of the buttons beside the star takes a step of the star's from the ⋯ off the text.
    CGFloat buttonStep = W * (kMoreCentre - kStarCentre), nextCentre = W * kStarCentre - (_star.hidden ? 0 : buttonStep);
    CGFloat switchCentre = nextCentre;
    if (!_switchVideo.hidden) nextCentre -= buttonStep;
    CGFloat djCentre = nextCentre;
    if (!_djButton.hidden) nextCentre -= buttonStep;
    CGFloat textWidth = MAX(0, nextCentre + buttonStep - kControlSide / 2 - 4 - left);
    // The block reaches kTitleFade past the text on either side, so at rest its fade lies over nothing.
    CGFloat textTop = round(headMid - (titleHeight + artistHeight) / 2);
    _titleBlock.frame = CGRectMake(left - kTitleFade, textTop, textWidth + 2 * kTitleFade, titleHeight + artistHeight);
    _title.frame = _besideTitle.frame = CGRectMake(0, 0, textWidth + kTitleFade, titleHeight);
    _artist.frame = _besideArtist.frame = CGRectMake(0, titleHeight, textWidth + kTitleFade, artistHeight);
    [CATransaction begin];
    [CATransaction setDisableActions:YES];
    _titleFade.frame = _titleBlock.bounds;
    CGFloat titleEdge = _titleBlock.bounds.size.width > 0 ? MIN(0.25, kTitleFade / _titleBlock.bounds.size.width) : 0;
    _titleFade.locations = @[@0, @(titleEdge), @(1 - titleEdge), @1];
    [CATransaction commit];
    _star.frame = centred(W * kStarCentre, headMid, kControlSide, kControlSide);
    _close.frame = centred(W * kMoreCentre, headMid, kControlSide, kControlSide);
    _switchVideo.frame = centred(switchCentre, headMid, kControlSide, kControlSide);
    _djButton.frame = centred(djCentre, headMid, kControlSide, kControlSide);
    _head.bounds = bounds;
    _head.center = CGPointMake(CGRectGetMidX(bounds), CGRectGetMidY(bounds));

    // The player's view.
    _scrubber.frame = centred(left + width / 2, H * kBarMid, width, 28);
    CGFloat timesHeight = ceil(_elapsed.font.lineHeight);
    _elapsed.frame = CGRectMake(left, round(H * kTimesTop), width / 2, timesHeight);
    _remaining.frame = CGRectMake(left + width / 2, round(H * kTimesTop), width / 2, timesHeight);
    CGFloat transportMid = H * kTransportMid;
    _controls.frame = centred(W * (kPreviousCentre + kNextCentre) / 2, transportMid, W * (kNextCentre - kPreviousCentre) + 64, 64);
    CGFloat controlsLeft = CGRectGetMinX(_controls.frame);
    _previous.frame = centred(W * kPreviousCentre - controlsLeft, 32, 56, 56);
    _play.frame = centred(W * (kPreviousCentre + kNextCentre) / 2 - controlsLeft, 32, 64, 64);
    _next.frame = centred(W * kNextCentre - controlsLeft, 32, 56, 56);
    _shuffle.frame = centred(left + 12, transportMid, 44, 44);
    _repeat.frame = centred(right - 12, transportMid, 44, 44);
    _volume.frame = centred(left + width / 2, H * kVolumeMid, width, 32);

    // The lines' view, over the column between the head and the foot.
    CGFloat linesTop = round(H * kLinesTop), linesBottom = round(H * kLinesBottom);
    // At rest the lines run on down to the foot and, with the title going too, up to the top (its owner, 2026-11-06).
    if (_resting && _lyricsMode && !_queueMode) {
        linesBottom = round(H * kLinesBottomResting);
        if (SGRLyricsHideMode() != SGRLyricsHideControls) linesTop = round(H * kLinesTopResting);
    }
    _stage.frame = CGRectMake(left - 24, linesTop, width + 48, linesBottom - linesTop);
    _lyrics.frame = _stage.bounds;
    // Laid out again when only the column moved, so a scroll by hand keeps its lines where they are (SGRKaraokeView.m).
    [_lyrics setNeedsLayout];
    // The queue runs down behind the foot to the screen's, its last track resting just above the foot (the portrait
    // page's way), so a lift that puts the foot away resizes nothing and the list never jumps.
    // It starts at the head's top, the head's room above its chips, which its scroll pushes up into as the Music app's
    // landscape queue pushes its title row out.
    CGFloat headTop = MAX(0, MIN(CGRectGetMinY(_titleBlock.frame), CGRectGetMinY(_star.frame)) - 6);
    _queue.frame = CGRectMake(left - 16, headTop, width + 32, H - headTop);
    _queue.headRoom = linesTop - headTop;
    _queue.controlsHeight = MAX(0, H - round(H * kLinesBottom));
    [_queue setControlsCover:_queueDragging ? 0 : _queue.controlsHeight animated:self.view.window != nil];

    // The foot.
    CGFloat footMid = H * kFootMid;
    _lyricsButton.frame = centred(W * kLyricsCentre, footMid, kControlSide, kControlSide);
    _lyricsDisc.center = _queueDisc.center = CGPointMake(kControlSide / 2, kControlSide / 2);
    _route.frame = centred(W * kRouteCentre, footMid, kControlSide, kControlSide);
    _routeName.frame = centred(W * kRouteCentre, H * kRouteNameMid, width * 0.5, ceil(_routeName.font.lineHeight));
    _queueButton.frame = centred(W * kQueueCentre, footMid, kControlSide, kControlSide);
    [self applyMode];
    if ([self videoFull]) [self layoutVideoPlayer];
}

// The controls a full screen video keeps, laid out as a video player's (its owner, 2026-11-10): the title and the artist
// top left, previous, play and next in the middle, the bar across the foot with the times under its ends and AirPlay
// beside it. The rest (★, ⋯, volume, shuffle, repeat, lyrics, the queue, the device's name) is out.
- (NSArray<UIView *> *)videoKept {
    return @[_title, _artist, _controls, _scrubber, _elapsed, _remaining, _route];
}

- (NSArray<UIView *> *)videoDropped {
    NSMutableArray<UIView *> *dropped = [NSMutableArray arrayWithObjects:_volume, _shuffle, _repeat, _lyricsButton, _queueButton, _routeName,
                                                                         _star, _close, _switchVideo, _djButton, nil];
    if (_optionBadge) [dropped addObject:_optionBadge];
    return dropped;
}

- (void)layoutVideoPlayer {
    CGRect bounds = self.view.bounds;
    CGFloat W = bounds.size.width, H = bounds.size.height;
    UIEdgeInsets safe = self.view.safeAreaInsets;
    CGFloat left = MAX(safe.left, 24) + 8, right = W - MAX(safe.right, 24) - 8;
    // The head, top left, across to the right edge.
    CGFloat titleHeight = ceil(_title.font.lineHeight), artistHeight = ceil(_artist.font.lineHeight);
    CGFloat top = MAX(safe.top, 20);
    CGFloat textWidth = MAX(0, right - left);
    _titleBlock.frame = CGRectMake(left - kTitleFade, top, textWidth + 2 * kTitleFade, titleHeight + artistHeight);
    _title.frame = _besideTitle.frame = CGRectMake(0, 0, textWidth + kTitleFade, titleHeight);
    _artist.frame = _besideArtist.frame = CGRectMake(0, titleHeight, textWidth + kTitleFade, artistHeight);
    [CATransaction begin];
    [CATransaction setDisableActions:YES];
    _titleFade.frame = _titleBlock.bounds;
    CGFloat titleEdge = _titleBlock.bounds.size.width > 0 ? MIN(0.25, kTitleFade / _titleBlock.bounds.size.width) : 0;
    _titleFade.locations = @[@0, @(titleEdge), @(1 - titleEdge), @1];
    [CATransaction commit];
    // Previous, play and next in the middle of the screen.
    CGFloat spread = 120;
    _controls.frame = centred(W / 2, H / 2, spread * 2 + 72, 72);
    _previous.frame = centred(36, 36, 56, 56);
    _play.frame = centred(spread + 36, 36, 72, 72);
    _next.frame = centred(spread * 2 + 36, 36, 56, 56);
    // The bar across the foot, AirPlay at its end, the times under the bar's ends.
    CGFloat barMid = H - MAX(safe.bottom, 12) - 40;
    _route.frame = centred(right - kControlSide / 2, barMid, kControlSide, kControlSide);
    CGFloat barRight = CGRectGetMinX(_route.frame) - 12;
    _scrubber.frame = CGRectMake(left, round(barMid - 14), MAX(0, barRight - left), 28);
    CGFloat timesHeight = ceil(_elapsed.font.lineHeight), timesTop = round(barMid + 12);
    _elapsed.frame = CGRectMake(left, timesTop, (barRight - left) / 2, timesHeight);
    _remaining.frame = CGRectMake(left + (barRight - left) / 2, timesTop, (barRight - left) / 2, timesHeight);
    for (UIView *view in [self videoDropped]) {
        view.alpha = 0;
        view.userInteractionEnabled = NO;
    }
}

// The player's view or the lines', as the lyrics button says: what each does not show is out, and the button is lit in
// the lines' view. Rest takes the head and the foot out besides (setControlsShown:).
- (void)applyMode {
    BOOL lines = _lyricsMode && !_bare && !_queueMode, queue = _queueMode;
    for (UIView *view in @[_scrubber, _elapsed, _remaining, _controls, _volume]) {
        view.alpha = lines || queue ? 0 : 1;
        view.userInteractionEnabled = !lines && !queue;
    }
    for (UIView *button in @[_shuffle, _repeat]) {
        BOOL off = button == _shuffle ? _shuffleOff : _repeatOff;
        button.alpha = lines || queue || off ? 0 : 1;
        button.userInteractionEnabled = !lines && !queue && !off;
    }
    _stage.alpha = lines ? 1 : 0;
    _stage.userInteractionEnabled = lines;
    _queue.alpha = queue ? 1 : 0;
    _queue.userInteractionEnabled = queue;
    [self placeHead];
    [self syncOptionBadge];
    _queueButton.glyph.tintColor = queue ? UIColor.clearColor : UIColor.whiteColor;
    _queueDisc.alpha = queue ? 1 : 0;
    _queueDisc.transform = queue ? CGAffineTransformIdentity : CGAffineTransformMakeScale(0.8, 0.8);
    _queueButton.accessibilityValue = queue ? @"Shown" : nil;
    // The page's way (SystemPlayer.m's syncLyrics): the filled glyph cut out of the disc while lit, the glyph itself
    // clear then, or it would fill the cut.
    [_lyricsButton.glyph setSymbol:lines ? @"quote.bubble.fill" : @"quote.bubble" animated:self.view.window != nil];
    _lyricsButton.glyph.tintColor = lines ? UIColor.clearColor : UIColor.whiteColor;
    _lyricsDisc.alpha = lines ? 1 : 0;
    _lyricsDisc.transform = lines ? CGAffineTransformIdentity : CGAffineTransformMakeScale(0.8, 0.8);
    // Set only on a change: the glyph button sets its own alpha with it, which would undo the rest's fade.
    if (_lyricsButton.enabled != (!_bare && !_narrating)) _lyricsButton.enabled = !_bare && !_narrating;
    _lyricsButton.accessibilityValue = lines ? @"Shown" : nil;
}

// A switch between the player, the lines and the queue: one crossfade on the layout's spring, the head moving with it,
// as it was before the switch was staged (its owner's recordings, 2026-11-06: the 12:51 build's was the smoother).
- (void)switchColumnAnimated:(BOOL)animated {
    [self setControlsShown:YES];
    void (^change)(void) = ^{
        [self.view setNeedsLayout];
        [self.view layoutIfNeeded];
    };
    if (animated && self.view.window) SGRAnimateLayout(self.view, change, nil);
    else change();
}

- (void)setLyricsMode:(BOOL)lyrics animated:(BOOL)animated {
    if (lyrics == _lyricsMode && !_queueMode && self.isViewLoaded) return;
    _lyricsMode = lyrics;
    _queueMode = NO;
    if (!self.isViewLoaded) return;
    [self switchColumnAnimated:animated];
    [self restartRest];
}

- (void)toggleLyricsMode {
    if (_narrating) return;
    [self setLyricsMode:!(_lyricsMode && !_queueMode) animated:YES];
}

// The queue in the column, in the lines' place; again, back to the player. It takes the lyrics' place for good, so the
// queue tapped again closes to the player rather than back to the lyrics (its owner, 2026-11-06). It never rests.
- (void)toggleQueueMode {
    if (_narrating && !_queueMode) return;
    [self setQueueMode:!_queueMode animated:YES];
}

- (void)setQueueMode:(BOOL)queue animated:(BOOL)animated {
    if (queue == _queueMode) return;
    _queueMode = queue;
    if (queue) _lyricsMode = NO;
    if (!self.isViewLoaded) return;
    if (_queueMode) {
        [self refreshQueue];
        [_queue scrollToTop];
    }
    [self switchColumnAnimated:animated];
    [self restartRest];
}

- (void)showingLyrics:(BOOL *)lyrics queue:(BOOL *)queue {
    *queue = _queueMode;
    *lyrics = _lyricsMode && !_queueMode && !_bare;
}

// A track lifted in the queue: the foot fades and drops away and the list takes its room, back a moment after the let go,
// as the portrait page's (SystemPlayer.m's setQueueDragging:).
- (void)setQueueDragging:(BOOL)dragging {
    if (!dragging) {
        NSUInteger token = ++_dragReturn;
        __weak SGRSystemLandscapeController *weakSelf = self;
        dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(0.45 * NSEC_PER_SEC)), dispatch_get_main_queue(), ^{
            SGRSystemLandscapeController *me = weakSelf;
            if (me && token == me->_dragReturn) [me moveFootForDrag:NO];
        });
        return;
    }
    ++_dragReturn;
    [self moveFootForDrag:YES];
}

- (void)moveFootForDrag:(BOOL)dragging {
    if (dragging == _queueDragging) return;
    _queueDragging = dragging;
    NSArray<UIView *> *foot = @[_lyricsButton, _route, _routeName, _queueButton];
    void (^fade)(void) = ^{
        for (UIView *view in foot) view.alpha = dragging ? 0 : 1;
    };
    void (^move)(void) = ^{
        CGAffineTransform away = dragging ? CGAffineTransformMakeTranslation(0, 100) : CGAffineTransformIdentity;
        for (UIView *view in foot) view.transform = away;
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
    for (UIView *view in foot) view.userInteractionEnabled = !dragging;
}

// The queue's scroll pushes the head up and out, as far as it has pushed its chips, fading as it goes; any other view
// has it in place.
- (void)pushHead:(CGFloat)push {
    _headPush = push;
    [self placeHead];
}

- (void)placeHead {
    CGFloat push = _queueMode ? _headPush : 0, room = MAX(1, _queue.headRoom);
    _head.transform = CGAffineTransformMakeTranslation(0, -push);
    _head.alpha = MIN(1, MAX(0, 1 - push / (room * 0.7))) * (_queueMode ? _queue.headShown : 1);
}

- (void)refreshQueue {
    if (!_queueMode) return;
    SPTPlayerState *state = SGPlayerState();
    NSString *from = SGRSystemContextTitle(state);
    [_queue showState:state from:from];
    id<SPTPlayer> player = (id<SPTPlayer>)SGPlayer();
    if (![player respondsToSelector:@selector(fetchQueue:on:)]) return;
    __weak SGRSystemLandscapeController *weakSelf = self;
    [player fetchQueue:^(id queue) {
        SGRSystemLandscapeController *me = weakSelf;
        NSArray *next = [queue respondsToSelector:@selector(nextTracks)] ? [(id<SPTPlayerQueue>)queue nextTracks] : nil;
        if (!me || !me->_queueMode || ![next isKindOfClass:NSArray.class]) return;
        me->_queueKey = SGRSystemQueueKey(next);
        [me->_queue showState:SGPlayerState() upcoming:next from:from];
        NSArray *own = SGRSystemHistoryTracks();
        if (own) [me->_queue showPast:own];
        else if ([queue respondsToSelector:@selector(prevTracks)]) [me->_queue showPast:[(id<SPTPlayerQueue>)queue prevTracks]];
    } on:dispatch_get_main_queue()];
}

- (BOOL)gestureRecognizer:(UIGestureRecognizer *)recognizer shouldRecognizeSimultaneouslyWithGestureRecognizer:(UIGestureRecognizer *)other {
    return recognizer == _wakePan;
}

// The title's swipe is sideways only, as the page's.
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
    return [track isKindOfClass:NSClassFromString(@"SPTPlayerTrack")] ? track : nil;
}

// Moved sideways the title and artist go with the finger and the next or previous track's come in beside them; far or
// fast enough it settles on that track and skips to it, short of that it springs back (SystemPlayer.m's titleSwiped:).
- (void)titleSwiped:(UIPanGestureRecognizer *)swipe {
    CGFloat step = _titleBlock.bounds.size.width - 2 * kTitleFade + kTitlePageGap, x = [swipe translationInView:_titleBlock].x;
    NSInteger way = x < 0 ? -1 : 1;
    SPTPlayerTrack *beside = [self trackFrom:way];
    switch (swipe.state) {
        case UIGestureRecognizerStateBegan:
            [self restartRest];
            // fall through
        case UIGestureRecognizerStateChanged: {
            _besideTitle.text = beside.trackTitle ?: @"";
            _besideArtist.text = beside.artistName ?: @"";
            _besideTitle.hidden = _besideArtist.hidden = !beside;
            [self placeTitlePagesAt:beside ? x : x / 4 way:way step:step];
            // A tick as the drag passes where letting go skips (Vibrations > Controls), as the page's.
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
            __weak SGRSystemLandscapeController *weakSelf = self;
            dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(1.2 * NSEC_PER_SEC)), dispatch_get_main_queue(), ^{
                SGRSystemLandscapeController *me = weakSelf;
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

- (void)placeTitlePagesAt:(CGFloat)offset way:(NSInteger)way step:(CGFloat)step {
    _title.transform = _artist.transform = CGAffineTransformMakeTranslation(offset, 0);
    _besideTitle.transform = _besideArtist.transform = CGAffineTransformMakeTranslation(offset - way * step, 0);
}

- (void)endTitleSkip {
    _titleSkipping = NO;
    [UIView performWithoutAnimation:^{
        self->_title.transform = self->_artist.transform = CGAffineTransformIdentity;
        self->_besideTitle.hidden = self->_besideArtist.hidden = YES;
    }];
}

// The tap to rest takes no touch that lands on a button, the queue's rows or the lines' seek.
- (BOOL)gestureRecognizer:(UIGestureRecognizer *)recognizer shouldReceiveTouch:(UITouch *)touch {
    if (recognizer != _hide) return YES;
    for (UIView *view = touch.view; view && view != self.view; view = view.superview) {
        if ([view isKindOfClass:UIControl.class] || view == _queue || view == _titleBlock) return NO;
    }
    return YES;
}

- (void)syncRouteName {
    // Only a device the sound goes to is named, as the Music app does: the phone's own speaker is not.
    _routeName.text = SGRPlayerOutputName();
    _routeName.hidden = _routeName.text.length == 0;
}

#pragma mark - the progress bar and Liked Songs

static double landscapePosition(SPTPlayerState *state) {
    if (!state) return 0;
    double position = state.isPaused ? state.positionAsOfTimestamp : state.position;
    if (!isfinite(position) || position < 0) return 0;
    return state.duration > 0 ? MIN(position, state.duration) : position;
}

static NSString *landscapeTime(double seconds) {
    NSInteger whole = isfinite(seconds) && seconds > 0 ? (NSInteger)floor(seconds) : 0;
    NSInteger hours = whole / 3600, minutes = whole / 60 % 60, rest = whole % 60;
    if (hours) return [NSString stringWithFormat:@"%ld:%02ld:%02ld", (long)hours, (long)minutes, (long)rest];
    return [NSString stringWithFormat:@"%ld:%02ld", (long)minutes, (long)rest];
}

// The page's video, taken into the holder while it plays and let go when it ends (the page then has none to lend).
- (void)adoptVideo {
    UIView *surface = SGRSystemTurnVideoSurface();
    if (surface && surface.superview != _videoHolder) {
        if (!_videoHolder) {
            _videoHolder = [UIView new];
            _videoHolder.backgroundColor = UIColor.blackColor;
            _videoHolder.clipsToBounds = YES;
            _videoHolder.layer.cornerRadius = SGRRadiusArtwork;
            _videoHolder.layer.cornerCurve = kCACornerCurveContinuous;
        }
        if (_videoHolder.superview != self.view) [self.view insertSubview:_videoHolder aboveSubview:_cover];
        if (!_videoDim) {
            _videoDim = [UIView new];
            _videoDim.backgroundColor = [UIColor colorWithWhite:0 alpha:0.5];
            _videoDim.userInteractionEnabled = NO;
        }
        if (_videoDim.superview != self.view) [self.view insertSubview:_videoDim aboveSubview:_videoHolder];
        [_videoHolder addSubview:surface];
        surface.frame = _videoHolder.bounds;
        _videoShown = surface;
        [self.view setNeedsLayout];
        [self restartRest];
    } else if (!surface && _videoHolder.superview) {
        [_videoHolder removeFromSuperview];
        [_videoDim removeFromSuperview];
        _videoShown = nil;
        if (_resting) [self setControlsShown:YES];
        [self.view setNeedsLayout];
    }
}

// While the DJ talks, its blue page and ring behind the column in place of the cover, as the portrait page shows them
// (SystemPlayer.m's showNarration:; its owner, 2026-11-10: "dj in landscape mode doesnt use the animation").
- (void)showNarration:(BOOL)on {
    if (on == _narrating) return;
    _narrating = on;
    if (on && !_djRing) {
        _djRing = [[SGRDJRingView alloc] initWithFrame:self.view.bounds];
        _djRing.alpha = 0;
        [self.view insertSubview:_djRing belowSubview:_cover];
    }
    _djRing.moving = on;
    // The lyrics and the queue closed and their buttons off while the DJ talks, as on the page.
    if (on && (_lyricsMode || _queueMode)) {
        [self setQueueMode:NO animated:YES];
        [self setLyricsMode:NO animated:YES];
    }
    _queueButton.enabled = !on;
    _lyricsButton.enabled = !on && !_bare;
    [self.view setNeedsLayout];
    SGRAnimate(SGRMotionFade, ^{
        self->_djRing.alpha = on ? 1 : 0;
        [self.view layoutIfNeeded];
    }, nil);
}

- (BOOL)videoFull {
    return _videoShown.superview == _videoHolder && _videoHolder.superview && !_lyricsMode && !_queueMode;
}

- (void)tick {
    [self adoptVideo];
    [self showNarration:SGRSystemIsNarration(SGPlayerState().track)];
    if (_scrubber.held) return;
    SPTPlayerState *state = SGPlayerState();
    // Nothing playing, or the AI DJ talking, which has no length: the bar empty and the times dashed, as the page's.
    if (!SGRSystemIsTrack(state.track) || SGRSystemIsNarration(state.track)) {
        if (!SGRSystemIsNarration(state.track) && _hadTrack) return;
        _scrubber.value = 0;
        _elapsed.text = _remaining.text = @"--:--";
        _scrubber.accessibilityValue = nil;
        return;
    }
    double duration = state.duration, position = landscapePosition(state);
    _scrubber.value = duration > 0 ? position / duration : 0;
    [self showTimesAt:position];
}

- (void)showTimesAt:(double)position {
    double duration = SGPlayerState().duration;
    _elapsed.text = landscapeTime(position);
    _remaining.text = [@"-" stringByAppendingString:landscapeTime(MAX(0, duration - position))];
    _scrubber.accessibilityValue = [NSString stringWithFormat:@"%@ of %@", landscapeTime(position), landscapeTime(duration)];
}

- (void)seekTo:(CGFloat)value {
    id<SPTPlayer> player = (id<SPTPlayer>)SGPlayer();
    double duration = SGPlayerState().duration;
    if (![player respondsToSelector:@selector(seekTo:)] || duration <= 0) return;
    [player seekTo:MIN(duration, MAX(0, value * duration))];
}

- (void)syncSaved {
    NSString *uri = SGURIString(SGPlayerState().track.URI);
    BOOL saveable = [uri hasPrefix:@"spotify:track:"];
    _star.enabled = saveable;
    _star.hidden = SGHidden(SGRKeyPlayerHideAdd);
    if (!saveable) {
        _savedWatch = nil;
        _savedTrack = nil;
        [self showSaved:NO];
        return;
    }
    if (![uri isEqualToString:_savedTrack]) {
        _savedTrack = uri;
        __weak SGRSystemLandscapeController *weakSelf = self;
        _savedWatch = SGRCollectionWatchURI([NSURL URLWithString:uri], ^{ [weakSelf syncSaved]; });
        [self showSaved:NO];
    }
    BOOL saved = NO;
    if (SGRCollectionWatchSaved(_savedWatch, &saved)) [self showSaved:saved];
}

- (void)showSaved:(BOOL)saved {
    _saved = saved;
    [_star.glyph setSymbol:saved ? @"star.fill" : @"star" animated:self.view.window != nil];
    _star.accessibilityLabel = saved ? @"Remove from Liked Songs" : @"Add to Liked Songs";
}

- (void)toggleSaved {
    if (!_savedTrack || !SGRCollectionSetSaved([NSURL URLWithString:_savedTrack], !_saved)) return;
    SGPlayFeedback(SGFeedbackAdd);
    [self showSaved:!_saved];
    [self restartRest];
}

- (void)viewDidAppear:(BOOL)animated {
    [super viewDidAppear:animated];
    [_tick invalidate];
    __weak SGRSystemLandscapeController *weakSelf = self;
    _tick = [NSTimer scheduledTimerWithTimeInterval:0.25 repeats:YES block:^(NSTimer *timer) { [weakSelf tick]; }];
    [self tick];
    [self restartRest];
    // Asked in viewWillAppear: too, where the screen is not in its window yet, so the clip stayed on its first frame (its
    // owner's recording, 2026-11-06).
    [self syncClipPlaying];
}

- (void)artworkChanged {
    NSString *identity = nil;
    UIImage *art = SGRNowPlayingArtwork(NULL, &identity);
    if (!art) return;
    // On the field's clock, so the cover and the colors behind it change as one.
    UIImageView *cover = _cover;
    [UIView transitionWithView:cover duration:SGRCrossfade options:UIViewAnimationOptionTransitionCrossDissolve
                    animations:^{ cover.image = art; } completion:nil];
    [_field setArtwork:art identity:identity animated:YES];
}

// Lines in: the lines' layout at once. None (the player's own verdict, after its grace): the cover's.
// Otherwise the layout stays, so a track change does not flash between the two. A track change alone never
// takes the lines away: the player may not have heard of it yet, and would still count the last one's grace.
- (void)updateBare:(BOOL)mayGoBare {
    BOOL bare = _bare;
    if (SGRPlayerLyricsAvailable()) bare = NO;
    else if (mayGoBare && SGRPlayerLyricsNone()) bare = YES;
    if (bare == _bare) return;
    _bare = bare;
    // The lines leave the window while they are away, so their display link stops with them.
    if (!bare) [self.view insertSubview:_stage aboveSubview:_controls];
    UIView *stage = _stage;
    void (^change)(void) = ^{
        [self.view setNeedsLayout];
        [self.view layoutIfNeeded];
    };
    void (^done)(BOOL) = ^(BOOL finished) {
        if (self->_bare) [stage removeFromSuperview];
    };
    if (self.view.window) SGRAnimateLayout(self.view, change, done);
    else {
        change();
        done(YES);
    }
    // Without lines the player's view stands in for them, and it never rests.
    if (bare) [self wake];
    else [self restartRest];
}

// Repeat is no change to the state's observers (PlayerState.x tells shuffle only), so the options are read at every report.
- (void)playerStateDidReport:(SPTPlayerState *)state {
    [self showOptions:state];
}

// Lit as the page's are, a light disc with the glyph cut out; dimmed and untouchable while Spotify does not let them
// change (SystemPlayer.m's showOptions:).
- (void)showOptions:(SPTPlayerState *)state {
    SPTPlayerOptions *options = [state respondsToSelector:@selector(options)] ? state.options : nil;
    BOOL shuffleAllowed = SGRSystemOptionAllowed(state, NO), repeatAllowed = SGRSystemOptionAllowed(state, YES);
    BOOL shuffling = shuffleAllowed && options.shufflingContext;
    BOOL track = repeatAllowed && options.repeatingTrack, context = repeatAllowed && options.repeatingContext;
    BOOL animated = self.view.window != nil;
    [_repeat.glyph setSymbol:track ? @"repeat.1" : @"repeat" animated:animated];
    [_shuffle setLit:shuffling plain:shuffleAllowed ? UIColor.whiteColor : [UIColor colorWithWhite:1 alpha:0.35] animated:animated];
    [_repeat setLit:track || context plain:repeatAllowed ? UIColor.whiteColor : [UIColor colorWithWhite:1 alpha:0.35] animated:animated];
    _shuffle.accessibilityValue = shuffling ? @"On" : @"Off";
    _repeat.accessibilityValue = track ? @"Track" : context ? @"On" : @"Off";
    [self syncOptionBadge];
}

- (void)syncOptionBadge {
    NSString *symbol = _queueMode ? nil : SGRSystemOptionBadgeSymbol(SGPlayerState(), _shuffleOff, _repeatOff);
    SGRSystemShowOptionBadge(_optionBadge, symbol, self.view.window != nil);
}

- (void)playerStateDidChange:(SPTPlayerState *)state {
    SPTPlayerTrack *track = SGRSystemIsTrack(state.track) ? state.track : nil;
    // A moment with no track between two (a new playlist loading) is not Not Playing: waited out and looked at again,
    // as the page does (SystemPlayer.m's show:).
    if (track) {
        _hadTrack = YES;
    } else if (_hadTrack) {
        if (!_emptyPending) {
            _emptyPending = YES;
            __weak typeof(self) weakSelf = self;
            dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(0.6 * NSEC_PER_SEC)), dispatch_get_main_queue(), ^{
                typeof(self) me = weakSelf;
                if (!me) return;
                me->_emptyPending = NO;
                if (SGRSystemIsTrack(SGPlayerState().track)) return;
                me->_hadTrack = NO;
                [me playerStateDidChange:SGPlayerState()];
            });
        }
        return;
    }
    // Nothing playing (no state at all at launch too): "Not Playing", the note for a cover, play rather than pause and
    // previous and next dimmed, as the page (its owner, 2026-11-09: the sideways player showed pause and 0:00).
    if (!track) {
        _cover.image = SGRSystemNotPlayingArt();
        _title.text = @"Not Playing";
        _artist.text = nil;
    }
    for (SGRSystemControlButton *skip in @[_previous, _next]) {
        skip.glyph.alpha = track ? 1 : 0.35;
        skip.userInteractionEnabled = track != nil;
    }
    if (!track) {
        [self tick];
        [_play turnToSymbol:@"play.fill" animated:self.view.window != nil];
        _play.accessibilityLabel = @"Play";
        [self showPaused:YES animated:self.view.window != nil];
        _field.motionHeld = YES;
        [self setControlsShown:YES];
        return;
    }
    // Back from Not Playing: the note gives way to the track's cover, which may not change, and so not be announced.
    if (_cover.image == SGRSystemNotPlayingArt()) [self artworkChanged];
    [self showOptions:state];
    [self updateBare:NO];
    [self syncClipPlaying];
    _title.text = state.track.trackTitle;
    _artist.text = state.track.artistName;
    // The swipe settled on this track already: the labels, which now show it, go back to the middle.
    if (_titleSkipping && ![SGURIString(state.track.URI) isEqualToString:_titleSkipFrom]) [self endTitleSkip];
    [self syncSaved];
    SGRSystemSyncRowButtons(_switchVideo, _djButton, self.view);
    [self tick];
    [_play turnToSymbol:state.isPaused ? @"play.fill" : @"pause.fill" animated:self.view.window != nil];
    _play.accessibilityLabel = state.isPaused ? @"Play" : @"Pause";
    [self showPaused:state.isPaused animated:self.view.window != nil];
    [self refreshQueue];
    _field.motionHeld = state.isPaused;
    // A pause brings the controls back and keeps them; playing again, from here or anywhere, starts the
    // clock. The tap on the play button cannot: the state saying so arrives a beat after it.
    if (state.isPaused) [self setControlsShown:YES];
    else if (!_rest && !_shield.superview) [self restartRest];
}

#pragma mark - controls

- (id<SPTPlayer>)player {
    id player = SGKaraokePlayer();
    return [player conformsToProtocol:@protocol(SPTPlayer)] || [player respondsToSelector:@selector(pause:)] ? player : nil;
}

// The symbol turns at the tap, as the page's does, rather than a beat later when the state reports.
- (void)togglePlay {
    id<SPTPlayer> player = self.player;
    BOOL resume = SGPlayerState().isPaused;
    SGPlayFeedback(resume ? SGFeedbackPlay : SGFeedbackPause);
    if (resume) [player resume:nil];
    else [player pause:nil];
    [_play turnToSymbol:resume ? @"pause.fill" : @"play.fill" animated:YES];
    _play.accessibilityLabel = resume ? @"Pause" : @"Play";
    [self restartRest];
}

- (void)previous {
    SGPlayFeedback(SGFeedbackSkip);
    [self.player skipToPreviousTrackWithOptions:nil];
    [_previous stepArrow:-1];
    [self restartRest];
}

- (void)next {
    SGPlayFeedback(SGFeedbackSkip);
    [self.player skipToNextTrackWithOptions:nil];
    [_next stepArrow:1];
    [self restartRest];
}

// The cover smaller while paused, with the page's spring (SystemPlayer.m's showPaused:); at full size under Reduce Motion.
- (void)showPaused:(BOOL)paused animated:(BOOL)animated {
    if (paused == _pausedShown && self.isViewLoaded) return;
    _pausedShown = paused;
    CGAffineTransform transform = paused && !SGRReduceMotion() ? CGAffineTransformMakeScale(kPausedScale, kPausedScale) : CGAffineTransformIdentity;
    if (!animated || SGRReduceMotion()) {
        _cover.transform = transform;
        return;
    }
    [UIView animateWithDuration:0.6 delay:0 usingSpringWithDamping:0.72 initialSpringVelocity:0
                        options:UIViewAnimationOptionBeginFromCurrentState | UIViewAnimationOptionAllowUserInteraction
                     animations:^{ self->_cover.transform = transform; } completion:nil];
}

// The ⋯ menu: the portrait page's, then the way back.
- (UIMenu *)moreMenu {
    __weak SGRSystemLandscapeController *menuSelf = self;
    UIAction *back = [UIAction actionWithTitle:@"Exit Full Screen" image:[UIImage systemImageNamed:@"arrow.down.right.and.arrow.up.left"]
                                    identifier:nil handler:^(UIAction *action) { [menuSelf turnBack]; }];
    // The portrait page's ⋯ above (SystemPlayer.m's menuItems), read afresh as it opens, then the screen's own.
    UIDeferredMenuElement *page = [UIDeferredMenuElement elementWithUncachedProvider:^(void (^completion)(NSArray<UIMenuElement *> *)) {
        SGRSystemLandscapeController *me = menuSelf;
        completion(me ? SGRSystemTurnMenuItems(me->_close, me, ^{ [menuSelf backgroundChanged]; }) : @[]);
    }];
    UIMenu *own = [UIMenu menuWithTitle:@"" image:nil identifier:nil options:UIMenuOptionsDisplayInline children:@[back]];
    return [UIMenu menuWithChildren:@[page, own]];
}

// The ⋯ switched the background: the clip follows.
- (void)backgroundChanged {
    [self updateClip];
    [self.view setNeedsLayout];
}

- (void)turnBack {
    SGRSystemTurnBack();
}

// VoiceOver's two-finger scrub.
- (BOOL)accessibilityPerformEscape {
    [self turnBack];
    return YES;
}

// The lines on their own, unless VoiceOver needs the controls to be there.
- (void)rest {
    if (((!_bare && _lyricsMode && !_queueMode) || [self videoFull]) && !UIAccessibilityIsVoiceOverRunning()) [self setControlsShown:NO];
}

- (void)wake {
    [self setControlsShown:YES];
}

- (void)setControlsShown:(BOOL)shown {
    // Already up: the clock starts over and nothing is laid out again. A second layout here, on the response's quick
    // curve, ran over a switch's spring and had it over in a few frames (its owner's recordings, 2026-11-06).
    if (shown && !_resting && !_shield.superview) {
        [_rest invalidate];
        _rest = nil;
        _hide.enabled = YES;
        [self restartRest];
        return;
    }
    [_rest invalidate];
    _rest = nil;
    _hide.enabled = shown;
    // Over a full screen video a tap anywhere brings the controls back; over the lines, a tap on them goes to them.
    _shield.passing = [self videoFull] ? nil : _stage;
    if (shown) [_shield removeFromSuperview];
    else if (!_shield.superview) {
        _shield.frame = self.view.bounds;
        [self.view addSubview:_shield];
    }
    // Back at a tap with the Kit's response, from where a fade out is; they go with the slow fade, as the
    // portrait player's do (PlayerLyrics.x).
    _resting = !shown;
    SGRAnimate(shown ? SGRMotionRespond : SGRMotionFade, ^{
        // The lines grow into the room the head and the foot leave, as the portrait page's do on their own.
        [self.view setNeedsLayout];
        [self.view layoutIfNeeded];
        // Keeping the title (Player.h), the title and the artist stay over the lines.
        NSArray<UIView *> *foot = @[self->_star, self->_close, self->_lyricsButton, self->_route, self->_routeName, self->_queueButton];
        NSArray<UIView *> *fading = SGRLyricsHideMode() == SGRLyricsHideControls ? foot
                                                                                 : [foot arrayByAddingObjectsFromArray:@[self->_title, self->_artist]];
        // A full screen video: the whole column goes, and the wash over the video with it.
        if ([self videoFull]) {
            fading = [self videoKept];
            for (UIView *view in [self videoDropped]) view.alpha = 0;
            self->_videoDim.alpha = shown ? 1 : 0;
        }
        // Back at the glyph button's own dim when it is off (the lyrics button of a track without lines).
        for (UIView *view in fading) {
            BOOL off = [view isKindOfClass:SGRGlyphButton.class] && !((SGRGlyphButton *)view).enabled;
            view.alpha = shown ? (off ? 0.35 : 1) : 0;
        }
        self->_lyrics.extrasHidden = !shown;
    }, nil);
    if (shown) [self restartRest];
}

- (void)restartRest {
    [_rest invalidate];
    _rest = nil;
    BOOL lines = !_bare && _lyricsMode && !_queueMode && SGRLyricsHideMode() != SGRLyricsHideOff;
    if (!(lines || [self videoFull]) || SGPlayerState().isPaused || UIAccessibilityIsVoiceOverRunning()) return;
    __weak SGRSystemLandscapeController *weakSelf = self;
    _rest = [NSTimer scheduledTimerWithTimeInterval:kLandscapeRest repeats:NO block:^(NSTimer *timer) {
        // A sheet over the lines (a line's meanings) keeps them up, and the clock runs again behind it.
        SGRSystemLandscapeController *strongSelf = weakSelf;
        if (strongSelf.presentedViewController) [strongSelf restartRest];
        else [strongSelf rest];
    }];
}

@end


UIViewController *SGRSystemMakeLandscape(BOOL lyrics, BOOL queue) {
    SGRSystemLandscapeController *screen = [SGRSystemLandscapeController new];
    [screen setLyricsMode:lyrics animated:NO];
    if (queue) [screen setQueueMode:YES animated:NO];
    return screen;
}

void SGRSystemLandscapeSetQueue(UIViewController *screen, BOOL queue, BOOL animated) {
    if ([screen isKindOfClass:SGRSystemLandscapeController.class]) [(SGRSystemLandscapeController *)screen setQueueMode:queue animated:animated];
}

void SGRSystemLandscapeShowing(UIViewController *screen, BOOL *lyrics, BOOL *queue) {
    if (![screen isKindOfClass:SGRSystemLandscapeController.class]) return;
    [(SGRSystemLandscapeController *)screen showingLyrics:lyrics queue:queue];
}

void SGRSystemLandscapeSetLyrics(UIViewController *screen, BOOL lyrics, BOOL animated) {
    if ([screen isKindOfClass:SGRSystemLandscapeController.class]) [(SGRSystemLandscapeController *)screen setLyricsMode:lyrics animated:animated];
}

void SGRSystemLandscapeLinesChanged(UIViewController *screen) {
    if ([screen isKindOfClass:SGRSystemLandscapeController.class]) [(SGRSystemLandscapeController *)screen updateBare:YES];
}


