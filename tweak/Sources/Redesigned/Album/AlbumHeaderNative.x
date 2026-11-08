// Native redesign's album page (with Native redesign off, AlbumHeader.x's): the header the Music app gives an album (iOS 26.4), the same one the playlist redesign
// gives a playlist. The cover runs full bleed across the top of the page and dissolves into the page's
// field, stretching when the page is pulled down (the Kit's SGRStretchHero); the title, the artist and the
// kind and date are centered on the bottom of that dissolve; and under them one row -- shuffle, a white Play
// capsule, and add.
//
// Tree (trees/clean/album/01.txt:39-152). The header is one element of the page's scrolling stack,
// id=CreativeWorkPlatform.Components.UI.CreativeWorkHeader, a plain UIView whose height the element framework
// measures from what it holds, down a chain of four stack views:
//
//     UIView {0, 78}                     the top inset, the status bar and the navigation bar's room
//       UIStackView                      the two groups
//         UIView 402x321                 the top group: the cover square, a spacer, and the title block --
//                                        TitleRow, and ParentRow, the artist with a facepile
//         UIView {0, 329} 402x71         the bottom group: Components.UI.MetadataRow (the kind and the date,
//                                        cells of a collection view) and the action row
//
// What the header shows is the redesign's own (the Kit's SGRHeaderInfo), not Spotify's rearranged: moving
// Spotify's stacks meant answering every pass of theirs, and the element framework measured the title for
// its own font. So Spotify's whole column is concealed and the Kit's view is drawn over the header in its
// place, reading its text off Spotify's concealed labels -- so it is in the app's language and follows
// whatever Spotify shows -- and drawing and firing Spotify's own controls. The header keeps its height, its
// fade as the page scrolls and its place in the stack.
//
// Play and shuffle are not in the header. The album page floats them over the page, pinned to the top
// trailing corner outside the scroll (01.txt:1431, :1436): they are concealed where they are, and the row
// draws them and fires them all the same.
#import <AVFoundation/AVFoundation.h>
#import <objc/message.h>
#import "Core/SGCore.h"
#import "Redesigned/Kit/SGRKit.h"
#import "Shared/AnimatedArtwork/AnimatedArtwork.h"
#import "Album.h"

// SPTNavigationControllerNavigationBarState, which every page on Spotify's stack answers (Shared/Navigation/PageTransition.x).
@interface UIViewController (SGRAlbumBarState)
- (NSInteger)preferredNavigationBarState;
- (BOOL)prefersLiquidGlassNavigationBar;
@end
// SPTPageController's address for the page, which the hosting controller answers for the page it hosts (Settings/SGPage.m).
@interface UIViewController (SGRAlbumPageURI)
- (NSURL *)spt_pageURI;
@end

// The dissolve and the scrim are the Kit's stretching hero's (SGRStretchHero.h), the playlist's numbers.
// A header whose text begins nearer the top than this is one mid load, not one to measure the hero from;
// and an artwork view narrower than this is a placeholder glyph rather than the cover.
static const CGFloat kMinHero = 120, kMinCover = 80;
// The square cover's corners with Full bleed covers off: Spotify's own (its ImageViewHolder, r=4), so the album's
// square is the playlist's, which is Spotify's square left in place.
static const CGFloat kSquareRadius = 4;

static char kHeaderKey, kCoverKey, kTitleKey, kParentKey, kMetaKey, kAddKey, kDownloadKey, kPlayKey, kShuffleKey;
static char kHeroKey, kHeroHeightKey, kHeaderHeightKey, kInfoKey, kHeaderWatchedKey, kRetryKey;
static char kExploreKey, kRowWatchedKey, kMoreKey, kPinnedMoreKey, kWideKey;

#pragma mark - moving Spotify's views

// Invisible for good. Spotify fades the header and the two floating controls by alpha as the page scrolls,
// so a redesign that answers with alpha is in a fight it loses a frame of on every scroll. `hidden` on the
// layer cannot be undone by a write to alpha, costs nothing per frame, and, unlike -[UIView setHidden:],
// tells neither KVO nor the stack views of it, which is what makes it safe on Spotify's Encore layouts; an
// empty mask holds when Spotify shows the view again with -setHidden:NO, which the playlist page does when
// Play is pressed (Playlist/PlaylistHeader.x).
static void conceal(UIView *view) {
    if (!view) return;
    if (!view.layer.hidden) view.layer.hidden = YES;
    if (!view.layer.mask) view.layer.mask = [CALayer layer];
    if (view.userInteractionEnabled) view.userInteractionEnabled = NO;
    view.accessibilityElementsHidden = YES;
}

// Drawn by nothing but not hidden: for Spotify's own column of the header, which the redesign still reads. A
// hidden collection view makes no cells, and the kind and the date are cells ("no metadata" in the harness
// with the column hidden, 2026-09-18), so the column keeps laying itself out and only its drawing goes.
static void blank(UIView *view) {
    if (!view) return;
    if (!view.layer.mask) view.layer.mask = [CALayer layer];
    if (view.userInteractionEnabled) view.userInteractionEnabled = NO;
    view.accessibilityElementsHidden = YES;
}

// The outermost view that still wraps the control exactly: the element view Spotify's layout places, so
// concealing it leaves the control itself alone to be read and fired.
static UIView *wrapperFor(UIView *control, UIView *stop) {
    UIView *wrapper = control;
    for (UIView *v = control.superview; v && v != stop; v = v.superview) {
        if (fabs(v.bounds.size.width - control.bounds.size.width) > 4) break;
        if (fabs(v.bounds.size.height - control.bounds.size.height) > 4) break;
        wrapper = v;
    }
    return wrapper;
}

// One of the two controls Spotify floats over the page. They are direct children of the page and 48pt
// across, so only the small children are searched: the wash, the tab and the navigation bar are the width
// of the page, and walking into the tab would be walking the whole list on every pass that missed.
static UIView *floatingIn(UIView *page, NSString *identifier, const void *cacheKey) {
    for (UIView *sub in page.subviews) {
        if (sub.bounds.size.width > 120) continue;
        UIView *found = SGRFindByIdentifier(sub, identifier, cacheKey);
        if (found) return found;
    }
    return nil;
}

static void setFrame(UIView *view, CGRect frame) {
    if (view && !CGRectIsEmpty(frame) && !CGRectEqualToRect(view.frame, frame)) view.frame = frame;
}

// The stack Spotify arranges the header's buttons in: the first one above `button`.
static UIView *rowOf(UIView *button, UIView *header) {
    for (UIView *v = button.superview; v && v != header; v = v.superview) {
        if ([v isKindOfClass:UIStackView.class]) return v;
    }
    return nil;
}

// Installs `laidOut` on the view's own pass once, under `key`.
static void watch(UIView *view, const void *key, void (^laidOut)(UIView *view)) {
    if (!view || objc_getAssociatedObject(view, key)) return;
    objc_setAssociatedObject(view, key, @YES, OBJC_ASSOCIATION_RETAIN_NONATOMIC);
    SGRObserveLayout(view, laidOut);
}

#pragma mark - the cover, full bleed

// The picture across the top of the page with the field showing through the bottom of it: the Kit's stretching
// hero (SGRStretchHero.h), whose bottom is masked away as the playlist's is, under a scrim for the status bar.
// Pulled down past the top, it grows upward by as much, so the picture stays one piece with the text and the
// list under it and zooms in, as the Music app's does, rather than sliding down and leaving the field showing
// above it (issue #169).
//
// Here the hero adds the cover square with Full bleed covers off, its shadow, and Apple Music's animated cover,
// which goes in the hero's masked content over the picture and so dissolves with it.
@interface SGRNativeAlbumHero : SGRStretchHero
@property (nonatomic, readonly) UIImageView *picture;
// Where Spotify lays its cover square out, in the hero's coordinates at rest. With Full bleed covers off the
// picture is drawn there instead, on the field with no scrim and no mask, until an animated cover fills the
// hero over it.
@property (nonatomic) CGRect square;
// Sideways, where the cover goes instead of Spotify's square: on the left, in the hero's coordinates at rest. Empty
// upright.
@property (nonatomic) CGRect wideSquare;
// Sideways the page rests scrolled down past the top of Spotify's header (trimTop), and Spotify fades its header by
// alpha as far as it is scrolled: the cover and the text came in half faded (device, 2026-11-08). YES keeps the
// header and the views above it, up to the list, opaque.
@property (nonatomic) BOOL keepsOpaque;
// The cover in Spotify's artwork view, and every cover it puts there afterward: the hero keeps itself
// right, rather than being handed a picture on each of the header's passes and staying empty between them.
- (void)followCover:(UIImageView *)source;
// Apple Music's animated cover over the picture, where the album has one. The same album again is a no-op.
- (void)playMotionForArtist:(NSString *)artist album:(NSString *)album;
// The square's shadow, copied off whichever layer under Spotify's concealed cover casts one (its ShadowContainer),
// so the album's square has the shadow the playlist's -- Spotify's own square -- does. Once found, a no-op.
- (void)takeShadowFrom:(UIView *)cover;
@end

@implementation SGRNativeAlbumHero {
    CALayer *_shadow;   // under the square, which clips and so cannot cast its own; beside the masked content
    __weak UIImageView *_cover;
    UIView *_extension;   // iOS 26's UIBackgroundExtensionView around the picture, nil before it
    NSString *_motionAlbum;
    AVPlayerLayer *_motion;
    AVQueuePlayer *_player;
    AVPlayerLooper *_looper;
    BOOL _motionOn;   // what the player was last asked, so a scroll's steps ask it nothing again
    BOOL _motionSeen; // whether the hero was on screen when the player was last asked
}


static void *kReadyContext = &kReadyContext;

- (instancetype)initWithFrame:(CGRect)frame {
    if (!(self = [super initWithFrame:frame])) return nil;
    self.logName = @"album";

    _picture = [[UIImageView alloc] initWithFrame:self.bounds];
    _picture.contentMode = UIViewContentModeScaleAspectFill;
    _picture.clipsToBounds = YES;
    // The cover is square and the hero runs a little taller, so a fill cut its sides: a title set edge to
    // edge on the cover lost its ends. On iOS 26 the cover stays whole at the top and the system carries its
    // bottom edge down the rest, as the Music app's album page does; before, it fills as it always did.
    Class extension = NSClassFromString(@"UIBackgroundExtensionView");
    if (extension) {
        _extension = [[extension alloc] initWithFrame:self.bounds];
        [_extension setValue:@NO forKey:@"automaticallyPlacesContentView"];
        [_extension setValue:_picture forKey:@"contentView"];
        [self.content addSubview:_extension];
    } else {
        _picture.autoresizingMask = UIViewAutoresizingFlexibleWidth | UIViewAutoresizingFlexibleHeight;
        [self.content addSubview:_picture];
    }

    // At the bottom, under the content's layer.
    _shadow = [CALayer layer];
    _shadow.hidden = YES;
    [self.layer insertSublayer:_shadow atIndex:0];

    NSNotificationCenter *center = NSNotificationCenter.defaultCenter;
    for (NSNotificationName name in @[UIApplicationDidBecomeActiveNotification, UIApplicationWillResignActiveNotification,
                                      NSProcessInfoPowerStateDidChangeNotification, UIAccessibilityReduceMotionStatusDidChangeNotification,
                                      UIAccessibilityVideoAutoplayStatusDidChangeNotification]) {
        [center addObserver:self selector:@selector(sgr_updateMotionSoon) name:name object:nil];
    }
    return self;
}

- (void)dealloc {
    [NSNotificationCenter.defaultCenter removeObserver:self];
    [self sgr_dropMotion];
}

- (void)setSquare:(CGRect)square {
    if (CGRectEqualToRect(_square, square)) return;
    _square = square;
    [self setNeedsLayout];
}

- (void)setWideSquare:(CGRect)wideSquare {
    if (CGRectEqualToRect(_wideSquare, wideSquare)) return;
    _wideSquare = wideSquare;
    [self setNeedsLayout];
}

- (void)layoutSubviews {
    // The cover is always a square, as the Music app sets it (its owner, 2026-11-08: Full bleed covers removed), and
    // an animated cover plays inside the same square: nothing is masked and there is no scrim.
    self.dissolves = NO;
    self.scrim.hidden = YES;
    [super layoutSubviews];
    [self sgr_keepOpaque];
    // Pulled down, the hero is `stretch` taller than at rest and as much lower in the header, so the square moves
    // down by the stretch with the list under it.
    CGRect at = CGRectIsEmpty(_wideSquare) ? _square : _wideSquare;
    if (self.bounds.size.height < 1 || CGRectIsEmpty(at)) return;
    CGRect square = CGRectOffset(at, 0, self.stretch);
    [CATransaction begin];
    [CATransaction setDisableActions:YES];
    UIView *holder = _extension ?: _picture;
    holder.frame = square;
    holder.layer.cornerRadius = kSquareRadius;
    holder.layer.cornerCurve = kCACornerCurveContinuous;
    holder.clipsToBounds = YES;
    if (_extension) _picture.frame = _extension.bounds;
    // A path, so the shadow is drawn from it rather than from an offscreen pass over the layer every frame.
    if (!CGSizeEqualToSize(_shadow.bounds.size, square.size))
        _shadow.shadowPath = [UIBezierPath bezierPathWithRoundedRect:(CGRect){CGPointZero, square.size} cornerRadius:kSquareRadius].CGPath;
    _shadow.frame = square;
    _shadow.hidden = NO;
    _motion.frame = square;
    _motion.cornerRadius = kSquareRadius;
    _motion.cornerCurve = kCACornerCurveContinuous;
    _motion.masksToBounds = YES;
    [CATransaction commit];
}

- (void)playMotionForArtist:(NSString *)artist album:(NSString *)album {
    NSString *key = artist.length && album.length ? [NSString stringWithFormat:@"%@\n%@", artist, album] : nil;
    if (!key || [key isEqualToString:_motionAlbum] || !SGEnabled(SGRKeyAlbumMotion)) return;
    _motionAlbum = key;
    // The player's size: at the screen's full width a square cover ran to the 1920 stream, tens of MB.
    CGFloat pixels = SGMotionPixels();
    __weak SGRNativeAlbumHero *weakSelf = self;
    // Square, in the cover's own box.
    SGMotionAlbumCover(artist, album, SGMotionSquare, pixels, ^(NSURL *file) {
        SGRNativeAlbumHero *hero = weakSelf;
        if (hero && file && [hero->_motionAlbum isEqualToString:key]) [hero showMotion:file];
    });
}

// Muted and looping, over the picture in the hero's masked content and under the scrim. The picture stays
// under it until the first frame is decoded, and only then does the clip fade in: a fade started at once was
// spent on a layer with nothing in it, and the clip cut in after it.
- (void)showMotion:(NSURL *)file {
    AVPlayerItem *item = [AVPlayerItem playerItemWithURL:file];
    _player = [AVQueuePlayer new];
    _player.muted = YES;
    _player.preventsDisplaySleepDuringVideoPlayback = NO;
    // A file on the phone: nothing to buffer against, so it starts as soon as it can.
    _player.automaticallyWaitsToMinimizeStalling = NO;
    _looper = [AVPlayerLooper playerLooperWithPlayer:_player templateItem:item];
    [self sgr_dropMotion];
    _motion = [AVPlayerLayer playerLayerWithPlayer:_player];
    _motion.videoGravity = AVLayerVideoGravityResizeAspectFill;
    _motion.zPosition = 0.5;
    _motion.opacity = 0;
    [self.content.layer addSublayer:_motion];
    [_motion addObserver:self forKeyPath:@"readyForDisplay" options:NSKeyValueObservingOptionInitial context:kReadyContext];
    _motionOn = NO;
    [self setNeedsLayout];
    [self layoutIfNeeded];
    [self sgr_updateMotion];
}

- (void)sgr_dropMotion {
    [_motion removeObserver:self forKeyPath:@"readyForDisplay" context:kReadyContext];
    [_motion removeFromSuperlayer];
    _motion = nil;
}

// The Kit watches the page's list for the pull; on the same steps, with a clip, whether the hero has left the
// screen or come back to it. A hero with no clip, which most album pages have, costs the scroll nothing more.
// Run after Spotify's own scroll handling: the list tells its observers once its delegate has been told.
- (void)sgr_keepOpaque {
    if (!self.keepsOpaque) return;
    for (UIView *v = self.superview; v && ![v isKindOfClass:UIScrollView.class]; v = v.superview) {
        if (v.alpha < 1) v.alpha = 1;
    }
}

- (void)listDidScroll {
    [self sgr_keepOpaque];
    SGRAlbumRecheckWide(self);
    if (_player && [self sgr_seen] != _motionSeen) [self sgr_updateMotion];
}

- (void)observeValueForKeyPath:(NSString *)keyPath ofObject:(id)object change:(NSDictionary *)change context:(void *)context {
    if (context != kReadyContext) {
        [super observeValueForKeyPath:keyPath ofObject:object change:change context:context];
        return;
    }
    __weak SGRNativeAlbumHero *weakSelf = self;
    dispatch_async(dispatch_get_main_queue(), ^{ [weakSelf sgr_fadeInMotion:object]; });
}

// Once, when the clip has a frame to show: over 0.2 s on a curve most of the way there at once (the Kit's response,
// an entrance being quick), on screen; at once off it.
- (void)sgr_fadeInMotion:(AVPlayerLayer *)layer {
    if (layer != _motion || !layer.readyForDisplay || layer.opacity == 1) return;
    [CATransaction begin];
    [CATransaction setDisableActions:YES];
    layer.opacity = 1;
    if (self.window) {
        CABasicAnimation *fade = [CABasicAnimation animationWithKeyPath:@"opacity"];
        fade.fromValue = @0;
        fade.toValue = @1;
        fade.duration = 0.2;
        fade.timingFunction = [CAMediaTimingFunction functionWithControlPoints:0.23 :1 :0.32 :1];
        [layer addAnimation:fade forKey:@"fade"];
    }
    [CATransaction commit];
}

// The power state is reported off the main thread.
- (void)sgr_updateMotionSoon {
    dispatch_async(dispatch_get_main_queue(), ^{ [self sgr_updateMotion]; });
}

// The clip moves under the conditions the player's does (Player/PlayerMotion.x), and only with Auto-Play
// Video Previews on; otherwise it holds its frame. Off screen it stops: an album page left on the
// navigation stack would otherwise keep decoding, and so would one scrolled down to its tracks, where the
// hero is above the top of the screen. Scrolled back, the clip goes on from the frame it stopped on.
- (BOOL)sgr_seen {
    UIWindow *window = self.window;
    return window && CGRectIntersectsRect([self convertRect:self.bounds toView:window], window.bounds);
}

- (void)sgr_updateMotion {
    BOOL front = UIApplication.sharedApplication.applicationState == UIApplicationStateActive;
    BOOL seen = _motionSeen = [self sgr_seen];
    BOOL may = seen && front && !SGRReduceMotion() && !NSProcessInfo.processInfo.lowPowerModeEnabled
            && UIAccessibilityIsVideoAutoplayEnabled();
    if (may == _motionOn) return;
    _motionOn = may;
    if (may) [_player play];
    else [_player pause];
}

- (void)didMoveToWindow {
    [super didMoveToWindow];
    [self sgr_updateMotion];
}

- (void)takeShadowFrom:(UIView *)cover {
    if (_shadow.shadowOpacity > 0) return;
    __block CALayer *found = nil;
    SGForEachView(cover, ^(UIView *v) {
        if (!found && v.layer.shadowOpacity > 0) found = v.layer;
    });
    if (!found) return;
    [CATransaction begin];
    [CATransaction setDisableActions:YES];
    _shadow.shadowColor = found.shadowColor;
    _shadow.shadowOpacity = found.shadowOpacity;
    _shadow.shadowRadius = found.shadowRadius;
    _shadow.shadowOffset = found.shadowOffset;
    [CATransaction commit];
    [self setNeedsLayout];
}

- (void)followCover:(UIImageView *)source {
    if (!source) return;
    [self takeCover:source late:NO];
    if (_cover == source) return;
    _cover = source;
    __weak SGRNativeAlbumHero *weakSelf = self;
    SGRObserveImage(source, ^(UIImageView *view) { [weakSelf takeCover:view late:YES]; });
}

// `late` is a cover that arrived after the header had laid out -- an album opened for the first time, whose
// artwork is still being fetched while the page is already on screen. The log line says once that the watch,
// and not one of the header's passes, is what filled the hero.
- (void)takeCover:(UIImageView *)source late:(BOOL)late {
    UIImage *image = source.image;
    if (!image || source.bounds.size.width < kMinCover || _picture.image == image) return;
    _picture.image = image;
    // The page's field takes its color from the same picture.
    SGRAlbumSetArtwork(self, image);
}

@end

// The image view of Spotify's artwork square: the one with the cover in it, or, before the cover has been
// fetched, the empty one it will land in, so it can be watched from the first pass.
// How far Spotify moved its own column up when the album page dropped the navigation bar: its layout guide loses the
// bar's 54pt (Shared/Navigation/PageTransition.x), so the column's top room shrinks by as much and the title, read off
// it, rose over the cover (screenshot of 2026-11-08). The deepest top room seen at this width is the page's with the
// bar, so the drop is that less the room now; the cover, the text and the header's height are kept where they were.
static char kSpacerKey, kDropTitleKey;
static CGFloat columnDrop(UIView *header) {
    // Read off Spotify's title row, which is what rose (54pt, the cover square staying where it was: screenshots of
    // 2026-11-08), not off the column's top room, which did not change.
    UIView *title = SGRFindByIdentifier(header, @"CreativeWorkPlatform.Components.UI.TitleRow", &kDropTitleKey);
    if (!title.window) return 0;
    CGFloat width = header.bounds.size.width, room = [title convertRect:title.bounds toView:header].origin.y;
    // Per width, so turning the phone and back finds the upright one again (the title rose over the cover after a turn:
    // recording of 2026-11-08).
    NSMutableDictionary<NSNumber *, NSNumber *> *kept = objc_getAssociatedObject(header, &kSpacerKey);
    if (!kept) {
        kept = [NSMutableDictionary dictionary];
        objc_setAssociatedObject(header, &kSpacerKey, kept, OBJC_ASSOCIATION_RETAIN_NONATOMIC);
    }
    NSNumber *key = @(round(width));
    CGFloat deepest = MAX(kept[key].doubleValue, room);
    kept[key] = @(deepest);
    return MAX(0, deepest - room);
}

static CGRect uprightCover(UIView *header);

static UIImageView *coverImageIn(UIView *cover) {
    __block UIImageView *found = nil, *empty = nil;
    SGForEachView(cover, ^(UIView *v) {
        if (found || ![v isKindOfClass:UIImageView.class]) return;
        UIImageView *image = (UIImageView *)v;
        if (image.bounds.size.width < kMinCover) return;
        if (image.image) found = image;
        else if (!empty) empty = image;
    });
    return found ?: empty;
}

// The picture runs from the top of the header down past where its text begins, so the title and the artist
// sit on the bottom of its dissolve; the dissolve is a mask, so what shows through it is the page's field at
// that height, whatever color it is there, pulled down or not, and there is no seam to see.
//
// `bottom` is taken from the header at rest, never from where it is mid scroll, and only ever grows: a header
// still loading is shorter than it will end up, and once the cover and the artist are in it settles and the
// picture does not change size again.
static void applyHero(UIView *header, UIView *cover, CGFloat bottom, CGRect wide) {
    SGRNativeAlbumHero *hero = objc_getAssociatedObject(header, &kHeroKey);
    if (!hero) {
        hero = [[SGRNativeAlbumHero alloc] initWithFrame:CGRectZero];
        objc_setAssociatedObject(header, &kHeroKey, hero, OBJC_ASSOCIATION_RETAIN_NONATOMIC);
    }
    if (hero.superview != header) [header insertSubview:hero atIndex:0];
    else if (header.subviews.firstObject != hero) [header sendSubviewToBack:hero];

    CGFloat height = [objc_getAssociatedObject(hero, &kHeroHeightKey) doubleValue];
    if (bottom > height + 0.5) {
        height = round(bottom);
        objc_setAssociatedObject(hero, &kHeroHeightKey, @(height), OBJC_ASSOCIATION_RETAIN_NONATOMIC);
    }
    if (height < kMinHero) return;
    hero.restHeight = height;
    [hero sgr_place];
    // Spotify's square at full size, in the header's coordinates, which are the hero's: grow-only like the height,
    // so the square stays put while the header fades and collapses. Its bottom too, since the cover can reach its
    // full size before the header's top inset is in.
    hero.wideSquare = wide;
    // The Music app's header does not fade as the page scrolls, upright or sideways (its owner's recordings, 2026-11-08).
    hero.keepsOpaque = YES;
    // Upright only: sideways Spotify lays its square out at another size, and the hero keeps the upright one for
    // when the phone turns back.
    if (CGRectIsEmpty(wide)) {
        CGRect own = uprightCover(header);
        if (!CGRectIsEmpty(own)) {
            if (!CGRectEqualToRect(hero.square, own)) hero.square = own;
        } else {
            CGRect square = [cover convertRect:cover.bounds toView:header];
            if (square.size.width >= kMinCover && (square.size.width > hero.square.size.width + 0.5
                                                   || CGRectGetMaxY(square) > CGRectGetMaxY(hero.square) + 0.5)) hero.square = square;
        }
        [hero takeShadowFrom:cover];
    }
    [hero followCover:coverImageIn(cover)];
    conceal(cover);
}

#pragma mark - what the header shows

static NSString *trimmed(NSString *text) {
    NSString *clean = [text stringByTrimmingCharactersInSet:NSCharacterSet.whitespaceAndNewlineCharacterSet];
    return clean.length ? clean : nil;
}

// The first label under `root` with more than a letter in it: the facepile's initials are labels of their own.
static NSString *firstText(UIView *root) {
    __block NSString *found = nil;
    SGForEachView(root, ^(UIView *v) {
        if (found || ![v isKindOfClass:UILabel.class]) return;
        NSString *text = trimmed(((UILabel *)v).text);
        if (text.length > 1) found = text;
    });
    return found;
}

// The kind and the date ("Album • 31. 1. 2025", "Single • 2024") are cells of a collection view, a label each;
// read in the order they are drawn in.
static NSString *metadataText(UIView *metadata) {
    NSMutableArray<UILabel *> *labels = [NSMutableArray array];
    SGForEachView(metadata, ^(UIView *v) {
        if ([v isKindOfClass:UILabel.class] && trimmed(((UILabel *)v).text) && v.window) [labels addObject:(UILabel *)v];
    });
    [labels sortUsingComparator:^NSComparisonResult(UILabel *a, UILabel *b) {
        CGFloat ax = [a convertPoint:CGPointZero toView:metadata].x, bx = [b convertPoint:CGPointZero toView:metadata].x;
        return ax < bx ? NSOrderedAscending : (ax > bx ? NSOrderedDescending : NSOrderedSame);
    }];
    NSMutableArray<NSString *> *parts = [NSMutableArray array];
    for (UILabel *label in labels) [parts addObject:trimmed(label.text)];
    return parts.count ? [parts componentsJoinedByString:@" "] : nil;
}

static void applyHeader(UIView *header, UIView *page);

#pragma mark - sideways

// The Music app's album page in landscape (its owner's recording, 2026-11-08): a cover kWideCover square at the top
// left, kWideInset in from the safe area, the text and the row kWideGap to its right, the songs kWideBelow under it.
static const CGFloat kWideCover = 200, kWideTop = 42, kWideInset = 32, kWideGap = 32, kWideBelow = 36;
// Upright, the title's top under the cover's bottom: the gap Spotify's own layout leaves (the dump of 2026-11-08: the
// square ending at 324, the title at 340).
static const CGFloat kTitleUnderCover = 16;
// Spotify's songs column sideways on the 16 Pro Max: 672pt, centred (the dump of 2026-11-08).
static const CGFloat kWideColumn = 672;

// The scroll view the page's header and list scroll in: the nearest above the header.
static UIScrollView *listAbove(UIView *header) {
    for (UIView *v = header.superview; v; v = v.superview) {
        if ([v isKindOfClass:UIScrollView.class]) return (UIScrollView *)v;
    }
    return nil;
}

// Where the header's top is on screen with the page at rest, Spotify resting it at an offset of 0 (the dump of
// 2026-11-08): the list's own top in the window and the header's place in its content, neither of which moves as the
// page scrolls, loads or bounces. Read from where the header was on screen at the time, the cover opened against the
// top edge and dropped into place a moment later (recording of 2026-11-08).
static CGFloat headerRestTop(UIView *header) {
    UIScrollView *list = listAbove(header);
    if (!list || !list.superview) return [header convertPoint:CGPointZero toView:nil].y;
    CGFloat listTop = [list.superview convertPoint:list.frame.origin toView:nil].y;
    CGFloat inContent = [header convertPoint:CGPointZero toView:list].y;
    return listTop + inContent - list.contentInset.top;
}

// Where the cover goes sideways, in the header's coordinates: kWideTop below the top of the screen with the page at
// rest, wherever Spotify rests the header (device, 2026-11-08: 86pt below the screen's top sideways). Read from where
// the header is now and how far the page is scrolled, so a scroll does not move it; nothing here moves the header, so
// nothing reads back what it set. Empty upright.
static CGRect wideCover(UIView *header, UIView *page) {
    UIWindow *window = header.window;
    if (!window || window.bounds.size.width <= window.bounds.size.height) return CGRectZero;
    UIEdgeInsets safe = window.safeAreaInsets;
    // In line with the songs, whose text starts SGRSideMargin into Spotify's column (its owner, 2026-11-08); before a
    // row has been laid out, kWideInset in from the safe area.
    CGFloat x = round(MAX(MAX(safe.left, safe.right), SGRSideMargin) + kWideInset), left, right;
    // The width the header will have sideways, between the safe areas. Until it has it (mid-turn, the first pass
    // sideways), the songs' column is still the upright one and put the cover at 16 before it jumped to 96 (the dump of
    // 2026-11-08), so the cover goes where the column will be: Spotify's 672pt reading width centred in that width.
    CGFloat wideWidth = window.bounds.size.width - safe.left - safe.right;
    if (fabs(header.bounds.size.width - wideWidth) > 1) x = round(MAX(0, (wideWidth - kWideColumn) / 2) + SGRSideMargin);
    else if (SGRAlbumListColumn(page, &left, &right)) x = round([page convertPoint:CGPointMake(left, 0) toView:header].x + SGRSideMargin);
    CGFloat side = MIN(kWideCover, window.bounds.size.height - kWideTop - kWideBelow - 100);
    if (side < kMinCover) return CGRectZero;
    return CGRectMake(x, MAX(0, round(kWideTop - headerRestTop(header))), side, side);
}

// Upright, the cover's own place, measured from the screen as the sideways one is: kUprightGap under the status bar
// and kUprightShare of the header's width, centred -- where Spotify's square sits on an album opened upright with its
// navigation bar (the dump of 2026-11-08: {96, 76, 248, 248} in 440). Following Spotify's square instead, an album
// opened sideways and turned upright took the one Spotify lays out with the bar gone, smaller and up in the status
// bar (recording of 2026-11-08). Empty sideways or before the header is in a window.
static const CGFloat kUprightGap = 14, kUprightShare = 248.0 / 440.0;
// The app's window, for a header not in it yet: an album page's first passes come before the push puts it on screen,
// and with no window the cover fell back to Spotify's larger square and the page slid up as it opened (recording of
// 2026-11-08).
static UIWindow *appWindow(void) {
    for (UIScene *scene in UIApplication.sharedApplication.connectedScenes) {
        if (![scene isKindOfClass:UIWindowScene.class]) continue;
        for (UIWindow *w in ((UIWindowScene *)scene).windows) if (w.isKeyWindow) return w;
    }
    return nil;
}

static CGRect uprightCover(UIView *header) {
    UIWindow *window = header.window ?: appWindow();
    if (!window || window.bounds.size.width > window.bounds.size.height) return CGRectZero;
    CGFloat width = header.bounds.size.width;
    if (width < 200) return CGRectZero;
    CGFloat side = round(width * kUprightShare);
    return CGRectMake(round((width - side) / 2), round(window.safeAreaInsets.top + kUprightGap - headerRestTop(header)), side, side);
}

// Spotify's header is as tall sideways as upright, far taller than the cover and the text beside it. It is the first
// arranged view of the stack the page scrolls (CreativeWorkPlatform.Header, the songs' tab view under it: the dump of
// 2026-11-08), so its element view is held to end kWideBelow under the cover with a height constraint, sideways only;
// Spotify's own column inside it is blanked, so what no longer fits draws nothing. Upright the constraint is off.
static char kWideHeightKey;
static void sizeHeader(UIView *header, CGFloat height) {
    UIView *element = header.superview;
    if (![element.accessibilityIdentifier isEqualToString:@"CreativeWorkPlatform.Header"]) return;
    NSLayoutConstraint *held = objc_getAssociatedObject(element, &kWideHeightKey);
    if (height < 1) {
        if (held.active) {
            held.active = NO;
        }
        return;
    }
    if (!held) {
        held = [element.heightAnchor constraintEqualToConstant:height];
        objc_setAssociatedObject(element, &kWideHeightKey, held, OBJC_ASSOCIATION_RETAIN_NONATOMIC);
    }
    if (held.active && fabs(held.constant - height) < 0.5) return;
    held.constant = round(height);
    held.active = YES;
}

// The top of the page as it scrolls (its owner, 2026-11-08): the Music app's -- iOS's soft fade across the status bar
// alone (the hard edge read as a bar), with the back button and ⋯ floating apart and no bar. The bar is what reached the edge 116pt
// down, a header across the top with the title in it, so the album page asks Spotify for none (SGRAlbumBar below)
// and pins its own back button. Sideways, no edge at all, as the Music app has. On every scroll view the page sits in.
// The fade reaches a little below the status bar, and the cover's top sits just under it at rest, so it caught the art's
// top edge (its owner, 2026-11-08): it is off until the cover's top has risen to the status bar's bottom, from where the
// art goes under the fade as everything else does.
static void shapeTopEdge(UIView *header, BOOL wide) {
    if (@available(iOS 26.0, *)) {
        BOOL off = wide;
        SGRNativeAlbumHero *hero = objc_getAssociatedObject(header, &kHeroKey);
        UIWindow *window = header.window;
        if (!off && hero && window && !CGRectIsEmpty(hero.square))
            off = CGRectGetMinY([header convertRect:hero.square toView:nil]) > window.safeAreaInsets.top + 0.5;
        for (UIView *v = listAbove(header); v; v = v.superview) {
            if (![v isKindOfClass:UIScrollView.class]) continue;
            UIScrollView *scroll = (UIScrollView *)v;
            if (scroll.topEdgeEffect.hidden != off) scroll.topEdgeEffect.hidden = off;
        }
    }
}

// The Kit's view over the whole header, its content on the header's bottom edge; Spotify's own column goes.
static SGRHeaderInfo *applyInfo(UIView *header, UIView *page, CGRect wide, NSString **artist, NSString **album) {
    SGRHeaderInfo *info = objc_getAssociatedObject(header, &kInfoKey);
    if (!info) {
        info = [[SGRHeaderInfo alloc] initWithFrame:CGRectZero];
        objc_setAssociatedObject(header, &kInfoKey, info, OBJC_ASSOCIATION_RETAIN_NONATOMIC);
    }
    if (info.superview != header) [header addSubview:info];
    else if (header.subviews.lastObject != info) [header bringSubviewToFront:info];
    SGRNativeAlbumHero *hero = objc_getAssociatedObject(header, &kHeroKey);
    for (UIView *sub in header.subviews) {
        if (sub != info && sub != hero) blank(sub);
    }
    // Sideways the title, the artist and the row go beside the cover on the right, their bottom on its bottom and
    // set from the left, as the Music app sets an album in landscape (its owner's recording, 2026-11-08).
    info.leading = !CGRectIsEmpty(wide);
    if (info.leading) {
        // To the right edge of the songs' column, as far in as the cover is on the left.
        CGFloat x = CGRectGetMaxX(wide) + kWideGap, left, right = header.bounds.size.width - CGRectGetMinX(wide) + SGRSideMargin;
        if (SGRAlbumListColumn(page, &left, &right)) right = [page convertPoint:CGPointMake(right, 0) toView:header].x;
        setFrame(info, CGRectMake(x, CGRectGetMinY(wide), MAX(0, right - SGRSideMargin - x), wide.size.height + SGRHeaderInfoBottom));
        if (info.pinnedTop != 0) {
            info.pinnedTop = 0;
            [info setNeedsLayout];
        }
    } else {
        setFrame(info, header.bounds);
    }

    UIView *title = SGRFindByIdentifier(header, @"CreativeWorkPlatform.Components.UI.TitleRow", &kTitleKey);
    // Spotify's header grows and shrinks as its Play turns to Pause (issue #25), its title row does not. Once the cover
    // is placed, the title goes kTitleUnderCover under it instead: Spotify's row rises with the navigation bar gone and
    // is caught mid-move after a turn, so read off it the title sat over the cover a moment and then jumped back down
    // (recording of 2026-11-08).
    SGRNativeAlbumHero *placed = objc_getAssociatedObject(header, &kHeroKey);
    // Before the hero has its square (the page's first pass, the text laid out ahead of the picture), Spotify's own
    // cover square, where the hero will take it from: read off the title row instead the text opened 25pt high and slid
    // down (recording of 2026-11-08).
    CGRect under = uprightCover(header);
    if (CGRectIsEmpty(under) && placed) under = placed.square;
    if (CGRectIsEmpty(under)) {
        UIView *cover = SGRFindByIdentifier(header, @"CreativeWorkPlatform.Components.UI.ArtWorkElement.WithCoverArt", &kCoverKey);
        CGRect spotify = cover.window ? [cover convertRect:cover.bounds toView:header] : CGRectZero;
        if (spotify.size.width >= kMinCover) under = spotify;
    }
    if (!info.leading && !CGRectIsEmpty(under)) {
        CGFloat top = round(CGRectGetMaxY(under) + kTitleUnderCover);
        if (fabs(top - info.pinnedTop) > 0.5) {
            info.pinnedTop = top;
            [info setNeedsLayout];
        }
    } else if (title.window && !info.leading) {
        CGFloat top = [title convertRect:title.bounds toView:header].origin.y + columnDrop(header);
        if (fabs(top - info.pinnedTop) > 0.5) {
            info.pinnedTop = top;
            [info setNeedsLayout];
        }
    }
    UIView *parent = SGRFindByIdentifier(header, @"CreativeWorkPlatform.Components.UI.ParentRow", &kParentKey);
    UIView *metadata = SGRFindByIdentifier(header, @"Components.UI.MetadataRow", &kMetaKey);
    NSString *length = metadataText(metadata), *line = firstText(parent);
    *album = firstText(title);
    *artist = line ?: trimmed(parent.accessibilityLabel);
    [info showTitle:*album creator:*artist length:length about:nil];
    // The line as it reads, without the accessibility label to fall back on: no line, no row loses its artist.
    SGRAlbumSetArtist(page, line);
    // The kind and the date are cells the metadata row's collection view makes on its own pass, after the
    // header's, and nothing lays the header out again when they arrive; the collection is Spotify's own Swift
    // class, which cannot be watched. So an empty row is read again a moment later, a few times at most.
    NSInteger tries = [objc_getAssociatedObject(header, &kRetryKey) integerValue];
    if (!length && metadata && tries < 6) {
        objc_setAssociatedObject(header, &kRetryKey, @(tries + 1), OBJC_ASSOCIATION_RETAIN_NONATOMIC);
        __weak UIView *weakHeader = header, *weakPage = page;
        dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(0.25 * NSEC_PER_SEC)), dispatch_get_main_queue(), ^{
            if (weakHeader && weakPage) applyHeader(weakHeader, weakPage);
        });
    }

    // The artist under the title, opened from the line that names them. ParentRow is one control for the
    // whole line however many artists are on the album, so several of them open Spotify's own picker
    // (issue #56).
    [info showCreatorLink:parent];
    // And the artist's picture before the name, the one Spotify draws at the start of the row.
    [info showCreatorPicture:SGRCreatorPicture(parent)];

    // More, pinned over the page rather than left in the header, which is blanked and scrolls away.
    SGRPinnedMore(page, &kPinnedMoreKey, SGRFindByIdentifier(header, @"Components.UI.ContextMenuButton*", &kMoreKey));

    UIView *play = floatingIn(page, @"header-play-button", &kPlayKey);
    UIView *shuffle = floatingIn(page, @"Components.UI.ShuffleButton", &kShuffleKey);
    UIView *add = SGRFindByIdentifier(header, @"Components.UI.AddToButton", &kAddKey);
    UIView *download = add ? nil : SGRFindByIdentifier(header, @"DownloadButton.Granular*", &kDownloadKey);
    [info showShuffle:shuffle play:play trailing:add ?: download
     trailingFallback:[UIImage systemImageNamed:add ? @"plus" : @"arrow.down"] playColor:SGRAlbumFieldColor(header)];
    // Only what the two floating buttons draw goes: a concealed layer still sends the actions the row fires.
    if (play) conceal(wrapperFor(play, page));
    if (shuffle) conceal(wrapperFor(shuffle, page));

    // Add arrives after the header has laid out on an album opened for the first time (the next time its state
    // is cached and it is there from the start), in a row that lays nothing else out (Native/Album/Album.x): the
    // row drew download on Play's right, or nothing, until the page was opened again (issue #19). So the row's
    // own pass is watched, a plain UIStackView, as the artist page's is, found from whichever of Spotify's
    // buttons is in it already.
    UIView *inRow = add ?: download ?: SGRFindByIdentifier(header, @"Components.UI.WatchFeedEntityExplorerButton", &kExploreKey);
    __weak UIView *weakHeader = header, *weakPage = page;
    watch(rowOf(inRow, header), &kRowWatchedKey, ^(UIView *view) {
        if (weakHeader && weakPage) applyHeader(weakHeader, weakPage);
    });

    return info;
}

#pragma mark - the header's pass

// Drawn by nothing, whatever Spotify does to it: an empty mask. Spotify switches the navigation bar's
// gradient on and off with -setHidden:, which writes the layer's own hidden and so undoes conceal(); and
// it fades both gradients by alpha. Neither touches a mask.
static void maskOut(UIView *view) {
    if (!view || view.layer.mask) return;
    view.layer.mask = [CALayer layer];
    view.accessibilityElementsHidden = YES;
}

// The color Spotify painted the wash in: the first opaque color of the gradient layer it draws with,
// whether that is the view's own layer or one under it. nil when it draws some other way, or has
// no color yet.
static UIColor *washColorOf(UIView *gradient) {
    NSMutableArray<CALayer *> *layers = [NSMutableArray arrayWithObject:gradient.layer];
    [layers addObjectsFromArray:gradient.layer.sublayers ?: @[]];
    for (CALayer *layer in layers) {
        if (![layer isKindOfClass:CAGradientLayer.class]) continue;
        for (id value in ((CAGradientLayer *)layer).colors) {
            CGColorRef cg = (__bridge CGColorRef)value;
            if (CFGetTypeID(cg) != CGColorGetTypeID() || CGColorGetAlpha(cg) < 0.5) continue;
            // The page's base surface is what a wash is before Spotify has a color for it, not a color.
            if (SGIsBaseSurface(cg)) return nil;
            return [UIColor colorWithCGColor:cg];
        }
    }
    return nil;
}

// Spotify's color wash behind the header goes, so the page's field shows through, and the color it was
// painted in goes to the field, to show until the cover's own main color has been read.
//
// The navigation bar's gradient goes too. Hidden at rest, it is shown as the page scrolls under the
// title, and over the field it was a flat dark band across the top (device, 2026-09-18). What keeps the
// title legible over the list is the soft top edge every redesigned page has (SGREdgeEffect.x), as it is
// on Home, Search and Library.
static char kNoBarKey, kPinnedBackKey;
static UIViewController *hostedOf(UIView *page) {
    for (UIResponder *r = page.nextResponder; r; r = r.nextResponder) {
        if (![r isKindOfClass:UIViewController.class]) continue;
        UIViewController *vc = (UIViewController *)r;
        if ([vc.parentViewController isKindOfClass:UINavigationController.class]) return vc;
    }
    return nil;
}

// No navigation bar over an album page: its controller in Spotify's stack is marked, answers Spotify's two questions
// as a page that wants none (SGRAlbumBar), and the bar goes now if the page is on top; Spotify asks again on every
// transition, so coming back to the album hides it and leaving shows it for the next page. The back button is pinned.
// The no-bar answers on whatever class the page's controller turns out to be: the album's is the one hooked at launch,
// and the artist page kept its bar -- "Lane 8" centred at the top as it scrolled (recording of 2026-11-08) -- so any
// other is given the same two answers here, once per class, wrapping its own.
static NSMutableSet<Class> *sgr_barHooked;
BOOL SGRAlbumWantsNoBar(UIViewController *hosted);
static void hookBarState(Class cls) {
    if (!cls) return;
    if (!sgr_barHooked) sgr_barHooked = [NSMutableSet set];
    for (Class c = cls; c; c = class_getSuperclass(c)) if ([sgr_barHooked containsObject:c]) return;
    [sgr_barHooked addObject:cls];
    SEL state = @selector(preferredNavigationBarState), glass = @selector(prefersLiquidGlassNavigationBar);
    if ([cls instancesRespondToSelector:state]) {
        NSInteger (*orig)(id, SEL) = (NSInteger (*)(id, SEL))class_getMethodImplementation(cls, state);
        IMP mine = imp_implementationWithBlock(^NSInteger(id me) { return SGRAlbumWantsNoBar(me) ? 2 : orig(me, state); });
        class_replaceMethod(cls, state, mine, method_getTypeEncoding(class_getInstanceMethod(cls, state)));
    }
    if ([cls instancesRespondToSelector:glass]) {
        BOOL (*orig)(id, SEL) = (BOOL (*)(id, SEL))class_getMethodImplementation(cls, glass);
        IMP mine = imp_implementationWithBlock(^BOOL(id me) { return SGRAlbumWantsNoBar(me) ? NO : orig(me, glass); });
        class_replaceMethod(cls, glass, mine, method_getTypeEncoding(class_getInstanceMethod(cls, glass)));
    }
}

static void dropNavigationBar(UIView *page) {
    // Spotify rests the page at an offset of 0 whatever the inset, so iOS's adjustment only ever moved it: taking the
    // bar away took its 78pt out of the inset, iOS kept the content still by scrolling 78pt, and the cover went up off
    // the top edge until Spotify scrolled back (the dump of 2026-11-08). With no adjustment, nothing moves.
    // Found by name through the cached lookups, not a walk of the whole page on every scroll step.
    static char kContainerKey, kOverlayKey;
    UIView *container = SGRFindByIdentifier(page, @"PCFFTabLayoutViewController.containerScrollView", &kContainerKey);
    UIView *overlay = SGRFindByIdentifier(page, @"PCFFTabLayoutViewController.overlayScrollView", &kOverlayKey);
    for (UIView *v in @[container ?: NSNull.null, overlay ?: NSNull.null]) {
        if ([v isKindOfClass:UIScrollView.class] && ((UIScrollView *)v).contentInsetAdjustmentBehavior != UIScrollViewContentInsetAdjustmentNever)
            ((UIScrollView *)v).contentInsetAdjustmentBehavior = UIScrollViewContentInsetAdjustmentNever;
    }
    UIViewController *hosted = hostedOf(page);
    if (!hosted) return;
    hookBarState(object_getClass(hosted));
    if (!objc_getAssociatedObject(hosted, &kNoBarKey)) {
        objc_setAssociatedObject(hosted, &kNoBarKey, @YES, OBJC_ASSOCIATION_RETAIN_NONATOMIC);
    }
    UINavigationController *nav = hosted.navigationController;
    if (nav.topViewController == hosted && !nav.navigationBarHidden && !nav.transitionCoordinator) [nav setNavigationBarHidden:YES animated:NO];
    SGRPinnedBack(page, &kPinnedBackKey);
}

// An album page asks for no bar from the moment Spotify first asks, before it has laid anything out, by its address:
// marked only once its header had laid out, the page laid out with the bar first, and dropping it then moved the whole
// page 25pt and back as it opened (recording of 2026-11-08).
static NSString *addressText(id value) {
    if (!value) return nil;
    if ([value isKindOfClass:NSURL.class]) return ((NSURL *)value).absoluteString;
    if ([value isKindOfClass:NSString.class]) return value;
    return [value description];
}

static BOOL isAlbumPage(UIViewController *hosted) {
    NSString *uri = [hosted respondsToSelector:@selector(spt_pageURI)] ? addressText(hosted.spt_pageURI) : nil;
    NSString *other = [hosted respondsToSelector:NSSelectorFromString(@"URI")]
        ? addressText(((id (*)(id, SEL))objc_msgSend)(hosted, NSSelectorFromString(@"URI"))) : nil;
    // The artist page takes the same (its owner, 2026-11-08: "the same treatment to the artist view").
    for (NSString *text in @[uri ?: @"", other ?: @""]) {
        if ([text hasPrefix:@"spotify:album:"] || [text containsString:@"open.spotify.com/album/"]
            || [text hasPrefix:@"spotify:artist:"] || [text containsString:@"open.spotify.com/artist/"]) return YES;
    }
    return NO;
}

void SGRDropNavigationBar(UIView *page) {
    dropNavigationBar(page);
}

BOOL SGRAlbumWantsNoBar(UIViewController *hosted) {
    return objc_getAssociatedObject(hosted, &kNoBarKey) != nil || isAlbumPage(hosted);
}

static void applyWash(UIView *page) {
    for (UIView *sub in page.subviews) {
        Class cls = sub.class;
        if (!SGClassNamed(cls, @"HeaderView") && !SGClassNamed(cls, @"HeaderNavigationBar")) continue;
        BOOL wash = !SGClassNamed(cls, @"NavigationBar");
        if (!wash) {
            // The bar's own fade is LiquidGlass's GradientView inside a plain view (the dump of 2026-11-08), tinted the
            // page's color as it scrolls: the accent-like band at the top its owner saw, upright and sideways.
            SGForEachView(sub, ^(UIView *v) {
                if (v != sub && SGClassNamed(v.class, @"GradientView")) maskOut(v);
            });
        }
        for (UIView *v in sub.subviews) {
            if (!SGClassNamed(v.class, @"GradientView")) continue;
            if (wash) {
                UIColor *color = washColorOf(v);
                SGRAlbumSetSpotifyColor(page, color);
            }
            maskOut(v);
        }
    }
}

static void applyHeader(UIView *header, UIView *page) {
    if (!SGRFindByIdentifier(header, @"CreativeWorkPlatform.Components.UI.TitleRow", &kTitleKey)) return;
    SGRAlbumHoldPage(page);
    applyWash(page);
    dropNavigationBar(page);
    // The header at rest is the tallest it has been at this width, so the picture does not change size as the header
    // loads or scrolls; each width keeps its own, so turning the phone and back finds the upright height again.
    CGFloat width = header.bounds.size.width, rest = header.bounds.size.height;
    NSMutableDictionary<NSNumber *, NSNumber *> *kept = objc_getAssociatedObject(header, &kHeaderHeightKey);
    if (!kept) {
        kept = [NSMutableDictionary dictionary];
        objc_setAssociatedObject(header, &kHeaderHeightKey, kept, OBJC_ASSOCIATION_RETAIN_NONATOMIC);
    }
    NSNumber *widthKey = @(round(width));
    rest = MAX(rest, kept[widthKey].doubleValue);
    kept[widthKey] = @(rest);
    CGRect wide = wideCover(header, page);
    BOOL turned = !CGRectIsEmpty(wide) && CGRectIsEmpty([objc_getAssociatedObject(header, &kWideKey) CGRectValue]);
    objc_setAssociatedObject(header, &kWideKey, [NSValue valueWithCGRect:wide], OBJC_ASSOCIATION_RETAIN_NONATOMIC);
    // Upright, held at its height with the bar while Spotify's column sits higher without it, so the songs stay under
    // the row rather than rising with the column.
    CGFloat drop = CGRectIsEmpty(wide) ? columnDrop(header) : 0;
    // And never shorter than the cover, the gap, the text and the row under it: back upright after a turn the header
    // came back short of that, the text no longer fitted under the cover and sat on the header's bottom edge over it
    // (recording of 2026-11-08).
    SGRNativeAlbumHero *heldHero = objc_getAssociatedObject(header, &kHeroKey);
    SGRHeaderInfo *heldInfo = objc_getAssociatedObject(header, &kInfoKey);
    CGFloat need = 0;
    CGRect cover0 = CGRectIsEmpty(wide) ? uprightCover(header) : CGRectZero;
    if (CGRectIsEmpty(cover0) && heldHero) cover0 = heldHero.square;
    if (CGRectIsEmpty(wide) && heldInfo && !CGRectIsEmpty(cover0))
        need = ceil(CGRectGetMaxY(cover0) + kTitleUnderCover + [heldInfo contentHeightForWidth:width] + SGRHeaderInfoBottom);
    // Held whenever that is known, so the hold never lets go and finds itself short again on the next pass.
    // Exactly that once the cover has its own place: the tallest the header had been at the width also counted a pass
    // mid-turn, and left 190pt of empty field between the row and the songs (recording of 2026-11-08).
    CGFloat upright = need > 0 ? need : drop > 0.5 ? rest : 0;
    sizeHeader(header, !CGRectIsEmpty(wide) ? CGRectGetMaxY(wide) + kWideBelow : upright);
    shapeTopEdge(header, !CGRectIsEmpty(wide));

    NSString *artist, *album;
    SGRHeaderInfo *info = applyInfo(header, page, wide, &artist, &album);
    // The picture reaches to where the content's top is at rest, plus the title and the artist.
    CGFloat bottom = CGRectIsEmpty(wide)
        ? rest - SGRHeaderInfoBottom - [info contentHeightForWidth:width] + SGRHeaderInfoTitleRise
        : CGRectGetMaxY(wide) + 1;
    UIView *cover = SGRFindByIdentifier(header, @"CreativeWorkPlatform.Components.UI.ArtWorkElement.WithCoverArt", &kCoverKey);
    if (cover) applyHero(header, cover, bottom, wide);
    SGRNativeAlbumHero *hero = objc_getAssociatedObject(header, &kHeroKey);
    [hero playMotionForArtist:artist album:album];
    // And once the turn has settled, in case nothing scrolls.
    if (turned && hero) {
        __weak SGRNativeAlbumHero *weakHero = hero;
        dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(0.5 * NSEC_PER_SEC)), dispatch_get_main_queue(), ^{
            if (weakHero) SGRAlbumRecheckWide(weakHero);
        });
    }
}

// Sideways, where the cover goes is read again as the list moves: the header's place at rest is read from the list's
// offset and insets, which are still the upright ones in the pass that turns the page (the cover sat under the top
// edge, device recording 2026-11-08). Only a change lays the header out again.
void SGRAlbumRecheckWide(UIView *hero) {
    UIView *header = hero.superview, *page = SGRAlbumPageOf(hero);
    if (!header || !page || header.window.bounds.size.width <= header.window.bounds.size.height) return;
    CGRect now = wideCover(header, page), was = [objc_getAssociatedObject(header, &kWideKey) CGRectValue];
    if (fabs(now.origin.y - was.origin.y) > 0.5 || fabs(now.origin.x - was.origin.x) > 0.5) applyHeader(header, page);
}

static void applyPage(UIView *page) {
    UIView *header = SGRFindByIdentifier(page, @"CreativeWorkPlatform.Components.UI.CreativeWorkHeader", &kHeaderKey);
    if (!header) return;
    applyHeader(header, page);
    // The header lays itself out again whenever its cover, its artist or its buttons arrive, which the
    // page's own pass does not hear about. It is a plain UIView, so its pass can be watched.
    watch(header, &kHeaderWatchedKey, ^(UIView *view) {
        UIView *owner = SGRAlbumPageOf(view);
        if (owner) applyHeader(view, owner);
    });
}

%hook _TtC28CreativeWorkPlatform_PageKit24CreativeWorkTemplateView
- (void)layoutSubviews {
    %orig;
    applyPage((UIView *)self);
}
%end

// The play button arrives in the page after the row that replaces it has been laid out, so a page opening
// showed Spotify's green disc in the corner until something else laid the page out. Its own pass is where
// it goes, and the class is Spotify's own so nothing else pays for the check.
%hook _TtC28EncoreConsumerMobile_BaseKit14PlayButtonView
- (void)layoutSubviews {
    %orig;
    UIView *button = (UIView *)self;
    if (button.layer.hidden || ![button.accessibilityIdentifier isEqualToString:@"header-play-button"]) return;
    UIView *page = SGRAlbumPageOf(button);
    if (!page) return;
    conceal(wrapperFor(button, page));
    applyPage(page);
}
%end

%group SGRAlbumBar
%hook SGRAlbumHostingController
- (NSInteger)preferredNavigationBarState {
    return SGRAlbumWantsNoBar((UIViewController *)self) ? 2 : %orig;
}
- (BOOL)prefersLiquidGlassNavigationBar {
    return SGRAlbumWantsNoBar((UIViewController *)self) ? NO : %orig;
}
%end
%end

%ctor {
    // Native redesign's album header; with it off, AlbumHeader.x's is the redesign's as it was.
    if (!SGRedesignedUI() || !SGNativeRedesign()) return;
    %init;
    // The controller every Music app page is hosted in on Spotify's stack (the album dump of 2026-11-08).
    // Swift's mangled name: the dotted one is not found from here, and the hook never went on (2026-11-08).
    Class hosting = NSClassFromString(@"_TtC33Navigation_PageAPIIntegrationImpl33MusicAppPageHostingViewController")
                 ?: NSClassFromString(@"Navigation_PageAPIIntegrationImpl.MusicAppPageHostingViewController");
    if (hosting && [hosting instancesRespondToSelector:@selector(preferredNavigationBarState)]) {
        %init(SGRAlbumBar, SGRAlbumHostingController = hosting);
        if (!sgr_barHooked) sgr_barHooked = [NSMutableSet set];
        [sgr_barHooked addObject:hosting];
    }
    SGRequireClasses(@[
        @"_TtC28CreativeWorkPlatform_PageKit24CreativeWorkTemplateView",
        @"_TtC28EncoreConsumerMobile_BaseKit14PlayButtonView",
    ]);
}
