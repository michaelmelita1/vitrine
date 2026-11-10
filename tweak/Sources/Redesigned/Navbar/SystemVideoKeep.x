// The music video kept playing behind the page's Picture in Picture (SystemPlayer.m's setUpPictureInPictureFor:). Spotify's
// video player (Betamax) turns the video off and plays the sound alone once the app is in the background, unless its own
// Picture in Picture is up: it asks BMVideoApplicationStateObservableImpl whether the app is backgrounded and its PiP
// controller source whether PiP is active (the binary, 2026-11-10: BMPlaybackSessionAttributes'
// initWithIsBackgrounded:isVideoDisabled:isPictureInPictureActive:...). The page's PiP is the mod's, so Spotify heard
// "backgrounded, no PiP" and the window went black (its owner, 2026-11-10). While the page's PiP is up, or ready to start
// as the app goes (canStartPictureInPictureAutomaticallyFromInline), both are answered for it.
#import "Core/SGCore.h"
#import "SystemPlayer.h"

static BOOL sg_armed, sg_active;

void SGRSystemVideoSetPiP(BOOL armed, BOOL active) {
    sg_armed = armed;
    sg_active = active;
}

%hook BMVideoApplicationStateObservableImpl
- (BOOL)isBackgrounded {
    return (sg_armed || sg_active) ? NO : %orig;
}
%end

%hook _TtC13BetamaxSDKAPI23PiPControllerSourceImpl
- (BOOL)isPictureInPictureActive {
    return sg_active || %orig;
}
%end

// What turns the video off in the background: it activates Betamax's audio-only profile on resigning active and on a
// change of the background state; held off while the page's PiP is ready or up.
%hook BMAudioOnlyProfileSwitcherImpl
- (void)setIsAudioOnlyProfileActivated:(BOOL)activated {
    %orig((sg_armed || sg_active) ? NO : activated);
}
%end

%ctor {
    if (!SGRedesignedUI() || !SGNativeRedesign()) return;
    %init;
}
