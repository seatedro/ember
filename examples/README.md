# Examples

Run these commands from the repository root.

## Indexed triangle

```sh
./build.sh --example triangle
./build/debug/examples/triangle
```

`triangle/main.odin` supplies the engine callbacks. `triangle/triangle.odin`
creates vertex and index buffers, describes the vertex layout, links the
shaders, draws, and releases the resources. Its GLSL sources live in
`triangle/shaders/`.

The triangle uses three positions with vertex colors and the indices `[0, 1, 2]`.
Its vertex shader writes positions directly into clip coordinates; the fragment
shader displays the interpolated color. This makes it a small reference for
indexed drawing, shader inputs, depth testing, and face culling.

The build selects this directory as the `game` collection and uses the shared
`src/entrypoint` and engine loop. `./build.sh` builds the default sphere demo
from `game/`. Build profiles also apply to examples:

```sh
BUILD=release ./build.sh --example triangle
./build/release/examples/triangle
```

The existing engine smoke test can exercise the example's rendering and cleanup:

```sh
odin run src/engine/test_gl -collection:ember=src -collection:game=examples/triangle -out:/tmp/ember-triangle-smoke
```
