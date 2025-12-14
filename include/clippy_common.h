/**
 * clippy_common.h - Shared code for clippy clipboard history tool
 *
 * This header contains shared constants, configuration, and utility functions
 * used by both the daemon (clipd) and CLI (clippy).
 */

#ifndef CLIPPY_COMMON_H
#define CLIPPY_COMMON_H

#import <Foundation/Foundation.h>
#include <sys/stat.h>

// ============================================================================
// Configuration Defaults (can be overridden by config file)
// ============================================================================

#define CLIPPY_DEFAULT_POLL_INTERVAL_MS   500
#define CLIPPY_DEFAULT_MAX_HISTORY_ITEMS  50
#define CLIPPY_DEFAULT_MAX_PINS           50
#define CLIPPY_DEFAULT_MAX_ENTRY_LENGTH   10000
#define CLIPPY_DEFAULT_MAX_AGE_DAYS       30
#define CLIPPY_DEFAULT_CLEANUP_INTERVAL   3600  // seconds

// ============================================================================
// File Names
// ============================================================================

#define CLIPPY_HISTORY_FILE   ".clipboard_history"
#define CLIPPY_PINS_FILE      ".clipboard_pins"
#define CLIPPY_CONFIG_FILE    ".clippy.conf"
#define CLIPPY_DATA_DIR       ".clippy_data"
#define CLIPPY_IMAGES_DIR     "images"
#define CLIPPY_BACKUP_SUFFIX  ".backup"

// ============================================================================
// Runtime Configuration
// ============================================================================

typedef struct {
    int pollIntervalMs;
    int maxHistoryItems;
    int maxPins;
    int maxEntryLength;
    int maxAgeDays;
    int cleanupIntervalSec;
} ClippyConfig;

// Global config instance
static ClippyConfig clippy_config = {
    .pollIntervalMs = CLIPPY_DEFAULT_POLL_INTERVAL_MS,
    .maxHistoryItems = CLIPPY_DEFAULT_MAX_HISTORY_ITEMS,
    .maxPins = CLIPPY_DEFAULT_MAX_PINS,
    .maxEntryLength = CLIPPY_DEFAULT_MAX_ENTRY_LENGTH,
    .maxAgeDays = CLIPPY_DEFAULT_MAX_AGE_DAYS,
    .cleanupIntervalSec = CLIPPY_DEFAULT_CLEANUP_INTERVAL
};

// ============================================================================
// File Path Helpers
// ============================================================================

static inline NSString *clippy_get_home_path(NSString *filename) {
    return [NSHomeDirectory() stringByAppendingPathComponent:filename];
}

static inline NSString *clippy_history_path(void) {
    return clippy_get_home_path(@CLIPPY_HISTORY_FILE);
}

static inline NSString *clippy_pins_path(void) {
    return clippy_get_home_path(@CLIPPY_PINS_FILE);
}

static inline NSString *clippy_config_path(void) {
    return clippy_get_home_path(@CLIPPY_CONFIG_FILE);
}

static inline NSString *clippy_data_dir(void) {
    return clippy_get_home_path(@CLIPPY_DATA_DIR);
}

static inline NSString *clippy_images_dir(void) {
    return [clippy_data_dir() stringByAppendingPathComponent:@CLIPPY_IMAGES_DIR];
}

/**
 * Ensure the images directory exists
 */
static inline BOOL clippy_ensure_images_dir(void) {
    NSFileManager *fm = [NSFileManager defaultManager];
    NSString *path = clippy_images_dir();

    if ([fm fileExistsAtPath:path]) {
        return YES;
    }

    NSError *error = nil;
    BOOL success = [fm createDirectoryAtPath:path
                 withIntermediateDirectories:YES
                                  attributes:@{NSFilePosixPermissions: @0700}
                                       error:&error];
    if (!success) {
        NSLog(@"clippy: Failed to create images dir: %@", error);
    }
    return success;
}

/**
 * Generate a unique filename for an image
 */
static inline NSString *clippy_generate_image_filename(void) {
    NSString *uuid = [[NSUUID UUID] UUIDString];
    return [NSString stringWithFormat:@"%@.png", uuid];
}

/**
 * Save image data to the images directory
 * Returns the full path to the saved file, or nil on failure
 */
static inline NSString *clippy_save_image(NSData *imageData) {
    if (!imageData || [imageData length] == 0) {
        return nil;
    }

    if (!clippy_ensure_images_dir()) {
        return nil;
    }

    NSString *filename = clippy_generate_image_filename();
    NSString *path = [clippy_images_dir() stringByAppendingPathComponent:filename];

    NSError *error = nil;
    BOOL success = [imageData writeToFile:path options:NSDataWritingAtomic error:&error];
    if (!success) {
        NSLog(@"clippy: Failed to save image: %@", error);
        return nil;
    }

    // Set restrictive permissions
    chmod([path fileSystemRepresentation], S_IRUSR | S_IWUSR);

    return path;
}

/**
 * Delete an image file
 */
static inline BOOL clippy_delete_image(NSString *path) {
    if (!path || [path length] == 0) {
        return NO;
    }

    NSFileManager *fm = [NSFileManager defaultManager];
    NSError *error = nil;
    return [fm removeItemAtPath:path error:&error];
}

// ============================================================================
// JSON File Operations (with error recovery)
// ============================================================================

/**
 * Read JSON array from file with validation and backup recovery
 * Returns empty mutable array on error
 */
static inline NSMutableArray *clippy_read_json_array(NSString *path) {
    NSFileManager *fm = [NSFileManager defaultManager];
    NSError *error = nil;

    // Try reading main file
    if ([fm fileExistsAtPath:path]) {
        NSString *content = [NSString stringWithContentsOfFile:path
                                                      encoding:NSUTF8StringEncoding
                                                         error:&error];
        if (!error && content && [content length] > 0) {
            NSData *data = [content dataUsingEncoding:NSUTF8StringEncoding];
            id parsed = [NSJSONSerialization JSONObjectWithData:data
                                                        options:0
                                                          error:&error];
            if (!error && [parsed isKindOfClass:[NSArray class]]) {
                return [NSMutableArray arrayWithArray:parsed];
            }
        }

        // Main file corrupted, try backup
        NSString *backupPath = [path stringByAppendingString:@CLIPPY_BACKUP_SUFFIX];
        if ([fm fileExistsAtPath:backupPath]) {
            NSLog(@"clippy: Main file corrupted, trying backup: %@", backupPath);
            content = [NSString stringWithContentsOfFile:backupPath
                                                encoding:NSUTF8StringEncoding
                                                   error:&error];
            if (!error && content && [content length] > 0) {
                NSData *data = [content dataUsingEncoding:NSUTF8StringEncoding];
                id parsed = [NSJSONSerialization JSONObjectWithData:data
                                                            options:0
                                                              error:&error];
                if (!error && [parsed isKindOfClass:[NSArray class]]) {
                    NSLog(@"clippy: Recovered from backup successfully");
                    return [NSMutableArray arrayWithArray:parsed];
                }
            }
        }

        // Both corrupted
        if (error) {
            NSLog(@"clippy: Failed to read %@: %@", path, error);
        }
    }

    return [NSMutableArray array];
}

/**
 * Write JSON array to file with backup
 * Creates backup of existing file before writing
 */
static inline BOOL clippy_write_json_array(NSArray *array, NSString *path) {
    NSFileManager *fm = [NSFileManager defaultManager];
    NSError *error = nil;

    // Create backup of existing file
    if ([fm fileExistsAtPath:path]) {
        NSString *backupPath = [path stringByAppendingString:@CLIPPY_BACKUP_SUFFIX];
        [fm removeItemAtPath:backupPath error:nil];  // Remove old backup
        [fm copyItemAtPath:path toPath:backupPath error:&error];
        if (error) {
            NSLog(@"clippy: Warning - failed to create backup: %@", error);
            error = nil;  // Continue anyway
        }
    }

    // Serialize to JSON
    NSData *data = [NSJSONSerialization dataWithJSONObject:array
                                                   options:NSJSONWritingPrettyPrinted
                                                     error:&error];
    if (error) {
        NSLog(@"clippy: Failed to serialize JSON: %@", error);
        return NO;
    }

    // Write atomically
    BOOL success = [data writeToFile:path options:NSDataWritingAtomic error:&error];
    if (!success) {
        NSLog(@"clippy: Failed to write %@: %@", path, error);
        return NO;
    }

    // Set restrictive permissions (owner read/write only)
    chmod([path fileSystemRepresentation], S_IRUSR | S_IWUSR);

    return YES;
}

// ============================================================================
// Configuration File Parsing
// ============================================================================

/**
 * Load configuration from ~/.clippy.conf
 * Format: key=value (one per line, # for comments)
 */
static inline void clippy_load_config(void) {
    NSString *path = clippy_config_path();
    NSError *error = nil;
    NSString *content = [NSString stringWithContentsOfFile:path
                                                  encoding:NSUTF8StringEncoding
                                                     error:&error];
    if (error || !content) {
        return;  // No config file, use defaults
    }

    NSArray *lines = [content componentsSeparatedByCharactersInSet:
                      [NSCharacterSet newlineCharacterSet]];

    for (NSString *line in lines) {
        NSString *trimmed = [line stringByTrimmingCharactersInSet:
                             [NSCharacterSet whitespaceCharacterSet]];

        // Skip empty lines and comments
        if ([trimmed length] == 0 || [trimmed hasPrefix:@"#"]) {
            continue;
        }

        NSArray *parts = [trimmed componentsSeparatedByString:@"="];
        if ([parts count] != 2) {
            continue;
        }

        NSString *key = [parts[0] stringByTrimmingCharactersInSet:
                         [NSCharacterSet whitespaceCharacterSet]];
        NSString *value = [parts[1] stringByTrimmingCharactersInSet:
                           [NSCharacterSet whitespaceCharacterSet]];
        int intValue = [value intValue];

        if ([key isEqualToString:@"poll_interval_ms"] && intValue > 0) {
            clippy_config.pollIntervalMs = intValue;
        } else if ([key isEqualToString:@"max_history_items"] && intValue > 0) {
            clippy_config.maxHistoryItems = intValue;
        } else if ([key isEqualToString:@"max_pins"] && intValue > 0) {
            clippy_config.maxPins = intValue;
        } else if ([key isEqualToString:@"max_entry_length"] && intValue > 0) {
            clippy_config.maxEntryLength = intValue;
        } else if ([key isEqualToString:@"max_age_days"] && intValue > 0) {
            clippy_config.maxAgeDays = intValue;
        } else if ([key isEqualToString:@"cleanup_interval_sec"] && intValue > 0) {
            clippy_config.cleanupIntervalSec = intValue;
        }
    }
}

// ============================================================================
// Display Helpers
// ============================================================================

#define CLIPPY_PREVIEW_LENGTH 60

static inline NSString *clippy_format_timestamp(NSNumber *timestamp) {
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

static inline NSString *clippy_preview_text(NSString *text) {
    text = [text stringByReplacingOccurrencesOfString:@"\n" withString:@"↵"];
    text = [text stringByReplacingOccurrencesOfString:@"\r" withString:@""];

    if ([text length] <= CLIPPY_PREVIEW_LENGTH) {
        return text;
    }

    return [[text substringToIndex:CLIPPY_PREVIEW_LENGTH] stringByAppendingString:@"..."];
}

// ============================================================================
// Cleanup Operations
// ============================================================================

/**
 * Remove entries older than maxAgeDays from a JSON array file
 * Returns number of entries removed
 */
static inline NSUInteger clippy_cleanup_old_entries(NSString *path) {
    NSMutableArray *entries = clippy_read_json_array(path);
    if ([entries count] == 0) {
        return 0;
    }

    NSTimeInterval maxAge = clippy_config.maxAgeDays * 24 * 60 * 60;
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
            [filtered addObject:entry];
        }
    }

    if (removed > 0) {
        clippy_write_json_array(filtered, path);
    }

    return removed;
}

#endif /* CLIPPY_COMMON_H */
