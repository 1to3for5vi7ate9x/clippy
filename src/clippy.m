/**
 * clippy - Clipboard History CLI
 *
 * Access clipboard history saved by clipd daemon.
 *
 * Commands:
 *   clippy list [N]    - Show last N items (default: 10)
 *   clippy get <N>     - Get Nth item and copy to clipboard
 *   clippy clear       - Clear all history
 *   clippy search <Q>  - Search history for text
 *
 * Build: clang -framework AppKit -framework Foundation -o clippy clip.m
 */

#import <AppKit/AppKit.h>
#import <Foundation/Foundation.h>

#define HISTORY_FILE_NAME ".clipboard_history"
#define PREVIEW_LENGTH 60

NSString *getHistoryFilePath(void) {
    NSString *home = NSHomeDirectory();
    return [home stringByAppendingPathComponent:@HISTORY_FILE_NAME];
}

// Read history from file
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

// Write history to file
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

// Format timestamp for display
NSString *formatTimestamp(NSNumber *timestamp) {
    NSDate *date = [NSDate dateWithTimeIntervalSince1970:[timestamp doubleValue]];
    NSDateFormatter *formatter = [[NSDateFormatter alloc] init];

    // Check if it's today
    if ([[NSCalendar currentCalendar] isDateInToday:date]) {
        [formatter setDateFormat:@"HH:mm:ss"];
        return [NSString stringWithFormat:@"Today %@", [formatter stringFromDate:date]];
    }

    // Check if it's yesterday
    if ([[NSCalendar currentCalendar] isDateInYesterday:date]) {
        [formatter setDateFormat:@"HH:mm"];
        return [NSString stringWithFormat:@"Yesterday %@", [formatter stringFromDate:date]];
    }

    // Otherwise show full date
    [formatter setDateFormat:@"MMM d HH:mm"];
    return [formatter stringFromDate:date];
}

// Truncate text for preview
NSString *previewText(NSString *text) {
    // Replace newlines with visible marker
    text = [text stringByReplacingOccurrencesOfString:@"\n" withString:@"↵"];
    text = [text stringByReplacingOccurrencesOfString:@"\r" withString:@""];

    if ([text length] <= PREVIEW_LENGTH) {
        return text;
    }

    return [[text substringToIndex:PREVIEW_LENGTH] stringByAppendingString:@"..."];
}

// Copy text to clipboard
void copyToClipboard(NSString *text) {
    NSPasteboard *pasteboard = [NSPasteboard generalPasteboard];
    [pasteboard clearContents];
    [pasteboard setString:text forType:NSPasteboardTypeString];
}

void printUsage(void) {
    printf("clippy - Clipboard History CLI\n\n");
    printf("Usage:\n");
    printf("  clippy list [N]      Show last N history items (default: 10)\n");
    printf("  clippy get <N>       Get item N and copy to clipboard (1 = most recent)\n");
    printf("  clippy clear         Clear all clipboard history\n");
    printf("  clippy search <Q>    Search history for text\n");
    printf("  clippy raw <N>       Print item N without formatting (for scripting)\n\n");
    printf("Examples:\n");
    printf("  clippy list          Show last 10 items\n");
    printf("  clippy list 20       Show last 20 items\n");
    printf("  clippy get 1         Copy most recent item to clipboard\n");
    printf("  clippy get 3         Copy 3rd most recent item\n");
    printf("  clippy search api    Find entries containing 'api'\n");
}

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

    printf("\nUse 'clippy get <N>' to copy an item to clipboard.\n");
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
    printf("Copied item %d to clipboard:\n%s\n", index, [previewText(text) UTF8String]);
    return 0;
}

int cmdRaw(int index) {
    NSArray *history = readHistory();

    if (index < 1 || index > (int)[history count]) {
        return 1;
    }

    NSDictionary *entry = history[index - 1];
    NSString *text = entry[@"text"];

    // Print raw text without newline for scripting
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

    printf("\nUse 'clippy get <N>' to copy an item to clipboard.\n");
    return 0;
}

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

        // List command
        if ([command isEqualToString:@"list"] || [command isEqualToString:@"ls"]) {
            int count = 10;
            if (argc >= 3) {
                count = atoi(argv[2]);
                if (count <= 0) count = 10;
            }
            return cmdList(count);
        }

        // Get command
        if ([command isEqualToString:@"get"]) {
            if (argc < 3) {
                fprintf(stderr, "Error: 'get' requires an index.\n");
                fprintf(stderr, "Usage: clip get <N>\n");
                return 1;
            }
            int index = atoi(argv[2]);
            return cmdGet(index);
        }

        // Raw command (for scripting)
        if ([command isEqualToString:@"raw"]) {
            if (argc < 3) {
                fprintf(stderr, "Error: 'raw' requires an index.\n");
                return 1;
            }
            int index = atoi(argv[2]);
            return cmdRaw(index);
        }

        // Clear command
        if ([command isEqualToString:@"clear"]) {
            return cmdClear();
        }

        // Search command
        if ([command isEqualToString:@"search"]) {
            if (argc < 3) {
                fprintf(stderr, "Error: 'search' requires a query.\n");
                fprintf(stderr, "Usage: clip search <query>\n");
                return 1;
            }
            NSString *query = [NSString stringWithUTF8String:argv[2]];
            return cmdSearch(query);
        }

        // Unknown command
        fprintf(stderr, "Unknown command: %s\n", [command UTF8String]);
        fprintf(stderr, "Run 'clip --help' for usage.\n");
        return 1;
    }
}
