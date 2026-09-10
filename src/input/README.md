# Input

Import `ember:input`. Read `app.input` during `update`; let `draw` render the
resulting game state.

```odin
if input.pressed(app.input, .Escape) {
    engine.request_quit(app)
}
if input.down(app.input, .W) {
    // Move using dt.
}
if input.mouse_down(app.input, .Left) {
    delta := app.input.mouse_delta // Displacement; don't multiply by dt.
}
```

## Behavior

- Keys: `down`, `pressed`, `released`. Mouse buttons: the same with `mouse_`.
- Queries are repeatable. Treat `app.input` as read-only.
- After each update, the engine calls `input.clear()`: press/release flags and
  movement/scroll deltas reset; held state, position, and focus remain.
- No update means input stays pending. Multiple updates see each press or delta
  only in the first update.
- A quick tap sets both press and release flags. Repeated taps coalesce;
  OS key repeat adds no presses. Keys identify physical controls, not typed text.

## Mouse and focus

| Field | Meaning |
| --- | --- |
| `mouse_position`, `mouse_delta` | Logical window units; origin top left, +X right, +Y down |
| `mouse_position_valid` | Cursor baseline is available |
| `scroll_delta` | Accumulated horizontal/vertical scroll units, including fractions |
| `focused` | Window has focus |

Focus loss releases held controls and cancels pending presses and deltas.
Unfocused input is ignored; the first cursor sample after refocus sets a baseline.

## Try it

See the [input example](../../examples/README.md#input).

```sh
odin test src/input
odin test src/engine -collection:ember=src
odin test src/platform/window
```

Test the registered GLFW callbacks using a hidden window:

```sh
odin run src/platform/window/test_input -collection:ember=src -out:/tmp/ember-window-input-smoke
```
