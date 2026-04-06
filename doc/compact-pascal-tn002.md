---
title: "TN-002: A 3D Graphics and Multimedia Library for Compact Pascal"
author: Jon Mayo
date: April 2026
---

## Overview

This note proposes a 3D graphics and multimedia library for Compact Pascal.  The library provides real-time rendering, audio playback, and input handling through a set of WASM imports backed by sokol on the host side.  The API is small enough for a newcomer to learn alongside the language, yet capable enough for interactive 3D applications: games, simulations, data visualization, model viewers, and demoscene productions.

The target capability level is roughly that of mid-1990s hardware (PlayStation, Nintendo 64, early PC 3D accelerators) -- vertex-colored and textured geometry, a fixed set of shipped shaders, no mandatory shader authoring.

## Design Principles

- **Small surface.**  Approximately 64 WASM imports plus 13 Pascal-side functions.  A programmer can read the full API in one sitting.

- **No shader authoring required.**  Shipped shader units cover the common rendering modes.  Custom shaders are supported but never mandatory.

- **Modular.**  Programs link only the shader units they need.  Adding a new rendering mode means adding a `.glsl` file and regenerating -- no changes to the core API.

- **Portable.**  The same Pascal source runs on every Compact Pascal host: Rust/wasmi, Zig/wasm3, and browser/JS.  The host implements the imports; the Pascal program is unaware of the backend.

- **Callback-driven lifecycle.**  The host owns the event loop.  Pascal provides `OnInit`, `OnFrame`, and `OnCleanup` callbacks.  This model works identically on native platforms (OS event loop) and in the browser (`requestAnimationFrame`).

## Architecture

```
 Pascal program
       |
       v
 Library imports   (~64 WASM imported functions)
       |
       v
 Host runtime      (Rust, Zig, or JS)
       |
       v
 sokol_gfx         (abstracts GL / Metal / Vulkan / WebGPU / D3D)
 sokol_audio        (cross-platform audio mixer)
```

The Pascal program calls imported functions.  The host implements those imports by driving sokol.  Pascal code never sees sokol types, shader objects, GPU buffers, or pipeline state directly.

### Why sokol

sokol_gfx is a small, single-header C library that abstracts over every major GPU backend.  It handles the portability problem (GL 3.3, GLES3/WebGL2, Metal, D3D11, Vulkan, WebGPU) so the host runtimes don't have to.

Shaders are compiled offline by **sokol-shdc** (which uses SPIRV-Cross internally) from annotated GLSL into a C header containing bytecode or source for every backend.  No runtime shader compilation.

### Why not Raylib

Raylib's `rlgl` layer solves the same batched-immediate-mode problem and is a useful reference for implementation.  However, binding to Raylib means inheriting its architectural decisions, dependency tree, and update cadence.  Building our own abstraction on sokol gives us control over the API surface and keeps the host-side code auditable.  We may end up in a similar place, but we get there on our own terms.

## Application Lifecycle

The application uses a callback model inspired by sokol_app's `frame_cb`.  The Pascal program defines callback procedures; the host runtime owns the event loop and calls them at the appropriate times.  This works identically on native (where the host runs a platform event loop) and in the browser (where the host hooks `requestAnimationFrame`).  No ifdefs, no per-platform code in Pascal.

GLUT popularized callbacks for input and reshape but missed the main render callback -- this library does not repeat that omission.

```pascal
program Wireframe;

uses ShaderVertexColor, AppInput;

procedure OnInit;
begin
  { load data, set initial state }
end;

procedure OnFrame;
var dt: real;
begin
  dt := GetDeltaTime;
  if KeyDown(KEY_ESCAPE) then Quit;

  ClearColor(0.1, 0.1, 0.2);
  ClearDepth;
  SetProjection(60.0, GetAspect, 0.1, 100.0);
  { draw scene }
end;

procedure OnCleanup;
begin
  { free resources }
end;

begin
  SetWindowTitle('Wireframe Viewer');
  SetWindowSize(640, 480);
  Run(OnInit, OnFrame, OnCleanup);
end.
```

`Run` hands control to the host runtime and never returns.  On native, it enters the platform event loop.  In the browser, it registers the frame callback with `requestAnimationFrame`.  The three callbacks are WASM exports that the host invokes.

### Lifecycle callbacks

| Callback    | Called                              |
|-------------|-------------------------------------|
| `OnInit`    | Once, after window/context creation |
| `OnFrame`   | Every frame                         |
| `OnCleanup` | Once, before shutdown               |

All three are passed to `Run` as procedure parameters.  The host guarantees `OnInit` runs before the first `OnFrame`, and `OnCleanup` runs after the last.

### Window and frame queries

| Function | Purpose |
|----------|---------|
| `SetWindowTitle(title)` | Set window title (call before `Run`) |
| `SetWindowSize(w, h)` | Set window size (call before `Run`) |
| `Run(init, frame, cleanup)` | Enter main loop -- does not return |
| `Quit` | Signal the host to exit after this frame |
| `SetTargetFPS(fps)` | Frame rate cap |
| `GetDeltaTime: real` | Seconds since last frame |
| `GetFPS: integer` | Current frame rate |
| `GetWindowWidth: integer` | Current width in pixels |
| `GetWindowHeight: integer` | Current height in pixels |
| `GetAspect: real` | Width / height |

Configuration calls (`SetWindowTitle`, `SetWindowSize`) are made in the program body before `Run`.  They set parameters that the host reads when creating the window.  Calling them after `Run` has no effect.

## Rendering Model

### Immediate-mode surface, batched internally

The Pascal-facing API looks like classic immediate mode:

```pascal
BindTexture(wallTex);
BindShader(ShaderGouraud.Shader);
BeginTriangles;
  Color3f(1.0, 0.8, 0.6);
  TexCoord2f(0.0, 0.0); Vertex3f(-1, -1, 0);
  TexCoord2f(1.0, 0.0); Vertex3f( 1, -1, 0);
  TexCoord2f(0.5, 1.0); Vertex3f( 0,  1, 0);
EndTriangles;
```

Internally, `BeginTriangles` opens a new vertex buffer (or sub-range of a large buffer).  Each `Vertex3f` call appends a vertex with the current color, texcoord, and normal state.  `EndTriangles` (or a state change like `BindTexture`) flushes the batch as a single sokol draw call.

This gives the simplicity of `glBegin`/`glEnd` with the performance of buffered submission.  The batching logic lives in the host, not in Pascal -- the WASM imports are just `vertex3f(x, y, z)` etc.

### Draw primitives

| Begin command      | Topology        |
|--------------------|-----------------|
| `BeginTriangles`   | Triangle list   |
| `BeginQuads`       | Quad list (host splits to triangles) |
| `BeginLines`       | Line list       |
| `BeginLineStrip`   | Line strip      |
| `BeginPoints`      | Point list      |

### State commands

These set per-vertex or per-batch state.  They are sticky until changed (like GL immediate mode):

| Command                              | Scope     |
|--------------------------------------|-----------|
| `Color3f(r, g, b)`                   | vertex    |
| `Color4f(r, g, b, a)`               | vertex    |
| `TexCoord2f(u, v)`                   | vertex    |
| `Normal3f(nx, ny, nz)`              | vertex    |
| `BindTexture(id)`                    | batch     |
| `BindShader(id)`                     | batch     |

### Scissor test

WebGL-style scissor rectangle for clipping.  Useful for viewports, text regions, split-screen layouts, UI panels, etc.

```pascal
EnableScissor;
Scissor(x, y, width, height);
{ draw calls here are clipped to the rectangle }
DisableScissor;
```

| Command                              | Purpose                        |
|--------------------------------------|--------------------------------|
| `EnableScissor`                      | Enable scissor test            |
| `DisableScissor`                     | Disable scissor test           |
| `Scissor(x, y, w, h)`               | Set scissor rectangle (pixels) |

Maps directly to sokol's `sg_apply_scissor_rect`.  Coordinates are in pixels, origin at top-left.

### Transform stack

Minimal matrix stack, enough for hierarchical models:

```pascal
SetProjection(fov, aspect, near, far);
SetCamera(eyeX, eyeY, eyeZ, targetX, targetY, targetZ, upX, upY, upZ);
PushMatrix;
  Translate(x, y, z);
  RotateY(angle);
  Scale(s, s, s);
  { draw calls here use the composed transform }
PopMatrix;
```

Matrix math runs in Pascal via the `MathVec` unit (see Matrix and Vector Math section).  The composed matrix is passed to the host as 16 floats when a batch is flushed.  The stack depth is fixed (16 or 32 levels -- sufficient for any reasonable scene graph).

## Shader Pipeline

```
 .glsl (annotated GLSL)
       |  sokol-shdc
       v
 .h (C header with all backend variants as byte arrays)
       |  shader2pas
       v
 .pas unit (Pascal unit exporting a shader identifier)
```

### sokol-shdc step

Standard sokol workflow.  Write one `.glsl` file per shader with `@vs`, `@fs`, `@program` annotations.  sokol-shdc produces a C header containing GLSL 330, GLSL 300es, HLSL, MSL, SPIR-V, and WGSL variants as embedded arrays.

### shader2pas step

A small tool (custom to this project) that reads the sokol-shdc output and generates a Pascal unit.  Each unit exports a typed constant or variable that the library recognizes as a shader handle.  Example:

```pascal
unit ShaderGouraud;
{ Auto-generated by shader2pas -- do not edit }

interface

var
  Shader: TShaderID;  { populated at init by the host runtime }

implementation
end.
```

The host runtime maps shader identifiers to the actual compiled pipeline objects at initialization.  The Pascal side only ever holds an opaque handle.

### Modularity

Users `uses` only the shader units they need:

```pascal
uses ShaderGouraud, ShaderTexturedFog;
```

This keeps the compiled WASM small (unused shaders are not linked) and makes the available feature set explicit in the source.  Adding a new rendering mode means adding a new `.glsl` file and regenerating -- no changes to the core library.

### Shipped shaders

A small set of built-in shaders covers the common rendering modes:

| Unit name             | Features                             |
|-----------------------|--------------------------------------|
| `ShaderVertexColor`   | Per-vertex color, no texture         |
| `ShaderGouraud`       | Textured + per-vertex color          |
| `ShaderGouraudFog`    | Textured + per-vertex color + fog    |
| `ShaderGouraudLit`    | Textured + per-vertex color + vertex lighting |
| `ShaderUnlit`         | Textured, no lighting or vertex color |
| `ShaderMSDF`          | MSDF text rendering (see Text Rendering) |
| `ShaderBitmapFont`    | Bitmap font fallback                 |

Users who want custom shaders write `.glsl`, run sokol-shdc + shader2pas, and `uses` the resulting unit.

## Texture Management

```pascal
var tex: TTextureID;
tex := LoadTexture('wall.png');
BindTexture(tex);
{ draw textured geometry }
FreeTexture(tex);
```

- Texture loading is a host import (the host decodes the image and creates a sokol texture object)
- Formats: at minimum PNG; host may support more
- Texture IDs are opaque integers
- Power-of-two sizes not required (sokol handles NPOT)

## Input

Polling model, checked once per frame:

```pascal
if KeyDown(KEY_W) then MoveForward(speed);
if KeyPressed(KEY_SPACE) then Fire;

mx := GetMouseX;
my := GetMouseY;
if MouseButtonDown(MOUSE_LEFT) then Select;

if GamepadConnected(0) then begin
  lx := GamepadAxis(0, AXIS_LEFT_X);
  ly := GamepadAxis(0, AXIS_LEFT_Y);
  if GamepadButton(0, BUTTON_A) then Confirm;
end;
```

| Category | Functions |
|----------|-----------|
| Keyboard | `KeyDown`, `KeyPressed`, `KeyReleased` |
| Mouse    | `GetMouseX`, `GetMouseY`, `GetMouseDeltaX`, `GetMouseDeltaY`, `MouseButtonDown`, `MouseButtonPressed` |
| Gamepad  | `GamepadConnected`, `GamepadAxis`, `GamepadButton`, `GamepadButtonPressed` |

Input constants (key codes, button IDs, axis IDs) are defined in an `AppInput` unit.

## Audio

Minimal mixer for sound effects and streamed music:

```pascal
var snd: TSoundID;
snd := LoadSound('alert.wav');
PlaySound(snd);
SetSoundVolume(snd, 0.5);
FreeSound(snd);

var mus: TMusicID;
mus := LoadMusic('ambient.ogg');
PlayMusic(mus);
SetMusicVolume(0.8);
```

| Category | Functions |
|----------|-----------|
| Sound effects | `LoadSound`, `FreeSound`, `PlaySound`, `StopSound`, `SetSoundVolume` |
| Music (streamed) | `LoadMusic`, `FreeMusic`, `PlayMusic`, `StopMusic`, `PauseMusic`, `ResumeMusic`, `SetMusicVolume` |
| Global | `SetMasterVolume` |

Backend: sokol_audio or miniaudio on the host side.  Formats: WAV at minimum; OGG recommended for streamed music.

## 2D Drawing

For overlays, HUDs, 2D applications, and screen-space UI, a set of 2D primitives operates in screen coordinates:

```pascal
Draw2DBegin(screenWidth, screenHeight);
  DrawSprite(tex, x, y, w, h);
Draw2DEnd;
```

This sets up an orthographic projection and disables depth testing for the enclosed calls.  Under the hood it uses the same batched vertex submission as 3D -- just with a different projection matrix.

## Text Rendering

MSDF (multichannel signed distance field) fonts rendered via texture atlas.  The design breaks text into composable pieces rather than a monolithic `DrawText` function.

### Components

1. **Font loading** -- `LoadFont(path): TFontID` loads a font metrics table and an MSDF texture atlas.  The atlas is a standard texture; the metrics table maps codepoints to atlas coordinates and advance widths.

2. **Raster position** -- a current position (like `glRasterPos` / `glBitmap`) that advances after each character.  Set explicitly with `SetRasterPos(x, y)`, read with `GetRasterPos`.

3. **Character drawing** -- `DrawChar(font, ch)` draws one character at the current raster position, then advances by the character's metric width.  This is the primitive; string drawing is a Pascal loop over `DrawChar`.

4. **MSDF shader** -- a shipped shader unit (`ShaderMSDF`) that samples the distance field atlas.  Bound like any other shader.  A simpler `ShaderBitmapFont` unit serves as a non-SDF fallback.

5. **Scissor test** -- the general-purpose scissor rectangle (see Rendering Model) provides clipping for text regions, scrolling panels, etc.

### Usage

```pascal
uses ShaderMSDF, AppInput;

var font: TFontID;

procedure OnInit;
begin
  font := LoadFont('assets/mono.fnt');
end;

procedure OnFrame;
var i: integer; s: string;
begin
  s := 'Hello, world!';
  BindShader(ShaderMSDF.Shader);
  BindTexture(GetFontTexture(font));
  SetRasterPos(10, 10);
  for i := 1 to Length(s) do
    DrawChar(font, s[i]);
end;
```

Users can write their own text layout -- wrapping, centering, typewriter effects -- because the primitives are low-level enough.  No need to bloat the library with string-level rendering functions.

MSDF atlas generation requires an external tool.  msdf-atlas-gen is the standard off-the-shelf choice.  A Compact Pascal MSDF generator could be a future tutorial project.

## Asset Loading

Assets are loaded from zip archives via a virtual filesystem API.  This works identically on native (zip file on disk) and in the browser (zip fetched by the embedding page).

### API

```pascal
var pak: TArchiveID;
pak := OpenArchive('assets.zip');
tex := LoadTextureFrom(pak, 'textures/wall.png');
snd := LoadSoundFrom(pak, 'sounds/alert.wav');
CloseArchive(pak);
```

| Function | Purpose |
|----------|---------|
| `OpenArchive(path): TArchiveID` | Open a zip file, return handle |
| `CloseArchive(id)` | Close the archive |
| `ArchiveExists(id, path): boolean` | Check if entry exists |
| `ReadArchive(id, path, buf, len): integer` | Read entry into buffer |
| `OpenDir(id, path): TDirID` | Open directory listing |
| `ReadDir(dir): string` | Next entry name |
| `CloseDir(dir)` | Close directory listing |

Higher-level loaders (`LoadTextureFrom`, `LoadSoundFrom`, `LoadFontFrom`) are convenience wrappers that call `ReadArchive` internally.

Multiple archives can be open simultaneously.  This enables layering (base assets + overlay, or scene-specific archives) and keeps individual zip files small.

The host implements the zip reading -- the Pascal side only sees opaque handles and byte buffers.  Zip is universally supported, streamable, and the browser host can use the same format (fetched as an ArrayBuffer, read with a JS zip library or WASM-side inflate).

## Matrix and Vector Math

Matrix math lives in Pascal, not the host.  This keeps it visible to users, useful beyond graphics (linear algebra, physics, simulations), and avoids adding matrix types to the WASM import surface.

### Base implementation (pure Pascal)

A `MathVec` unit provides `TVec2`, `TVec3`, `TVec4`, and `TMat4` as array types:

```pascal
type
  TVec3 = array[1..3] of real;
  TVec4 = array[1..4] of real;
  TMat4 = array[1..4] of TVec4;  { column-major }
```

Operations are plain procedures -- `MatMul`, `MatTranslate`, `MatRotateY`, `MatPerspective`, `VecNormalize`, `VecDot`, `VecCross`, etc.  Scalar loops over arrays.  This works on every runtime including wasm3.

For the target capability level this is more than sufficient -- the consoles and PCs of that era ran matrix math on CPUs far slower than a WASM interpreter.

### WASM SIMD acceleration (future)

WASM SIMD (`v128` / `f32x4`) is supported by wasmi (v0.43+) and wasmtime, but not wasm3.  A future optimization pass could map `TVec4` and `TMat4` operations to SIMD instructions automatically when targeting SIMD-capable runtimes.  Same Pascal source, faster execution.  This is a compiler optimization, not an API change.

A `SimdMath` unit exposing `f32x4` as a first-class type could serve power users, but this is not a priority.

The wasm-math project [1] is a useful reference for WASM SIMD matrix patterns.

### Transform stack

The transform stack (`SetProjection`, `PushMatrix`, `Translate`, etc.) is implemented in Pascal on top of `MathVec`.  The composed matrix is passed to the host as 16 floats when a draw batch is flushed.  This means the transform API is a Pascal unit, not a set of WASM imports -- reducing the host-side surface.

## Function Count Summary

| Category     | Import? | Count | Notes                           |
|--------------|---------|-------|-------------------------------- |
| Window/frame | yes     | 10    | config, run, quit, queries      |
| Drawing      | yes     | 12    | begin/end, vertex, state        |
| Texture      | yes     | 4     | load, free, bind, set params    |
| Input        | yes     | 12    | keyboard, mouse, gamepad        |
| Audio        | yes     | 11    | sounds, music, volume           |
| Archive/VFS  | yes     | 7     | open, close, read, dir listing  |
| Scissor      | yes     | 3     | enable, disable, set rect       |
| Text/font    | yes     | 5     | load, draw char, raster pos     |
| Transform    | Pascal  | 8     | MathVec unit, matrix stack      |
| 2D helpers   | Pascal  | 5     | sprites, ortho mode             |
| **Total**    |         | **~77** | ~64 imports + ~13 Pascal-side |

## Implementation Considerations

This library is a late-stage addition, dependent on:

- Dynamic memory allocation (Phase 5 in the project roadmap)
- Real type support
- Unit system

Suggested implementation order:

1. **Window + frame loop + input** -- get something on screen
2. **2D drawing + textures** -- sprites and bitmap text
3. **3D batched rendering** -- the core vertex submission API
4. **Shipped shaders + shader2pas** -- the modular shader pipeline
5. **Audio** -- sound effects and music
6. **Gamepad** -- controller support

## Open Questions

- **Archive format details.**  Plain zip (deflate) is the obvious choice.  Compression level constraints or alignment requirements for streaming need investigation.

## References

[1] AFE-GmdG, "wasm-math," 2023.  MIT license.  https://github.com/AFE-GmdG/wasm-math
