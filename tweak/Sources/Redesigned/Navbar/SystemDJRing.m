// SystemDJRing.h. Measured off Spotify's own DJ screen (a recording of it on the 12 mini, 2026-11-10): a green circle,
// round while the DJ is quiet, that dents inward at its upper right as the voice gets loud, at most two fifths of its
// radius, the dent always the same shape (the DJ logo's), only deeper or shallower. Two solid copies behind it, teal and
// then blue, stand out past the dent as long as there is one, a little behind it in time. A display link draws it only while it moves and is in a window.
//
// Threading: main thread only.
#import <QuartzCore/QuartzCore.h>
#import "Core/SGCore.h"
#import "Redesigned/Player/Player.h"
#import "Redesigned/Player/SGRSpectrum.h"
#import "SystemDJRing.h"

// Spotify's DJ colors, read off the recording: the blue behind, the ring, and its two copies.
static UIColor *rgb(int r, int g, int b) { return [UIColor colorWithRed:r / 255.0 green:g / 255.0 blue:b / 255.0 alpha:1]; }
// The ring's radius (to the middle of its line) and line, as shares of the square's side: Spotify's circle is half the
// screen across with a line a seventh of its radius; in the cover it is drawn a little larger.
static const CGFloat kRadius = 0.27, kLine = 0.04;
// The deepest dent, as a share of the radius.
static const CGFloat kDentDepth = 0.40;
// How far back each copy is, in seconds.
static const CFTimeInterval kCopyLag[2] = {0.04, 0.08};
enum { kPoints = 180, kHistory = 64 };
// The voice's bands (SGRSpectrum.m: 24 bands, evenly in pitch), and how loud is loud: the DJ talks at -25 to -15 dB in
// those bands with its peaks at -14 (the phone's log, 2026-11-10), so the ring is round at -32 and fully dented only at
// the peaks, as Spotify's is now and then rather than throughout.
enum { kVoiceFirst = 5, kVoiceLast = 15 };
static const float kQuiet = -32, kLoud = -14;

// The dent's shape: how far in the ring goes at an angle (radians, clockwise from 3 o'clock on screen), 0 to 1 of the
// deepest. Fitted to the recording's deepest frame: deepest at 308 degrees (half past one), falling off faster towards
// 12 o'clock than towards 3, one smooth curve with no corners.
static const CGFloat kDentAt = 308, kDentLead = 40, kDentTrail = 46;
static CGFloat angleFrom(CGFloat angle, CGFloat centre) {
    CGFloat d = fmod(angle * 180 / M_PI - centre + 540, 360) - 180;
    return d;
}
static CGFloat dentAt(CGFloat angle) {
    CGFloat d = angleFrom(angle, kDentAt), w = d < 0 ? kDentLead : kDentTrail;
    return exp(-(d / w) * (d / w));
}
// Where the copies stand out past the ring: around the dent, from 11 o'clock to 5, most at 330 degrees.
static CGFloat copyAt(CGFloat angle) {
    CGFloat d = angleFrom(angle, 330) / 70;
    return exp(-d * d);
}
// How far out each copy stands at the dent's deepest, as a share of the radius: the teal one a line's width past the
// ring, the blue one half a line past the teal (the recording's deepest frame).
static const CGFloat kCopyPush[2] = {0.14, 0.22};
// How deep each copy dents beside the ring, which moves the most (its owner, 2026-11-10: "3 circles on top of each other
// that move with different intensities"; the recording's deepest frames).
static const CGFloat kCopyDent[2] = {0.65, 0.40};

@implementation SGRDJRingView {
    CAShapeLayer *_ring;
    CAShapeLayer *_copies[2];
    CADisplayLink *_link;
    // The dent's depth, 0 to 1, each frame, with when: the copies read it back.
    CGFloat _depths[kHistory];
    CFTimeInterval _times[kHistory];
    NSInteger _head;
    CGFloat _depth;
    CFTimeInterval _last;
    BOOL _reading;
}

- (instancetype)initWithFrame:(CGRect)frame {
    if (!(self = [super initWithFrame:frame])) return nil;
    self.backgroundColor = rgb(12, 88, 182);
    self.userInteractionEnabled = NO;
    self.isAccessibilityElement = NO;
    // The farther copy first, so the nearer one and the ring draw over it.
    _copies[1] = [self shapeIn:rgb(26, 151, 218)];
    _copies[0] = [self shapeIn:rgb(33, 215, 187)];
    _ring = [self shapeIn:rgb(26, 230, 143)];
    return self;
}

- (CAShapeLayer *)shapeIn:(UIColor *)color {
    CAShapeLayer *layer = [CAShapeLayer layer];
    layer.fillColor = UIColor.clearColor.CGColor;
    layer.strokeColor = color.CGColor;
    layer.lineCap = kCALineCapRound;
    layer.lineJoin = kCALineJoinRound;
    layer.actions = @{@"path": NSNull.null, @"position": NSNull.null, @"bounds": NSNull.null};
    [self.layer addSublayer:layer];
    return layer;
}

- (void)dealloc {
    [_link invalidate];
    if (_reading) SGRSpectrumNeedReader(NO);
}

- (void)layoutSubviews {
    [super layoutSubviews];
    CGFloat line = round([self radius] * kLine / kRadius);
    for (CAShapeLayer *layer in @[_copies[1], _copies[0], _ring]) {
        layer.frame = self.bounds;
        layer.lineWidth = line;
    }
    [self drawRing];
}

- (CGFloat)radius {
    return _ringRadius > 0 ? _ringRadius : MIN(self.bounds.size.width, self.bounds.size.height) * kRadius;
}

- (CGPoint)centre {
    return _ringRadius > 0 ? _ringCentre : CGPointMake(CGRectGetMidX(self.bounds), CGRectGetMidY(self.bounds));
}

- (void)setRingCentre:(CGPoint)centre {
    if (CGPointEqualToPoint(centre, _ringCentre)) return;
    _ringCentre = centre;
    [self setNeedsLayout];
}

- (void)setRingRadius:(CGFloat)radius {
    if (radius == _ringRadius) return;
    _ringRadius = radius;
    [self setNeedsLayout];
}

- (void)didMoveToWindow {
    [super didMoveToWindow];
    [self updateLink];
}

- (void)setMoving:(BOOL)moving {
    if (moving == _moving) return;
    _moving = moving;
    [self updateLink];
}

// The link and the spectrum's reader on only while it moves on screen. Stopped, the ring goes round again.
- (void)updateLink {
    BOOL on = _moving && self.window && !self.hidden;
    if (on != _reading) {
        _reading = on;
        SGRSpectrumNeedReader(on);
    }
    if (on && !_link) {
        _link = [CADisplayLink displayLinkWithTarget:self selector:@selector(step:)];
        // Not capped at 60: a link capped there drags the player's 120 Hz transitions down with it (AGENTS.md).
        _link.preferredFrameRateRange = CAFrameRateRangeMake(30, 120, 120);
        [_link addToRunLoop:NSRunLoop.mainRunLoop forMode:NSRunLoopCommonModes];
        _last = 0;
    } else if (!on && _link) {
        [_link invalidate];
        _link = nil;
        _depth = 0;
        for (NSInteger i = 0; i < kHistory; i++) _depths[i] = 0;
        [self drawRing];
    }
}

// How loud the voice is now, 0 to 1: the loudest of its bands, between kQuiet and kLoud.
- (CGFloat)voiceLevel {
    float levels[SGRSpectrumBands];
    SGRSpectrumRead(levels);
    float loudest = SGRSpectrumFloor;
    for (int i = kVoiceFirst; i <= kVoiceLast && i < SGRSpectrumBands; i++) loudest = MAX(loudest, levels[i]);
    return MAX(0, MIN(1, (loudest - kQuiet) / (kLoud - kQuiet)));
}

- (void)step:(CADisplayLink *)link {
    CFTimeInterval now = link.targetTimestamp;
    CFTimeInterval dt = _last > 0 ? MIN(0.1, now - _last) : 1.0 / 60;
    _last = now;
    CGFloat target = [self voiceLevel];
    // Spotify's goes from round to fully dented within a frame or two of its recording (a tenth of a second) and back as
    // quickly: in over 0.05 s, out over 0.1 s.
    CGFloat ease = 1 - exp(-dt / (target > _depth ? 0.05 : 0.1));
    _depth += (target - _depth) * ease;
    _head = (_head + 1) % kHistory;
    _depths[_head] = _depth;
    _times[_head] = now;
    [self drawRing];
}

// The depth lag seconds ago, from the frames kept.
- (CGFloat)depthBefore:(CFTimeInterval)lag {
    CFTimeInterval want = _times[_head] - lag;
    for (NSInteger back = 0; back < kHistory; back++) {
        NSInteger i = (_head - back + kHistory) % kHistory;
        if (_times[i] <= want || _times[i] == 0) return _depths[i];
    }
    return _depths[(_head + 1) % kHistory];
}

- (CGPathRef)pathFor:(CGFloat)depth CF_RETURNS_RETAINED {
    return [self pathFor:depth push:0];
}

// The ring at a depth; push moves it out around the dent, by that share of the radius at full depth.
- (CGPathRef)pathFor:(CGFloat)depth push:(CGFloat)push CF_RETURNS_RETAINED {
    CGPoint centre = [self centre];
    CGFloat radius = [self radius];
    CGMutablePathRef path = CGPathCreateMutable();
    for (NSInteger i = 0; i < kPoints; i++) {
        CGFloat a = 2 * M_PI * i / kPoints;
        CGFloat r = radius * (1 - kDentDepth * depth * dentAt(a) + push * depth * copyAt(a));
        CGPoint p = CGPointMake(centre.x + r * cos(a), centre.y + r * sin(a));
        if (i == 0) CGPathMoveToPoint(path, NULL, p.x, p.y);
        else CGPathAddLineToPoint(path, NULL, p.x, p.y);
    }
    CGPathCloseSubpath(path);
    return path;
}

- (void)drawRing {
    if (self.bounds.size.width < 1) return;
    CGPathRef ring = [self pathFor:_depth];
    _ring.path = ring;
    CGPathRelease(ring);
    for (NSInteger i = 0; i < 2; i++) {
        CGPathRef copy = [self pathFor:[self depthBefore:kCopyLag[i]] * kCopyDent[i] push:kCopyPush[i] / kCopyDent[i]];
        _copies[i].path = copy;
        CGPathRelease(copy);
    }
}

@end

// The DJ's logo, as the DJ sheet's Let DJ pick draws it (the 12 mini's screenshot, 2026-11-10): a ring and one line of the
// same weight inside it, which leaves the ring at one o'clock heading in towards the middle, bends, and joins it again
// along it just past three, an S. Fitted on the Mac against the screenshot (its owner: the leaf before "is not good").
static UIImage *drawnDJGlyph(CGFloat pointSize);

// Spotify's own DJ icon, from its asset catalog ("dj-button": a template vector, 48 points, in the 9.1.90 Assets.car),
// drawn at the size asked for; the drawn one below only if a version has none (its owner, 2026-11-10: "just match the icon").
// The part of an image that is drawn: the box round its pixels with any alpha, in points.
static CGRect inkBox(UIImage *image) {
    CGImageRef cg = image.CGImage;
    if (!cg) return CGRectMake(0, 0, image.size.width, image.size.height);
    size_t w = CGImageGetWidth(cg), h = CGImageGetHeight(cg);
    NSMutableData *data = [NSMutableData dataWithLength:w * h];
    CGContextRef ctx = CGBitmapContextCreate(data.mutableBytes, w, h, 8, w, NULL, (CGBitmapInfo)kCGImageAlphaOnly);
    if (!ctx) return CGRectMake(0, 0, image.size.width, image.size.height);
    CGContextDrawImage(ctx, CGRectMake(0, 0, w, h), cg);
    CGContextRelease(ctx);
    const uint8_t *alpha = data.bytes;
    size_t minX = w, minY = h, maxX = 0, maxY = 0;
    for (size_t y = 0; y < h; y++) for (size_t x = 0; x < w; x++) {
        if (alpha[y * w + x] < 16) continue;
        minX = MIN(minX, x); maxX = MAX(maxX, x); minY = MIN(minY, y); maxY = MAX(maxY, y);
    }
    if (maxX < minX) return CGRectMake(0, 0, image.size.width, image.size.height);
    CGFloat scale = image.scale;
    return CGRectMake(minX / scale, minY / scale, (maxX - minX + 1) / scale, (maxY - minY + 1) / scale);
}

// Spotify's own DJ icon, from its asset catalog ("dj-button": a template vector, 48 points, in the 9.1.90 Assets.car),
// its ring drawn to fill the size asked for, as the drawn glyph's did, whatever margin the catalog gives it (its owner,
// 2026-11-10: "just match the icon", then "slightly smaller than it used to be"). The drawn one below only if a version
// has none.
UIImage *SGRDJGlyphImage(CGFloat pointSize) {
    UIImage *own = [UIImage imageNamed:@"dj-button" inBundle:NSBundle.mainBundle compatibleWithTraitCollection:nil];
    if (!own) return drawnDJGlyph(pointSize);
    // Measured once, at the catalog's own size, rendered so a vector has pixels to read.
    static CGRect ink;
    static CGSize canvas;
    static dispatch_once_t once;
    dispatch_once(&once, ^{
        canvas = own.size;
        UIGraphicsImageRendererFormat *format = [UIGraphicsImageRendererFormat preferredFormat];
        format.scale = 3;
        UIImage *drawn = [[[UIGraphicsImageRenderer alloc] initWithSize:canvas format:format] imageWithActions:^(UIGraphicsImageRendererContext *c) {
            [own drawInRect:CGRectMake(0, 0, canvas.width, canvas.height)];
        }];
        ink = inkBox(drawn);
    });
    if (ink.size.width < 1 || ink.size.height < 1) ink = CGRectMake(0, 0, canvas.width, canvas.height);
    CGFloat zoom = pointSize / MAX(ink.size.width, ink.size.height);
    CGRect into = CGRectMake(-ink.origin.x * zoom, -ink.origin.y * zoom, canvas.width * zoom, canvas.height * zoom);
    // Centred, for an ink box that is not square.
    into.origin.x += (pointSize - ink.size.width * zoom) / 2;
    into.origin.y += (pointSize - ink.size.height * zoom) / 2;
    UIGraphicsImageRenderer *renderer = [[UIGraphicsImageRenderer alloc] initWithSize:CGSizeMake(pointSize, pointSize)];
    UIImage *image = [renderer imageWithActions:^(UIGraphicsImageRendererContext *context) {
        [own drawInRect:into];
    }];
    return [image imageWithRenderingMode:UIImageRenderingModeAlwaysTemplate];
}

static UIImage *drawnDJGlyph(CGFloat pointSize) {
    CGFloat side = pointSize, line = MAX(1.5, round(pointSize * 0.095 * 2) / 2);
    CGFloat radius = (side - line) / 2;
    CGPoint centre = CGPointMake(side / 2, side / 2);
    // The line's ends on the ring (degrees clockwise from 3 o'clock), and how far each end's handle reaches, as shares of
    // the radius: in along the radius at the start, back along the ring at the end.
    static const CGFloat kFrom = 286, kTo = 388, kLeave = 0.68, kJoin = 0.6;
    CGFloat from = kFrom * M_PI / 180, to = kTo * M_PI / 180;
    CGPoint start = CGPointMake(centre.x + radius * cos(from), centre.y + radius * sin(from));
    CGPoint end = CGPointMake(centre.x + radius * cos(to), centre.y + radius * sin(to));
    CGPoint leave = CGPointMake(start.x - kLeave * radius * cos(from), start.y - kLeave * radius * sin(from));
    CGPoint join = CGPointMake(end.x + kJoin * radius * sin(to), end.y - kJoin * radius * cos(to));
    UIGraphicsImageRenderer *renderer = [[UIGraphicsImageRenderer alloc] initWithSize:CGSizeMake(side, side)];
    UIImage *image = [renderer imageWithActions:^(UIGraphicsImageRendererContext *context) {
        UIBezierPath *ring = [UIBezierPath bezierPathWithArcCenter:centre radius:radius startAngle:0 endAngle:2 * M_PI clockwise:YES];
        UIBezierPath *fold = [UIBezierPath bezierPath];
        [fold moveToPoint:start];
        [fold addCurveToPoint:end controlPoint1:leave controlPoint2:join];
        for (UIBezierPath *path in @[ring, fold]) {
            path.lineWidth = line;
            path.lineCapStyle = kCGLineCapRound;
        }
        [UIColor.blackColor setStroke];
        [ring stroke];
        [fold stroke];
    }];
    return [image imageWithRenderingMode:UIImageRenderingModeAlwaysTemplate];
}
