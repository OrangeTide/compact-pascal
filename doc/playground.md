# Compact Pascal Playground — Design Document

DRAFT — 2026-04-06

The playground is a browser-based IDE for writing, compiling, and running
Compact Pascal programs. It runs entirely client-side: the compiler WASM
snapshot executes in the browser via the WebAssembly API, and compiled
programs run in a Web Worker with a WASI shim.

The playground is designed to be self-contained and redistributable.
Third parties can host their own instance by copying the `pages/playground/`
directory and providing a compiler snapshot.

## Architecture

```
┌────────────────────────────────────────────────────────────────┐
│  Browser                                                       │
│                                                                │
│  ┌─────────────┐    stdin    ┌──────────────┐                  │
│  │  Editor     │───(source)──▶  Compiler    │                  │
│  │  (textarea) │             │  (WASM)      │                  │
│  └─────────────┘             └──────┬───────┘                  │
│                                     │ stdout (compiled .wasm)  │
│                                     ▼                          │
│                              ┌──────────────┐                  │
│                              │  Web Worker  │                  │
│                              │  (runs prog) │                  │
│                              └──────┬───────┘                  │
│                                     │ postMessage              │
│                                     ▼                          │
│                              ┌──────────────┐                  │
│                              │  Output Pane │                  │
│                              └──────────────┘                  │
└────────────────────────────────────────────────────────────────┘
```

**Compile** runs on the main thread: the compiler WASM module is
instantiated with a WASI shim that feeds the editor content as stdin and
captures stdout (the compiled WASM bytes) and stderr (error messages).

**Run** executes in a Web Worker so it can be terminated with
`worker.terminate()` if the program hangs or loops forever. The worker
posts stdout/stderr chunks back to the main thread via `postMessage`.

## Layout

```
┌─────────────────────────────────────────────────────────────────────────┐
│ [Compact Pascal]  📂 Open Sample  📤 Upload  📥 Download  🔧 Compile    │
│                   ▶️ Run  ⏹️ Stop                            [☀/🌙]      │
├────────────────────────────────────┬────────────────────────────────────┤
│ [• hello.pas ×] [fizzbuzz.pas ×]   │  Output                [Clear]     │
├────────────────────────────────────┤  ──────                            │
│  1│ program hello;                 │  Compiled 142 bytes                │
│  2│ begin                          │  > Hello, world!                   │
│  3│   writeln('Hello, world!')     │                                    │
│  4│ end.                           │                                    │
│   │                                │                                    │
├────────────────────────────────────┴────────────────────────────────────┤
│ Ready                                                       Ln 1, Col 1 │
└─────────────────────────────────────────────────────────────────────────┘
```

- **Top bar**: project title (links to main site with unsaved-changes
  confirmation), file and action buttons with emoji icons, dark mode
  toggle on the far right. Buttons are left-justified in a single row.
- **Editor pane** (left): tabbed buffers with line-numbered textarea.
  Modified tabs show a bullet prefix (`•`) as an unsaved indicator.
  When no tabs are open, the editor hides and the output pane fills the
  full width.
- **Output pane** (right): scrollable log showing compiler messages and
  program output. Has a clear button. Not a modal — always visible.
- **Status bar**: cursor position, compiler status messages.
- **Splitter**: draggable vertical divider between editor and output.

The split defaults to roughly 60/40 (editor/output). On narrow screens
(< 700px), the layout stacks vertically.

### Dark Mode

A toggle in the top-right corner of the toolbar switches between light
and dark themes. The theme is implemented with CSS custom properties on
`body.dark`:

- Light theme: warm cream/sienna palette (`--bg: #f5f0e8`).
- Dark theme: dark backgrounds, light text (`--bg: #1e1a16`).

The preference is persisted to `localStorage` (`playground_dark_mode`)
and restored on page load.

## File Operations

### Open Sample (from catalog)

The "Open Sample" button fetches `files.json` and presents a dropdown
list. Each entry names a `.pas` file relative to `samples/`. Selecting
one fetches the file and either:

- **Replaces** the current tab, if it is unmodified and was not restored
  from localStorage (the `fromStorage` flag prevents overwriting a
  user's restored session).
- **Opens a new tab**, if the current tab has unsaved changes or was
  restored from a previous session.

```json
[
  {
    "name": "Hello World",
    "file": "hello.pas",
    "description": "Simple writeln example"
  },
  {
    "name": "FizzBuzz",
    "file": "fizzbuzz.pas",
    "description": "Classic loop with conditionals"
  },
  {
    "name": "Fibonacci",
    "file": "fibonacci.pas",
    "description": "Recursive function demo"
  }
]
```

To add a new sample, drop a `.pas` file into `samples/` and add an entry
to `files.json`. No code changes needed.

### Upload

Opens a native file picker (`<input type="file">`). Accepted extensions:
`.pas`, `.pp`, `.p`, `.txt`.

### Download

Saves the current buffer as a file via `Blob` + `URL.createObjectURL`.

### Save / Restore

All open buffers are persisted to `localStorage` on every edit. The
session is restored on page load. Restored buffers are marked with a
`fromStorage` flag so that Open Sample does not silently overwrite them.

### Navigation Guard

Clicking the "Compact Pascal" title link triggers a `confirmLeave()`
check. If any buffer has unsaved changes (content differs from its
`savedText` snapshot), the user is prompted before navigating away.

## Compile / Run / Stop

### Compile

1. Encode editor content as UTF-8 byte array.
2. Reset WASI context: set stdin to source bytes, clear stdout/stderr.
3. Call compiler module's `_start` export.
4. Catch `WasiExit` — exit code 0 means success.
5. Collect stdout bytes (compiled WASM) and stderr text (errors).
6. On success: store compiled bytes on the buffer object, show byte count
   in output pane.
7. On failure: show stderr in output pane with error styling.

The compiler module is loaded once at page load and reused for each
compilation. Each compile creates a fresh `WebAssembly.Instance` from the
pre-compiled `WebAssembly.Module` to get clean memory state.

### Run

1. If no compiled bytes on current buffer, compile first.
2. Create a Web Worker from `run-worker.js`.
3. Post the compiled WASM bytes to the worker.
4. Worker instantiates with WASI shim and calls `_start`.
5. Worker posts `{type: 'stdout', data: '...'}` and
   `{type: 'stderr', data: '...'}` messages back.
6. Worker posts `{type: 'exit', code: N}` on completion.
7. Main thread appends output to the output pane.

Only one program runs at a time. The Run button is disabled while a
program is active. The active worker reference is stored globally.

### Stop

Calls `worker.terminate()` on the active worker. Shows "Program stopped"
in the output pane. Re-enables the Run button.

## WASI Shim

Both the compiler and the running program use WASI preview 1. The shim
implements five imports:

| Import              | Behavior                                            |
|---------------------|-----------------------------------------------------|
| `fd_read`           | Reads from a byte array (stdin). Returns 0 at EOF.  |
| `fd_write`          | Appends to a byte array (stdout/stderr per fd).     |
| `proc_exit`         | Throws `WasiExit` exception to halt execution.      |
| `args_get`          | Returns 0 args (no command-line arguments).          |
| `args_sizes_get`    | Returns argc=0, buf_size=0.                          |

The iovec layout follows WASI spec: each iovec is 8 bytes
(4-byte `buf` pointer + 4-byte `buf_len`), little-endian.

## Compiler Error Format

The compiler emits errors to stderr in a consistent format:

```
Error: [LINE:COL] message
```

The output pane can pattern-match `\[(\d+):(\d+)\]` to make errors
clickable — clicking jumps the editor cursor to that line and column.

## Syntax Highlighting

Syntax highlighting uses a state-machine tokenizer driven by JSON syntax
definition files. The format is derived from Joe/Jupp `.jsf` files,
translated to JSON for easy editing.

### How it works

The editor remains a `<textarea>` for input handling. Behind it, a
`<pre id="highlight">` element mirrors the text with `<span class="...">`
wrappers for each token. The textarea has transparent text and background;
the pre provides the visible colored text underneath. The textarea's caret
remains visible via `caret-color`. Both elements scroll in sync.

The tokenizer runs on every keystroke (no debounce). It produces a
per-character style array in O(n) time. For playground-sized programs this
is fast enough.

### Syntax definition format

A syntax file is a JSON object with three top-level fields:

| Field | Purpose |
|-------|---------|
| `name` | Display name (e.g. "Pascal") |
| `startState` | Initial state name |
| `styles` | Map of logical style names to CSS class names |

Each state has:

| Field | Purpose |
|-------|---------|
| `style` | Style applied to characters consumed in this state. If omitted and the state name matches a key in `styles`, that style is inferred. Otherwise defaults to `idle`. |
| `default` | Next state for unmatched characters. Can be a string (`"idle"`) or an object (`{"next": "idle", "noeat": true, "recolor": 1}`). |
| `rules` | Ordered list of character-class transitions. First match wins. |
| `keywords` | Map of lowercase identifiers to style names (on ident-like states only). Applied retroactively when leaving the state via a `noeat` default. |
| `strings` | Map of literal strings to `{"next": "state", "recolor": N}`. Matches accumulated buffer content on each default-eat transition. Used for multi-character lookahead (e.g. `<!--`, `<![CDATA[`). |

Each rule has:

| Field | Purpose |
|-------|---------|
| `match` | Character class. Ranges like `a-zA-Z0-9`, single chars like `(`, `{`, special `\n`. A `-` at the end of the string is literal. |
| `next` | Target state. |
| `recolor` | Retroactively restyle the previous N characters (including current) with the target state's style. |
| `noeat` | Don't consume the character; re-process it in the target state. |
| `buffer` | Start accumulating characters for keyword or string lookup. |

The `normalizeSyntax()` preprocessor expands shorthand (style inference,
object-form defaults) into the canonical form the tokenizer expects. This
keeps syntax files concise while maintaining backward compatibility with
the original explicit format.

### Available definitions

| File | Source | States | Notes |
|------|--------|--------|-------|
| `pascal.json` | `pascal.jsf` | 13 | Keywords, `{}` and `(* *)` comments, `''` strings, numbers with exponents |
| `html.json` | `html.jsf` | 43 | Tag/attribute keywords, entity refs, comments, `<script>`/`<style>` embedded content |
| `xml.json` | `xml.jsf` | 34 | Strict validation, entity refs, `<!-- -->`, `<![CDATA[]]>`, `<?...?>`, uses `strings` for multi-char matching |

### CSS classes

Syntax colors use CSS custom properties, with separate values for light
and dark themes:

| Class | Light | Dark | Used for |
|-------|-------|------|----------|
| `.syn-comment` | `#6a9955` | `#6a9955` | Comments |
| `.syn-constant` | `#b5632f` | `#ce9178` | Strings, numbers, CDATA |
| `.syn-keyword` | `#a0522d` | `#d4845a` | Keywords, tag names |
| `.syn-type` | `#2e7d6e` | `#4ec9b0` | Type names |
| `.syn-operator` | `#2c2420` | `#d4d4d4` | Operators |
| `.syn-function` | `#6f4e37` | `#dcdcaa` | Built-in functions, PIs |
| `.syn-entity` | `#6f4e37` | `#dcdcaa` | Entity references |
| `.syn-attr` | `#2e7d6e` | `#4ec9b0` | Attributes, declarations |
| `.syn-error` | `#dc3545` | `#f44747` | Malformed markup |
| `.syn-embedded` | `#6e5494` | `#b8a2d0` | `<script>`/`<style>` body content (italic) |

## Future Extras

These are not part of the initial implementation but are planned:

- **Graphics canvas**: a pop-out window for programs that use a graphics
  API. Appears on demand when the program calls graphics imports.
  Can be popped out of the browser window.
- **WASM disassembly pane**: shows `wasm2wat`-style disassembly of the
  compiled output. Useful for the tutorial.
- **GitHub Gist sharing**: POST to the GitHub Gist API (unauthenticated
  creates anonymous gists; authenticated via OAuth for user gists).
  The Gist API endpoint is `POST https://api.github.com/gists`.
- **Paste URL loading**: accept a URL query parameter (`?url=...`) that
  fetches a Pascal source file. Content-type must be `text/*`. This
  enables sharing via paste services.
- **stdin input**: a text field in the output pane where the user can
  type input for programs that call `readln`.

## File Structure

```
pages/playground/
  index.html         — main page (HTML + CSS + JS, single file)
  run-worker.js      — Web Worker for program execution
  files.json         — sample program catalog
  samples/
    hello.pas
    fizzbuzz.pas
    fibonacci.pas
    ...
  syntax/
    pascal.json      — Pascal syntax definition
    html.json        — HTML syntax definition
    xml.json         — XML syntax definition (uses strings for multi-char matching)
```

## Dependencies

None. The playground is plain HTML/CSS/JS with no build step, no npm, no
framework. It uses the browser's native `WebAssembly`, `Worker`, `fetch`,
and `localStorage` APIs.

## Hosting

Copy `pages/playground/` and `snapshot/compiler.wasm` to any static file
server. The playground fetches the compiler snapshot from
`../snapshot/compiler.wasm` (relative path). Override this by setting
`window.CPAS_COMPILER_URL` before the script runs.

For local development without the snapshot, the playground shows
"Compiler unavailable" in the output pane but all editing features work.

## Future Items

- [ ] plumb some WASI calls that are appropriate for our playground environment.
    - fd_write, fd_read, fd_close, and path_open calls.
    - our javascript runtime keeps a file descriptor table. Each entry is an file_ops
    - initial program starts with file_ops entries, 0, 1, 2 set to file_ops with callbacks appropriate for stdin, stdout, and stderr respectively.
    - [ ] path_open allocates the next available file descriptor table entry. file_ops is a read and/or write to an editor buffer of the same name. the write callback handler calls notifiers array in the file_ops object that editor tab(s) can use to receive update events. (fd_datasync would have been a more elegant way to implement this, but we didn't implement that API)
    - the end result: Pascal programs can create new editor tabs and read/write text.
- [ ] update our layout to support mobile friendly view. perhaps editor and output are top/bottom instead of side-by-side? (need to make some decisions)
- [ ] support binary editor tabs. these would be displayed in an hex/ascii
  view. user can change the view's "record size" to change the number of hex
  values per row. default is 16 like a standard hex viewer. This enables users
  to view and modify pascal records. Creating an ideal environment for
  teaching.
- [ ] add a scroll lock button for the output window. (lock/unlock emoji)
- [ ] output window and graphic windows are tabs on the right-hand side, mirroring the tab UI of the editor panes. These output/graphics tabs can also be popped out of the frame.
- [ ] add syntax for c (and h), json (use c.jsf as inspiration?), tex, csv (I have no examples, but commas and quotes seem obvious), wasm (use lisp.jsf as inspiration?), markdown (I have no example), sh, ini (perhaps conf.jsf as a starting point, add [section], might also be a basis for a toml syntax), diff/patch.
