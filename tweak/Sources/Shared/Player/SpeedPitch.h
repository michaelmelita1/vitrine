// Speed and pitch done to Spotify's sound, and the chain the mod's processors share on its output, under either look.
// Nothing here draws.
//
//     SpeedPitch.x       Spotify's output taken over between its mixer and its speaker unit, where speed and pitch, Sing's
//                        stage, the audio effects and Music Haptics run, and Spotify's outputs kept apart, one of them the
//                        music's (SGPlayerMusicOutput)
//     SGTimePitch.m      Apple's time and pitch unit, pulling the mixer or working in place
//
// The speed is set by the player page's hold on the cover (2×); neither speed nor pitch is stored.
// Threading: main thread only, except what SGTimePitch.h says runs on the render thread.
#import <UIKit/UIKit.h>
#import <AudioToolbox/AudioToolbox.h>

// The speed Spotify's sound plays at, 1 when normal.
double SGPlayerSpeed(void);
// Whether speed can apply: Spotify's output was taken over when it wired it.
BOOL SGPlayerSpeedAllowed(void);
void SGSetPlayerSpeed(double speed);
// Semitones Spotify's output is moved by, 0 when it is not.
float SGPlayerPitch(void);
void SGSetPlayerPitch(float semitones);
// Speed and pitch move together, like a record, by resampling rather than the time stretch. On until
// switched off, from the switch under the two sliders.
#define SGKeyPitchFollowsSpeed @"spotifyglass.speed.pitchFollows"
BOOL SGPlayerPitchFollowsSpeed(void);
void SGSetPlayerPitchFollowsSpeed(BOOL follows);
// Whether the output could be reached to change its pitch.
BOOL SGPlayerPitchAvailable(void);
// The mod's own volume on Spotify's sound, 0 to 1, 1 when normal: the sleep timer's fade (SleepTimer.h).
// Any thread. The sound moves to it within half a second and never in a step. It scales what the speaker
// unit plays, in the output's own format, so a Connect device is left as it was, and it
// does nothing when Spotify's output was never reached (AudioOutputUnitStart not rebound). Not stored.
void SGPlayerSetGain(float gain);

// A stage between Spotify's mixer and the rest of the chain (Sing's look-ahead, Shared/Sing): it fills the
// chain's buffers, pulling the mixer through `pull` as much as it likes. NULL passes the mixer straight on.
// Called on the render thread, and only on the music's output (below) while Spotify's connection to it is taken
// over (SGPlayerSpeedAllowed). The buffers are in SGPlayerMusicClientFormat's format. With `sounding` set, a pull stops
// at the first part the mixer marks silent (Spotify has none of its sound there yet), leaves the rest silent unrendered
// and sets the frames before it; without, every part is rendered, silent or not.
typedef OSStatus (*SGPlayerPull)(void *context, UInt32 frames, AudioBufferList *data, UInt32 *sounding);
typedef OSStatus (*SGPlayerStage)(UInt32 frames, AudioBufferList *data, SGPlayerPull pull, void *context);
void SGPlayerSetStage(SGPlayerStage stage);
@class SPTPlayerState;
// Sing's lead, for the own clock -[SPTPlayerState position] keeps away from 1x (SpeedPitch.x): the seconds it holds ahead
// of what plays now, and the correction it takes off a report. Set once by Sing.x.
typedef double (*SGPlayerHeldLead)(void);
typedef double (*SGPlayerLeadOf)(SPTPlayerState *state);
void SGPlayerSetLeadReaders(SGPlayerHeldLead held, SGPlayerLeadOf of);

// The music's output: of the RemoteIO units Spotify runs at once (a chain per sample rate, and voice search's),
// the one that carries every processor of its sound (speed and pitch, Sing's stage, the audio effects, Music
// Haptics), NULL until Spotify connects or starts one. Any thread; the render thread compares it with a render
// notify's unit to process the music's output alone.
AudioUnit SGPlayerMusicOutput(void);
// The format Spotify hands the music's output (its input scope, element 0), the one the stage's buffers are
// in. NO when there is no such output. Not on the render thread.
BOOL SGPlayerMusicClientFormat(AudioStreamBasicDescription *format);
// `watcher` is called with the music's output each time it changes (NULL when there is none any more), Spotify
// starts it again, or a format of it changes: the time to read its format, add a render notify to it and start
// over what was held. Called on Spotify's audio thread or a queue of Shared/Player's, under a lock a dispose
// waits for, so the unit stays alive through the call; it must not wait on the main thread. NO when
// Spotify's output cannot be reached at all. Register from a %ctor; up to four.
typedef void (*SGPlayerOutputWatcher)(AudioUnit output);
BOOL SGPlayerWatchMusicOutput(SGPlayerOutputWatcher watcher);

#if SG_DRIVER
// Speed-rebuffer test (FLEX builds): completed runs of silence from the music's mixer so far, and the last one's
// start (mach time) and length; silentNow while one is running.
uint64_t SGSpeedProbeSilence(uint64_t *host, double *ms, bool *silentNow);
#endif
