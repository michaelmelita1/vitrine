// Native redesign's output glyph (SystemPlayer.m's AirPlay button, the mini player's): the device playing drawn as the
// Music app draws it, AirPods by model, a HomePod, a Mac, EarPods..., with its name for the line under it. This was the
// redesigned player's footer glyph in PR #192; the redesigned player keeps Spotify's own Connect glyph, and only Native
// redesign draws this. A Spotify Connect device is drawn as AirPlay: its name came from the redesigned player's footer,
// which is not up under Native redesign.
#import <AVFoundation/AVFoundation.h>
#import <objc/message.h>
#import <objc/runtime.h>
#import "Core/SGCore.h"
#import "Redesigned/Kit/SGRKit.h"
#import "Navbar.h"
#import "SystemPlayer.h"

static NSString *const kConnectSymbol = @"airplayaudio";

NSNotificationName const SGRPlayerOutputDidChangeNotification = @"spotifyglass.redesign.playerOutputDidChange";

// Everything that can change the glyph comes through here (a route change and its late fill-ins, MediaPlayer's answer):
// the page and the mini player ask SGRPlayerOutputSymbol again.
static void paintConnectAgain(void) {
    [NSNotificationCenter.defaultCenter postNotificationName:SGRPlayerOutputDidChangeNotification object:nil];
}

// The middle glyph is the output's, as the Music app's is: AirPlay audio on the phone, AirPods, headphones, a HomePod,
// a car (its owner's screenshots, 2026-10-30). iOS gives an app the route's type and name and, through AVFoundation's
// output devices, a kind (AVOutputDevice's deviceSubType, 2 for the AirPods, 12 for a HomePod mini, the phone's log);
// the model and the system's own symbol name come back empty, so AirPods are told apart by their name and a HomePod
// is drawn as the full-size one until MediaPlayer names its model (fetchPicked). A Spotify Connect device plays with the phone's own route, so it keeps AirPlay.
typedef NS_ENUM(NSInteger, SGROutputKind) { SGROutputKindHeadphones = 2, SGROutputKindHeadset = 3, SGROutputKindTV = 11, SGROutputKindHomePod = 12, SGROutputKindAppleTV = 13, SGROutputKindCar = 14 };

// The AirPlay route MediaPlayer says is picked, its name and its model (fetchPicked). Stale from a route change until the
// next answer: two AirPlay routes can both be named "AirPlay", so the last answer may be the other device's.
static NSString *sg_pickedName, *sg_pickedProduct, *sg_pickedFor;
static BOOL sg_pickedStale;

// The output device playing: the one named as the route is, or, for an AirPlay route iOS names only "AirPlay" (the
// phone's log, 2026-10-30), the AirPlay one (deviceType 0) among them. The context's list can hold more than one.
static id outputDevice(AVAudioSessionPortDescription *port) {
    @try {
        Class contextClass = NSClassFromString(@"AVOutputContext");
        if (![contextClass respondsToSelector:@selector(sharedSystemAudioContext)]) return nil;
        NSArray *devices = [[contextClass performSelector:@selector(sharedSystemAudioContext)] valueForKey:@"outputDevices"];
        id named = nil, airPlay = nil;
        for (id device in devices) {
            if ([[device valueForKey:@"name"] isEqual:port.portName]) named = device;
            if (!airPlay && [[device valueForKey:@"deviceType"] integerValue] == 0) airPlay = device;
        }
        if (named) return named;
        return [port.portType isEqualToString:AVAudioSessionPortAirPlay] ? airPlay : (devices.count == 1 ? devices.firstObject : nil);
    } @catch (NSException *e) {
        return nil;
    }
}

static NSInteger kindOf(id device) {
    @try { return device ? [[device valueForKey:@"deviceSubType"] integerValue] : -1; } @catch (NSException *e) { return -1; }
}

// The output's name, where iOS names the route only "AirPlay": MediaPlayer's answer while it is this route's, else
// AVFoundation's device (`device`, outputDevice's), which follows a switch at once.
static NSString *outputName(AVAudioSessionPortDescription *port, id device) {
    if (![port.portType isEqualToString:AVAudioSessionPortAirPlay]) return port.portName;
    BOOL generic = [port.portName isEqualToString:@"AirPlay"] || !port.portName.length;
    if (!generic) return port.portName;
    if (sg_pickedName.length && !sg_pickedStale) return sg_pickedName;
    NSString *name = nil;
    @try { name = [device valueForKey:@"name"]; } @catch (NSException *e) {}
    if ([name isKindOfClass:NSString.class] && name.length) return name;
    return sg_pickedName.length ? sg_pickedName : port.portName;
}

// The AirPlay route playing, as MediaPlayer's routing controller has it: its name, which iOS's own route can leave as
// "AirPlay" for good (the phone's log, 2026-10-30), and its model, which AVFoundation leaves out for an app
// (MPAVOutputDeviceRoute's productIdentifier, AudioAccessory1,1 for the owner's HomePod). Fetched once per AirPlay
// route, with discovery on only while the routes are fetched, and the glyph drawn again when it comes.

// Each output's model as MediaPlayer's routes name it (MRAVOutputDevice's modelID: BTHeadphones76,8240 for a pair of
// AirPods, AudioAccessory1,1 for a HomePod, MacBookPro18,3), kept by the output's name across launches. iOS names a
// Bluetooth device's model only while it is not the one playing (the phone's log, 2026-10-30: none for the AirPods Pro
// in use, Caitlin's named), so what was seen before is what draws it.
// Only devices this phone has played to are kept (kOutputsUsedKey), not every one discovery finds nearby, and no more
// than kOutputModelsMax of them.
static NSString *const kOutputModelsKey = @"spotifyglass.redesign.outputModels", *const kOutputsUsedKey = @"spotifyglass.redesign.outputsUsed";
static const NSUInteger kOutputModelsMax = 24;
static NSMutableDictionary<NSString *, NSString *> *sg_outputModels;
static NSMutableOrderedSet<NSString *> *sg_outputsUsed;

static NSMutableOrderedSet<NSString *> *outputsUsed(void) {
    if (!sg_outputsUsed) {
        NSArray *stored = [NSUserDefaults.standardUserDefaults arrayForKey:kOutputsUsedKey];
        sg_outputsUsed = stored ? [NSMutableOrderedSet orderedSetWithArray:stored] : [NSMutableOrderedSet orderedSet];
    }
    return sg_outputsUsed;
}

static NSMutableDictionary<NSString *, NSString *> *outputModels(void);

// An output played to, the most recent last; the oldest beyond the limit is forgotten with its model.
static void markOutputUsed(NSString *name) {
    if (!name.length || [name isEqualToString:@"AirPlay"]) return;
    NSMutableOrderedSet *used = outputsUsed();
    if ([used.lastObject isEqual:name]) return;
    [used removeObject:name];
    [used addObject:name];
    BOOL forgot = NO;
    while (used.count > kOutputModelsMax) {
        forgot = [outputModels() objectForKey:used.firstObject] != nil || forgot;
        [outputModels() removeObjectForKey:used.firstObject];
        [used removeObjectAtIndex:0];
    }
    [NSUserDefaults.standardUserDefaults setObject:used.array forKey:kOutputsUsedKey];
    if (forgot) [NSUserDefaults.standardUserDefaults setObject:outputModels() forKey:kOutputModelsKey];
}

static NSMutableDictionary<NSString *, NSString *> *outputModels(void) {
    if (!sg_outputModels) {
        NSDictionary *stored = [NSUserDefaults.standardUserDefaults dictionaryForKey:kOutputModelsKey];
        sg_outputModels = stored ? [stored mutableCopy] : [NSMutableDictionary dictionary];
    }
    return sg_outputModels;
}

static void rememberModels(NSArray *routes) {
    NSMutableDictionary *models = outputModels();
    BOOL changed = NO;
    for (id route in routes) {
        @try {
            NSString *name = [route valueForKey:@"routeName"];
            id device = [route valueForKey:@"outputDevice"];
            NSString *model = [device respondsToSelector:@selector(modelID)] ? [device valueForKey:@"modelID"] : nil;
            if (![name isKindOfClass:NSString.class] || ![outputsUsed() containsObject:name]) continue;
            if (![model isKindOfClass:NSString.class] || !model.length || [models[name] isEqualToString:model]) continue;
            models[name] = model;
            changed = YES;
        } @catch (NSException *e) {}
    }
    if (changed) [NSUserDefaults.standardUserDefaults setObject:models forKey:kOutputModelsKey];
}

// Apple's Bluetooth product IDs (BTHeadphones76,<id>), drawn as the system's menu draws them; a newer ID than these is a
// newer pair, drawn as the newest of its kind.
static NSString *symbolForHeadphones(NSString *model, NSString *name) {
    NSString *prefix = @"BTHeadphones76,";
    if (![model hasPrefix:prefix]) return nil;
    NSInteger product = [[model substringFromIndex:prefix.length] integerValue];
    // SF Symbols' own names, as iOS 27 has them.
    switch (product) {
        case 0x2002: case 0x200F: return @"airpods";
        case 0x2013: return @"airpods.gen3";
        case 0x2019: case 0x201B: return @"airpods.gen4";
        // The first and second generation look alike and share one artwork; the third has its own (the Music app draws
        // the owner's AirPods Pro 2 as airpods.pro.gen1, iOS 27.2, 2026-10-30).
        case 0x200E: case 0x2014: case 0x2024: return @"airpods.pro.gen1";
        case 0x2027: return @"airpods.pro.gen3";
        case 0x200A: case 0x201F: return @"airpods.max";
        case 0x2003: return @"beats.powerbeats3";
        case 0x200D: return @"beats.powerbeats";
        case 0x200B: return @"beats.powerbeats.pro";
        case 0x2012: return @"beats.fit.pro";
        case 0x2011: return @"beats.studiobuds";
        case 0x2016: return @"beats.studiobuds.plus";
        case 0x2006: case 0x2009: case 0x200C: case 0x2017: return @"beats.headphones";
    }
    NSString *lower = name.lowercaseString;
    if ([lower containsString:@"airpods"] && product > 0x2024) {
        if ([lower containsString:@"max"]) return @"airpods.max";
        if ([lower containsString:@"pro"]) return @"airpods.pro.gen3";
        return @"airpods.gen4";
    }
    return nil;
}

static id sg_routing;
static NSUInteger sg_fetchToken;

// Discovery off again, only by the fetch that turned it on last: an earlier one's answer switched it off under a later
// fetch still running.
static void endDiscovery(NSUInteger token) {
    if (token != sg_fetchToken || !sg_routing) return;
    @try { ((void (*)(id, SEL, NSInteger))objc_msgSend)(sg_routing, @selector(setDiscoveryMode:), 0); } @catch (NSException *e) {}
}

static NSUInteger sg_fetchAttempt;

static void fetchPicked(AVAudioSessionPortDescription *port) {
    if (!port.UID || [sg_pickedFor isEqualToString:port.UID]) return;
    sg_pickedFor = port.UID;
    NSUInteger token = ++sg_fetchToken, attempt = sg_fetchAttempt;
    sg_fetchAttempt = 0;
    NSString *portType = port.portType;
    // The last answer stays until the new one comes, used only while its name fits the route (outputSymbol): cleared at
    // once, every switch drew a speaker for a moment (the phone's log, 2026-10-30).
    Class controllerClass = NSClassFromString(@"MPAVRoutingController");
    SEL fetch = NSSelectorFromString(@"fetchAvailableRoutesWithCompletionHandler:");
    @try {
        // alloc and init by hand, outside ARC: init consumes what alloc made and returns its own +1 (AGENTS.md).
        if (!sg_routing && [controllerClass instancesRespondToSelector:@selector(initWithName:)]) {
            void *raw = ((void *(*)(Class, SEL))objc_msgSend)(controllerClass, @selector(alloc));
            sg_routing = CFBridgingRelease(((void *(*)(void *, SEL, NSString *))objc_msgSend)(raw, @selector(initWithName:), @"vitrine"));
        }
        id controller = sg_routing;
        if (![controller respondsToSelector:fetch] || ![controller respondsToSelector:@selector(setDiscoveryMode:)]) return;
        ((void (*)(id, SEL, NSInteger))objc_msgSend)(controller, @selector(setDiscoveryMode:), 3);
        // Never left on: a fetch that does not answer has discovery ended for it.
        dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(5 * NSEC_PER_SEC)), dispatch_get_main_queue(), ^{ endDiscovery(token); });
        ((void (*)(id, SEL, id))objc_msgSend)(controller, fetch, ^(NSArray *routes) {
            dispatch_async(dispatch_get_main_queue(), ^{
                endDiscovery(token);
                if (token != sg_fetchToken) return;
                @try {
                    id picked = [controller valueForKey:@"pickedRoute"];
                    NSString *name = [picked valueForKey:@"routeName"];
                    // MediaPlayer can still answer with the route before (a pair of AirPods while AirPlay already plays,
                    // the phone's log, 2026-10-30): an AirPlay route takes only an AirPlay answer, asked again a moment later.
                    BOOL wantAirPlay = [portType isEqualToString:AVAudioSessionPortAirPlay];
                    BOOL airPlay = [picked respondsToSelector:@selector(isAirPlayRoute)] && [[picked valueForKey:@"isAirPlayRoute"] boolValue];
                    if (!airPlay) for (id route in routes) {
                        if ([[route valueForKey:@"routeName"] isEqual:name] && [route respondsToSelector:@selector(isAirPlayRoute)])
                            airPlay = [[route valueForKey:@"isAirPlayRoute"] boolValue];
                    }
                    // A placeholder of iOS's while a route is handed over (its owner's screenshot, 2026-10-30), no device's.
                    if ([name isEqual:@"AirPlayHandoffDevice"]) airPlay = NO;
                    if (wantAirPlay && !airPlay) {
                        if (attempt < 3) {
                            sg_pickedFor = nil;
                            dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(0.7 * NSEC_PER_SEC)), dispatch_get_main_queue(), ^{
                                if (token == sg_fetchToken) {
                                    sg_fetchAttempt = attempt + 1;
                                    paintConnectAgain();
                                }
                            });
                        }
                        return;
                    }
                    // The picked route can be another class with no model (the phone's log, 2026-10-30): its model is
                    // on the route of that name in the list.
                    NSString *product = nil;
                    rememberModels(routes);
                    for (id route in routes) {
                        if (![[route valueForKey:@"routeName"] isEqual:name] || ![route respondsToSelector:@selector(productIdentifier)]) continue;
                        product = [route valueForKey:@"productIdentifier"];
                        if ([product isKindOfClass:NSString.class] && product.length) break;
                    }
                    sg_pickedName = [name isKindOfClass:NSString.class] ? name : nil;
                    sg_pickedProduct = [product isKindOfClass:NSString.class] ? product : nil;
                    sg_pickedStale = NO;
                } @catch (NSException *e) {}
                paintConnectAgain();
            });
        });
    } @catch (NSException *e) {}
}

static NSString *symbolForProduct(NSString *product) {
    if ([product hasPrefix:@"AudioAccessory5"]) return @"homepod.mini.fill";
    if ([product hasPrefix:@"AudioAccessory6"]) return @"homepod.2.fill";
    if ([product hasPrefix:@"AudioAccessory"]) return @"homepod.fill";
    if ([product hasPrefix:@"AppleTV"]) return @"appletv.fill";
    if ([product hasPrefix:@"MacBook"]) return @"macbook";
    if ([product hasPrefix:@"iMac"]) return @"desktopcomputer";
    if ([product hasPrefix:@"Macmini"]) return @"macmini.fill";
    if ([product hasPrefix:@"Mac"]) return @"desktopcomputer";
    if ([product hasPrefix:@"iPad"]) return @"ipad";
    if ([product hasPrefix:@"iPhone"]) return @"iphone";
    return nil;
}

// A device's symbol from the system's own catalogue: asked by name the usual way, iOS answers as the SDK Spotify is built
// with (iOS 26), which lacks iOS 27's names and draws airpods.pro as it was; read from CoreGlyphs itself, it has them all
// (the phone, iOS 27.2, 2026-10-30).
static UIImage *deviceSymbol(NSString *name, UIImageConfiguration *config) {
    static NSBundle *glyphs;
    static dispatch_once_t once;
    dispatch_once(&once, ^{ glyphs = [NSBundle bundleWithPath:@"/System/Library/CoreServices/CoreGlyphs.bundle"]; });
    UIImage *image = glyphs ? [UIImage imageNamed:name inBundle:glyphs withConfiguration:config] : nil;
    return image.isSymbolImage ? image : [UIImage systemImageNamed:name withConfiguration:config];
}

// Whether this iOS has the symbol, asked once per name.
static BOOL hasDeviceSymbol(NSString *name) {
    static NSMutableDictionary<NSString *, NSNumber *> *known;
    if (!known) known = [NSMutableDictionary dictionary];
    NSNumber *has = known[name];
    if (!has) known[name] = has = @(deviceSymbol(name, nil) != nil);
    return has.boolValue;
}

static NSString *outputSymbol(void) {
    AVAudioSessionPortDescription *port = AVAudioSession.sharedInstance.currentRoute.outputs.firstObject;
    NSString *type = port.portType, *name = port.portName.lowercaseString ?: @"";
    NSString *symbol = kConnectSymbol;
    if ([type isEqualToString:AVAudioSessionPortHeadphones] || [type isEqualToString:AVAudioSessionPortUSBAudio]
               || [type isEqualToString:AVAudioSessionPortLineOut]) {
        // Wired, through the headphone jack, an adapter, or USB-C earphones: drawn as EarPods (its owner's pick, 2026-10-30).
        symbol = @"earpods";
    } else if ([type isEqualToString:AVAudioSessionPortCarAudio]) {
        symbol = @"car.fill";
    } else if ([type isEqualToString:AVAudioSessionPortHDMI]) {
        symbol = @"tv.fill";
    } else if ([type isEqualToString:AVAudioSessionPortBluetoothA2DP] || [type isEqualToString:AVAudioSessionPortBluetoothLE]
               || [type isEqualToString:AVAudioSessionPortBluetoothHFP]) {
        markOutputUsed(port.portName);
        fetchPicked(port);
        NSString *known = symbolForHeadphones(outputModels()[port.portName], port.portName);
        // By name until the model is known; the first and second AirPods Pro share airpods.pro.gen1, as the Music app
        // draws them, airpods.pro being the third's.
        if (known) symbol = known;
        else if ([name containsString:@"airpods max"]) symbol = @"airpods.max";
        else if ([name containsString:@"airpods pro"]) symbol = @"airpods.pro.gen1";
        else if ([name containsString:@"airpods"]) symbol = @"airpods";
        else if ([name containsString:@"beats"]) symbol = @"beats.headphones";
        else {
            NSInteger kind = kindOf(outputDevice(port));
            if (kind == SGROutputKindCar) symbol = @"car.fill";
            else if (kind == SGROutputKindHeadphones || kind == SGROutputKindHeadset) symbol = @"headphones";
            else symbol = @"hifispeaker.fill";
        }
    } else if ([type isEqualToString:AVAudioSessionPortAirPlay]) {
        id device = outputDevice(port);
        NSString *deviceName = outputName(port, device);
        markOutputUsed(deviceName);
        fetchPicked(port);
        // The model remembered for the output's name draws it at once; MediaPlayer's answer, while it is this route's, after.
        BOOL fits = !sg_pickedStale && ([port.portName isEqualToString:sg_pickedName] || [port.portName isEqualToString:@"AirPlay"]);
        NSString *modelSymbol = symbolForProduct(outputModels()[deviceName]) ?: (fits ? symbolForProduct(sg_pickedProduct) : nil);
        NSInteger kind = modelSymbol ? -1 : kindOf(device);
        if (modelSymbol) symbol = modelSymbol;
        // Not yet known (iOS's list and MediaPlayer's answer can trail a switch): AirPlay's own glyph until they come.
        else if (kind < 0 && sg_pickedStale) symbol = kConnectSymbol;
        else if (kind == SGROutputKindHomePod) symbol = @"homepod.fill";
        else if (kind == SGROutputKindAppleTV) symbol = @"appletv.fill";
        else if (kind == SGROutputKindTV) symbol = @"tv.fill";
        else symbol = @"hifispeaker.fill";
    }
    // A name an older iOS lacks falls back to its older name, then to AirPlay.
    static NSDictionary<NSString *, NSString *> *older;
    if (!older) older = @{@"airpods.pro.gen1": @"airpodspro", @"airpods.pro.gen3": @"airpods.pro", @"airpods.pro": @"airpodspro",
                          @"airpods.max": @"airpodsmax", @"airpods.gen4": @"airpods.gen3", @"airpods.gen3": @"airpods",
                          @"homepod.2.fill": @"homepod.fill", @"homepod.mini.fill": @"homepodmini.fill", @"beats.fit.pro": @"beats.fitpro",
                          @"beats.studiobuds.plus": @"beats.studiobuds", @"macbook": @"laptopcomputer", @"beats.powerbeats.pro": @"beats.powerbeats", @"beats.powerbeats3": @"beats.powerbeats"};
    while (!hasDeviceSymbol(symbol) && older[symbol]) symbol = older[symbol];
    if (!hasDeviceSymbol(symbol)) symbol = kConnectSymbol;
    return symbol;
}

// The line under the row, the Music app's: the device's name, nothing on the phone's own speaker (its owner's
// screenshots, 2026-10-30; the Music app's "iPhone → " before an AirPlay one left out, its owner's pick).

static NSString *routeText(void) {
    AVAudioSessionPortDescription *port = AVAudioSession.sharedInstance.currentRoute.outputs.firstObject;
    NSString *type = port.portType;
    if (!port || [type isEqualToString:AVAudioSessionPortBuiltInSpeaker] || [type isEqualToString:AVAudioSessionPortBuiltInReceiver]) return nil;
    return outputName(port, outputDevice(port));
}


NSString *SGRPlayerOutputSymbol(void) {
    return outputSymbol();
}

UIImage *SGRPlayerOutputImage(NSString *symbol, UIImageConfiguration *config) {
    return symbol ? deviceSymbol(symbol, config) : nil;
}

NSString *SGRPlayerOutputName(void) {
    return routeText();
}

#pragma mark - the press

// A finger's stay on a control presses the first SGRGlyphView inside it and lets go as it lifts, taking nothing from its
// taps or holds: the footer's press feel, for a control that draws its own glyph.
@interface SGRGlyphPressWatch : NSObject <UIGestureRecognizerDelegate>
@end

@implementation SGRGlyphPressWatch
- (void)touched:(UILongPressGestureRecognizer *)press {
    __block SGRGlyphView *glyph = nil;
    SGForEachView(press.view, ^(UIView *view) {
        if (!glyph && [view isKindOfClass:SGRGlyphView.class]) glyph = (SGRGlyphView *)view;
    });
    UIGestureRecognizerState state = press.state;
    if (state == UIGestureRecognizerStateBegan) SGRGlyphPress(glyph, YES);
    else if (state == UIGestureRecognizerStateEnded || state == UIGestureRecognizerStateCancelled || state == UIGestureRecognizerStateFailed) SGRGlyphPress(glyph, NO);
}

- (BOOL)gestureRecognizer:(UIGestureRecognizer *)recognizer shouldRecognizeSimultaneouslyWithGestureRecognizer:(UIGestureRecognizer *)other {
    return YES;
}
@end

static char kGlyphPressKey;

void SGRPlayerPressGlyphOnTouch(UIView *control) {
    if (!control || objc_getAssociatedObject(control, &kGlyphPressKey)) return;
    static SGRGlyphPressWatch *watch;
    if (!watch) watch = [SGRGlyphPressWatch new];
    UILongPressGestureRecognizer *press = [[UILongPressGestureRecognizer alloc] initWithTarget:watch action:@selector(touched:)];
    press.minimumPressDuration = 0;
    press.allowableMovement = 30;
    press.cancelsTouchesInView = NO;
    press.delaysTouchesBegan = NO;
    press.delaysTouchesEnded = NO;
    press.delegate = watch;
    [control addGestureRecognizer:press];
    objc_setAssociatedObject(control, &kGlyphPressKey, press, OBJC_ASSOCIATION_RETAIN_NONATOMIC);
}

%ctor {
    if (!SGRSystemTabsOn()) return;
    // The route changes off the main thread, so it is not observed on the main queue (AGENTS.md).
    [NSNotificationCenter.defaultCenter addObserverForName:AVAudioSessionRouteChangeNotification object:nil queue:nil usingBlock:^(NSNotification *note) {
        dispatch_async(dispatch_get_main_queue(), ^{
            // iOS can keep one ID for every AirPlay route (an AirPlay route named "AirPlay"), so each change is asked anew,
            // and the last answer may be another device's until then.
            sg_pickedFor = nil;
            sg_pickedStale = YES;
            paintConnectAgain();
        });
        // iOS fills in the new output a moment after the route changes, an AirPlay route named "AirPlay" until then.
        for (NSNumber *delay in @[@0.6, @2]) {
            dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(delay.doubleValue * NSEC_PER_SEC)), dispatch_get_main_queue(), ^{
                paintConnectAgain();
            });
        }
    }];
}
