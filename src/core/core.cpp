#include "core.h"
#include <cstdarg>
#include <cstdio>
#include <cstdlib>
#include <cstring>

namespace ember {

Arena arena_create(u64 size) {
    Arena a = {};
    a.base = (u8*)malloc(size);
    a.size = size;
    a.used = 0;
    return a;
};

void arena_destroy(Arena* a) {
    free(a->base);
    a = null;
}

void* arena_push(Arena* a, u64 size) {
    EMBER_ASSERT(a->used + size <= a->size);
    void* ptr = a->base + a->used;
    a->used += size;
    return ptr;
}

void* arena_push_zero(Arena* a, u64 size) {
    void* ptr = arena_push(a, size);
    memset(ptr, 0, size);
    return ptr;
}

void arena_reset(Arena* a) { a->used = 0; }

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
