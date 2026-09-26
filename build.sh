#!/bin/sh

set -e

usage() {
    echo "usage: ./build.sh --example NAME [options]"
    echo ""
    echo "options:"
    echo "  -h, --help    show this help"
    echo "  --example NAME build the example in examples/NAME"
    echo "  --backend opengl|metal (default: metal on macOS, opengl elsewhere; Metal requires macOS 13+)"
    echo ""
    echo "environment:"
    echo "  BUILD=debug   (default) debug build"
    echo "  BUILD=release optimized build"
    echo "  BUILD=dist    aggressively optimized distribution build"
    echo ""
    echo "examples:"
    echo "  ./build.sh --example physics"
    echo "  BUILD=release ./build.sh --example physics"
    echo "  ./build.sh --example triangle"
    echo "  ./build.sh --backend metal --example triangle"
    echo ""
    exit 0
}

BACKEND="opengl"
if [ "$(uname -s)" = Darwin ]; then
    BACKEND="metal"
fi
EXAMPLE=""
while [ "$#" -gt 0 ]; do
    case "$1" in
        -h|--help) usage ;;
        --backend)
            if [ "$#" -lt 2 ]; then
                echo "error: --backend requires opengl or metal" >&2
                exit 1
            fi
            BACKEND="$2"
            shift 2
            ;;
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
OUT_DIR="build/$BUILD/$BACKEND"
LINK_DIR="build/$BUILD"
case "$BACKEND" in
    opengl) ;;
    metal)
        if [ "$(uname -s)" != Darwin ]; then
            echo "error: Metal requires macOS" >&2
            exit 1
        fi
        ;;
    *)
        echo "error: unknown backend '$BACKEND'" >&2
        exit 1
        ;;
esac
if [ -z "$EXAMPLE" ]; then
    echo "error: choose an example with --example NAME" >&2
    exit 1
fi
GAME_DIR="examples/$EXAMPLE"
if [ ! -f "$GAME_DIR/main.odin" ]; then
    echo "error: unknown example '$EXAMPLE'" >&2
    exit 1
fi
OUT_DIR="$OUT_DIR/examples"
TARGET="$EXAMPLE"
LINK_DIR="$LINK_DIR/examples"
LINK_TARGET="../$BACKEND/examples/$TARGET"
ODIN_FLAGS="-define:EMBER_BACKEND=$BACKEND -collection:ember=src -collection:game=$GAME_DIR -out:$OUT_DIR/$TARGET"

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

echo "Building ember $TARGET ($BUILD, $BACKEND)"
odin build src/entrypoint $ODIN_FLAGS
mkdir -p "$LINK_DIR"
ln -sfn "$LINK_TARGET" "$LINK_DIR/$TARGET"
echo "done: $LINK_DIR/$TARGET -> $LINK_TARGET"
