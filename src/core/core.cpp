#include "core.h"
#include <cstdarg>
#include <cstdio>
#include <cstdlib>

namespace ember {

Arena Arena::create(u64 size) {
    Arena a = {};
    a.base = (u8*)malloc(size);
    a.size = size;
    a.used = 0;
    return a;
};

void Arena::destroy(Arena* a) {
    free(a->base);
    a = null;
}

void* Arena::push(Arena* a, u64 size) {
    EMBER_ASSERT(a->used + size <= a->size);
    void* ptr = a->base + a->used;
    a->used += size;
    return ptr;
}

void Arena::reset(Arena* a) {
    a->used = 0;
}

void log(LogLevel level, const char* tag, const char* fmt, ...) {
    const char* level_str[] = { "TRACE", "DEBUG", "INFO", "WARN", "ERROR", "FATAL" };
    fprintf(stderr, "[%s] %s: ", level_str[(int)level], tag);
    va_list args;
    va_start(args, fmt);
    vfprintf(stderr, fmt, args);
    va_end(args);

    fprintf(stderr, "\n");
}

} // namespace ember
