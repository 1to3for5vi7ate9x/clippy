#include <stdio.h>
#include <string.h>
#include "clipboard-history.h"

int process_data(const char *input) {
    if (input == NULL) {
        return -1;
    }
    // Add your processing logic here
    return (int)strlen(input);
}
