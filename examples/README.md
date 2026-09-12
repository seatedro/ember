# Examples

Run from the repository root. `./build.sh` builds the default sphere demo:
left drag orbits, scroll zooms, `R` resets, `M` switches material colors, and Escape closes.
The game supplies geometry, camera, and transforms to the
[renderer](../src/renderer/renderer.odin), which submits GPU draws.
Each [material](../src/renderer/material.odin) owns an appearance buffer and references a shader.
The game creates explicit [pipelines](../src/renderer/pipeline.odin) for the sphere
and grid. Both sphere palettes share one pipeline; the grid uses colored line geometry.
Both draw through the same mesh/material API with layouts and render settings supplied by the game.
The demo loads the banded and grid shaders from `game/assets/shaders/` at runtime, so run it
from the repository root. The [shader library](../src/shaders/library.odin) owns
and reuses the compiled stages.
See [camera.odin](../src/camera/camera.odin) for the camera data and math.

## Input

```sh
./build.sh --example input
./build/debug/examples/input
```

- **Space:** change background while held.
- **Left drag / scroll:** log movement and scroll offsets.
- **Switch applications:** check focus handling.
- **Escape:** close.

Key and button presses/releases are logged. See [input.odin](../src/input/input.odin) for input behavior.

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
