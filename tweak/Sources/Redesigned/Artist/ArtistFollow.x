// Whether the user follows the page's artist, read from Spotify's collection state (following saves the
// artist to the collection) rather than the Follow button, whose only state is its localized title.
// The provider is the one Spotify's own code uses, kept weakly.
#import <objc/message.h>
#import <os/lock.h>
#import "Core/SGCore.h"
#import "Artist.h"
#import "Shared/HeadGestures/HeadGestures.h"

@protocol SGRCollectionState <NSObject>
+ (id)saved;
- (BOOL)contains:(id)state;
- (NSInteger)rawValue;
@end

@protocol SGRCollectionStateProvider <NSObject>
- (id)subscribeCollectionStateForURL:(NSURL *)url completion:(void (^)(id state, NSError *error))completion;
@end

static __weak id sg_provider;
// Guards sg_provider and keepProvider's `logged`; a lock of this file's own, so Spotify's threads binding rows
// never queue behind another file's.
static os_unfair_lock sg_providerLock = OS_UNFAIR_LOCK_INIT;

// Called from wherever Spotify reaches for its provider, any thread.
static void keepProvider(id provider) {
    if (!provider || ![provider respondsToSelector:@selector(subscribeCollectionStateForURL:completion:)]) return;
    // Nearly every call brings the provider already kept; a weak load is atomic, and the lock below decides.
    if (provider == sg_provider) return;
    static NSMutableSet<NSString *> *logged;
    NSString *name = nil;
    os_unfair_lock_lock(&sg_providerLock);
    if (provider != sg_provider) {
        sg_provider = provider;
        if (!logged) logged = [NSMutableSet set];
        name = NSStringFromClass([provider class]);
        if ([logged containsObject:name]) name = nil;
        else [logged addObject:name];
    }
    os_unfair_lock_unlock(&sg_providerLock);
    if (name) SGLog(@"redesign artist: collection state from %@", name);
}

static __weak id sg_platform;

// The platform that saves to Liked Songs, from whichever of Spotify's four the app last reached for, as
// Shared/HeadGestures/HeadGestures.x keeps it: 9.1.90 may never make SPTCollectionPlatformImplementation, whose init was
// the only place it was kept, and the player page's star did nothing (its owner, 2026-11-06). Asked for from any thread.
static void keepPlatform(id platform) {
    if (![platform respondsToSelector:NSSelectorFromString(@"addURL:showUIConfirmation:completion:")]) return;
    os_unfair_lock_lock(&sg_providerLock);
    sg_platform = platform;
    os_unfair_lock_unlock(&sg_providerLock);
}

static id currentProvider(void) {
    os_unfair_lock_lock(&sg_providerLock);
    id provider = sg_provider;
    os_unfair_lock_unlock(&sg_providerLock);
    id platform = sg_platform ?: SGCollectionPlatformKept();
    if (!provider && [platform respondsToSelector:@selector(stateProvider)]) {
        provider = [platform performSelector:@selector(stateProvider)];
        keepProvider(provider);
    }
    return provider;
}

%hook SPTCollectionPlatformImplementation
- (id)initWithCosmosDataLoader:(id)loader isGatedEntityRelationsEnabled:(BOOL)gated {
    id platform = %orig;
    sg_platform = platform;
    return platform;
}
- (id)stateProvider {
    id provider = %orig;
    keepProvider(provider);
    keepPlatform(self);
    return provider;
}
%end

%hook _TtC23Collection_PlatformImpl22CollectionPlatformImpl
- (id)stateProvider {
    id provider = %orig;
    keepProvider(provider);
    keepPlatform(self);
    return provider;
}
%end

%hook _TtC23Collection_PlatformImpl27CollectionPlatformMigration
- (id)stateProvider {
    id provider = %orig;
    keepProvider(provider);
    keepPlatform(self);
    return provider;
}
%end

%hook _TtC26AlignedCuration_CommonImpl21ACUCollectionPlatform
- (id)stateProvider {
    id provider = %orig;
    keepProvider(provider);
    keepPlatform(self);
    return provider;
}
%end

%hook _TtC23Collection_PlatformImpl35CollectionPlatformStateProviderImpl
- (id)subscribeCollectionStateForURL:(id)url completion:(id)completion {
    keepProvider(self);
    return %orig;
}
- (id)subscribeCollectionStateForURLs:(id)urls completion:(id)completion {
    keepProvider(self);
    return %orig;
}
- (id)subscribeCollectionStateForURL:(id)url inContextURL:(id)context completion:(id)completion {
    keepProvider(self);
    return %orig;
}
- (id)subscribeCollectionStateForURLs:(id)urls inContextURL:(id)context completion:(id)completion {
    keepProvider(self);
    return %orig;
}
%end

%hook _TtC26AlignedCuration_CommonImpl25ACUEsperantoStateProvider
- (id)subscribeCollectionStateForURL:(id)url completion:(id)completion {
    keepProvider(self);
    return %orig;
}
- (id)subscribeCollectionStateForURLs:(id)urls completion:(id)completion {
    keepProvider(self);
    return %orig;
}
- (id)subscribeCollectionStateForURL:(id)url inContextURL:(id)context completion:(id)completion {
    keepProvider(self);
    return %orig;
}
- (id)subscribeCollectionStateForURLs:(id)urls inContextURL:(id)context completion:(id)completion {
    keepProvider(self);
    return %orig;
}
%end

// The Follow element asks Curation's provider, which wraps the collection one.
%hook _TtC21Curation_PlatformImpl30CUPStateProviderImplementation
- (id)subscribeCollectionStateForURL:(id)url inContext:(id)context completion:(id)completion {
    Ivar ivar = class_getInstanceVariable(object_getClass(self), "collectionPlatformStateProvider");
    if (ivar) keepProvider(object_getIvar(self, ivar));
    return %orig;
}
%end

#pragma mark - one subscription per page

// Held by the page, so the subscription ends with it.
@interface SGRFollowWatch : NSObject
@property (nonatomic, copy) NSURL *uri;
@property (nonatomic, strong) id token;
@property (nonatomic) BOOL subscribed;
@property (nonatomic) NSInteger following;   // -1 until the first state arrives
@property (nonatomic, copy) void (^changed)(void);
@end

@implementation SGRFollowWatch
- (void)dealloc {
    if ([_token respondsToSelector:@selector(cancel)]) [_token cancel];
}
@end

static char kWatchKey;

// The artist the page is for. The artist page's controllers carry no URI, but the header's ⋯ does:
// Components.UI.ContextMenuButton-<artist id>.
static NSURL *artistURI(UIView *page, NSString *moreIdentifier) {
    for (UIResponder *responder = page; responder; responder = responder.nextResponder) {
        if (![responder isKindOfClass:UIViewController.class] || ![responder respondsToSelector:@selector(spt_pageURI)]) continue;
        id uri = [(id)responder performSelector:@selector(spt_pageURI)];
        if ([uri isKindOfClass:NSURL.class] && [[uri absoluteString] hasPrefix:@"spotify:artist:"]) return uri;
    }
    NSString *prefix = @"Components.UI.ContextMenuButton-";
    if (![moreIdentifier hasPrefix:prefix]) return nil;
    NSString *identifier = [moreIdentifier substringFromIndex:prefix.length];
    NSCharacterSet *base62 = [NSCharacterSet alphanumericCharacterSet].invertedSet;
    if (identifier.length != 22 || [identifier rangeOfCharacterFromSet:base62].location != NSNotFound) return nil;
    return [NSURL URLWithString:[@"spotify:artist:" stringByAppendingString:identifier]];
}

static void subscribe(SGRFollowWatch *watch, id provider) {
    Class stateClass = NSClassFromString(@"SPTCollectionPlatformState");
    if (![stateClass respondsToSelector:@selector(saved)]) return;
    id saved = [(Class<SGRCollectionState>)stateClass saved];
    __weak SGRFollowWatch *weakWatch = watch;
    NSURL *uri = watch.uri;
    watch.subscribed = YES;
    watch.token = [(id<SGRCollectionStateProvider>)provider subscribeCollectionStateForURL:uri completion:^(id state, NSError *error) {
        if (error || ![state respondsToSelector:@selector(contains:)]) return;
        BOOL following = [(id<SGRCollectionState>)state contains:saved];
        dispatch_async(dispatch_get_main_queue(), ^{
            SGRFollowWatch *current = weakWatch;
            if (!current || current.following == following) return;
            current.following = following;
            if (current.changed) current.changed();
        });
    }];
}

BOOL SGRArtistFollowing(UIView *page, NSString *moreIdentifier, BOOL *following, void (^changed)(void)) {
    if (!page) return NO;
    SGRFollowWatch *watch = objc_getAssociatedObject(page, &kWatchKey);
    if (!watch) {
        NSURL *uri = artistURI(page, moreIdentifier);
        if (!uri) {
            static __weak UIView *loggedPage;
            if (loggedPage != page) {
                loggedPage = page;
                SGLog(@"redesign artist: follow has no artist URI, more is %@", moreIdentifier);
            }
            return NO;
        }
        watch = [SGRFollowWatch new];
        watch.uri = uri;
        watch.following = -1;
        objc_setAssociatedObject(page, &kWatchKey, watch, OBJC_ASSOCIATION_RETAIN_NONATOMIC);
    }
    watch.changed = changed;
    id provider = watch.subscribed ? nil : currentProvider();
    if (provider) subscribe(watch, provider);
    if (watch.following < 0) return NO;
    if (following) *following = watch.following == 1;
    return YES;
}

id SGRCollectionWatchURI(NSURL *uri, void (^changed)(void)) {
    if (!uri) return nil;
    SGRFollowWatch *watch = [SGRFollowWatch new];
    watch.uri = uri;
    watch.following = -1;
    watch.changed = changed;
    id provider = currentProvider();
    if (provider) subscribe(watch, provider);
    return watch;
}

BOOL SGRCollectionWatchSaved(id watch, BOOL *saved) {
    if (![watch isKindOfClass:SGRFollowWatch.class]) return NO;
    SGRFollowWatch *follow = watch;
    id provider = follow.subscribed ? nil : currentProvider();
    if (provider) subscribe(follow, provider);
    if (follow.following < 0) return NO;
    if (saved) *saved = follow.following == 1;
    return YES;
}

BOOL SGRCollectionSetSaved(NSURL *uri, BOOL saved) {
    os_unfair_lock_lock(&sg_providerLock);
    id platform = sg_platform;
    os_unfair_lock_unlock(&sg_providerLock);
    // Head Gestures keeps one from the same classes from launch, whatever look: the one it has, should none have come here.
    if (!platform) platform = SGCollectionPlatformKept();
    SEL selector = saved ? NSSelectorFromString(@"addURL:showUIConfirmation:completion:") : NSSelectorFromString(@"removeURL:showUIConfirmation:completion:");
    if (!uri || ![platform respondsToSelector:selector]) return NO;
    // Spotify's own confirmation ("Added to Liked Songs"), as a tap on its add button gives; a completion that reads no
    // arguments, as HeadGestures.x passes, is safe whatever it is called with.
    void (^done)(void) = ^{};
    ((void (*)(id, SEL, NSURL *, BOOL, id))objc_msgSend)(platform, selector, uri, YES, done);
    return YES;
}

%ctor {
    if (!SGRedesignedUI()) return;
    %init;
    SGRequireClasses(@[@"SPTCollectionPlatformState", @"_TtC23Collection_PlatformImpl35CollectionPlatformStateProviderImpl"]);
}
