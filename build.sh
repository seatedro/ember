#!/bin/sh

set -e

usage() {
    echo "usage: ./build.sh [options]"
    echo ""
    echo "options:"
    echo "  -h, --help    show this help"
    echo ""
    echo "environment:"
    echo "  BUILD=debug   (default) debug build"
    echo "  BUILD=release release build with -O2"
    echo "  BUILD=dist    distribution build with -O3 -flto"
    echo ""
    echo "examples:"
    echo "  ./build.sh"
    echo "  BUILD=release ./build.sh"
    exit 0
}

case "${1:-}" in
    -h|--help) usage ;;
esac

CXX="clang++"

if [ "$(uname)" = "Darwin" ]; then
    LIBS="$(pkg-config --libs glfw3) -framework OpenGL -framework Cocoa -framework IOKit -lpthread -lm"
else
    LIBS="-lglfw -lGL -lpthread -ldl -lm"
fi

CFLAGS="-std=c++23 -Wall -Wextra -Werror"
CFLAGS="$CFLAGS -DEMBER_RHI_OPENGL"
CFLAGS="$CFLAGS -fno-exceptions -fno-rtti"
CFLAGS="$CFLAGS -Isrc -Ivendor/glfw/include -Ivendor/glad/include -Ivendor/imgui"

BUILD="${BUILD:-debug}"
if [ "$BUILD" = "debug" ]; then
  CFLAGS="$CFLAGS -O0 -g -DEMBER_DEBUG"
  # CFLAGS="$CFLAGS -fsanitize=address,undefined -fno-omit-frame-pointer"
  # CFLAGS="$CFLAGS -fsanitize-ignorelist=asan_ignorelist.txt"
  # LIBS="$LIBS -fsanitize=address,undefined"
elif [ "$BUILD" = "release" ]; then
  CFLAGS="$CFLAGS -O2 -DNDEBUG"
elif [ "$BUILD" = "dist" ]; then
  CFLAGS="$CFLAGS -O3 -flto -DNDEBUG -DEMBER_DIST"
  if [ "$(uname)" = "Darwin" ]; then
    LIBS="$LIBS -Wl,-dead_strip"
  else
    CFLAGS="$CFLAGS -ffunction-sections -fdata-sections"
    LIBS="$LIBS -Wl,--gc-sections -s"
  fi
fi

OUT_DIR="build/$BUILD"
mkdir -p "$OUT_DIR"

VENDOR_CFLAGS="-Ivendor/glad/include -Ivendor/imgui"
VENDOR_CFLAGS="$VENDOR_CFLAGS -w"

VENDOR_C="vendor/glad/src/glad.c"
VENDOR_OBJS=""
for src in $VENDOR_C; do
    obj="$OUT_DIR/$(basename ${src%.c}.o)"
    $CC -c $VENDOR_CFLAGS $src -o $obj
    VENDOR_OBJS="$VENDOR_OBJS $obj"
done

echo "Building ember ($BUILD)"

SRCS=$(fd -e cpp . src game)

$CXX $CFLAGS $SRCS $VENDOR_OBJS -o "$OUT_DIR/game" $LIBS

echo "done: $OUT_DIR/game"
