#import "Core/SGCore.h"
#import "Settings/SGPage.h"
#import "Settings/SGPageStyle.h"
#import "Navbar.h"
#import "Shared/Navigation/AddTabSheet.h"
#import "Redesigned/Kit/SGRTokens.h"

// What "Add a tab" offers: URIs Spotify's own router resolves to a page of its own, each with the
// name of the SPTEncoreIcon class method that draws its glyph. Playlists was spotify:collection:playlists
// until 0.20, which 9.1.78 knows only from its old iPad sidebar table and has no handler for (#66);
// spotify:playlists is the form its collection URI parser lists, next to spotify:playlists:by-you.
// The picker still asks the dispatcher about each one and leaves out what it has nowhere to send.
static NSArray<NSDictionary *> *tabPresets(void) {
    return @[
        @{SGTabTitle: @"Home", SGTabURI: @"spotify:home", SGTabIcon: @"home"},
        @{SGTabTitle: @"Search", SGTabURI: @"spotify:search", SGTabIcon: @"search"},
        @{SGTabTitle: @"Your Library", SGTabURI: @"spotify:collection", SGTabIcon: @"collection"},
        @{SGTabTitle: @"Liked Songs", SGTabURI: @"spotify:collection:tracks", SGTabIcon: @"heart"},
        @{SGTabTitle: @"Playlists", SGTabURI: @"spotify:playlists", SGTabIcon: @"playlist"},
        @{SGTabTitle: @"Albums", SGTabURI: @"spotify:collection:albums", SGTabIcon: @"album"},
        @{SGTabTitle: @"Artists", SGTabURI: @"spotify:collection:artists", SGTabIcon: @"artist"},
        @{SGTabTitle: @"Podcasts", SGTabURI: @"spotify:collection:podcasts", SGTabIcon: @"podcasts"},
        @{SGTabTitle: @"Audiobooks", SGTabURI: @"spotify:collection:audiobooks", SGTabIcon: @"audiobook"},
        @{SGTabTitle: @"Downloads", SGTabURI: @"spotify:collection:downloads", SGTabIcon: @"downloaded"},
        @{SGTabTitle: @"Your Episodes", SGTabURI: @"spotify:collection:your-episodes", SGTabIcon: @"bookmark"},
        @{SGTabTitle: @"Browse", SGTabURI: @"spotify:browse", SGTabIcon: @"browse"},
        @{SGTabTitle: @"New Releases", SGTabURI: @"spotify:new-releases", SGTabIcon: @"star"},
        @{SGTabTitle: @"Made For You", SGTabURI: @"spotify:made-for-you", SGTabIcon: @"user"},
        @{SGTabTitle: @"Concerts", SGTabURI: @"spotify:concerts", SGTabIcon: @"events"},
        @{SGTabTitle: @"Queue", SGTabURI: @"spotify:now-playing:queue", SGTabIcon: @"queue"},
        @{SGTabTitle: @"Create", SGTabURI: @"spotify:create-menu", SGTabIcon: @"plus"},
    ];
}

// The list the Navbar page edits: the saved order first, then every tab of Spotify's it does not
// name, in Spotify's order. Entries for tabs Spotify no longer has drop out.
static NSMutableArray<NSMutableDictionary *> *navbarEntries(void) {
    NSArray<NSString *> *stock = SGRNavbarStock();
    NSMutableArray<NSMutableDictionary *> *entries = [NSMutableArray array];
    NSMutableSet<NSString *> *seen = [NSMutableSet set];
    for (NSDictionary *entry in SGRNavbarLayout()) {
        NSString *ident = entry[SGRNavbarID];
        if (![ident isKindOfClass:NSString.class] || [seen containsObject:ident]) continue;
        if (!entry[SGRNavbarURI] && ![stock containsObject:ident]) continue;
        [seen addObject:ident];
        [entries addObject:[entry mutableCopy]];
    }
    for (NSString *ident in stock) {
        if ([seen containsObject:ident]) continue;
        [entries addObject:[@{SGRNavbarID: ident, SGRNavbarTitle: ident} mutableCopy]];
    }
    return entries;
}

// A tab of the mod's own carries an identity of its own, so the same page can sit on the bar twice
// and renaming one does not shuffle the order.
static NSMutableDictionary *tabEntry(NSDictionary *tab) {
    NSMutableDictionary *entry = [@{SGRNavbarID: NSUUID.UUID.UUIDString, SGRNavbarTitle: tab[SGTabTitle],
                                    SGRNavbarURI: tab[SGTabURI], SGRNavbarIcon: tab[SGTabIcon]} mutableCopy];
    entry[SGRNavbarIconSet] = tab[SGTabIconSet];
    return entry;
}

static void appendTab(NSDictionary *tab) {
    SGRSetNavbarLayout([navbarEntries() arrayByAddingObject:tabEntry(tab)]);
    SGRRefreshTabBar();
}

// The Add a Tab sheet's tab for an entry of the mod's own, and the entry it gives back, keeping its identity and place.
static NSDictionary *sheetTab(NSDictionary *entry) {
    NSMutableDictionary *tab = [@{SGTabTitle: entry[SGRNavbarTitle] ?: @"", SGTabURI: entry[SGRNavbarURI], SGTabIcon: entry[SGRNavbarIcon] ?: @"star"} mutableCopy];
    tab[SGTabIconSet] = entry[SGRNavbarIconSet];
    return tab;
}

static NSMutableDictionary *editedEntry(NSDictionary *entry, NSDictionary *edited) {
    NSMutableDictionary *now = [entry mutableCopy];
    now[SGRNavbarTitle] = edited[SGTabTitle];
    now[SGRNavbarURI] = edited[SGTabURI];
    now[SGRNavbarIcon] = edited[SGTabIcon];
    now[SGRNavbarIconSet] = edited[SGTabIconSet];
    return now;
}

#pragma mark - glyphs

static UIImage *glyphFor(NSDictionary *entry, BOOL active) {
    return SGRNavbarGlyph(entry, active) ?: [UIImage systemImageNamed:@"square.dashed"];
}

#pragma mark - the page

typedef NS_ENUM(NSInteger, SGRNavbarSection) {
    SGRNavbarSectionLabels,
    SGRNavbarSectionTabs,
    SGRNavbarSectionLinks,   // Add a tab, Use Spotify's tabs
    SGRNavbarSectionCount,
};

// A tab of the list: a check circle that shows or hides it, its glyph, its name, and the table's drag handle.
@interface SGRTabCell : UITableViewCell
@property (nonatomic, strong) UIButton *check;
@end

@implementation SGRTabCell
- (void)layoutSubviews {
    [super layoutSubviews];
    CGFloat height = self.contentView.bounds.size.height;
    self.check.frame = CGRectMake(4, (height - 44) / 2, 44, 44);
}
@end

// The tab editor: Icons only, the tabs in the order the bar shows them
// (the circle shows or hides one, the handle drags it, a tap on one of the mod's own opens it in the Add a
// Tab sheet to edit or remove), then adding one and going back to Spotify's tabs.
// Spotify's own tabs are named by their label and drawn by Spotify, so they can be hidden but not renamed,
// given another icon or removed. Mod Settings and the welcome tour show the same editor.
@interface SGRNavbarPage : SGPage
@end

@implementation SGRNavbarPage {
    NSMutableArray<NSMutableDictionary *> *_entries;
}

- (instancetype)init {
    if (!(self = [super initWithStyle:UITableViewStyleInsetGrouped])) return nil;
    self.title = @"Tab bar";
    return self;
}

- (void)viewDidLoad {
    [super viewDidLoad];
    self.tableView.allowsSelectionDuringEditing = YES;
    self.tableView.editing = YES;
    _entries = navbarEntries();
}

- (void)viewWillAppear:(BOOL)animated {
    [super viewWillAppear:animated];
    [self reload];
}

- (void)viewDidLayoutSubviews {
    [super viewDidLayoutSubviews];
    SGInsetForBars(self.tableView);
}

- (void)reload {
    _entries = navbarEntries();
    [self.tableView reloadData];
}

- (void)save {
    SGRSetNavbarLayout(_entries);
    SGRRefreshTabBar();
}

- (NSInteger)numberOfSectionsInTableView:(UITableView *)table {
    return SGRNavbarSectionCount;
}

- (NSInteger)tableView:(UITableView *)table numberOfRowsInSection:(NSInteger)section {
    if (section == SGRNavbarSectionTabs) return (NSInteger)_entries.count;
    return section == SGRNavbarSectionLinks ? 2 : 1;
}

- (NSString *)headerFor:(NSInteger)section {
    return section == SGRNavbarSectionTabs ? @"Tabs" : nil;
}

- (NSString *)footerFor:(NSInteger)section {
    if (section == SGRNavbarSectionTabs)
        return @"Drag a tab to move it. Tap one you added to rename it or change its icon, or one of Spotify's to hide it.";
    return nil;
}

- (UIView *)tableView:(UITableView *)table viewForHeaderInSection:(NSInteger)section {
    NSString *title = [self headerFor:section];
    return title ? SGSectionHeader(table, title) : nil;
}

- (CGFloat)tableView:(UITableView *)table heightForHeaderInSection:(NSInteger)section {
    return [self headerFor:section] ? SGSectionHeaderHeight() : SGSectionGap;
}

- (UIView *)tableView:(UITableView *)table viewForFooterInSection:(NSInteger)section {
    NSString *text = [self footerFor:section];
    return text ? SGSectionFooter(table, text) : nil;
}

- (CGFloat)tableView:(UITableView *)table heightForFooterInSection:(NSInteger)section {
    NSString *text = [self footerFor:section];
    return text ? SGSectionFooterHeight(table, text) : CGFLOAT_MIN;
}

- (UITableViewCell *)tabCell:(UITableView *)table at:(NSIndexPath *)path {
    SGRTabCell *cell = [table dequeueReusableCellWithIdentifier:@"tab"] ?: [[SGRTabCell alloc] initWithStyle:UITableViewCellStyleDefault reuseIdentifier:@"tab"];
    NSDictionary *entry = _entries[(NSUInteger)path.row];
    BOOL hidden = [entry[SGRNavbarHidden] boolValue];
    SGFillCell(cell, entry[SGRNavbarTitle], nil, hidden ? SGGrey() : nil, nil);
    UIListContentConfiguration *content = (UIListContentConfiguration *)cell.contentConfiguration;
    content.image = glyphFor(entry, NO);
    content.imageProperties.tintColor = hidden ? SGGrey() : UIColor.whiteColor;
    content.imageProperties.maximumSize = CGSizeMake(24, 24);
    content.imageProperties.reservedLayoutSize = CGSizeMake(28, 28);
    content.imageToTextPadding = 12;
    NSDirectionalEdgeInsets margins = content.directionalLayoutMargins;
    margins.leading = 52;
    content.directionalLayoutMargins = margins;
    cell.contentConfiguration = content;
    cell.separatorInset = UIEdgeInsetsMake(0, 52, 0, 0);
    cell.selectionStyle = UITableViewCellSelectionStyleDefault;
    cell.accessibilityValue = hidden ? @"Hidden" : @"Shown";
    cell.accessibilityHint = entry[SGRNavbarURI] ? @"Opens the tab to edit it" : @"Shows or hides the tab";

    if (!cell.check) {
        cell.check = [UIButton buttonWithType:UIButtonTypeSystem];
        [cell.check addTarget:self action:@selector(checkTapped:) forControlEvents:UIControlEventTouchUpInside];
        [cell.contentView addSubview:cell.check];
    }
    UIImageSymbolConfiguration *size = [UIImageSymbolConfiguration configurationWithPointSize:22 weight:UIImageSymbolWeightRegular];
    [cell.check setImage:[UIImage systemImageNamed:hidden ? @"circle" : @"checkmark.circle.fill" withConfiguration:size] forState:UIControlStateNormal];
    cell.check.tintColor = hidden ? SGGrey() : SGRTabAccent();
    cell.check.accessibilityLabel = [NSString stringWithFormat:@"Show %@ on the bar", entry[SGRNavbarTitle]];
    cell.check.accessibilityValue = hidden ? @"Off" : @"On";
    return cell;
}

- (UITableViewCell *)tableView:(UITableView *)table cellForRowAtIndexPath:(NSIndexPath *)path {
    if (path.section == SGRNavbarSectionLabels) {
        UITableViewCell *cell = SGDequeueCell(table, @"labels");
        SGFillCell(cell, @"Icons only", @"No names under the tabs", nil, nil);
        UISwitch *toggle = [UISwitch new];
        toggle.onTintColor = SGGreen();
        toggle.on = SGHidden(SGRKeyNavbarHideLabels);
        [toggle addTarget:self action:@selector(labelsToggled:) forControlEvents:UIControlEventValueChanged];
        cell.accessoryView = toggle;
        cell.selectionStyle = UITableViewCellSelectionStyleNone;
        return cell;
    }
    if (path.section == SGRNavbarSectionTabs) return [self tabCell:table at:path];
    UITableViewCell *cell = SGDequeueCell(table, @"navbar");
    switch (path.section) {
        default:
            // Links in the accent color, as the system's own actions in a list are.
            SGFillCell(cell, path.row == 0 ? @"Add a tab" : @"Use Spotify's tabs", nil, SGRAccent(), nil);
            cell.selectionStyle = UITableViewCellSelectionStyleDefault;
            cell.accessibilityTraits = UIAccessibilityTraitButton;
            break;
    }
    return cell;
}

- (BOOL)tableView:(UITableView *)table canMoveRowAtIndexPath:(NSIndexPath *)path {
    return path.section == SGRNavbarSectionTabs;
}

- (BOOL)tableView:(UITableView *)table canEditRowAtIndexPath:(NSIndexPath *)path {
    return path.section == SGRNavbarSectionTabs;
}

// The circle stands where the delete control would; a tab of the mod's own is removed from its sheet.
- (UITableViewCellEditingStyle)tableView:(UITableView *)table editingStyleForRowAtIndexPath:(NSIndexPath *)path {
    return UITableViewCellEditingStyleNone;
}

- (BOOL)tableView:(UITableView *)table shouldIndentWhileEditingRowAtIndexPath:(NSIndexPath *)path {
    return NO;
}

- (NSIndexPath *)tableView:(UITableView *)table targetIndexPathForMoveFromRowAtIndexPath:(NSIndexPath *)from toProposedIndexPath:(NSIndexPath *)to {
    if (to.section == SGRNavbarSectionTabs) return to;
    // Dragged past either end of the list, the tab stops at that end.
    return [NSIndexPath indexPathForRow:to.section < SGRNavbarSectionTabs ? 0 : (NSInteger)_entries.count - 1 inSection:SGRNavbarSectionTabs];
}

- (void)tableView:(UITableView *)table moveRowAtIndexPath:(NSIndexPath *)from toIndexPath:(NSIndexPath *)to {
    NSMutableDictionary *entry = _entries[(NSUInteger)from.row];
    [_entries removeObjectAtIndex:(NSUInteger)from.row];
    [_entries insertObject:entry atIndex:(NSUInteger)to.row];
    [self save];
}

- (void)toggleRow:(NSInteger)row {
    NSMutableDictionary *entry = _entries[(NSUInteger)row];
    entry[SGRNavbarHidden] = [entry[SGRNavbarHidden] boolValue] ? nil : @YES;
    [self save];
    [self.tableView reloadRowsAtIndexPaths:@[[NSIndexPath indexPathForRow:row inSection:SGRNavbarSectionTabs]] withRowAnimation:UITableViewRowAnimationNone];
}

- (void)checkTapped:(UIButton *)check {
    UIView *view = check;
    while (view && ![view isKindOfClass:UITableViewCell.class]) view = view.superview;
    NSIndexPath *path = view ? [self.tableView indexPathForCell:(UITableViewCell *)view] : nil;
    if (path.section == SGRNavbarSectionTabs) [self toggleRow:path.row];
}

- (void)tableView:(UITableView *)table didSelectRowAtIndexPath:(NSIndexPath *)path {
    [table deselectRowAtIndexPath:path animated:YES];
    __weak typeof(self) weakSelf = self;
    switch (path.section) {
        case SGRNavbarSectionTabs:
            if (_entries[(NSUInteger)path.row][SGRNavbarURI]) [self editRow:path.row];
            else [self toggleRow:path.row];
            break;
        case SGRNavbarSectionLinks: {
            if (path.row == 1) {
                [self reset];
                break;
            }
            SGPresentAddTabSheet(self, tabPresets(), ^(NSDictionary *tab) {
                appendTab(tab);
                [weakSelf reload];
            });
            break;
        }
    }
}

// The entry of the list as it is now with this identity; the list is read again whenever the page appears.
- (NSMutableDictionary *)entryWithID:(NSString *)ident {
    for (NSMutableDictionary *entry in _entries) if ([entry[SGRNavbarID] isEqualToString:ident]) return entry;
    return nil;
}

// The Add a Tab sheet over the tab as it is; Save keeps its place on the bar and its identity.
- (void)editRow:(NSInteger)row {
    NSDictionary *entry = _entries[(NSUInteger)row];
    NSString *ident = entry[SGRNavbarID];
    __weak typeof(self) weakSelf = self;
    SGPresentEditTabSheet(self, tabPresets(), sheetTab(entry), ^(NSDictionary *edited) {
        NSMutableDictionary *now = [weakSelf entryWithID:ident];
        if (!now) return;
        [now setDictionary:editedEntry(now, edited)];
        [weakSelf save];
        [weakSelf.tableView reloadData];
    }, ^{
        typeof(self) page = weakSelf;
        NSMutableDictionary *now = [page entryWithID:ident];
        if (!now) return;
        [page->_entries removeObjectIdenticalTo:now];
        [page save];
        [page.tableView reloadData];
    });
}

- (void)labelsToggled:(UISwitch *)toggle {
    SGSetEnabled(SGRKeyNavbarHideLabels, toggle.on);
    SGRRefreshTabBar();
}

- (void)reset {
    UIAlertController *alert = [UIAlertController alertControllerWithTitle:@"Use Spotify's tabs"
                                                                  message:@"Every tab of Spotify's comes back where Spotify put it, and the tabs you added go."
                                                           preferredStyle:UIAlertControllerStyleAlert];
    [alert addAction:[UIAlertAction actionWithTitle:@"Cancel" style:UIAlertActionStyleCancel handler:nil]];
    [alert addAction:[UIAlertAction actionWithTitle:@"Reset" style:UIAlertActionStyleDestructive handler:^(UIAlertAction *action) {
        SGRSetNavbarLayout(@[]);
        SGRRefreshTabBar();
        [self reload];
    }]];
    [self presentViewController:alert animated:YES completion:nil];
}

@end

UIViewController *SGRNavbarSettingsPage(void) {
    return [SGRNavbarPage new];
}
