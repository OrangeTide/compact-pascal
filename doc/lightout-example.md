# Light's Out — Browser Game Example (Design Doc)

**Status:** Blocked — waiting on const array literals in Compact Pascal. Design is settled; implementation is on hold until the compiler can initialize array constants from a literal list. See [Blockers](#blockers).

## Blockers

This example cannot be implemented cleanly with the current Phase 1 compiler. Three pieces of static data need aggregate array initialization:

- **Level set** — 50 levels × 25 cells, encoded as a flat bit array (1,600 bits padded, 32 bits per row for cheap indexing). See [Level Data Encoding](#level-data-encoding).
- **Seven-segment glyph table** — `array[0..17] of array[0..6] of boolean` (digits 0–9, `L`, and 7 single-segment entries for the snake animation). See [Rendering Model](#rendering-model).
- **Fanfare** — paired `array[0..N-1] of integer` for frequencies and durations. See [Fanfare](#fanfare).

Each of these is workable today by filling the array by index at startup (`InitFanfare`-style), but doing it for all three pieces turns the example into a wall of assignment statements that obscures the actual game. The example is meant to read clearly and show off the language; deferring until literals land is the right call.

**Unblocked by:** a const / typed-constant form of the shape `const foo: array[0..N-1] of T = (v0, v1, ..., vN-1);`. This is a Turbo Pascal / Delphi feature and a natural extension of the existing typed-constant mechanism. When it lands, all three workarounds above collapse to single declarations and the example proceeds.

## Purpose

A working Light's Out puzzle that runs in a browser, written in Compact Pascal and compiled to WASM, using JavaScript only as a thin host for canvas, audio, and pointer events. The example demonstrates the full Phase 1 FFI pipeline: `{$IMPORT}`, `{$EXPORT}`, arrays, constants, and a frame-driven game loop. Target reader: someone skimming the repo to decide whether Compact Pascal is real.

Based on Jon's 2009 X11/Cairo implementation at [lightout.git](git//ocelot.rm-f.net/~jon/game/lightout.git). This browser port drops the dirty-rect tracking, shaped-window masks, and keyboard input — the game loop shrinks by roughly half.

## Scope

- **Full original level set** — all ~50 levels from the 2009 C implementation, preserved verbatim. The 1995 Tiger Electronics handheld fit them in a glop-top microcontroller; 1,250 bits of level data is a rounding error on the modern web.
- **5×5 grid**, tap/click a cell to toggle it and its four orthogonal neighbors, clear the grid to advance.
- **Mouse and touch input only** — unified via pointer events. Works on desktop and mobile browsers without separate code paths.
- **Seven-segment LED header** showing the level number as `L##`, rendered from the glyph table in the clock example (elem0..elem6 layout, 7 filled rectangles per digit). Some animation of the level display on win, perhaps an LED snaking pattern or simply flashing '---' (TBD)
- **Pascal-implemented fanfare** on win — Pascal calls `AudioPlayTone(freq, durationMs, offsetMs)` repeatedly, JS schedules them against `AudioContext.currentTime`.

Out of scope (deferred or declined):
- Keyboard navigation and highlight cursor (C version had arrow keys + select).
- Dirty-rect rendering (Canvas is double-buffered; full redraw on each state change is trivial at 5×5).
- Shaped-window masks (X11-specific, meaningless on the web).
- Persistent level progress across reloads (would need `localStorage` import; not worth it for an example).
- Level editor UI.

## Architecture

```
+-------------------+       exports              +-------------------+
|                   |  init, handleClick,        |                   |
|   lightout.pas    |  stepAnim, requestFrame    |     host.js       |
|   (compiled       | -------------------------> |  (canvas, audio,  |
|    to WASM)       |                            |   pointer events) |
|                   | <------------------------- |                   |
|                   |  imports                   |                   |
|                   |  canvasFillRect,           |                   |
|                   |  canvasClear,              |                   |
|                   |  audioPlayTone,            |                   |
|                   |  requestAnimFrame          |                   |
+-------------------+                            +---------+---------+
                                                           |
                                                           v
                                                 +-------------------+
                                                 |   index.html      |
                                                 |   <canvas>        |
                                                 +-------------------+
```

Pascal owns all game state: the 5×5 board, current level number, and win-animation phase. JS owns no game logic — it is a pure transport layer between WASM and browser APIs.

## Files

```
examples/lightout/
  lightout.pas     — game logic, rendering, input handling, level data (~200 lines)
  host.js          — canvas + audio + pointer event glue (~80 lines)
  index.html       — canvas scaffold and module loader (~25 lines)
  Makefile         — build lightout.wasm, optional `make serve` for local HTTP
  README.md        — build and run instructions
```

## Level Data Encoding

**Decision: pascal source level encoding. Re-encode our original strings as an array of bits (booleans?). **

Reason:
- self-contained. the pascal code has everything needed, we don't hide behind our JavaScript runtime.
- a single dimension flat array so we don't wait for multi-dimensional arrays support.
- a realistic implementation in Pascal's heyday would use 32 bits per row to make indexing the array cheap.
- TP-style short strings max at 255 chars. We can't use a more concise encoding for this data like the C version did.

**Mechanism:**

1. lightout.pas has a const array of 1250 bits, padded to 1600 bits (32-bit per level). TBD: do we index booleans one bit at a time, or just grab an Integer and shift through the bits? the latter means our const array can encode each level as a single hexadecimal. but it's a little obtuse to the reader.
2. `host.js` doesn't have to do anything special about our level data. It keeps the host.js pretty generic and focused on canvas and drawing.

**NOTE** this depends on const array literals landing in Compact Pascal.

## Rendering Model

Pascal draws by calling host-provided rectangle primitives. No path API, no text API, no images. The entire game can be drawn with filled rectangles.

**Coordinate system:** Pascal works in a virtual 500×600 coordinate space (500 wide × 600 tall). The host scales this to the actual canvas size in CSS pixels. This keeps Pascal arithmetic in integers and decouples the game from device pixel ratio.

**Layout:**
- Header: y ∈ [0, 100] — seven-segment `L##` centered.
- Board: y ∈ [100, 600] — 5×5 grid, each cell 100×100 virtual units.

**Seven-segment LED glyphs** (from the clock example):

```
    +-- elem0 --+
    |           |
  elem1       elem2
    |           |
    +-- elem3 --+
    |           |
  elem4       elem5
    |           |
    +-- elem6 --+
```

Glyph table: `array[0..10] of array[0..6] of boolean`, indices 0–9 for digits, index 10 for `L`. Each digit is drawn as up to seven `CanvasFillRect` calls for the seven segments. `ord('5') - ord('0') = 5` gives a natural mapping, with `L` hardcoded as index 10.

for the win animation add 
[LED_ELEM0] = {1,0,0,0,0,0,0},
[LED_ELEM1] = {0,1,0,0,0,0,0},
[LED_ELEM2] = {0,0,1,0,0,0,0},
[LED_ELEM3] = {0,0,0,1,0,0,0},
[LED_ELEM4] = {0,0,0,0,1,0,0},
[LED_ELEM5] = {0,0,0,0,0,1,0},
[LED_ELEM6] = {0,0,0,0,0,0,1},

then "snake" animation is 0,1,2,4,5,6 for the left-most and right-most LEDs. and the opposite sequence for the middle LED.

**Full redraw on state change.** Pascal calls a `Redraw` procedure that clears the canvas and re-emits every rectangle. Triggered by:
- `Init` completing.
- `HandleClick` producing a valid move.
- `StepAnimation` during the win sequence.

No diff, no dirty flags. At 5×5 cells plus a 3-digit header, a full redraw is well under a hundred rectangle calls.

## Input Model

**Pointer events only.** The host registers `pointerdown` on the canvas, which unifies mouse, touch, and pen on every modern browser. It explicitly does not register separate `click`, `mousedown`, or `touchstart` handlers — mixing them causes double-fire on mobile.

**CSS must include `touch-action: none` on the canvas** to prevent the browser from intercepting touches for scrolling or pinch-zoom. The host also calls `event.preventDefault()` in the handler for belt-and-suspenders.

**Flow:**

1. Browser fires `pointerdown` on canvas.
2. Host converts event coordinates to Pascal's virtual space using `getBoundingClientRect()`.
3. Host calls exported `HandleClick(vx: integer, vy: integer)`.
4. Pascal computes grid cell from `vx, vy`, ignoring out-of-range values. If the click is inside the board, it calls `DoMove(col, row)` which toggles the cell and its four neighbors.
5. Pascal calls `Redraw` and `CheckWin`.

## Win Sequence and Animation

The C version used `sleep(1)` between animation frames. The browser cannot block — the main thread must return to the event loop to repaint. Animation is driven by `requestAnimationFrame`.

touch/click and requestAnimationFrame plumbing makes the Pascal side event driven.

We can also have Pascal side send a hint to the host.js that we're idle or performing animation. This can put the brakes on sending requestAnimationFrame requests and limit updates to only events.
making our app a little more efficient. it's a puzzle game, 95% of the time we're idle waiting for the user input.

**State machine:**
- `stPlay` — normal gameplay.
- `stWinAnim` — win detected, fanfare playing and win pattern cycling.
- `stAdvance` — fanfare done, load next level, transition back to `stPlay`.

**When `CheckWin` returns true:**
1. Pascal sets state to `stWinAnim`, records start time.
2. Pascal emits the fanfare: a sequence of `AudioPlayTone(freq, durationMs, offsetMs)` calls covering the full tune. JS queues them all at once against `AudioContext.currentTime` — Pascal does not block waiting for tones to finish.
3. Pascal calls `RequestAnimFrame()` (imported). JS sets up a `requestAnimationFrame` loop that calls back into exported `StepAnimation(elapsedMs: integer)`.
4. `StepAnimation` computes the current win-pattern frame (0..N), redraws, and returns a boolean: should the host schedule another frame?
5. When the animation is complete, Pascal increments the level, reloads the board, returns `false` from `StepAnimation`, and JS stops the rAF loop.

This splits the loop control cleanly: Pascal owns the animation logic and frame count, JS owns the rAF pump.

## Fanfare

A short melody implemented directly in Pascal as a sequence of `AudioPlayTone` calls. Notes are expressed as `(frequencyHz, durationMs)` pairs iterated over a typed constant array. Offset accumulates as the loop progresses.

```pascal
procedure PlayFanfare;
var
  i, offset: integer;
begin
  offset := 0;
  for i := 0 to FanfareLength - 1 do begin
    AudioPlayTone(FanfareFreqs[i], FanfareDurs[i], offset);
    offset := offset + FanfareDurs[i];
  end;
end;
```

Since Compact Pascal has no array aggregate literals, `FanfareFreqs` and `FanfareDurs` are `array[0..N-1] of integer` filled at init time by a short `InitFanfare` procedure that writes each element by index. Ugly but honest, and advertises a real TP-compat gap for future work. (When array literals land, this collapses to one const.)

## FFI Surface

### Imports (JS → Pascal)

Module name for all imports: `host`.

| Pascal declaration | Description |
|---|---|
| `procedure CanvasClear(r, g, b: integer); external;` | Fill the entire canvas with RGB (each component 0–255). |
| `procedure CanvasFillRect(x, y, w, h: integer; r, g, b: integer); external;` | Fill a rectangle in virtual coordinates. |
| `procedure AudioPlayTone(freqHz, durMs, offsetMs: integer); external;` | Schedule a sine-wave tone. `offsetMs` is relative to "now" at the time of the call. |
| `procedure RequestAnimFrame; external;` | Ask the host to call `StepAnimation` on the next frame. Idempotent within a frame. |
| `function GetTimeMs: integer; external;` | Milliseconds since module init. Monotonic. Used for animation timing. |

### Exports (Pascal → JS)

| Export | Description |
|---|---|
| `Init` | Called once after the module is instantiated. Loads level 0, performs initial redraw. Level data, glyph table, and fanfare arrays are all Pascal-side constants; no host copying step. |
| `HandleClick(vx, vy: integer)` | Called on `pointerdown`. Coordinates in virtual space. |
| `StepAnimation(elapsedMs: integer): integer` | Called from rAF loop during win sequence. Returns non-zero to request another frame. |

The `integer`-for-boolean return on `StepAnimation` is because Phase 1 WASM export type mapping for `boolean` should be verified before we assume it round-trips. Using `integer` is safe.

## Memory Layout

Standard Phase 1 layout:
- Nil guard (4 bytes).
- Data segment: string constants, level bit array (const), glyph table (const), fanfare arrays (const), board state, current level, animation state.
- Stack grows down from top.
- No heap — no `new` in Phase 1.

All static data lives in Pascal-side constants. No JS-visible address exports and no shared-memory writes from the host are required.

## Build

`Makefile` targets:
- `lightout.wasm` — compile `lightout.pas` using the fpc-bootstrapped compiler.
- `serve` — start a local HTTP server (`python3 -m http.server`) in `examples/lightout/` because modern browsers block `fetch()` from `file://`.
- `clean` — remove `lightout.wasm`.

`README.md` gives a one-line run instruction: `make serve` then open `http://localhost:8000/`.

## Pressure Points Worth Flagging

1. **Static data without aggregate literals.** Levels, glyph table, and fanfare all want `const foo: array[...] of T = (...)`. Writing three `InitXxx` procedures that assign every element by index is the only workaround available in Phase 1, and doing it three times buries the game logic under setup noise. This is why the example is blocked — see [Blockers](#blockers).

2. **Audio context gesture requirement.** Modern browsers refuse to start an `AudioContext` until a user gesture. The host must create and resume the audio context inside the first `pointerdown` handler, not at page load. Easy to get wrong; will be caught on first touch if not handled.

3. **Coordinate scaling on high-DPI.** The canvas's CSS size and backing-store size differ on Retina/mobile. Host must scale event coordinates by the ratio of CSS size to virtual size (500×600), not the backing store. `getBoundingClientRect()` gives the CSS rect — that is what to use.

4. **Canvas state between frames.** Canvas 2D preserves pixels between frames (it is not cleared automatically). Full redraw starts with `CanvasClear`. Don't skip that.

## Open Questions

1. **Do `{$EXPORT}`-ed `var` arrays export an address?** The ref documents exporting procedures and functions; variable exports may be a Phase 2 item. No longer gating for this example now that level data is a Pascal-side const, but the answer is worth knowing — if `var` arrays don't export directly, the fallback is a `GetLevelBufferAddr()`-style accessor function (works regardless).
2. **Does `{$IMPORT 'host' name}` work with a module name of `host`?** The tutorial uses `wasi_snapshot_preview1`; `host` should behave the same, but worth a 5-line smoke test before wiring up the full import surface.
3. **Seven-segment header, or drop it?** The letter `L` is the only non-digit glyph needed, and a full 11-entry glyph table (plus 7 snake-animation entries) is a chunky const. If it feels heavy once const array literals land, dropping the header and putting the level number in the page title is an option. Decide after first implementation attempt.
4. **Restart button?** Cheap addition, increases the example's friendliness. Probably yes, as a second `{$EXPORT}` called from an HTML `<button>`.

## Build Order

Gated on const array literals landing in Compact Pascal. Once that feature ships:

1. Verify `{$IMPORT 'host' name}` works with a 20-line stub (Open Question #2).
2. Write `host.js` and `index.html` against a stub `lightout.pas` that draws a single red rectangle on click. Confirm the pointer event path end-to-end.
3. Add seven-segment rendering and the board grid. No game logic yet.
4. Add `HandleClick` → `DoMove` → win detection. Levels hard-coded to one level.
5. Add the full level set as a const bit array; wire up level advance.
6. Add fanfare and win animation.
7. Polish, `README.md`, final cross-browser test (Chrome, Firefox, Safari, mobile Safari).

Each step is runnable and visibly correct before moving to the next.
