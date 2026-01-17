#pragma once
#include <cstdlib>
#include <cstring>
#include <stdint.h>

#define null     nullptr
#define internal static
#define global   static
#define pub      static

#ifdef EMBER_DEBUG
#define EMBER_ASSERT(cond)                                                                         \
    do {                                                                                           \
        if (!(cond))                                                                               \
            __builtin_trap();                                                                      \
    } while (0)
#else
#define EMBER_ASSERT(cond) ((void)0)
#endif // EMBER_DEBUG

#define EMBER_INVALID_PATH    EMBER_ASSERT(!"invalid code path")
#define EMBER_NOT_IMPLEMENTED EMBER_ASSERT(!"not implemented")

#define LOG_INFO(tag, ...)  ember::log(ember::LogLevel::Info, tag, __VA_ARGS__)
#define LOG_ERROR(tag, ...) ember::log(ember::LogLevel::Error, tag, __VA_ARGS__)

// cpp brain fuckery so i can use defer *mwah*
// template deduces lambda type, stores inline
// destructor calls lambda when it goes out of scope
#define EMBER_DEFER_CONCAT(a, b) a##b
#define EMBER_DEFER_VAR(n)       EMBER_DEFER_CONCAT(_defer_, n)
#define defer(code)              auto EMBER_DEFER_VAR(__LINE__) = make_defer([&] { code; })

namespace ember {

template <typename F>
struct Deferrer {
    F f;
    ~Deferrer() { f(); }
};

template <typename F>
Deferrer<F> make_defer(F f) {
    return { f };
}

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

constexpr u32 KB(u32 n) { return n * 1024; }
constexpr u32 MB(u32 n) { return n * 1024 * 1024; }
constexpr u32 GB(u32 n) { return n * 1024 * 1024 * 1024; }

// using template here for convenience
template <typename T, u32 MAX>
struct Pool {
    T   data[MAX];
    u32 free_list[MAX];
    u32 free_count;
    u32 count;

    void init() {
        count = 0;
        free_count = 0;
    }

    u32 alloc() {
        if (free_count > 0) {
            u32 id = free_list[--free_count];
            EMBER_ASSERT(id < count);
            return id;
        }
        EMBER_ASSERT(count < MAX);
        return count++;
    }

    void release(u32 id) {
        EMBER_ASSERT(id < count);
        EMBER_ASSERT(free_count < MAX);

#if defined(EMBER_DEBUG)
        // double free detection
        for (u32 i = 0; i < free_count; i++) {
            EMBER_ASSERT(free_list[i] != id);
        }
#endif

        free_list[free_count++] = id;
    }

    T* get(u32 id) {
        EMBER_ASSERT(id < count);
        return &data[id];
    }
};

struct Arena {
    u8* base;
    u64 size;
    u64 used;

    pub Arena create(u64 size) {
        Arena a = {};
        a.base = (u8*)malloc(size);
        a.size = size;
        a.used = 0;
        return a;
    };

    pub void destroy(Arena* a) {
        free(a->base);
        a = null;
    }

    pub void* push(Arena* a, u64 size) {
        EMBER_ASSERT(a->used + size <= a->size);
        void* ptr = a->base + a->used;
        a->used += size;
        return ptr;
    }

    pub void* push_zero(Arena* a, u64 size) {
        void* ptr = push(a, size);
        memset(ptr, 0, size);
        return ptr;
    }

    pub void reset(Arena* a) { a->used = 0; }

    template <typename T>
    pub T* alloc(Arena* a) {
        return (T*)push_zero(a, sizeof(T));
    }

    template <typename T>
    pub T* alloc_array(Arena* a, u64 count) {
        return (T*)push_zero(a, sizeof(T) * count);
    }
};

enum class LogLevel { Trace, Debug, Info, Warn, Error, Panic };

void log(LogLevel level, const char* tag, const char* fmt, ...);

struct ByteBuffer {
    u8* data;
    u32 size;
    u32 capacity;

    pub ByteBuffer create(u32 initial_capacity = KB(64)) {
        ByteBuffer buf = {};
        buf.data = (u8*)malloc(initial_capacity);
        buf.capacity = initial_capacity;
        buf.size = 0;
        return buf;
    }

    pub void destroy(ByteBuffer* buf) {
        if (buf->data)
            free(buf->data);
        *buf = {};
    }

    pub void clear(ByteBuffer* buf) { buf->size = 0; }

    pub void reserve(ByteBuffer* buf, u32 additional) {
        if (buf->size + additional > buf->capacity) {
            u32 new_capacity = buf->capacity * 2; // simple 2x alloc
            while (new_capacity < buf->size + additional)
                new_capacity *= 2;
            buf->data = (u8*)realloc(buf->data, new_capacity);
            buf->capacity = new_capacity;
        }
    }

    pub void write_bytes(ByteBuffer* buf, const void* src, u32 len) {
        reserve(buf, len);
        memcpy(buf->data + buf->size, src, len);
        buf->size += len;
    }

    template <typename T>
    pub void write(ByteBuffer* buf, const T& value) {
        reserve(buf, sizeof(T));
        memcpy(buf->data + buf->size, &value, &value, sizeof(T));
        buf->size += sizeof(T);
    }
};

struct ByteReader {
    const u8* data;
    u32       size;
    u32       pos;

    pub ByteReader from(const ByteBuffer* buf) { return { buf->data, buf->size, 0 }; }

    template <typename T>
    pub T read(ByteReader* r) {
        EMBER_ASSERT(r->pos + sizeof(T) <= r->size);
        T value;
        memcpy(&value, r->data + r->pos, sizeof(T));
        r->pos += sizeof(T);
        return value;
    }

    pub b32 has_more(const ByteReader* r) { return r->pos < r->size; }
};

} // namespace ember
