// Speed and pitch's sliders, the playback speed and the pitch (SpeedPitch.x applies them), in a popover the player
// page's ⋯ opens (Redesigned/Player/PlayerMenu.m, SGPlayerShowSpeedPitchPanel). The block is drawn from its own
// measures and type, not from the redesign's Kit. Speed and pitch last until Spotify quits.
#import <CoreText/SFNTLayoutTypes.h>
#import <objc/runtime.h>
#import "Core/SGCore.h"
#import "Settings/SGPageStyle.h"
#import "Shared/AudioEffects/AudioEffects.h"
#import "Shared/Haptics/Haptics.h"
#import "SpeedPitch.h"

static const CGFloat kRowHeight = 56, kSliderBlockHeight = 72, kSwitchRowHeight = 44, kPanelBottom = 12;
// The block's own measures and type, so it stands on Spotify's sheet under either look rather than on
// the redesign's Kit: the sheet's side margin, the gap everything else is a multiple of, and a spring
// that settles without overshooting.
static const CGFloat kSideMargin = 16, kGrid = 8;
static const NSTimeInterval kOpenDuration = 0.45;

static UIColor *primary(void) {
    return UIColor.whiteColor;
}

// White at the weight the sheet's own secondary text is, a step firmer with Increase Contrast.
static UIColor *secondary(void) {
    return [UIColor colorWithWhite:1 alpha:UIAccessibilityDarkerSystemColorsEnabled() ? 0.80 : 0.65];
}

// The system font at a text style's size, which stops growing past `largest` so the row still fits.
static UIFont *font(UIFontTextStyle style, UIFontWeight weight, UIContentSizeCategory largest) {
    UIContentSizeCategory current = UIApplication.sharedApplication.preferredContentSizeCategory;
    if (largest && UIContentSizeCategoryCompareToCategory(current, largest) == NSOrderedDescending) current = largest;
    UITraitCollection *traits = [UITraitCollection traitCollectionWithPreferredContentSizeCategory:current];
    CGFloat size = [UIFont preferredFontForTextStyle:style compatibleWithTraitCollection:traits].pointSize;
    return [UIFont systemFontOfSize:size weight:weight];
}

// Digits of one width, so a value does not shuffle as it counts.
static UIFont *monospacedDigits(UIFont *base) {
    if (!base) return nil;
    NSArray *features = @[@{UIFontFeatureTypeIdentifierKey: @(kNumberSpacingType), UIFontFeatureSelectorIdentifierKey: @(kMonospacedNumbersSelector)}];
    UIFontDescriptor *descriptor = [base.fontDescriptor fontDescriptorByAddingAttributes:@{UIFontDescriptorFeatureSettingsAttribute: features}];
    return [UIFont fontWithDescriptor:descriptor size:base.pointSize];
}

static void animateOpen(void (^animations)(void), void (^completion)(BOOL finished)) {
    if (UIAccessibilityIsReduceMotionEnabled()) {
        [UIView performWithoutAnimation:animations];
        if (completion) completion(YES);
        return;
    }
    [UIView animateWithDuration:kOpenDuration delay:0 usingSpringWithDamping:1 initialSpringVelocity:0
                        options:UIViewAnimationOptionAllowUserInteraction | UIViewAnimationOptionBeginFromCurrentState
                     animations:animations completion:completion];
}
static const float kMinSpeed = 0.5f, kMaxSpeed = 2, kSpeedStep = 0.05f;
static const float kMaxPitch = 12;
// Speed is applied at most this often while the slider moves.
static const NSTimeInterval kSpeedInterval = 0.05;

static BOOL sg_open;

#pragma mark - the block

@interface SGSpeedPitchView : UIView
@property (nonatomic, weak) UITableView *table;
@property (nonatomic) BOOL inFooter;
// The sliders alone, always open, for the redesign's panel under the ⋯ (SGPlayerShowSpeedPitchPanel).
@property (nonatomic) BOOL panelOnly;
@end

@implementation SGSpeedPitchView {
    UIControl *_row;
    UIImageView *_icon, *_chevron;
    UILabel *_title, *_summary;
    UIView *_panel;
    UILabel *_speedName, *_pitchName, *_reverbName;
    UIButton *_speedValue, *_pitchValue, *_reverbValue;
    UISlider *_speed, *_pitch, *_reverb;
    UILabel *_followsName;
    UISwitch *_follows;
    float _shownSpeed, _shownPitch, _shownReverb;
    NSTimeInterval _speedSentAt;
    BOOL _speedPending;
}

static UIImage *symbol(NSString *name, CGFloat size, UIImageSymbolWeight weight) {
    return [UIImage systemImageNamed:name withConfiguration:[UIImageSymbolConfiguration configurationWithPointSize:size weight:weight]];
}

// A glyph with its color drawn in, so it never passes through a tint on its way to the screen.
static UIImage *paintedSymbol(NSString *name, CGFloat size, UIImageSymbolWeight weight, UIColor *color) {
    return [symbol(name, size, weight) imageWithTintColor:color renderingMode:UIImageRenderingModeAlwaysOriginal];
}

static UILabel *makeLabel(UIFont *font, UIColor *color) {
    UILabel *label = [UILabel new];
    label.font = font;
    label.textColor = color;
    label.adjustsFontForContentSizeCategory = NO;
    return label;
}

- (UIButton *)valueButton:(SEL)reset {
    UIButton *button = [UIButton buttonWithType:UIButtonTypeSystem];
    button.titleLabel.font = monospacedDigits(font(UIFontTextStyleSubheadline, UIFontWeightSemibold, UIContentSizeCategoryExtraLarge));
    button.tintColor = primary();
    [button setTitleColor:primary() forState:UIControlStateNormal];
    [button setTitleColor:[primary() colorWithAlphaComponent:0.4] forState:UIControlStateHighlighted];
    [button setTitleColor:primary() forState:UIControlStateDisabled];
    button.contentHorizontalAlignment = UIControlContentHorizontalAlignmentRight;
    button.accessibilityHint = @"Resets it";
    [button addTarget:self action:reset forControlEvents:UIControlEventTouchUpInside];
    return button;
}

// A glyph centered in a box of one size, so both sliders' tracks start and end at the same x.
static UIImage *endImage(NSString *name, CGFloat size) {
    UIImage *glyph = paintedSymbol(name, size, UIImageSymbolWeightMedium, secondary());
    CGSize box = CGSizeMake(24, 24);
    return [[[UIGraphicsImageRenderer alloc] initWithSize:box] imageWithActions:^(UIGraphicsImageRendererContext *context) {
        [glyph drawAtPoint:CGPointMake((box.width - glyph.size.width) / 2, (box.height - glyph.size.height) / 2)];
    }];
}

// Both sliders have their normal in the middle of the range rather than at one end, so neither track
// fills: a tick marks where normal is, under the thumb until it moves away.
- (UISlider *)slider:(float)min max:(float)max normal:(float)normal minImage:(NSString *)minImage maxImage:(NSString *)maxImage {
    UISlider *slider = [UISlider new];
    slider.minimumValue = min;
    slider.maximumValue = max;
    UIColor *track = [UIColor colorWithWhite:1 alpha:0.2];
    slider.minimumTrackTintColor = track;
    slider.maximumTrackTintColor = track;
    slider.minimumValueImage = endImage(minImage, 13);
    slider.maximumValueImage = endImage(maxImage, 17);
    UIView *tick = [UIView new];
    tick.backgroundColor = secondary();
    tick.layer.cornerRadius = 1;
    tick.userInteractionEnabled = NO;
    tick.tag = (NSInteger)(normal * 1000);
    [slider insertSubview:tick atIndex:0];
    [slider addTarget:self action:@selector(sliderMoved:) forControlEvents:UIControlEventValueChanged];
    [slider addTarget:self action:@selector(sliderReleased:) forControlEvents:UIControlEventTouchUpInside | UIControlEventTouchUpOutside | UIControlEventTouchCancel];
    return slider;
}

// The tick at the normal value's x on the track, found the way the thumb is placed.
static void placeTick(UISlider *slider) {
    UIView *tick = slider.subviews.firstObject;
    if (tick.subviews.count || tick.class != UIView.class) return;
    CGRect track = [slider trackRectForBounds:slider.bounds];
    float normal = tick.tag / 1000.0f;
    CGRect thumb = [slider thumbRectForBounds:slider.bounds trackRect:track value:normal];
    tick.frame = CGRectMake(roundf(CGRectGetMidX(thumb)) - 1, CGRectGetMidY(track) - 6, 2, 12);
    [slider sendSubviewToBack:tick];
}

- (instancetype)initWithFrame:(CGRect)frame {
    if (!(self = [super initWithFrame:frame])) return nil;
    self.clipsToBounds = YES;
    self.backgroundColor = UIColor.clearColor;
    // Nothing here draws in the tint: every color is set on the view that draws it, and the glyphs have
    // theirs painted in rather than tinted. The row came up in the system blue for a moment as the sheet
    // appeared on the phone (issue #68), which is the tint a view inherits when nothing up the sheet sets
    // one. The block's own tint is white as well, for whatever UIKit draws in it (the sliders' parts).
    self.tintColor = primary();

    _row = [UIControl new];
    [_row addTarget:self action:@selector(toggle) forControlEvents:UIControlEventTouchUpInside];
    [_row addTarget:self action:@selector(rowHighlight) forControlEvents:UIControlEventTouchDown | UIControlEventTouchDragEnter];
    [_row addTarget:self action:@selector(rowUnhighlight) forControlEvents:UIControlEventTouchUpInside | UIControlEventTouchUpOutside | UIControlEventTouchCancel | UIControlEventTouchDragExit];
    _row.isAccessibilityElement = YES;
    _row.accessibilityTraits = UIAccessibilityTraitButton;
    [self addSubview:_row];

    _icon = [[UIImageView alloc] initWithImage:paintedSymbol(@"slider.horizontal.3", 20, UIImageSymbolWeightRegular, secondary())];
    _icon.contentMode = UIViewContentModeCenter;
    _title = makeLabel(font(UIFontTextStyleBody, UIFontWeightRegular, UIContentSizeCategoryExtraLarge), primary());
    _title.text = @"Speed and pitch";
    _summary = makeLabel(monospacedDigits(font(UIFontTextStyleSubheadline, UIFontWeightRegular, UIContentSizeCategoryExtraLarge)), secondary());
    _summary.textAlignment = NSTextAlignmentRight;
    _chevron = [[UIImageView alloc] initWithImage:paintedSymbol(@"chevron.down", 13, UIImageSymbolWeightSemibold, secondary())];
    _chevron.contentMode = UIViewContentModeCenter;
    for (UIView *view in @[_icon, _title, _summary, _chevron]) {
        view.userInteractionEnabled = NO;
        [_row addSubview:view];
    }

    _panel = [UIView new];
    [self addSubview:_panel];
    UIFont *nameFont = font(UIFontTextStyleSubheadline, UIFontWeightRegular, UIContentSizeCategoryExtraLarge);
    _speedName = makeLabel(nameFont, secondary());
    _speedName.text = @"Speed";
    _pitchName = makeLabel(nameFont, secondary());
    _pitchName.text = @"Pitch";
    _speedValue = [self valueButton:@selector(resetSpeed)];
    _pitchValue = [self valueButton:@selector(resetPitch)];
    _speed = [self slider:kMinSpeed max:kMaxSpeed normal:1 minImage:@"tortoise.fill" maxImage:@"hare.fill"];
    _speed.accessibilityLabel = @"Speed";
    _pitch = [self slider:-kMaxPitch max:kMaxPitch normal:0 minImage:@"arrow.down" maxImage:@"arrow.up"];
    _pitch.accessibilityLabel = @"Pitch";
    _reverbName = makeLabel(nameFont, secondary());
    _reverbName.text = @"Reverb";
    _reverbValue = [self valueButton:@selector(resetReverb)];
    _reverb = [self slider:0 max:100 normal:0 minImage:@"speaker" maxImage:@"building.columns"];
    _reverb.accessibilityLabel = @"Reverb";
    _followsName = makeLabel(nameFont, primary());
    _followsName.text = @"Pitch follows speed";
    _follows = [UISwitch new];
    _follows.accessibilityLabel = @"Pitch follows speed";
    [_follows addTarget:self action:@selector(followsChanged) forControlEvents:UIControlEventValueChanged];
    for (UIView *view in @[_speedName, _speedValue, _speed, _pitchName, _pitchValue, _pitch, _reverbName, _reverbValue, _reverb,
                           _followsName, _follows]) [_panel addSubview:view];

    [self refresh];
    return self;
}

+ (CGFloat)heightOpen:(BOOL)open {
    return kRowHeight + (open ? 3 * kSliderBlockHeight + kSwitchRowHeight + kPanelBottom : 0);
}

// Set after init, which drew the values for the sheet's closed block: drawn again open.
- (void)setPanelOnly:(BOOL)panelOnly {
    _panelOnly = panelOnly;
    [self showValues];
    [self setNeedsLayout];
}

- (void)layoutSubviews {
    [super layoutSubviews];
    CGFloat width = self.bounds.size.width, side = kSideMargin;
    _row.frame = CGRectMake(0, 0, width, kRowHeight);
    _icon.frame = CGRectMake(side, (kRowHeight - 24) / 2, 24, 24);
    _chevron.frame = CGRectMake(width - side - 20, (kRowHeight - 20) / 2, 20, 20);
    CGFloat titleX = side + 24 + side;
    CGFloat titleWidth = MIN([_title sizeThatFits:CGSizeMake(CGFLOAT_MAX, kRowHeight)].width, CGRectGetMinX(_chevron.frame) - titleX - kGrid);
    _title.frame = CGRectMake(titleX, 0, titleWidth, kRowHeight);
    CGFloat summaryX = CGRectGetMaxX(_title.frame) + kGrid;
    _summary.frame = CGRectMake(summaryX, 0, MAX(0, CGRectGetMinX(_chevron.frame) - kGrid - summaryX), kRowHeight);

    _row.hidden = self.panelOnly;
    _panel.frame = CGRectMake(0, self.panelOnly ? kGrid : kRowHeight, width, 3 * kSliderBlockHeight + kSwitchRowHeight + kPanelBottom);
    CGFloat y = 0;
    for (NSArray<UIView *> *line in @[@[_speedName, _speedValue, _speed], @[_pitchName, _pitchValue, _pitch],
                                       @[_reverbName, _reverbValue, _reverb]]) {
        line[0].frame = CGRectMake(side, y + 4, width / 2 - side, 24);
        line[1].frame = CGRectMake(width / 2, y + 4, width / 2 - side, 24);
        line[2].frame = CGRectMake(side, y + 30, width - 2 * side, 36);
        [line[2] layoutIfNeeded];
        placeTick((UISlider *)line[2]);
        y += kSliderBlockHeight;
    }
    CGSize toggle = [_follows sizeThatFits:CGSizeZero];
    _follows.frame = CGRectMake(width - side - toggle.width, y + (kSwitchRowHeight - toggle.height) / 2, toggle.width, toggle.height);
    _followsName.frame = CGRectMake(side, y, CGRectGetMinX(_follows.frame) - side - kGrid, kSwitchRowHeight);
}

#pragma mark state

float SGPlayerReverb(void) {
    return SGDSPSwitch(SGKeyDSP) && SGDSPSwitch(SGKeyDSPReverb) ? roundf(SGDSPNumber(SGKeyDSPReverbAmount)) : 0;
}

void SGPlayerSetReverb(float amount) {
    if (amount > 0) {
        SGDSPSetNumber(SGKeyDSPReverbAmount, amount);
        if (!SGDSPSwitch(SGKeyDSPReverb)) SGDSPSetSwitch(SGKeyDSPReverb, YES);
        if (!SGDSPSwitch(SGKeyDSP)) SGDSPSetSwitch(SGKeyDSP, YES);
    } else if (SGDSPSwitch(SGKeyDSPReverb)) {
        SGDSPSetSwitch(SGKeyDSPReverb, NO);
    }
}

static float snappedSpeed(float value) {
    float speed = roundf(value / kSpeedStep) * kSpeedStep;
    return fabsf(speed - 1) < kSpeedStep * 0.6f ? 1 : speed;
}

static NSString *speedText(float speed) {
    return [NSString stringWithFormat:@"%.2f×", speed];
}

static NSString *pitchText(float pitch) {
    if (pitch == 0) return @"0";
    return [NSString stringWithFormat:@"%@%.0f", pitch > 0 ? @"+" : @"−", fabsf(pitch)];
}

// What the player and the pitch say now, onto the controls (not while a finger is on one).
- (void)refresh {
    BOOL speedAllowed = SGPlayerSpeedAllowed(), pitchAvailable = SGPlayerPitchAvailable();
    if (!_speed.tracking) _shownSpeed = snappedSpeed(SGPlayerSpeed());
    if (!_pitch.tracking) _shownPitch = SGPlayerPitch();
    if (!_reverb.tracking) _shownReverb = SGPlayerReverb();
    _reverb.value = _shownReverb;
    _speed.value = _shownSpeed;
    _pitch.value = _shownPitch;
    _speed.enabled = speedAllowed;
    _pitch.enabled = pitchAvailable;
    _speed.alpha = speedAllowed ? 1 : 0.4;
    // Following needs the speed's unit, which the in place fallback does not have.
    _follows.on = SGPlayerPitchFollowsSpeed();
    _follows.enabled = speedAllowed;
    _follows.alpha = _followsName.alpha = speedAllowed ? 1 : 0.4;
    [self showValues];
}

- (void)showValues {
    BOOL speedAllowed = SGPlayerSpeedAllowed(), pitchAvailable = SGPlayerPitchAvailable();
    // While pitch follows a speed that is not normal, the speed sets the pitch and the semitones are not
    // played (SGTimePitch.h), so the slider stands aside and nothing claims them.
    BOOL following = speedAllowed && _follows.on && _shownSpeed != 1;
    float pitch = following ? 0 : _shownPitch;
    [UIView performWithoutAnimation:^{
        [_speedValue setTitle:speedAllowed ? speedText(_shownSpeed) : @"Unavailable here" forState:UIControlStateNormal];
        [_pitchValue setTitle:!pitchAvailable ? @"Unavailable" : following ? @"Follows speed" : [pitchText(pitch) stringByAppendingString:pitch ? @" st" : @""]
                     forState:UIControlStateNormal];
        [_speedValue layoutIfNeeded];
        [_pitchValue layoutIfNeeded];
    }];
    BOOL pitchFree = pitchAvailable && !following;
    _pitch.enabled = pitchFree;
    _pitch.alpha = pitchFree ? 1 : 0.4;
    _speedValue.enabled = speedAllowed && _shownSpeed != 1;
    _pitchValue.enabled = pitchFree && pitch != 0;
    [UIView performWithoutAnimation:^{
        [_reverbValue setTitle:_shownReverb > 0 ? [NSString stringWithFormat:@"%.0f%%", _shownReverb] : @"Off" forState:UIControlStateNormal];
        [_reverbValue layoutIfNeeded];
    }];
    _reverbValue.enabled = _shownReverb > 0;
    _reverb.accessibilityValue = _shownReverb > 0 ? [NSString stringWithFormat:@"%.0f percent", _shownReverb] : @"Off";
    _speed.accessibilityValue = speedAllowed ? speedText(_shownSpeed) : @"Unavailable";
    _pitch.accessibilityValue = following ? @"Follows speed" : pitch == 0 ? @"Original pitch"
                                : [NSString stringWithFormat:@"%.0f semitones %@", fabsf(pitch), pitch > 0 ? @"up" : @"down"];

    NSMutableArray<NSString *> *changed = [NSMutableArray array];
    if (_shownSpeed != 1) [changed addObject:speedText(_shownSpeed)];
    if (pitch != 0) [changed addObject:[pitchText(pitch) stringByAppendingString:@" st"]];
    if (_shownReverb > 0) [changed addObject:@"Reverb"];
    _summary.text = sg_open ? nil : [changed componentsJoinedByString:@"  "];
    _row.accessibilityLabel = changed.count ? [@"Speed and pitch, " stringByAppendingString:[changed componentsJoinedByString:@", "]] : @"Speed and pitch";
    _row.accessibilityValue = sg_open ? @"Expanded" : @"Collapsed";
    _chevron.transform = sg_open ? CGAffineTransformMakeRotation(M_PI) : CGAffineTransformIdentity;
    _panel.alpha = sg_open || self.panelOnly ? 1 : 0;
    _panel.accessibilityElementsHidden = !sg_open && !self.panelOnly;
}

#pragma mark actions

- (void)rowHighlight {
    _row.backgroundColor = [UIColor colorWithWhite:1 alpha:0.08];
}

- (void)rowUnhighlight {
    [UIView animateWithDuration:0.2 animations:^{ _row.backgroundColor = UIColor.clearColor; }];
}

- (void)toggle {
    sg_open = !sg_open;
    if (sg_open) [self refresh];
    UITableView *table = self.table;
    CGRect frame = self.frame;
    frame.size.height = [SGSpeedPitchView heightOpen:sg_open];
    animateOpen(^{
        [table beginUpdates];
        self.frame = frame;
        if (self.inFooter) table.tableFooterView = self;
        else table.tableHeaderView = self;
        [self showValues];
        [self layoutIfNeeded];
        [table endUpdates];
    }, ^(BOOL finished) {
        if (sg_open) [table scrollRectToVisible:[table convertRect:self.bounds fromView:self] animated:YES];
    });
    [table invalidateIntrinsicContentSize];
    UIView *sheet = table.superview;
    for (int i = 0; sheet && i < 4; i++, sheet = sheet.superview) [sheet setNeedsLayout];
    UIAccessibilityPostNotification(UIAccessibilityLayoutChangedNotification, sg_open ? _speed : nil);
    SGLog(@"speed and pitch: speed and pitch %@, table %.0f tall showing %.0f", sg_open ? @"opened" : @"closed", table.contentSize.height, table.bounds.size.height);
}

- (void)sendSpeed {
    _speedPending = NO;
    _speedSentAt = CACurrentMediaTime();
    SGSetPlayerSpeed(_shownSpeed);
}

- (void)sliderMoved:(UISlider *)slider {
    if (slider == _speed) {
        float speed = snappedSpeed(slider.value);
        if (speed == _shownSpeed) return;
        if (speed == 1 || _shownSpeed == 1) SGPlayFeedback(SGFeedbackDetent);
        _shownSpeed = speed;
        NSTimeInterval wait = kSpeedInterval - (CACurrentMediaTime() - _speedSentAt);
        if (wait <= 0) [self sendSpeed];
        else if (!_speedPending) {
            _speedPending = YES;
            __weak SGSpeedPitchView *weakSelf = self;
            dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(wait * NSEC_PER_SEC)), dispatch_get_main_queue(), ^{
                SGSpeedPitchView *view = weakSelf;
                if (view && view->_speedPending) [view sendSpeed];
            });
        }
    } else if (slider == _reverb) {
        float amount = roundf(slider.value / 5) * 5;
        if (amount == _shownReverb) return;
        if (amount == 0 || _shownReverb == 0) SGPlayFeedback(SGFeedbackDetent);
        _shownReverb = amount;
        SGPlayerSetReverb(amount);
    } else {
        float pitch = roundf(slider.value);
        if (pitch == _shownPitch) return;
        if (pitch == 0 || _shownPitch == 0) SGPlayFeedback(SGFeedbackDetent);
        _shownPitch = pitch;
        SGSetPlayerPitch(pitch);
    }
    [self showValues];
}

- (void)sliderReleased:(UISlider *)slider {
    if (slider == _speed) {
        slider.value = _shownSpeed;
        if (_speedPending || snappedSpeed(SGPlayerSpeed()) != _shownSpeed) [self sendSpeed];
    } else if (slider == _reverb) {
        slider.value = _shownReverb;
    } else {
        slider.value = _shownPitch;
    }
}

- (void)resetReverb {
    _shownReverb = 0;
    SGPlayerSetReverb(0);
    [_reverb setValue:0 animated:YES];
    [self showValues];
}

- (void)followsChanged {
    SGSetPlayerPitchFollowsSpeed(_follows.on);
    SGPlayFeedback(SGFeedbackDetent);
    [self refresh];
}

- (void)resetSpeed {
    _shownSpeed = 1;
    [self sendSpeed];
    [_speed setValue:1 animated:YES];
    [self showValues];
}

- (void)resetPitch {
    _shownPitch = 0;
    SGSetPlayerPitch(0);
    [_pitch setValue:0 animated:YES];
    [self showValues];
}

@end

#pragma mark - the panel

// A popover, so it takes the system's glass and closes on a tap outside it. On iPhone a popover becomes a
// sheet unless its delegate says otherwise.
@interface SGSpeedPitchPanel : UIViewController
@end

@implementation SGSpeedPitchPanel
- (void)loadView {
    SGSpeedPitchView *block = [SGSpeedPitchView new];
    block.panelOnly = YES;
    self.view = block;
}
@end

void SGPlayerShowSpeedPitchPanel(UIView *from) {
    SGSpeedPitchPanel *panel = [SGSpeedPitchPanel new];
    panel.preferredContentSize = CGSizeMake(320, kGrid + 3 * kSliderBlockHeight + kSwitchRowHeight + kPanelBottom);
    SGPresentPopover(panel, from);
}

// Spotify's player, whose ⋯ sheet once took the block, is never shown now: no context menu is the player's.
BOOL SGPlayerMenuIsPlayers(UIViewController *menu) {
    return NO;
}
