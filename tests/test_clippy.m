/**
 * test_clippy.m - Tests for clippy clipboard history tool
 *
 * Simple test framework with assertions.
 * Build: make test
 */

#import <Foundation/Foundation.h>
#include "clippy_common.h"

// ============================================================================
// Test Framework
// ============================================================================

static int tests_run = 0;
static int tests_passed = 0;
static int tests_failed = 0;

#define TEST(name) void test_##name(void)
#define RUN_TEST(name) do { \
    printf("  Testing %s... ", #name); \
    tests_run++; \
    @try { \
        test_##name(); \
        tests_passed++; \
        printf("PASS\n"); \
    } @catch (NSException *e) { \
        tests_failed++; \
        printf("FAIL: %s\n", [[e reason] UTF8String]); \
    } \
} while(0)

#define ASSERT(cond) do { \
    if (!(cond)) { \
        @throw [NSException exceptionWithName:@"AssertionFailed" \
                reason:[NSString stringWithFormat:@"Assertion failed: %s", #cond] \
                userInfo:nil]; \
    } \
} while(0)

#define ASSERT_EQ(a, b) do { \
    if ((a) != (b)) { \
        @throw [NSException exceptionWithName:@"AssertionFailed" \
                reason:[NSString stringWithFormat:@"Expected %d == %d", (int)(a), (int)(b)] \
                userInfo:nil]; \
    } \
} while(0)

#define ASSERT_STR_EQ(a, b) do { \
    if (![(a) isEqualToString:(b)]) { \
        @throw [NSException exceptionWithName:@"AssertionFailed" \
                reason:[NSString stringWithFormat:@"Expected '%@' == '%@'", (a), (b)] \
                userInfo:nil]; \
    } \
} while(0)

// ============================================================================
// Test Fixtures
// ============================================================================

static NSString *testHistoryPath = nil;
static NSString *testPinsPath = nil;
static NSString *testConfigPath = nil;

void setup(void) {
    // Use temp directory for test files
    NSString *tempDir = NSTemporaryDirectory();
    testHistoryPath = [tempDir stringByAppendingPathComponent:@"test_clipboard_history"];
    testPinsPath = [tempDir stringByAppendingPathComponent:@"test_clipboard_pins"];
    testConfigPath = [tempDir stringByAppendingPathComponent:@"test_clippy.conf"];

    // Clean up any existing test files
    NSFileManager *fm = [NSFileManager defaultManager];
    [fm removeItemAtPath:testHistoryPath error:nil];
    [fm removeItemAtPath:testPinsPath error:nil];
    [fm removeItemAtPath:testConfigPath error:nil];
    [fm removeItemAtPath:[testHistoryPath stringByAppendingString:@".backup"] error:nil];
    [fm removeItemAtPath:[testPinsPath stringByAppendingString:@".backup"] error:nil];
}

void teardown(void) {
    NSFileManager *fm = [NSFileManager defaultManager];
    [fm removeItemAtPath:testHistoryPath error:nil];
    [fm removeItemAtPath:testPinsPath error:nil];
    [fm removeItemAtPath:testConfigPath error:nil];
    [fm removeItemAtPath:[testHistoryPath stringByAppendingString:@".backup"] error:nil];
    [fm removeItemAtPath:[testPinsPath stringByAppendingString:@".backup"] error:nil];
}

// ============================================================================
// Tests: File Path Helpers
// ============================================================================

TEST(file_paths) {
    NSString *history = clippy_history_path();
    NSString *pins = clippy_pins_path();
    NSString *config = clippy_config_path();

    ASSERT([history hasSuffix:@".clipboard_history"]);
    ASSERT([pins hasSuffix:@".clipboard_pins"]);
    ASSERT([config hasSuffix:@".clippy.conf"]);
}

// ============================================================================
// Tests: JSON Read/Write
// ============================================================================

TEST(json_write_read_empty) {
    NSMutableArray *data = [NSMutableArray array];
    ASSERT(clippy_write_json_array(data, testHistoryPath));

    NSMutableArray *read = clippy_read_json_array(testHistoryPath);
    ASSERT_EQ([read count], 0);
}

TEST(json_write_read_data) {
    NSMutableArray *data = [NSMutableArray array];
    [data addObject:@{@"text": @"hello", @"timestamp": @(1234567890)}];
    [data addObject:@{@"text": @"world", @"timestamp": @(1234567891)}];

    ASSERT(clippy_write_json_array(data, testHistoryPath));

    NSMutableArray *read = clippy_read_json_array(testHistoryPath);
    ASSERT_EQ([read count], 2);
    ASSERT_STR_EQ(read[0][@"text"], @"hello");
    ASSERT_STR_EQ(read[1][@"text"], @"world");
}

TEST(json_read_nonexistent) {
    NSMutableArray *read = clippy_read_json_array(@"/nonexistent/path/file.json");
    ASSERT_EQ([read count], 0);
}

TEST(json_backup_created) {
    // Write initial data
    NSMutableArray *data1 = [NSMutableArray arrayWithObject:@{@"text": @"first"}];
    clippy_write_json_array(data1, testHistoryPath);

    // Write new data (should create backup)
    NSMutableArray *data2 = [NSMutableArray arrayWithObject:@{@"text": @"second"}];
    clippy_write_json_array(data2, testHistoryPath);

    // Check backup exists
    NSString *backupPath = [testHistoryPath stringByAppendingString:@".backup"];
    ASSERT([[NSFileManager defaultManager] fileExistsAtPath:backupPath]);

    // Check backup contains old data
    NSMutableArray *backup = clippy_read_json_array(backupPath);
    ASSERT_EQ([backup count], 1);
    ASSERT_STR_EQ(backup[0][@"text"], @"first");
}

TEST(json_corrupted_returns_empty) {
    // Write corrupted main file
    [@"{ invalid json" writeToFile:testHistoryPath
                        atomically:YES
                          encoding:NSUTF8StringEncoding
                             error:nil];

    // Read should return empty array (graceful handling)
    NSMutableArray *read = clippy_read_json_array(testHistoryPath);
    ASSERT_EQ([read count], 0);
}

// ============================================================================
// Tests: Display Helpers
// ============================================================================

TEST(preview_text_short) {
    NSString *text = @"Hello World";
    NSString *preview = clippy_preview_text(text);
    ASSERT_STR_EQ(preview, @"Hello World");
}

TEST(preview_text_long) {
    NSString *text = [@"" stringByPaddingToLength:100 withString:@"x" startingAtIndex:0];
    NSString *preview = clippy_preview_text(text);
    ASSERT_EQ([preview length], CLIPPY_PREVIEW_LENGTH + 3);  // +3 for "..."
    ASSERT([preview hasSuffix:@"..."]);
}

TEST(preview_text_newlines) {
    NSString *text = @"line1\nline2\rline3";
    NSString *preview = clippy_preview_text(text);
    ASSERT([preview containsString:@"↵"]);
    ASSERT(![preview containsString:@"\n"]);
    ASSERT(![preview containsString:@"\r"]);
}

TEST(format_timestamp_today) {
    NSNumber *now = @([[NSDate date] timeIntervalSince1970]);
    NSString *formatted = clippy_format_timestamp(now);
    ASSERT([formatted hasPrefix:@"Today"]);
}

TEST(format_timestamp_yesterday) {
    NSTimeInterval yesterday = [[NSDate date] timeIntervalSince1970] - (24 * 60 * 60);
    NSNumber *ts = @(yesterday);
    NSString *formatted = clippy_format_timestamp(ts);
    ASSERT([formatted hasPrefix:@"Yesterday"]);
}

// ============================================================================
// Tests: Configuration
// ============================================================================

TEST(config_defaults) {
    // Reset to defaults
    clippy_config.pollIntervalMs = CLIPPY_DEFAULT_POLL_INTERVAL_MS;
    clippy_config.maxHistoryItems = CLIPPY_DEFAULT_MAX_HISTORY_ITEMS;
    clippy_config.maxPins = CLIPPY_DEFAULT_MAX_PINS;

    ASSERT_EQ(clippy_config.pollIntervalMs, 500);
    ASSERT_EQ(clippy_config.maxHistoryItems, 50);
    ASSERT_EQ(clippy_config.maxPins, 50);
    ASSERT_EQ(clippy_config.maxAgeDays, 30);
}

// ============================================================================
// Tests: Cleanup
// ============================================================================

TEST(cleanup_old_entries) {
    // Create entries with different ages
    NSTimeInterval now = [[NSDate date] timeIntervalSince1970];
    NSMutableArray *data = [NSMutableArray array];

    // Recent entry (should keep)
    [data addObject:@{@"text": @"recent", @"timestamp": @(now - 86400)}];  // 1 day old

    // Old entry (should remove)
    [data addObject:@{@"text": @"old", @"timestamp": @(now - (40 * 86400))}];  // 40 days old

    clippy_write_json_array(data, testHistoryPath);

    // Run cleanup
    NSUInteger removed = clippy_cleanup_old_entries(testHistoryPath);
    ASSERT_EQ(removed, 1);

    // Verify only recent entry remains
    NSMutableArray *read = clippy_read_json_array(testHistoryPath);
    ASSERT_EQ([read count], 1);
    ASSERT_STR_EQ(read[0][@"text"], @"recent");
}

// ============================================================================
// Tests: File Permissions
// ============================================================================

TEST(file_permissions) {
    NSMutableArray *data = [NSMutableArray arrayWithObject:@{@"text": @"secret"}];
    clippy_write_json_array(data, testHistoryPath);

    NSDictionary *attrs = [[NSFileManager defaultManager] attributesOfItemAtPath:testHistoryPath error:nil];
    NSNumber *perms = attrs[NSFilePosixPermissions];

    // Should be 0600 (owner read/write only)
    ASSERT_EQ([perms intValue] & 0777, 0600);
}

// ============================================================================
// Main
// ============================================================================

int main(int argc, const char *argv[]) {
    (void)argc;
    (void)argv;

    @autoreleasepool {
        printf("\n=== Clippy Test Suite ===\n\n");

        printf("File Path Tests:\n");
        setup();
        RUN_TEST(file_paths);
        teardown();

        printf("\nJSON Read/Write Tests:\n");
        setup();
        RUN_TEST(json_write_read_empty);
        teardown();

        setup();
        RUN_TEST(json_write_read_data);
        teardown();

        setup();
        RUN_TEST(json_read_nonexistent);
        teardown();

        setup();
        RUN_TEST(json_backup_created);
        teardown();

        setup();
        RUN_TEST(json_corrupted_returns_empty);
        teardown();

        printf("\nDisplay Helper Tests:\n");
        setup();
        RUN_TEST(preview_text_short);
        RUN_TEST(preview_text_long);
        RUN_TEST(preview_text_newlines);
        RUN_TEST(format_timestamp_today);
        RUN_TEST(format_timestamp_yesterday);
        teardown();

        printf("\nConfiguration Tests:\n");
        setup();
        RUN_TEST(config_defaults);
        teardown();

        printf("\nCleanup Tests:\n");
        setup();
        RUN_TEST(cleanup_old_entries);
        teardown();

        printf("\nPermissions Tests:\n");
        setup();
        RUN_TEST(file_permissions);
        teardown();

        printf("\n=== Results ===\n");
        printf("Tests run: %d\n", tests_run);
        printf("Passed:    %d\n", tests_passed);
        printf("Failed:    %d\n", tests_failed);
        printf("\n");

        return tests_failed > 0 ? 1 : 0;
    }
}
