# Examples

Run from the repository root. `./build.sh` builds the default sphere demo.

## Input

```sh
./build.sh --example input
./build/debug/examples/input
```

- **Space:** change background while held.
- **Left drag / scroll:** log movement and scroll offsets.
- **Switch applications:** check focus handling.
- **Escape:** close.

Key and button presses/releases are logged. See [input behavior](../src/input/README.md).

## Indexed triangle

```sh
./build.sh --example triangle
./build/debug/examples/triangle
```

A colored triangle demonstrating indexed drawing, vertex attributes, depth
testing, and face culling.

- [main.odin](triangle/main.odin): engine callbacks.
- [triangle.odin](triangle/triangle.odin): buffers, pipeline, drawing, cleanup.
- [shaders/](triangle/shaders/): clip-space positions and interpolated color.

Examples use the shared engine loop and support the usual build profiles:

```sh
BUILD=release ./build.sh --example triangle
./build/release/examples/triangle
```

Check triangle rendering and cleanup:

```sh
odin run src/engine/test_gl -collection:ember=src -collection:game=examples/triangle -out:/tmp/ember-triangle-smoke
```
