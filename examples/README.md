# Examples

Run from the repository root. Set `BUILD=release` for optimized builds.

## Sphere

```sh
./build.sh
./build/debug/game
```

Drag to orbit, scroll to zoom, `R` to reset, `M` to swap colors, Escape to close.

## Input

```sh
./build.sh --example input
./build/debug/examples/input
```

Logs keyboard, mouse, and focus events. Hold Space to change the background;
Escape closes.

## Indexed triangle

```sh
./build.sh --example triangle
./build/debug/examples/triangle
```

Indexed drawing with depth testing and face culling.
