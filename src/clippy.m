/**
 * clippy - Clipboard History CLI
 *
 * Access clipboard history saved by clipd daemon.
 *
 * History Commands:
 *   clippy list [N]      - Show last N items (default: 10)
 *   clippy get <N>       - Get Nth item and copy to clipboard
 *   clippy clear         - Clear all history
 *   clippy search <Q>    - Search history for text
 *
 * Pin Commands:
 *   clippy pin <N> [label]  - Pin item N from history (optional label)
 *   clippy pins             - List all pinned items
 *   clippy unpin <N>        - Remove pinned item N
 *   clippy paste <N>        - Copy pinned item N to clipboard
 *
 * Build: clang -framework AppKit -framework Foundation -o clippy clippy.m
 */

#import <AppKit/AppKit.h>
#import <Foundation/Foundation.h>
#include <sys/stat.h>

#define HISTORY_FILE_NAME ".clipboard_history"
#define PINS_FILE_NAME ".clipboard_pins"
#define PREVIEW_LENGTH 60

// ============================================================================
// File Path Helpers
// ============================================================================

NSString *getHistoryFilePath(void) {
    NSString *home = NSHomeDirectory();
    return [home stringByAppendingPathComponent:@HISTORY_FILE_NAME];
}

NSString *getPinsFilePath(void) {
    NSString *home = NSHomeDirectory();
    return [home stringByAppendingPathComponent:@PINS_FILE_NAME];
}

// ============================================================================
// History Functions
// ============================================================================

NSArray<NSDictionary *> *readHistory(void) {
    NSString *path = getHistoryFilePath();

    NSError *error = nil;
    NSString *content = [NSString stringWithContentsOfFile:path
                                                  encoding:NSUTF8StringEncoding
                                                     error:&error];
    if (error || !content) {
        return @[];
    }

    NSData *data = [content dataUsingEncoding:NSUTF8StringEncoding];
    NSArray *parsed = [NSJSONSerialization JSONObjectWithData:data
                                                      options:0
                                                        error:&error];
    if (error || ![parsed isKindOfClass:[NSArray class]]) {
        return @[];
    }

    return parsed;
}

BOOL writeHistory(NSArray *history) {
    NSString *path = getHistoryFilePath();

    NSError *error = nil;
    NSData *data = [NSJSONSerialization dataWithJSONObject:history
                                                   options:NSJSONWritingPrettyPrinted
                                                     error:&error];
    if (error) {
        return NO;
    }

    return [data writeToFile:path options:NSDataWritingAtomic error:&error];
}

// ============================================================================
// Pins Functions
// ============================================================================

NSMutableArray<NSDictionary *> *readPins(void) {
    NSString *path = getPinsFilePath();

    NSError *error = nil;
    NSString *content = [NSString stringWithContentsOfFile:path
                                                  encoding:NSUTF8StringEncoding
                                                     error:&error];
    if (error || !content) {
        return [NSMutableArray array];
    }

    NSData *data = [content dataUsingEncoding:NSUTF8StringEncoding];
    NSArray *parsed = [NSJSONSerialization JSONObjectWithData:data
                                                      options:0
                                                        error:&error];
    if (error || ![parsed isKindOfClass:[NSArray class]]) {
        return [NSMutableArray array];
    }

    return [NSMutableArray arrayWithArray:parsed];
}

BOOL writePins(NSArray *pins) {
    NSString *path = getPinsFilePath();

    NSError *error = nil;
    NSData *data = [NSJSONSerialization dataWithJSONObject:pins
                                                   options:NSJSONWritingPrettyPrinted
                                                     error:&error];
    if (error) {
        return NO;
    }

    BOOL success = [data writeToFile:path options:NSDataWritingAtomic error:&error];
    if (success) {
        // Set restrictive permissions (owner read/write only)
        chmod([path fileSystemRepresentation], S_IRUSR | S_IWUSR);
    }
    return success;
}

// ============================================================================
// Display Helpers
// ============================================================================

NSString *formatTimestamp(NSNumber *timestamp) {
    NSDate *date = [NSDate dateWithTimeIntervalSince1970:[timestamp doubleValue]];
    NSDateFormatter *formatter = [[NSDateFormatter alloc] init];

    if ([[NSCalendar currentCalendar] isDateInToday:date]) {
        [formatter setDateFormat:@"HH:mm:ss"];
        return [NSString stringWithFormat:@"Today %@", [formatter stringFromDate:date]];
    }

    if ([[NSCalendar currentCalendar] isDateInYesterday:date]) {
        [formatter setDateFormat:@"HH:mm"];
        return [NSString stringWithFormat:@"Yesterday %@", [formatter stringFromDate:date]];
    }

    [formatter setDateFormat:@"MMM d HH:mm"];
    return [formatter stringFromDate:date];
}

NSString *previewText(NSString *text) {
    text = [text stringByReplacingOccurrencesOfString:@"\n" withString:@"↵"];
    text = [text stringByReplacingOccurrencesOfString:@"\r" withString:@""];

    if ([text length] <= PREVIEW_LENGTH) {
        return text;
    }

    return [[text substringToIndex:PREVIEW_LENGTH] stringByAppendingString:@"..."];
}

void copyToClipboard(NSString *text) {
    NSPasteboard *pasteboard = [NSPasteboard generalPasteboard];
    [pasteboard clearContents];
    [pasteboard setString:text forType:NSPasteboardTypeString];
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
    NSArray *history = readHistory();

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

        NSString *timeStr = formatTimestamp(timestamp);
        NSString *preview = previewText(text);

        printf("  %2ld. [%s] %s\n",
               (long)(i + 1),
               [timeStr UTF8String],
               [preview UTF8String]);
    }

    printf("\nUse 'clippy get <N>' to copy, 'clippy pin <N>' to save permanently.\n");
    return 0;
}

int cmdGet(int index) {
    NSArray *history = readHistory();

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
    NSString *text = entry[@"text"];

    copyToClipboard(text);
    printf("Copied to clipboard: %s\n", [previewText(text) UTF8String]);
    return 0;
}

int cmdRaw(int index) {
    NSArray *history = readHistory();

    if (index < 1 || index > (int)[history count]) {
        return 1;
    }

    NSDictionary *entry = history[index - 1];
    NSString *text = entry[@"text"];

    printf("%s", [text UTF8String]);
    return 0;
}

int cmdClear(void) {
    NSString *path = getHistoryFilePath();
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
    NSArray *history = readHistory();

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

        NSString *timeStr = formatTimestamp(timestamp);
        NSString *preview = previewText(text);

        printf("  %2ld. [%s] %s\n",
               (long)index,
               [timeStr UTF8String],
               [preview UTF8String]);
    }

    printf("\nUse 'clippy get <N>' to copy, 'clippy pin <N>' to save permanently.\n");
    return 0;
}

// ============================================================================
// Pin Commands
// ============================================================================

int cmdPin(int historyIndex, NSString *label) {
    NSArray *history = readHistory();

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

    NSMutableArray *pins = readPins();

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

    if (writePins(pins)) {
        NSString *preview = previewText(text);
        if (label && [label length] > 0) {
            printf("Pinned as #%lu [%s]: %s\n",
                   (unsigned long)[pins count],
                   [label UTF8String],
                   [preview UTF8String]);
        } else {
            printf("Pinned as #%lu: %s\n",
                   (unsigned long)[pins count],
                   [preview UTF8String]);
        }
        return 0;
    }

    fprintf(stderr, "Error: Failed to save pin.\n");
    return 1;
}

int cmdPins(void) {
    NSArray *pins = readPins();

    if ([pins count] == 0) {
        printf("No pinned items.\n");
        printf("Use 'clippy pin <N>' to pin an item from history.\n");
        return 0;
    }

    printf("Pinned Items (%lu):\n\n", (unsigned long)[pins count]);

    for (NSUInteger i = 0; i < [pins count]; i++) {
        NSDictionary *pin = pins[i];
        NSString *text = pin[@"text"];
        NSString *label = pin[@"label"];
        NSNumber *timestamp = pin[@"timestamp"];

        NSString *timeStr = formatTimestamp(timestamp);
        NSString *preview = previewText(text);

        if (label && [label length] > 0) {
            printf("  %2lu. [%s] {%s} %s\n",
                   (unsigned long)(i + 1),
                   [timeStr UTF8String],
                   [label UTF8String],
                   [preview UTF8String]);
        } else {
            printf("  %2lu. [%s] %s\n",
                   (unsigned long)(i + 1),
                   [timeStr UTF8String],
                   [preview UTF8String]);
        }
    }

    printf("\nUse 'clippy paste <N>' to copy a pinned item to clipboard.\n");
    return 0;
}

int cmdPaste(int index) {
    NSArray *pins = readPins();

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

    copyToClipboard(text);

    if (label && [label length] > 0) {
        printf("Copied pin #%d [%s] to clipboard: %s\n",
               index, [label UTF8String], [previewText(text) UTF8String]);
    } else {
        printf("Copied pin #%d to clipboard: %s\n",
               index, [previewText(text) UTF8String]);
    }
    return 0;
}

int cmdUnpin(int index) {
    NSMutableArray *pins = readPins();

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

    if (writePins(pins)) {
        if (label && [label length] > 0) {
            printf("Unpinned #%d [%s]: %s\n",
                   index, [label UTF8String], [previewText(text) UTF8String]);
        } else {
            printf("Unpinned #%d: %s\n", index, [previewText(text) UTF8String]);
        }
        return 0;
    }

    fprintf(stderr, "Error: Failed to update pins.\n");
    return 1;
}

// ============================================================================
// Main
// ============================================================================

int main(int argc, const char *argv[]) {
    @autoreleasepool {
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

        // List
        if ([command isEqualToString:@"list"] || [command isEqualToString:@"ls"]) {
            int count = 10;
            if (argc >= 3) {
                count = atoi(argv[2]);
                if (count <= 0) count = 10;
            }
            return cmdList(count);
        }

        // Get
        if ([command isEqualToString:@"get"]) {
            if (argc < 3) {
                fprintf(stderr, "Error: 'get' requires an index.\n");
                fprintf(stderr, "Usage: clippy get <N>\n");
                return 1;
            }
            int index = atoi(argv[2]);
            return cmdGet(index);
        }

        // Raw
        if ([command isEqualToString:@"raw"]) {
            if (argc < 3) {
                fprintf(stderr, "Error: 'raw' requires an index.\n");
                return 1;
            }
            int index = atoi(argv[2]);
            return cmdRaw(index);
        }

        // Clear
        if ([command isEqualToString:@"clear"]) {
            return cmdClear();
        }

        // Search
        if ([command isEqualToString:@"search"]) {
            if (argc < 3) {
                fprintf(stderr, "Error: 'search' requires a query.\n");
                fprintf(stderr, "Usage: clippy search <query>\n");
                return 1;
            }
            NSString *query = [NSString stringWithUTF8String:argv[2]];
            return cmdSearch(query);
        }

        // ---- Pin Commands ----

        // Pin
        if ([command isEqualToString:@"pin"]) {
            if (argc < 3) {
                fprintf(stderr, "Error: 'pin' requires a history index.\n");
                fprintf(stderr, "Usage: clippy pin <N> [label]\n");
                return 1;
            }
            int index = atoi(argv[2]);
            NSString *label = nil;
            if (argc >= 4) {
                label = [NSString stringWithUTF8String:argv[3]];
            }
            return cmdPin(index, label);
        }

        // Pins (list)
        if ([command isEqualToString:@"pins"]) {
            return cmdPins();
        }

        // Paste (from pins)
        if ([command isEqualToString:@"paste"]) {
            if (argc < 3) {
                fprintf(stderr, "Error: 'paste' requires a pin index.\n");
                fprintf(stderr, "Usage: clippy paste <N>\n");
                return 1;
            }
            int index = atoi(argv[2]);
            return cmdPaste(index);
        }

        // Unpin
        if ([command isEqualToString:@"unpin"]) {
            if (argc < 3) {
                fprintf(stderr, "Error: 'unpin' requires a pin index.\n");
                fprintf(stderr, "Usage: clippy unpin <N>\n");
                return 1;
            }
            int index = atoi(argv[2]);
            return cmdUnpin(index);
        }

        // Unknown command
        fprintf(stderr, "Unknown command: %s\n", [command UTF8String]);
        fprintf(stderr, "Run 'clippy --help' for usage.\n");
        return 1;
    }
}
