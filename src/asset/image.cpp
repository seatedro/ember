#include "image.h"
#include "core/core.h"
#include "core/file.h"
#include <cstring>

namespace ember {

internal b32 safe_add(u64 a, u64 b, u64* out) {
    if (a > UINT64_MAX - b)
        return false;
    *out = a + b;
    return true;
}

internal b32 safe_mul(u64 a, u64 b, u64* out) {
    if (a != 0 && b > UINT64_MAX / a)
        return false;
    *out = a * b;
    return true;
}

internal b32 range_check(u64 offset, u64 length, u64 size) {
    if (offset > size)
        return false;
    if (length > size - offset)
        return false;
    return true;
}

constexpr u8 PNG_MAGIC[8] = { 137, 80, 78, 71, 13, 10, 26, 10 };

constexpr u32 PNG_TAG(char a, char b, char c, char d) {
    return ((u32)a << 24) | ((u32)b << 16) | ((u32)c << 8) | (u32)d;
}

struct PngPass {
    u32 start_x;
    u32 start_y;
    u32 step_x;
    u32 step_y;
};

// clang-format off
constexpr PngPass ADAM7_PASSES[7] = {
    { 0, 0, 8, 8 },
    { 4, 0, 8, 8 },
    { 0, 4, 4, 8 },
    { 2, 0, 4, 4 },
    { 0, 2, 2, 4 },
    { 1, 0, 2, 2 },
    { 0, 1, 1, 2 },
};
// clang-format on

Image load_image(Arena* arena, const char* path) {
    EmberFile file = read_file_binary(arena, path);
    if (!file.success) {
        LOG_ERROR("image", "failed to read image file: %s", path);
        return {};
    }

    if (file.size >= 8) {
        const u8* p = file.data;
        if (memcmp(p, PNG_MAGIC, 8) == 0)
            return load_png(arena, file.data, file.size);
    }

    if (file.size >= 2) {
        if (file.data[0] == 'B' && file.data[1] == 'M')
            return load_bmp(arena, file.data, file.size);
    }

    LOG_ERROR("image", "unsupported image format: %s", path);
    return {};
}

internal u8 extract_component(u32 value, u32 mask) {
    if (mask == 0)
        return 0;
    u32 shift = 0;
    while ((mask & 1u) == 0u) {
        mask >>= 1u;
        shift++;
    }

    u32 bits = 0;
    while ((mask & 1u) != 0u) {
        mask >>= 1u;
        bits++;
    }
    if (bits == 0)
        return 0;

    u32 max = (1u << bits) - 1u;
    u32 component = (value >> shift) & max;
    if (max == 255u)
        return (u8)component;

    return (u8)((component * 255u + (max / 2u)) / max);
}

} // namespace ember
