// The redesign's accent color, which colors the tab bar alone (Navbar/SystemTabs.x, SGRTabAccent); Spotify's green
// everywhere else is white (its owner, 2026-11-08: "the accent colour to really only impact the tab bar").
// Spotify's green, #1ED760, is one token. Its three components occur once in the
// whole binary, and every green the app draws, from the play button to the "Zobrazit vše" links
// and the progress bar, is that token or a state blended from it. So it is swapped where it is
// born, in the UIColor initializer, and the blends follow. Lottie animations carry their own green
// and are caught at the layer, below. Image assets with green baked in, the logo above all, are
// out of reach.
#import "Core/SGCore.h"
#import "SGRAccent.h"

// The greens the app is known to build from literals: the token, and the older brand green the
// upsell backend still names.
static const uint32_t kGreens[] = {0x1ED760, 0x1DB954};


static NSInteger chosen(void) {
    NSInteger rgb = SGInt(SGRKeyAccent, SGRDefaultAccent);
    return rgb >= 0 && rgb <= 0xFFFFFF ? rgb : -1;
}

static void unpack(uint32_t rgb, CGFloat *r, CGFloat *g, CGFloat *b) {
    *r = ((rgb >> 16) & 0xFF) / 255.0;
    *g = ((rgb >> 8) & 0xFF) / 255.0;
    *b = (rgb & 0xFF) / 255.0;
}

// Made again only when another color is stored: the pick applies at once, and the key is read per call for it.
UIColor *SGRAccentColor(void) {
    static NSInteger madeFor = -1;
    static UIColor *made;
    NSInteger rgb = chosen();
    if (rgb < 0) return nil;
    if (made && rgb == madeFor) return made;
    CGFloat r, g, b;
    unpack((uint32_t)rgb, &r, &g, &b);
    made = [UIColor colorWithRed:r green:g blue:b alpha:1];
    madeFor = rgb;
    return made;
}

NSInteger SGRAccentRGB(void) {
    NSInteger rgb = chosen();
    return rgb < 0 ? SGSpotifyGreen : rgb;
}

// A darker green than the token comes out as white darkened by the same amount, a gray, so the two keep their
// relation.
static BOOL swap(CGFloat *r, CGFloat *g, CGFloat *b) {
    for (size_t i = 0; i < sizeof(kGreens) / sizeof(kGreens[0]); i++) {
        CGFloat gr, gg, gb;
        unpack(kGreens[i], &gr, &gg, &gb);
        if (fabs(*r - gr) > 0.01 || fabs(*g - gg) > 0.01 || fabs(*b - gb) > 0.01) continue;
        CGFloat ar = 1, ag = 1, ab = 1;
        CGFloat factor = MAX(gr, MAX(gg, gb)) / (0xD7 / 255.0);
        *r = MIN(1, ar * factor);
        *g = MIN(1, ag * factor);
        *b = MIN(1, ab * factor);
        return YES;
    }
    return NO;
}

%hook UIColor
- (UIColor *)initWithRed:(CGFloat)r green:(CGFloat)g blue:(CGFloat)b alpha:(CGFloat)a {
    swap(&r, &g, &b);
    return %orig(r, g, b, a);
}
+ (UIColor *)colorWithRed:(CGFloat)r green:(CGFloat)g blue:(CGFloat)b alpha:(CGFloat)a {
    swap(&r, &g, &b);
    return %orig(r, g, b, a);
}
%end

// Lottie draws its animations, the play indicator and the checkmarks among them, from colors
// in the animation file straight onto shape layers, or into color keyframes, never through
// UIColor. The same swap goes on the CGColor. Layers get set off the main thread too, so the
// copy is made with CoreGraphics alone; NULL when the color is not one of the greens.
static CGColorRef swappedCopy(CGColorRef color) {
    if (!color || CFGetTypeID(color) != CGColorGetTypeID() || CGColorGetNumberOfComponents(color) != 4) return NULL;
    const CGFloat *c = CGColorGetComponents(color);
    CGFloat r = c[0], g = c[1], b = c[2];
    if (!swap(&r, &g, &b)) return NULL;
    CGFloat out[] = {r, g, b, c[3]};
    return CGColorCreate(CGColorGetColorSpace(color), out);
}

static id swappedValue(id value) {
    CGColorRef swapped = swappedCopy((__bridge CGColorRef)value);
    if (!swapped) return value;
    id boxed = (__bridge_transfer id)swapped;
    return boxed;
}

%hook CAShapeLayer
- (void)setFillColor:(CGColorRef)color {
    CGColorRef swapped = swappedCopy(color);
    CGColorRef used = swapped ?: color;
    %orig(used);
    if (swapped) CGColorRelease(swapped);
}
- (void)setStrokeColor:(CGColorRef)color {
    CGColorRef swapped = swappedCopy(color);
    CGColorRef used = swapped ?: color;
    %orig(used);
    if (swapped) CGColorRelease(swapped);
}
%end

%hook CALayer
- (void)setBackgroundColor:(CGColorRef)color {
    CGColorRef swapped = swappedCopy(color);
    CGColorRef used = swapped ?: color;
    %orig(used);
    if (swapped) CGColorRelease(swapped);
}
%end

%hook CABasicAnimation
- (void)setFromValue:(id)value {
    id used = swappedValue(value);
    %orig(used);
}
- (void)setToValue:(id)value {
    id used = swappedValue(value);
    %orig(used);
}
%end

%hook CAKeyframeAnimation
- (void)setValues:(NSArray *)values {
    NSMutableArray *mapped = nil;
    for (NSUInteger i = 0; i < values.count; i++) {
        id swapped = swappedValue(values[i]);
        if (swapped == values[i] && !mapped) continue;
        if (!mapped) mapped = [values mutableCopy];
        mapped[i] = swapped;
    }
    NSArray *used = mapped ?: values;
    %orig(used);
}
%end

// A switch that is on shows it only by its track's color, so Spotify's green made white left a white knob on a white
// track (code review, 2026-11-08): a white on-tint goes back to the system's own green.
static BOOL isWhite(UIColor *color) {
    CGFloat w = 0, a = 0, r, g, b;
    if ([color getWhite:&w alpha:&a]) return w > 0.95 && a > 0.5;
    return [color getRed:&r green:&g blue:&b alpha:&a] && MIN(r, MIN(g, b)) > 0.95 && a > 0.5;
}

%hook UISwitch
- (void)setOnTintColor:(UIColor *)color {
    %orig(color && isWhite(color) ? nil : color);
}
%end

%ctor {
    if (!SGRedesignedUI()) return;
    %init;
}
