#import "SystemQueue.h"
#import "SystemHistory.h"
#import <objc/message.h>
#import "Core/SGCore.h"
#import "Headers/SPTPlayer.h"
#import "Redesigned/Kit/SGRKit.h"
#import "Shared/AutoMix/AutoMix.h"

// The chips' height and gap, the rows' height, cover side and corners, and the most tracks shown (the player reports
// far more ahead on a long playlist; the Music app's list is a look ahead too).
static const CGFloat kChipHeight = 34, kChipGap = 10, kChipsBelow = 14, kRowHeight = 56, kRowCover = 44, kRowCoverRadius = 6;
static const CGFloat kSideMargin = 28, kListTopFade = 18, kListFootFade = 36;
// History: its heading's height, the gap under its last track, and the most tracks it shows.
static const CGFloat kHistoryHeading = 36, kHistoryBelow = 10;
static const NSUInteger kHistoryMost = 20;
static const NSUInteger kMostTracks = 60;

static BOOL isTrack(id track) {
    return [track isKindOfClass:NSClassFromString(@"SPTPlayerTrack")];
}

// A group of the list: Spotify's provider for its tracks, its heading and its note.
@interface SGRQueueGroup : NSObject
@property (nonatomic, copy) NSString *heading, *note;
@property (nonatomic, strong) NSMutableArray<SPTPlayerTrack *> *tracks;
@property (nonatomic, strong) NSMutableArray<NSNumber *> *places;   // each track's index in the list it was laid out from
@end

@implementation SGRQueueGroup
@end

#pragma mark - a row

@interface SGRQueueRow : UITableViewCell
@property (nonatomic, readonly) UIImageView *cover;
@property (nonatomic, readonly) UILabel *title, *artist;
@property (nonatomic, copy) NSString *coverFor;   // the track its cover was asked for, so a late answer for another is dropped
@property (nonatomic, readonly) UIImageView *grip;  // drawn by the row: the list is not in UIKit's editing, so a swipe works
@end

// The Music app's reorder grip, measured off its owner's screenshot (2026-11-02): three long thin lines, 25 pt wide,
// 1.4 pt thick, 6 pt apart, round-ended. Drawn once, a template.
static UIImage *gripGlyph(void) {
    static UIImage *glyph;
    if (glyph) return glyph;
    CGFloat width = 25, line = 1.4, gap = 6;
    CGSize size = CGSizeMake(width, 2 * gap + line);
    glyph = [[[[UIGraphicsImageRenderer alloc] initWithSize:size] imageWithActions:^(UIGraphicsImageRendererContext *context) {
        [UIColor.blackColor setStroke];
        for (int i = 0; i < 3; i++) {
            CGFloat y = line / 2 + i * gap;
            UIBezierPath *path = [UIBezierPath bezierPath];
            [path moveToPoint:CGPointMake(line / 2, y)];
            [path addLineToPoint:CGPointMake(width - line / 2, y)];
            path.lineWidth = line;
            path.lineCapStyle = kCGLineCapRound;
            [path stroke];
        }
    }] imageWithRenderingMode:UIImageRenderingModeAlwaysTemplate];
    return glyph;
}

@implementation SGRQueueRow

- (instancetype)initWithStyle:(UITableViewCellStyle)style reuseIdentifier:(NSString *)identifier {
    if (!(self = [super initWithStyle:style reuseIdentifier:identifier])) return nil;
    self.backgroundColor = UIColor.clearColor;
    UIView *pressed = [UIView new];
    pressed.backgroundColor = [UIColor colorWithWhite:1 alpha:0.08];
    self.selectedBackgroundView = pressed;
    _cover = [UIImageView new];
    _cover.contentMode = UIViewContentModeScaleAspectFill;
    _cover.clipsToBounds = YES;
    _cover.layer.cornerRadius = kRowCoverRadius;
    _cover.layer.cornerCurve = kCACornerCurveContinuous;
    _cover.backgroundColor = [UIColor colorWithWhite:1 alpha:0.1];
    _title = [UILabel new];
    _title.font = SGRFont(UIFontTextStyleSubheadline, UIFontWeightSemibold, UIContentSizeCategoryExtraExtraLarge);
    _title.textColor = SGRPrimary();
    _artist = [UILabel new];
    _artist.font = SGRFont(UIFontTextStyleFootnote, UIFontWeightRegular, UIContentSizeCategoryExtraExtraLarge);
    _artist.textColor = SGRSecondary();
    _grip = [[UIImageView alloc] initWithImage:gripGlyph()];
    _grip.tintColor = [UIColor colorWithWhite:1 alpha:0.4];
    _grip.contentMode = UIViewContentModeCenter;
    for (UIView *view in @[_cover, _title, _artist, _grip]) [self.contentView addSubview:view];
    return self;
}

- (void)layoutSubviews {
    [super layoutSubviews];
    CGSize size = self.contentView.bounds.size;
    _cover.frame = CGRectMake(kSideMargin, round((size.height - kRowCover) / 2), kRowCover, kRowCover);
    CGFloat gripWidth = _grip.hidden ? 0 : 44;
    _grip.frame = CGRectMake(size.width - kSideMargin + 12 - gripWidth, 0, gripWidth, size.height);
    CGFloat textX = CGRectGetMaxX(_cover.frame) + 12, textWidth = MAX(0, size.width - kSideMargin - textX - (gripWidth ? gripWidth - 12 : 0));
    CGFloat titleHeight = ceil(_title.font.lineHeight), artistHeight = ceil(_artist.font.lineHeight);
    CGFloat top = round((size.height - titleHeight - artistHeight) / 2);
    _title.frame = CGRectMake(textX, top, textWidth, titleHeight);
    _artist.frame = CGRectMake(textX, top + titleHeight, textWidth, artistHeight);
}

@end

#pragma mark - the queue

@interface SGRSystemQueueView () <UITableViewDataSource, UITableViewDelegate, UIGestureRecognizerDelegate>
@end

static BOOL noReasons(id limits, NSString *name) {
    SEL selector = NSSelectorFromString(name);
    if (![limits respondsToSelector:selector]) return YES;
    id reasons = ((id (*)(id, SEL))objc_msgSend)(limits, selector);
    return ![reasons respondsToSelector:@selector(count)] || [reasons count] == 0;
}

BOOL SGRSystemOptionAllowed(SPTPlayerState *state, BOOL repeat) {
    SEL restrictions = NSSelectorFromString(@"restrictions");
    id limits = [state respondsToSelector:restrictions] ? ((id (*)(id, SEL))objc_msgSend)(state, restrictions) : nil;
    if (!limits) return YES;
    if (!repeat) return noReasons(limits, @"disallowTogglingShuffleReasons");
    return noReasons(limits, @"disallowTogglingRepeatContextReasons") || noReasons(limits, @"disallowTogglingRepeatTrackReasons");
}

@implementation SGRSystemQueueView {
    UIButton *_automix;   // one chip, three states as repeat has: off, AutoMix (beat-matched), Crossfade
    UIButton *_shuffle, *_repeat;   // shown while the controls have them hidden (showsShuffle, showsRepeat)
    UIButton *_clear;               // clears Playing Next, dimmed while it holds nothing
    UIButton *_jam;                 // starts a Jam, or opens it while one is on (onJam)
    UIView *_chipsRow;              // holds the chips, so the row fades as a whole whatever each chip's own dim
    BOOL _shuffling;
    NSInteger _repeatMode;          // 0 off, 1 the playlist or album, 2 the track
    UITableView *_list;
    CAGradientLayer *_listFade;
    CGFloat _controlsCover;   // how much of the list's foot the controls cover now (controlsHeight, or 0 in a drag)
    CGFloat _headPush;        // how far the list's scroll has pushed the page's head up, 0 to headRoom
    UIView *_chipsBar;        // with headRoom: the list's header, History, the head's room, then the chips, scrolling with it
    UIView *_historyBox;      // History: the tracks played before this one, above the head, as the Music app has them
    NSArray<SPTPlayerTrack *> *_history;   // oldest first, the one just played last
    NSArray<NSString *> *_historyKey;
    BOOL _pastFromQueue;
    UIView *_pinnedHeading;   // the group heading held under the chips once its own has gone under them
    UIView *_pinnedClip;      // holds it, cut at the chips' foot, so the next group pushing it up never shows it over them
    NSString *_pinnedKey;     // what it was made for
    CGFloat _pinnedBottom;    // where it ends, the top's fade beginning there; 0 with none      // History read from Spotify's whole queue: the state's few no longer stand in for it
    NSArray<SGRQueueGroup *> *_groups;
    NSArray<NSString *> *_shownURIs;   // the tracks last shown, so the same queue again is not laid out again
    NSArray *_upcoming;                // Spotify's whole list of tracks to come, when shown from it; nil from the state
    void (^_waiting)(void);            // a new list held back while a finger is on the list (a track being moved)
    // A track being moved by its grip (reordered:): its row's picture following the finger up and down, the row it stands
    // in now, and where it was picked up.
    UIView *_lifted;
    NSIndexPath *_liftedAt, *_liftedFrom;
    __weak SPTPlayerTrack *_liftedTrack;   // the track lifted: its row stays hidden wherever UIKit draws it meanwhile
    CGFloat _liftOffset;
    CGPoint _dragPoint;                // the finger, in this view, for the frames between its moves
    CADisplayLink *_dragLink;
    BOOL _quietMoves;                  // the moves of one lift handed to Spotify once, at the let go
    BOOL _repeatContext;
}

- (instancetype)initWithFrame:(CGRect)frame {
    if (!(self = [super initWithFrame:frame])) return nil;
    _automix = [self chipWithImage:automixGlyph() title:@"AutoMix"];
    [_automix setTitle:@" AutoMix" forState:UIControlStateNormal];
    _automix.titleLabel.font = SGRFont(UIFontTextStyleSubheadline, UIFontWeightSemibold, UIContentSizeCategoryExtraLarge);
    __weak typeof(self) weakSelf = self;
    [_automix addAction:[UIAction actionWithHandler:^(UIAction *action) { [weakSelf stepAutoMix]; }]
         forControlEvents:UIControlEventTouchUpInside];
    // Grouped, so the group headings scroll with their tracks rather than stand over them.
    _list = [[UITableView alloc] initWithFrame:CGRectZero style:UITableViewStyleGrouped];
    _list.sectionFooterHeight = 10;
    _list.backgroundColor = UIColor.clearColor;
    _list.separatorStyle = UITableViewCellSeparatorStyleNone;
    _list.rowHeight = kRowHeight;
    // Exact sizes, none guessed: a row moved while the list scrolls up made UIKit measure the guessed groups above
    // again and put the list back down by the difference, so a lifted track never got higher (phone log, 2026-11-03).
    _list.estimatedRowHeight = 0;
    _list.estimatedSectionHeaderHeight = 0;
    _list.estimatedSectionFooterHeight = 0;
    _list.sectionHeaderTopPadding = 0;
    _list.dataSource = self;
    _list.delegate = self;
    _list.showsVerticalScrollIndicator = NO;
    // Grips out as the Music app's queue has them, drawn by the rows: a press on a grip lifts its track, which follows the
    // finger up and down only, iOS's reorder (its owner, 2026-11-02), and a swipe left takes a track out. UIKit's own
    // reordering turned swipes off, and its drag and drop let the row float anywhere. A tap still plays.
    UILongPressGestureRecognizer *reorder = [[UILongPressGestureRecognizer alloc] initWithTarget:self action:@selector(reordered:)];
    reorder.minimumPressDuration = 0.08;
    reorder.delegate = self;
    [_list addGestureRecognizer:reorder];
    _list.contentInset = UIEdgeInsetsMake(kListTopFade / 2, 0, kListFootFade, 0);
    [_list registerClass:SGRQueueRow.class forCellReuseIdentifier:@"row"];
    // No gap of the grouped style's own over the first group.
    _list.tableHeaderView = [[UIView alloc] initWithFrame:CGRectMake(0, 0, 0, CGFLOAT_MIN)];
    // The list fades out at its top edge, under the chips, as the lyrics' lines do at theirs.
    _listFade = [CAGradientLayer layer];
    _listFade.colors = @[(id)UIColor.clearColor.CGColor, (id)UIColor.clearColor.CGColor, (id)UIColor.blackColor.CGColor,
                         (id)UIColor.blackColor.CGColor, (id)UIColor.clearColor.CGColor];
    _list.layer.mask = _listFade;
    _shuffle = [self chipWithImage:chipSymbol(@"shuffle") title:@"Shuffle"];
    _repeat = [self chipWithImage:chipSymbol(@"repeat") title:@"Repeat"];
    _shuffle.hidden = _repeat.hidden = YES;
    [_shuffle addAction:[UIAction actionWithHandler:^(UIAction *action) { [weakSelf stepShuffle]; }]
       forControlEvents:UIControlEventTouchUpInside];
    [_repeat addAction:[UIAction actionWithHandler:^(UIAction *action) { [weakSelf stepRepeat]; }]
      forControlEvents:UIControlEventTouchUpInside];
    // Clear, beside AutoMix (its owner, 2026-11-02): every track queued by hand out at once.
    _clear = [self chipWithImage:chipSymbol(@"xmark") title:@"Clear Playing Next"];
    _clear.titleLabel.font = SGRFont(UIFontTextStyleSubheadline, UIFontWeightSemibold, UIContentSizeCategoryExtraLarge);
    [_clear addAction:[UIAction actionWithHandler:^(UIAction *action) { [weakSelf tapClear]; }] forControlEvents:UIControlEventTouchUpInside];
    _jam = [self chipWithImage:chipSymbol(@"person.2.fill") title:@"Start a Jam"];
    _jam.titleLabel.font = SGRFont(UIFontTextStyleSubheadline, UIFontWeightSemibold, UIContentSizeCategoryExtraLarge);
    [_jam addAction:[UIAction actionWithHandler:^(UIAction *action) { if (weakSelf.onJam) weakSelf.onJam(); }]
   forControlEvents:UIControlEventTouchUpInside];
    _chipsRow = [UIView new];
    _headShown = 1;
    [self addSubview:_list];
    [self addSubview:_chipsRow];
    for (UIView *view in @[_automix, _shuffle, _repeat, _clear, _jam]) [_chipsRow addSubview:view];
    [self syncCrossfade];
    [self syncClear];
    return self;
}

// The Music app's crossfade glyph (its owner's recording, 2026-11-02), which SF Symbols has no public match for: two
// curves crossing, one whole and one faint. Drawn once, a template, so the chip's ink colors it.
static UIImage *crossfadeGlyph(void) {
    static UIImage *glyph;
    if (glyph) return glyph;
    CGSize size = CGSizeMake(22, 16);
    UIGraphicsImageRenderer *renderer = [[UIGraphicsImageRenderer alloc] initWithSize:size];
    glyph = [[renderer imageWithActions:^(UIGraphicsImageRendererContext *context) {
        CGFloat inset = 2, w = size.width - 2 * inset, h = size.height - 2 * inset, x = inset, y = inset;
        UIBezierPath *(^curve)(CGPoint, CGPoint) = ^UIBezierPath *(CGPoint from, CGPoint to) {
            UIBezierPath *path = [UIBezierPath bezierPath];
            [path moveToPoint:from];
            [path addCurveToPoint:to controlPoint1:CGPointMake(from.x + w * 0.45, from.y) controlPoint2:CGPointMake(to.x - w * 0.45, to.y)];
            path.lineWidth = 2.2;
            path.lineCapStyle = kCGLineCapRound;
            return path;
        };
        // Down from the top left, faint end to end, and over it up from the bottom left, whole (its owner, 2026-11-02).
        [[UIColor colorWithWhite:0 alpha:0.4] setStroke];
        [curve(CGPointMake(x, y), CGPointMake(x + w, y + h)) stroke];
        [UIColor.blackColor setStroke];
        [curve(CGPointMake(x, y + h), CGPointMake(x + w, y)) stroke];
    }] imageWithRenderingMode:UIImageRenderingModeAlwaysTemplate];
    return glyph;
}

// The Music app's AutoMix symbol (its owner's screenshots, 2026-11-02): a thin, faded ring behind a filled disc with a
// hole in its middle. Drawn once, a template (the ring's fade is its alpha, which a template keeps).
static UIImage *automixGlyph(void) {
    static UIImage *glyph;
    if (glyph) return glyph;
    CGSize size = CGSizeMake(26, 16);
    UIGraphicsImageRenderer *renderer = [[UIGraphicsImageRenderer alloc] initWithSize:size];
    glyph = [[renderer imageWithActions:^(UIGraphicsImageRendererContext *context) {
        CGFloat d = 14, y = 1, line = 1.6;
        [[UIColor colorWithWhite:0 alpha:0.4] set];
        UIBezierPath *ring = [UIBezierPath bezierPathWithOvalInRect:CGRectInset(CGRectMake(1, y, d, d), line / 2, line / 2)];
        ring.lineWidth = line;
        [ring stroke];
        [UIColor.blackColor set];
        UIBezierPath *disc = [UIBezierPath bezierPathWithOvalInRect:CGRectMake(size.width - 1 - d, y, d, d)];
        [disc appendPath:[UIBezierPath bezierPathWithOvalInRect:CGRectInset(CGRectMake(size.width - 1 - d, y, d, d), d * 0.32, d * 0.32)]];
        disc.usesEvenOddFillRule = YES;
        [disc fill];
    }] imageWithRenderingMode:UIImageRenderingModeAlwaysTemplate];
    return glyph;
}

// An SF Symbol at the chips' size, a template.
static UIImage *chipSymbol(NSString *name) {
    UIImageSymbolConfiguration *config = [UIImageSymbolConfiguration configurationWithPointSize:16 weight:UIImageSymbolWeightSemibold];
    return [[UIImage systemImageNamed:name withConfiguration:config] imageWithRenderingMode:UIImageRenderingModeAlwaysTemplate];
}

// A chip as the Music app's queue has them: a capsule with its glyph, lit (filled light, the glyph dark) while on.
- (UIButton *)chipWithImage:(UIImage *)image title:(NSString *)title {
    UIButton *chip = [UIButton buttonWithType:UIButtonTypeCustom];
    [chip setImage:image forState:UIControlStateNormal];
    chip.layer.cornerRadius = kChipHeight / 2;
    chip.layer.cornerCurve = kCACornerCurveContinuous;
    chip.accessibilityLabel = title;
    [self paintChip:chip on:NO];
    return chip;
}

- (void)paintChip:(UIButton *)chip on:(BOOL)on {
    chip.backgroundColor = [self fillFor:on];
    UIColor *ink = on ? [UIColor colorWithWhite:0.08 alpha:0.9] : SGRPrimary();
    chip.tintColor = ink;
    [chip setTitleColor:ink forState:UIControlStateNormal];
    chip.accessibilityValue = on ? @"On" : @"Off";
    [self cutOut:chip];
}

// Lit, the glyph and the name are cut out of the light fill, as the lyrics' and the queue's discs are on the page (its
// owner, 2026-11-09), so the page shows through them: a mask of the capsule less what the chip draws, made again
// whenever the chip's size, glyph or name changes. Unlit, no mask.
- (void)cutOut:(UIButton *)chip {
    BOOL lit = CGColorEqualToColor(chip.backgroundColor.CGColor, [self fillFor:YES].CGColor);
    CGSize size = chip.bounds.size;
    if (!lit || size.width < 1 || size.height < 1) {
        if (chip.layer.mask) chip.layer.mask = nil;
        return;
    }
    [chip layoutIfNeeded];
    UIImage *glyph = [chip imageForState:UIControlStateNormal];
    NSString *title = [chip titleForState:UIControlStateNormal];
    CGRect glyphFrame = chip.imageView.frame, titleFrame = chip.titleLabel.frame;
    UIFont *font = chip.titleLabel.font;
    UIImage *mask = [[[UIGraphicsImageRenderer alloc] initWithSize:size] imageWithActions:^(UIGraphicsImageRendererContext *context) {
        [UIColor.blackColor setFill];
        [[UIBezierPath bezierPathWithRoundedRect:CGRectMake(0, 0, size.width, size.height) cornerRadius:size.height / 2] fill];
        CGContextSetBlendMode(context.CGContext, kCGBlendModeDestinationOut);
        if (glyph && !CGRectIsEmpty(glyphFrame)) [[glyph imageWithTintColor:UIColor.blackColor renderingMode:UIImageRenderingModeAlwaysOriginal] drawInRect:glyphFrame blendMode:kCGBlendModeDestinationOut alpha:1];
        if (title.length && font && !CGRectIsEmpty(titleFrame))
            [title drawInRect:titleFrame withAttributes:@{NSFontAttributeName: font, NSForegroundColorAttributeName: UIColor.blackColor}];
    }];
    CALayer *layer = [chip.layer.mask isKindOfClass:CALayer.class] ? chip.layer.mask : [CALayer layer];
    [CATransaction begin];
    [CATransaction setDisableActions:YES];
    layer.frame = chip.bounds;
    layer.contents = (__bridge id)mask.CGImage;
    [CATransaction commit];
    if (chip.layer.mask != layer) chip.layer.mask = layer;
}

// Mod Settings' AutoMix, the same setting (its owner, 2026-11-02): one chip that steps through it as repeat steps
// through its modes, off, then AutoMix (the Beat-matched style), then Crossfade, then off again, as the page's switch
// and style menu set them (Shared/AutoMix/AutoMixSettings.m). Off it reads AutoMix, unlit; on, it is lit and names the
// style. Dimmed until Spotify has read its settings, a few seconds into a launch.
- (void)syncCrossfade {
    [self syncAutoMixAnimated:NO];
}

// A step of the chip's, animated: the fill and ink cross over, the glyph and name dissolve into the new ones, and the chip
// gives a little as it changes, settling on the press spring (its owner, 2026-11-02). Reduce Motion keeps the fade alone.
- (void)syncAutoMixAnimated:(BOOL)animated {
    SGTransitionSettings settings;
    BOOL read = SGTransitionSettingsRead(&settings);
    _automix.enabled = read;
    _automix.alpha = read ? 1 : 0.5;
    BOOL on = read && SGFlag(SGKeyAutoMix, NO);
    BOOL crossfade = on && SGAutoMixCurrentStyle() == SGAutoMixCrossfade;
    [self setChip:_automix on:on image:crossfade ? crossfadeGlyph() : automixGlyph() title:crossfade ? @"Crossfade" : @"AutoMix" animated:animated];
    _automix.accessibilityLabel = @"AutoMix";
    _automix.accessibilityValue = !on ? @"Off" : crossfade ? @"Crossfade" : @"Beat-matched";
}

// The glyphs alone while Shuffle or Repeat stand beside AutoMix, the Music app's row of four; AutoMix alone keeps its name.
- (BOOL)glyphsOnly {
    // AutoMix and Clear alone share the row at half its width each, room for their names (its owner, 2026-11-02).
    return _showsShuffle || _showsRepeat;
}

// Any chip's change: the glyph and name dissolve into the new ones, the fill and ink cross over, and the chip gives a
// little, settling on the press spring. Unchanged, nothing moves; Reduce Motion keeps the fade alone.
- (void)setChip:(UIButton *)chip on:(BOOL)on image:(UIImage *)image title:(NSString *)name animated:(BOOL)animated {
    NSString *title = self.glyphsOnly ? nil : [@" " stringByAppendingString:name];
    BOOL swaps = [chip imageForState:UIControlStateNormal] != image
              || !([chip titleForState:UIControlStateNormal] == title || [[chip titleForState:UIControlStateNormal] isEqualToString:title]);
    BOOL lights = !CGColorEqualToColor(chip.backgroundColor.CGColor, [self fillFor:on].CGColor);
    BOOL moves = animated && chip.window && (swaps || lights);
    // The glyph and name change at once: a cross-dissolve showed both names over each other, cut out of the fill by the
    // mask of only one of them (its owner's recording, 2026-11-09). The fill fades and the chip gives instead.
    if (swaps) {
        [UIView performWithoutAnimation:^{
            [chip setImage:image forState:UIControlStateNormal];
            [chip setTitle:title forState:UIControlStateNormal];
            [chip layoutIfNeeded];
        }];
    }
    if (moves) {
        SGRAnimate(SGRMotionFade, ^{ [self paintChip:chip on:on]; }, nil);
        if (!SGRReduceMotion()) {
            chip.transform = CGAffineTransformMakeScale(0.94, 0.94);
            SGRAnimate(SGRMotionPress, ^{ chip.transform = CGAffineTransformIdentity; }, nil);
        }
    } else {
        [self paintChip:chip on:on];
    }
}

- (UIColor *)fillFor:(BOOL)on {
    return on ? [UIColor colorWithWhite:1 alpha:0.85] : [UIColor colorWithWhite:1 alpha:0.14];
}

- (void)syncShuffleRepeatAnimated:(BOOL)animated {
    [self setChip:_shuffle on:_shuffling image:chipSymbol(@"shuffle") title:@"Shuffle" animated:animated];
    _shuffle.accessibilityValue = _shuffling ? @"On" : @"Off";
    [self setChip:_repeat on:_repeatMode > 0 image:chipSymbol(_repeatMode == 2 ? @"repeat.1" : @"repeat") title:@"Repeat" animated:animated];
    _repeat.accessibilityValue = _repeatMode == 2 ? @"This song" : _repeatMode == 1 ? @"All" : @"Off";
}

- (void)setShowsShuffle:(BOOL)shows {
    if (shows == _showsShuffle) return;
    _showsShuffle = shows;
    _shuffle.hidden = !shows;
    [self chipsChanged];
}

- (void)setShowsRepeat:(BOOL)shows {
    if (shows == _showsRepeat) return;
    _showsRepeat = shows;
    _repeat.hidden = !shows;
    [self chipsChanged];
}

- (void)chipsChanged {
    [self syncAutoMixAnimated:NO];
    [self syncClear];
    [self syncShuffleRepeatAnimated:NO];
    [self setNeedsLayout];
}

// The tap shows the next state at once, as Spotify's own buttons do; Spotify's state confirms it (showState:).
- (void)tapClear {
    if (!SGRReduceMotion()) {
        UIButton *clear = _clear;
        clear.transform = CGAffineTransformMakeScale(0.94, 0.94);
        SGRAnimate(SGRMotionPress, ^{ clear.transform = CGAffineTransformIdentity; }, nil);
    }
    [self clearQueued];
}

// Clear shown while Playing Next holds tracks it can take out, and gone while not (its owner, 2026-11-09: not dimmed);
// the other chips take its room.
- (void)syncClear {
    BOOL any = NO;
    for (SGRQueueGroup *group in _groups) if ([group.heading isEqualToString:@"Playing Next"] && group.tracks.count) any = YES;
    BOOL on = any && _upcoming != nil;
    NSString *title = self.glyphsOnly ? nil : @" Clear";
    if (!([_clear titleForState:UIControlStateNormal] == title || [[_clear titleForState:UIControlStateNormal] isEqualToString:title]))
        [UIView performWithoutAnimation:^{ [self->_clear setTitle:title forState:UIControlStateNormal]; [self->_clear layoutIfNeeded]; }];
    [self paintChip:_clear on:NO];
    BOOL changed = _clear.enabled != on || _clear.hidden == on;
    _clear.enabled = on;
    if (!changed) return;
    if (!self.window) {
        _clear.hidden = !on;
        _clear.alpha = on ? 1 : 0;
        [self setNeedsLayout];
        return;
    }
    if (on) {
        _clear.hidden = NO;
        _clear.alpha = 0;
    }
    [self setNeedsLayout];
    SGRAnimate(SGRMotionPress, ^{
        [self layoutIfNeeded];
        self->_clear.alpha = on ? 1 : 0;
    }, ^(BOOL finished) {
        if (!self->_clear.enabled) self->_clear.hidden = YES;
    });
}

- (void)stepShuffle {
    _shuffling = !_shuffling;
    [self syncShuffleRepeatAnimated:YES];
    if (self.onShuffle) self.onShuffle();
}

- (void)stepRepeat {
    _repeatMode = (_repeatMode + 1) % 3;
    [self syncShuffleRepeatAnimated:YES];
    if (self.onRepeat) self.onRepeat();
}

- (void)stepAutoMix {
    SGTransitionSettings settings;
    if (!SGTransitionSettingsRead(&settings)) return;
    BOOL on = SGFlag(SGKeyAutoMix, NO);
    if (!on) {
        SGAutoMixSetStyle(SGAutoMixBeatMatched);
        SGSetEnabled(SGKeyAutoMix, YES);
        SGAutoMixApply(YES);
    } else if (SGAutoMixCurrentStyle() == SGAutoMixBeatMatched) {
        SGAutoMixSetStyle(SGAutoMixCrossfade);
    } else {
        SGSetEnabled(SGKeyAutoMix, NO);
        SGAutoMixApply(NO);
    }
    [self syncAutoMixAnimated:YES];
}

- (void)setJamOn:(BOOL)jamOn {
    _jamOn = jamOn;
    [self paintChip:_jam on:jamOn];
    _jam.accessibilityLabel = jamOn ? @"Jam" : @"Start a Jam";
}

- (void)layoutSubviews {
    [super layoutSubviews];
    CGSize size = self.bounds.size;
    // The chips shown share the row equally, kChipGap apart: Shuffle, Repeat, then AutoMix, the Music app's order.
    NSMutableArray<UIView *> *chips = [NSMutableArray array];
    if (_showsShuffle) [chips addObject:_shuffle];
    if (_showsRepeat) [chips addObject:_repeat];
    // Jam in the middle, labelled like AutoMix and Clear (its owner, 2026-11-09): AutoMix, Jam, Clear.
    [chips addObject:_automix];
    [chips addObject:_jam];
    if (_clear.enabled) [chips addObject:_clear];
    NSString *jamTitle = self.glyphsOnly ? nil : @" Jam";
    if (!([_jam titleForState:UIControlStateNormal] == jamTitle || [[_jam titleForState:UIControlStateNormal] isEqualToString:jamTitle]))
        [UIView performWithoutAnimation:^{ [self->_jam setTitle:jamTitle forState:UIControlStateNormal]; }];
    CGFloat chipWidth = MAX(0, (size.width - 2 * kSideMargin - kChipGap * (chips.count - 1)) / chips.count);
    // With headRoom the chips ride up with the list from under the head, and once at the top they stay there, the tracks
    // passing under them (its owner, 2026-11-06: "i wanted the chips to be stuck on the top"); without, they stand over
    // the list.
    BOOL inList = _headRoom > 0;
    CGFloat history = [self historyHeight], chipsTop = [self chipsY];
    _historyBox.frame = CGRectMake(0, 0, size.width, history);
    for (UIView *view in _historyBox.subviews) {
        if (view.tag == 1) view.frame = CGRectMake(kSideMargin, 6, size.width - 2 * kSideMargin, kHistoryHeading - 6);
        else if (view.tag > 100) view.frame = CGRectMake(0, kHistoryHeading + (_history.count - (view.tag - 100)) * kRowHeight, size.width, kRowHeight);
    }
    _chipsRow.frame = CGRectMake(0, chipsTop, size.width, kChipHeight);
    [self bringSubviewToFront:_chipsRow];
    [chips enumerateObjectsUsingBlock:^(UIView *chip, NSUInteger i, BOOL *stop) {
        chip.bounds = CGRectMake(0, 0, chipWidth, kChipHeight);
        chip.center = CGPointMake(kSideMargin + i * (chipWidth + kChipGap) + chipWidth / 2, kChipHeight / 2);
    }];
    for (UIButton *chip in @[_automix, _shuffle, _repeat, _clear, _jam]) [self cutOut:chip];
    CGFloat listTop = inList ? 0 : kChipHeight + kChipsBelow - kListTopFade / 2;
    _list.frame = CGRectMake(0, listTop, size.width, MAX(0, size.height - listTop));
    [CATransaction begin];
    [CATransaction setDisableActions:YES];
    _listFade.frame = _list.bounds;
    _pinnedKey = nil;
    [self placePinnedHeading];
    [self placeFade];
    [CATransaction commit];
    [self padForHistory];
    // The list's size known now: how much of the head and the chips shows is worked out again.
    if (_headRoom > 0) [self pushHead];
}

// Room under a short list, so it scrolls far enough for the head to rest where it does with History above out of view.
- (void)padForHistory {
    if (_headRoom <= 0) return;
    CGFloat pad = _list.tableFooterView.frame.size.height;
    CGFloat content = _list.contentSize.height - pad;
    CGFloat needed = [self historyHeight] + _list.bounds.size.height - _list.adjustedContentInset.top - _list.adjustedContentInset.bottom;
    CGFloat want = MAX(0, ceil(needed - content));
    if (fabs(want - pad) < 1) return;
    _list.tableFooterView = [[UIView alloc] initWithFrame:CGRectMake(0, 0, _list.bounds.size.width, want)];
}

// Where the chips stand in the view: under the head's room, less the scroll, never above the top.
- (CGFloat)chipsY {
    return _headRoom > 0 ? MAX(0, _headRoom - [self scrolled]) : 0;
}

// History's height over the head's room: its heading and its rows, nothing without them.
- (CGFloat)historyHeight {
    return _headRoom > 0 && _history.count ? kHistoryHeading + _history.count * kRowHeight + kHistoryBelow : 0;
}

// How far the list has scrolled from where the head stands at rest; less than 0 with History pulled down into view.
- (CGFloat)scrolled {
    return _list.contentOffset.y + _list.adjustedContentInset.top - [self historyHeight];
}

- (void)setHeadRoom:(CGFloat)room {
    room = MAX(0, round(room));
    if (room == _headRoom) return;
    BOOL atTop = [self scrolled] <= 0.5;
    BOOL was = _headRoom > 0;
    _headRoom = room;
    if (room > 0) {
        if (!_chipsBar) _chipsBar = [UIView new];
        // A header's height is read as it is set, so it is set again for a new one.
        [self sizeChipsBar];
    } else if (was) {
        _list.tableHeaderView = [[UIView alloc] initWithFrame:CGRectMake(0, 0, 0, CGFLOAT_MIN)];
    }
    UIEdgeInsets inset = _list.contentInset;
    inset.top = room > 0 ? 0 : kListTopFade / 2;
    _list.contentInset = inset;
    if (atTop) [self scrollToTop];
    [self pushHead];
    [self setNeedsLayout];
}

// The list's header as tall as History, the head's room and the chips; set again for a new height, as a header's is read
// as it is set.
- (void)sizeChipsBar {
    if (_headRoom <= 0) return;
    CGFloat height = [self historyHeight] + _headRoom + kChipHeight + kChipsBelow - kListTopFade / 2;
    if (_list.tableHeaderView == _chipsBar && _chipsBar.frame.size.height == height) return;
    _chipsBar.frame = CGRectMake(0, 0, _list.bounds.size.width, height);
    _list.tableHeaderView = _chipsBar;
}

// The tracks played before this one (Spotify's state's reverse, which its back button steps through), as History over
// the head, pulled down into view as the Music app's is (its owner, 2026-11-06). Kept where the head was at rest.
- (void)showHistory:(SPTPlayerState *)state {
    if (_pastFromQueue) return;
    // The mod's own History (SystemHistory.h) in place of the state's, while its switch is on.
    NSArray *own = SGRSystemHistoryTracks();
    if (own) {
        [self showPast:own];
        return;
    }
    id reverse = [state respondsToSelector:@selector(reverse)] ? state.reverse : nil;
    [self showHistoryOf:reverse];
}

// The state holds only the last two or three (its owner, 2026-11-06: "history only shows 2"); Spotify's whole queue
// holds more, as its own queue page shows them.
- (void)showPast:(NSArray *)past {
    if (![past isKindOfClass:NSArray.class]) return;
    _pastFromQueue = YES;
    if (_list.isTracking || _list.isDragging || _lifted) return;
    [self showHistoryOf:past];
}

- (void)showHistoryOf:(id)reverse {
    if (_headRoom <= 0) return;
    NSMutableArray<SPTPlayerTrack *> *tracks = [NSMutableArray array];
    NSMutableArray<NSString *> *key = [NSMutableArray array];
    for (id track in [reverse isKindOfClass:NSArray.class] ? reverse : @[]) {
        // Spotify's tracks, or the mod's own History's songs, which answer the same (SystemHistory.h).
        if (![track respondsToSelector:@selector(trackTitle)] || ![track respondsToSelector:@selector(URI)]) continue;
        [tracks addObject:track];
        [key addObject:SGURIString([(SPTPlayerTrack *)track URI]) ?: @""];
    }
    while (tracks.count > kHistoryMost) {
        [tracks removeObjectAtIndex:0];
        [key removeObjectAtIndex:0];
    }
    if ([key isEqualToArray:_historyKey ?: @[]]) return;
    CGFloat scrolled = [self scrolled];
    _history = tracks;
    _historyKey = key;
    if (!_historyBox) {
        _historyBox = [UIView new];
        [_chipsBar addSubview:_historyBox];
    }
    for (UIView *view in _historyBox.subviews.copy) [view removeFromSuperview];
    if (tracks.count) {
        UILabel *heading = [UILabel new];
        heading.font = SGRFont(UIFontTextStyleHeadline, UIFontWeightBold, UIContentSizeCategoryExtraExtraLarge);
        heading.textColor = SGRPrimary();
        heading.text = @"History";
        heading.tag = 1;
        [_historyBox addSubview:heading];
        [tracks enumerateObjectsUsingBlock:^(SPTPlayerTrack *track, NSUInteger i, BOOL *stop) {
            SGRQueueRow *row = [[SGRQueueRow alloc] initWithStyle:UITableViewCellStyleDefault reuseIdentifier:nil];
            row.grip.hidden = YES;
            row.title.text = track.trackTitle;
            row.artist.text = track.artistName.length ? track.artistName : track.metadata[@"album_title"];
            row.accessibilityLabel = [NSString stringWithFormat:@"%@, %@", track.trackTitle ?: @"", row.artist.text ?: @""];
            row.accessibilityTraits = UIAccessibilityTraitButton;
            NSString *uri = SGURIString(track.URI) ?: @"";
            row.coverFor = uri;
            __weak SGRQueueRow *weakRow = row;
            SGRTrackPicture(track, ^(UIImage *image) {
                SGRQueueRow *shown = weakRow;
                if ([shown.coverFor isEqualToString:uri]) shown.cover.image = image;
            });
            // Back as many tracks as it lies behind this one.
            NSInteger steps = (NSInteger)(tracks.count - i);
            row.tag = 100 + steps;
            [row addGestureRecognizer:[[UITapGestureRecognizer alloc] initWithTarget:self action:@selector(historyTapped:)]];
            [self->_historyBox addSubview:row];
        }];
    }
    [self sizeChipsBar];
    [self setNeedsLayout];
    [self layoutIfNeeded];
    [_list layoutIfNeeded];
    [self padForHistory];
    // Where it was: the head at rest stays at rest, History's new height above it.
    _list.contentOffset = CGPointMake(0, scrolled + [self historyHeight] - _list.adjustedContentInset.top);
    [self pushHead];
}

- (void)historyTapped:(UITapGestureRecognizer *)tap {
    NSInteger steps = tap.view.tag - 100;
    if (steps <= 0 || (NSUInteger)steps > _history.count || !_onPickPast) return;
    _onPickPast(_history[_history.count - steps], steps);
}

// How much of something whose foot is at `bottom` shows: all of it until it nears where the list fades out over the
// controls, none past there, as the list's own rows go.
- (CGFloat)shownAbove:(CGFloat)bottom {
    // Not laid out yet: nothing is known to be past the foot (the queue opened, asked before its list had a size, hid the
    // page's title row; its owner's recording, 2026-11-06).
    if (_list.bounds.size.height <= 0) return 1;
    CGFloat end = _list.frame.origin.y + _list.bounds.size.height - _controlsCover;
    return MIN(1, MAX(0, (end - bottom) / kListFootFade));
}

// The list's scroll from where the head rests pushes the page's head up with it, as far as its room, and down with
// History pulled into view. Pulled down, the head and the chips fade as they reach the list's foot, rather than run on
// over the controls (its owner's recording, 2026-11-06).
- (void)pushHead {
    CGFloat push = MIN(_headRoom, [self scrolled]);
    _chipsRow.alpha = [self shownAbove:[self chipsY] + kChipHeight];
    CGFloat shown = [self shownAbove:_headRoom - MIN(0, push)];
    if (push == _headPush && shown == _headShown) return;
    _headPush = push;
    _headShown = shown;
    if (_onHeadPush) _onHeadPush(push);
}

// The part under the controls is theirs: touches there go through to them while they show; so is what is above the chips,
// the head's.
- (UIView *)hitTest:(CGPoint)point withEvent:(UIEvent *)event {
    if (_controlsCover > 0 && point.y > self.bounds.size.height - _controlsCover) return nil;
    // Where the page's head shows now, the touch is its.
    if (_headRoom > 0 && _headShown > 0.5 && point.y >= -_headPush && point.y < _headRoom - _headPush) return nil;
    return [super hitTest:point withEvent:event];
}

// Faded at the top under the chips, and at the foot over the progress bar (its owner, 2026-11-02), the foot's fade ending
// where the controls begin.
- (void)placeFade {
    CGFloat height = _list.bounds.size.height;
    if (height <= 0) return;
    CGFloat end = MAX(0, height - _controlsCover);
    // The top's fade below the chips, and below the heading held under them, once they stand at the top, so tracks pass
    // out of sight there rather than under them (its owner, 2026-11-06: "the fade is a bit too close it overlaps");
    // lower, what is above them (History, the head's room) shows whole.
    CGFloat pinned = _headRoom > 0 && [self chipsY] <= 0 ? MAX([self pinTop], _pinnedBottom) : 0;
    CGFloat from = MIN(0.5, MAX(0, pinned) / height);
    CGFloat edge = MIN(from + 0.3, from + kListTopFade / height);
    CGFloat stop = MAX(edge, end / height), start = MIN(stop, MAX(edge, (end - kListFootFade) / height));
    _listFade.locations = @[@0, @(from), @(edge), @(start), @(stop)];
}

- (void)setControlsHeight:(CGFloat)height {
    if (height == _controlsHeight) return;
    _controlsHeight = height;
    CGPoint offset = _list.contentOffset;
    UIEdgeInsets inset = _list.contentInset;
    inset.bottom = kListFootFade + height;
    _list.contentInset = inset;
    _list.contentOffset = offset;
}

- (void)setControlsCover:(CGFloat)cover animated:(BOOL)animated {
    if (cover == _controlsCover) return;
    _controlsCover = cover;
    [CATransaction begin];
    if (animated) [CATransaction setAnimationDuration:cover > 0 ? 0.45 : 0.3];
    else [CATransaction setDisableActions:YES];
    [self placeFade];
    [CATransaction commit];
}

// The list held back under a finger, shown once the finger is off.
- (void)showWaitingLater {
    __weak typeof(self) weakSelf = self;
    dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(0.25 * NSEC_PER_SEC)), dispatch_get_main_queue(), ^{
        typeof(self) me = weakSelf;
        if (!me || !me->_waiting) return;
        if (me->_list.isTracking || me->_list.isDragging || me->_lifted) { [me showWaitingLater]; return; }
        void (^show)(void) = me->_waiting;
        me->_waiting = nil;
        show();
    });
}

// The fade is the list's layer's mask, which lies in its bounds, so it moves with the scrolling or the rows past the
// first screen would scroll out of it.
- (void)scrollViewDidScroll:(UIScrollView *)list {
    if (list != _list) return;
    [CATransaction begin];
    [CATransaction setDisableActions:YES];
    _listFade.frame = _list.bounds;
    if (_headRoom > 0) {
        CGFloat y = [self chipsY];
        _chipsRow.frame = CGRectMake(0, y, _chipsRow.frame.size.width, kChipHeight);
        [self placePinnedHeading];
        [self placeFade];
    }
    [CATransaction commit];
    if (_headRoom > 0) [self pushHead];
}

// Where a group's heading is held: just under the chips.
- (CGFloat)pinTop {
    return [self chipsY] + kChipHeight + 6;
}

// The group whose heading has gone up under the chips has it held there, as a list's headings stay at its top, until
// the next group's heading pushes it up and out (its owner, 2026-11-06: pin Continue Playing and Autoplay too).
- (void)placePinnedHeading {
    _pinnedBottom = 0;
    if (_headRoom <= 0 || !_groups.count || [self chipsY] > 0) {
        _pinnedClip.hidden = YES;
        return;
    }
    CGFloat top = [self pinTop], offset = _list.contentOffset.y, next = CGFLOAT_MAX;
    NSInteger section = -1;
    for (NSInteger i = 0; i < (NSInteger)_groups.count; i++) {
        CGFloat y = [_list rectForHeaderInSection:i].origin.y - offset + _list.frame.origin.y;
        if (y < top) section = i;
        else {
            next = y;
            break;
        }
    }
    if (section < 0) {
        _pinnedClip.hidden = YES;
        return;
    }
    SGRQueueGroup *group = _groups[(NSUInteger)section];
    NSString *key = [NSString stringWithFormat:@"%@\n%@", group.heading ?: @"", group.note ?: @""];
    CGFloat height = [self tableView:_list heightForHeaderInSection:section];
    if (!_pinnedClip) {
        _pinnedClip = [UIView new];
        _pinnedClip.clipsToBounds = YES;
        _pinnedClip.userInteractionEnabled = NO;
    }
    if (_pinnedClip.superview != self) [self insertSubview:_pinnedClip aboveSubview:_list];
    if (!_pinnedHeading || ![key isEqualToString:_pinnedKey]) {
        [_pinnedHeading removeFromSuperview];
        _pinnedHeading = [self tableView:_list viewForHeaderInSection:section];
        _pinnedHeading.userInteractionEnabled = NO;
        _pinnedKey = key;
        [_pinnedClip addSubview:_pinnedHeading];
    }
    // Pushed up by the next group's heading, it slides up under the chips' foot and is cut there, as the list's rows are
    // (its owner's recording, 2026-11-09: "Continue Playing" was left over the AutoMix chip).
    CGFloat y = MIN(top, next - height);
    _pinnedClip.frame = CGRectMake(0, top, self.bounds.size.width, height);
    _pinnedHeading.frame = CGRectMake(0, y - top, self.bounds.size.width, height);
    _pinnedClip.hidden = y + height <= top;
    _pinnedBottom = MAX(top, y + height);
}

- (void)scrollToTop {
    [_list setContentOffset:CGPointMake(0, [self historyHeight] - _list.adjustedContentInset.top) animated:NO];
}

- (void)showState:(SPTPlayerState *)state from:(NSString *)contextTitle {
    [self showState:state upcoming:nil from:contextTitle];
}

- (void)showState:(SPTPlayerState *)state upcoming:(NSArray *)upcoming from:(NSString *)contextTitle {
    if (!(_list.isTracking || _list.isDragging || _lifted)) [self showHistory:state];
    SPTPlayerOptions *options = [state respondsToSelector:@selector(options)] ? state.options : nil;
    _repeatContext = options.repeatingContext;
    [self syncCrossfade];
    // Spotify's own state for Shuffle and Repeat, animated when it changed while shown.
    // Off and dimmed while Spotify does not let them change (autoplay, radio), as its Connect menu shows them.
    BOOL shuffleAllowed = SGRSystemOptionAllowed(state, NO), repeatAllowed = SGRSystemOptionAllowed(state, YES);
    BOOL shuffling = shuffleAllowed && options.shufflingContext;
    NSInteger repeatMode = !repeatAllowed ? 0 : options.repeatingTrack ? 2 : options.repeatingContext ? 1 : 0;
    _shuffle.enabled = shuffleAllowed;
    _repeat.enabled = repeatAllowed;
    _shuffle.alpha = shuffleAllowed ? 1 : 0.4;
    _repeat.alpha = repeatAllowed ? 1 : 0.4;
    BOOL changed = shuffling != _shuffling || repeatMode != _repeatMode;
    _shuffling = shuffling;
    _repeatMode = repeatMode;
    if (changed || !_shuffle.backgroundColor) [self syncShuffleRepeatAnimated:changed];

    // The tracks to come, nearest first, in groups by where they came from, the groups in the order they meet.
    // The whole queue when Spotify has handed it over (upcoming), else the state's few tracks to come.
    // The state's few never stand in for the whole list already shown: Spotify's whole queue follows them each time.
    if (!upcoming.count && _upcoming) return;
    // Never laid out anew under a finger: a reload in the middle of a move drops the row being moved.
    if (_list.isTracking || _list.isDragging || _lifted) {
        __weak typeof(self) weakSelf = self;
        BOOL scheduled = _waiting != nil;
        _waiting = ^{ [weakSelf showState:state upcoming:upcoming from:contextTitle]; };
        if (!scheduled) [self showWaitingLater];
        return;
    }
    _waiting = nil;
    NSArray *future = upcoming.count ? upcoming : [state respondsToSelector:@selector(future)] ? state.future : nil;
    _upcoming = upcoming.count ? [upcoming copy] : nil;
    NSMutableArray<NSString *> *uris = [NSMutableArray array];
    NSMutableArray<SGRQueueGroup *> *groups = [NSMutableArray array];
    NSArray *items = [future isKindOfClass:NSArray.class] ? future : @[];
    for (NSUInteger place = 0; place < items.count; place++) {
        id item = items[place];
        if (!isTrack(item) || uris.count >= kMostTracks) continue;
        SPTPlayerTrack *track = item;
        [uris addObject:SGURIString(track.URI) ?: @""];
        NSString *provider = [track respondsToSelector:@selector(provider)] ? track.provider : nil;
        NSString *heading = [provider isEqualToString:@"queue"] ? @"Playing Next"
                          : [provider isEqualToString:@"autoplay"] ? @"Autoplay" : @"Continue Playing";
        SGRQueueGroup *group = groups.lastObject;
        if (![group.heading isEqualToString:heading]) {
            group = [SGRQueueGroup new];
            group.heading = heading;
            group.note = [heading isEqualToString:@"Continue Playing"] && contextTitle.length ? [@"From " stringByAppendingString:contextTitle]
                       : [heading isEqualToString:@"Autoplay"] ? @"Similar music" : nil;
            group.tracks = [NSMutableArray array];
            group.places = [NSMutableArray array];
            [groups addObject:group];
        }
        [group.tracks addObject:track];
        [group.places addObject:@(place)];
    }
    // The repeat note under the main group, as the Music app's "Repeating" line.
    SGRQueueGroup *main = nil;
    for (SGRQueueGroup *group in groups) if ([group.heading isEqualToString:@"Continue Playing"]) main = group;
    if (main && _repeatContext) main.note = main.note ? [main.note stringByAppendingString:@" · Repeating"] : @"Repeating";
    NSString *signature = [NSString stringWithFormat:@"%@|%@", [uris componentsJoinedByString:@","], main.note ?: @""];
    if ([signature isEqualToString:[_shownURIs componentsJoinedByString:@","]]) return;
    _shownURIs = @[signature];
    _groups = groups;
    [_list reloadData];
    [_list layoutIfNeeded];
    [self padForHistory];
    [self syncClear];
}

#pragma mark - UITableViewDataSource

- (NSInteger)numberOfSectionsInTableView:(UITableView *)table {
    return MAX(1, (NSInteger)_groups.count);
}

- (NSInteger)tableView:(UITableView *)table numberOfRowsInSection:(NSInteger)section {
    return section < (NSInteger)_groups.count ? (NSInteger)_groups[(NSUInteger)section].tracks.count : 0;
}

- (UITableViewCell *)tableView:(UITableView *)table cellForRowAtIndexPath:(NSIndexPath *)path {
    SGRQueueRow *row = [table dequeueReusableCellWithIdentifier:@"row" forIndexPath:path];
    SPTPlayerTrack *track = _groups[(NSUInteger)path.section].tracks[(NSUInteger)path.row];
    row.title.text = track.trackTitle;
    row.artist.text = track.artistName.length ? track.artistName : track.metadata[@"album_title"];
    row.accessibilityLabel = [NSString stringWithFormat:@"%@, %@", track.trackTitle ?: @"", row.artist.text ?: @""];
    NSString *uri = SGURIString(track.URI) ?: @"";
    row.coverFor = uri;
    row.grip.hidden = _upcoming == nil;
    row.alpha = _lifted && track == _liftedTrack ? 0 : 1;
    row.cover.image = nil;
    __weak SGRQueueRow *weakRow = row;
    SGRTrackPicture(track, ^(UIImage *image) {
        SGRQueueRow *shown = weakRow;
        if ([shown.coverFor isEqualToString:uri]) shown.cover.image = image;
    });
    return row;
}

#pragma mark - UITableViewDelegate

- (CGFloat)tableView:(UITableView *)table heightForHeaderInSection:(NSInteger)section {
    if (section >= (NSInteger)_groups.count) return 0;
    return _groups[(NSUInteger)section].note ? 52 : 36;
}

// The group's heading, bold, and its note under it, as the Music app's "Continue Playing / From …".
- (UIView *)tableView:(UITableView *)table viewForHeaderInSection:(NSInteger)section {
    if (section >= (NSInteger)_groups.count) return nil;
    SGRQueueGroup *group = _groups[(NSUInteger)section];
    UIView *header = [UIView new];
    UILabel *heading = [UILabel new], *note = [UILabel new];
    heading.font = SGRFont(UIFontTextStyleHeadline, UIFontWeightBold, UIContentSizeCategoryExtraExtraLarge);
    heading.textColor = SGRPrimary();
    heading.text = group.heading;
    note.font = SGRFont(UIFontTextStyleFootnote, UIFontWeightRegular, UIContentSizeCategoryExtraExtraLarge);
    note.textColor = SGRSecondary();
    note.text = group.note;
    CGFloat width = table.bounds.size.width - 2 * kSideMargin, headingHeight = ceil(heading.font.lineHeight);
    heading.frame = CGRectMake(kSideMargin, 6, width, headingHeight);
    note.frame = CGRectMake(kSideMargin, 6 + headingHeight, width, ceil(note.font.lineHeight));
    [header addSubview:heading];
    if (group.note) [header addSubview:note];
    header.accessibilityElements = group.note ? @[heading, note] : @[heading];
    return header;
}

#pragma mark - moving tracks

- (BOOL)tableView:(UITableView *)table canMoveRowAtIndexPath:(NSIndexPath *)path {
    return _upcoming != nil;
}

// Within its own group only: a track keeps where it came from (the hand queue, the album or playlist, autoplay).
- (NSIndexPath *)tableView:(UITableView *)table targetIndexPathForMoveFromRowAtIndexPath:(NSIndexPath *)from
       toProposedIndexPath:(NSIndexPath *)to {
    if (to.section == from.section) return to;
    NSInteger last = (NSInteger)_groups[(NSUInteger)from.section].tracks.count - 1;
    return [NSIndexPath indexPathForRow:to.section < from.section ? 0 : MAX(0, last) inSection:from.section];
}

- (void)tableView:(UITableView *)table moveRowAtIndexPath:(NSIndexPath *)from toIndexPath:(NSIndexPath *)to {
    [self moveTrackFrom:from to:to];
}

// The track at `from` moved to `to` in its group and in the whole list, both or neither: every place is checked before
// anything changes, so the rows and _upcoming never disagree (the review, 2026-11-04). NO when nothing moved.
- (BOOL)moveTrackFrom:(NSIndexPath *)from to:(NSIndexPath *)to {
    if (!_upcoming || from.section != to.section || [from isEqual:to] || from.section < 0 || (NSUInteger)from.section >= _groups.count) return NO;
    SGRQueueGroup *group = _groups[(NSUInteger)from.section];
    NSMutableArray<SPTPlayerTrack *> *tracks = group.tracks;
    NSUInteger count = MIN(tracks.count, group.places.count);
    if (from.row < 0 || to.row < 0 || (NSUInteger)from.row >= count || (NSUInteger)to.row >= count) return NO;
    // Its place in the whole list, and the place of the track it lands on (the list may hold more than tracks).
    NSUInteger fromIndex = group.places[(NSUInteger)from.row].unsignedIntegerValue;
    NSUInteger toIndex = group.places[(NSUInteger)to.row].unsignedIntegerValue;
    NSMutableArray *whole = [_upcoming mutableCopy];
    if (fromIndex >= whole.count || toIndex >= whole.count) return NO;
    SPTPlayerTrack *moved = tracks[(NSUInteger)from.row];
    [tracks removeObjectAtIndex:(NSUInteger)from.row];
    [tracks insertObject:moved atIndex:(NSUInteger)to.row];
    id item = whole[fromIndex];
    [whole removeObjectAtIndex:fromIndex];
    [whole insertObject:item atIndex:toIndex];
    _upcoming = [whole copy];
    [self renumberPlaces];
    _shownURIs = nil;
    if (!_quietMoves && self.onReorder) self.onReorder(_upcoming);
    return YES;
}

// The places anew: the tracks in the whole list's order, handed out to the rows in theirs.
- (void)renumberPlaces {
    NSArray *whole = _upcoming;
    NSUInteger g = 0, row = 0, shown = 0;
    for (NSUInteger place = 0; place < whole.count && g < _groups.count; place++) {
        if (!isTrack(whole[place]) || shown >= kMostTracks) continue;
        shown++;
        while (g < _groups.count && row >= _groups[g].places.count) { g++; row = 0; }
        if (g < _groups.count) _groups[g].places[row++] = @(place);
    }
}

#pragma mark - moving by the grip

// The card under the finger, held inside its group's rows and inside the part of the list that shows; the list scrolled
// while the finger is near its top or foot, faster the further in; and the rows moved round the card.
- (void)followDrag {
    if (!_lifted) return;
    CGPoint finger = _dragPoint;
    NSInteger section = _liftedAt.section;
    NSInteger rows = [_list numberOfRowsInSection:section];
    if (rows <= 0) return;
    CGRect list = _list.frame;
    CGFloat top = CGRectGetMinY(list) + kListTopFade / 2, foot = CGRectGetMaxY(list) - _controlsCover - kListFootFade / 2;
    CGFloat zone = 44, step = 0;
    if (finger.y < top + zone) step = -MIN(7, 1 + (top + zone - finger.y) / 8);
    else if (finger.y > foot - zone) step = MIN(7, 1 + (finger.y - foot + zone) / 8);
    if (step) {
        // No further than the group's own first and last rows: past them the card can't follow (its owner, 2026-11-03).
        CGFloat groupTop = CGRectGetMinY([_list rectForRowAtIndexPath:[NSIndexPath indexPathForRow:0 inSection:section]]);
        CGFloat groupFoot = CGRectGetMaxY([_list rectForRowAtIndexPath:[NSIndexPath indexPathForRow:rows - 1 inSection:section]]);
        CGFloat minY = MAX(-_list.adjustedContentInset.top, groupTop - (top - CGRectGetMinY(list)));
        CGFloat maxY = MIN(_list.contentSize.height + _list.adjustedContentInset.bottom - _list.bounds.size.height,
                           groupFoot - (foot - CGRectGetMinY(list)));
        CGFloat now = _list.contentOffset.y;
        CGFloat offset = step < 0 ? MAX(now + step, MIN(now, minY)) : MIN(now + step, MAX(now, maxY));
        if (offset != now) _list.contentOffset = CGPointMake(0, offset);
    }
    CGFloat half = _lifted.bounds.size.height / 2;
    CGFloat firstMid = [_list convertPoint:CGPointMake(0, CGRectGetMidY([_list rectForRowAtIndexPath:[NSIndexPath indexPathForRow:0 inSection:section]])) toView:self].y;
    CGFloat lastMid = [_list convertPoint:CGPointMake(0, CGRectGetMidY([_list rectForRowAtIndexPath:[NSIndexPath indexPathForRow:rows - 1 inSection:section]])) toView:self].y;
    CGFloat y = finger.y - _liftOffset;
    y = MIN(MAX(y, top + half), MAX(top + half, foot - half));
    y = MIN(MAX(y, firstMid), lastMid);
    _lifted.center = CGPointMake(_lifted.center.x, y);
    NSIndexPath *target = [_list indexPathForRowAtPoint:[self convertPoint:CGPointMake(CGRectGetMidX(self.bounds), y) toView:_list]];
    if (!target || target.section != section || [target isEqual:_liftedAt]) return;
    _quietMoves = YES;
    BOOL moved = [self moveTrackFrom:_liftedAt to:target];
    _quietMoves = NO;
    if (!moved) return;
    // The place first: UIKit draws rows anew during the move, and the lifted one must already be known there.
    NSIndexPath *was = _liftedAt;
    _liftedAt = target;
    [_list moveRowAtIndexPath:was toIndexPath:target];
    [_list cellForRowAtIndexPath:target].alpha = 0;
    [UISelectionFeedbackGenerator.new selectionChanged];
}

- (void)dragTicked:(CADisplayLink *)link {
    if (!_lifted || !self.window) {
        [link invalidate];
        if (link == _dragLink) _dragLink = nil;
        return;
    }
    [self followDrag];
}

// Only a press on a movable row's grip: the rest of the row scrolls, taps and swipes as before.
- (BOOL)gestureRecognizerShouldBegin:(UIGestureRecognizer *)recognizer {
    if (!_upcoming) return NO;
    CGPoint point = [recognizer locationInView:_list];
    NSIndexPath *path = [_list indexPathForRowAtPoint:point];
    SGRQueueRow *row = path ? (SGRQueueRow *)[_list cellForRowAtIndexPath:path] : nil;
    if (![row isKindOfClass:SGRQueueRow.class] || row.grip.hidden) return NO;
    CGRect grip = [row.grip convertRect:CGRectInset(row.grip.bounds, -8, 0) toView:_list];
    return CGRectContainsPoint(grip, point);
}

- (void)reordered:(UILongPressGestureRecognizer *)press {
    CGPoint point = [press locationInView:_list];
    switch (press.state) {
        case UIGestureRecognizerStateBegan: {
            NSIndexPath *path = [_list indexPathForRowAtPoint:point];
            UITableViewCell *cell = path ? [_list cellForRowAtIndexPath:path] : nil;
            if (!cell) return;
            // The row's picture on a thin blur, the Music app's lifted row (its owner, 2026-11-02): the rows under it show
            // through softened, with a light tint over them.
            // Over the list rather than in it: in it, the card scrolled with the rows and went under the list's top fade
            // and the chips when dragged up (its owner's recordings, 2026-11-03); over it, it stays under the finger
            // inside the part of the list that shows, while the rows run beneath.
            UIView *picture = [[UIView alloc] initWithFrame:[_list convertRect:cell.frame toView:self]];
            picture.layer.shadowColor = UIColor.blackColor.CGColor;
            picture.layer.shadowOpacity = 0.3;
            picture.layer.shadowRadius = 10;
            picture.layer.shadowOffset = CGSizeMake(0, 4);
            UIVisualEffectView *blur = [[UIVisualEffectView alloc] initWithEffect:[UIBlurEffect effectWithStyle:UIBlurEffectStyleSystemUltraThinMaterialDark]];
            blur.frame = picture.bounds;
            blur.layer.cornerRadius = 10;
            blur.layer.cornerCurve = kCACornerCurveContinuous;
            blur.clipsToBounds = YES;
            blur.contentView.backgroundColor = [UIColor colorWithWhite:1 alpha:0.06];
            [picture addSubview:blur];
            UIView *content = [cell snapshotViewAfterScreenUpdates:NO];
            content.frame = picture.bounds;
            [picture addSubview:content];
            [self insertSubview:picture aboveSubview:_list];
            _lifted = picture;
            _liftedAt = _liftedFrom = path;
            _liftedTrack = _groups[(NSUInteger)path.section].tracks[(NSUInteger)path.row];
            _liftOffset = [press locationInView:self].y - picture.center.y;
            cell.alpha = 0;
            [UISelectionFeedbackGenerator.new selectionChanged];
            SGRAnimate(SGRMotionPress, ^{ picture.transform = CGAffineTransformMakeScale(1.02, 1.02); }, nil);
            if (self.onDragging) self.onDragging(YES);
            _dragPoint = [press locationInView:self];
            // The list scrolls on under a finger held still near its top or foot, every frame, not only as it moves.
            [_dragLink invalidate];
            _dragLink = [CADisplayLink displayLinkWithTarget:self selector:@selector(dragTicked:)];
            _dragLink.preferredFrameRateRange = CAFrameRateRangeMake(60, 120, 120);
            [_dragLink addToRunLoop:NSRunLoop.mainRunLoop forMode:NSRunLoopCommonModes];
            break;
        }
        case UIGestureRecognizerStateChanged: {
            if (!_lifted) return;
            _dragPoint = [press locationInView:self];
            [self followDrag];
            break;
        }
        case UIGestureRecognizerStateEnded:
        case UIGestureRecognizerStateCancelled:
        case UIGestureRecognizerStateFailed: {
            [_dragLink invalidate];
            _dragLink = nil;
            UIView *picture = _lifted;
            if (!picture) return;
            NSIndexPath *at = _liftedAt;
            BOOL moved = ![at isEqual:_liftedFrom];
            _lifted = nil;
            _liftedTrack = nil;
            UITableViewCell *cell = [_list cellForRowAtIndexPath:at];
            CGRect home = [_list convertRect:[_list rectForRowAtIndexPath:at] toView:self];
            SGRAnimate(SGRMotionLayout, ^{
                picture.transform = CGAffineTransformIdentity;
                picture.center = CGPointMake(CGRectGetMidX(home), CGRectGetMidY(home));
                picture.layer.shadowOpacity = 0;
            }, ^(BOOL finished) {
                cell.alpha = 1;
                [picture removeFromSuperview];
            });
            if (self.onDragging) self.onDragging(NO);
            if (moved && self.onReorder) self.onReorder(_upcoming);
            break;
        }
        default:
            break;
    }
}

#pragma mark - clearing the queue

// Every track queued by hand (the Playing Next group) out at once, the Music app's Clear (its owner, 2026-11-02).
- (void)clearQueued {
    if (!_upcoming) return;
    NSUInteger index = NSNotFound;
    for (NSUInteger i = 0; i < _groups.count; i++) if ([_groups[i].heading isEqualToString:@"Playing Next"]) index = i;
    if (index == NSNotFound) return;
    NSMutableIndexSet *places = [NSMutableIndexSet indexSet];
    for (NSNumber *place in _groups[index].places) [places addIndex:place.unsignedIntegerValue];
    NSMutableArray *whole = [_upcoming mutableCopy];
    [places enumerateIndexesWithOptions:NSEnumerationReverse usingBlock:^(NSUInteger place, BOOL *stop) {
        if (place < whole.count) [whole removeObjectAtIndex:place];
    }];
    _upcoming = [whole copy];
    NSMutableArray<SGRQueueGroup *> *groups = [_groups mutableCopy];
    [groups removeObjectAtIndex:index];
    _groups = groups;
    [self renumberPlaces];
    _shownURIs = nil;
    if (_groups.count) [_list deleteSections:[NSIndexSet indexSetWithIndex:index] withRowAnimation:UITableViewRowAnimationFade];
    else [_list reloadData];
    [_list layoutIfNeeded];
    [self padForHistory];
    [self syncClear];
    if (self.onReorder) self.onReorder(_upcoming);
}

#pragma mark - removing tracks

// A track taken out of what is to come (its owner, 2026-11-02): out of the whole list, handed back to Spotify as a move
// is (onReorder, setQueue:), and its row out of the list at once. A group left empty goes with its heading.
- (void)removeRowAt:(NSIndexPath *)path {
    if (!_upcoming || (NSUInteger)path.section >= _groups.count) return;
    SGRQueueGroup *group = _groups[(NSUInteger)path.section];
    if ((NSUInteger)path.row >= group.tracks.count) return;
    NSUInteger place = group.places[(NSUInteger)path.row].unsignedIntegerValue;
    NSMutableArray *whole = [_upcoming mutableCopy];
    if (place >= whole.count) return;
    [whole removeObjectAtIndex:place];
    _upcoming = [whole copy];
    [group.tracks removeObjectAtIndex:(NSUInteger)path.row];
    [group.places removeObjectAtIndex:(NSUInteger)path.row];
    BOOL emptied = group.tracks.count == 0;
    if (emptied) {
        NSMutableArray<SGRQueueGroup *> *groups = [_groups mutableCopy];
        [groups removeObjectAtIndex:(NSUInteger)path.section];
        _groups = groups;
    }
    [self renumberPlaces];
    _shownURIs = nil;
    // The last group gone, the list is drawn again whole: a reload may not run inside a batch of updates.
    if (emptied && !_groups.count) [_list reloadData];
    else if (emptied) [_list deleteSections:[NSIndexSet indexSetWithIndex:(NSUInteger)path.section] withRowAnimation:UITableViewRowAnimationFade];
    else [_list deleteRowsAtIndexPaths:@[path] withRowAnimation:UITableViewRowAnimationFade];
    [self padForHistory];
    [self syncClear];
    if (self.onReorder) self.onReorder(_upcoming);
}

// Where a track's row is now, by the track itself; nil once it has gone.
- (NSIndexPath *)placeOfTrack:(SPTPlayerTrack *)track {
    if (!track) return nil;
    for (NSUInteger section = 0; section < _groups.count; section++) {
        NSUInteger row = [_groups[section].tracks indexOfObjectIdenticalTo:track];
        if (row != NSNotFound) return [NSIndexPath indexPathForRow:(NSInteger)row inSection:(NSInteger)section];
    }
    return nil;
}

// A swipe to the left, as the Music app's queue has: Remove.
- (UISwipeActionsConfiguration *)tableView:(UITableView *)table trailingSwipeActionsConfigurationForRowAtIndexPath:(NSIndexPath *)path {
    if (!_upcoming) return nil;
    if ((NSUInteger)path.section >= _groups.count || (NSUInteger)path.row >= _groups[(NSUInteger)path.section].tracks.count) return nil;
    __weak typeof(self) weakSelf = self;
    // The track itself, found again at the tap: the list can be drawn anew while the button shows, and the row's place
    // then holds another track.
    __weak SPTPlayerTrack *track = _groups[(NSUInteger)path.section].tracks[(NSUInteger)path.row];
    // A round red button with a minus, the Music app's (its owner's recording, 2026-11-02): the glyph alone, no title.
    UIContextualAction *remove = [UIContextualAction contextualActionWithStyle:UIContextualActionStyleDestructive title:nil
                                                                       handler:^(UIContextualAction *action, UIView *view, void (^done)(BOOL)) {
        NSIndexPath *now = [weakSelf placeOfTrack:track];
        if (now) [weakSelf removeRowAt:now];
        done(now != nil);
    }];
    // The Music app's: a white disc with the minus cut through it, on the red (its owner's screenshot, 2026-11-02).
    remove.image = [UIImage systemImageNamed:@"minus.circle.fill" withConfiguration:[UIImageSymbolConfiguration configurationWithPointSize:22 weight:UIImageSymbolWeightSemibold]];
    remove.backgroundColor = UIColor.systemRedColor;
    remove.accessibilityLabel = @"Remove";
    UISwipeActionsConfiguration *config = [UISwipeActionsConfiguration configurationWithActions:@[remove]];
    config.performsFirstActionWithFullSwipe = YES;
    return config;
}

- (UIView *)tableView:(UITableView *)table viewForFooterInSection:(NSInteger)section {
    return [UIView new];
}

- (void)tableView:(UITableView *)table didSelectRowAtIndexPath:(NSIndexPath *)path {
    [table deselectRowAtIndexPath:path animated:YES];
    SPTPlayerTrack *track = _groups[(NSUInteger)path.section].tracks[(NSUInteger)path.row];
    if (self.onPick) self.onPick(track);
}

@end
