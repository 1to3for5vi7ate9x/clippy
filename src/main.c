#include <stdio.h>
#include "clipboard-history.h"

int main(int argc, char *argv[]) {
    printf("Hello from clipboard-history!\n");

    int result = process_data("example");
    printf("Result: %d\n", result);

    return 0;
}
