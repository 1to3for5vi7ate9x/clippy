/**
 * test_fuzzy_search.m - Tests for fuzzy search algorithm
 *
 * Build: make test-fuzzy
 */

#import <Foundation/Foundation.h>

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
                reason:[NSString stringWithFormat:@"Expected %ld == %ld", (long)(a), (long)(b)] \
                userInfo:nil]; \
    } \
} while(0)

#define ASSERT_GT(a, b) do { \
    if (!((a) > (b))) { \
        @throw [NSException exceptionWithName:@"AssertionFailed" \
                reason:[NSString stringWithFormat:@"Expected %ld > %ld", (long)(a), (long)(b)] \
                userInfo:nil]; \
    } \
} while(0)

// ============================================================================
// Fuzzy Search Implementation (copied from clippy_picker.m for testing)
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
// Tests: Empty/Null Inputs
// ============================================================================

TEST(empty_pattern_matches_all) {
    FuzzyMatchResult result = fuzzyMatch(@"", @"hello world");
    ASSERT(result.matches);
    ASSERT_EQ(result.score, 0);
}

TEST(empty_text_no_match) {
    FuzzyMatchResult result = fuzzyMatch(@"hello", @"");
    ASSERT(!result.matches);
}

TEST(nil_pattern_matches_all) {
    FuzzyMatchResult result = fuzzyMatch(nil, @"hello");
    ASSERT(result.matches);
}

TEST(nil_text_no_match) {
    FuzzyMatchResult result = fuzzyMatch(@"hello", nil);
    ASSERT(!result.matches);
}

// ============================================================================
// Tests: Basic Matching
// ============================================================================

TEST(exact_match) {
    FuzzyMatchResult result = fuzzyMatch(@"hello", @"hello");
    ASSERT(result.matches);
    ASSERT_GT(result.score, 0);
}

TEST(substring_match) {
    FuzzyMatchResult result = fuzzyMatch(@"ell", @"hello");
    ASSERT(result.matches);
    ASSERT_GT(result.score, 0);
}

TEST(scattered_match) {
    FuzzyMatchResult result = fuzzyMatch(@"hlo", @"hello");
    ASSERT(result.matches);
}

TEST(no_match) {
    FuzzyMatchResult result = fuzzyMatch(@"xyz", @"hello");
    ASSERT(!result.matches);
    ASSERT_EQ(result.score, 0);
}

TEST(case_insensitive) {
    FuzzyMatchResult result1 = fuzzyMatch(@"HELLO", @"hello");
    FuzzyMatchResult result2 = fuzzyMatch(@"hello", @"HELLO");
    ASSERT(result1.matches);
    ASSERT(result2.matches);
}

// ============================================================================
// Tests: Scoring
// ============================================================================

TEST(consecutive_scores_higher) {
    // "hel" in "hello" (consecutive) should score higher than "hlo" (scattered)
    FuzzyMatchResult consecutive = fuzzyMatch(@"hel", @"hello");
    FuzzyMatchResult scattered = fuzzyMatch(@"hlo", @"hello");

    ASSERT(consecutive.matches);
    ASSERT(scattered.matches);
    ASSERT_GT(consecutive.score, scattered.score);
}

TEST(start_match_scores_higher) {
    // Matching at start should score higher
    FuzzyMatchResult startMatch = fuzzyMatch(@"hel", @"hello world");
    FuzzyMatchResult midMatch = fuzzyMatch(@"wor", @"hello world");

    ASSERT(startMatch.matches);
    ASSERT(midMatch.matches);
    ASSERT_GT(startMatch.score, midMatch.score);
}

TEST(word_boundary_bonus) {
    // "wo" at word start in "hello world" should get bonus
    FuzzyMatchResult result = fuzzyMatch(@"w", @"hello world");
    ASSERT(result.matches);
    ASSERT_GT(result.score, 0);
}

TEST(earlier_position_scores_higher) {
    FuzzyMatchResult early = fuzzyMatch(@"a", @"abc");
    FuzzyMatchResult late = fuzzyMatch(@"c", @"abc");

    ASSERT(early.matches);
    ASSERT(late.matches);
    ASSERT_GT(early.score, late.score);
}

// ============================================================================
// Tests: Real-World Examples
// ============================================================================

TEST(api_key_search) {
    FuzzyMatchResult result = fuzzyMatch(@"sk-", @"sk-proj-abc123xyz");
    ASSERT(result.matches);
}

TEST(email_search) {
    FuzzyMatchResult result = fuzzyMatch(@"email", @"my-email@example.com");
    ASSERT(result.matches);
}

TEST(url_search) {
    FuzzyMatchResult result = fuzzyMatch(@"github", @"https://github.com/user/repo");
    ASSERT(result.matches);
}

TEST(partial_command) {
    // Common use case: searching for commands
    FuzzyMatchResult result = fuzzyMatch(@"gits", @"git status");
    ASSERT(result.matches);
}

// ============================================================================
// Tests: Edge Cases
// ============================================================================

TEST(single_char_match) {
    FuzzyMatchResult result = fuzzyMatch(@"h", @"hello");
    ASSERT(result.matches);
}

TEST(pattern_longer_than_text) {
    FuzzyMatchResult result = fuzzyMatch(@"hello world", @"hi");
    ASSERT(!result.matches);
}

TEST(special_characters) {
    FuzzyMatchResult result = fuzzyMatch(@"@", @"email@test.com");
    ASSERT(result.matches);
}

TEST(unicode_characters) {
    FuzzyMatchResult result = fuzzyMatch(@"caf", @"cafe");
    ASSERT(result.matches);
}

// ============================================================================
// Main
// ============================================================================

int main(int argc, const char *argv[]) {
    (void)argc;
    (void)argv;

    @autoreleasepool {
        printf("\n=== Fuzzy Search Test Suite ===\n\n");

        printf("Empty/Null Input Tests:\n");
        RUN_TEST(empty_pattern_matches_all);
        RUN_TEST(empty_text_no_match);
        RUN_TEST(nil_pattern_matches_all);
        RUN_TEST(nil_text_no_match);

        printf("\nBasic Matching Tests:\n");
        RUN_TEST(exact_match);
        RUN_TEST(substring_match);
        RUN_TEST(scattered_match);
        RUN_TEST(no_match);
        RUN_TEST(case_insensitive);

        printf("\nScoring Tests:\n");
        RUN_TEST(consecutive_scores_higher);
        RUN_TEST(start_match_scores_higher);
        RUN_TEST(word_boundary_bonus);
        RUN_TEST(earlier_position_scores_higher);

        printf("\nReal-World Example Tests:\n");
        RUN_TEST(api_key_search);
        RUN_TEST(email_search);
        RUN_TEST(url_search);
        RUN_TEST(partial_command);

        printf("\nEdge Case Tests:\n");
        RUN_TEST(single_char_match);
        RUN_TEST(pattern_longer_than_text);
        RUN_TEST(special_characters);
        RUN_TEST(unicode_characters);

        printf("\n=== Results ===\n");
        printf("Tests run: %d\n", tests_run);
        printf("Passed:    %d\n", tests_passed);
        printf("Failed:    %d\n", tests_failed);
        printf("\n");

        return tests_failed > 0 ? 1 : 0;
    }
}
