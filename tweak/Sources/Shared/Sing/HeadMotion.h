// Head motion from AirPods Pro, AirPods 3 and later, AirPods Max and some Beats (CMHeadphoneMotionManager), for
// Karaoke's spatial voice. The app's one manager: iOS hands a manager's motion to one handler.
// Threading: main thread only, but for the listeners' handlers.
#import <CoreMotion/CoreMotion.h>

// Head motion under `name`; a nil handler takes it out. While any listener is in, the manager runs. A handler is
// called on the motion's serial queue with every motion, and with nil when the motion stops: the headphones gone,
// the manager stopped, or the listener taken out.
void SGHeadMotionListen(NSString *name, void (^handler)(CMDeviceMotion *motion));
// Asks for Motion & Fitness now, while a page is in front, if it was never asked and nothing listens yet.
void SGHeadMotionAskPermission(void);
// Whether this iPhone can read headphone motion at all (the headphones are another matter).
BOOL SGHeadMotionAvailable(void);
