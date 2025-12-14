/**
 * clippy - Clipboard History CLI
 *
 * Access clipboard history saved by clipd daemon.
 *
 * Build: clang -framework AppKit -framework Foundation -Iinclude -o clippy clippy.m
 */

#import <AppKit/AppKit.h>
#import <Foundation/Foundation.h>
#include "clippy_common.h"

// ============================================================================
// Clipboard Operations
// ============================================================================

void copyTextToClipboard(NSString *text) {
    NSPasteboard *pasteboard = [NSPasteboard generalPasteboard];
    [pasteboard clearContents];
    [pasteboard setString:text forType:NSPasteboardTypeString];
}

void copyImageToClipboard(NSString *imagePath) {
    NSData *imageData = [NSData dataWithContentsOfFile:imagePath];
    if (!imageData) {
        fprintf(stderr, "Error: Could not read image file: %s\n", [imagePath UTF8String]);
        return;
    }

    NSImage *image = [[NSImage alloc] initWithData:imageData];
    if (!image) {
        fprintf(stderr, "Error: Could not create image from data\n");
        return;
    }

    NSPasteboard *pasteboard = [NSPasteboard generalPasteboard];
    [pasteboard clearContents];
    [pasteboard writeObjects:@[image]];
}

// ============================================================================
// Help
// ============================================================================

void printUsage(void) {
    printf("clippy - Clipboard History CLI\n\n");
    printf("History Commands:\n");
    printf("  clippy list [N]        Show last N history items (default: 10)\n");
    printf("  clippy get <N>         Copy history item N to clipboard\n");
    printf("  clippy search <Q>      Search history for text\n");
    printf("  clippy clear           Clear all clipboard history\n");
    printf("  clippy raw <N>         Print history item N (for scripting)\n\n");
    printf("Pin Commands:\n");
    printf("  clippy pin <N> [label] Pin history item N (optional label)\n");
    printf("  clippy pins            List all pinned items\n");
    printf("  clippy paste <N>       Copy pinned item N to clipboard\n");
    printf("  clippy unpin <N>       Remove pinned item N\n\n");
    printf("Configuration:\n");
    printf("  clippy config          Show current configuration\n\n");
    printf("Examples:\n");
    printf("  clippy list            Show last 10 clipboard items\n");
    printf("  clippy get 1           Copy most recent item\n");
    printf("  clippy pin 3 \"API key\" Pin item 3 with label\n");
    printf("  clippy pins            Show all pins\n");
    printf("  clippy paste 1         Copy first pinned item\n");
}

// ============================================================================
// History Commands
// ============================================================================

int cmdList(int count) {
    NSArray *history = clippy_read_json_array(clippy_history_path());

    if ([history count] == 0) {
        printf("No clipboard history.\n");
        printf("Make sure clipd daemon is running: pgrep clipd\n");
        return 0;
    }

    NSInteger showCount = MIN(count, (int)[history count]);
    printf("Clipboard History (showing %ld of %lu):\n\n",
           (long)showCount, (unsigned long)[history count]);

    for (NSInteger i = 0; i < showCount; i++) {
        NSDictionary *entry = history[i];
        NSString *text = entry[@"text"];
        NSNumber *timestamp = entry[@"timestamp"];
        NSString *type = entry[@"type"] ?: @"text";

        NSString *timeStr = clippy_format_timestamp(timestamp);
        NSString *preview = clippy_preview_text(text);

        if ([type isEqualToString:@"image"]) {
            printf("  %2ld. [%s] [IMAGE] %s\n",
                   (long)(i + 1), [timeStr UTF8String], [preview UTF8String]);
        } else {
            printf("  %2ld. [%s] %s\n",
                   (long)(i + 1), [timeStr UTF8String], [preview UTF8String]);
        }
    }

    printf("\nUse 'clippy get <N>' to copy, 'clippy pin <N>' to save permanently.\n");
    return 0;
}

int cmdGet(int index) {
    NSArray *history = clippy_read_json_array(clippy_history_path());

    if ([history count] == 0) {
        fprintf(stderr, "Error: No clipboard history.\n");
        return 1;
    }

    if (index < 1 || index > (int)[history count]) {
        fprintf(stderr, "Error: Invalid index %d. Valid range: 1-%lu\n",
                index, (unsigned long)[history count]);
        return 1;
    }

    NSDictionary *entry = history[index - 1];
    NSString *type = entry[@"type"] ?: @"text";

    if ([type isEqualToString:@"image"]) {
        NSString *path = entry[@"path"];
        if (![[NSFileManager defaultManager] fileExistsAtPath:path]) {
            fprintf(stderr, "Error: Image file not found: %s\n", [path UTF8String]);
            return 1;
        }
        copyImageToClipboard(path);
        printf("Copied image to clipboard: %s\n", [entry[@"text"] UTF8String]);
    } else {
        NSString *text = entry[@"text"];
        copyTextToClipboard(text);
        printf("Copied to clipboard: %s\n", [clippy_preview_text(text) UTF8String]);
    }

    return 0;
}

int cmdRaw(int index) {
    NSArray *history = clippy_read_json_array(clippy_history_path());

    if (index < 1 || index > (int)[history count]) {
        return 1;
    }

    NSDictionary *entry = history[index - 1];
    NSString *text = entry[@"text"];

    printf("%s", [text UTF8String]);
    return 0;
}

int cmdClear(void) {
    NSString *path = clippy_history_path();
    NSFileManager *fm = [NSFileManager defaultManager];

    if (![fm fileExistsAtPath:path]) {
        printf("History already empty.\n");
        return 0;
    }

    NSError *error = nil;
    if ([fm removeItemAtPath:path error:&error]) {
        printf("Clipboard history cleared.\n");
        return 0;
    }

    fprintf(stderr, "Error: Failed to clear history: %s\n",
            [[error localizedDescription] UTF8String]);
    return 1;
}

int cmdSearch(NSString *query) {
    NSArray *history = clippy_read_json_array(clippy_history_path());

    if ([history count] == 0) {
        printf("No clipboard history to search.\n");
        return 0;
    }

    query = [query lowercaseString];
    NSMutableArray *results = [NSMutableArray array];

    for (NSInteger i = 0; i < (NSInteger)[history count]; i++) {
        NSDictionary *entry = history[i];
        NSString *text = entry[@"text"];

        if ([[text lowercaseString] containsString:query]) {
            [results addObject:@{@"index": @(i + 1), @"entry": entry}];
        }
    }

    if ([results count] == 0) {
        printf("No results found for '%s'.\n", [query UTF8String]);
        return 0;
    }

    printf("Search results for '%s' (%lu matches):\n\n",
           [query UTF8String], (unsigned long)[results count]);

    for (NSDictionary *result in results) {
        NSInteger index = [result[@"index"] integerValue];
        NSDictionary *entry = result[@"entry"];
        NSString *text = entry[@"text"];
        NSNumber *timestamp = entry[@"timestamp"];

        NSString *timeStr = clippy_format_timestamp(timestamp);
        NSString *preview = clippy_preview_text(text);

        printf("  %2ld. [%s] %s\n", (long)index, [timeStr UTF8String], [preview UTF8String]);
    }

    printf("\nUse 'clippy get <N>' to copy, 'clippy pin <N>' to save permanently.\n");
    return 0;
}

// ============================================================================
// Pin Commands
// ============================================================================

int cmdPin(int historyIndex, NSString *label) {
    NSArray *history = clippy_read_json_array(clippy_history_path());

    if ([history count] == 0) {
        fprintf(stderr, "Error: No clipboard history.\n");
        return 1;
    }

    if (historyIndex < 1 || historyIndex > (int)[history count]) {
        fprintf(stderr, "Error: Invalid history index %d. Valid range: 1-%lu\n",
                historyIndex, (unsigned long)[history count]);
        return 1;
    }

    NSDictionary *historyEntry = history[historyIndex - 1];
    NSString *text = historyEntry[@"text"];

    NSMutableArray *pins = clippy_read_json_array(clippy_pins_path());

    // Check pin limit
    if ((int)[pins count] >= clippy_config.maxPins) {
        fprintf(stderr, "Error: Pin limit reached (%d). Unpin some items first.\n",
                clippy_config.maxPins);
        return 1;
    }

    // Check for duplicate
    for (NSDictionary *pin in pins) {
        if ([pin[@"text"] isEqualToString:text]) {
            fprintf(stderr, "Error: This item is already pinned.\n");
            return 1;
        }
    }

    // Create pin entry
    NSMutableDictionary *pinEntry = [NSMutableDictionary dictionary];
    pinEntry[@"text"] = text;
    pinEntry[@"timestamp"] = @([[NSDate date] timeIntervalSince1970]);
    if (label && [label length] > 0) {
        pinEntry[@"label"] = label;
    }

    [pins addObject:pinEntry];

    if (clippy_write_json_array(pins, clippy_pins_path())) {
        NSString *preview = clippy_preview_text(text);
        if (label && [label length] > 0) {
            printf("Pinned as #%lu [%s]: %s\n",
                   (unsigned long)[pins count], [label UTF8String], [preview UTF8String]);
        } else {
            printf("Pinned as #%lu: %s\n",
                   (unsigned long)[pins count], [preview UTF8String]);
        }
        return 0;
    }

    fprintf(stderr, "Error: Failed to save pin.\n");
    return 1;
}

int cmdPins(void) {
    NSArray *pins = clippy_read_json_array(clippy_pins_path());

    if ([pins count] == 0) {
        printf("No pinned items.\n");
        printf("Use 'clippy pin <N>' to pin an item from history.\n");
        return 0;
    }

    printf("Pinned Items (%lu/%d):\n\n", (unsigned long)[pins count], clippy_config.maxPins);

    for (NSUInteger i = 0; i < [pins count]; i++) {
        NSDictionary *pin = pins[i];
        NSString *text = pin[@"text"];
        NSString *label = pin[@"label"];
        NSNumber *timestamp = pin[@"timestamp"];

        NSString *timeStr = clippy_format_timestamp(timestamp);
        NSString *preview = clippy_preview_text(text);

        if (label && [label length] > 0) {
            printf("  %2lu. [%s] {%s} %s\n",
                   (unsigned long)(i + 1), [timeStr UTF8String],
                   [label UTF8String], [preview UTF8String]);
        } else {
            printf("  %2lu. [%s] %s\n",
                   (unsigned long)(i + 1), [timeStr UTF8String], [preview UTF8String]);
        }
    }

    printf("\nUse 'clippy paste <N>' to copy a pinned item to clipboard.\n");
    return 0;
}

int cmdPaste(int index) {
    NSArray *pins = clippy_read_json_array(clippy_pins_path());

    if ([pins count] == 0) {
        fprintf(stderr, "Error: No pinned items.\n");
        return 1;
    }

    if (index < 1 || index > (int)[pins count]) {
        fprintf(stderr, "Error: Invalid pin index %d. Valid range: 1-%lu\n",
                index, (unsigned long)[pins count]);
        return 1;
    }

    NSDictionary *pin = pins[index - 1];
    NSString *text = pin[@"text"];
    NSString *label = pin[@"label"];

    copyTextToClipboard(text);

    if (label && [label length] > 0) {
        printf("Copied pin #%d [%s]: %s\n",
               index, [label UTF8String], [clippy_preview_text(text) UTF8String]);
    } else {
        printf("Copied pin #%d: %s\n", index, [clippy_preview_text(text) UTF8String]);
    }
    return 0;
}

int cmdUnpin(int index) {
    NSMutableArray *pins = clippy_read_json_array(clippy_pins_path());

    if ([pins count] == 0) {
        fprintf(stderr, "Error: No pinned items.\n");
        return 1;
    }

    if (index < 1 || index > (int)[pins count]) {
        fprintf(stderr, "Error: Invalid pin index %d. Valid range: 1-%lu\n",
                index, (unsigned long)[pins count]);
        return 1;
    }

    NSDictionary *pin = pins[index - 1];
    NSString *text = pin[@"text"];
    NSString *label = pin[@"label"];

    [pins removeObjectAtIndex:index - 1];

    if (clippy_write_json_array(pins, clippy_pins_path())) {
        if (label && [label length] > 0) {
            printf("Unpinned #%d [%s]: %s\n",
                   index, [label UTF8String], [clippy_preview_text(text) UTF8String]);
        } else {
            printf("Unpinned #%d: %s\n", index, [clippy_preview_text(text) UTF8String]);
        }
        return 0;
    }

    fprintf(stderr, "Error: Failed to update pins.\n");
    return 1;
}

// ============================================================================
// Config Command
// ============================================================================

int cmdConfig(void) {
    printf("Clippy Configuration:\n\n");
    printf("  poll_interval_ms   = %d\n", clippy_config.pollIntervalMs);
    printf("  max_history_items  = %d\n", clippy_config.maxHistoryItems);
    printf("  max_pins           = %d\n", clippy_config.maxPins);
    printf("  max_entry_length   = %d\n", clippy_config.maxEntryLength);
    printf("  max_age_days       = %d\n", clippy_config.maxAgeDays);
    printf("  cleanup_interval   = %d sec\n", clippy_config.cleanupIntervalSec);
    printf("\nConfig file: %s\n", [clippy_config_path() UTF8String]);

    NSFileManager *fm = [NSFileManager defaultManager];
    if ([fm fileExistsAtPath:clippy_config_path()]) {
        printf("Status: Custom config loaded\n");
    } else {
        printf("Status: Using defaults (no config file)\n");
    }
    return 0;
}

// ============================================================================
// Main
// ============================================================================

int main(int argc, const char *argv[]) {
    @autoreleasepool {
        // Load configuration
        clippy_load_config();

        if (argc < 2) {
            printUsage();
            return 0;
        }

        NSString *command = [NSString stringWithUTF8String:argv[1]];

        // Help
        if ([command isEqualToString:@"--help"] || [command isEqualToString:@"-h"]) {
            printUsage();
            return 0;
        }

        // ---- History Commands ----

        if ([command isEqualToString:@"list"] || [command isEqualToString:@"ls"]) {
            int count = 10;
            if (argc >= 3) {
                count = atoi(argv[2]);
                if (count <= 0) count = 10;
            }
            return cmdList(count);
        }

        if ([command isEqualToString:@"get"]) {
            if (argc < 3) {
                fprintf(stderr, "Error: 'get' requires an index.\n");
                fprintf(stderr, "Usage: clippy get <N>\n");
                return 1;
            }
            return cmdGet(atoi(argv[2]));
        }

        if ([command isEqualToString:@"raw"]) {
            if (argc < 3) {
                fprintf(stderr, "Error: 'raw' requires an index.\n");
                return 1;
            }
            return cmdRaw(atoi(argv[2]));
        }

        if ([command isEqualToString:@"clear"]) {
            return cmdClear();
        }

        if ([command isEqualToString:@"search"]) {
            if (argc < 3) {
                fprintf(stderr, "Error: 'search' requires a query.\n");
                return 1;
            }
            return cmdSearch([NSString stringWithUTF8String:argv[2]]);
        }

        // ---- Pin Commands ----

        if ([command isEqualToString:@"pin"]) {
            if (argc < 3) {
                fprintf(stderr, "Error: 'pin' requires a history index.\n");
                fprintf(stderr, "Usage: clippy pin <N> [label]  or  clippy pin <label> <N>\n");
                return 1;
            }

            // Smart argument parsing: detect if first arg is number or label
            NSString *arg1 = [NSString stringWithUTF8String:argv[2]];
            int index = [arg1 intValue];
            NSString *label = nil;

            if (index > 0) {
                // First arg is index: clippy pin 3 "label"
                if (argc >= 4) {
                    label = [NSString stringWithUTF8String:argv[3]];
                }
            } else if (argc >= 4) {
                // First arg is label: clippy pin "label" 3
                label = arg1;
                index = atoi(argv[3]);
            } else {
                fprintf(stderr, "Error: Could not parse arguments.\n");
                fprintf(stderr, "Usage: clippy pin <N> [label]  or  clippy pin <label> <N>\n");
                return 1;
            }

            return cmdPin(index, label);
        }

        if ([command isEqualToString:@"pins"]) {
            return cmdPins();
        }

        if ([command isEqualToString:@"paste"]) {
            if (argc < 3) {
                fprintf(stderr, "Error: 'paste' requires a pin index.\n");
                return 1;
            }
            return cmdPaste(atoi(argv[2]));
        }

        if ([command isEqualToString:@"unpin"]) {
            if (argc < 3) {
                fprintf(stderr, "Error: 'unpin' requires a pin index.\n");
                return 1;
            }
            return cmdUnpin(atoi(argv[2]));
        }

        // ---- Config Command ----

        if ([command isEqualToString:@"config"]) {
            return cmdConfig();
        }

        // Unknown command
        fprintf(stderr, "Unknown command: %s\n", [command UTF8String]);
        fprintf(stderr, "Run 'clippy --help' for usage.\n");
        return 1;
    }
}
