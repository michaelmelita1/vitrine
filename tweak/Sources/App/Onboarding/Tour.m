#import "Core/SGCore.h"
#import "Settings/SGPageStyle.h"
#import "Onboarding.h"
#import "App/About/About.h"
#import "Shared/AdBlock/AdBlock.h"

static const CGFloat kMargin = 24;
static const CGFloat kCardRadius = 22;

#pragma mark - glass

// A view whose glass pane follows its bounds; the panes in SGGlass.m are laid out by their hosts.
@interface SGGlassView : UIView
@property (nonatomic) CGFloat radius;
@property (nonatomic) BOOL capsule;
@end

@implementation SGGlassView
static char kPaneKey;
- (void)layoutSubviews {
    [super layoutSubviews];
    UIVisualEffectView *pane = SGGlassFor(self, &kPaneKey);
    pane.frame = self.bounds;
    SGShapeGlass(pane, self.radius, self.capsule);
}
@end

UIButton *SGOnboardingButton(NSString *title) {
    UIButtonConfiguration *config;
    if (@available(iOS 26.0, *)) config = [UIButtonConfiguration prominentGlassButtonConfiguration];
    else config = [UIButtonConfiguration filledButtonConfiguration];
    config.cornerStyle = UIButtonConfigurationCornerStyleCapsule;
    config.baseBackgroundColor = SGGreen();
    config.baseForegroundColor = SGOnAccent();
    config.contentInsets = NSDirectionalEdgeInsetsMake(15, 20, 15, 20);
    config.attributedTitle = [[NSAttributedString alloc] initWithString:title attributes:@{NSFontAttributeName: [UIFont systemFontOfSize:17 weight:UIFontWeightSemibold]}];
    UIButton *button = [UIButton buttonWithConfiguration:config primaryAction:nil];
    button.translatesAutoresizingMaskIntoConstraints = NO;
    return button;
}

#pragma mark - the choice

// A card's row: a symbol on a dim square, a name over a line of small gray text, and an accessory at the end.
static UIStackView *cardRow(NSString *symbol, NSString *title, NSString *subtitle, UIView *accessory) {
    UIImageView *icon = SGSymbolView(symbol, 17, UIImageSymbolWeightSemibold, 36);
    icon.tintColor = UIColor.whiteColor;
    icon.backgroundColor = [UIColor colorWithWhite:1 alpha:0.10];
    icon.layer.cornerRadius = 10;
    icon.layer.cornerCurve = kCACornerCurveContinuous;

    UILabel *name = [UILabel new];
    name.text = title;
    name.font = [UIFont systemFontOfSize:17 weight:UIFontWeightSemibold];
    name.textColor = UIColor.whiteColor;
    UILabel *line = [UILabel new];
    line.text = subtitle;
    line.font = [UIFont systemFontOfSize:13];
    line.textColor = SGGrey();
    line.numberOfLines = 0;
    UIStackView *text = [[UIStackView alloc] initWithArrangedSubviews:@[name, line]];
    text.axis = UILayoutConstraintAxisVertical;
    text.spacing = 2;

    UIStackView *row = [[UIStackView alloc] initWithArrangedSubviews:accessory ? @[icon, text, accessory] : @[icon, text]];
    row.alignment = accessory ? UIStackViewAlignmentCenter : UIStackViewAlignmentTop;
    row.spacing = 14;
    [text setContentHuggingPriority:UILayoutPriorityDefaultLow - 1 forAxis:UILayoutConstraintAxisHorizontal];
    [text setContentCompressionResistancePriority:UILayoutPriorityDefaultHigh - 1 forAxis:UILayoutConstraintAxisHorizontal];
    [NSLayoutConstraint activateConstraints:@[
        [icon.widthAnchor constraintEqualToConstant:36],
        [icon.heightAnchor constraintEqualToConstant:36],
    ]];
    return row;
}

// A glass card of rows, in the look cards' shape, that only points somewhere: the tips at the end of the tour.
static UIView *tipsCard(NSArray<UIView *> *rows) {
    SGGlassView *card = [SGGlassView new];
    card.radius = kCardRadius;
    card.clipsToBounds = YES;
    card.layer.cornerRadius = kCardRadius;
    card.layer.cornerCurve = kCACornerCurveContinuous;
    UIStackView *column = [[UIStackView alloc] initWithArrangedSubviews:rows];
    column.axis = UILayoutConstraintAxisVertical;
    column.spacing = 16;
    column.translatesAutoresizingMaskIntoConstraints = NO;
    [card addSubview:column];
    [NSLayoutConstraint activateConstraints:@[
        [column.leadingAnchor constraintEqualToAnchor:card.leadingAnchor constant:16],
        [column.trailingAnchor constraintEqualToAnchor:card.trailingAnchor constant:-16],
        [column.topAnchor constraintEqualToAnchor:card.topAnchor constant:16],
        [column.bottomAnchor constraintEqualToAnchor:card.bottomAnchor constant:-16],
    ]];
    return card;
}

// A glass card: symbol, name, a line on what it brings, and a check when it is picked. With an accessory instead, the
// card is a row for it (the ads switch).
@interface SGLookCard : UIControl
- (instancetype)initWithSymbol:(NSString *)symbol title:(NSString *)title subtitle:(NSString *)subtitle;
- (instancetype)initWithSymbol:(NSString *)symbol title:(NSString *)title subtitle:(NSString *)subtitle accessory:(UIView *)accessory;
@end

@implementation SGLookCard {
    SGGlassView *_glass;
    UIImageView *_check;
}

- (instancetype)initWithSymbol:(NSString *)symbol title:(NSString *)title subtitle:(NSString *)subtitle {
    return [self initWithSymbol:symbol title:title subtitle:subtitle accessory:nil];
}

- (instancetype)initWithSymbol:(NSString *)symbol title:(NSString *)title subtitle:(NSString *)subtitle accessory:(UIView *)accessory {
    if (!(self = [super initWithFrame:CGRectZero])) return nil;
    if (!accessory) _check = SGSymbolView(@"circle", 22, UIImageSymbolWeightRegular, 26);
    UIStackView *row = cardRow(symbol, title, subtitle, accessory ?: _check);
    row.userInteractionEnabled = NO;
    row.translatesAutoresizingMaskIntoConstraints = NO;

    _glass = [SGGlassView new];
    _glass.radius = kCardRadius;
    _glass.userInteractionEnabled = NO;
    _glass.translatesAutoresizingMaskIntoConstraints = NO;
    self.clipsToBounds = YES;
    self.layer.cornerRadius = kCardRadius;
    self.layer.cornerCurve = kCACornerCurveContinuous;
    self.layer.borderColor = SGGreen().CGColor;
    [self addSubview:_glass];
    [self addSubview:row];
    [NSLayoutConstraint activateConstraints:@[
        [_glass.topAnchor constraintEqualToAnchor:self.topAnchor],
        [_glass.bottomAnchor constraintEqualToAnchor:self.bottomAnchor],
        [_glass.leadingAnchor constraintEqualToAnchor:self.leadingAnchor],
        [_glass.trailingAnchor constraintEqualToAnchor:self.trailingAnchor],
        [row.leadingAnchor constraintEqualToAnchor:self.leadingAnchor constant:16],
        [row.trailingAnchor constraintEqualToAnchor:self.trailingAnchor constant:-16],
        [row.topAnchor constraintEqualToAnchor:self.topAnchor constant:16],
        [row.bottomAnchor constraintEqualToAnchor:self.bottomAnchor constant:-16],
    ]];
    return self;
}

- (void)setSelected:(BOOL)selected {
    [super setSelected:selected];
    _check.image = [UIImage systemImageNamed:selected ? @"checkmark.circle.fill" : @"circle"
                           withConfiguration:[UIImageSymbolConfiguration configurationWithPointSize:22 weight:UIImageSymbolWeightRegular]];
    _check.tintColor = selected ? SGGreen() : SGGrey();
    self.layer.borderWidth = selected ? 2 : 0;
}

- (void)setHighlighted:(BOOL)highlighted {
    [super setHighlighted:highlighted];
    self.alpha = highlighted ? 0.6 : 1;
}

@end

#pragma mark - the logo

// Vitrine's icon in live glass: reeds of glass over a warm glow, the shop window of icons/Vitrine.png.
// The tour opens on it, each reed flying in and landing beside the last, before the page comes in
// under it. Glass shows and hides by its effect, never by an alpha (Redesigned/Kit/SGRGlass.h).
@interface SGTourLogo : UIView
// The state before the landing: the frame alone, no glass, no glow, the reeds out of place.
- (void)prepare;
// Plays the landing, then runs `landed` as the last reed starts to settle; under Reduce Motion the reeds
// and the glow fade in where they are.
- (void)landThen:(void (^)(void))landed;
@end

@implementation SGTourLogo {
    CAGradientLayer *_glow;
    UIView *_pane;
    NSArray<UIVisualEffectView *> *_reeds;
    NSArray<CAGradientLayer *> *_flutes;
}

static const NSUInteger kReeds = 5;

// Clear glass, the style for what sits over something bright, so the glow keeps its light through it.
static UIVisualEffect *reedEffect(void) {
    Class glass = NSClassFromString(@"UIGlassEffect");
    if ([glass respondsToSelector:@selector(effectWithStyle:)]) return [glass effectWithStyle:1];
    return SGGlassEffect();
}
static const CGFloat kLogoRadius = 22;

- (instancetype)initWithFrame:(CGRect)frame {
    if (!(self = [super initWithFrame:frame])) return nil;
    self.isAccessibilityElement = YES;
    self.accessibilityLabel = @"Vitrine";
    self.accessibilityTraits = UIAccessibilityTraitImage;

    _pane = [UIView new];
    _pane.clipsToBounds = YES;
    _pane.layer.cornerRadius = kLogoRadius;
    _pane.layer.cornerCurve = kCACornerCurveContinuous;
    _pane.layer.borderWidth = 1;
    _pane.layer.borderColor = [UIColor colorWithWhite:1 alpha:0.28].CGColor;
    [self addSubview:_pane];

    // The icon's palette: a light core going to Apple Music red, then violet, then the dark around it.
    _glow = [CAGradientLayer layer];
    _glow.type = kCAGradientLayerRadial;
    _glow.colors = @[(id)[UIColor colorWithRed:1 green:0.93 blue:0.9 alpha:1].CGColor,
                     (id)[UIColor colorWithRed:0.98 green:0.18 blue:0.28 alpha:1].CGColor,
                     (id)[UIColor colorWithRed:0.55 green:0.2 blue:0.85 alpha:1].CGColor,
                     (id)[UIColor colorWithRed:0.08 green:0.04 blue:0.1 alpha:1].CGColor];
    _glow.locations = @[@0, @0.35, @0.7, @1];
    _glow.startPoint = CGPointMake(0.45, 0.5);
    _glow.endPoint = CGPointMake(1.05, 1.1);
    [_pane.layer addSublayer:_glow];

    // Each reed is a flute: shade where its curve turns away on the right, a line of light on the left.
    NSMutableArray<UIVisualEffectView *> *reeds = [NSMutableArray array];
    NSMutableArray<CAGradientLayer *> *flutes = [NSMutableArray array];
    for (NSUInteger i = 0; i < kReeds; i++) {
        UIVisualEffectView *reed = [[UIVisualEffectView alloc] initWithEffect:reedEffect()];
        reed.userInteractionEnabled = NO;
        reed.clipsToBounds = YES;
        CAGradientLayer *flute = [CAGradientLayer layer];
        flute.startPoint = CGPointMake(0, 0.5);
        flute.endPoint = CGPointMake(1, 0.5);
        flute.colors = @[(id)[UIColor colorWithWhite:1 alpha:0].CGColor, (id)[UIColor colorWithWhite:1 alpha:0.45].CGColor,
                         (id)[UIColor colorWithWhite:1 alpha:0].CGColor, (id)[UIColor colorWithWhite:0 alpha:0].CGColor,
                         (id)[UIColor colorWithWhite:0 alpha:0.35].CGColor];
        flute.locations = @[@0.08, @0.16, @0.3, @0.6, @1];
        [reed.contentView.layer addSublayer:flute];
        [flutes addObject:flute];
        [_pane addSubview:reed];
        [reeds addObject:reed];
    }
    _reeds = reeds;
    _flutes = flutes;
    return self;
}

- (void)layoutSubviews {
    [super layoutSubviews];
    _pane.frame = self.bounds;
    [CATransaction begin];
    [CATransaction setDisableActions:YES];
    _glow.frame = _pane.bounds;
    CGFloat width = self.bounds.size.width / kReeds, height = self.bounds.size.height;
    for (NSUInteger i = 0; i < kReeds; i++) {
        UIVisualEffectView *reed = _reeds[i];
        // Frames are laid out under the identity transform the landing ends on.
        CGAffineTransform transform = reed.transform;
        reed.transform = CGAffineTransformIdentity;
        reed.frame = CGRectMake(i * width, 0, width, height);
        reed.transform = transform;
        _flutes[i].frame = reed.bounds;
    }
    [CATransaction commit];
}

- (void)prepare {
    BOOL reduce = UIAccessibilityIsReduceMotionEnabled();
    _glow.opacity = 0;
    for (NSUInteger i = 0; i < kReeds; i++) {
        _reeds[i].effect = nil;
        _reeds[i].contentView.alpha = 0;
        // Alternate reeds come from above and below, the middle one from furthest, so the pane closes
        // on itself rather than sliding in from one side.
        CGFloat from = (i % 2 ? -1 : 1) * (28 + 10 * (CGFloat)(2 - labs((long)i - 2)));
        if (!reduce) _reeds[i].transform = CGAffineTransformScale(CGAffineTransformMakeTranslation(0, from), 0.94, 0.94);
    }
}

- (void)landThen:(void (^)(void))landed {
    BOOL reduce = UIAccessibilityIsReduceMotionEnabled();

    CABasicAnimation *glow = [CABasicAnimation animationWithKeyPath:@"opacity"];
    glow.fromValue = @0;
    glow.toValue = @1;
    glow.duration = 0.5;
    glow.timingFunction = [CAMediaTimingFunction functionWithControlPoints:0.23 :1 :0.32 :1];
    _glow.opacity = 1;
    [_glow addAnimation:glow forKey:@"in"];

    if (reduce) {
        [UIView animateWithDuration:0.3 animations:^{
            for (UIVisualEffectView *reed in self->_reeds) {
                reed.effect = reedEffect();
                reed.contentView.alpha = 1;
            }
        }];
        if (landed) landed();
        return;
    }
    // A landing has a little give: damping 0.8, the reeds 50 ms apart.
    const NSTimeInterval stagger = 0.05, flight = 0.55;
    for (NSUInteger i = 0; i < kReeds; i++) {
        UIVisualEffectView *reed = _reeds[i];
        UIViewPropertyAnimator *animator = [[UIViewPropertyAnimator alloc] initWithDuration:flight dampingRatio:0.8 animations:^{
            reed.transform = CGAffineTransformIdentity;
            reed.effect = reedEffect();
            reed.contentView.alpha = 1;
        }];
        [animator startAnimationAfterDelay:0.1 + i * stagger];
    }
    if (landed) {
        dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)((0.1 + (kReeds - 1) * stagger + flight * 0.5) * NSEC_PER_SEC)),
                       dispatch_get_main_queue(), landed);
    }
}

@end

#pragma mark - the tour

// One page, the two choices worth making now under Vitrine's logo: the redesign or Spotify's own look, and
// Spotify without its ads. Everything else waits in Mod Settings; a card of pointers names what people miss there.
@interface SGOnboardingController : UIViewController
@end

// A symbol and a line of small gray text, the note under a card.
static UIStackView *noteLine(UIImageView *icon, UILabel *text) {
    text.font = [UIFont systemFontOfSize:13];
    text.textColor = SGGrey();
    text.numberOfLines = 0;
    [text setContentHuggingPriority:UILayoutPriorityDefaultLow - 1 forAxis:UILayoutConstraintAxisHorizontal];
    UIStackView *line = [[UIStackView alloc] initWithArrangedSubviews:@[icon, text]];
    line.alignment = UIStackViewAlignmentTop;
    line.spacing = 10;
    return line;
}

// The three switches at the top of the Premium, ads & privacy page, which the No ads card sets together.
static NSArray<NSString *> *adKeys(void) {
    return @[SGKeyHideAds, SGKeyHideUpsells, SGKeyFakePremium];
}

static BOOL adFree(void) {
    for (NSString *key in adKeys()) if (!SGHidden(key)) return NO;
    return YES;
}

@implementation SGOnboardingController {
    SGTourLogo *_logo;
    SGLookCard *_adsCard;
    UISwitch *_ads;
    UIButton *_primary;
    NSArray<UIView *> *_page;   // what comes in under the logo, in order
    BOOL _landed;
}

- (instancetype)init {
    if (!(self = [super initWithNibName:nil bundle:nil])) return nil;
    self.modalPresentationStyle = UIModalPresentationOverFullScreen;
    self.modalTransitionStyle = UIModalTransitionStyleCrossDissolve;
    // Its text is white, and the glass under it would take the system's appearance, light in light mode.
    SGPresentDark(self);
    return self;
}

// What people miss in Mod Settings, as pointers only: the tour has no way into a page but holding Home.
- (UIView *)tipsView {
    UIStackView *lyrics = cardRow(@"quote.bubble", @"Lyrics", @"A live preview of the look, the sources in order, and lyrics even where "
                                  @"Spotify has none.\nMod Settings > Lyrics", nil);
    if (@available(iOS 17.0, *)) {
        UIStackView *liveActivity = cardRow(@"platter.filled.bottom.iphone", @"Live Activity",
                                            @"The track on the lock screen.\nMod Settings > Live Activity", nil);
        return tipsCard(@[lyrics, liveActivity]);
    }
    return tipsCard(@[lyrics]);
}

- (void)viewDidLoad {
    [super viewDidLoad];
    self.view.backgroundColor = [UIColor colorWithWhite:0 alpha:0.85];

    _logo = [SGTourLogo new];
    _logo.translatesAutoresizingMaskIntoConstraints = NO;
    // The column stretches its children to its width; the logo keeps its square inside a strip.
    UIView *strip = [UIView new];
    [strip addSubview:_logo];

    UILabel *heading = [UILabel new];
    heading.text = @"Welcome to Vitrine.";
    heading.font = [UIFont systemFontOfSize:30 weight:UIFontWeightBold];
    heading.textColor = UIColor.whiteColor;
    heading.numberOfLines = 0;
    // Below iOS 26 the look does not run (Core/SGUIMode.h): said once here, and in Mod Settings while it is so.
    UILabel *lookText = [UILabel new];
    lookText.text = SGRedesignAvailable() ? @"Spotify in Apple Music's style: iOS's own tab bar, a player page and Apple Music style lyrics."
                                          : [NSString stringWithFormat:@"Vitrine's look needs iOS 26. On iOS %@ Spotify keeps its own; "
                                                @"ads, lyrics sources and the rest below still work.", UIDevice.currentDevice.systemVersion];
    UIStackView *lookNote = noteLine(SGSymbolView(SGRedesignAvailable() ? @"sparkles" : @"exclamationmark.triangle.fill", 15,
                                                  UIImageSymbolWeightSemibold, 22), lookText);
    lookNote.arrangedSubviews.firstObject.tintColor = SGRedesignAvailable() ? SGGrey() : UIColor.systemYellowColor;
    lookNote.layoutMargins = UIEdgeInsetsMake(4, 4, 0, 4);
    lookNote.layoutMarginsRelativeArrangement = YES;

    // Spotify without its ads: one switch for Hide ads, Hide upsells and Spoof Premium. Off leaves each as it
    // is; the tour again shows on only while all three are. They are read at launch, so on ends in a restart.
    _ads = [UISwitch new];
    _ads.onTintColor = SGGreen();
    _ads.on = adFree();
    _adsCard = [[SGLookCard alloc] initWithSymbol:@"speaker.slash" title:@"No ads"
                                         subtitle:@"No ads, no Premium upsells, and Premium spoofed." accessory:_ads];
    [_adsCard addTarget:self action:@selector(toggleAds) forControlEvents:UIControlEventTouchUpInside];
    _adsCard.isAccessibilityElement = YES;
    _adsCard.accessibilityLabel = @"No ads";
    _adsCard.accessibilityHint = @"No ads, no Premium upsells, and Premium spoofed.";
    _adsCard.accessibilityValue = _ads.on ? @"On" : @"Off";
    if (@available(iOS 17.0, *)) _adsCard.accessibilityTraits = UIAccessibilityTraitToggleButton;
    else _adsCard.accessibilityTraits = UIAccessibilityTraitButton;
    UILabel *adsText = [UILabel new];
    adsText.text = @"Three switches of Premium, ads & privacy, applied at the restart; off leaves each as it is. Spoof Premium is "
                   @"untested and can end in a forced logout; a Premium account gains nothing from it. Offline, audio quality and "
                   @"sessions stay the server's.";
    UIStackView *adsNote = noteLine(SGSymbolView(@"info.circle.fill", 15, UIImageSymbolWeightSemibold, 22), adsText);
    adsNote.arrangedSubviews.firstObject.tintColor = SGGrey();
    adsNote.layoutMargins = UIEdgeInsetsMake(4, 4, 0, 4);
    adsNote.layoutMarginsRelativeArrangement = YES;

    UILabel *tipsHeading = [UILabel new];
    tipsHeading.text = @"Easy to miss";
    tipsHeading.font = [UIFont systemFontOfSize:17 weight:UIFontWeightSemibold];
    tipsHeading.textColor = UIColor.whiteColor;
    UIView *tips = [self tipsView];

    UIStackView *column = [[UIStackView alloc] initWithArrangedSubviews:@[strip, heading, lookNote, _adsCard, adsNote, tipsHeading, tips]];
    column.axis = UILayoutConstraintAxisVertical;
    column.spacing = 12;
    [column setCustomSpacing:28 afterView:strip];
    [column setCustomSpacing:32 afterView:lookNote];
    [column setCustomSpacing:32 afterView:adsNote];
    column.translatesAutoresizingMaskIntoConstraints = NO;

    UIScrollView *scroll = [UIScrollView new];
    scroll.alwaysBounceVertical = YES;
    scroll.showsVerticalScrollIndicator = NO;
    scroll.translatesAutoresizingMaskIntoConstraints = NO;
    [scroll addSubview:column];
    [self.view addSubview:scroll];

    _primary = SGOnboardingButton(@"Start listening");
    [_primary addTarget:self action:@selector(finish) forControlEvents:UIControlEventTouchUpInside];
    UILabel *footer = [UILabel new];
    footer.text = @"Hold Home to open settings.";
    footer.font = [UIFont systemFontOfSize:13];
    footer.textColor = SGGrey();
    footer.textAlignment = NSTextAlignmentCenter;
    footer.translatesAutoresizingMaskIntoConstraints = NO;
    [self.view addSubview:_primary];
    [self.view addSubview:footer];

    UILayoutGuide *safe = self.view.safeAreaLayoutGuide;
    UILayoutGuide *frame = scroll.frameLayoutGuide, *content = scroll.contentLayoutGuide;
    [NSLayoutConstraint activateConstraints:@[
        [scroll.topAnchor constraintEqualToAnchor:safe.topAnchor],
        [scroll.leadingAnchor constraintEqualToAnchor:self.view.leadingAnchor],
        [scroll.trailingAnchor constraintEqualToAnchor:self.view.trailingAnchor],
        [scroll.bottomAnchor constraintEqualToAnchor:_primary.topAnchor constant:-12],
        [column.topAnchor constraintEqualToAnchor:content.topAnchor constant:48],
        [column.bottomAnchor constraintEqualToAnchor:content.bottomAnchor constant:-24],
        [column.leadingAnchor constraintEqualToAnchor:content.leadingAnchor constant:kMargin],
        [column.trailingAnchor constraintEqualToAnchor:content.trailingAnchor constant:-kMargin],
        [column.widthAnchor constraintEqualToAnchor:frame.widthAnchor constant:-2 * kMargin],
        [_logo.leadingAnchor constraintEqualToAnchor:strip.leadingAnchor],
        [_logo.topAnchor constraintEqualToAnchor:strip.topAnchor],
        [_logo.bottomAnchor constraintEqualToAnchor:strip.bottomAnchor],
        [_logo.widthAnchor constraintEqualToConstant:88],
        [_logo.heightAnchor constraintEqualToConstant:88],
        [_primary.leadingAnchor constraintEqualToAnchor:self.view.leadingAnchor constant:kMargin],
        [_primary.trailingAnchor constraintEqualToAnchor:self.view.trailingAnchor constant:-kMargin],
        [_primary.bottomAnchor constraintEqualToAnchor:footer.topAnchor constant:-12],
        [footer.leadingAnchor constraintEqualToAnchor:self.view.leadingAnchor constant:kMargin],
        [footer.trailingAnchor constraintEqualToAnchor:self.view.trailingAnchor constant:-kMargin],
        [footer.bottomAnchor constraintEqualToAnchor:safe.bottomAnchor constant:-8],
    ]];
    [self refresh];

    // The tour opens on the logo alone; the page waits under it until the reeds land.
    _page = @[heading, lookNote, _adsCard, adsNote, tipsHeading, tips, _primary, footer];
    [_logo prepare];
    BOOL reduce = UIAccessibilityIsReduceMotionEnabled();
    for (UIView *view in _page) {
        view.alpha = 0;
        if (!reduce) view.transform = CGAffineTransformMakeTranslation(0, 16);
    }
}

- (void)viewDidAppear:(BOOL)animated {
    [super viewDidAppear:animated];
    if (_landed) return;
    _landed = YES;
    NSArray<UIView *> *page = _page;
    [_logo landThen:^{
        // A strong ease out, critically damped, 40 ms between the parts. Under Reduce Motion the page
        // only fades, as nothing was moved out of place.
        for (NSUInteger i = 0; i < page.count; i++) {
            UIViewPropertyAnimator *animator = [[UIViewPropertyAnimator alloc] initWithDuration:0.45 dampingRatio:1 animations:^{
                page[i].alpha = 1;
                page[i].transform = CGAffineTransformIdentity;
            }];
            [animator startAnimationAfterDelay:i * 0.04];
        }
    }];
}

- (void)toggleAds {
    [_ads setOn:!_ads.on animated:YES];
    _adsCard.accessibilityValue = _ads.on ? @"On" : @"Off";
    [self refresh];
}

// The ad switches are read at launch, so turning them on ends the tour in a restart.
- (BOOL)needsRestart {
    return _ads.on && !adFree();
}

- (void)refresh {
    UIButtonConfiguration *config = _primary.configuration;
    NSString *title = self.needsRestart ? @"Restart Spotify" : @"Start listening";
    config.attributedTitle = [[NSAttributedString alloc] initWithString:title attributes:@{NSFontAttributeName: [UIFont systemFontOfSize:17 weight:UIFontWeightSemibold]}];
    _primary.configuration = config;
}

- (void)finish {
    SGSetEnabled(SGKeyOnboardingSeen, YES);
    if (_ads.on) for (NSString *key in adKeys()) SGSetEnabled(key, YES);
    if (self.needsRestart) {
        SGRestartSpotify();
        return;
    }
    [self dismissViewControllerAnimated:YES completion:^{ SGShowSigningFixIfPending(); }];
}

@end

#pragma mark - entry

static __weak SGOnboardingController *sg_tour;

BOOL SGOnboardingShowing(void) {
    return sg_tour != nil || SGWhatsNewShowing();
}

void SGShowOnboarding(void) {
    if (sg_tour) return;
    UIViewController *top = SGTopController();
    // Presenting from an alert lands nowhere; the tour waits for it to go.
    if (!top || [top isKindOfClass:UIAlertController.class]) {
        dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(1 * NSEC_PER_SEC)), dispatch_get_main_queue(), ^{ SGShowOnboarding(); });
        return;
    }
    SGOnboardingController *tour = [SGOnboardingController new];
    sg_tour = tour;
    [top presentViewController:tour animated:YES completion:nil];
}
