#!/bin/sh

set -e

usage() {
    echo "usage: ./build.sh [options]"
    echo ""
    echo "options:"
    echo "  -h, --help    show this help"
    echo "  --example NAME build an example from examples/NAME"
    echo ""
    echo "environment:"
    echo "  BUILD=debug   (default) debug build"
    echo "  BUILD=release optimized build"
    echo "  BUILD=dist    aggressively optimized distribution build"
    echo ""
    echo "examples:"
    echo "  ./build.sh"
    echo "  BUILD=release ./build.sh"
    echo "  ./build.sh --example triangle"
    exit 0
}

EXAMPLE=""
while [ "$#" -gt 0 ]; do
    case "$1" in
        -h|--help) usage ;;
        --example)
            if [ "$#" -lt 2 ]; then
                echo "error: --example requires a name" >&2
                exit 1
            fi
            EXAMPLE="$2"
            case "$EXAMPLE" in
                ''|*[!a-zA-Z0-9_-]*)
                    echo "error: invalid example name '$EXAMPLE'" >&2
                    exit 1
                    ;;
            esac
            shift 2
            ;;
        *)
            echo "error: unknown option '$1'" >&2
            exit 1
            ;;
    esac
done

BUILD="${BUILD:-debug}"
OUT_DIR="build/$BUILD"
GAME_DIR="game"
TARGET="game"
if [ -n "$EXAMPLE" ]; then
    GAME_DIR="examples/$EXAMPLE"
    if [ ! -f "$GAME_DIR/main.odin" ]; then
        echo "error: unknown example '$EXAMPLE'" >&2
        exit 1
    fi
    OUT_DIR="$OUT_DIR/examples"
    TARGET="$EXAMPLE"
fi
ODIN_FLAGS="-collection:ember=src -collection:game=$GAME_DIR -out:$OUT_DIR/$TARGET"

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

echo "Building ember $TARGET ($BUILD)"
odin build src/entrypoint $ODIN_FLAGS
echo "done: $OUT_DIR/$TARGET"
