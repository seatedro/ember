# Camera

`Camera` stores position and quaternion orientation in world space. Use
`orientation = 1` for identity: +X right, +Y up, looking along -Z.

```odin
pose := camera.from_orbit(camera.Orbit {
    target = {0, 0, 0},
    yaw = 0.5,
    pitch = 0.2,
    distance = 4,
})
view := camera.view(pose)
projection := emath.perspective(fov_y, aspect, near, far)
mvp := projection * view * model
```

- `view` inverts the pose: rotation becomes `Rᵀ`, translation becomes `-Rᵀ * position`.
- `Orbit` stores target, yaw, pitch, and positive distance. Angles are radians.
- `from_orbit` derives the pose. Input bindings and navigation limits belong to the caller.
- Projection stays separate. Supply the aspect ratio of the rendering target.

The [sphere demo](../../game/camera.odin) maps left drag to orbit, scroll to zoom,
and `R` to reset. Run `./build.sh` then `./build/debug/game` from the repo root.

```sh
odin test src/core/math
odin test src/camera
odin test game -collection:ember=src
odin run src/camera/test_gl -collection:ember=src -collection:game=game -out:/tmp/ember-camera-smoke
```
