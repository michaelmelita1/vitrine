// Tab bar: Spotify's own bar stays where it is, unseen and untouchable, as the source of the tabs of the redesign's
// system tab bar (SystemTabs.x), which stands over Spotify's tab area. Navbar.x composes Spotify's row first, so its
// order, hidden tabs and tabs of the mod's own carry over. Each pass of Spotify's bar hands its items, and the one
// shown, to SystemTabs.x (SGRSystemTabsSync), which reads each item's glyph and name here and passes a tap on to it.
//
// Tree (trees/home.txt): NavigationUI_TabBarImpl.TabBarView > TabBarCompactView > UIStackView of
//   ElementContentView<TabBarItemElement>, each with an SPTEncoreIconView and an SPTEncoreLabel.
#import "Core/SGCore.h"
#import "Navbar.h"
#import "Headers/SPTEncoreIconView.h"
#import "Shared/Navigation/TabIcons.h"
#import <objc/message.h>

static __weak UIView *sg_stockBar;

#pragma mark - reading Spotify's items

// The items the bar shows, left to right as Navbar/Navbar.x placed them.
static NSArray<UIView *> *tabItems(UIView *tabBar) {
    // The order Navbar.x composed; Spotify's row as it stands until it has.
    NSArray<UIView *> *composed = SGRNavbarOrder(tabBar);
    if (composed.count) return composed;
    NSMutableArray<UIView *> *items = [NSMutableArray array];
    for (UIView *item in SGRowIn(tabBar).arrangedSubviews) {
        if (!item.hidden && item.bounds.size.width >= 20) [items addObject:item];
    }
    return [items sortedArrayUsingComparator:^NSComparisonResult(UIView *a, UIView *b) {
        return [@(SGFrameIn(a, tabBar).origin.x) compare:@(SGFrameIn(b, tabBar).origin.x)];
    }];
}

static UILabel *labelIn(UIView *item) {
    __block UILabel *label = nil;
    SGForEachView(item, ^(UIView *v) {
        if (!label && [v isKindOfClass:UILabel.class] && ((UILabel *)v).text.length) label = (UILabel *)v;
    });
    return label;
}

static UIView *iconIn(UIView *item) {
    __block UIView *icon = nil;
    SGForEachView(item, ^(UIView *v) {
        if (icon || v.bounds.size.width < 2) return;
        if ([v isKindOfClass:UIImageView.class] || [NSStringFromClass(v.class) containsString:@"IconView"]) icon = v;
    });
    return icon;
}

// Spotify paints the selected tab's label white and the rest #B3B3B3.
static BOOL isActive(UIView *item) {
    UIColor *color = labelIn(item).textColor;
    CGFloat white = 0, alpha = 0, r, g, b;
    if (![color getWhite:&white alpha:&alpha] && [color getRed:&r green:&g blue:&b alpha:&alpha]) white = MIN(r, MIN(g, b));
    return white > 0.95;
}

static BOOL hasInk(UIImage *image) {
    CGImageRef cg = image.CGImage;
    size_t width = CGImageGetWidth(cg), height = CGImageGetHeight(cg);
    if (!width || !height) return NO;
    NSMutableData *pixels = [NSMutableData dataWithLength:width * height];
    CGContextRef context = CGBitmapContextCreate(pixels.mutableBytes, width, height, 8, width, NULL, (CGBitmapInfo)kCGImageAlphaOnly);
    CGContextDrawImage(context, CGRectMake(0, 0, width, height), cg);
    CGContextRelease(context);
    const uint8_t *alpha = pixels.bytes;
    for (size_t i = 0; i < pixels.length; i++) if (alpha[i] > 16) return YES;
    return NO;
}

static UIImage *renderLayer(CALayer *layer, CGSize size) {
    UIGraphicsImageRenderer *renderer = [[UIGraphicsImageRenderer alloc] initWithSize:size];
    UIImage *image = [renderer imageWithActions:^(UIGraphicsImageRendererContext *context) {
        [layer renderInContext:context.CGContext];
    }];
    return hasInk(image) ? [image imageWithRenderingMode:UIImageRenderingModeAlwaysTemplate] : nil;
}

// The SPTEncoreIcon an icon view was built with. Encore keeps it in a Swift ivar with no getter.
static id encoreIconOf(UIView *view) {
    Ivar ivar = class_getInstanceVariable(view.class, "icon");
    const char *type = ivar ? ivar_getTypeEncoding(ivar) : NULL;
    return type && type[0] == '@' ? object_getIvar(view, ivar) : nil;
}

// An SPTEncoreIcon's name, which is what tells two icons apart: Spotify may hand a view a new instance of the
// same glyph. Nil for an icon that does not say.
static NSString *iconName(id icon) {
    id name = [icon respondsToSelector:@selector(name)] ? [icon name] : nil;
    return [name isKindOfClass:NSString.class] ? name : nil;
}

// The filled variant of a tab's SPTEncoreIcon (-active, which fillBar's log prints), when it has one. A filled
// icon has none: its -active is itself, or the same glyph again.
static id activeVariantOf(id icon) {
    SEL selector = NSSelectorFromString(@"active");
    if (!icon || ![icon respondsToSelector:selector]) return nil;
    id variant = ((id (*)(id, SEL))objc_msgSend)(icon, selector);
    if (variant == icon || ![variant isKindOfClass:[icon class]]) return nil;
    NSString *name = iconName(icon);
    return name && [name isEqualToString:iconName(variant)] ? nil : variant;
}

// One glyph of a tab: `icon` drawn at the size of `live`, Spotify's icon view it came from. The caller picks the
// icon, outline or filled, so the cache key names the glyph actually drawn and an outline drawing can never be
// filed under a filled icon's name or the other way round. isActive only picks the view's colors, white either
// way. Drawn on an icon view of our own, off screen, so the images do not wait for Spotify's views to lay out
// and paint, and UITabBar swaps image and selectedImage itself.
static UIImage *drawGlyph(UIView *live, id icon, BOOL active) {
    if (!live) return nil;
    CGSize size = live.bounds.size;
    Class viewClass = NSClassFromString(@"SPTEncoreIconView");
    if (icon && viewClass) {
        static NSCache<NSString *, UIImage *> *cache;
        if (!cache) cache = [NSCache new];
        NSString *key = [NSString stringWithFormat:@"%@ %d %@", iconName(icon) ?: icon, active, NSStringFromCGSize(size)];
        UIImage *cached = [cache objectForKey:key];
        if (cached) return cached;
        SPTEncoreIconView *view = [[viewClass alloc] initWithIcon:icon];
        view.frame = (CGRect){CGPointZero, size};
        [view setForegroundColor:UIColor.whiteColor];
        if ([view respondsToSelector:@selector(setActiveForegroundColor:)]) [view setActiveForegroundColor:UIColor.whiteColor];
        if ([view respondsToSelector:@selector(setIsActive:)]) [view setIsActive:active];
        [view layoutIfNeeded];
        UIImage *image = renderLayer(view.layer, size);
        if (image) {
            [cache setObject:image forKey:key];
            return image;
        }
    }
    // Tabs of the mod's own draw a UIImageView, or an icon Encore would not draw off screen.
    return size.width >= 2 ? renderLayer(live.layer, size) : nil;
}

// A tab's glyph from what its view holds now, the filled variant for the selected state where the icon has one.
static UIImage *glyphOf(UIView *item, BOOL active) {
    UIView *live = iconIn(item);
    id icon = live ? encoreIconOf(live) : nil;
    if (active) icon = activeVariantOf(icon) ?: icon;
    return drawGlyph(live, icon, active);
}

// For the Tab bar page's list and preview: a tab of Spotify's drawn from its item on the bar, hidden or not,
// found by the label its entry is named after; a tab of the mod's own drawn from its entry, as Navbar.x
// draws it on the bar. Nil while Spotify's item has not been built.
UIImage *SGRNavbarGlyph(NSDictionary *entry, BOOL active) {
    if (entry[SGRNavbarURI]) {
        UIView *holder = [[UIView alloc] initWithFrame:CGRectMake(0, 0, 24, 24)];
        UIView *icon = SGTabIconView(entry[SGRNavbarIcon], [entry[SGRNavbarIconSet] isEqual:SGTabIconSetSymbols], UIColor.whiteColor);
        icon.translatesAutoresizingMaskIntoConstraints = YES;
        icon.frame = holder.bounds;
        if ([icon isKindOfClass:UIImageView.class]) icon.contentMode = UIViewContentModeScaleAspectFit;
        [holder addSubview:icon];
        [holder layoutIfNeeded];
        return glyphOf(holder, active);
    }
    for (UIView *item in SGRowIn(sg_stockBar).arrangedSubviews) {
        if ([NSStringFromClass(item.class) isEqualToString:@"SGRTabItemView"]) continue;
        if ([labelIn(item).text isEqualToString:entry[SGRNavbarID]]) return glyphOf(item, active);
    }
    return nil;
}

#pragma mark - passing a tap on

// NavigationUI_TabBarImpl's TabBarItemElementUI answers a tap recognizer (-handleTap), so the tap is
// replayed through the recognizer's own target-action pairs, the same call a real touch ends in.
static BOOL fireTapRecognizers(UIView *view) {
    Ivar targetsIvar = class_getInstanceVariable(UIGestureRecognizer.class, "_targets");
    if (!targetsIvar) return NO;
    BOOL fired = NO;
    for (UIGestureRecognizer *recognizer in view.gestureRecognizers) {
        if (![recognizer isKindOfClass:UITapGestureRecognizer.class] || !recognizer.enabled) continue;
        for (id pair in object_getIvar(recognizer, targetsIvar)) {
            Ivar targetIvar = class_getInstanceVariable([pair class], "_target");
            Ivar actionIvar = class_getInstanceVariable([pair class], "_action");
            if (!targetIvar || !actionIvar) continue;
            id target = object_getIvar(pair, targetIvar);
            SEL action = *(SEL *)((char *)(__bridge void *)pair + ivar_getOffset(actionIvar));
            if (!target || !action || ![target respondsToSelector:action]) continue;
            SGLog(@"tab bar: tap -> %@ %@", NSStringFromClass([target class]), NSStringFromSelector(action));
            ((void (*)(id, SEL, id))objc_msgSend)(target, action, recognizer);
            fired = YES;
        }
    }
    return fired;
}

static void forwardTap(UIView *item) {
    __block BOOL sent = NO;
    SGForEachView(item, ^(UIView *v) {
        if (!sent) sent = fireTapRecognizers(v);
    });
    SGForEachView(item, ^(UIView *v) {
        if (sent || ![v isKindOfClass:UIControl.class]) return;
        SGLog(@"tab bar: tap -> control %@", NSStringFromClass(v.class));
        [(UIControl *)v sendActionsForControlEvents:UIControlEventTouchUpInside];
        sent = YES;
    });
    if (!sent) {
        NSMutableString *out = [NSMutableString stringWithFormat:@"tab bar: nothing to tap in %@", NSStringFromClass(item.class)];
        SGForEachView(item, ^(UIView *v) {
            for (UIGestureRecognizer *r in v.gestureRecognizers) [out appendFormat:@"\n  %@ on %@", r, NSStringFromClass(v.class)];
        });
        SGLogLong(@"navbar", out);
    }
}

// For the system tab bar (SystemTabs.x): Spotify's items read and tapped.
UIImage *SGRTabSourceGlyph(UIView *source, BOOL active) {
    return glyphOf(source, active);
}

// For the system tab bar: one of Spotify's tabs drawn from Spotify's own Encore glyphs, as the Tab bar page's
// Spotify Encore list draws them (Shared/Navigation/TabIcons.m), outline and filled (the glyph's -active variant), so both
// are there from the first launch. Spotify 9.1.90's icon view keeps its icon as a Swift value the mod cannot read (the
// phone's log, 2026-11-02), so the tab is told by its name, or failing that by its place in Spotify's own order. NO for a
// tab not known here (one of the mod's own, or one Spotify adds), which the bar draws as it stands.
static NSArray<NSString *> *encoreCandidates(UIView *source) {
    NSString *label = labelIn(source).text.lowercaseString ?: @"";
    static NSArray<NSArray<NSString *> *> *byPlace;
    if (!byPlace) byPlace = @[@[@"home"], @[@"search"], @[@"library", @"yourLibrary", @"collection"], @[@"plus", @"create"]];
    if ([label containsString:@"home"]) return byPlace[0];
    if ([label containsString:@"search"]) return byPlace[1];
    if ([label containsString:@"librar"]) return byPlace[2];
    if ([label containsString:@"create"]) return byPlace[3];
    NSUInteger place = [SGRNavbarStock() indexOfObject:labelIn(source).text ?: @""];
    return place < byPlace.count ? byPlace[place] : nil;
}

// An SF Symbol as the tab editor draws one (19 pt semibold), a template for the bar to tint.
static UIImage *tabSymbol(NSString *name) {
    UIImage *image = name.length ? [UIImage systemImageNamed:name withConfiguration:[UIImageSymbolConfiguration configurationWithPointSize:19 weight:UIImageSymbolWeightSemibold]] : nil;
    return [image imageWithRenderingMode:UIImageRenderingModeAlwaysTemplate];
}

BOOL SGRTabSourceEncoreGlyphs(UIView *source, UIImage **outline, UIImage **filled) {
    UIView *live = iconIn(source);
    if (!live) return NO;
    // A tab of the mod's own: the icon its entry names. A symbol's outline is the name without ".fill" and its filled one
    // the name with it, where this iOS has both; an Encore glyph's filled one is its -active variant.
    NSString *entryName = nil;
    BOOL entrySymbol = NO;
    NSArray<NSString *> *candidates = encoreCandidates(source);
    if (SGRTabItemIcon(source, &entryName, &entrySymbol)) {
        if (entrySymbol) {
            NSString *base = [entryName hasSuffix:@".fill"] ? [entryName substringToIndex:entryName.length - 5] : entryName;
            UIImage *line = tabSymbol(base) ?: tabSymbol(entryName), *solid = tabSymbol([base stringByAppendingString:@".fill"]) ?: line;
            if (!line) return NO;
            if (outline) *outline = line;
            if (filled) *filled = solid;
            return YES;
        }
        candidates = @[entryName];
    }
    NSArray<NSString *> *names = SGEncoreGlyphNames();
    Class iconClass = NSClassFromString(@"SPTEncoreIcon");
    id icon = nil;
    for (NSString *name in candidates) {
        if (![names containsObject:name]) continue;
        @try { icon = ((id (*)(id, SEL))objc_msgSend)(iconClass, NSSelectorFromString(name)); } @catch (NSException *e) { icon = nil; }
        if (icon) break;
    }
    if (!icon) return NO;
    id variant = activeVariantOf(icon);
    UIImage *drawnOutline = drawGlyph(live, icon, NO), *drawnFilled = drawGlyph(live, variant ?: icon, YES);
    if (!drawnOutline || !drawnFilled) return NO;
    if (outline) *outline = drawnOutline;
    if (filled) *filled = drawnFilled;
    return YES;
}

NSString *SGRTabSourceTitle(UIView *source) {
    return labelIn(source).text ?: @"";
}

void SGRForwardTabTap(UIView *source) {
    forwardTap(source);
}

static UIViewController *containerOf(UIView *stockBar) {
    Class containerClass = NSClassFromString(@"_TtC23NavigationUI_TabBarImpl19TabBarContainerImpl");
    for (UIResponder *r = stockBar.nextResponder; r; r = r.nextResponder) {
        if ([r isKindOfClass:containerClass]) return (UIViewController *)r;
    }
    return nil;
}

#pragma mark - handing the tabs over

static void syncBar(UIView *stockBar) {
    sg_stockBar = stockBar;
    for (UIView *sub in stockBar.subviews) {
        if (sub.alpha > 0) sub.alpha = 0;
        sub.userInteractionEnabled = NO;
    }
    // The bar and what holds it take no touches either: left on, they stood unseen at the foot of the screen over the
    // page, under the system bar (its owner, 2026-10-31). Its taps are passed on to its items in code (forwardTap).
    for (UIView *v = stockBar; v && ![v.nextResponder isKindOfClass:UIViewController.class]; v = v.superview) {
        if (v.userInteractionEnabled) v.userInteractionEnabled = NO;
    }
    NSArray<UIView *> *sources = tabItems(stockBar);
    if (!sources.count) return;
    UIView *active = SGRNavbarLitTab();
    if (![sources containsObject:active]) active = nil;
    for (UIView *source in sources) if (!active && isActive(source)) active = source;
    SGRSystemTabsSync(containerOf(stockBar), stockBar, sources, active);
}

#pragma mark - hooks

static UIView *tabBarOf(UIView *item) {
    Class barClass = NSClassFromString(@"_TtC23NavigationUI_TabBarImpl10TabBarView");
    for (UIView *v = item.superview; v; v = v.superview) if ([v isKindOfClass:barClass]) return v;
    return nil;
}

// The bar in its own pass, and whether one of its items laid out during it.
static __weak UIView *sg_passBar;
static BOOL sg_itemsLaidOut;

%hook _TtC23NavigationUI_TabBarImpl10TabBarView
- (void)layoutSubviews {
    // A pass nested in another (an item's layoutIfNeeded) hands both back, so the outer one still composes.
    UIView *bar = (UIView *)self, *outer = sg_passBar;
    BOOL outerLaidOut = sg_itemsLaidOut;
    sg_passBar = bar;
    %orig;
    SGRComposeTabBar(bar);
    sg_itemsLaidOut = NO;
    for (UIView *sub in bar.subviews) [sub layoutIfNeeded];
    // Items the row's pass laid out are composed once, all together, rather than once each.
    if (sg_itemsLaidOut) SGRComposeTabBar(bar);
    sg_passBar = outer;
    sg_itemsLaidOut = outerLaidOut;
    syncBar(bar);
}
%end

// The bar's own pass runs before Spotify has filled the row; the items lay out as they arrive. Inside the bar's
// pass, the pass composes once after them; outside it, the item composes at once, so no frame shows Spotify's row.
static void itemDidLayOut(UIView *item) {
    UIView *bar = tabBarOf(item);
    if (!bar) return;
    if (bar == sg_passBar) {
        sg_itemsLaidOut = YES;
        return;
    }
    SGRComposeTabBar(bar);
    syncBar(bar);
}

%hook _TtC23NavigationUI_TabBarImpl21TabBarItemElementView
- (void)layoutSubviews {
    %orig;
    itemDidLayOut((UIView *)self);
}
%end

%hook _TtC25CreateMenu_TabBarItemImpl24CreateMenuTabBarItemView
- (void)layoutSubviews {
    %orig;
    itemDidLayOut((UIView *)self);
}
%end

// A tab changed from elsewhere (a link, the side drawer) repaints the labels without a layout pass.
%hook _TtC23NavigationUI_TabBarImpl19TabBarContainerImpl
- (void)setSelectedViewController:(UIViewController *)controller {
    %orig;
    dispatch_async(dispatch_get_main_queue(), ^{
        UIView *bar = sg_stockBar;
        if (bar) syncBar(bar);
    });
}
%end

// Spotify's own fade under its bar, 219 pt down to black from 9.1.90 (TabBarGradientView), stays clear: the system tab
// bar draws its own.
%group SpotifyBarFade
%hook _TtC23NavigationUI_TabBarImpl18TabBarGradientView
- (void)didMoveToWindow {
    %orig;
    ((UIView *)self).alpha = 0;
}
- (void)setAlpha:(CGFloat)alpha {
    %orig(0);
}
%end
%end

%ctor {
    if (!SGRedesignedUI()) return;
    %init;
    if (objc_getClass("_TtC23NavigationUI_TabBarImpl18TabBarGradientView")) %init(SpotifyBarFade);
    SGRequireClasses(@[
        @"_TtC23NavigationUI_TabBarImpl10TabBarView",
        @"_TtC23NavigationUI_TabBarImpl21TabBarItemElementView",
        @"_TtC25CreateMenu_TabBarItemImpl24CreateMenuTabBarItemView",
        @"_TtC23NavigationUI_TabBarImpl19TabBarContainerImpl",
    ]);
}
