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
┌──────────────────────────────────────────────────────────────┐
│  Browser                                                      │
│                                                               │
│  ┌─────────────┐    stdin     ┌──────────────┐               │
│  │  Editor      │───(source)──▶  Compiler     │               │
│  │  (textarea)  │             │  (WASM)       │               │
│  └─────────────┘             └──────┬───────┘               │
│                                      │ stdout (compiled .wasm)│
│                                      ▼                        │
│                              ┌──────────────┐               │
│                              │  Web Worker   │               │
│                              │  (runs prog)  │               │
│                              └──────┬───────┘               │
│                                      │ postMessage           │
│                                      ▼                        │
│                              ┌──────────────┐               │
│                              │  Output Pane  │               │
│                              └──────────────┘               │
└──────────────────────────────────────────────────────────────┘
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
│ [Compact Pascal]  📂 Open Sample  📤 Upload  📥 Download  🔧 Compile  │
│                   ▶️ Run  ⏹️ Stop                            [☀/🌙]   │
├────────────────────────────────────┬────────────────────────────────────┤
│ [• hello.pas ×] [fizzbuzz.pas ×]  │  Output                [Clear]    │
├────────────────────────────────────┤  ──────                           │
│  1│ program hello;                 │  Compiled 142 bytes               │
│  2│ begin                          │  > Hello, world!                  │
│  3│   writeln('Hello, world!')     │                                   │
│  4│ end.                           │                                   │
│  │                                 │                                   │
├────────────────────────────────────┴────────────────────────────────────┤
│ Ready                                                      Ln 1, Col 1 │
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

## Syntax Highlighting (Stretch Goal)

Syntax highlighting uses a state-machine engine driven by JSON syntax
definition files. The format is inspired by the Joe/Jupp `.jsf` format.

### How it works

The editor remains a `<textarea>` for input handling. Behind it, a
`<pre>` element mirrors the text with `<span class="...">` wrappers for
each token. The textarea is transparent; the pre provides the visible
colored text. Both scroll in sync.

### Syntax definition format

A syntax file defines states. Each state has:
- A `default` transition (for unmatched characters).
- Character-class transitions (regex-like patterns).
- An optional `keywords` map for identifier classification.
- An optional `recolor` count to repaint previous characters.

Example (`pascal.json`, derived from `pascal.jsf`):

```json
{
  "name": "Pascal",
  "extensions": [".pas", ".pp", ".p"],
  "styles": {
    "idle": "",
    "comment": "syn-comment",
    "constant": "syn-constant",
    "keyword": "syn-keyword",
    "type": "syn-type",
    "operator": "syn-operator",
    "function": "syn-function"
  },
  "states": {
    "idle": {
      "default": "idle",
      "rules": [
        { "match": "[a-zA-Z]", "next": "ident", "buffer": true },
        { "match": "(", "next": "maybe_comment" },
        { "match": "{", "next": "comment", "style": "comment", "recolor": 1 },
        { "match": "'", "next": "string", "style": "constant", "recolor": 1 },
        { "match": "[0-9]", "next": "number", "style": "constant", "recolor": 1 }
      ]
    },
    "comment": {
      "style": "comment",
      "default": "comment",
      "rules": [
        { "match": "*", "next": "maybe_end_comment" },
        { "match": "}", "next": "idle" }
      ]
    },
    "ident": {
      "default": { "next": "idle", "noeat": true },
      "rules": [
        { "match": "[a-zA-Z0-9_]", "next": "ident" }
      ],
      "keywords": {
        "keyword": ["and", "array", "begin", "case", "const", "div", "do",
          "downto", "else", "end", "file", "for", "function", "goto", "if",
          "in", "label", "mod", "nil", "not", "of", "or", "packed",
          "procedure", "program", "record", "repeat", "set", "then", "to",
          "type", "until", "var", "while", "with"],
        "type": ["integer", "boolean", "real", "char", "string", "text",
          "byte", "word", "shortint", "longint", "shortstring"],
        "function": ["abs", "arctan", "chr", "concat", "copy", "cos",
          "eof", "eoln", "exp", "halt", "hi", "length", "lo", "ln",
          "odd", "ord", "pred", "round", "sin", "sqr", "sqrt", "succ",
          "trunc", "upcase", "val", "write", "writeln", "read", "readln",
          "inc", "dec", "new", "dispose", "delete", "insert", "str",
          "fillchar", "move", "sizeof", "high", "low"]
      }
    }
  }
}
```

The engine is ~100 lines of JS. It processes the full editor text on each
keystroke (debounced to ~50ms). For the size of programs people write in a
playground, this is fast enough.

### CSS classes

```css
.syn-comment  { color: #6a9955; }  /* green */
.syn-constant { color: #569cd6; }  /* blue */
.syn-keyword  { font-weight: 600; }
.syn-type     { font-weight: 600; color: #4ec9b0; }
.syn-operator { font-weight: 600; }
.syn-function { font-weight: 600; color: #dcdcaa; }
```

Colors will be tuned to match the playground's warm palette.

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
    pascal.json      — syntax definition (stretch goal)
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
