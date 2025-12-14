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
#define PINS_FILE_NAME ".clipboard_pins"
#define MAX_ENTRY_LENGTH 10000  // Truncate very long entries
#define MAX_AGE_DAYS 30         // Auto-delete entries older than this
#define CLEANUP_INTERVAL_SEC 3600  // Run cleanup every hour

static volatile sig_atomic_t running = 1;
static NSString *historyFilePath = nil;
static NSString *pinsFilePath = nil;

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

NSString *getPinsFilePath(void) {
    if (!pinsFilePath) {
        NSString *home = NSHomeDirectory();
        pinsFilePath = [home stringByAppendingPathComponent:@PINS_FILE_NAME];
    }
    return pinsFilePath;
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

// Clean up entries older than MAX_AGE_DAYS
NSUInteger cleanupOldEntries(NSString *filePath) {
    NSError *error = nil;
    NSString *content = [NSString stringWithContentsOfFile:filePath
                                                  encoding:NSUTF8StringEncoding
                                                     error:&error];
    if (error || !content) {
        return 0;
    }

    NSData *data = [content dataUsingEncoding:NSUTF8StringEncoding];
    NSArray *entries = [NSJSONSerialization JSONObjectWithData:data
                                                       options:0
                                                         error:&error];
    if (error || ![entries isKindOfClass:[NSArray class]]) {
        return 0;
    }

    NSTimeInterval maxAge = MAX_AGE_DAYS * 24 * 60 * 60;
    NSTimeInterval now = [[NSDate date] timeIntervalSince1970];
    NSMutableArray *filtered = [NSMutableArray array];
    NSUInteger removed = 0;

    for (NSDictionary *entry in entries) {
        NSNumber *timestamp = entry[@"timestamp"];
        if (timestamp) {
            NSTimeInterval age = now - [timestamp doubleValue];
            if (age <= maxAge) {
                [filtered addObject:entry];
            } else {
                removed++;
            }
        } else {
            // Keep entries without timestamp (shouldn't happen, but safe)
            [filtered addObject:entry];
        }
    }

    if (removed > 0) {
        NSData *jsonData = [NSJSONSerialization dataWithJSONObject:filtered
                                                           options:NSJSONWritingPrettyPrinted
                                                             error:&error];
        if (!error) {
            [jsonData writeToFile:filePath options:NSDataWritingAtomic error:&error];
            chmod([filePath fileSystemRepresentation], S_IRUSR | S_IWUSR);
        }
    }

    return removed;
}

// Run cleanup on both history and pins
void runCleanup(void) {
    NSUInteger historyRemoved = cleanupOldEntries(getHistoryFilePath());
    NSUInteger pinsRemoved = cleanupOldEntries(getPinsFilePath());

    if (historyRemoved > 0 || pinsRemoved > 0) {
        NSLog(@"clipd: Cleanup complete - removed %lu history entries, %lu pins (older than %d days)",
              (unsigned long)historyRemoved, (unsigned long)pinsRemoved, MAX_AGE_DAYS);
    }
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
                printf("Entries older than %d days are auto-deleted.\n", MAX_AGE_DAYS);
                printf("File permissions are set to 600 (owner only).\n");
                return 0;
            }
        }

        // Setup signal handlers for graceful shutdown
        signal(SIGINT, signalHandler);
        signal(SIGTERM, signalHandler);

        NSLog(@"clipd: Starting clipboard monitoring daemon");
        NSLog(@"clipd: History file: %@", getHistoryFilePath());
        NSLog(@"clipd: Auto-cleanup: entries older than %d days", MAX_AGE_DAYS);

        // Run cleanup on startup
        runCleanup();

        NSPasteboard *pasteboard = [NSPasteboard generalPasteboard];
        NSInteger lastChangeCount = [pasteboard changeCount];
        NSTimeInterval lastCleanup = [[NSDate date] timeIntervalSince1970];

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

                // Periodic cleanup check (every hour)
                NSTimeInterval now = [[NSDate date] timeIntervalSince1970];
                if (now - lastCleanup >= CLEANUP_INTERVAL_SEC) {
                    runCleanup();
                    lastCleanup = now;
                }

                // Sleep for poll interval
                [NSThread sleepForTimeInterval:(POLL_INTERVAL_MS / 1000.0)];
            }
        }

        NSLog(@"clipd: Shutting down gracefully");
    }
    return 0;
}
