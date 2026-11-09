#import "SystemJam.h"

static BOOL isJamHat(UIView *view) {
    return [NSStringFromClass(view.class) containsString:@"JamHatElement"];
}

static BOOL isFacepile(UIView *view) {
    return [NSStringFromClass(view.class) hasSuffix:@"FacepileStackView"];
}

// One walk of the windows: whether a Jam hat is in them and every face image in a facepile. Hidden ones count: the
// redesign hides Spotify's own now playing bar, which is where the hat is, and Spotify takes the hat out when the Jam ends
// (the owner's Jam log, 2026-11-09).
// Home's avatar, the button that opens the side drawer ("Your profile and settings", id Components.UI.SideDrawerButton in
// 9.1.90's tree; an AdaptiveFaceContainer in older builds), whose picture is the user's own.
static BOOL isOwnFace(UIView *view) {
    return [view.accessibilityIdentifier isEqualToString:@"Components.UI.SideDrawerButton"]
        || [NSStringFromClass(view.class) hasSuffix:@"AdaptiveFaceContainer"];
}

// The picture in `root`, the user's own in Home's avatar (ListeningActivity_ElementsKit's AdaptiveFaceContainer,
// HomeHeader.x): the largest image view's image, or a picture drawn straight onto a layer. Not held to square: the
// avatar is 32x34 (HomeHeader.x's tree), and taking only squares found nothing (its owner, 2026-11-09).
static void largestImageIn(UIView *root, UIImage **best, CGFloat *bestSide) {
    CGFloat side = MIN(root.bounds.size.width, root.bounds.size.height);
    UIImage *image = nil;
    if ([root isKindOfClass:UIImageView.class]) image = ((UIImageView *)root).image;
    else if ([root isKindOfClass:UIButton.class]) image = [(UIButton *)root imageForState:UIControlStateNormal];
    if (!image) {
        id contents = root.layer.contents;
        if (contents && CFGetTypeID((__bridge CFTypeRef)contents) == CGImageGetTypeID())
            image = [UIImage imageWithCGImage:(__bridge CGImageRef)contents];
    }
    if (image && side >= 16 && side > *bestSide && image.size.width >= 16 && image.renderingMode != UIImageRenderingModeAlwaysTemplate) {
        *best = image;
        *bestSide = side;
    }
    for (UIView *sub in root.subviews) largestImageIn(sub, best, bestSide);
}

static UIImage *imageIn(UIView *root) {
    UIImage *best = nil;
    CGFloat side = 0;
    largestImageIn(root, &best, &side);
    return best;
}

static UIImage *sg_ownFace;

// Kept on disk too, so a Jam already on when Spotify opens shows it before Home has loaded the avatar (its owner,
// 2026-11-09: silhouettes then).
static NSString *ownFacePath(void) {
    NSString *dir = [NSSearchPathForDirectoriesInDomains(NSCachesDirectory, NSUserDomainMask, YES).firstObject stringByAppendingPathComponent:@"Vitrine"];
    [NSFileManager.defaultManager createDirectoryAtPath:dir withIntermediateDirectories:YES attributes:nil error:nil];
    return [dir stringByAppendingPathComponent:@"own-face.png"];
}

static void keepOwnFace(UIImage *own) {
    if (own == sg_ownFace) return;
    sg_ownFace = own;
    // Once a launch: the avatar's image is handed over anew on many passes.
    static BOOL written;
    if (written) return;
    written = YES;
    dispatch_async(dispatch_get_global_queue(QOS_CLASS_UTILITY, 0), ^{
        [UIImagePNGRepresentation(own) writeToFile:ownFacePath() atomically:YES];
    });
}

static UIImage *ownFace(void) {
    static BOOL read;
    if (!sg_ownFace && !read) {
        read = YES;
        sg_ownFace = [UIImage imageWithContentsOfFile:ownFacePath()];
    }
    return sg_ownFace;
}

// Inside one of Spotify's Jam views: a class of the Jam's or of social listening on the way down. Facepiles elsewhere
// show other people, an artist's on a page among them (the owner's recording, 2026-11-09: the artist playing showed
// in the Jam's faces), so only these are read.
static BOOL isJamView(UIView *view) {
    NSString *name = NSStringFromClass(view.class);
    return [name containsString:@"Jam"] || [name containsString:@"SocialListening"] || [name containsString:@"SocialSession"];
}

static void walkIn(UIView *view, BOOL inJam, BOOL inFacepile, BOOL *hat, NSMutableArray<UIImage *> *faces);

static void walk(UIView *view, BOOL inFacepile, BOOL *hat, NSMutableArray<UIImage *> *faces) {
    walkIn(view, NO, inFacepile, hat, faces);
}

static void walkIn(UIView *view, BOOL inJam, BOOL inFacepile, BOOL *hat, NSMutableArray<UIImage *> *faces) {
    if (!*hat && isJamHat(view)) *hat = YES;
    inJam = inJam || isJamView(view);
    if (isOwnFace(view)) {
        UIImage *own = imageIn(view);
        if (own) keepOwnFace(own);
    }
    BOOL facepile = inFacepile || (inJam && isFacepile(view));
    if (facepile && [view isKindOfClass:UIImageView.class]) {
        UIImage *image = ((UIImageView *)view).image;
        CGSize size = view.bounds.size;
        if (image && size.width >= 12 && fabs(size.width - size.height) < 2 && ![faces containsObject:image]) [faces addObject:image];
    }
    for (UIView *sub in view.subviews) walkIn(sub, inJam, facepile, hat, faces);
}

NSArray<UIImage *> *SGRSystemJamFaces(NSUInteger max) {
    BOOL hat = NO;
    NSMutableArray<UIImage *> *faces = [NSMutableArray array];
    for (UIScene *scene in UIApplication.sharedApplication.connectedScenes) {
        if (![scene isKindOfClass:UIWindowScene.class]) continue;
        for (UIWindow *window in ((UIWindowScene *)scene).windows) walk(window, NO, &hat, faces);
    }
    // Spotify shows the facepile only while its Jam sheet is up, so the faces seen are kept for as long as the Jam lasts
    // (the owner's recording, 2026-11-09: the faces came and went); before any, the user's own picture, the host's.
    static NSArray<UIImage *> *kept;
    if (!hat) {
        kept = nil;
        return nil;
    }
    if (faces.count) kept = faces.count > max ? [faces subarrayWithRange:NSMakeRange(0, max)] : faces.copy;
    if (kept.count) return kept;
    return ownFace() ? @[ownFace()] : @[];
}
