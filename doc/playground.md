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
│  Browser (main thread)                                         │
│                                                                │
│  ┌─────────────┐    stdin    ┌──────────────┐                  │
│  │  Editor     │───(source)──▶  Compiler    │                  │
│  │  (textarea) │             │  (WASM)      │                  │
│  └─────┬───────┘             └──────┬───────┘                  │
│        │ read/write files           │ stdout (compiled .wasm)  │
│        │ (SharedArrayBuffer)        ▼                          │
│        │                     ┌──────────────┐                  │
│        ├─────────────────────│  Web Worker  │                  │
│        │   stdin input ──────│  (runs prog) │                  │
│        │ (SharedArrayBuffer) └──────┬───────┘                  │
│        │                            │ postMessage              │
│        ▼                            ▼                          │
│  ┌─────────────┐             ┌──────────────┐                  │
│  │ Editor Tabs │             │  Output Pane │                  │
│  │ (file I/O)  │             │  + stdin bar │                  │
│  └─────────────┘             └──────────────┘                  │
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
This is transparent to the user — they pick up where they left off.

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
2. Allocate a `SharedArrayBuffer` for stdin and file I/O (see
   "Interactive Stdin" below).
3. Create a Web Worker from `run-worker.js`.
4. Post the compiled WASM bytes and shared buffer to the worker.
5. Worker instantiates with WASI shim and calls `_start`.
6. Worker posts messages back to the main thread:
   - `{type: 'stdout', data: '...'}` — program output
   - `{type: 'stderr', data: '...'}` — error output
   - `{type: 'waiting_input'}` — program blocked on `fd_read`
   - `{type: 'file_write', name, data}` — write to editor tab
   - `{type: 'file_read_request', name}` — request editor tab content
   - `{type: 'file_close', name}` — file closed
   - `{type: 'exit', code: N}` — program finished
7. Main thread appends output to the output pane and handles file I/O
   requests (see "Editor-as-Filesystem" below).

Only one program runs at a time. The Run button is disabled while a
program is active. The active worker reference is stored globally.

### Stop

Calls `worker.terminate()` on the active worker. Shows "Program stopped"
in the output pane. Re-enables the Run button.

## WASI Shim

Both the compiler and the running program use WASI preview 1. The two
contexts have different shim implementations because they have different
needs.

### Compiler WASI shim (main thread)

The compiler runs on the main thread. Its I/O is non-interactive: stdin
is pre-loaded with the source text and stdout/stderr are collected into
byte arrays.

| Import              | Behavior                                            |
|---------------------|-----------------------------------------------------|
| `fd_read`           | Reads from a pre-loaded byte array (source text).   |
| `fd_write`          | Appends to a byte array (stdout=WASM, stderr=errors). |
| `proc_exit`         | Throws `WasiExit` to halt.                          |
| `args_get`          | Returns 0 args (no command-line arguments).          |
| `args_sizes_get`    | Returns argc=0, buf_size=0.                          |

### Program WASI shim (Web Worker)

Running programs execute in a Web Worker with a richer WASI shim that
supports interactive stdin, file I/O, and an fd table.

| Import              | Behavior                                            |
|---------------------|-----------------------------------------------------|
| `fd_read`           | Reads via fd table. fd 0 blocks on SharedArrayBuffer. |
| `fd_write`          | Writes via fd table. Flushes to main thread per call. |
| `fd_close`          | Closes an fd, frees the table slot.                  |
| `path_open`         | Opens a file backed by an editor buffer.             |
| `proc_exit`         | Throws `WasiExit` to halt.                          |
| `args_get`          | Returns 0 args (no command-line arguments).          |
| `args_sizes_get`    | Returns argc=0, buf_size=0.                          |

The iovec layout follows WASI spec: each iovec is 8 bytes
(4-byte `buf` pointer + 4-byte `buf_len`), little-endian.

### File descriptor table

The worker maintains an fd table (array of `file_ops` objects). Each
entry has:

| Field   | Type       | Purpose                                      |
|---------|------------|----------------------------------------------|
| `read`  | function   | Read callback, null if not readable.          |
| `write` | function   | Write callback, null if not writable.         |
| `close` | function   | Cleanup callback.                             |
| `flags` | number     | `O_RDONLY`, `O_WRONLY`, etc.                  |

Initial state: fd 0 = stdin, fd 1 = stdout, fd 2 = stderr. fd 3 is
the pre-opened editor root directory (used as `fd_dir` for `path_open`).

`fd_read` and `fd_write` look up `fdTable[fd]` and dispatch to the
appropriate callback. Invalid fds return `ERRNO_BADF` (8). Closing
fd 0/1/2 is allowed (programs sometimes close stdin after reading).

## Interactive Stdin

WASM execution is synchronous. When a program calls `readln`, the
worker's `fd_read` must return data immediately — but the user hasn't
typed it yet. Web Workers cannot block on `postMessage`, but they can
block using `SharedArrayBuffer` + `Atomics.wait()`.

### Shared buffer protocol

The main thread allocates a 4 KB `SharedArrayBuffer` and passes it to
the worker with the `run` message. The buffer has a simple protocol:

```
Byte offset   Size    Field
0             4       status: 0=empty, 1=data ready, 2=EOF
4             4       length: number of bytes in payload
8             ~4080   payload: UTF-8 input bytes
```

### Blocking read sequence

```
         Worker                           Main Thread
           │                                   │
           │  fd_read(fd=0) called              │
           │                                   │
           ├─ check status word                │
           │  status == 0 (empty)              │
           │                                   │
           ├─ postMessage({type:               │
           │   'waiting_input'})               │
           │                                   ├─ show input prompt
           ├─ Atomics.wait(status, 0)          │   indicator in
           │  (thread blocks)                  │   output pane
           │                                   │
           │                                   │  user types "42"
           │                                   │  and presses Enter
           │                                   │
           │                                   ├─ encode "42\n" as
           │                                   │  UTF-8 into shared
           │                                   │  buffer payload
           │                                   ├─ set length = 3
           │                                   ├─ Atomics.store
           │                                   │  (status, 1)
           │                                   ├─ Atomics.notify
           │                                   │  (status)
           │                                   │
           ├─ (wakes up)                       │
           ├─ copy payload into                │
           │  WASM memory iovecs               │
           ├─ set status = 0                   │
           ├─ Atomics.notify(status)           │
           │  (signals main thread             │
           │   can accept more input)          │
           ├─ return bytes read                │
           │                                   │
           │  program continues...             │
```

### EOF handling

The "EOF" button (or Ctrl+D) sets status to 2. The worker's `fd_read`
returns 0 bytes (EOF), which the Pascal runtime interprets as `eof`
returning `true`.

### COOP/COEP headers

`SharedArrayBuffer` requires two HTTP headers:

- `Cross-Origin-Opener-Policy: same-origin`
- `Cross-Origin-Embedder-Policy: require-corp`

GitHub Pages does not support custom headers. The playground uses the
`coi-serviceworker` pattern: a service worker intercepts responses and
injects the required headers. The service worker script is loaded from
`index.html` before any other scripts.

### Input field UI

A text input appears in the output pane footer while a program is
running. It is styled distinctly (monospace, slight background tint) to
distinguish it from editor UI. A prompt indicator appears when the
program is blocked on input. The field is hidden when the program exits
or is stopped.

## Editor-as-Filesystem

Programs can open, read, and write files. In the playground, "files"
are editor buffers — opening a file for writing creates (or updates) an
editor tab; opening for reading fetches the content of an existing tab.

### How it works

The compiler emits `path_open` and `fd_close` WASI calls for Pascal's
`assign`/`reset`/`rewrite`/`close` built-ins. The playground's WASI
shim intercepts these calls and maps them to editor buffers.

### Directory roots

The WASM side maintains 26 directory root globals (`fd_dir_A` through
`fd_dir_Z`), analogous to drive letters. All are initialized to -1
except `fd_dir_A` which is fd 3 — the pre-opened editor root. Programs
pass `fd_dir_A` as the first argument to `path_open`.

The playground runtime pre-opens fd 3 as a virtual directory whose
"files" are editor buffers. Only A: is used initially. The other 25
slots are reserved (e.g., B: for a read-only samples directory).

### path_open flow

1. Worker reads the path string from WASM linear memory.
2. Validates `fd_dir` is a valid pre-opened directory (fd 3).
3. Checks `oflags`: `O_CREAT` (1), `O_EXCL` (4), `O_TRUNC` (8).
4. Allocates the next free fd table slot.
5. Creates a `file_ops` object with read/write callbacks backed by
   a byte buffer.
6. Stores the allocated fd at the output pointer in WASM memory.
7. Returns 0 (success) or an errno (`ENOENT`=44, `EBADF`=8, etc.).

### Writing files

Each `fd_write` call to a file-backed fd posts a
`{type: 'file_write', name, data}` message to the main thread
immediately (flush per write). The main thread decodes the data as
UTF-8 and creates or updates an editor tab with that filename.

On `fd_close`, the worker posts `{type: 'file_close', name}` as a
final notification.

### Reading files

When a program opens a file for reading, the worker uses the same
`SharedArrayBuffer` blocking pattern as stdin:

1. Worker posts `{type: 'file_read_request', name}` to main thread.
2. Worker blocks on `Atomics.wait()`.
3. Main thread looks up the editor buffer by filename.
4. If found: encodes content as UTF-8, writes it into the shared
   buffer, sets status to 1, notifies.
5. If not found: writes `ENOENT` errno into status, notifies.
6. Worker wakes, copies content into a local read buffer.
7. Subsequent `fd_read` calls consume from this buffer.

### Result: programs create editor tabs

The end result is that Pascal programs can create new editor tabs and
read/write text. For example:

```pascal
var f: text;
begin
  assign(f, 'output.txt');
  rewrite(f);
  writeln(f, 'Generated by program');
  close(f);
end.
```

This creates a new editor tab named `output.txt` containing
"Generated by program". The tab appears alongside any user-created
tabs and can be edited, saved, or downloaded.

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

- **stdin input**: a text field in the output pane where the user can
  type input for programs that call `readln`. MVP requirement — users
  will expect interactive programs to work.
- **Graphics canvas**: a pop-out window for programs that use a graphics
  API. Appears on demand when the program calls graphics imports.
  Can be popped out of the browser window. Aspirational — tied to
  TN-002, which is a large project on its own.
- **WASM disassembly pane**: shows `wasm2wat`-style disassembly of the
  compiled output. Useful for the tutorial. Large implementation effort
  but high value for teaching WASM concepts.
- **GitHub Gist sharing**: POST to the GitHub Gist API (unauthenticated
  creates anonymous gists; authenticated via OAuth for user gists).
  The Gist API endpoint is `POST https://api.github.com/gists`.
- **Paste URL loading**: accept a URL query parameter (`?url=...`) that
  fetches a Pascal source file. Content-type must be `text/*`. This
  enables sharing via paste services.

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

Copy `pages/playground/` to any static file server with `compiler.wasm`
in the same directory. The playground looks for `compiler.wasm` in its
own directory first, then falls back to `../snapshot/compiler.wasm` for
local development. Override the path by setting `window.CPAS_COMPILER_URL`
before the script runs.

For local development without the snapshot, the playground shows
"Compiler unavailable" in the output pane but all editing features work.

## Future Items

- [ ] stdin input for running programs. A text field in the output pane
  where the user can type input for programs that call `readln`. This is
  an MVP requirement — users will expect interactive programs to work.
- [ ] plumb WASI calls for the playground environment.
    - fd_write, fd_read, fd_close, and path_open calls.
    - The JavaScript runtime keeps a file descriptor table. Each entry
      is a file_ops object. Programs start with fd 0, 1, 2 mapped to
      stdin, stdout, and stderr respectively.
    - path_open takes an fd_dir parameter — a pre-opened directory
      handle. The WASM side maintains a table of 26 directory root
      globals (A: through Z:, like drive letters), most initialized
      to -1. By default fd=3 is the "root" directory of the editor
      (A:), which is what programs normally pass.
    - path_open allocates the next available fd table entry. The
      file_ops is a read and/or write to an editor buffer of the same
      name. Creation vs error is controlled by oflags; fs_flags
      handles O_RDONLY and similar. The write callback calls a
      notifiers array in the file_ops object that editor tab(s) use
      to receive update events. (fd_datasync would have been a more
      elegant way to implement this, but we didn't implement that API.)
    - The end result: Pascal programs can create new editor tabs and
      read/write text.
- [ ] binary editor tabs (depends on WASI plumbing). Displayed in a
  hex/ascii view. User can change the view's "record size" to set the
  number of hex values per row. Default is 16 like a standard hex
  viewer. This enables users to view and modify Pascal records —
  creating an ideal environment for teaching file I/O without jumping
  straight to binary record dumps.
- [ ] add a scroll lock button for the output window. (lock/unlock emoji)
- [ ] output and graphics panes as tabs on the right-hand side,
  mirroring the tab UI of the editor panes.
- [ ] pop-out windows for output/graphics tabs. Detach a tab into its
  own browser window. (Separate from the tabbed layout above.)
- [ ] mobile-friendly layout. Editor on top, output on bottom (vertical
  stack). Tap-to-switch between full-screen editor and full-screen
  output modes. Drag-to-select uses native platform cut/paste.
- [ ] add syntax definitions for: C/H, CSV, JSON, WAT (WASM text
  format, use lisp.jsf as inspiration), markdown.
