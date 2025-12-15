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

// ============================================================================
// Fuzzy Search
// ============================================================================

typedef struct {
    BOOL matches;
    NSInteger score;
} FuzzyMatchResult;

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

            if ((NSInteger)textIdx == lastMatchIdx + 1) {
                consecutiveBonus += 2;
                score += consecutiveBonus;
            } else {
                consecutiveBonus = 0;
            }

            if (textIdx == 0) {
                score += 10;
            } else {
                unichar prevChar = [lowerText characterAtIndex:textIdx - 1];
                if ([[NSCharacterSet whitespaceAndNewlineCharacterSet] characterIsMember:prevChar] ||
                    [[NSCharacterSet punctuationCharacterSet] characterIsMember:prevChar]) {
                    score += 5;
                }
            }

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
// Picker Delegate Protocol
// ============================================================================

@protocol ClippyPickerDelegate <NSObject>
- (void)selectNextRow;
- (void)selectPreviousRow;
- (void)confirmSelection;
- (void)hidePickerWindow;
@end

// ============================================================================
// Custom Panel - Can Become Key Window
// ============================================================================

@interface ClippyPanel : NSPanel
@end

@implementation ClippyPanel

- (BOOL)canBecomeKeyWindow {
    return YES;
}

- (BOOL)canBecomeMainWindow {
    return YES;
}

@end

// ============================================================================
// Custom Search Field - Handles Arrow Keys
// ============================================================================

@interface ClippySearchField : NSTextField
@property (weak) id<ClippyPickerDelegate> pickerDelegate;
@end

@implementation ClippySearchField

- (BOOL)acceptsFirstResponder {
    return YES;
}

- (BOOL)becomeFirstResponder {
    BOOL result = [super becomeFirstResponder];
    if (result) {
        NSLog(@"clippy-picker: Search field became first responder");
    }
    return result;
}

- (BOOL)performKeyEquivalent:(NSEvent *)event {
    unsigned short keyCode = event.keyCode;

    // Escape
    if (keyCode == 53) {
        [self.pickerDelegate hidePickerWindow];
        return YES;
    }
    // Enter/Return
    if (keyCode == 36 || keyCode == 76) {
        [self.pickerDelegate confirmSelection];
        return YES;
    }

    return [super performKeyEquivalent:event];
}

- (void)keyDown:(NSEvent *)event {
    unsigned short keyCode = event.keyCode;

    NSLog(@"clippy-picker: keyDown received, keyCode=%d", keyCode);

    // Arrow Up
    if (keyCode == 126) {
        [self.pickerDelegate selectPreviousRow];
        return;
    }
    // Arrow Down
    if (keyCode == 125) {
        [self.pickerDelegate selectNextRow];
        return;
    }
    // Enter/Return
    if (keyCode == 36 || keyCode == 76) {
        [self.pickerDelegate confirmSelection];
        return;
    }
    // Escape
    if (keyCode == 53) {
        [self.pickerDelegate hidePickerWindow];
        return;
    }

    [super keyDown:event];
}

@end

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
        _mainLabel = [[NSTextField alloc] initWithFrame:NSZeroRect];
        _mainLabel.bordered = NO;
        _mainLabel.editable = NO;
        _mainLabel.backgroundColor = [NSColor clearColor];
        _mainLabel.font = [NSFont systemFontOfSize:13];
        _mainLabel.textColor = [NSColor labelColor];
        _mainLabel.lineBreakMode = NSLineBreakByTruncatingTail;
        _mainLabel.translatesAutoresizingMaskIntoConstraints = NO;
        [self addSubview:_mainLabel];

        _timeLabel = [[NSTextField alloc] initWithFrame:NSZeroRect];
        _timeLabel.bordered = NO;
        _timeLabel.editable = NO;
        _timeLabel.backgroundColor = [NSColor clearColor];
        _timeLabel.font = [NSFont systemFontOfSize:10];
        _timeLabel.textColor = [NSColor secondaryLabelColor];
        _timeLabel.translatesAutoresizingMaskIntoConstraints = NO;
        [self addSubview:_timeLabel];

        _typeLabel = [[NSTextField alloc] initWithFrame:NSZeroRect];
        _typeLabel.bordered = NO;
        _typeLabel.editable = NO;
        _typeLabel.backgroundColor = [NSColor clearColor];
        _typeLabel.font = [NSFont systemFontOfSize:9 weight:NSFontWeightMedium];
        _typeLabel.textColor = [NSColor systemBlueColor];
        _typeLabel.translatesAutoresizingMaskIntoConstraints = NO;
        [self addSubview:_typeLabel];

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
                                                NSWindowDelegate, ClippyPickerDelegate>

@property (strong) NSStatusItem *statusItem;
@property (strong) ClippyPanel *pickerWindow;
@property (strong) ClippySearchField *searchField;
@property (strong) NSTableView *tableView;
@property (strong) NSVisualEffectView *effectView;

@property (strong) NSMutableArray *allHistory;
@property (strong) NSMutableArray *filteredHistory;

@property (assign) CFMachPortRef eventTap;
@property (assign) CFRunLoopSourceRef runLoopSource;
@property (assign) EventHotKeyRef hotkeyRef;
@property (strong) id clickMonitor;

@end

@implementation ClippyPickerAppDelegate

// ============================================================================
// Application Lifecycle
// ============================================================================

- (void)applicationDidFinishLaunching:(NSNotification *)notification {
    clippy_load_config();

    [NSApp setActivationPolicy:NSApplicationActivationPolicyAccessory];

    [self setupStatusItem];
    [self createPickerWindow];

    // Try Carbon hotkey first (more reliable), fall back to CGEventTap
    if (![self setupCarbonHotkey]) {
        NSLog(@"clippy-picker: Carbon hotkey failed, trying CGEventTap...");
        if ([self checkAccessibilityPermission]) {
            if (![self setupGlobalHotkey]) {
                [self showAccessibilityAlert];
            }
        } else {
            [self showAccessibilityAlert];
        }
    }

    [[NSNotificationCenter defaultCenter] addObserver:self
                                             selector:@selector(showPicker:)
                                                 name:@"ShowPickerNotification"
                                               object:nil];

    NSLog(@"clippy-picker: Started successfully");
}

- (void)applicationWillTerminate:(NSNotification *)notification {
    if (self.hotkeyRef) {
        UnregisterEventHotKey(self.hotkeyRef);
    }
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

    NSImage *icon = [NSImage imageWithSystemSymbolName:@"doc.on.clipboard"
                              accessibilityDescription:@"Clippy"];
    if (!icon) {
        icon = [NSImage imageNamed:NSImageNameTouchBarHistoryTemplate];
    }
    if (icon) {
        [icon setTemplate:YES];
        self.statusItem.button.image = icon;
    } else {
        self.statusItem.button.title = @"📋";
    }
    self.statusItem.button.toolTip = @"Clippy - Clipboard History (Cmd+Shift+V)";

    NSMenu *menu = [[NSMenu alloc] init];

    NSMenuItem *showItem = [[NSMenuItem alloc] initWithTitle:@"Show Picker (Cmd+Shift+V)"
                                                      action:@selector(showPicker:)
                                               keyEquivalent:@"V"];
    showItem.keyEquivalentModifierMask = NSEventModifierFlagCommand | NSEventModifierFlagShift;
    [menu addItem:showItem];

    [menu addItem:[NSMenuItem separatorItem]];

    [menu addItemWithTitle:@"Quit Clippy Picker"
                    action:@selector(terminate:)
             keyEquivalent:@"q"];

    self.statusItem.menu = menu;
}

// ============================================================================
// Carbon Hotkey (More Reliable)
// ============================================================================

static OSStatus hotkeyHandler(EventHandlerCallRef nextHandler, EventRef event, void *userData) {
    (void)nextHandler;
    (void)event;
    (void)userData;

    dispatch_async(dispatch_get_main_queue(), ^{
        [[NSNotificationCenter defaultCenter]
         postNotificationName:@"ShowPickerNotification" object:nil];
    });

    return noErr;
}

- (BOOL)setupCarbonHotkey {
    EventTypeSpec eventType;
    eventType.eventClass = kEventClassKeyboard;
    eventType.eventKind = kEventHotKeyPressed;

    OSStatus status = InstallApplicationEventHandler(&hotkeyHandler, 1, &eventType, NULL, NULL);
    if (status != noErr) {
        NSLog(@"clippy-picker: Failed to install event handler: %d", (int)status);
        return NO;
    }

    EventHotKeyID hotkeyID;
    hotkeyID.signature = 'clip';
    hotkeyID.id = 1;

    // Cmd+Shift+V: keycode 9, modifiers cmdKey + shiftKey
    status = RegisterEventHotKey(9, cmdKey + shiftKey, hotkeyID,
                                  GetApplicationEventTarget(), 0, &_hotkeyRef);

    if (status != noErr) {
        NSLog(@"clippy-picker: Failed to register hotkey: %d", (int)status);
        return NO;
    }

    NSLog(@"clippy-picker: Carbon hotkey (Cmd+Shift+V) registered successfully");
    return YES;
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
// CGEventTap Global Hotkey (Fallback)
// ============================================================================

static CGEventRef hotkeyCallback(CGEventTapProxy proxy, CGEventType type,
                                  CGEventRef event, void *refcon) {
    (void)proxy;

    ClippyPickerAppDelegate *delegate = (__bridge ClippyPickerAppDelegate *)refcon;

    if (type == kCGEventTapDisabledByTimeout || type == kCGEventTapDisabledByUserInput) {
        NSLog(@"clippy-picker: Event tap was disabled, re-enabling...");
        if (delegate.eventTap) {
            CGEventTapEnable(delegate.eventTap, true);
        }
        return event;
    }

    if (type == kCGEventKeyDown) {
        CGEventFlags flags = CGEventGetFlags(event);
        int64_t keycode = CGEventGetIntegerValueField(event, kCGKeyboardEventKeycode);

        BOOL hasCmd = (flags & kCGEventFlagMaskCommand) != 0;
        BOOL hasShift = (flags & kCGEventFlagMaskShift) != 0;
        BOOL noAlt = (flags & kCGEventFlagMaskAlternate) == 0;
        BOOL noCtrl = (flags & kCGEventFlagMaskControl) == 0;

        // V key is keycode 9
        if (hasCmd && hasShift && noAlt && noCtrl && keycode == 9) {
            NSLog(@"clippy-picker: Hotkey detected!");
            dispatch_async(dispatch_get_main_queue(), ^{
                [[NSNotificationCenter defaultCenter]
                 postNotificationName:@"ShowPickerNotification" object:nil];
            });
            return NULL;
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
        NSLog(@"clippy-picker: Failed to create event tap - need Accessibility permission");
        return NO;
    }

    self.runLoopSource = CFMachPortCreateRunLoopSource(kCFAllocatorDefault, self.eventTap, 0);
    CFRunLoopAddSource(CFRunLoopGetCurrent(), self.runLoopSource, kCFRunLoopCommonModes);
    CGEventTapEnable(self.eventTap, true);

    NSLog(@"clippy-picker: CGEventTap hotkey registered");
    return YES;
}

// ============================================================================
// Picker Window
// ============================================================================

- (void)createPickerWindow {
    NSRect frame = NSMakeRect(0, 0, PICKER_WIDTH, PICKER_HEIGHT);

    self.pickerWindow = [[ClippyPanel alloc]
        initWithContentRect:frame
                  styleMask:NSWindowStyleMaskBorderless
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
    [self.pickerWindow setAcceptsMouseMovedEvents:YES];

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

    self.searchField = [[ClippySearchField alloc] initWithFrame:searchFrame];
    self.searchField.pickerDelegate = self;
    self.searchField.placeholderString = @"Search clipboard history... (↑↓ to navigate, Enter to select)";
    self.searchField.bordered = NO;
    self.searchField.focusRingType = NSFocusRingTypeNone;
    self.searchField.backgroundColor = [NSColor colorWithWhite:0.5 alpha:0.1];
    self.searchField.wantsLayer = YES;
    self.searchField.layer.cornerRadius = 8;
    self.searchField.font = [NSFont systemFontOfSize:16];
    self.searchField.delegate = self;
    self.searchField.autoresizingMask = NSViewWidthSizable | NSViewMinYMargin;

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

    NSLog(@"clippy-picker: Showing picker window");

    self.allHistory = clippy_read_json_array(clippy_history_path());

    NSArray *pins = clippy_read_json_array(clippy_pins_path());
    for (NSDictionary *pin in [pins reverseObjectEnumerator]) {
        NSMutableDictionary *marked = [pin mutableCopy];
        marked[@"isPinned"] = @YES;
        [self.allHistory insertObject:marked atIndex:0];
    }

    self.searchField.stringValue = @"";
    self.filteredHistory = [self.allHistory mutableCopy];
    [self.tableView reloadData];

    // Center on screen with mouse cursor
    NSPoint mouseLoc = [NSEvent mouseLocation];
    NSScreen *screen = [NSScreen mainScreen];
    for (NSScreen *s in [NSScreen screens]) {
        if (NSPointInRect(mouseLoc, s.frame)) {
            screen = s;
            break;
        }
    }

    NSRect screenFrame = screen.visibleFrame;
    NSRect windowFrame = self.pickerWindow.frame;
    CGFloat x = NSMidX(screenFrame) - windowFrame.size.width / 2;
    CGFloat y = NSMidY(screenFrame) - windowFrame.size.height / 2 + 100;
    [self.pickerWindow setFrameOrigin:NSMakePoint(x, y)];

    // Activate app and show window
    [NSApp activateIgnoringOtherApps:YES];
    [self.pickerWindow makeKeyAndOrderFront:nil];

    // Ensure search field gets focus - use dispatch to ensure window is ready
    dispatch_async(dispatch_get_main_queue(), ^{
        [self.pickerWindow makeFirstResponder:self.searchField];
        NSLog(@"clippy-picker: First responder set to search field");

        // Also select the text field's editor for immediate typing
        NSText *fieldEditor = [self.pickerWindow fieldEditor:YES forObject:self.searchField];
        if (fieldEditor) {
            [fieldEditor setSelectedRange:NSMakeRange(0, 0)];
        }
    });

    if ([self.filteredHistory count] > 0) {
        [self.tableView selectRowIndexes:[NSIndexSet indexSetWithIndex:0]
                    byExtendingSelection:NO];
        [self.tableView scrollRowToVisible:0];
    }

    // Add click monitor to close on click outside
    if (self.clickMonitor) {
        [NSEvent removeMonitor:self.clickMonitor];
    }
    __weak typeof(self) weakSelf = self;
    self.clickMonitor = [NSEvent addGlobalMonitorForEventsMatchingMask:NSEventMaskLeftMouseDown
                                                               handler:^(NSEvent *event) {
        NSPoint clickLoc = event.locationInWindow;
        NSPoint screenLoc = [event.window convertPointToScreen:clickLoc];
        NSRect windowFrame = weakSelf.pickerWindow.frame;

        if (!NSPointInRect(screenLoc, windowFrame)) {
            dispatch_async(dispatch_get_main_queue(), ^{
                [weakSelf hidePickerWindow];
            });
        }
    }];
}

- (void)hidePickerWindow {
    NSLog(@"clippy-picker: Hiding picker window");

    // Remove click monitor
    if (self.clickMonitor) {
        [NSEvent removeMonitor:self.clickMonitor];
        self.clickMonitor = nil;
    }

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

        [scored sortUsingComparator:^NSComparisonResult(id a, id b) {
            return [b[@"score"] compare:a[@"score"]];
        }];

        self.filteredHistory = [[scored valueForKey:@"entry"] mutableCopy];
    }

    [self.tableView reloadData];

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

    cell.timeLabel.stringValue = timestamp ? clippy_format_timestamp(timestamp) : @"";

    if (isPinned) {
        cell.typeLabel.stringValue = label ? [NSString stringWithFormat:@"📌 %@", label] : @"📌 PIN";
        cell.typeLabel.textColor = [NSColor systemOrangeColor];
    } else if ([type isEqualToString:@"image"]) {
        cell.typeLabel.stringValue = @"🖼 IMAGE";
        cell.typeLabel.textColor = [NSColor systemPurpleColor];
    } else {
        cell.typeLabel.stringValue = @"";
    }

    cell.mainLabel.stringValue = clippy_preview_text(text);

    return cell;
}

// ============================================================================
// Text Field Delegate
// ============================================================================

- (void)controlTextDidChange:(NSNotification *)notification {
    (void)notification;
    [self updateFilteredResults];
}

// Intercept arrow keys, Enter, and Escape from the search field
- (BOOL)control:(NSControl *)control textView:(NSTextView *)textView doCommandBySelector:(SEL)commandSelector {
    (void)control;
    (void)textView;

    NSLog(@"clippy-picker: doCommandBySelector: %@", NSStringFromSelector(commandSelector));

    // Arrow Up
    if (commandSelector == @selector(moveUp:)) {
        [self selectPreviousRow];
        return YES;
    }
    // Arrow Down
    if (commandSelector == @selector(moveDown:)) {
        [self selectNextRow];
        return YES;
    }
    // Enter/Return
    if (commandSelector == @selector(insertNewline:)) {
        [self confirmSelection];
        return YES;
    }
    // Escape
    if (commandSelector == @selector(cancelOperation:)) {
        [self hidePickerWindow];
        return YES;
    }

    return NO;
}

// ============================================================================
// Keyboard Navigation
// ============================================================================

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
        NSLog(@"clippy-picker: Copied to clipboard: %@", clippy_preview_text(text));
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
