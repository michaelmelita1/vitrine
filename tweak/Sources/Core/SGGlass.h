// Glass panes: one UIVisualEffectView per host, kept behind the host's own content.
#import <UIKit/UIKit.h>

// UIGlassEffect made the only way that resolves its material, or a dark chrome blur before iOS 26.
UIVisualEffect *SGGlassEffect(void);
UIVisualEffectView *SGGlassFor(UIView *host, const void *key);
// Several panes on one host, addressed by index.
UIVisualEffectView *SGGlassAt(UIView *host, NSUInteger index);
// Glass takes its shape from cornerConfiguration on iOS 26; layer.cornerRadius is the fallback.
void SGShapeGlass(UIView *glass, CGFloat radius, BOOL capsule);

// Dark whatever the system is set to, for a controller the mod presents. A sheet's glass is its presentation's,
// which the controller's own override does not reach. Call it after modalPresentationStyle is set.
void SGPresentDark(UIViewController *controller);

// The areas the redesign keeps transparent are its own: Redesigned/Kit/SGRRepaint.h.
