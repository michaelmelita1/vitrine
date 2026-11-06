// Settings of the player that hold on any iOS.
#import <UIKit/UIKit.h>

UIViewController *SGLockScreenWidgetPage(void);

// Switch to video hidden from Spotify's player (VideoSwitch.x), off until switched on. The redesign's player page
// shows its switch on the Player page's Controls, though the page has no video chip yet (Redesigned/Player/
// SystemPlayer.m's TODO).
#define SGKeyHideVideoSwitch @"spotifyglass.hide.videoSwitch"
