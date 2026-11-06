// The redesign's tab composition: the row the system tab bar mirrors (TabBar.x, SystemTabs.x).
// Navbar: which tabs the bar shows, in what order, and tabs of the mod's own that open any
// spotify: URI. Spotify keeps its four items (Home, Search, Library, Create) as the arranged
// subviews of one stack view, but a tap on one of them is answered by counting the row off from
// the left, not by asking the item what it is: moved in the stack, an item takes the tap of
// whatever used to stand there. So the stack's own order is left exactly as Spotify built it.
//
// The composed order is kept beside the row instead (SGRNavbarOrder), and the system tab bar, which draws the tabs and
// passes each tap to its item, reads it from there; Spotify's own bar stays hidden under it. Items of the mod's own go
// on the end of the stack, past what Spotify counts. A tap on one goes through Spotify's link dispatcher, the same
// route the app takes for a link it opens itself, so any URI works.
//
// The page that link pushes is the tab's: the tab bar lights the tab while that page is on its stack and
// the stack is on screen, and a second tap goes back to the page rather than opening the link again, the
// way a second tap on one of Spotify's tabs goes back to its root.
//
// Tree (trees/home.txt): NavigationUI_TabBarImpl.TabBarView > TabBarCompactView > UIStackView
//   402x49 of four ElementContentView<TabBarItemElement> 100x49, each an SPTEncoreIconView 24x24
//   at y 12.5 over an SPTEncoreLabel at y 35.
#import "Core/SGCore.h"
#import "Navbar.h"
#import "Shared/Navigation/Links.h"
#import "Shared/Navigation/TabIcons.h"
#import <objc/message.h>

static const CGFloat kIconSize = 24;
static const CGFloat kIconTop = 12.5;
static const CGFloat kLabelTop = 35;
static const CGFloat kLabelHeight = 14;
static char kCustomKey, kOrderKey;

// Where Spotify's own items keep their icon and label, read off one of them every pass, so an item of
// the mod's own sits on the same line as its neighbors.
static CGRect sg_iconBox = {{0, kIconTop}, {kIconSize, kIconSize}};
static CGRect sg_labelBox = {{0, kLabelTop}, {0, kLabelHeight}};

static __weak UIView *sg_navbarRoot;
static UIFont *sg_tabFont;
// Spotify's own tabs in Spotify's order, from the first layout pass of this launch, before
// anything below has moved them.
static NSMutableArray<NSString *> *sg_stockOrder;

static UIColor *itemColor(void) { return [UIColor colorWithWhite:0xB3 / 255.0 alpha:1]; }

// A page pushed this soon after a tap on a tab of the mod's own is the page the tab opened.
static const CFTimeInterval kTabPush = 1;
static __weak UIView *sg_tappedTab, *sg_pageTab;
static CFTimeInterval sg_tappedAt;
static __weak UIViewController *sg_tabPage;

static BOOL tabPageShowing(void) {
    UIViewController *page = sg_tabPage;
    UINavigationController *nav = page.navigationController;
    return sg_pageTab && nav.viewIfLoaded.window && [nav.viewControllers containsObject:page];
}

#pragma mark - the mod's own items

// Drawn the way Spotify's own are, an Encore glyph or an SF Symbol at the glyphs' size
// (Shared/Navigation/TabIcons.h).
static UIView *iconView(NSDictionary *entry) {
    return SGTabIconView(entry[SGRNavbarIcon], [entry[SGRNavbarIconSet] isEqual:SGTabIconSetSymbols], itemColor());
}

@interface SGRTabItemView : UIControl
@property (nonatomic, copy) NSString *uri;
// The icon its entry names, an Encore glyph or an SF Symbol (iconIsSymbol), for the system tab bar (SGRTabItemIcon).
@property (nonatomic, copy) NSString *iconGlyph;
@property (nonatomic) BOOL iconIsSymbol;
- (instancetype)initWithEntry:(NSDictionary *)entry;
- (void)applyEntry:(NSDictionary *)entry;
@end

@implementation SGRTabItemView {
    NSString *_iconName;
    UIView *_icon;
    UILabel *_title;
}

- (instancetype)initWithEntry:(NSDictionary *)entry {
    if (!(self = [super initWithFrame:CGRectZero])) return nil;
    _title = [UILabel new];
    _title.textAlignment = NSTextAlignmentCenter;
    _title.textColor = itemColor();
    [self addSubview:_title];
    [self applyEntry:entry];
    [self addTarget:self action:@selector(open) forControlEvents:UIControlEventTouchUpInside];
    return self;
}

- (void)applyEntry:(NSDictionary *)entry {
    self.uri = entry[SGRNavbarURI];
    _title.text = entry[SGRNavbarTitle];
    self.iconGlyph = entry[SGRNavbarIcon] ?: @"star";
    self.iconIsSymbol = [entry[SGRNavbarIconSet] isEqual:SGTabIconSetSymbols];
    // The set is part of the name: "star" is a glyph in one and a symbol in the other.
    NSString *name = [NSString stringWithFormat:@"%@ %@", entry[SGRNavbarIconSet] ?: @"encore", entry[SGRNavbarIcon] ?: @"star"];
    if ([name isEqualToString:_iconName]) return;
    [_icon removeFromSuperview];
    _iconName = [name copy];
    _icon = iconView(entry);
    // Encore's views lay themselves out from constraints; this one is placed by frame.
    _icon.translatesAutoresizingMaskIntoConstraints = YES;
    [self addSubview:_icon];
}

// Both boxes come off a neighbor, so whatever Spotify does to the row's line-up is copied rather than
// guessed at; only the horizontal centering is the item's own.
- (void)layoutSubviews {
    [super layoutSubviews];
    CGFloat width = self.bounds.size.width;
    // The system tab bar draws the names; the hidden row keeps its icons for the glyphs.
    _title.hidden = YES;
    _title.font = sg_tabFont ?: [UIFont systemFontOfSize:10];
    _title.frame = CGRectMake(0, CGRectGetMinY(sg_labelBox), width, CGRectGetHeight(sg_labelBox));
    _icon.frame = CGRectMake((width - CGRectGetWidth(sg_iconBox)) / 2, CGRectGetMinY(sg_iconBox),
                             CGRectGetWidth(sg_iconBox), CGRectGetHeight(sg_iconBox));
}

// A row that splits its width evenly ignores this, but one that sizes itself to its content would
// otherwise have nothing to go on for an item of ours.
- (CGSize)intrinsicContentSize {
    return CGSizeMake(kIconSize * 2, kLabelTop + kLabelHeight);
}

- (void)setHighlighted:(BOOL)highlighted {
    [super setHighlighted:highlighted];
    self.alpha = highlighted ? 0.5 : 1;
}

// Through the app's own link dispatcher (Shared/Navigation/Links.h). What the dispatcher makes of the
// URI goes to the log first, so a tab that ends in Spotify's "Couldn't open link" says why.
- (void)open {
    UIViewController *page = sg_tabPage;
    if (sg_pageTab == self && tabPageShowing()) {
        UINavigationController *nav = page.navigationController;
        if (nav.topViewController != page) [nav popToViewController:page animated:YES];
        SGLog(@"navbar: back to the tab's page %@", NSStringFromClass(page.class));
        return;
    }
    sg_tappedTab = self;
    sg_tappedAt = CACurrentMediaTime();
    // A link that pushes no page leaves the light where Spotify has it.
    dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)((kTabPush + 0.05) * NSEC_PER_SEC)), dispatch_get_main_queue(), ^{
        SGRRefreshTabBar();
    });
    NSURL *url = SGRNavbarTabURL(self.uri);
    NSString *via = nil;
    SGLinkRoute route = SGSpotifyURIRoute(url, &via);
    SGLog(@"navbar: open %@ -> %@", url.absoluteString ?: self.uri,
          route == SGLinkRouteOpens ? via : route == SGLinkRouteNone ? @"no handler" : @"unknown");
    if (!SGOpenSpotifyURI(url)) SGLog(@"navbar: cannot open %@, dispatcher %@", self.uri, SGLinkDispatcher());
}

@end

#pragma mark - composition

// Spotify's items are told apart by the label under the icon: it survives the element views being
// rebuilt, and it is the name the Navbar page lists them under.
static NSString *stockID(UIView *item) {
    __block NSString *text = nil;
    SGForEachView(item, ^(UIView *v) {
        if (!text && [v isKindOfClass:UILabel.class] && ((UILabel *)v).text.length) text = ((UILabel *)v).text;
    });
    return text ?: NSStringFromClass(item.class);
}

static void measureItem(UIView *item) {
    __block UIView *icon = nil, *label = nil;
    SGForEachView(item, ^(UIView *v) {
        if (!icon && [NSStringFromClass(v.class) containsString:@"IconView"] && v.bounds.size.width > 1) icon = v;
        if (!label && [v isKindOfClass:UILabel.class] && ((UILabel *)v).text.length) label = v;
    });
    if (icon) sg_iconBox = SGFrameIn(icon, item);
    if (!label) return;
    sg_labelBox = SGFrameIn(label, item);
    if (!sg_tabFont) sg_tabFont = ((UILabel *)label).font;
}

static NSMutableDictionary<NSString *, SGRTabItemView *> *customItems(UIStackView *stack) {
    NSMutableDictionary *items = objc_getAssociatedObject(stack, &kCustomKey);
    if (!items) {
        items = [NSMutableDictionary dictionary];
        objc_setAssociatedObject(stack, &kCustomKey, items, OBJC_ASSOCIATION_RETAIN_NONATOMIC);
    }
    return items;
}

void SGRComposeTabBar(UIView *tabBar) {
    UIStackView *stack = SGRowIn(tabBar);
    if (!stack) return;
    sg_navbarRoot = tabBar;

    NSMutableDictionary<NSString *, UIView *> *stockViews = [NSMutableDictionary dictionary];
    for (UIView *item in stack.arrangedSubviews) {
        if ([item isKindOfClass:SGRTabItemView.class]) continue;
        NSString *ident = stockID(item);
        if (stockViews[ident]) continue;
        stockViews[ident] = item;
        measureItem(item);
        if (!sg_stockOrder) sg_stockOrder = [NSMutableArray array];
        if (![sg_stockOrder containsObject:ident]) [sg_stockOrder addObject:ident];
    }
    if (sg_stockOrder && ![sg_stockOrder isEqualToArray:SGRNavbarStock()]) SGRSetNavbarStock(sg_stockOrder);

    NSMutableDictionary<NSString *, SGRTabItemView *> *custom = customItems(stack);
    NSMutableArray<UIView *> *wanted = [NSMutableArray array];
    NSMutableSet<NSString *> *placed = [NSMutableSet set];
    NSMutableSet<NSString *> *keep = [NSMutableSet set];

    // The saved list, which with nothing saved is Spotify's own order, all shown (Use Spotify's tabs goes back to it).
    for (NSDictionary *entry in SGRNavbarLayout()) {
        NSString *ident = entry[SGRNavbarID];
        if (![ident isKindOfClass:NSString.class] || [placed containsObject:ident]) continue;
        [placed addObject:ident];
        BOOL hidden = [entry[SGRNavbarHidden] boolValue];
        if (entry[SGRNavbarURI]) {
            if (hidden) continue;
            SGRTabItemView *item = custom[ident];
            if (item) [item applyEntry:entry];
            else custom[ident] = item = [[SGRTabItemView alloc] initWithEntry:entry];
            [keep addObject:ident];
            [wanted addObject:item];
        } else if (stockViews[ident]) {
            stockViews[ident].hidden = hidden;
            [wanted addObject:stockViews[ident]];
        }
    }
    // Tabs of Spotify's the list does not name — or named before Spotify had built them — keep
    // Spotify's own place, at the end, shown.
    for (NSString *ident in sg_stockOrder) {
        UIView *item = stockViews[ident];
        if (!item || [wanted containsObject:item]) continue;
        item.hidden = NO;
        [wanted addObject:item];
    }
    for (NSString *ident in custom.allKeys) {
        if ([keep containsObject:ident]) continue;
        [custom[ident] removeFromSuperview];
        [custom removeObjectForKey:ident];
    }

    // A bar with nothing on it would strand whoever emptied it, so the last word is Spotify's.
    BOOL empty = YES;
    for (UIView *item in wanted) if (!item.hidden) empty = NO;
    if (empty) for (UIView *item in wanted) item.hidden = NO;

    // Items of the mod's own join the stack at the end, where they are past whatever Spotify
    // counts, and Spotify's own keep the places it gave them.
    for (UIView *item in wanted) {
        if ([item isKindOfClass:SGRTabItemView.class] && item.superview != stack) [stack addArrangedSubview:item];
    }
    NSMutableArray<UIView *> *order = [NSMutableArray array];
    for (UIView *item in wanted) {
        if (item.hidden || item.superview != stack) continue;
        [order addObject:item];
    }
    if (![order isEqualToArray:objc_getAssociatedObject(stack, &kOrderKey)]) {
        objc_setAssociatedObject(stack, &kOrderKey, order, OBJC_ASSOCIATION_RETAIN_NONATOMIC);
    }
}

NSArray<UIView *> *SGRNavbarOrder(UIView *tabBar) {
    UIStackView *stack = SGRowIn(tabBar);
    return stack ? objc_getAssociatedObject(stack, &kOrderKey) : nil;
}

UIView *SGRNavbarLitTab(void) {
    if (tabPageShowing()) return sg_pageTab;
    // From the tap until its page comes, so the bar does not go back to Spotify's tab in between.
    return CACurrentMediaTime() - sg_tappedAt < kTabPush ? sg_tappedTab : nil;
}

%hook SPNavigationController
- (void)pushViewController:(UIViewController *)page animated:(BOOL)animated {
    UIView *tab = sg_tappedTab;
    if (tab && CACurrentMediaTime() - sg_tappedAt < kTabPush) {
        sg_pageTab = tab;
        sg_tabPage = page;
        sg_tappedTab = nil;
        SGLog(@"navbar: %@ is the tab's page", NSStringFromClass(page.class));
    }
    %orig;
}

// A push, a pop or a swipe back: the bar looks again at whether the tab's page is still up.
- (void)navigationController:(UINavigationController *)controller didShowViewController:(UIViewController *)page animated:(BOOL)animated {
    %orig;
    if (sg_pageTab) SGRRefreshTabBar();
}
%end

BOOL SGRTabItemIcon(UIView *item, NSString **name, BOOL *symbol) {
    if (![item isKindOfClass:SGRTabItemView.class]) return NO;
    SGRTabItemView *tab = (SGRTabItemView *)item;
    if (name) *name = tab.iconGlyph;
    if (symbol) *symbol = tab.iconIsSymbol;
    return tab.iconGlyph.length > 0;
}

void SGRRefreshTabBar(void) {
    [sg_navbarRoot setNeedsLayout];
}

%ctor {
    if (!SGRedesignedUI()) return;
    SGRFoldNavbarSplit();
    %init;
    SGRequireClasses(@[
        @"SPNavigationController",
        @"SPTEncoreIcon",
    ]);
}
