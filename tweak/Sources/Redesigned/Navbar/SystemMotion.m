// Native redesign's player page (SystemPlayer.m): its Animated background, the clip drawn the way PR #192 drew the
// redesigned player's, which the redesigned player itself no longer does (Redesigned/Player/PlayerMotion.x keeps main's).
// The clip and its poster are PlayerMotion.x's (SGRPlayerMotionPreview hands them here under Native redesign); this file
// only draws them. What follows is #192's description of the drawing.
//
// Animated artwork, the track's Canvas or Apple Music's animated cover behind the player,
// the way the lock screen draws it (measured off recordings, 2026-10-22). A cover runs the width of the screen,
// starting a little way down; past each end its own edge rows, playing with it, are stretched on to the top and
// the bottom of the screen, mirrored so they meet the cover row for row, the way the lock screen carries a
// picture's folds and edges on as streaks (nothing is made up). They are copies of the cover's own layer that a
// replicator draws (CAReplicatorLayer), so they show the very frame the cover does: player layers of their own
// for them, on the same player, now and then drew a frame the cover was not on, and the seam showed as a line. Both ends blur, easing off across the cover's
// edges, with one variable Gaussian blur on the clip itself (Core Animation's variableBlur filter, its strength
// read from a mask), drawn by the render server with every frame and with no material's gray over it; a
// material (UIVisualEffectView) is kept only for an OS without the filter. A Canvas is drawn to the full height
// and only its foot is carried on and blurred, under the controls; behind the lyrics the whole clip is blurred.
// Tried and dropped: a still band (the poster's top, stretched or blurred) stood still while the clip moved; the
// whole cover mirrored over the band put a dark shape of it there; fading the cover over the band drew both at
// once, a gray stripe; and the foot dissolved into the album page's color drew no picture there at all.
// The player's square cover goes while a clip plays, so a track without one keeps its cover over Fluid
// (PlayerField.x keeps the field Fluid for this choice). The player's ⋯ menu switches between Animated
// and Fluid at once (Shared/Player/SpeedPitch.h).
//
// The clip is a subview of the field, not of the background plane: the plane's layout brings the field to
// the front on every pass, and a sibling would end up under it. Each of the field's layout passes attaches
// it (SGRPlayerMotionFieldLaidOut), so a clip that came in before the player first opened, or a field
// Spotify built again, gets it.
//
// The clip holds still when the moving field does (SGRField.m): out of a window, with the app not in front,
// while the player opens or closes, and while the song is paused. Under Reduce Motion and in Low Power Mode
// no clip plays at all: the cover stays over Fluid, as for a track without one, until both are off again.
// While a clip is showing, the Fluid field under it is held still too, and once the clip has faded in it is
// hidden (the field's covered): the field's color is what shows above the clip on the pull that dismisses.
//
// The clip is dimmed by how bright it is (SGRPlayerClipDim): three of its frames are measured as it comes in,
// so a white Canvas is drawn darker than a black one and the white text over it keeps its contrast.
//
// A track that changes while the player cannot be seen (out of a window, or with the app not in front, which a
// locked phone's player is while it stays in its window) takes the last clip away at once, without a fade, so
// the last track's clip does not greet the player as it opens.
//
// The clip and the cover cross over: the clip fades in from its first frame (the poster, under the video
// until the video has decoded one) as the cover fades out, and fades out as the cover comes back. A clip
// that has drawn no frame of its own after kGiveUp seconds on screen is given up, and the cover comes back.
// On a skip the last clip stays a moment (kHandOver), so a clip already in the store (the next track's is
// fetched ahead, SGMotionFollower) crosses over it with no cover between.
//
// Spotify's music video (Switch to video) draws in one of three of its units, each told by its video surface
// as the video comes and goes: while one shows it, the clip goes and the cover comes back, as for Fluid.
#import <AVFoundation/AVFoundation.h>
#import "Core/SGCore.h"
#import "Redesigned/Kit/SGRKit.h"
#import "Shared/AnimatedArtwork/AnimatedArtwork.h"
#import "Shared/Player/PlayerState.h"
#import "Shared/Player/SGLastTrack.h"
#import "Shared/Player/SpeedPitch.h"
#import "Redesigned/Player/Player.h"
#import "SystemPlayer.h"

// Where the blur under the controls may start at the latest, as a share of the clip's height.
static const CGFloat kFootFrom = 0.9;
// How far down a cover starts, as a share of the screen (the lock screen's, measured off recordings 2026-10-22),
// and how far into it the blur over the band above reaches before it is gone. A Canvas still starts at the top.
static const CGFloat kCoverDrop = 0.087, kTopBlurRamp = 45;
// How much the clip's reflections past its ends are stretched: the lock screen mirrors the cover at both ends and
// stretches the reflection away from the edge, about twice (its owner's unblurred photos, 2026-10-24: a mouth 110px
// tall came back 220px below the cover's foot, its blur starting just under the mouth, about 60pt above the foot).
static const CGFloat kMirrorStretch = 2;
// The variable blur's radius where it is whole, in pixels (the filter's own): the lock screen's strongest, about a
// 23px Gaussian, found by blurring its unblurred screen by known amounts until each row kept the detail its blurred
// screen keeps (Gracie Abrams, 2026-10-24). Read as a share of detail lost instead, it came out at 90-120px, and the
// foot smeared to one color. The whole radius is the top band's: three times the foot's, whose shares are a third.
static const CGFloat kVariableBlurRadius = 72;
// The scrim over a cover's band, the album page's (AlbumHeader.x) strength over a little more height: black
// this strong at the top, gone this far down, so the status bar and the header keep on a white band.
static const CGFloat kTopScrim = 180, kTopScrimAlpha = 0.28;

@interface CAFilter : NSObject
+ (instancetype)filterWithType:(NSString *)type;
@end
// A clip this much taller than wide is drawn to the window's full height and centered, cut at its sides: a Canvas
// (9:16). Apple Music's tall cover (3:4) and a square one keep their own height, the width of the screen from the
// top, as the lock screen draws them; drawn to the full height, a 3:4 cover was cut to the middle of its width.
static const CGFloat kCanvasAspect = 1.5;
// The blur starts at the seam, or this share of the screen down where that is higher, so it is under the
// controls whatever the clip's shape; it is whole kBlurRamp points below its start.
static const CGFloat kBlurByControls = 0.6, kBlurRamp = 96;
// A cover's foot blurs out instead, as the lock screen's does: from a height on the screen, not the cover's foot, since
// the lock screen's starts at the same height whatever the cover (a mouth sharp there on one, gloves soft just below
// it on another, their feet at different heights; 2026-10-24).
// Where the controls' dim is placed by, kept where it was before the blur moved down: from kFootBlurFrom, whole at
// kDimWholeAt.
static const CGFloat kFootBlurFrom = 0.57, kDimWholeAt = 0.69;
// The lock screen's blur by height on the screen, as shares of kVariableBlurRadius, calibrated the same way: none down to
// 57% of the screen, 2px at 60.7%, 6px at 62.8%, 10px at 65.9%, 14px at 69%, 17px at 75.3% and its whole from 83.7%.
// Over the band above a cover it is barely there, about 1.5px to 15% of the screen: the band reads soft because it is
// a stretched reflection, and a heavy blur there drew a flat band with a hard edge.
// Tuned by eye from there with its owner (2026-10-24): starting at 55% of the screen and growing very slowly, barely
// there until 65% (where it starts is settled), then on to the whole radius at the bottom, as the lock screen's
// reflection is a smooth wash under its controls (the calibration read too little there, the wash having no detail).
static const CGFloat kFootBlur[][2] = {{0.55, 0}, {0.6, 0.01}, {0.65, 0.03}, {0.7, 0.07}, {0.75, 0.25}, {0.8, 0.5},
                                       {0.9, 1}};
// The band above a cover, which the calibration could not read (a stretched reflection has no fine detail to lose):
// about 10px at the cover's edge, easing off over the cover's top 45pt (to kTopBlurEnd of the screen), where it starts
// and ends settled; heavier up at the status bar, where the lock screen smears the hair to blobs (2026-10-24).
static const CGFloat kTopBlurTop = 0.6, kTopBlurEdge = 0.133, kTopBlurHold = 0.108, kTopBlurHeld = 0.07, kTopBlurEnd = 0.134;
// Seconds a clip may be on screen in front without drawing a frame before it is given up.
static const NSTimeInterval kGiveUp = 5;
// The dim's floor and ceiling, and what the lyrics add to it.
static const CGFloat kDimLeast = 0.10, kDimMost = 0.80, kDimLyrics = 0.05;
// Under the lyrics and the queue, the landscape player's blur (SystemLandscape.m's kBlurRadius and kWashSaturation): a
// plain blur with the colors raised, not the system's material, which greyed the clip and darkened it (its owner,
// 2026-11-06: "washed out and dark").
static const CGFloat kLyricsBlurRadius = 72, kLyricsSaturation = 1.5;
// The dim is whole only where the text is, from where the blur under the controls is whole down; above, it eases
// off to nothing by this share of the screen below the clip's top, so the cover reads as bright as the lock screen
// draws it. Behind the lyrics, which run the whole height, it is whole throughout.
static const CGFloat kDimEaseFrom = 0.25;
// The share of the dim kept under the controls: the whole of it, worked out for small white text at 4.5:1, turned the
// clip's colors there to one dark brown, so the blurred foot showed none of the picture the lock screen shows (device,
// 2026-10-24). The title is large text, readable at less. Behind the lyrics, and with Increase Contrast, it is whole.
static const CGFloat kDimUnderControls = 0.55;
// Below the controls it goes on darkening to the bottom of the screen, as the Music app's animated artwork does: off its
// owner's screenshots of a light song (2026-11-04), about 27% black at 70% of the screen, 44% at 85% and 60% at the
// foot. These are shares of the dim worked out for the clip, at kDimFootAt of the screen and at its foot, tuned over that
// song's own animated cover until the page read as the Music app's, row for row (155 at 78%, 137 at 85%, 122 at 92%, 106
// at the foot, against its 154, 135, 115 and 96). A dark clip's dim is small, so the ramp
// barely shows there.
static const CGFloat kDimFootAt = 0.85, kDimByFoot = 0.8, kDimAtFoot = 1.6;
// The frames measured for the dim besides the poster, in seconds into the clip (one past its end is skipped).
static const double kMeasuredAt[] = {1, 2};

static CGFloat clipDim(CGFloat luminance, BOOL contrast, BOOL lyrics) {
    // White is 1, so (1 + 0.05) / (L + 0.05) >= ratio puts the clip's luminance at `most` or under.
    CGFloat ratio = contrast ? 7 : 4.5, most = 1.05 / ratio - 0.05;
    // A black layer scales the clip's encoded values, which Core Animation blends, so its linear luminance
    // goes down by about the 2.2nd power of what the layer leaves.
    CGFloat dim = luminance > most ? 1 - pow(most / luminance, 1 / 2.2) : 0;
    dim = MIN(MAX(dim, kDimLeast), kDimMost);
    return lyrics ? dim + kDimLyrics : dim;
}

// Each pixel's linear luminance, of the image drawn 16 points square, onto `into` as floats.
static void addLuminances(CGImageRef image, NSMutableData *into) {
    if (!image) return;
    enum { kSide = 16 };
    uint8_t pixels[kSide * kSide * 4];
    CGColorSpaceRef space = CGColorSpaceCreateWithName(kCGColorSpaceSRGB);
    CGContextRef context = CGBitmapContextCreate(pixels, kSide, kSide, 8, kSide * 4, space, (CGBitmapInfo)kCGImageAlphaNoneSkipLast);
    CGColorSpaceRelease(space);
    if (!context) return;
    CGContextDrawImage(context, CGRectMake(0, 0, kSide, kSide), image);
    CGContextRelease(context);
    for (int i = 0; i < kSide * kSide; i++) {
        float linear[3];
        for (int c = 0; c < 3; c++) {
            float v = pixels[i * 4 + c] / 255.0f;
            linear[c] = v <= 0.04045f ? v / 12.92f : powf((v + 0.055f) / 1.055f, 2.4f);
        }
        float luminance = 0.2126f * linear[0] + 0.7152f * linear[1] + 0.0722f * linear[2];
        [into appendBytes:&luminance length:sizeof luminance];
    }
}

// The 75th percentile of the luminances: the bright end the text has to stand out against, past a few
// highlights.
static CGFloat brightEnd(NSData *luminances) {
    NSUInteger count = luminances.length / sizeof(float);
    if (!count) return 0;
    NSMutableData *sorted = [luminances mutableCopy];
    qsort_b(sorted.mutableBytes, count, sizeof(float), ^int(const void *a, const void *b) {
        float x = *(const float *)a, y = *(const float *)b;
        return x < y ? -1 : x > y;
    });
    return ((const float *)sorted.bytes)[(count - 1) * 3 / 4];
}

@interface SGRSystemMotionView : UIView <SGPlayerStateObserver>
@property (nonatomic) CGFloat screenHeight;
// Runs when the clip has drawn nothing kGiveUp seconds after it was first on screen in front.
@property (nonatomic, copy) void (^gaveUp)(void);
- (void)playFile:(NSURL *)file poster:(UIImage *)poster;
- (void)appear:(BOOL)animated then:(void (^)(void))done;
- (void)setBlurred:(BOOL)blurred animated:(BOOL)animated;
@end

@implementation SGRSystemMotionView {
    AVQueuePlayer *_player;
    AVPlayerLooper *_looper;
    UIView *_picture;   // the clip over its foot, faded in as one
    CALayer *_still;    // the poster, with the video drawn over it
    AVPlayerLayer *_clip;
    CAGradientLayer *_seamMask;
    CAReplicatorLayer *_footCopy;   // the clip and its head again, mirrored and stretched down from its foot
    CAReplicatorLayer *_headCopy;   // the clip again, mirrored and stretched up from a cover's top edge
    CAGradientLayer *_scrim;   // over a cover's band, for the status bar and the header
    UIVisualEffectView *_topBlur;   // over the head and the top of the cover
    CAGradientLayer *_topMask;
    BOOL _variable;   // the variableBlur filter is there, so the materials stay off
    NSString *_blurKey;   // the stops the variable blur's mask was drawn for
    CAGradientLayer *_dim;   // black over the clip and its foot, as dark as the clip is bright where the text is
    NSMutableData *_luminances;   // of the frames measured so far
    BOOL _lyricsUp;
    UIVisualEffectView *_seamBlur, *_lyricsBlur;
    UIView *_lyricsWash;     // the landscape player's blur, over the clip while the lyrics or the queue are up; nil where
                             // the system has no backdrop filters, the material then
    CGFloat _aspect;
    BOOL _timing;   // the give-up's count is running
}

// What fades is the effect views' effect, never their alpha or an ancestor's: UIKit draws a blur under a
// fading alpha or a mask wrongly or not at all.
static UIBlurEffect *blurEffect(void) {
    return [UIBlurEffect effectWithStyle:UIBlurEffectStyleSystemUltraThinMaterialDark];
}

- (instancetype)initWithFrame:(CGRect)frame {
    if (!(self = [super initWithFrame:frame])) return nil;
    self.userInteractionEnabled = NO;
    self.accessibilityElementsHidden = YES;
    _picture = [[UIView alloc] initWithFrame:frame];
    [self addSubview:_picture];
    // An AVPlayerLayer draws nothing until its first frame is decoded, so the poster, the clip's first
    // frame and where the looper starts, is the contents of the layer the video draws in: there is a
    // picture from the first frame, and the video covers it exactly.
    _still = [CALayer layer];
    _still.contentsGravity = kCAGravityResizeAspectFill;
    _still.masksToBounds = YES;
    _clip = [AVPlayerLayer layer];
    _clip.videoGravity = AVLayerVideoGravityResizeAspectFill;
    [_still addSublayer:_clip];
    // Anchored at their origin, so a copy's transform is made about a point given in the picture's own terms.
    _headCopy = [CAReplicatorLayer layer];
    _headCopy.anchorPoint = CGPointZero;
    [_headCopy addSublayer:_still];
    _footCopy = [CAReplicatorLayer layer];
    _footCopy.anchorPoint = CGPointZero;
    [_footCopy addSublayer:_headCopy];
    [_picture.layer addSublayer:_footCopy];
    // The copies reach far past the field, stretched as they are; nothing past it is drawn or blurred.
    _picture.layer.masksToBounds = YES;
    _dim = [CAGradientLayer layer];
    _dim.colors = @[(id)UIColor.blackColor.CGColor, (id)UIColor.blackColor.CGColor, (id)UIColor.blackColor.CGColor, (id)UIColor.blackColor.CGColor];
    _dim.opacity = kDimLeast;
    [_picture.layer addSublayer:_dim];
    _scrim = [CAGradientLayer layer];
    _scrim.colors = @[(id)[UIColor colorWithWhite:0 alpha:kTopScrimAlpha].CGColor, (id)UIColor.clearColor.CGColor];
    [_picture.layer addSublayer:_scrim];

    _seamBlur = [[UIVisualEffectView alloc] initWithEffect:nil];
    _seamBlur.overrideUserInterfaceStyle = UIUserInterfaceStyleDark;
    UIView *mask = [UIView new];
    _seamMask = [CAGradientLayer layer];
    _seamMask.colors = @[(id)UIColor.clearColor.CGColor, (id)UIColor.blackColor.CGColor];
    [mask.layer addSublayer:_seamMask];
    _seamBlur.maskView = mask;
    [self addSubview:_seamBlur];
    _topBlur = [[UIVisualEffectView alloc] initWithEffect:nil];
    _topBlur.overrideUserInterfaceStyle = UIUserInterfaceStyleDark;
    UIView *topMask = [UIView new];
    _topMask = [CAGradientLayer layer];
    _topMask.colors = @[(id)UIColor.blackColor.CGColor, (id)UIColor.blackColor.CGColor, (id)UIColor.clearColor.CGColor];
    [topMask.layer addSublayer:_topMask];
    _topBlur.maskView = topMask;
    [self addSubview:_topBlur];
    _variable = [NSClassFromString(@"CAFilter") filterWithType:@"variableBlur"] != nil;
    _lyricsBlur = [[UIVisualEffectView alloc] initWithEffect:nil];
    _lyricsBlur.overrideUserInterfaceStyle = UIUserInterfaceStyleDark;
    [self addSubview:_lyricsBlur];
    Class backdrop = NSClassFromString(@"CABackdropLayer");
    id gaussian = [NSClassFromString(@"CAFilter") filterWithType:@"gaussianBlur"];
    id saturate = [NSClassFromString(@"CAFilter") filterWithType:@"colorSaturate"];
    if (backdrop && gaussian && saturate) {
        [gaussian setValue:@(kLyricsBlurRadius) forKey:@"inputRadius"];
        [gaussian setValue:@YES forKey:@"inputNormalizeEdges"];
        [saturate setValue:@(kLyricsSaturation) forKey:@"inputAmount"];
        _lyricsWash = [UIView new];
        _lyricsWash.userInteractionEnabled = NO;
        _lyricsWash.alpha = 0;
        CALayer *layer = [backdrop layer];
        layer.filters = @[gaussian, saturate];
        [_lyricsWash.layer addSublayer:layer];
        [self addSubview:_lyricsWash];
    }

    NSNotificationCenter *center = NSNotificationCenter.defaultCenter;
    for (NSNotificationName name in @[UIApplicationDidBecomeActiveNotification, UIApplicationWillResignActiveNotification,
                                      NSProcessInfoPowerStateDidChangeNotification, UIAccessibilityReduceMotionStatusDidChangeNotification]) {
        [center addObserver:self selector:@selector(updateMotionSoon) name:name object:nil];
    }
    [center addObserver:self selector:@selector(updateDim) name:UIAccessibilityDarkerSystemColorsStatusDidChangeNotification object:nil];
    SGRObservePlayerTransition(self, ^(id owner) { [owner updateMotion]; }, ^(id owner) { [owner updateMotion]; });
    SGAddPlayerStateObserver(self);
    return self;
}

- (void)playerStateDidChange:(SPTPlayerState *)state {
    [self updateMotion];
}

- (void)dealloc {
    [NSNotificationCenter.defaultCenter removeObserver:self];
}

- (void)setScreenHeight:(CGFloat)height {
    if (height == _screenHeight) return;
    _screenHeight = height;
    [self setNeedsLayout];
}

- (void)layoutSubviews {
    [super layoutSubviews];
    CGRect bounds = self.bounds;
    CGFloat width = bounds.size.width, total = MAX(1, bounds.size.height);
    CGFloat screen = _screenHeight > 0 ? _screenHeight : total;
    CGFloat height = round(width * _aspect);
    if (_aspect > kCanvasAspect) height = MAX(height, screen);
    CGFloat top = _aspect > kCanvasAspect ? 0 : round(screen * kCoverDrop);
    CGFloat seam = top + round(height * kFootFrom), blurFrom = MIN(seam, round(screen * kBlurByControls));
    CGFloat blurRamp = kBlurRamp;
    if (top > 0) {
        // The controls' dim is whole where the lock screen's blur is half.
        blurFrom = round(screen * kFootBlurFrom);
        blurRamp = round(screen * kDimWholeAt) - blurFrom;
    }
    _picture.frame = bounds;
    _seamBlur.frame = bounds;
    _seamBlur.maskView.frame = bounds;
    _topBlur.frame = bounds;
    _topBlur.maskView.frame = bounds;
    _topBlur.hidden = top == 0;
    _lyricsBlur.frame = bounds;
    _lyricsWash.frame = bounds;
    _lyricsWash.layer.sublayers.firstObject.frame = bounds;
    [CATransaction begin];
    [CATransaction setDisableActions:YES];
    _still.frame = CGRectMake(0, top, width, height);
    _clip.frame = _still.bounds;
    // The cover's copy above it: flipped about its top edge and stretched kMirrorStretch times away from it, a row y
    // below that edge landing kMirrorStretch * y above it. The rest of the copy is past the field.
    _footCopy.frame = bounds;
    _headCopy.frame = bounds;
    _headCopy.instanceCount = top > 0 ? 2 : 1;
    _headCopy.instanceTransform = flipAbout(top, kMirrorStretch);
    _scrim.hidden = top == 0;
    _scrim.frame = CGRectMake(0, 0, width, kTopScrim);
    _topMask.frame = bounds;
    _topMask.locations = @[@0, @(top / total), @(MIN(1, (top + kTopBlurRamp) / total))];
    // The same below, about the clip's foot, down to the bottom of the field. The copy of the head this makes lands
    // far below the field.
    CGFloat below = MAX(0, total - top - height);
    _footCopy.instanceCount = below > 0 ? 2 : 1;
    _footCopy.instanceTransform = flipAbout(top + height, kMirrorStretch);
    // On past the field's foot by twice the blur's radius: the variable blur on the clip reaches that far beyond it, where
    // the mirrored foot goes on undimmed, and pulled that light back up into the bottom of the screen (2026-11-04, over a
    // real clip: a flat 60% dim read 98 mid-screen and 132 at the foot).
    CGFloat dimmed = total + 2 * kVariableBlurRadius;
    _dim.frame = CGRectMake(0, 0, width, dimmed);
    _dim.locations = @[@((top + screen * kDimEaseFrom) / dimmed), @((blurFrom + blurRamp) / dimmed),
                       @(screen * kDimFootAt / dimmed), @(screen / dimmed)];
    _seamMask.frame = bounds;
    _seamMask.locations = @[@(MIN(1, blurFrom / total)), @(MIN(1, (blurFrom + blurRamp) / total))];
    if (_variable) {
        // At its strength down to the cover's top edge and easing off inside it, so the cover keeps nearly all its height.
        // The lock screen's, by height on the screen (kFootBlur, kTopBlur...).
        BOOL band = top > 0;
        CGFloat hold = MAX(top, round(screen * kTopBlurHold)), end = MAX(hold + 1, round(screen * kTopBlurEnd));
        CGFloat stops[12][2] = {{0, band ? kTopBlurTop : 0}, {top, band ? kTopBlurEdge : 0}, {hold, band ? kTopBlurHeld : 0}, {end, 0}};
        NSUInteger count = 4;
        for (NSUInteger i = 0; i < sizeof(kFootBlur) / sizeof(kFootBlur[0]); i++) {
            stops[count][0] = round(screen * kFootBlur[i][0]);
            stops[count][1] = kFootBlur[i][1];
            count++;
        }
        stops[count][0] = total;
        stops[count][1] = kFootBlur[sizeof(kFootBlur) / sizeof(kFootBlur[0]) - 1][1];
        count++;
        [self variableBlur:stops count:count size:bounds.size];
    }
    [CATransaction commit];
}

- (void)playFile:(NSURL *)file poster:(UIImage *)poster {
    _aspect = poster.size.height / poster.size.width;
    _still.contents = (__bridge id)poster.CGImage;
    [self setNeedsLayout];
    _player = [AVQueuePlayer new];
    _player.muted = YES;
    _player.preventsDisplaySleepDuringVideoPlayback = NO;
    _looper = [AVPlayerLooper playerLooperWithPlayer:_player templateItem:[AVPlayerItem playerItemWithURL:file]];
    _clip.player = _player;
    [self setNeedsLayout];
    [self updateMotion];
    [self measure:file poster:poster];
}

// The poster now, so the clip comes in already dimmed, and two later frames as they are read.
- (void)measure:(NSURL *)file poster:(UIImage *)poster {
    _luminances = [NSMutableData data];
    addLuminances(poster.CGImage, _luminances);
    [CATransaction begin];
    [CATransaction setDisableActions:YES];
    [self updateDim];
    [CATransaction commit];
    AVAssetImageGenerator *generator = [AVAssetImageGenerator assetImageGeneratorWithAsset:[AVURLAsset assetWithURL:file]];
    generator.appliesPreferredTrackTransform = YES;
    generator.maximumSize = CGSizeMake(64, 64);
    __weak SGRSystemMotionView *weakSelf = self;
    NSMutableData *into = _luminances;
    for (size_t i = 0; i < sizeof kMeasuredAt / sizeof *kMeasuredAt; i++) {
        [generator generateCGImageAsynchronouslyForTime:CMTimeMakeWithSeconds(kMeasuredAt[i], 600)
                                      completionHandler:^(CGImageRef image, CMTime actual, NSError *error) {
            if (!image) return;
            NSMutableData *frame = [NSMutableData data];
            addLuminances(image, frame);
            dispatch_async(dispatch_get_main_queue(), ^{
                SGRSystemMotionView *view = weakSelf;
                if (!view || view->_luminances != into) return;
                [into appendData:frame];
                [view updateDim];
            });
        }];
    }
}

- (void)updateDim {
    BOOL contrast = UIAccessibilityDarkerSystemColorsEnabled();
    CGFloat dim = clipDim(brightEnd(_luminances), contrast, _lyricsUp);
    CGFloat top = _lyricsUp ? 1 : 0;
    if (_lyricsUp || contrast) {
        _dim.opacity = (float)dim;
        _dim.colors = @[(id)[UIColor colorWithWhite:0 alpha:top].CGColor, (id)UIColor.blackColor.CGColor, (id)UIColor.blackColor.CGColor,
                        (id)UIColor.blackColor.CGColor];
        return;
    }
    // Its share under the controls, then on to the foot (kDimAtFoot), as the layer's opacity at its whole.
    CGFloat whole = MIN(1, dim * kDimAtFoot);
    _dim.opacity = (float)whole;
    CGFloat (^share)(CGFloat) = ^CGFloat(CGFloat of) { return whole > 0 ? MIN(1, dim * of / whole) : 0; };
    _dim.colors = @[(id)UIColor.clearColor.CGColor, (id)[UIColor colorWithWhite:0 alpha:share(kDimUnderControls)].CGColor,
                    (id)[UIColor colorWithWhite:0 alpha:share(kDimByFoot)].CGColor, (id)UIColor.blackColor.CGColor];
}

// The variable blur on the clip, whole where a stop says 1 and none where it says 0, eased between, each stop at a
// height in points. Its mask, drawn at a point a pixel, is drawn again only when the stops or the size change.
- (void)variableBlur:(CGFloat (*)[2])stops count:(NSUInteger)count size:(CGSize)size {
    if (size.width < 1 || size.height < 1) return;
    NSMutableString *key = [NSMutableString stringWithFormat:@"%.0fx%.0f", size.width, size.height];
    for (NSUInteger i = 0; i < count; i++) [key appendFormat:@" %.0f:%.0f", stops[i][0], stops[i][1]];
    if ([key isEqualToString:_blurKey]) return;
    _blurKey = key;
    NSMutableArray *colors = [NSMutableArray array];
    CGFloat locations[12];
    for (NSUInteger i = 0; i < count && i < 12; i++) {
        [colors addObject:(id)[UIColor colorWithWhite:0 alpha:stops[i][1]].CGColor];
        locations[i] = MIN(1, MAX(0, stops[i][0] / size.height));
    }
    const CGFloat *at = locations;   // run at once, below: a block cannot take the array itself
    UIGraphicsImageRendererFormat *format = [UIGraphicsImageRendererFormat preferredFormat];
    format.scale = 1;
    format.opaque = NO;
    UIImage *mask = [[[UIGraphicsImageRenderer alloc] initWithSize:size format:format] imageWithActions:^(UIGraphicsImageRendererContext *context) {
        CGColorSpaceRef space = CGColorSpaceCreateDeviceGray();
        CGGradientRef gradient = CGGradientCreateWithColors(space, (__bridge CFArrayRef)colors, at);
        CGContextDrawLinearGradient(context.CGContext, gradient, CGPointZero, CGPointMake(0, size.height), 0);
        CGGradientRelease(gradient);
        CGColorSpaceRelease(space);
    }];
    CAFilter *blur = [NSClassFromString(@"CAFilter") filterWithType:@"variableBlur"];
    [blur setValue:@(kVariableBlurRadius) forKey:@"inputRadius"];
    [blur setValue:(__bridge id)mask.CGImage forKey:@"inputMaskImage"];
    [blur setValue:@YES forKey:@"inputNormalizeEdges"];
    _picture.layer.filters = blur ? @[blur] : nil;
}

// A copy flipped about the row `y` and stretched `stretch` times from it, for a replicator anchored at its origin: a
// point `d` past the row lands `stretch * d` before it.
static CATransform3D flipAbout(CGFloat y, CGFloat stretch) {
    CATransform3D t = CATransform3DMakeTranslation(0, -y, 0);
    t = CATransform3DConcat(t, CATransform3DMakeScale(1, -MAX(1, stretch), 1));
    return CATransform3DConcat(t, CATransform3DMakeTranslation(0, y, 0));
}

// `done` runs once the clip is opaque, unless something cut the fade in short.
- (void)appear:(BOOL)animated then:(void (^)(void))done {
    _picture.alpha = 0;
    void (^apply)(void) = ^{
        self->_picture.alpha = 1;
        if (self->_variable) return;
        self->_seamBlur.effect = blurEffect();
        self->_topBlur.effect = blurEffect();
    };
    if (animated) {
        SGRAnimate(SGRMotionFade, apply, ^(BOOL finished) {
            if (finished) done();
        });
    } else {
        apply();
        done();
    }
}

// The clip and both blurs fade out; `done` runs once they have.
- (void)disappear:(void (^)(void))done {
    SGRAnimate(SGRMotionFade, ^{
        self->_picture.alpha = 0;
        self->_seamBlur.effect = nil;
        self->_topBlur.effect = nil;
        self->_lyricsBlur.effect = nil;
        self->_lyricsWash.alpha = 0;
    }, ^(BOOL finished) { done(); });
}

// The lyrics' blur, and their share of the dim, which a layer's own animation carries over the same fade.
- (void)setBlurred:(BOOL)blurred animated:(BOOL)animated {
    _lyricsUp = blurred;
    void (^apply)(void) = ^{
        if (self->_lyricsWash) self->_lyricsWash.alpha = blurred ? 1 : 0;
        else self->_lyricsBlur.effect = blurred ? blurEffect() : nil;
    };
    [CATransaction begin];
    [CATransaction setDisableActions:!animated];
    [CATransaction setAnimationDuration:SGRCrossfade];
    [self updateDim];
    [CATransaction commit];
    if (animated) SGRAnimate(SGRMotionFade, apply, nil);
    else apply();
}

// The power state is reported off the main thread.
- (void)updateMotionSoon {
    dispatch_async(dispatch_get_main_queue(), ^{ [self updateMotion]; });
}

// A locked phone keeps the player in its window, so being in front counts as much as being in one.
- (void)updateMotion {
    BOOL front = UIApplication.sharedApplication.applicationState == UIApplicationStateActive;
    BOOL may = self.window && !self.hidden && front && !SGRPlayerIsTransitioning() && !SGRReduceMotion() && !NSProcessInfo.processInfo.lowPowerModeEnabled
        && !SGPlayerState().isPaused;
    if (may) [_player play];
    else [_player pause];
    // A paused player still draws the clip's first frame, so the count runs whenever it is on screen in front.
    if (_player && self.window && front && !_timing && !_clip.readyForDisplay) {
        _timing = YES;
        __weak SGRSystemMotionView *weakSelf = self;
        dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(kGiveUp * NSEC_PER_SEC)), dispatch_get_main_queue(), ^{
            SGRSystemMotionView *view = weakSelf;
            if (!view) return;
            view->_timing = NO;
            // Taken off screen meanwhile, the count starts again when it is back.
            BOOL shown = view.window && UIApplication.sharedApplication.applicationState == UIApplicationStateActive;
            if (shown && !view->_clip.readyForDisplay && view.gaveUp) view.gaveUp();
        });
    }
}

- (void)didMoveToWindow {
    [super didMoveToWindow];
    [self updateMotion];
}

// Hidden counts as out of the window: the player page hides it under its landscape player.
- (void)setHidden:(BOOL)hidden {
    BOOL changed = hidden != self.hidden;
    [super setHidden:hidden];
    if (changed) [self updateMotion];
}

@end

UIView *SGRSystemMotionPreviewOf(NSURL *file, UIImage *poster) {
    SGRSystemMotionView *preview = [[SGRSystemMotionView alloc] initWithFrame:CGRectZero];
    [preview playFile:file poster:poster];
    [preview appear:NO then:^{}];
    return preview;
}
