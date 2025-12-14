#include <stdio.h>
#include <assert.h>
#include "clipboard-history.h"

void test_process_data(void) {
    assert(process_data("hello") == 5);
    assert(process_data(NULL) == -1);
    printf("PASS: test_process_data\n");
}

int main(void) {
    printf("Running tests...\n\n");
    test_process_data();
    printf("\nAll tests passed!\n");
    return 0;
}
