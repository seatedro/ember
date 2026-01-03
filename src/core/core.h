#pragma once
#include <stdint.h>

#define null     nullptr
#define internal static
#define global   static

#define KB(n) ((n) * 1024ULL)
#define MB(n) ((n) * 1024ULL * 1024ULL)
#define GB(n) ((n) * 1024ULL * 1024ULL * 1024ULL)

#ifdef EMBER_DEBUG
#define EMBER_ASSERT(cond)    \
    do {                      \
        if (!(cond))          \
            __builtin_trap(); \
    } while (0)
#else
#define EMBER_ASSERT(cond) ((void)0)
#endif // EMBER_DEBUG

#define LOG_INFO(tag, ...)  ember::log(ember::LogLevel::Info, tag, __VA_ARGS__)
#define LOG_ERROR(tag, ...) ember::log(ember::LogLevel::Error, tag, __VA_ARGS__)

namespace ember {

typedef uint8_t  u8;
typedef uint16_t u16;
typedef uint32_t u32;
typedef uint64_t u64;
typedef int8_t   i8;
typedef int16_t  i16;
typedef int32_t  i32;
typedef int64_t  i64;
typedef float    f32;
typedef double   f64;
typedef u32      b32;

struct Arena {
    u8* base;
    u64 size;
    u64 used;

    static Arena create(u64 size);
    static void* push(Arena* a, u64 size);
    static void  reset(Arena* a);
    static void  destroy(Arena* a);
};

enum class LogLevel {
    Trace,
    Debug,
    Info,
    Warn,
    Error,
    Panic
};

void log(LogLevel level, const char* tag, const char* fmt, ...);

} // namespace ember
