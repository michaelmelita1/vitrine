// The saved composition of the redesign's bar, as NSUserDefaults property lists.
#import "Navbar.h"
#import "Shared/Navigation/Links.h"

NSString *const SGRNavbarID = @"id";
NSString *const SGRNavbarTitle = @"title";
NSString *const SGRNavbarURI = @"uri";
NSString *const SGRNavbarIcon = @"icon";
NSString *const SGRNavbarIconSet = @"iconSet";
NSString *const SGRNavbarHidden = @"hidden";

static NSString *const kNavbarLayout = @"spotifyglass.redesign.navbar.layout";
static NSString *const kNavbarStock = @"spotifyglass.redesign.navbar.stock";
static NSString *const kNavbarSplit = @"spotifyglass.redesign.navbar.apart";
static NSString *const kNavbarSplitWas = @"spotifyglass.redesign.navbar.split";

// Only property list types go in, so a corrupt read cannot be anything but an array of dictionaries.
static NSArray *listOfKind(NSString *key, Class kind) {
    NSArray *list = [NSUserDefaults.standardUserDefaults arrayForKey:key];
    for (id item in list) if (![item isKindOfClass:kind]) return @[];
    return list ?: @[];
}

NSArray<NSDictionary *> *SGRNavbarLayout(void) {
    return listOfKind(kNavbarLayout, NSDictionary.class);
}

void SGRSetNavbarLayout(NSArray<NSDictionary *> *layout) {
    [NSUserDefaults.standardUserDefaults setObject:layout ?: @[] forKey:kNavbarLayout];
}

// Split tabs, a list of tabs set apart at the trailing end of the glass bar, are gone with that bar; the system tab bar
// keeps one row. Their order was the bar's order on the right, after the rest, so each moves to the end of the bar's
// list, once, and the list is let go: the mod's own as they were, Spotify's shown and out of their earlier place. A
// list from before the split tabs had one of their own (.split, the identities of entries of the bar's list) is read
// the same way. Run at launch, so a settings backup from before, which an import writes back before it restarts, is
// folded too.
void SGRFoldNavbarSplit(void) {
    NSUserDefaults *store = NSUserDefaults.standardUserDefaults;
    BOOL hasList = [store objectForKey:kNavbarSplit] != nil, hasOld = [store objectForKey:kNavbarSplitWas] != nil;
    if (!hasList && !hasOld) return;
    NSMutableArray<NSDictionary *> *apart = [NSMutableArray array];
    if (hasList) {
        [apart addObjectsFromArray:listOfKind(kNavbarSplit, NSDictionary.class)];
    } else {
        // The old list named entries of the bar's list, or Spotify's tabs it never named, in no order: the bar's order
        // first, then Spotify's.
        NSMutableOrderedSet<NSString *> *split = [NSMutableOrderedSet orderedSetWithArray:listOfKind(kNavbarSplitWas, NSString.class)];
        for (NSDictionary *entry in SGRNavbarLayout()) {
            NSString *ident = entry[SGRNavbarID];
            if (![ident isKindOfClass:NSString.class] || ![split containsObject:ident]) continue;
            [split removeObject:ident];
            if (![entry[SGRNavbarHidden] boolValue]) [apart addObject:entry];
        }
        NSArray<NSString *> *stock = SGRNavbarStock();
        for (NSString *ident in stock) if ([split containsObject:ident]) [apart addObject:@{SGRNavbarID: ident, SGRNavbarTitle: ident}];
    }
    NSMutableSet<NSString *> *moved = [NSMutableSet set];
    for (NSDictionary *entry in apart) if ([entry[SGRNavbarID] isKindOfClass:NSString.class]) [moved addObject:entry[SGRNavbarID]];
    NSMutableArray<NSDictionary *> *layout = [NSMutableArray array];
    for (NSDictionary *entry in SGRNavbarLayout()) {
        if (![moved containsObject:entry[SGRNavbarID]]) [layout addObject:entry];
    }
    if (apart.count) {
        // Spotify's tabs the bar's list never named stood after the ones it did, in Spotify's order: they are named now,
        // so they keep their place ahead of the moved tabs.
        NSMutableSet<NSString *> *named = [NSMutableSet set];
        for (NSDictionary *entry in layout) if ([entry[SGRNavbarID] isKindOfClass:NSString.class]) [named addObject:entry[SGRNavbarID]];
        for (NSString *ident in SGRNavbarStock()) {
            if (![named containsObject:ident] && ![moved containsObject:ident]) [layout addObject:@{SGRNavbarID: ident, SGRNavbarTitle: ident}];
        }
        for (NSDictionary *entry in apart) {
            NSMutableDictionary *shown = [entry mutableCopy];
            [shown removeObjectForKey:SGRNavbarHidden];
            [layout addObject:shown];
        }
        SGRSetNavbarLayout(layout);
    }
    [store removeObjectForKey:kNavbarSplit];
    [store removeObjectForKey:kNavbarSplitWas];
}

NSArray<NSString *> *SGRNavbarStock(void) {
    return listOfKind(kNavbarStock, NSString.class);
}

void SGRSetNavbarStock(NSArray<NSString *> *stock) {
    [NSUserDefaults.standardUserDefaults setObject:stock ?: @[] forKey:kNavbarStock];
}

NSURL *SGRNavbarTabURL(NSString *uri) {
    NSURL *url = SGSpotifyURIFromText(uri);
    if ([url.absoluteString isEqualToString:@"spotify:collection:playlists"]) return [NSURL URLWithString:@"spotify:playlists"];
    return url;
}
