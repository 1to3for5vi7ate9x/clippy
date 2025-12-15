/**
 * clippy_picker.m - Global Hotkey Clipboard Picker
 *
 * A native macOS GUI app that provides a global hotkey (Cmd+Shift+V)
 * to display a fuzzy search popup for clipboard history selection.
 *
 * Build: clang -framework AppKit -framework Foundation -framework Carbon -Iinclude -o clippy-picker clippy_picker.m
 */

#import <AppKit/AppKit.h>
#import <Carbon/Carbon.h>
#include "clippy_common.h"

// ============================================================================
// Constants
// ============================================================================

#define PICKER_WIDTH 600
#define PICKER_HEIGHT 400
#define ROW_HEIGHT 44
#define SEARCH_HEIGHT 36
#define PADDING 12

// Keycode for 'V' key
#define KEYCODE_V 9

// ============================================================================
// Fuzzy Search
// ============================================================================

typedef struct {
    BOOL matches;
    NSInteger score;
} FuzzyMatchResult;

/**
 * Fuzzy match algorithm with scoring
 * Scores based on: substring match, position, consecutive matches, word boundaries
 */
static FuzzyMatchResult fuzzyMatch(NSString *pattern, NSString *text) {
    FuzzyMatchResult result = {NO, 0};

    if (!pattern || [pattern length] == 0) {
        result.matches = YES;
        result.score = 0;
        return result;
    }

    if (!text || [text length] == 0) {
        return result;
    }

    NSString *lowerPattern = [pattern lowercaseString];
    NSString *lowerText = [text lowercaseString];

    NSUInteger patternIdx = 0;
    NSUInteger textIdx = 0;
    NSInteger score = 0;
    NSInteger consecutiveBonus = 0;
    NSInteger lastMatchIdx = -2;

    while (patternIdx < [lowerPattern length] && textIdx < [lowerText length]) {
        unichar patternChar = [lowerPattern characterAtIndex:patternIdx];
        unichar textChar = [lowerText characterAtIndex:textIdx];

        if (patternChar == textChar) {
            score += 1;

            // Bonus for consecutive matches
            if ((NSInteger)textIdx == lastMatchIdx + 1) {
                consecutiveBonus += 2;
                score += consecutiveBonus;
            } else {
                consecutiveBonus = 0;
            }

            // Bonus for matching at word start
            if (textIdx == 0) {
                score += 10;
            } else {
                unichar prevChar = [lowerText characterAtIndex:textIdx - 1];
                if ([[NSCharacterSet whitespaceAndNewlineCharacterSet] characterIsMember:prevChar] ||
                    [[NSCharacterSet punctuationCharacterSet] characterIsMember:prevChar]) {
                    score += 5;
                }
            }

            // Bonus for early position
            score += MAX(0, (50 - (NSInteger)textIdx));

            lastMatchIdx = textIdx;
            patternIdx++;
        }
        textIdx++;
    }

    result.matches = (patternIdx == [lowerPattern length]);
    result.score = result.matches ? score : 0;
    return result;
}

// ============================================================================
// Custom Table Cell View
// ============================================================================

@interface ClippyTableCellView : NSTableCellView
@property (strong) NSTextField *mainLabel;
@property (strong) NSTextField *timeLabel;
@property (strong) NSTextField *typeLabel;
@end

@implementation ClippyTableCellView

- (instancetype)initWithFrame:(NSRect)frame {
    self = [super initWithFrame:frame];
    if (self) {
        // Main text label
        _mainLabel = [[NSTextField alloc] initWithFrame:NSZeroRect];
        _mainLabel.bordered = NO;
        _mainLabel.editable = NO;
        _mainLabel.backgroundColor = [NSColor clearColor];
        _mainLabel.font = [NSFont systemFontOfSize:13];
        _mainLabel.textColor = [NSColor labelColor];
        _mainLabel.lineBreakMode = NSLineBreakByTruncatingTail;
        _mainLabel.translatesAutoresizingMaskIntoConstraints = NO;
        [self addSubview:_mainLabel];

        // Time label
        _timeLabel = [[NSTextField alloc] initWithFrame:NSZeroRect];
        _timeLabel.bordered = NO;
        _timeLabel.editable = NO;
        _timeLabel.backgroundColor = [NSColor clearColor];
        _timeLabel.font = [NSFont systemFontOfSize:10];
        _timeLabel.textColor = [NSColor secondaryLabelColor];
        _timeLabel.translatesAutoresizingMaskIntoConstraints = NO;
        [self addSubview:_timeLabel];

        // Type label (for images/pins)
        _typeLabel = [[NSTextField alloc] initWithFrame:NSZeroRect];
        _typeLabel.bordered = NO;
        _typeLabel.editable = NO;
        _typeLabel.backgroundColor = [NSColor clearColor];
        _typeLabel.font = [NSFont systemFontOfSize:9 weight:NSFontWeightMedium];
        _typeLabel.textColor = [NSColor systemBlueColor];
        _typeLabel.translatesAutoresizingMaskIntoConstraints = NO;
        [self addSubview:_typeLabel];

        // Layout constraints
        [NSLayoutConstraint activateConstraints:@[
            [_timeLabel.leadingAnchor constraintEqualToAnchor:self.leadingAnchor constant:12],
            [_timeLabel.topAnchor constraintEqualToAnchor:self.topAnchor constant:6],
            [_timeLabel.widthAnchor constraintEqualToConstant:100],

            [_typeLabel.leadingAnchor constraintEqualToAnchor:_timeLabel.trailingAnchor constant:8],
            [_typeLabel.centerYAnchor constraintEqualToAnchor:_timeLabel.centerYAnchor],

            [_mainLabel.leadingAnchor constraintEqualToAnchor:self.leadingAnchor constant:12],
            [_mainLabel.trailingAnchor constraintEqualToAnchor:self.trailingAnchor constant:-12],
            [_mainLabel.topAnchor constraintEqualToAnchor:_timeLabel.bottomAnchor constant:2],
        ]];
    }
    return self;
}

@end

// ============================================================================
// App Delegate
// ============================================================================

@interface ClippyPickerAppDelegate : NSObject <NSApplicationDelegate, NSTableViewDataSource,
                                                NSTableViewDelegate, NSTextFieldDelegate,
                                                NSWindowDelegate>

@property (strong) NSStatusItem *statusItem;
@property (strong) NSPanel *pickerWindow;
@property (strong) NSTextField *searchField;
@property (strong) NSTableView *tableView;
@property (strong) NSVisualEffectView *effectView;

@property (strong) NSMutableArray *allHistory;
@property (strong) NSMutableArray *filteredHistory;

@property (assign) CFMachPortRef eventTap;
@property (assign) CFRunLoopSourceRef runLoopSource;

@end

@implementation ClippyPickerAppDelegate

// ============================================================================
// Application Lifecycle
// ============================================================================

- (void)applicationDidFinishLaunching:(NSNotification *)notification {
    // Load config
    clippy_load_config();

    // Set as accessory app (no dock icon)
    [NSApp setActivationPolicy:NSApplicationActivationPolicyAccessory];

    // Setup components
    [self setupStatusItem];
    [self createPickerWindow];

    // Setup global hotkey
    if ([self checkAccessibilityPermission]) {
        if (![self setupGlobalHotkey]) {
            [self showAccessibilityAlert];
        }
    } else {
        [self showAccessibilityAlert];
    }

    // Listen for show picker notification
    [[NSNotificationCenter defaultCenter] addObserver:self
                                             selector:@selector(showPicker:)
                                                 name:@"ShowPickerNotification"
                                               object:nil];
}

- (void)applicationWillTerminate:(NSNotification *)notification {
    if (self.eventTap) {
        CGEventTapEnable(self.eventTap, false);
        CFMachPortInvalidate(self.eventTap);
        CFRelease(self.eventTap);
    }
    if (self.runLoopSource) {
        CFRunLoopRemoveSource(CFRunLoopGetCurrent(), self.runLoopSource, kCFRunLoopCommonModes);
        CFRelease(self.runLoopSource);
    }
}

// ============================================================================
// Status Bar
// ============================================================================

- (void)setupStatusItem {
    self.statusItem = [[NSStatusBar systemStatusBar] statusItemWithLength:NSVariableStatusItemLength];

    // Use clipboard icon
    NSImage *icon = [NSImage imageWithSystemSymbolName:@"doc.on.clipboard"
                              accessibilityDescription:@"Clippy"];
    if (!icon) {
        // Fallback for older macOS
        icon = [NSImage imageNamed:NSImageNameTouchBarHistoryTemplate];
    }
    [icon setTemplate:YES];
    self.statusItem.button.image = icon;
    self.statusItem.button.toolTip = @"Clippy - Clipboard History";

    // Create menu
    NSMenu *menu = [[NSMenu alloc] init];

    NSMenuItem *showItem = [[NSMenuItem alloc] initWithTitle:@"Show Picker"
                                                      action:@selector(showPicker:)
                                               keyEquivalent:@""];
    showItem.keyEquivalentModifierMask = NSEventModifierFlagCommand | NSEventModifierFlagShift;
    showItem.keyEquivalent = @"v";
    [menu addItem:showItem];

    [menu addItem:[NSMenuItem separatorItem]];

    [menu addItemWithTitle:@"Quit Clippy Picker"
                    action:@selector(terminate:)
             keyEquivalent:@"q"];

    self.statusItem.menu = menu;
}

// ============================================================================
// Accessibility Permission
// ============================================================================

- (BOOL)checkAccessibilityPermission {
    NSDictionary *options = @{(__bridge NSString *)kAXTrustedCheckOptionPrompt: @NO};
    return AXIsProcessTrustedWithOptions((__bridge CFDictionaryRef)options);
}

- (void)showAccessibilityAlert {
    dispatch_async(dispatch_get_main_queue(), ^{
        NSAlert *alert = [[NSAlert alloc] init];
        alert.messageText = @"Accessibility Permission Required";
        alert.informativeText = @"Clippy Picker needs Accessibility permission for the "
                                "Cmd+Shift+V global hotkey.\n\n"
                                "You can still use the menu bar icon to open the picker.";
        [alert addButtonWithTitle:@"Open System Settings"];
        [alert addButtonWithTitle:@"Later"];

        if ([alert runModal] == NSAlertFirstButtonReturn) {
            NSString *urlString = @"x-apple.systempreferences:"
                                  "com.apple.preference.security?Privacy_Accessibility";
            [[NSWorkspace sharedWorkspace] openURL:[NSURL URLWithString:urlString]];
        }
    });
}

// ============================================================================
// Global Hotkey
// ============================================================================

static CGEventRef hotkeyCallback(CGEventTapProxy proxy, CGEventType type,
                                  CGEventRef event, void *refcon) {
    (void)proxy;
    (void)refcon;

    // Handle tap disabled event
    if (type == kCGEventTapDisabledByTimeout || type == kCGEventTapDisabledByUserInput) {
        ClippyPickerAppDelegate *delegate = (__bridge ClippyPickerAppDelegate *)refcon;
        if (delegate.eventTap) {
            CGEventTapEnable(delegate.eventTap, true);
        }
        return event;
    }

    if (type == kCGEventKeyDown) {
        CGEventFlags flags = CGEventGetFlags(event);
        int64_t keycode = CGEventGetIntegerValueField(event, kCGKeyboardEventKeycode);

        // Check for Cmd+Shift+V
        BOOL hasCmd = (flags & kCGEventFlagMaskCommand) != 0;
        BOOL hasShift = (flags & kCGEventFlagMaskShift) != 0;
        BOOL noAlt = (flags & kCGEventFlagMaskAlternate) == 0;
        BOOL noCtrl = (flags & kCGEventFlagMaskControl) == 0;
        BOOL isV = (keycode == KEYCODE_V);

        if (hasCmd && hasShift && noAlt && noCtrl && isV) {
            dispatch_async(dispatch_get_main_queue(), ^{
                [[NSNotificationCenter defaultCenter]
                 postNotificationName:@"ShowPickerNotification" object:nil];
            });
            return NULL;  // Consume the event
        }
    }

    return event;
}

- (BOOL)setupGlobalHotkey {
    CGEventMask eventMask = CGEventMaskBit(kCGEventKeyDown);

    self.eventTap = CGEventTapCreate(
        kCGSessionEventTap,
        kCGHeadInsertEventTap,
        kCGEventTapOptionDefault,
        eventMask,
        hotkeyCallback,
        (__bridge void *)self
    );

    if (!self.eventTap) {
        NSLog(@"clippy-picker: Failed to create event tap");
        return NO;
    }

    self.runLoopSource = CFMachPortCreateRunLoopSource(kCFAllocatorDefault, self.eventTap, 0);
    CFRunLoopAddSource(CFRunLoopGetCurrent(), self.runLoopSource, kCFRunLoopCommonModes);
    CGEventTapEnable(self.eventTap, true);

    NSLog(@"clippy-picker: Global hotkey (Cmd+Shift+V) registered");
    return YES;
}

// ============================================================================
// Picker Window
// ============================================================================

- (void)createPickerWindow {
    NSRect frame = NSMakeRect(0, 0, PICKER_WIDTH, PICKER_HEIGHT);

    self.pickerWindow = [[NSPanel alloc]
        initWithContentRect:frame
                  styleMask:NSWindowStyleMaskBorderless | NSWindowStyleMaskNonactivatingPanel
                    backing:NSBackingStoreBuffered
                      defer:NO];

    [self.pickerWindow setLevel:NSFloatingWindowLevel];
    [self.pickerWindow setCollectionBehavior:
        NSWindowCollectionBehaviorCanJoinAllSpaces |
        NSWindowCollectionBehaviorFullScreenAuxiliary |
        NSWindowCollectionBehaviorTransient];
    [self.pickerWindow setOpaque:NO];
    [self.pickerWindow setBackgroundColor:[NSColor clearColor]];
    [self.pickerWindow setHasShadow:YES];
    [self.pickerWindow setDelegate:self];

    // Visual effect view for blur
    self.effectView = [[NSVisualEffectView alloc] initWithFrame:frame];
    self.effectView.material = NSVisualEffectMaterialHUDWindow;
    self.effectView.state = NSVisualEffectStateActive;
    self.effectView.wantsLayer = YES;
    self.effectView.layer.cornerRadius = 12;
    self.effectView.layer.masksToBounds = YES;
    self.effectView.autoresizingMask = NSViewWidthSizable | NSViewHeightSizable;

    [self.pickerWindow.contentView addSubview:self.effectView];

    [self setupSearchField];
    [self setupTableView];
}

- (void)setupSearchField {
    CGFloat y = PICKER_HEIGHT - SEARCH_HEIGHT - PADDING;
    NSRect searchFrame = NSMakeRect(PADDING, y, PICKER_WIDTH - 2 * PADDING, SEARCH_HEIGHT);

    self.searchField = [[NSTextField alloc] initWithFrame:searchFrame];
    self.searchField.placeholderString = @"Search clipboard history...";
    self.searchField.bordered = NO;
    self.searchField.focusRingType = NSFocusRingTypeNone;
    self.searchField.backgroundColor = [NSColor colorWithWhite:0.5 alpha:0.1];
    self.searchField.wantsLayer = YES;
    self.searchField.layer.cornerRadius = 8;
    self.searchField.font = [NSFont systemFontOfSize:16];
    self.searchField.delegate = self;
    self.searchField.autoresizingMask = NSViewWidthSizable | NSViewMinYMargin;

    // Add some padding inside the text field
    NSTextFieldCell *cell = self.searchField.cell;
    if ([cell respondsToSelector:@selector(setLineBreakMode:)]) {
        cell.lineBreakMode = NSLineBreakByTruncatingTail;
    }

    [self.effectView addSubview:self.searchField];
}

- (void)setupTableView {
    CGFloat tableHeight = PICKER_HEIGHT - SEARCH_HEIGHT - 3 * PADDING;
    NSRect scrollFrame = NSMakeRect(0, 0, PICKER_WIDTH, tableHeight);

    NSScrollView *scrollView = [[NSScrollView alloc] initWithFrame:scrollFrame];
    scrollView.hasVerticalScroller = YES;
    scrollView.hasHorizontalScroller = NO;
    scrollView.autohidesScrollers = YES;
    scrollView.drawsBackground = NO;
    scrollView.autoresizingMask = NSViewWidthSizable | NSViewHeightSizable;

    self.tableView = [[NSTableView alloc] initWithFrame:scrollView.bounds];
    self.tableView.dataSource = self;
    self.tableView.delegate = self;
    self.tableView.rowHeight = ROW_HEIGHT;
    self.tableView.backgroundColor = [NSColor clearColor];
    self.tableView.headerView = nil;
    self.tableView.intercellSpacing = NSMakeSize(0, 1);
    self.tableView.selectionHighlightStyle = NSTableViewSelectionHighlightStyleRegular;
    self.tableView.allowsEmptySelection = NO;
    self.tableView.doubleAction = @selector(confirmSelection);
    self.tableView.target = self;

    NSTableColumn *column = [[NSTableColumn alloc] initWithIdentifier:@"content"];
    column.width = PICKER_WIDTH;
    column.resizingMask = NSTableColumnAutoresizingMask;
    [self.tableView addTableColumn:column];

    scrollView.documentView = self.tableView;

    [self.effectView addSubview:scrollView];
}

// ============================================================================
// Show/Hide Picker
// ============================================================================

- (void)showPicker:(id)sender {
    (void)sender;

    // Load history
    self.allHistory = clippy_read_json_array(clippy_history_path());

    // Add pinned items at the top with marker
    NSArray *pins = clippy_read_json_array(clippy_pins_path());
    for (NSDictionary *pin in [pins reverseObjectEnumerator]) {
        NSMutableDictionary *marked = [pin mutableCopy];
        marked[@"isPinned"] = @YES;
        [self.allHistory insertObject:marked atIndex:0];
    }

    // Reset search and filter
    self.searchField.stringValue = @"";
    self.filteredHistory = [self.allHistory mutableCopy];
    [self.tableView reloadData];

    // Center on main screen
    NSScreen *screen = [NSScreen mainScreen];
    NSRect screenFrame = screen.visibleFrame;
    NSRect windowFrame = self.pickerWindow.frame;
    CGFloat x = NSMidX(screenFrame) - windowFrame.size.width / 2;
    CGFloat y = NSMidY(screenFrame) - windowFrame.size.height / 2 + 100;
    [self.pickerWindow setFrameOrigin:NSMakePoint(x, y)];

    // Show and focus
    [self.pickerWindow makeKeyAndOrderFront:nil];
    [NSApp activateIgnoringOtherApps:YES];
    [self.pickerWindow makeFirstResponder:self.searchField];

    // Select first row if available
    if ([self.filteredHistory count] > 0) {
        [self.tableView selectRowIndexes:[NSIndexSet indexSetWithIndex:0]
                    byExtendingSelection:NO];
        [self.tableView scrollRowToVisible:0];
    }
}

- (void)hidePickerWindow {
    [self.pickerWindow orderOut:nil];
}

// ============================================================================
// Window Delegate
// ============================================================================

- (void)windowDidResignKey:(NSNotification *)notification {
    (void)notification;
    [self hidePickerWindow];
}

// ============================================================================
// Filter Results
// ============================================================================

- (void)updateFilteredResults {
    NSString *query = self.searchField.stringValue;

    if ([query length] == 0) {
        self.filteredHistory = [self.allHistory mutableCopy];
    } else {
        NSMutableArray *scored = [NSMutableArray array];

        for (NSDictionary *entry in self.allHistory) {
            NSString *text = entry[@"text"] ?: @"";
            NSString *label = entry[@"label"] ?: @"";

            // Match against both text and label
            FuzzyMatchResult textMatch = fuzzyMatch(query, text);
            FuzzyMatchResult labelMatch = fuzzyMatch(query, label);

            NSInteger bestScore = MAX(textMatch.score, labelMatch.score);
            BOOL matches = textMatch.matches || labelMatch.matches;

            if (matches) {
                [scored addObject:@{
                    @"entry": entry,
                    @"score": @(bestScore)
                }];
            }
        }

        // Sort by score descending
        [scored sortUsingComparator:^NSComparisonResult(id a, id b) {
            return [b[@"score"] compare:a[@"score"]];
        }];

        self.filteredHistory = [[scored valueForKey:@"entry"] mutableCopy];
    }

    [self.tableView reloadData];

    // Select first row
    if ([self.filteredHistory count] > 0) {
        [self.tableView selectRowIndexes:[NSIndexSet indexSetWithIndex:0]
                    byExtendingSelection:NO];
    }
}

// ============================================================================
// Table View Data Source
// ============================================================================

- (NSInteger)numberOfRowsInTableView:(NSTableView *)tableView {
    (void)tableView;
    return [self.filteredHistory count];
}

- (NSView *)tableView:(NSTableView *)tableView viewForTableColumn:(NSTableColumn *)tableColumn row:(NSInteger)row {
    (void)tableColumn;

    ClippyTableCellView *cell = [tableView makeViewWithIdentifier:@"ClippyCell" owner:self];
    if (!cell) {
        cell = [[ClippyTableCellView alloc] initWithFrame:NSMakeRect(0, 0, PICKER_WIDTH, ROW_HEIGHT)];
        cell.identifier = @"ClippyCell";
    }

    NSDictionary *entry = self.filteredHistory[row];
    NSString *text = entry[@"text"] ?: @"";
    NSNumber *timestamp = entry[@"timestamp"];
    NSString *type = entry[@"type"] ?: @"text";
    BOOL isPinned = [entry[@"isPinned"] boolValue];
    NSString *label = entry[@"label"];

    // Format timestamp
    cell.timeLabel.stringValue = timestamp ? clippy_format_timestamp(timestamp) : @"";

    // Format type indicator
    if (isPinned) {
        cell.typeLabel.stringValue = label ? [NSString stringWithFormat:@"PIN: %@", label] : @"PIN";
        cell.typeLabel.textColor = [NSColor systemOrangeColor];
    } else if ([type isEqualToString:@"image"]) {
        cell.typeLabel.stringValue = @"IMAGE";
        cell.typeLabel.textColor = [NSColor systemPurpleColor];
    } else {
        cell.typeLabel.stringValue = @"";
    }

    // Format main text
    cell.mainLabel.stringValue = clippy_preview_text(text);

    return cell;
}

// ============================================================================
// Keyboard Navigation
// ============================================================================

- (void)controlTextDidChange:(NSNotification *)notification {
    (void)notification;
    [self updateFilteredResults];
}

- (BOOL)control:(NSControl *)control textView:(NSTextView *)textView doCommandBySelector:(SEL)commandSelector {
    (void)control;
    (void)textView;

    if (commandSelector == @selector(moveUp:)) {
        [self selectPreviousRow];
        return YES;
    }
    if (commandSelector == @selector(moveDown:)) {
        [self selectNextRow];
        return YES;
    }
    if (commandSelector == @selector(insertNewline:)) {
        [self confirmSelection];
        return YES;
    }
    if (commandSelector == @selector(cancelOperation:)) {
        [self hidePickerWindow];
        return YES;
    }
    return NO;
}

- (void)selectNextRow {
    NSInteger nextRow = self.tableView.selectedRow + 1;
    if (nextRow < (NSInteger)[self.filteredHistory count]) {
        [self.tableView selectRowIndexes:[NSIndexSet indexSetWithIndex:nextRow]
                    byExtendingSelection:NO];
        [self.tableView scrollRowToVisible:nextRow];
    }
}

- (void)selectPreviousRow {
    NSInteger prevRow = self.tableView.selectedRow - 1;
    if (prevRow >= 0) {
        [self.tableView selectRowIndexes:[NSIndexSet indexSetWithIndex:prevRow]
                    byExtendingSelection:NO];
        [self.tableView scrollRowToVisible:prevRow];
    }
}

- (void)confirmSelection {
    NSInteger row = self.tableView.selectedRow;
    if (row >= 0 && row < (NSInteger)[self.filteredHistory count]) {
        NSDictionary *entry = self.filteredHistory[row];
        [self copyEntryToClipboard:entry];
        [self hidePickerWindow];
    }
}

// ============================================================================
// Clipboard Operations
// ============================================================================

- (void)copyEntryToClipboard:(NSDictionary *)entry {
    NSPasteboard *pasteboard = [NSPasteboard generalPasteboard];
    [pasteboard clearContents];

    NSString *type = entry[@"type"] ?: @"text";

    if ([type isEqualToString:@"image"]) {
        NSString *path = entry[@"path"];
        if (path && [[NSFileManager defaultManager] fileExistsAtPath:path]) {
            NSData *imageData = [NSData dataWithContentsOfFile:path];
            if (imageData) {
                NSImage *image = [[NSImage alloc] initWithData:imageData];
                if (image) {
                    [pasteboard writeObjects:@[image]];
                    NSLog(@"clippy-picker: Copied image to clipboard");
                    return;
                }
            }
        }
    }

    NSString *text = entry[@"text"];
    if (text) {
        [pasteboard setString:text forType:NSPasteboardTypeString];
        NSLog(@"clippy-picker: Copied text to clipboard");
    }
}

@end

// ============================================================================
// Main
// ============================================================================

int main(int argc, const char *argv[]) {
    (void)argc;
    (void)argv;

    @autoreleasepool {
        NSApplication *app = [NSApplication sharedApplication];
        ClippyPickerAppDelegate *delegate = [[ClippyPickerAppDelegate alloc] init];
        app.delegate = delegate;
        [app run];
    }
    return 0;
}
