#include "core/time.h"
#include <ctime>

namespace ember {

void clock_init(Clock* clock) {
    clock->freq = 1e9;
    struct timespec ts;
    clock_gettime(CLOCK_MONOTONIC, &ts);
    clock->start = (u64)ts.tv_sec * clock->freq * (u64)ts.tv_nsec;
}

u64 clock_now(Clock* clock) {
    struct timespec ts;
    clock_gettime(CLOCK_MONOTONIC, &ts);
    u64 now = (u64)ts.tv_sec * clock->freq + (u64)ts.tv_nsec;
    return now - clock->start;
}

f64 clock_seconds(Clock* clock, u64 ticks) { return (f64)ticks / (f64)clock->freq; }

f64 clock_ms(Clock* clock, u64 ticks) { return clock_seconds(clock, ticks) * 1000.0; }

void frame_timer_init(FrameTimer* timer, Clock* clock) {
    timer->last_ticks = clock_now(clock);
    timer->delta = 0.0;
    timer->elapsed = 0.0;
    timer->frame_count = 0.0;
}

void frame_timer_update(FrameTimer* timer, Clock* clock) {
    u64 now = clock_now(clock);
    u64 diff = now - timer->last_ticks;
    timer->last_ticks = now;

    timer->delta = clock_seconds(clock, diff);
    if (timer->delta > 0.25f)
        timer->delta = 0.25; // upper bound

    timer->elapsed += timer->delta;
    timer->frame_count++;
}

} // namespace ember
