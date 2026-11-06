// Hold to play faster on the cover of the player page (SystemPlayer.m): holding either side of
// it plays at 2x until the finger lifts, with a 2x badge on the Kit's glass at its top.
#import "Core/SGCore.h"
#import "Redesigned/Kit/SGRKit.h"
#import "Shared/Haptics/Haptics.h"
#import "Shared/Player/SpeedPitch.h"
#import "Player.h"

#pragma mark - hold to play faster

// Holding either side of the cover plays at kHoldSpeed until the finger lifts, and the speed set before
// comes back. The middle third is left alone, and a hold that starts to move is a swipe to the next track.
// It is a speed like the menu's, so with Pitch follows speed on (until switched off) it also plays an
// octave higher, the way a record does.
static const double kHoldSpeed = 2;
static char kHoldKey, kBadgeGlassKey;

@interface SGRCoverHold : UILongPressGestureRecognizer
@end

@implementation SGRCoverHold {
    double _before;
    UIView *_badge;
    UILabel *_badgeLabel;
    BOOL _badgeShown;
}

- (void)sgr_held {
    UIView *cover = self.view;
    if (self.state == UIGestureRecognizerStateBegan) {
        CGFloat x = [self locationInView:cover].x, third = cover.bounds.size.width / 3;
        if ((x > third && x < 2 * third) || !SGPlayerSpeedAllowed()) {
            self.enabled = NO;
            self.enabled = YES;   // cancels this hold
            return;
        }
        _before = SGPlayerSpeed();
        SGSetPlayerSpeed(kHoldSpeed);
        SGPlayFeedback(SGFeedbackGrab);
        [self showBadge:YES on:cover];
        UIAccessibilityPostNotification(UIAccessibilityAnnouncementNotification, @"Playing at 2 times speed");
    } else if (self.state == UIGestureRecognizerStateEnded || self.state == UIGestureRecognizerStateCancelled
               || self.state == UIGestureRecognizerStateFailed) {
        if (_before > 0) SGSetPlayerSpeed(_before);
        _before = 0;
        [self showBadge:NO on:cover];
    }
}

// "2×" and a forward glyph on the Kit's glass capsule at the top of the cover while it is held. What fades
// is the glass's effect (SGRShowGlass), never an alpha over it; the capsule grows in from 0.9 with the Kit's
// press spring and goes with its exit, quicker than it came: the finger is already off the cover.
- (void)showBadge:(BOOL)shown on:(UIView *)cover {
    if (shown && !_badge) {
        _badgeLabel = [UILabel new];
        UIFont *font = [UIFont systemFontOfSize:15 weight:UIFontWeightSemibold];
        NSTextAttachment *arrows = [NSTextAttachment textAttachmentWithImage:[[UIImage systemImageNamed:@"forward.fill"
            withConfiguration:[UIImageSymbolConfiguration configurationWithFont:font]] imageWithTintColor:UIColor.whiteColor
            renderingMode:UIImageRenderingModeAlwaysOriginal]];
        NSMutableAttributedString *text = [[NSMutableAttributedString alloc] initWithString:@"2×  "
            attributes:@{NSFontAttributeName: font, NSForegroundColorAttributeName: UIColor.whiteColor}];
        [text appendAttributedString:[NSAttributedString attributedStringWithAttachment:arrows]];
        _badgeLabel.attributedText = text;
        _badgeLabel.textAlignment = NSTextAlignmentCenter;
        _badge = [[UIView alloc] initWithFrame:CGRectMake(0, 0, 92, 34)];
        _badge.userInteractionEnabled = NO;
        _badgeLabel.frame = _badge.bounds;
        _badgeLabel.autoresizingMask = UIViewAutoresizingFlexibleWidth | UIViewAutoresizingFlexibleHeight;
        [_badge addSubview:_badgeLabel];
    }
    if (!_badge) return;
    _badgeShown = shown;
    UIView *badge = _badge, *label = _badgeLabel;
    // Made again by the Kit if Reduce Transparency changed: then it is a solid fill, which fades by alpha.
    UIView *shape = SGRGlassCapsuleInside(badge, &kBadgeGlassKey, badge.bounds.size, NO);
    void (^state)(BOOL) = ^(BOOL on) {
        SGRShowGlass(shape, on);
        label.alpha = on ? 1 : 0;
    };
    if (shown) {
        if (badge.superview != cover) {
            badge.center = CGPointMake(CGRectGetMidX(cover.bounds), 30);
            state(NO);
            badge.transform = SGRReduceMotion() ? CGAffineTransformIdentity : CGAffineTransformMakeScale(0.9, 0.9);
            [cover addSubview:badge];
        }
        // A fade alone under Reduce Motion, where the Kit's spring would be no animation at all.
        SGRAnimate(SGRReduceMotion() ? SGRMotionFade : SGRMotionPress, ^{
            state(YES);
            badge.transform = CGAffineTransformIdentity;
        }, nil);
    } else {
        SGRAnimate(SGRMotionExit, ^{ state(NO); }, ^(BOOL finished) {
            if (finished && !self->_badgeShown) [badge removeFromSuperview];
        });
    }
}

@end

static void watchHold(UIView *tilt) {
    if (objc_getAssociatedObject(tilt, &kHoldKey)) return;
    SGRCoverHold *hold = [[SGRCoverHold alloc] initWithTarget:nil action:nil];
    [hold addTarget:hold action:@selector(sgr_held)];
    hold.minimumPressDuration = 0.35;
    [tilt addGestureRecognizer:hold];
    objc_setAssociatedObject(tilt, &kHoldKey, hold, OBJC_ASSOCIATION_ASSIGN);
}

void SGRPlayerAttachCoverHold(UIView *cover) {
    if (cover) watchHold(cover);
}
