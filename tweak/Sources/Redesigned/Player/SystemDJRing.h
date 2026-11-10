// The AI DJ talking, drawn as Spotify draws it on its own DJ screen, which the player page stands in for (its owner,
// 2026-11-10): a green ring on Spotify's DJ blue that dents with the voice, with two copies of where it was. Spotify's
// own (Endless_AIDJVisualizationKit) cannot be made from outside: its views trap when created (2026-11-09).
#import <UIKit/UIKit.h>

@interface SGRDJRingView : UIView
// Moving: the ring follows the voice (the output's spectrum, SGRSpectrum.h) at up to 60 frames a second. Off, it rests.
@property (nonatomic) BOOL moving;
// Where the ring stands in the view and how large (to the middle of its line), its line a seventh of that, as Spotify's.
// With no radius set, the middle of the view and a share of its side.
@property (nonatomic) CGPoint ringCentre;
@property (nonatomic) CGFloat ringRadius;
@end

// The DJ X logo as a template image a point size across: the ring and, inside its upper right, the dent's curve, as on
// Spotify's DJ button. For the player's DJ button (SystemPlayer.m).
UIImage *SGRDJGlyphImage(CGFloat pointSize);
