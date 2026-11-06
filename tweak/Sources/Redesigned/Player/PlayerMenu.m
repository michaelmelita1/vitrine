// The player page's Artwork submenu (SystemPlayer.m's ⋯): Fluid, Visualizer or Animated, while the background is one of
// the three.
#import "Core/SGCore.h"
#import "Shared/Player/PlayerState.h"
#import "Player.h"

UIMenu *SGRPlayerMenuArtwork(void (^changed)(void)) {
    if (!SGPlayerMenuOffersAnimatedArtwork()) return nil;
    NSArray<NSArray *> *backgrounds = @[
        @[@(SGRPlayerBackgroundFluid), @"Fluid", @"drop"],
        @[@(SGRPlayerBackgroundVisualiser), @"Visualizer", @"waveform"],
        @[@(SGRPlayerBackgroundAnimated), @"Animated", @"play.rectangle.on.rectangle"],
    ];
    SGRPlayerBackgroundKind current = SGRPlayerBackground();
    NSMutableArray<UIMenuElement *> *items = [NSMutableArray array];
    NSString *currentName = nil;
    for (NSArray *background in backgrounds) {
        SGRPlayerBackgroundKind kind = [background[0] integerValue];
        UIAction *pick = [UIAction actionWithTitle:background[1] image:[UIImage systemImageNamed:background[2]] identifier:nil handler:^(UIAction *action) {
            SGRPlayerMenuSetBackground(kind);
            if (changed) changed();
        }];
        if (kind == current) {
            pick.state = UIMenuElementStateOn;
            currentName = background[1];
        }
        [items addObject:pick];
    }
    UIMenu *menu = [UIMenu menuWithTitle:@"Artwork" image:[UIImage systemImageNamed:@"photo"] identifier:nil options:0 children:items];
    menu.subtitle = currentName;
    return menu;
}
