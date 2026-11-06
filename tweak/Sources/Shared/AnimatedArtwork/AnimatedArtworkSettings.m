// What the lock screen fills the screen with, the lyrics' style and whether the downloads run in Low Data
// Mode. iOS 26 and up only.
#import "Core/SGCore.h"
#import "Settings/SGModPage.h"
#import "Settings/SGPageStyle.h"
#import "AnimatedArtwork.h"

SGLockArtwork SGLockScreenArtwork(void) {
    if (@available(iOS 26.0, *)) {
        // The old switch's YES and NO read as Moving artwork and Off, the enum's first two.
        static dispatch_once_t once;
        dispatch_once(&once, ^{ SGMigrateKey(SGKeyLockScreenMotion, SGKeyLockScreenArtwork); });
        switch (SGInt(SGKeyLockScreenArtwork, SGLockArtworkOff)) {
            case 1: case 4: return SGLockArtworkMotion;   // 4 was Moving artwork with lyrics
            case 3: return SGLockArtworkEverySong;
            default: return SGLockArtworkOff;             // 2 was Lyrics
        }
    }
    return SGLockArtworkOff;
}

CGSize SGLockClipSize(CGFloat pixels) {
    CGFloat width = MAX(floor(pixels / 16) * 16, 16);
    return CGSizeMake(width, round(width * 4 / 3 / 16) * 16);
}

NSArray *SGLockScreenMotionRows(void) {
    if (@available(iOS 26.0, *)) {
        SGLockScreenArtwork();   // moves the old switch over before the row reads the new key
        NSArray<NSString *> *names = @[@"Off", @"Moving artwork", @"Every song"];
        NSArray<NSNumber *> *values = @[@(SGLockArtworkOff), @(SGLockArtworkMotion), @(SGLockArtworkEverySong)];
        SGModRow *artwork = SGMenuRow(@"Full-screen artwork", names, ^NSString *{
            NSUInteger at = [values indexOfObject:@(SGLockScreenArtwork())];
            return names[at == NSNotFound ? 0 : at];
        }, ^(NSInteger index) { SGSetInt(SGKeyLockScreenArtwork, values[(NSUInteger)index].integerValue); });
        SGModRow *lowData = SGOptionRow(@"Download in Low Data Mode", @"Moving artwork, up to about 7 MB a song", SGKeyMotionLowData);
        lowData.visible = ^BOOL { return SGLockScreenArtwork() != SGLockArtworkOff; };
        SGModRow *sources = SGMotionSourcesRow();
        sources.visible = lowData.visible;
        return @[artwork, sources, lowData];
    }
    return @[SGLockScreenArtworkNeedsRow()];
}

// Below iOS 26 the section stays, with one row that says why there is nothing to pick.
SGModRow *SGLockScreenArtworkNeedsRow(void) {
    return SGStatActionRow(@"Full-screen artwork", nil, ^NSString *{ return @"Needs iOS 26"; }, ^{
        NSString *message = [NSString stringWithFormat:@"This iPhone has iOS %@. The lock screen takes moving artwork "
                                                       @"from apps from iOS 26 on, so the Canvas and Apple Music's animated "
                                                       @"covers can show there once the iPhone is updated.", UIDevice.currentDevice.systemVersion];
        UIAlertController *alert = [UIAlertController alertControllerWithTitle:@"Needs iOS 26" message:message
                                                                preferredStyle:UIAlertControllerStyleAlert];
        [alert addAction:[UIAlertAction actionWithTitle:@"OK" style:UIAlertActionStyleCancel handler:nil]];
        [SGTopController() presentViewController:alert animated:YES completion:nil];
    });
}
