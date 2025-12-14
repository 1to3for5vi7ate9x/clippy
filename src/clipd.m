/**
 * clipd - Clipboard History Daemon
 *
 * Monitors the macOS clipboard and saves history to ~/.clipboard_history
 * Uses only Apple's native frameworks - zero external dependencies.
 *
 * Build: clang -framework AppKit -framework Foundation -o clipd clipd.m
 */

#import <AppKit/AppKit.h>
#import <Foundation/Foundation.h>
#include <signal.h>
#include <sys/stat.h>

// Configuration
#define POLL_INTERVAL_MS 500
#define MAX_HISTORY_ITEMS 50
#define HISTORY_FILE_NAME ".clipboard_history"
#define MAX_ENTRY_LENGTH 10000  // Truncate very long entries

static volatile sig_atomic_t running = 1;
static NSString *historyFilePath = nil;

void signalHandler(int sig) {
    (void)sig;
    running = 0;
}

NSString *getHistoryFilePath(void) {
    if (!historyFilePath) {
        NSString *home = NSHomeDirectory();
        historyFilePath = [home stringByAppendingPathComponent:@HISTORY_FILE_NAME];
    }
    return historyFilePath;
}

// Read existing history entries from file
NSMutableArray<NSDictionary *> *readHistory(void) {
    NSString *path = getHistoryFilePath();
    NSMutableArray *history = [NSMutableArray array];

    NSError *error = nil;
    NSString *content = [NSString stringWithContentsOfFile:path
                                                  encoding:NSUTF8StringEncoding
                                                     error:&error];
    if (error || !content) {
        return history;
    }

    // Parse JSON array
    NSData *data = [content dataUsingEncoding:NSUTF8StringEncoding];
    NSArray *parsed = [NSJSONSerialization JSONObjectWithData:data
                                                      options:0
                                                        error:&error];
    if (!error && [parsed isKindOfClass:[NSArray class]]) {
        [history addObjectsFromArray:parsed];
    }

    return history;
}

// Write history to file with restrictive permissions
BOOL writeHistory(NSArray<NSDictionary *> *history) {
    NSString *path = getHistoryFilePath();

    NSError *error = nil;
    NSData *data = [NSJSONSerialization dataWithJSONObject:history
                                                   options:NSJSONWritingPrettyPrinted
                                                     error:&error];
    if (error) {
        NSLog(@"clipd: Failed to serialize history: %@", error);
        return NO;
    }

    BOOL success = [data writeToFile:path options:NSDataWritingAtomic error:&error];
    if (!success) {
        NSLog(@"clipd: Failed to write history: %@", error);
        return NO;
    }

    // Set file permissions to 600 (owner read/write only)
    chmod([path fileSystemRepresentation], S_IRUSR | S_IWUSR);

    return YES;
}

// Add new entry to history
void addToHistory(NSString *text) {
    if (!text || [text length] == 0) {
        return;
    }

    // Truncate very long entries
    if ([text length] > MAX_ENTRY_LENGTH) {
        text = [[text substringToIndex:MAX_ENTRY_LENGTH] stringByAppendingString:@"... [truncated]"];
    }

    NSMutableArray *history = readHistory();

    // Skip if same as most recent entry
    if ([history count] > 0) {
        NSDictionary *lastEntry = [history firstObject];
        NSString *lastText = lastEntry[@"text"];
        if ([lastText isEqualToString:text]) {
            return;
        }
    }

    // Create new entry with timestamp
    NSDictionary *entry = @{
        @"text": text,
        @"timestamp": @([[NSDate date] timeIntervalSince1970])
    };

    // Insert at beginning (most recent first)
    [history insertObject:entry atIndex:0];

    // Trim to max size
    while ([history count] > MAX_HISTORY_ITEMS) {
        [history removeLastObject];
    }

    writeHistory(history);
}

int main(int argc, const char *argv[]) {
    @autoreleasepool {
        // Check for --help flag
        for (int i = 1; i < argc; i++) {
            if (strcmp(argv[i], "--help") == 0 || strcmp(argv[i], "-h") == 0) {
                printf("clipd - Clipboard History Daemon\n\n");
                printf("Usage: clipd [OPTIONS]\n\n");
                printf("Options:\n");
                printf("  -h, --help     Show this help message\n");
                printf("  --foreground   Run in foreground (default, for debugging)\n\n");
                printf("The daemon monitors the clipboard and saves history to:\n");
                printf("  %s\n\n", [[getHistoryFilePath() stringByExpandingTildeInPath] UTF8String]);
                printf("History is limited to %d items.\n", MAX_HISTORY_ITEMS);
                printf("File permissions are set to 600 (owner only).\n");
                return 0;
            }
        }

        // Setup signal handlers for graceful shutdown
        signal(SIGINT, signalHandler);
        signal(SIGTERM, signalHandler);

        NSLog(@"clipd: Starting clipboard monitoring daemon");
        NSLog(@"clipd: History file: %@", getHistoryFilePath());

        NSPasteboard *pasteboard = [NSPasteboard generalPasteboard];
        NSInteger lastChangeCount = [pasteboard changeCount];

        // Main polling loop
        while (running) {
            @autoreleasepool {
                NSInteger currentChangeCount = [pasteboard changeCount];

                if (currentChangeCount != lastChangeCount) {
                    lastChangeCount = currentChangeCount;

                    // Get string content from clipboard
                    NSString *text = [pasteboard stringForType:NSPasteboardTypeString];
                    if (text) {
                        // Trim whitespace
                        text = [text stringByTrimmingCharactersInSet:
                                [NSCharacterSet whitespaceAndNewlineCharacterSet]];

                        if ([text length] > 0) {
                            addToHistory(text);
                        }
                    }
                }

                // Sleep for poll interval
                [NSThread sleepForTimeInterval:(POLL_INTERVAL_MS / 1000.0)];
            }
        }

        NSLog(@"clipd: Shutting down gracefully");
    }
    return 0;
}
