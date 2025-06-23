
#include "avery.h"

void hello() { avprint("Hello, from another function!\n"); }

avery_status init() {
    avprint("Hello, World!\n");
    hello();
    return AVERY_OK;
}

avery_status destroy() { return AVERY_OK; }
