# Examples

Run from the repository root. Set `BUILD=release` for optimized builds.

## Sphere

```sh
./build.sh --backend opengl --example sphere
./build/debug/examples/sphere
```

Drag to orbit, scroll to zoom, `R` to reset, `M` to swap colors, Escape to close.

## Input

```sh
./build.sh --backend opengl --example input
./build/debug/examples/input
```

Logs keyboard, mouse, and focus events. Hold Space to change the background;
Escape closes.

## Indexed triangle

```sh
./build.sh --backend opengl --example triangle
./build/debug/examples/triangle
```

Indexed drawing with depth testing and face culling.

## Metal (macOS 13+)

```sh
./build.sh --backend metal
./build/debug/metal/game
./build.sh --backend metal --example sphere
./build/debug/metal/examples/sphere
```
