/**
 * clipd - Clipboard History Daemon
 *
 * Monitors the macOS clipboard and saves history to ~/.clipboard_history
 * Uses only Apple's native frameworks - zero external dependencies.
 *
 * Build: clang -framework AppKit -framework Foundation -Iinclude -o clipd clipd.m
 */

#import <AppKit/AppKit.h>
#import <Foundation/Foundation.h>
#include <signal.h>
#include "clippy_common.h"

static volatile sig_atomic_t running = 1;

void signalHandler(int sig) {
    (void)sig;
    running = 0;
}

// ============================================================================
// History Management
// ============================================================================

void addTextToHistory(NSString *text) {
    if (!text || [text length] == 0) {
        return;
    }

    // Truncate very long entries
    if ((int)[text length] > clippy_config.maxEntryLength) {
        text = [[text substringToIndex:clippy_config.maxEntryLength]
                stringByAppendingString:@"... [truncated]"];
    }

    NSMutableArray *history = clippy_read_json_array(clippy_history_path());

    // Skip if same as most recent entry
    if ([history count] > 0) {
        NSDictionary *lastEntry = [history firstObject];
        if ([lastEntry[@"type"] isEqualToString:@"text"]) {
            NSString *lastText = lastEntry[@"text"];
            if ([lastText isEqualToString:text]) {
                return;
            }
        }
    }

    // Create new entry with timestamp
    NSDictionary *entry = @{
        @"text": text,
        @"timestamp": @([[NSDate date] timeIntervalSince1970]),
        @"type": @"text"
    };

    // Insert at beginning (most recent first)
    [history insertObject:entry atIndex:0];

    // Trim to max size (delete old image files if needed)
    while ((int)[history count] > clippy_config.maxHistoryItems) {
        NSDictionary *oldEntry = [history lastObject];
        if ([oldEntry[@"type"] isEqualToString:@"image"]) {
            clippy_delete_image(oldEntry[@"path"]);
        }
        [history removeLastObject];
    }

    clippy_write_json_array(history, clippy_history_path());
}

void addImageToHistory(NSData *imageData) {
    if (!imageData || [imageData length] == 0) {
        return;
    }

    // Save image to disk
    NSString *imagePath = clippy_save_image(imageData);
    if (!imagePath) {
        return;
    }

    NSMutableArray *history = clippy_read_json_array(clippy_history_path());

    // Create image entry
    NSDictionary *entry = @{
        @"type": @"image",
        @"path": imagePath,
        @"text": [NSString stringWithFormat:@"[Image: %lu bytes]", (unsigned long)[imageData length]],
        @"timestamp": @([[NSDate date] timeIntervalSince1970])
    };

    // Insert at beginning
    [history insertObject:entry atIndex:0];

    // Trim to max size
    while ((int)[history count] > clippy_config.maxHistoryItems) {
        NSDictionary *oldEntry = [history lastObject];
        if ([oldEntry[@"type"] isEqualToString:@"image"]) {
            clippy_delete_image(oldEntry[@"path"]);
        }
        [history removeLastObject];
    }

    clippy_write_json_array(history, clippy_history_path());
}

// ============================================================================
// Cleanup
// ============================================================================

void runCleanup(void) {
    NSUInteger historyRemoved = clippy_cleanup_old_entries(clippy_history_path());
    NSUInteger pinsRemoved = clippy_cleanup_old_entries(clippy_pins_path());

    if (historyRemoved > 0 || pinsRemoved > 0) {
        NSLog(@"clipd: Cleanup - removed %lu history, %lu pins (older than %d days)",
              (unsigned long)historyRemoved, (unsigned long)pinsRemoved,
              clippy_config.maxAgeDays);
    }
}

// ============================================================================
// Main
// ============================================================================

int main(int argc, const char *argv[]) {
    @autoreleasepool {
        // Check for --help flag
        for (int i = 1; i < argc; i++) {
            if (strcmp(argv[i], "--help") == 0 || strcmp(argv[i], "-h") == 0) {
                printf("clipd - Clipboard History Daemon\n\n");
                printf("Usage: clipd [OPTIONS]\n\n");
                printf("Options:\n");
                printf("  -h, --help     Show this help message\n");
                printf("  --foreground   Run in foreground (default)\n\n");
                printf("Files:\n");
                printf("  ~/.clipboard_history   History storage\n");
                printf("  ~/.clipboard_pins      Pinned items\n");
                printf("  ~/.clippy.conf         Configuration (optional)\n\n");
                printf("Config file format (key=value):\n");
                printf("  poll_interval_ms = %d\n", CLIPPY_DEFAULT_POLL_INTERVAL_MS);
                printf("  max_history_items = %d\n", CLIPPY_DEFAULT_MAX_HISTORY_ITEMS);
                printf("  max_pins = %d\n", CLIPPY_DEFAULT_MAX_PINS);
                printf("  max_entry_length = %d\n", CLIPPY_DEFAULT_MAX_ENTRY_LENGTH);
                printf("  max_age_days = %d\n", CLIPPY_DEFAULT_MAX_AGE_DAYS);
                return 0;
            }
        }

        // Load configuration
        clippy_load_config();

        // Setup signal handlers
        signal(SIGINT, signalHandler);
        signal(SIGTERM, signalHandler);

        NSLog(@"clipd: Starting clipboard monitoring daemon");
        NSLog(@"clipd: Config - poll=%dms, max_history=%d, max_age=%d days",
              clippy_config.pollIntervalMs,
              clippy_config.maxHistoryItems,
              clippy_config.maxAgeDays);

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

                    // Check for text first (most common)
                    NSString *text = [pasteboard stringForType:NSPasteboardTypeString];
                    if (text) {
                        text = [text stringByTrimmingCharactersInSet:
                                [NSCharacterSet whitespaceAndNewlineCharacterSet]];

                        if ([text length] > 0) {
                            addTextToHistory(text);
                        }
                    }
                    // Check for image if no text
                    else {
                        NSData *pngData = [pasteboard dataForType:NSPasteboardTypePNG];
                        if (pngData) {
                            addImageToHistory(pngData);
                        } else {
                            // Try TIFF format (macOS screenshots)
                            NSData *tiffData = [pasteboard dataForType:NSPasteboardTypeTIFF];
                            if (tiffData) {
                                // Convert TIFF to PNG for consistent storage
                                NSBitmapImageRep *imageRep = [NSBitmapImageRep imageRepWithData:tiffData];
                                if (imageRep) {
                                    NSData *pngConverted = [imageRep representationUsingType:NSBitmapImageFileTypePNG
                                                                                  properties:@{}];
                                    if (pngConverted) {
                                        addImageToHistory(pngConverted);
                                    }
                                }
                            }
                        }
                    }
                }

                // Periodic cleanup
                NSTimeInterval now = [[NSDate date] timeIntervalSince1970];
                if (now - lastCleanup >= clippy_config.cleanupIntervalSec) {
                    runCleanup();
                    lastCleanup = now;
                }

                // Sleep for poll interval
                [NSThread sleepForTimeInterval:(clippy_config.pollIntervalMs / 1000.0)];
            }
        }

        NSLog(@"clipd: Shutting down gracefully");
    }
    return 0;
}
