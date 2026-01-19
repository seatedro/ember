#pragma once

#include "core/core.h"

namespace ember {

struct Clock {
    u64 freq;
    u64 start;
};

struct FrameTimer {
    u64 last_ticks;
    u64 frame_count;
    f64 delta;
    f64 elapsed;
};

void clock_init(Clock* clock);
u64 clock_now(Clock* clock);
f64 clock_seconds(Clock* clock, u64 ticks);
f64 clock_ms(Clock* clock, u64 ticks);

void frame_timer_init(FrameTimer* timer, Clock* clock);
void frame_timer_update(FrameTimer* timer, Clock* clock);

} // namespace ember
