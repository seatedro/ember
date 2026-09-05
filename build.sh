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
    echo "  BUILD=release optimized build"
    echo "  BUILD=dist    aggressively optimized distribution build"
    echo ""
    echo "examples:"
    echo "  ./build.sh"
    echo "  BUILD=release ./build.sh"
    exit 0
}

case "${1:-}" in
    -h|--help) usage ;;
esac

BUILD="${BUILD:-debug}"
OUT_DIR="build/$BUILD"
ODIN_FLAGS="-collection:ember=src -collection:game=game -out:$OUT_DIR/game"

case "$BUILD" in
    debug)
        ODIN_FLAGS="$ODIN_FLAGS -debug -o:none"
        ;;
    release)
        ODIN_FLAGS="$ODIN_FLAGS -o:speed"
        ;;
    dist)
        ODIN_FLAGS="$ODIN_FLAGS -o:aggressive -disable-assert"
        ;;
    *)
        echo "error: unknown BUILD profile '$BUILD'" >&2
        exit 1
        ;;
esac

mkdir -p "$OUT_DIR"

echo "Building ember ($BUILD)"
odin build src/entrypoint $ODIN_FLAGS
echo "done: $OUT_DIR/game"
