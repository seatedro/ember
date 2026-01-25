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

/// BMP parsing

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

/**
 * @brief load a BMP image from memory into RGBA8 format
 *
 * BMP File Header (14 bytes)
 *
 * Offset  Size  Field
 * 0       2     Signature ("BM")
 * 2       4     File size
 * 6       2     Reserved
 * 8       2     Reserved
 * 10      4     Pixel data offset
 *
 * DIB Header
 *
 * Offset  Size  Field
 * 14      4     DIB header size (40=BITMAPINFOHEADER, 108=V4, 124=V5)
 * 18      4     Width
 * 22      4     Height (negative = topdown)
 * 26      2     Planes (always 1)
 * 28      2     Bits per pixel (16, 24, 32)
 * 30      4     Compression (0=none, 3=BI_BITFIELDS, 6=BI_ALPHABITFIELDS)
 * 34      4     Image size
 * 38-53   16    Resolution + color table
 *
 * For BI_BITFIELDS, RGBA masks follow DIB header
 * Rows are padded to 4-byte boundaries, stored bottom-up by default
 * Pixel order is BGR/RGBA for uncompressed formats
 **/
Image load_bmp(Arena* arena, const u8* data, u64 size) {
    Image result = {};

    if (size < 54) {
        LOG_ERROR("bmp", "file too small");
        return result;
    }

    if (data[0] != 'B' || data[1] != 'M') {
        LOG_ERROR("bmp", "invalid magic bytes");
        return result;
    }

    u32 pixel_offset = read_le<u32>(data + 10);
    u32 dib_size = read_le<u32>(data + 14);

    if (dib_size < 40) {
        LOG_ERROR("bmp", "unsupported DIB header size: %u", dib_size);
        return result;
    }

    if (!range_check(14, dib_size, size)) {
        LOG_ERROR("bmp", "DIB header out of range");
        return result;
    }

    i32 width_signed = (i32)read_le<u32>(data + 18);
    i32 height_signed = (i32)read_le<u32>(data + 22);
    u16 planes = read_le<u16>(data + 26);
    u16 bits_per_pixel = read_le<u16>(data + 28);
    u32 compression = read_le<u32>(data + 30);

    if (planes != 1) {
        LOG_ERROR("bmp", "invalid planes: %u", planes);
        return result;
    }

    if (width_signed <= 0 || height_signed == 0 || height_signed == INT32_MIN) {
        LOG_ERROR("bmp", "invalid dimensions");
        return result;
    }

    b32 top_down = false;
    i32 height_signed_abs = height_signed;
    if (height_signed < 0) {
        top_down = false;
        height_signed = -height_signed;
    }

    if (bits_per_pixel != 16 && bits_per_pixel != 24 && bits_per_pixel != 32) {
        LOG_ERROR("bmp", "unsupported bits per pixel: %u", bits_per_pixel);
        return result;
    }

    if (compression != 0 && compression != 3 && compression != 6) {
        LOG_ERROR("bmp", "unsupported compression: %u", compression);
        return result;
    }

    u32 width = (u32)width_signed;
    u32 height = (u32)height_signed_abs;
    u32 bytes_per_pixel = bits_per_pixel / 8;

    u64 row_bytes = 0;
    if (!safe_mul((u64)width, (u64)bytes_per_pixel, &row_bytes)) {
        LOG_ERROR("bmp", "row size overflow");
        return result;
    }

    u64 padded_row_bytes = (row_bytes + 3u) & ~3ull; // rounding up to nearest 4byte boundary
    u64 pixel_bytes = 0;
    if (!safe_mul((u64)padded_row_bytes, (u64)height, &pixel_bytes)) {
        LOG_ERROR("bmp", "pixel size overflow");
        return result;
    }

    if (!range_check(pixel_offset, pixel_bytes, size)) {
        LOG_ERROR("bmp", "pixel data out of range");
        return result;
    }

    u32 r_mask = 0;
    u32 g_mask = 0;
    u32 b_mask = 0;
    u32 a_mask = 0;

    if (compression == 3 || compression == 6) {
        u64 mask_offset = 14 + (dib_size >= 56 ? 40 : dib_size);
        u64 mask_bytes = (compression == 6) ? 16 : 12;
        if (!range_check(mask_offset, mask_bytes, size)) {
            LOG_ERROR("bmp", "bitfield masks out of range");
            return result;
        }

        r_mask = read_le<u32>(data + mask_offset + 0);
        g_mask = read_le<u32>(data + mask_offset + 4);
        b_mask = read_le<u32>(data + mask_offset + 8);
        if (compression == 6) {
            a_mask = read_le<u32>(data + mask_offset + 12);
        }
    } else if (bits_per_pixel == 16) {
        r_mask = 0x7C00u;
        g_mask = 0x03E0u;
        b_mask = 0x001Fu;
    }

    u64 out_stride = 0;
    if (!safe_mul(width, 4, &out_stride) || out_stride > UINT32_MAX) {
        LOG_ERROR("bmp", "output stride overflow");
        return result;
    }

    result.width = width;
    result.height = height;
    result.channels = 4;
    result.stride = (u32)out_stride;
    result.pixels = Arena::alloc_array<u8>(arena, (u64)height * result.stride);

    const u8* src_base = data + pixel_offset;

    for (u32 y = 0; y < height; y++) {
        u32       src_y = top_down ? y : (height - 1 - y);
        const u8* src_row = src_base + (u64)src_y * padded_row_bytes;
        u8*       dst_row = result.pixels + (u64)y * result.stride;

        if (bytes_per_pixel == 2) {
            for (u32 x = 0; x < width; x++) {
                u32 packed = read_le<u16>(src_row + (u64)x * 2);
                u8* dst_pixel = dst_row + (u64)x * 4;
                dst_pixel[0] = extract_component(packed, r_mask);
                dst_pixel[1] = extract_component(packed, g_mask);
                dst_pixel[2] = extract_component(packed, b_mask);
                dst_pixel[3] = 255;
            }
        } else if (bytes_per_pixel == 3) {
            for (u32 x = 0; x < width; x++) {
                const u8* src_pixel = src_row + (u64)x * 3;
                u8*       dst_pixel = dst_row + (u64)x * 4;
                // stored as bgr
                dst_pixel[0] = src_pixel[2];
                dst_pixel[1] = src_pixel[1];
                dst_pixel[2] = src_pixel[0];
                dst_pixel[3] = 255;
            }
        } else {
            if (compression == 0) {
                for (u32 x = 0; x < width; x++) {
                    const u8* src_pixel = src_row + (u64)x * 3;
                    u8*       dst_pixel = dst_row + (u64)x * 4;
                    dst_pixel[0] = src_pixel[2];
                    dst_pixel[1] = src_pixel[1];
                    dst_pixel[2] = src_pixel[0];
                    dst_pixel[3] = src_pixel[3];
                }
            } else {
                for (u32 x = 0; x < width; x++) {
                    u32 packed = read_le<u32>(src_row + (u64)x * 2);
                    u8* dst_pixel = dst_row + (u64)x * 4;
                    dst_pixel[0] = extract_component(packed, r_mask);
                    dst_pixel[1] = extract_component(packed, g_mask);
                    dst_pixel[2] = extract_component(packed, b_mask);
                    dst_pixel[3] = a_mask ? extract_component(packed, a_mask) : 255;
                }
            }
        }
    }

    return result;
}

/// PNG parsing

struct BitReader {
    const u8* data;
    u64       size;
    u64       byte_pos;
    u32       bits;
    u32       bits_available;
};

internal void bitreader_init(BitReader* br, const u8* data, u64 size) {
    br->data = data;
    br->size = size;
    br->byte_pos = 0;
    br->bits = 0;
    br->bits_available = 0;
}

internal b32 bitreader_refill(BitReader* br) {
    while (br->bits_available <= 24 && br->byte_pos < br->size) {
        br->bits |= (u32)br->data[br->byte_pos++] << br->bits_available;
        br->bits_available += 8;
    }
    return br->bits_available > 0;
}

internal b32 bitreader_read(BitReader* br, u32 n, u32* out) {
    if (n == 0 || n > 24) {
        LOG_ERROR("png::bitreader", "invalid read length");
        return false;
    }
    if (!bitreader_refill(br)) {
        LOG_ERROR("png::bitreader", "bitreader refill failed");
        return false;
    }
    if (br->bits_available < n) {
        LOG_ERROR("png::bitreader", "not enough bits available for read");
        return false;
    }

    *out = br->bits & ((1u << n) - 1u);
    br->bits >>= n;
    br->bits_available -= n;
    return true;
}

internal void bitreader_align_to_byte(BitReader* br) {
    u32 skip = br->bits_available & 7u;
    if (skip) {
        br->bits >>= skip;
        br->bits_available -= skip;
    }
}

internal b32 bitreader_consume_bytes(BitReader* br, u32 count, u8* dst) {
    // if not byte aligned
    if ((br->bits_available & 7u) != 0) {
        LOG_ERROR("png::bitreader", "data is not byte aligned");
        return false;
    }

    u64 byte_pos = br->byte_pos - (br->bits_available / 8);
    if (!range_check(byte_pos, count, br->size)) {
        LOG_ERROR("png::bitreader", "data is not within range");
        return false;
    }

    if (count > 0) {
        memcpy(dst, br->data + byte_pos, count);
        byte_pos += count;
    }

    br->byte_pos = byte_pos;
    br->bits = 0;
    br->bits_available = 0;
    return true;
}

} // namespace ember
