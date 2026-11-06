# Vitrine

A Theos tweak (Objective-C + Logos) injected into the decrypted Spotify iOS app. The full guide is
`docs/tweaks.md`; read it before changing code.

## One look: the redesign

Vitrine draws one look on Spotify's screens, the redesign (`Redesigned/`): the mod's own Liquid Glass look,
from a clean sheet. iOS's own tab bar with the mod's mini player in it (`Redesigned/Navbar/`) and the mod's own
player page in place of Spotify's (`Redesigned/Player/`), the glass search field, the lyrics page with Apple Music style
lyrics always on, a decluttered Home, Search's categories on tinted glass, a Library with one large title, the
playlist, album and artist pages the way the Music app lays them out with one pinned ⋯ over each, black
throughout, and its own accent color. There is no switch for it: the Redesigned UI switch, the native look it
picked between (`Native/`, Spotify's own screens with the mod's tweaks on them) and Native redesign's switch
are gone.

Anything that doesn't draw on Spotify's screens is `Shared/`: ads, privacy, lyrics sources, blocked artists,
flags, Vibrations, Speed and pitch and Sing. Some of those
were the redesign's until they moved to `Shared/`, so their keys lost the `.redesign.` and `Core/SGPrefs.h`'s
`SGMigrateKey` carries the old ones over at launch.

**The redesign is built for iOS 26.** It is Liquid Glass, which the system draws from 26 on and no older OS
can be given. `SGRedesignedUI()` (`Core/SGUIMode.h`) is `SGRedesignAvailable()`, iOS 26 and later: below 26
nothing of `Redesigned/` installs and Spotify keeps its own look, while `Shared/` and Mod Settings still run,
Mod Settings saying at its top that the look needs iOS 26 (`App/Onboarding/Environment.m`) and the tour saying
it once. Spotify 9.1.78's own floor is iOS 16.1. Vitrine is made for Spotify 9.1.78 and supports 9.1.88 and
9.1.90, the daily test build. The install warning leaves all three alone. A new version goes in one of the two lists
in `App/Onboarding/Onboarding.h` (`SGSpotifySupportedVersions`, `SGSpotifyLikelyWorksVersions`), and the warning's text
and About follow. The IPA build reads
Spotify's flag table from the IPA it builds, and again when the version changes.

## Where code goes (`tweak/Sources/`)

| Layer | What | Gate at the top of every `%ctor` |
|---|---|---|
| `Shared/` | behavior and data that draw on no Spotify screen | none |
| `Redesigned/` | the redesign (`Kit/` + parts) | `if (!SGRedesignedUI()) return;` |
| `App/` | Mod Settings root and combined pages, Mod page, tour | none |
| `Core/`, `Settings/`, `Headers/`, `Diagnostics/` | infrastructure | none |

Rules:

- Imports run one way: `Core <- Settings <- Shared <- Redesigned <- App`. `scripts/check-layers.sh` runs
  before every build and fails on a violation. Don't work around it.
- The redesign's names start `SGR…` and its keys `spotifyglass.redesign.`; `Shared/`'s start `SG…`.
- A lower layer that needs something from a higher one gets it through a registry in `Core`
  (forced flags: `Core/SGFlagForce.h`) or a function declared low and defined high.
- Settings: each layer builds its own rows and sections; `App/Pages.m` and `App/ModSettings.x` put them on
  their pages.
- Keys start with `spotifyglass.` (redesign-only ones with `spotifyglass.redesign.`). Switches are
  read live through the `Core/SGPrefs.m` memo, but any feature whose `%ctor` installs its hooks only when it
  is on takes effect at the next launch.

## Working on it

- Build: `make install` (signs and pushes to the phone), `make quick` (a tweak-only change, in seconds), `make release` (IPA only). Tweak only:
  `env -u MAKELEVEL gmake -C tweak clean package`.
- Look at Spotify's views through recorded trees (`make session` records clean ones into
  `trees/clean/`) before hooking anything. Prove every class and selector against the tree or the binary.
- Device log: `make log` (`[spotifyglass]` lines).
- Releases: Release Please (`.github/workflows/release.yml`). Commit as `feat:` / `fix:` (they bump
  `version.txt` and fill `CHANGELOG.md`; `chore:`, `refactor:` and `docs:` stay out). Merging its
  release PR tags `vX.Y.Z` and builds the tweak to check it compiles; nothing is attached. Never edit `version.txt` by hand.
- Known traps: anything pushed onto Spotify's nav stack must conform to `SPTPageController`
  (`Settings/SGPage.m`). Setting `hidden` on views inside Spotify's `OverflowStackView` or its Encore
  stacks crashes, so use alpha. A `CADisplayLink` capped at 60 Hz drags the player's 120 Hz
  transitions down with it. Never observe a notification that other threads post (`NSUserDefaultsDidChangeNotification`,
  `AVAudioSessionRouteChangeNotification`) with `queue:NSOperationQueue.mainQueue`: the posting thread waits
  for main, and at launch main waits on Spotify's CoreThread, so Spotify hangs and is killed. Use `queue:nil`
  and `dispatch_async` to main. Glass takes the appearance it inherits, and outside Spotify's navigation
  stacks (the tab bar, the now playing bar, the player) that is the system's: set every pane of the
  mod's to `overrideUserInterfaceStyle = UIUserInterfaceStyleDark`, or it goes light in light mode. Present a
  controller of the mod's through `SGPresentDark` (`Core/SGGlass.h`): a sheet's glass is its presentation's, and the
  controller's own override does not reach it. ARC does not know that `init` consumes its receiver: calling
  `alloc`/`init` through a cast `objc_msgSend` over-releases when `init` returns another object, so do both on
  `void *` and hand the result to `CFBridgingRelease`. A Logos hook on an `init…` that returns another object
  returns it with `CFBridgingRetain`, or the app crashes at launch. iOS 26's scroll edge effect blurs any header
  that sits inside its own scroll view; hide that list's `topEdgeEffect`.
