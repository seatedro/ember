#pragma once

#include "core/core.h"

namespace ember {

struct Image {
    u8* pixels;
    u32 width;
    u32 height;
    u32 channels;
    u32 stride;
};

template <typename T>
inline T read_le(const u8* p);

template <>
inline u16 read_le<u16>(const u8* p) {
    return (u16)p[0] | ((u16)p[1] << 8);
}

template <>
inline u32 read_le<u32>(const u8* p) {
    return (u32)p[0] | ((u32)p[1] << 8) | ((u32)p[2] << 16) | ((u32)p[3] << 24);
}

template <typename T>
inline T read_be(const u8* p);

template <>
inline u16 read_be<u16>(const u8* p) {
    return (u16)((u16)p[0] << 8) | (u16)p[1];
}

template <>
inline u32 read_be<u32>(const u8* p) {
    return ((u32)p[0] << 24) | ((u32)p[1] << 16) | ((u32)p[2] << 8) | (u32)p[3];
}

Image load_bmp(Arena* arena, const u8* data, u64 size);
Image load_png(Arena* arena, const u8* data, u64 size);
Image load_img(Arena* arena, const char* path);

} // namespace ember
