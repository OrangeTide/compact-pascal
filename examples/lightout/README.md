# Light's Out — Browser Game Example

A 5×5 Light's Out puzzle game compiled from Pascal to WASM, running entirely in the browser.

## Build and Run

```bash
make serve
```

Then open `http://localhost:8000/` in your browser.

## Gameplay

- Click (or tap) a cell to toggle it and its four orthogonal neighbors.
- Clear all lights to win.
- The game will play a fanfare and animate the header on victory.

## Architecture

- **lightout.pas** — Game logic and state, written in Compact Pascal.
  - Board state and level data stored as typed constants.
  - Game loop driven by pointer events and `requestAnimationFrame`.
  - Calls imported host functions for rendering and audio.

- **host.js** — JavaScript bridge providing canvas rendering, Web Audio tone generation, and pointer event handling.
  - Scales virtual 500×600 coordinate system to actual canvas size.
  - Handles `pointerdown` events and converts to virtual coordinates.
  - Instantiates the WASM module and wires imports/exports.

- **index.html** — Minimal HTML with a canvas element.

## Implementation Notes

### FFI Surface

The Pascal module exports three callbacks:

- `Init()` — Called after WASM instantiation. Initializes the board and draws the initial state.
- `HandleClick(vx, vy: integer)` — Called on pointer events with virtual coordinates.
- `StepAnimation(elapsedMs: integer): integer` — Called from `requestAnimationFrame` during win animation. Returns non-zero to request another frame.

The Pascal module imports five host functions:

- `CanvasClear(r, g, b: integer)` — Fill canvas with RGB color.
- `CanvasFillRect(x, y, w, h: integer; r, g, b: integer)` — Draw a filled rectangle in virtual coordinates.
- `AudioPlayTone(freqHz, durMs, offsetMs: integer)` — Schedule a sine-wave tone.
- `RequestAnimFrame()` — Request a `requestAnimationFrame` callback.
- `GetTimeMs(): integer` — Get milliseconds since module init.

### Coordinate System

All drawing uses a virtual 500×600 coordinate system. The host scales this to the actual canvas size via CSS.

- Header: y ∈ [0, 100] — displays the level number as "L##".
- Board: y ∈ [100, 600] — 5×5 grid with 100×100 cells.

### Audio

The fanfare is a sequence of tones scheduled via `AudioPlayTone`. Each call passes a frequency, duration, and offset relative to "now" at the time of the call. The host uses `AudioContext.currentTime` to schedule all tones at once, so the Pascal code does not block waiting for audio to finish.

The Web Audio API requires a user gesture to create or resume the `AudioContext`. The host creates the context on the first `pointerdown` event.

### Level Data

In this example, there is only one hardcoded level. A production version would store multiple level sets as typed-constant arrays in Pascal.

## Customization

- Edit `lightout.pas` to add more levels to `LevelInit` and increase `NumLevels`.
- Modify the fanfare by editing `FanfareFreqs` and `FanfareDurs` arrays.
- Adjust colors in `DrawBoard` and `DrawDigit` for different visual themes.

## Technical Details

- **Language:** Compact Pascal (Phase 1), compiled to WASM 1.0.
- **Module format:** Standard WASM with `host` import module for host functions.
- **Exports:** Procedures decorated with `{$EXPORT name}` become WASM module exports.
- **Imports:** Procedures decorated with `{$IMPORT 'module' name}` become WASM module imports.

See the [Compact Pascal Language Reference](../../doc/compact-pascal-ref.md) for FFI documentation.
