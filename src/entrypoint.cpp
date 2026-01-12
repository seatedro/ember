#include "ember.h"

extern ember::EmberConfig cfg;

int main() {
    ember::ember_run(&cfg);
    return 0;
}
