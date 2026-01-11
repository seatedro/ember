#include "file.h"
#include "core/core.h"
#include <cstdio>
namespace ember {

EmberFile read_file_binary(Arena* arena, const char* path) {
    EmberFile result = {};

    FILE* f = fopen(path, "rb");
    if (!f) {
        LOG_ERROR("file", "failed to open: %s", path);
        return result;
    }
    defer(fclose(f));

    fseek(f, 0, SEEK_END);
    result.size = (u64)ftell(f);
    fseek(f, 0, SEEK_SET);

    result.data = Arena::alloc_array<u8>(arena, result.size);
    if (!result.data) {
        LOG_ERROR("file", "arena allocation failed for: %s", path);
        return result;
    }

    u64 read = fread(result.data, 1, result.size, f);
    result.success = (read == result.size);

    return result;
}

EmberFile read_file_text(Arena* arena, const char* path) {
    EmberFile result = read_file_binary(arena, path);
    if (result.success) {
        u8* null_term = Arena::alloc<u8>(arena);
        *null_term = '\0';
        result.size++;
    }
    return result;
}

b32 write_file(const char* path, const void* data, u64 size) {
    FILE* f = fopen(path, "wb");
    if (!f)
        return false;
    defer(fclose(f));

    u64 written = fwrite(data, 1, size, f);
    return written == size;
}

b32 file_exists(const char* path) {
    FILE* f = fopen(path, "rb");
    if (f) {
        fclose(f);
        return true;
    }
    return false;
}

u64 file_size(const char* path) {
    FILE* f = fopen(path, "rb");
    if (!f)
        return 0;
    defer(fclose(f));

    fseek(f, 0, SEEK_END);
    u64 size = (u64)ftell(f);
    return size;
}

} // namespace ember
