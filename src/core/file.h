#pragma once

#include "core.h"

namespace ember {

struct EmberFile {
    u8* data;
    u64 size;
    b32 success;
};

EmberFile read_file_binary(Arena* arena, const char* path);
EmberFile read_file_text(Arena* arena, const char* path);
b32       write_file(const char* path, const void* data, u64 size);
b32       file_exists(const char* path);
u64       file_size(const char* path);

} // namespace ember
