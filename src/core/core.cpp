#include "core.h"
#include <cstdarg>
#include <cstdio>
#include <cstdlib>
#include <cstring>

namespace ember {

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
