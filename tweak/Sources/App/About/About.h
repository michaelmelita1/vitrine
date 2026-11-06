// About: the Mod page, the build's stamp, the licenses, signing and backups.
#import <UIKit/UIKit.h>
#import "Settings/SGModPage.h"

// Which build this is: the commit, plus the build time when it had uncommitted changes (scripts/build-stamp.sh).
const char *SGBuildStamp(void);
// The version with that stamp after it, as Mod Settings shows it.
NSString *SGVersionWithBuild(void);
UIViewController *SGLicensesPage(void); // Licenses.m: the mod's license and the third-party ones it ships

// Whether the now playing card on the lock screen can open this build. It depends on the signature,
// not on the mod: iOS launches by the App ID of the application-identifier entitlement, so a build
// whose bundle id is not that App ID cannot be opened from the card. Signing.m says so once.
NSString *SGSigningAppIdentifier(void);      // App ID without the team prefix, nil if unreadable
BOOL SGSigningOpensFromLockScreen(void);     // YES when unreadable, so a build that works stays quiet
SGModRow *SGSigningWarningRow(void);          // nil while the signature is sound
void SGCheckSigningOnce(void);
// When the provisioning profile the build is signed with runs out, read from embedded.mobileprovision:
// nil without one. A free Apple ID's lasts a week, after which Spotify no longer opens.
BOOL SGSigningWeekLong(void);
SGModRow *SGSigningExpiryRow(void);   // "Signed until …", nil without a profile

// Backup.m: the settings out to a JSON file through the share sheet, and back in from one, replacing
// what is set and restarting.
void SGExportSettings(void);
void SGImportSettings(void);
// A text file for a bug report through the share sheet: the versions and switches, the ad counts, this launch's
// log lines and the config Spotify's server last sent (Shared/AdBlock/Premium.m). No account details or settings
// values beyond the switches named; the log can name songs played.
void SGShareDiagnostics(void);

UIViewController *SGAboutPage(void);   // the Mod page
