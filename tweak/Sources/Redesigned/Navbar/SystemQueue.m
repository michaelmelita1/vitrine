#import "SystemQueue.h"
#import "Core/SGCore.h"
#import "Headers/SPTPlayer.h"
#import "Redesigned/Kit/SGRKit.h"
#import "Shared/AutoMix/AutoMix.h"

// The chips' height and gap, the rows' height, cover side and corners, and the most tracks shown (the player reports
// far more ahead on a long playlist; the Music app's list is a look ahead too).
static const CGFloat kChipHeight = 34, kChipGap = 10, kChipsBelow = 14, kRowHeight = 56, kRowCover = 44, kRowCoverRadius = 6;
static const CGFloat kSideMargin = 28, kListTopFade = 18;
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
@end

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
    for (UIView *view in @[_cover, _title, _artist]) [self.contentView addSubview:view];
    return self;
}

- (void)layoutSubviews {
    [super layoutSubviews];
    CGSize size = self.contentView.bounds.size;
    _cover.frame = CGRectMake(kSideMargin, round((size.height - kRowCover) / 2), kRowCover, kRowCover);
    CGFloat textX = CGRectGetMaxX(_cover.frame) + 12, textWidth = MAX(0, size.width - kSideMargin - textX);
    CGFloat titleHeight = ceil(_title.font.lineHeight), artistHeight = ceil(_artist.font.lineHeight);
    CGFloat top = round((size.height - titleHeight - artistHeight) / 2);
    _title.frame = CGRectMake(textX, top, textWidth, titleHeight);
    _artist.frame = CGRectMake(textX, top + titleHeight, textWidth, artistHeight);
}

@end

#pragma mark - the queue

@interface SGRSystemQueueView () <UITableViewDataSource, UITableViewDelegate>
@end

@implementation SGRSystemQueueView {
    UIButton *_automix;   // one chip, three states as repeat has: off, AutoMix (beat-matched), Crossfade
    UIButton *_shuffle, *_repeat;   // shown while the controls have them hidden (showsShuffle, showsRepeat)
    BOOL _shuffling;
    NSInteger _repeatMode;          // 0 off, 1 the playlist or album, 2 the track
    UITableView *_list;
    CAGradientLayer *_listFade;
    NSArray<SGRQueueGroup *> *_groups;
    NSArray<NSString *> *_shownURIs;   // the tracks last shown, so the same queue again is not laid out again
    NSArray *_upcoming;                // Spotify's whole list of tracks to come, when shown from it; nil from the state
    void (^_waiting)(void);            // a new list held back while a finger is on the list (a track being moved)
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
    _list.estimatedSectionFooterHeight = 10;
    _list.backgroundColor = UIColor.clearColor;
    _list.separatorStyle = UITableViewCellSeparatorStyleNone;
    _list.rowHeight = kRowHeight;
    _list.sectionHeaderTopPadding = 0;
    _list.dataSource = self;
    _list.delegate = self;
    _list.showsVerticalScrollIndicator = NO;
    // Always in reordering, as the Music app's queue has its grips out; a tap still plays the track.
    _list.editing = YES;
    _list.allowsSelectionDuringEditing = YES;
    _list.contentInset = UIEdgeInsetsMake(kListTopFade / 2, 0, 12, 0);
    [_list registerClass:SGRQueueRow.class forCellReuseIdentifier:@"row"];
    // No gap of the grouped style's own over the first group.
    _list.tableHeaderView = [[UIView alloc] initWithFrame:CGRectMake(0, 0, 0, CGFLOAT_MIN)];
    // The list fades out at its top edge, under the chips, as the lyrics' lines do at theirs.
    _listFade = [CAGradientLayer layer];
    _listFade.colors = @[(id)UIColor.clearColor.CGColor, (id)UIColor.blackColor.CGColor, (id)UIColor.blackColor.CGColor];
    _list.layer.mask = _listFade;
    _shuffle = [self chipWithImage:chipSymbol(@"shuffle") title:@"Shuffle"];
    _repeat = [self chipWithImage:chipSymbol(@"repeat") title:@"Repeat"];
    _shuffle.hidden = _repeat.hidden = YES;
    [_shuffle addAction:[UIAction actionWithHandler:^(UIAction *action) { [weakSelf stepShuffle]; }]
       forControlEvents:UIControlEventTouchUpInside];
    [_repeat addAction:[UIAction actionWithHandler:^(UIAction *action) { [weakSelf stepRepeat]; }]
      forControlEvents:UIControlEventTouchUpInside];
    for (UIView *view in @[_list, _automix, _shuffle, _repeat]) [self addSubview:view];
    [self syncCrossfade];
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

// The Music app's AutoMix symbol (its owner's screenshot, 2026-11-02): a ring overlapping a filled disc with a hole in
// its middle. Drawn once, a template.
static UIImage *automixGlyph(void) {
    static UIImage *glyph;
    if (glyph) return glyph;
    CGSize size = CGSizeMake(26, 16);
    UIGraphicsImageRenderer *renderer = [[UIGraphicsImageRenderer alloc] initWithSize:size];
    glyph = [[renderer imageWithActions:^(UIGraphicsImageRendererContext *context) {
        CGFloat d = 14, y = 1, line = 2.6;
        [UIColor.blackColor set];
        UIBezierPath *ring = [UIBezierPath bezierPathWithOvalInRect:CGRectInset(CGRectMake(1, y, d, d), line / 2, line / 2)];
        ring.lineWidth = line;
        [ring stroke];
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
    if (swaps) {
        void (^swap)(void) = ^{
            [chip setImage:image forState:UIControlStateNormal];
            [chip setTitle:title forState:UIControlStateNormal];
        };
        if (moves) [UIView transitionWithView:chip duration:SGRCrossfade options:UIViewAnimationOptionTransitionCrossDissolve | UIViewAnimationOptionAllowUserInteraction
                                   animations:swap completion:nil];
        else [UIView performWithoutAnimation:swap];
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
    [self syncShuffleRepeatAnimated:NO];
    [self setNeedsLayout];
}

// The tap shows the next state at once, as Spotify's own buttons do; Spotify's state confirms it (showState:).
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
        SGLog(@"system player: queue turned AutoMix on, beat-matched");
    } else if (SGAutoMixCurrentStyle() == SGAutoMixBeatMatched) {
        SGAutoMixSetStyle(SGAutoMixCrossfade);
        SGLog(@"system player: queue turned AutoMix to crossfade");
    } else {
        SGSetEnabled(SGKeyAutoMix, NO);
        SGAutoMixApply(NO);
        SGLog(@"system player: queue turned AutoMix off");
    }
    [self syncAutoMixAnimated:YES];
}

- (void)layoutSubviews {
    [super layoutSubviews];
    CGSize size = self.bounds.size;
    // The chips shown share the row equally, kChipGap apart: Shuffle, Repeat, then AutoMix, the Music app's order.
    NSMutableArray<UIView *> *chips = [NSMutableArray array];
    if (_showsShuffle) [chips addObject:_shuffle];
    if (_showsRepeat) [chips addObject:_repeat];
    [chips addObject:_automix];
    CGFloat chipWidth = MAX(0, (size.width - 2 * kSideMargin - kChipGap * (chips.count - 1)) / chips.count);
    [chips enumerateObjectsUsingBlock:^(UIView *chip, NSUInteger i, BOOL *stop) {
        chip.bounds = CGRectMake(0, 0, chipWidth, kChipHeight);
        chip.center = CGPointMake(kSideMargin + i * (chipWidth + kChipGap) + chipWidth / 2, kChipHeight / 2);
    }];
    CGFloat listTop = kChipHeight + kChipsBelow - kListTopFade / 2;
    _list.frame = CGRectMake(0, listTop, size.width, MAX(0, size.height - listTop));
    [CATransaction begin];
    [CATransaction setDisableActions:YES];
    _listFade.frame = _list.bounds;
    CGFloat edge = _list.bounds.size.height > 0 ? MIN(0.3, kListTopFade / _list.bounds.size.height) : 0;
    _listFade.locations = @[@0, @(edge), @1];
    [CATransaction commit];
}

// The list held back under a finger, shown once the finger is off.
- (void)showWaitingLater {
    __weak typeof(self) weakSelf = self;
    dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(0.25 * NSEC_PER_SEC)), dispatch_get_main_queue(), ^{
        typeof(self) me = weakSelf;
        if (!me || !me->_waiting) return;
        if (me->_list.isTracking || me->_list.isDragging) { [me showWaitingLater]; return; }
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
    [CATransaction commit];
}

- (void)scrollToTop {
    [_list setContentOffset:CGPointMake(0, -_list.adjustedContentInset.top) animated:NO];
}

- (void)showState:(SPTPlayerState *)state from:(NSString *)contextTitle {
    [self showState:state upcoming:nil from:contextTitle];
}

- (void)showState:(SPTPlayerState *)state upcoming:(NSArray *)upcoming from:(NSString *)contextTitle {
    SPTPlayerOptions *options = [state respondsToSelector:@selector(options)] ? state.options : nil;
    _repeatContext = options.repeatingContext;
    [self syncCrossfade];
    // Spotify's own state for Shuffle and Repeat, animated when it changed while shown.
    BOOL shuffling = options.shufflingContext;
    NSInteger repeatMode = options.repeatingTrack ? 2 : options.repeatingContext ? 1 : 0;
    BOOL changed = shuffling != _shuffling || repeatMode != _repeatMode;
    _shuffling = shuffling;
    _repeatMode = repeatMode;
    if (changed || !_shuffle.backgroundColor) [self syncShuffleRepeatAnimated:changed];

    // The tracks to come, nearest first, in groups by where they came from, the groups in the order they meet.
    // The whole queue when Spotify has handed it over (upcoming), else the state's few tracks to come.
    // The state's few never stand in for the whole list already shown: Spotify's whole queue follows them each time.
    if (!upcoming.count && _upcoming) return;
    // Never laid out anew under a finger: a reload in the middle of a move drops the row being moved.
    if (_list.isTracking || _list.isDragging) {
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

- (UITableViewCellEditingStyle)tableView:(UITableView *)table editingStyleForRowAtIndexPath:(NSIndexPath *)path {
    return UITableViewCellEditingStyleNone;
}

- (BOOL)tableView:(UITableView *)table shouldIndentWhileEditingRowAtIndexPath:(NSIndexPath *)path {
    return NO;
}

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
    if (!_upcoming || from.section != to.section || [from isEqual:to]) return;
    SGRQueueGroup *group = _groups[(NSUInteger)from.section];
    NSMutableArray<SPTPlayerTrack *> *tracks = group.tracks;
    // Its place in the whole list, and the place of the track it lands on (the list may hold more than tracks).
    NSUInteger fromIndex = group.places[(NSUInteger)from.row].unsignedIntegerValue;
    NSUInteger toIndex = group.places[(NSUInteger)to.row].unsignedIntegerValue;
    SPTPlayerTrack *moved = tracks[(NSUInteger)from.row];
    [tracks removeObjectAtIndex:(NSUInteger)from.row];
    [tracks insertObject:moved atIndex:(NSUInteger)to.row];
    NSMutableArray *whole = [_upcoming mutableCopy];
    if (fromIndex >= whole.count || toIndex >= whole.count) return;
    id item = whole[fromIndex];
    [whole removeObjectAtIndex:fromIndex];
    [whole insertObject:item atIndex:toIndex];
    _upcoming = [whole copy];
    // The places anew: the tracks in the whole list's order, handed out to the rows in theirs.
    NSUInteger g = 0, row = 0, shown = 0;
    for (NSUInteger place = 0; place < whole.count && g < _groups.count; place++) {
        if (!isTrack(whole[place]) || shown >= kMostTracks) continue;
        shown++;
        while (g < _groups.count && row >= _groups[g].places.count) { g++; row = 0; }
        if (g < _groups.count) _groups[g].places[row++] = @(place);
    }
    _shownURIs = nil;
    if (self.onReorder) self.onReorder(_upcoming);
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
