// The redesign's ⋯ as the system menu (ContextMenu.h says what and why).
//
// The sheet is ContextMenu_InternalImpl.ContextMenuViewController, presented on its own or as the root of
// ContextMenuNativeNavigationController; its rows are a table sized to its content (Shared/Player/
// harness/menu says more), each a ContextMenuTableViewCell whose only ivar is the
// containedView Spotify draws the row in (nm on 9.1.78). So a row is read off the cell it fills -- its words
// from its labels, its glyph from its image view or else drawn off the small view at its leading edge -- and
// picked through the table's own delegate, as a tap on it would be.
//
// What UIKit does was checked in the simulator against harness/system-menu/ (iOS 27): a presentation's
// container exists from the presented controller's viewWillAppear: on, not when presentViewController: returns,
// so that is where the sheet is hidden; a menu asked for while the sheet's presentation is still under way
// comes up only some of the time (most of the time on a first showing, not on a second right after a first),
// and the presentation takes 0.2 s and more to end even unanimated, so the menu is asked for a turn after
// viewWillAppear: and, when that does not come, again from the presentation's completion, the sheet going up
// unanimated for that to be soon; -performPrimaryAction brings the menu up over the hidden sheet and calls
// willDisplayMenuForConfiguration: before it returns; a pick runs the action's handler before
// willEndForConfiguration:, so by the end of the menu's dismissal it is known whether there was one.
#import <objc/message.h>
#import <objc/runtime.h>
#import "Core/SGCore.h"
#import "Redesigned/Kit/SGRKit.h"
#import "Shared/Player/SpeedPitch.h"
#import "Shared/AlbumQueue/AlbumQueue.h"
#import "Shared/LyricsTranslation/BatchTranslation.h"
#import "ContextMenu.h"

// After a pick of Spotify's, how long its sheet has to start going, or to push a page of its own (which shows
// it at once), before it is taken to have stayed up for some other reason and is shown.
static const NSTimeInterval kSettle = 1;
// How often the sheet is asked for its rows until it has them.
static const NSTimeInterval kRowsPoll = 0.1;

static NSString *const kSheetClass = @"_TtC24ContextMenu_InternalImpl25ContextMenuViewController";

static char kAnchorKey, kSessionKey;

@class SGRMenuSession;
// The session whose pick is being fired on its hidden sheet, for a page the row pushes inside the sheet.
static __weak SGRMenuSession *sg_firing;

#pragma mark - the sheet

// Spotify's ContextMenuViewController in what was presented: itself, the root of its navigation controller, or
// a child of a controller wrapped around either.
// Matched by class, not by name: NSStringFromClass gives a Swift class's readable name ("Module.Class") on
// iOS 27, never the mangled one kSheetClass holds.
static UIViewController *sheetIn(UIViewController *presented) {
    static Class sheetClass;
    if (!sheetClass) sheetClass = NSClassFromString(kSheetClass);
    if (!presented || !sheetClass) return nil;
    if ([presented isKindOfClass:sheetClass]) return presented;
    if ([presented isKindOfClass:UINavigationController.class]) {
        UIViewController *root = ((UINavigationController *)presented).viewControllers.firstObject;
        if ([root isKindOfClass:sheetClass]) return root;
    }
    for (UIViewController *child in presented.childViewControllers) {
        UIViewController *sheet = sheetIn(child);
        if (sheet) return sheet;
    }
    return nil;
}

static UITableView *tableIn(UIView *root, int depth) {
    if ([root isKindOfClass:UITableView.class]) return (UITableView *)root;
    if (!root || depth > 5) return nil;
    for (UIView *child in root.subviews) {
        UITableView *table = tableIn(child, depth + 1);
        if (table) return table;
    }
    return nil;
}

static NSInteger rowCount(UITableView *table) {
    NSInteger rows = 0;
    for (NSInteger section = 0; section < table.numberOfSections; section++) rows += [table numberOfRowsInSection:section];
    return rows;
}

static BOOL shows(UIView *view) {
    return !view.hidden && view.alpha > 0.01;
}

// The visible labels' words in reading order: the row's title first, a line under it second.
static NSArray<UILabel *> *labelsIn(UIView *root) {
    NSMutableArray<UILabel *> *labels = [NSMutableArray array];
    SGForEachView(root, ^(UIView *view) {
        if ([view isKindOfClass:UILabel.class] && shows(view) && ((UILabel *)view).text.length) [labels addObject:(UILabel *)view];
    });
    [labels sortUsingComparator:^NSComparisonResult(UILabel *a, UILabel *b) {
        CGRect ra = [a convertRect:a.bounds toView:root], rb = [b convertRect:b.bounds toView:root];
        if (fabs(CGRectGetMinY(ra) - CGRectGetMinY(rb)) > 4) return CGRectGetMinY(ra) < CGRectGetMinY(rb) ? NSOrderedAscending : NSOrderedDescending;
        return CGRectGetMinX(ra) < CGRectGetMinX(rb) ? NSOrderedAscending : NSOrderedDescending;
    }];
    return labels;
}

// The first accessibility identifier in the row, for the log.
static NSString *identifierIn(UIView *root) {
    __block NSString *found = nil;
    SGForEachView(root, ^(UIView *view) {
        if (!found && view.accessibilityIdentifier.length) found = view.accessibilityIdentifier;
    });
    return found;
}

// The row's glyph as a template, for the menu to draw in its own color: an image view's picture, else the
// small view at the row's leading edge drawn into one (Encore draws its icons into a view of its own,
// Redesigned/Playlist/PlaylistMenu.x).
static UIImage *glyphIn(UIView *root, NSString *title) {
    __block UIImageView *image = nil;
    __block UIView *drawn = nil;
    __block CGFloat drawnX = CGFLOAT_MAX;
    SGForEachView(root, ^(UIView *view) {
        if (view == root || !shows(view)) return;
        CGSize size = view.bounds.size;
        if (size.width < 12 || size.width > 40 || size.height < 12 || size.height > 40) return;
        if (!image && [view isKindOfClass:UIImageView.class] && ((UIImageView *)view).image) image = (UIImageView *)view;
        CGFloat x = [view convertRect:view.bounds toView:root].origin.x;
        if (![view isKindOfClass:UILabel.class] && !view.subviews.count && x < drawnX) {
            drawn = view;
            drawnX = x;
        }
    });
    // A cover (Encore's media image view, as Liked Songs' own) would draw as a solid square: a symbol in the
    // menu's color stands in for it.
    if (image && [image.superview.accessibilityIdentifier isEqualToString:@"Encore.ImageView"]) {
        NSString *name = @"music.note.list";
        if ([title containsString:@"Liked Songs"]) name = [title hasPrefix:@"Remove"] ? @"heart.fill" : @"heart";
        UIImageSymbolConfiguration *size = [UIImageSymbolConfiguration configurationWithPointSize:17 weight:UIImageSymbolWeightRegular];
        return [UIImage systemImageNamed:name withConfiguration:size];
    }
    if (image) return [image.image imageWithRenderingMode:UIImageRenderingModeAlwaysTemplate];
    if (!drawn || drawnX > root.bounds.size.width / 3) return nil;
    UIImage *picture = [[[UIGraphicsImageRenderer alloc] initWithSize:drawn.bounds.size] imageWithActions:^(UIGraphicsImageRendererContext *context) {
        [drawn.layer renderInContext:context.CGContext];
    }];
    return [picture imageWithRenderingMode:UIImageRenderingModeAlwaysTemplate];
}

// Spotify grays a row out (lyrics for a track no source has them for) rather than leaving it out.
static BOOL rowEnabled(UITableView *table, NSIndexPath *path, UITableViewCell *cell, UILabel *title) {
    if (!cell.userInteractionEnabled) return NO;
    id<UITableViewDelegate> delegate = table.delegate;
    if ([delegate respondsToSelector:@selector(tableView:shouldHighlightRowAtIndexPath:)] && ![delegate tableView:table shouldHighlightRowAtIndexPath:path]) return NO;
    CGFloat alpha = 1;
    [title.textColor getRed:NULL green:NULL blue:NULL alpha:&alpha];
    return title.enabled && title.alpha * alpha >= 0.6;
}

// Fires a control as a tap on it would: its primary action's handlers if it has any, else its touch up inside
// ones (the mod's own watchers left out of the count), else its accessibility activation. What it did, for the log.
static NSString *fireControl(UIControl *control) {
    if (!control) return @"nothing to fire";
    __block UIControlEvents events = 0;
    if ([control respondsToSelector:@selector(enumerateEventHandlers:)]) {
        [control enumerateEventHandlers:^(UIAction *action, id target, SEL selector, UIControlEvents handled, BOOL *stop) {
            // The mod's own watcher of the ⋯ is not Spotify's action.
            if (!action && [NSStringFromClass([target class]) hasSuffix:@"TapWatcher"]) return;
            events |= handled;
        }];
    }
    if (events & UIControlEventPrimaryActionTriggered) {
        [control sendActionsForControlEvents:UIControlEventPrimaryActionTriggered];
        return [NSString stringWithFormat:@"%@'s primary action", NSStringFromClass(control.class)];
    }
    if (events & UIControlEventTouchUpInside) {
        [control sendActionsForControlEvents:UIControlEventTouchUpInside];
        return [NSString stringWithFormat:@"%@'s touch up inside", NSStringFromClass(control.class)];
    }
    BOOL done = [control accessibilityActivate];
    return [NSString stringWithFormat:@"%@'s accessibility activation (%@, events 0x%lx)", NSStringFromClass(control.class), done ? @"taken" : @"refused", (unsigned long)events];
}

// Picks the row as a tap would; a row that answers to no delegate is tapped through the first control in it.
// Only the cells on screen exist, so a row further down is scrolled to first (the table is hidden).
static void selectRow(UITableView *table, NSIndexPath *path) {
    id<UITableViewDelegate> delegate = table.delegate;
    if ([delegate respondsToSelector:@selector(tableView:willSelectRowAtIndexPath:)]) path = [delegate tableView:table willSelectRowAtIndexPath:path];
    if (!path) return;
    if ([delegate respondsToSelector:@selector(tableView:didSelectRowAtIndexPath:)]) {
        [table selectRowAtIndexPath:path animated:NO scrollPosition:UITableViewScrollPositionNone];
        [delegate tableView:table didSelectRowAtIndexPath:path];
        return;
    }
    UITableViewCell *cell = [table cellForRowAtIndexPath:path];
    if (!cell && path.section < table.numberOfSections && path.row < [table numberOfRowsInSection:path.section]) {
        [table scrollToRowAtIndexPath:path atScrollPosition:UITableViewScrollPositionMiddle animated:NO];
        [table layoutIfNeeded];
        cell = [table cellForRowAtIndexPath:path];
    }
    __block UIControl *control = nil;
    SGForEachView(cell, ^(UIView *view) {
        if (!control && [view isKindOfClass:UIControl.class] && view.userInteractionEnabled) control = (UIControl *)view;
    });
    SGLog(@"system menu: the sheet's table has no didSelect, so %@ (row %ld%@)", fireControl(control), (long)path.row, cell ? @"" : @", no cell");
}

// The mod's own rows in the table's header or footer view: the view itself or its children, controls of the
// mod's (SG…) with a label. Spotify's own header (the track it is for) is not one.
static NSArray<UIControl *> *modRowsIn(UIView *slot) {
    if (!slot || slot.bounds.size.height < 1) return @[];
    NSMutableArray<UIControl *> *rows = [NSMutableArray array];
    for (UIView *view in [slot isKindOfClass:UIControl.class] ? @[slot] : slot.subviews) {
        if ([view isKindOfClass:UIControl.class] && shows(view) && view.accessibilityLabel.length
            && [NSStringFromClass(view.class) hasPrefix:@"SG"]) [rows addObject:(UIControl *)view];
    }
    return rows;
}

static NSString *controllersIn(UIViewController *presented);

static UIMenu *inlineGroup(NSArray<UIMenuElement *> *children) {
    return [UIMenu menuWithTitle:@"" image:nil identifier:nil options:UIMenuOptionsDisplayInline children:children];
}

#pragma mark - one menu

// One row of the sheet as read: a row of Spotify's table (`path`) or a control of the mod's (`control`).
@interface SGRSheetRow : NSObject
@property (nonatomic, strong) NSIndexPath *path;
@property (nonatomic, weak) UIControl *control;
@property (nonatomic, copy) NSString *title, *subtitle, *identifier;
@property (nonatomic, strong) UIImage *image;
@property (nonatomic) BOOL enabled;
@end
@implementation SGRSheetRow
@end

@class SGRMenuAnchor;

// One ⋯ tap: the sheet Spotify presented, the anchor the menu comes from, and what was picked. Spotify's sheet
// comes first, from the ⋯'s tap, and the menu is opened over it, hidden (takeOver, open).
@interface SGRMenuSession : NSObject
@property (nonatomic, weak) UIViewController *presented;
@property (nonatomic, weak) SGRMenuAnchor *anchor;
@property (nonatomic) BOOL displayed, revealed, ended, opened;
@property (nonatomic, copy) void (^pick)(void);
// When the sheet was taken over (the ⋯'s touch is the Kit's), for the log of where the time to the menu goes.
@property (nonatomic) CFTimeInterval takenAt;
- (void)open;
- (void)tryEarly;
- (void)present;
- (void)shown;
- (void)reveal;
- (void)hide;
- (void)menuEnded;
- (UIView *)container;
- (void)rowPresented;
- (UIMenu *)menu;
@end

// An invisible button over the ⋯ that only hosts the menu. It takes touches only while the menu is up
// (UIKit will not present a menu from a view that takes none), so a tap on the ⋯ reaches the ⋯.
@interface SGRMenuAnchor : UIButton
@property (nonatomic, strong) SGRMenuSession *session;
@end

@implementation SGRMenuAnchor

- (void)contextMenuInteraction:(UIContextMenuInteraction *)interaction willDisplayMenuForConfiguration:(UIContextMenuConfiguration *)configuration
                      animator:(id<UIContextMenuInteractionAnimating>)animator {
    [super contextMenuInteraction:interaction willDisplayMenuForConfiguration:configuration animator:animator];
    [self.session shown];
}

- (void)contextMenuInteraction:(UIContextMenuInteraction *)interaction willEndForConfiguration:(UIContextMenuConfiguration *)configuration
                      animator:(id<UIContextMenuInteractionAnimating>)animator {
    [super contextMenuInteraction:interaction willEndForConfiguration:configuration animator:animator];
    SGRMenuSession *session = self.session;
    self.session = nil;
    self.userInteractionEnabled = NO;
    // At once, not at the end of the menu's dismissal: on the phone that end never came (the animator's
    // completion never ran), so every pick and close waited out a 3 s limit with the hidden sheet over the
    // player. The pick fires a turn later, which the sheet takes while the menu is still fading.
    [session menuEnded];
}

@end

@implementation SGRMenuSession {
    // The sheet's rows in its groups (the mod's header rows, each section, the mod's footer rows), nil until
    // the sheet has them; read once.
    NSArray<NSArray<SGRSheetRow *> *> *_groups;
    __weak UITableView *_table;
    // Run once the rows are read: the menu's deferred rows.
    NSMutableArray<dispatch_block_t> *_whenRead;
    NSTimer *_poll;
    CFTimeInterval _openedAt, _askedAt;
    // The menu is asked for while the sheet's presentation is still under way, which UIKit takes only some of
    // the time; if it does not come, it is asked for again once the sheet is up.
    BOOL _early, _wasEarly;
    // A row picked on the sheet presented something of Spotify's.
    BOOL _rowPresented;
}

- (UIViewController *)sheet {
    return sheetIn(self.presented);
}

// The presentation's container, which the sheet is hidden in. Asked of the controller UIKit presented: a
// controller inside it (the sheet, taken over as it appeared inside one of Spotify's) would answer with a
// presentation controller of its own, made then, holding nothing.
- (UIView *)container {
    UIViewController *outer = self.presented;
    while (outer.parentViewController) outer = outer.parentViewController;
    return outer.presentationController.containerView;
}

- (void)open {
    if (self.opened) return;
    self.opened = YES;
    SGRMenuAnchor *anchor = self.anchor;
    if (!anchor.window || !self.presented.presentingViewController) {
        SGLog(@"system menu: the ⋯ left the screen before its menu could open, Spotify's sheet shown");
        [self reveal];
        return;
    }
    _openedAt = CACurrentMediaTime();
    // A turn later, so the menu never comes up in the same turn as the touch that opened Spotify's sheet.
    dispatch_async(dispatch_get_main_queue(), ^{ [self present]; });
}

// The first try, a turn after the sheet starts to appear, before its presentation is over: the wait for that is
// the most the mod adds between the touch and the menu (0.2 s and more in the simulator, even unanimated). UIKit
// brings a menu up then only some of the time, so a try that does not come is let go and open asks again once
// the sheet is up.
- (void)tryEarly {
    if (self.opened || self.displayed || self.ended || self.revealed) return;
    _early = _wasEarly = YES;
    [self present];
}

// The menu up from the anchor, at once, with what needs nothing of the sheet; Spotify's rows are read after it is
// asked for, so the time they take is not the menu's.
- (void)present {
    if (self.displayed || self.ended || self.revealed) return;
    if (!_whenRead) _whenRead = [NSMutableArray array];
    SGRMenuAnchor *anchor = self.anchor;
    if (!anchor.window || !self.presented.presentingViewController) {
        SGLog(@"system menu: the ⋯ left the screen before its menu could open, Spotify's sheet shown");
        [self reveal];
        return;
    }
    if (!_askedAt) _askedAt = CACurrentMediaTime();
    anchor.session = self;
    anchor.menu = [self menu];
    anchor.userInteractionEnabled = YES;
    SEL perform = NSSelectorFromString(@"performPrimaryAction");
    if ([anchor respondsToSelector:perform]) ((void (*)(id, SEL))objc_msgSend)(anchor, perform);
    if (!self.displayed) {
        UIContextMenuInteraction *interaction = anchor.contextMenuInteraction;
        for (id<UIInteraction> each in anchor.interactions) {
            if (!interaction && [(id)each isKindOfClass:UIContextMenuInteraction.class]) interaction = (UIContextMenuInteraction *)each;
        }
        SEL present = NSSelectorFromString(@"_presentMenuAtLocation:");
        if ([interaction respondsToSelector:present]) {
            CGPoint middle = CGPointMake(CGRectGetMidX(anchor.bounds), CGRectGetMidY(anchor.bounds));
            ((void (*)(id, SEL, CGPoint))objc_msgSend)(interaction, present, middle);
        }
    }
    // Both ways answer before they return; one more turn is given for an OS that answers a moment later.
    dispatch_async(dispatch_get_main_queue(), ^{
        if (!self.displayed && !self.ended && self->_early) {
            self->_early = NO;
            anchor.userInteractionEnabled = NO;
            anchor.session = nil;
            static int logged;
            if (logged++ < 3) SGLog(@"system menu: the menu asked for while Spotify's sheet came up did not come, asked again once it is up");
            return;
        }
        self->_early = NO;
        if (!self.displayed && !self.ended) {
            SGLog(@"system menu: the menu did not come up, Spotify's sheet shown");
            anchor.userInteractionEnabled = NO;
            anchor.session = nil;
            [self reveal];
            return;
        }
        if (![self readRows]) [self pollRows];
    });
}

// Where the time from the takeover to the menu on screen went, in seconds after the takeover.
- (void)shown {
    if (self.displayed) return;
    self.displayed = YES;
    if (!_whenRead) _whenRead = [NSMutableArray array];
    CFTimeInterval now = CACurrentMediaTime(), from = self.takenAt;
    SGLog(@"system menu: the menu is up %.2f s after the takeover, first asked for at %.2f%@, %@",
          now - from, _askedAt - from,
          _wasEarly ? @" while the sheet came up" : @"", _openedAt ? [NSString stringWithFormat:@"the sheet up at %.2f", _openedAt - from] : @"before the sheet was up");
}

// Something of Spotify's was presented while a row picked on this sheet fired: the row's own sheet.
- (void)rowPresented {
    _rowPresented = YES;
}

#pragma mark the menu

// Spotify's rows, waited for.
- (UIMenu *)menu {
    return [UIMenu menuWithChildren:@[[self deferredRows]]];
}

// The sheet's rows as menu items. Uncached: every menu reads the sheet it was opened with.
- (UIDeferredMenuElement *)deferredRows {
    __weak SGRMenuSession *weakSelf = self;
    return [UIDeferredMenuElement elementWithUncachedProvider:^(void (^completion)(NSArray<UIMenuElement *> *)) {
        SGRMenuSession *session = weakSelf;
        if (!session || session->_groups) {
            completion(session ? [session rowElements] : @[]);
            return;
        }
        SGLog(@"system menu: Spotify's rows asked for before the sheet has them");
        [session->_whenRead addObject:^{
            SGRMenuSession *read = weakSelf;
            NSArray<UIMenuElement *> *elements = read ? [read rowElements] : @[];
            completion(elements);
            // UIKit can leave its loading row up although the rows were handed to it: the menu it shows is built
            // again after this one, and its deferred element is never asked (the songs liked by one artist, device
            // 2026-10-23). The visible menu is then given the rows in place of it, tried as the menu comes on screen.
            for (NSNumber *after in @[@0.15, @0.45, @0.9]) {
                dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(after.doubleValue * NSEC_PER_SEC)), dispatch_get_main_queue(), ^{
                    SGRMenuSession *later = weakSelf;
                    if (!later || later.ended) return;
                    [later.anchor.contextMenuInteraction updateVisibleMenuWithBlock:^UIMenu *(UIMenu *visible) {
                        NSUInteger at = [visible.children indexOfObjectPassingTest:^BOOL(UIMenuElement *child, NSUInteger index, BOOL *stop) {
                            return [child isKindOfClass:UIDeferredMenuElement.class];
                        }];
                        if (at == NSNotFound) return visible;
                        NSMutableArray<UIMenuElement *> *children = [visible.children mutableCopy];
                        [children replaceObjectsInRange:NSMakeRange(at, 1) withObjectsFromArray:elements];
                        return [visible menuByReplacingChildren:children];
                    }];
                });
            }
        }];
    }];
}

- (UIMenuElement *)elementFor:(SGRSheetRow *)row {
    if ([row.control isKindOfClass:UIButton.class]) {
        UIButton *button = (UIButton *)row.control;
        if (button.menu && button.showsMenuAsPrimaryAction) return button.menu;
    }
    return [self actionFor:row];
}

- (NSArray<UIMenuElement *> *)rowElements {
    NSMutableArray<UIMenuElement *> *groups = [NSMutableArray array];
    for (NSArray<SGRSheetRow *> *group in _groups) {
        NSMutableArray<UIMenuElement *> *actions = [NSMutableArray array];
        for (SGRSheetRow *row in group) [actions addObject:[self elementFor:row]];
        if (actions.count) [groups addObject:inlineGroup(actions)];
    }
    return groups;
}

- (UIAction *)actionFor:(SGRSheetRow *)row {
    __weak SGRMenuSession *weakSelf = self;
    UIAction *action = [UIAction actionWithTitle:row.title image:row.image identifier:nil handler:^(UIAction *picked) {
        weakSelf.pick = ^{ [weakSelf fire:row]; };
    }];
    action.subtitle = row.subtitle;
    if (!row.enabled) action.attributes = UIMenuElementAttributesDisabled;
    return action;
}

#pragma mark the rows

- (void)pollRows {
    if (_poll) return;
    __weak SGRMenuSession *weakSelf = self;
    // In the common modes, so a scroll through the menu does not hold the rows back.
    _poll = [NSTimer timerWithTimeInterval:kRowsPoll repeats:YES block:^(NSTimer *timer) {
        SGRMenuSession *session = weakSelf;
        if (!session || session.ended || [session readRows]) {
            [timer invalidate];
            if (session) session->_poll = nil;
        }
    }];
    [NSRunLoop.mainRunLoop addTimer:_poll forMode:NSRunLoopCommonModes];
}

// Reads the sheet's rows once it has them, and runs what waited for them. Whether they are read.
- (BOOL)readRows {
    if (_groups) return YES;
    UITableView *table = tableIn(self.sheet.viewIfLoaded, 0);
    if (!table || rowCount(table) == 0) return NO;
    SGAlbumQueueInstall(self.sheet);
    SGBatchTranslationInstall(self.sheet);
    CFTimeInterval started = CACurrentMediaTime();
    [table layoutIfNeeded];
    _table = table;
    NSMutableArray<NSArray<SGRSheetRow *> *> *groups = [NSMutableArray array];
    NSArray<SGRSheetRow *> *header = [self modRows:modRowsIn(table.tableHeaderView)];
    if (header.count) [groups addObject:header];
    NSUInteger read = 0;
    for (NSInteger section = 0; section < table.numberOfSections; section++) {
        NSMutableArray<SGRSheetRow *> *rows = [NSMutableArray array];
        for (NSInteger index = 0; index < [table numberOfRowsInSection:section]; index++) {
            SGRSheetRow *row = [self rowAt:[NSIndexPath indexPathForRow:index inSection:section] inTable:table];
            if (row) [rows addObject:row];
        }
        read += rows.count;
        if (rows.count) [groups addObject:rows];
    }
    NSArray<SGRSheetRow *> *footer = [self modRows:modRowsIn(table.tableFooterView)];
    if (footer.count) [groups addObject:footer];
    _groups = groups;
    CFTimeInterval now = CACurrentMediaTime();
    SGLog(@"system menu: %lu of Spotify's rows and %lu of the mod's read in %.0f ms, %.2f s after the takeover", (unsigned long)read,
          (unsigned long)(header.count + footer.count), (now - started) * 1000, now - self.takenAt);
    // The anchor's menu becomes the rows themselves. UIKit builds the menu it shows again from the
    // anchor's (the one asked for while the sheet came up is never on screen), so the menu comes up whole instead of
    // from its loading row, growing down as the rows come (device, 2026-10-23).
    if (self.anchor && !self.ended) self.anchor.menu = [UIMenu menuWithChildren:[self rowElements]];

    NSArray<dispatch_block_t> *waiting = _whenRead;
    _whenRead = [NSMutableArray array];
    for (dispatch_block_t block in waiting) block();
    return YES;
}

- (SGRSheetRow *)rowAt:(NSIndexPath *)path inTable:(UITableView *)table {
    UITableViewCell *cell = [table cellForRowAtIndexPath:path];
    if (!cell && [table.dataSource respondsToSelector:@selector(tableView:cellForRowAtIndexPath:)]) cell = [table.dataSource tableView:table cellForRowAtIndexPath:path];
    NSArray<UILabel *> *labels = labelsIn(cell);
    if (!labels.count) return nil;
    SGRSheetRow *row = [SGRSheetRow new];
    row.path = path;
    row.title = labels[0].text;
    if (labels.count > 1) row.subtitle = labels[1].text;
    row.image = glyphIn(cell, row.title);
    row.identifier = identifierIn(cell);
    row.enabled = rowEnabled(table, path, cell, labels[0]);
    return row;
}

- (NSArray<SGRSheetRow *> *)modRows:(NSArray<UIControl *> *)controls {
    NSMutableArray<SGRSheetRow *> *rows = [NSMutableArray array];
    for (UIControl *control in controls) {
        SGRSheetRow *row = [SGRSheetRow new];
        row.control = control;
        row.title = control.accessibilityLabel;
        row.image = glyphIn(control, row.title);
        row.enabled = YES;
        [rows addObject:row];
    }
    return rows;
}

// A row of the sheet's fired, on the sheet still hidden under where the menu was.
- (void)fire:(SGRSheetRow *)row {
    UIViewController *presented = self.presented;
    if (!presented.presentingViewController || self.revealed) return;
    sg_firing = self;
    _rowPresented = NO;
    if (row.control) {
        [row.control sendActionsForControlEvents:UIControlEventTouchUpInside];
    } else {
        UITableView *table = _table;
        if (table.window) selectRow(table, row.path);
    }
    // A row that pushes a page of its own inside the sheet shows it as it pushes (the push hook below); one that
    // leaves the sheet up some other way shows it after kSettle.
    dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(kSettle * NSEC_PER_SEC)), dispatch_get_main_queue(), ^{
        if (sg_firing == self) sg_firing = nil;
        UIViewController *still = self.presented;
        if (self.revealed || !still.presentingViewController || still.isBeingDismissed || !still.viewIfLoaded.window) return;
        // Spotify put up a sheet of the row's own (Sleep timer's): that is what shows; the card it came from goes,
        // unseen, never over it.
        if (self->_rowPresented) {
            SGLog(@"system menu: the row picked (%@) put up a sheet of its own, Spotify's hidden card goes unseen", row.title);
            [still.presentingViewController dismissViewControllerAnimated:NO completion:nil];
            return;
        }
        UINavigationController *navigation = self.sheet.navigationController;
        SGLog(@"system menu: the row picked (%@) left Spotify's sheet up without pushing a page, so it is shown (it holds %@%@)", row.title,
              navigation ? [[navigation.viewControllers valueForKey:@"class"] componentsJoinedByString:@" > "] : NSStringFromClass(self.sheet.class),
              still.presentedViewController ? [NSString stringWithFormat:@", and presents %@", NSStringFromClass(still.presentedViewController.class)] : @"");
        [self reveal];
    });
}

// The menu is gone. A pick is fired now, on the sheet still hidden under it; anything else leaves the sheet
// nothing to do, so it goes. Done a turn later, once the menu's own presentation is off the sheet.
- (void)menuEnded {
    if (self.ended) return;
    self.ended = YES;
    void (^pick)(void) = self.pick;
    self.pick = nil;
    dispatch_async(dispatch_get_main_queue(), ^{
        UIViewController *presented = self.presented;
        if (self.revealed) return;
        if (!presented.presentingViewController) return;
        if (!pick) {
            [presented.presentingViewController dismissViewControllerAnimated:NO completion:nil];
            // Never a hidden sheet left behind: should UIKit have turned the dismissal down, it is asked again.
            dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(0.5 * NSEC_PER_SEC)), dispatch_get_main_queue(), ^{
                UIViewController *still = self.presented;
                if (!still.presentingViewController || still.isBeingDismissed || self.revealed) return;
                SGLog(@"system menu: Spotify's hidden sheet was still up after the menu closed, dismissed again");
                [still.presentingViewController dismissViewControllerAnimated:NO completion:nil];
            });
            return;
        }
        pick();
    });
}

// Spotify's sheet as it would have been: what the menu falls back to, and what a row that opens a page of
// the sheet's own leads to.
// The sheet unseen and out of the way of touches, so one left up for any reason never stands between a finger
// and the player.
- (void)hide {
    UIView *container = self.container;
    container.alpha = 0;
    container.userInteractionEnabled = NO;
}

- (void)reveal {
    if (self.revealed || !self.presented) return;
    self.revealed = YES;
    UIView *container = self.container;
    container.userInteractionEnabled = YES;
    SGRAnimate(SGRMotionFade, ^{ container.alpha = 1; }, nil);
    [self.sheet.viewIfLoaded setNeedsLayout];
}

@end

// The session on the sheet or a controller it is inside of. With `fresh`, as the sheet appears, a session whose
// menu has opened is an earlier showing's (a controller Spotify kept and shows again): it is let go, so this
// showing is looked at afresh rather than left to a session that is over.
static SGRMenuSession *sessionFor(UIViewController *controller, BOOL fresh) {
    for (UIViewController *vc = controller; vc; vc = vc.parentViewController) {
        SGRMenuSession *session = objc_getAssociatedObject(vc, &kSessionKey);
        if (!session) continue;
        if (!fresh || !session.opened) return session;
        SGLog(@"system menu: a ⋯ sheet appears again holding an earlier showing's session (on %@), let go", NSStringFromClass(vc.class));
        objc_setAssociatedObject(vc, &kSessionKey, nil, OBJC_ASSOCIATION_RETAIN_NONATOMIC);
    }
    return nil;
}

#pragma mark - the ⋯

static SGRMenuAnchor *anchorIn(UIView *host) {
    SGRMenuAnchor *anchor = objc_getAssociatedObject(host, &kAnchorKey);
    if (!anchor) {
        anchor = [SGRMenuAnchor buttonWithType:UIButtonTypeCustom];
        anchor.showsMenuAsPrimaryAction = YES;
        anchor.userInteractionEnabled = NO;
        // VoiceOver reaches the ⋯ itself, whose tap brings the menu up the same way.
        anchor.isAccessibilityElement = NO;
        anchor.accessibilityElementsHidden = YES;
        anchor.overrideUserInterfaceStyle = UIUserInterfaceStyleDark;
        anchor.autoresizingMask = UIViewAutoresizingFlexibleWidth | UIViewAutoresizingFlexibleHeight;
        objc_setAssociatedObject(host, &kAnchorKey, anchor, OBJC_ASSOCIATION_RETAIN_NONATOMIC);
    }
    if (anchor.superview != host) [host addSubview:anchor];
    anchor.frame = host.bounds;
    return anchor;
}

// A page's ⋯ was touched this recently: a context menu sheet that is not taken over now is worth a line saying why.
static BOOL claimRecent(void) {
    return SGRPinnedMoreRecentButton() != nil;
}

// Why a sheet was not taken over: every time while a ⋯ touch is recent, so the next log of a ⋯ that opened
// Spotify's sheet says why; a few times otherwise, since every other context menu in the app passes here too.
static void whyNot(NSString *via, BOOL recent, NSString *reason) {
    static int logged;
    if (recent || logged++ < 4) SGLog(@"system menu: a sheet %@, not taken over: %@", via, reason);
}

// The controllers from `presented` down, for the log of a presentation that held no sheet.
static NSString *controllersIn(UIViewController *presented) {
    NSMutableArray<NSString *> *names = [NSMutableArray arrayWithObject:NSStringFromClass(presented.class)];
    if ([presented isKindOfClass:UINavigationController.class]) {
        for (UIViewController *vc in ((UINavigationController *)presented).viewControllers) [names addObject:NSStringFromClass(vc.class)];
    }
    for (UIViewController *child in presented.childViewControllers) [names addObject:NSStringFromClass(child.class)];
    return [names componentsJoinedByString:@" > "];
}

// Whether this sheet is a watched ⋯'s, and if so its session, with the sheet's presentation now the menu's.
// `via` says which way in asked, for the log.
static SGRMenuSession *takeOver(UIViewController *presented, NSString *via) {
    BOOL recent = claimRecent();
    if (!sheetIn(presented)) {
        if (recent) SGLog(@"system menu: %@ presented soon after a page's ⋯ touch holds no ⋯ sheet (%@)", NSStringFromClass(presented.class),
                          controllersIn(presented));
        return nil;
    }
    // While a row picked on a menu's sheet fires, what comes up is that row's (Sleep timer's own sheet), never
    // a new ⋯ menu.
    if (sg_firing) {
        whyNot(via, YES, @"it came while a picked row fired, so it is the row's");
        return nil;
    }
    UIView *button = SGRPinnedMoreRecentButton();
    if (!button) {
        whyNot(via, recent, @"no page's ⋯ was touched");
        return nil;
    }
    if (!button.window) {
        whyNot(via, YES, [NSString stringWithFormat:@"the ⋯ touched (%@) is off screen", NSStringFromClass(button.class)]);
        return nil;
    }
    static BOOL canPresent, checked;
    if (!checked) {
        checked = YES;
        canPresent = [UIControl instancesRespondToSelector:NSSelectorFromString(@"performPrimaryAction")]
                  || [UIContextMenuInteraction instancesRespondToSelector:NSSelectorFromString(@"_presentMenuAtLocation:")];
    }
    if (!canPresent) {
        whyNot(via, YES, @"this iOS has no way to open a button's menu from code");
        return nil;
    }
    SGRMenuSession *session = [SGRMenuSession new];
    session.takenAt = CACurrentMediaTime();
    session.presented = presented;
    session.anchor = anchorIn(button);
    objc_setAssociatedObject(presented, &kSessionKey, session, OBJC_ASSOCIATION_RETAIN_NONATOMIC);
    SGLog(@"system menu: the ⋯ sheet taken over %@", via);
    return session;
}

// Should neither appearance call come to a sheet taken over as it laid out, its menu opens once its
// presentation is over all the same: looked at every tenth of a second for up to 3 s.
static void openWhenUp(SGRMenuSession *session, UIViewController *sheet, int tries) {
    __weak UIViewController *weakSheet = sheet;
    dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(0.1 * NSEC_PER_SEC)), dispatch_get_main_queue(), ^{
        UIViewController *up = weakSheet;
        if (session.opened || !up) return;
        UIViewController *outer = up;
        while (outer.parentViewController) outer = outer.parentViewController;
        if ((!up.viewIfLoaded.window || outer.isBeingPresented) && tries < 30) {
            openWhenUp(session, up, tries + 1);
            return;
        }
        SGLog(@"system menu: the ⋯ sheet taken over as it laid out did not say it appeared, its menu opened anyway");
        [session open];
    });
}

// A row picked on the hidden sheet that pushes a page inside it (Sleep timer's options): the page goes in without
// its slide, so the sheet is shown on that page rather than on the card it covers, and the sheet is shown.
%hook UINavigationController
- (void)pushViewController:(UIViewController *)page animated:(BOOL)animated {
    SGRMenuSession *session = sg_firing;
    UIView *container = session.container;
    if (!session || session.revealed || !container || ![self.viewIfLoaded isDescendantOfView:container]) {
        %orig;
        return;
    }
    sg_firing = nil;
    SGLog(@"system menu: the row picked pushed %@ inside Spotify's sheet, which is shown on it", NSStringFromClass(page.class));
    %orig(page, NO);
    [session reveal];
}
%end

%hook UIViewController
- (void)presentViewController:(UIViewController *)presented animated:(BOOL)animated completion:(void (^)(void))completion {
    SGRMenuSession *firing = sg_firing;
    if (firing) {
        SGLog(@"system menu: while a picked row fires, %@ presents %@", NSStringFromClass(self.class), NSStringFromClass(presented.class));
        [firing rowPresented];
    }
    SGRMenuSession *session = takeOver(presented, @"as it is presented");
    if (!session) {
        %orig;
        return;
    }
    %orig(presented, NO, ^{
        if (completion) completion();
        [session open];
    });
}
%end

%hook _TtC24ContextMenu_InternalImpl25ContextMenuViewController
// A sheet Spotify puts up some other way than presentViewController: (the player's ⋯ on a phone), or inside a
// controller of its own that held no sheet yet when it was presented, is taken over as it first lays out or
// appears, from the same claim, and its menu opened once it has appeared.
//
// Its first layout can come before its presentation's container exists, so it is hidden at each layout and in
// viewWillAppear:, the first moment the container does exist, before it has drawn a frame; its dimming too, so
// the screen does not darken under the menu.
- (void)viewDidLayoutSubviews {
    %orig;
    UIViewController *sheet = (UIViewController *)self;
    SGRMenuSession *session = sessionFor(sheet, NO);
    // Only a sheet on its way up, not one that was up before the ⋯ was touched laying out again.
    UIViewController *outer = sheet;
    while (outer.parentViewController) outer = outer.parentViewController;
    if (!session && claimRecent() && (!sheet.viewIfLoaded.window || outer.isBeingPresented)) {
        session = takeOver(sheet, @"as it lays out");
        if (session) openWhenUp(session, sheet, 0);
    }
    // Until its menu opens: a session that has opened hides its sheet itself, or is an earlier showing's.
    if (session && !session.opened && !session.revealed) [session hide];
}

- (void)viewWillAppear:(BOOL)animated {
    %orig;
    SGRMenuSession *session = sessionFor((UIViewController *)self, YES);
    if (!session) session = takeOver((UIViewController *)self, @"as it appears");
    if (session && !session.revealed) [session hide];
    if (session) dispatch_async(dispatch_get_main_queue(), ^{ [session tryEarly]; });
}

- (void)viewDidAppear:(BOOL)animated {
    %orig;
    SGRMenuSession *session = sessionFor((UIViewController *)self, NO);
    if (session && !session.opened) [session open];
}
%end

%ctor {
    if (!SGRedesignedUI()) return;
    %init;
    SGRequireClasses(@[kSheetClass]);
}
