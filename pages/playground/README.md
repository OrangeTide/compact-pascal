# Compact Pascal Playground

Browser-based IDE for Compact Pascal with syntax highlighting, sample programs, and compile/run functionality.

## Features

- **Editor**: Monospace editor with line numbers, tab management, undo/redo support
- **Sample Programs**: Load example programs (Hello World, FizzBuzz, Fibonacci)
- **File Operations**: Upload/download files, save/restore session to browser storage
- **Compilation**: Compile Pascal source to WASM with error diagnostics
- **Execution**: Run compiled WASM programs and capture output

## Architecture

### JavaScript Components

The playground consists of:

1. **Editor & Tabs** - Multi-buffer editor with localStorage session persistence
2. **Menu & Controls** - Save, Load, Upload, Download, Copy, Paste, Compile, Run
3. **WASI Shim** - JavaScript implementation of WASI preview 1 for the compiler and programs:
   - `fd_write` - Write to stdout/stderr
   - `fd_read` - Read from stdin
   - `proc_exit` - Handle process exit
   - `args_get` / `args_sizes_get` - Command-line argument stubs
4. **Modal Console** - Display compiler diagnostics and program output

### Compiler Integration

The playground expects the Compact Pascal compiler as a WASM module at `../snapshot/compiler.wasm`.

The compiler is invoked by:

1. Resetting I/O buffers
2. Writing source code to stdin (fd 0) via the WASI shim
3. Calling `_start()` export
4. Capturing stdout (fd 1) as compiled WASM bytes
5. Capturing stderr (fd 2) as error messages

### Development Server

For local development (when the WASM snapshot is not available), a Node.js development server is provided:

```bash
node pages/playground/compile-server.js
```

This server:
- Serves the playground at `http://localhost:8080/playground/`
- Proxies `/api/compile` requests to the native compiler binary
- Converts binary output to JSON for the frontend

## Building the Compiler WASM Snapshot

The compiler snapshot doesn't exist yet because the Compact Pascal compiler hasn't achieved self-hosting. To create it:

1. Complete the self-hosting bootstrap - the compiler must be able to compile itself
2. Run: `./compiler/cpas < compiler/cpas.pas > snapshot/compiler.wasm`
3. Verify: `wasm-validate snapshot/compiler.wasm`
4. Test fixpoint: `wasmtime run snapshot/compiler.wasm < compiler/cpas.pas | cmp - snapshot/compiler.wasm`
5. Commit to git

Once the snapshot exists, the playground will use it automatically without needing the development server.

## Current Limitations

- **Self-hosting not ready**: The compiler can compile sample programs but not itself yet
- **Development server required**: Use `compile-server.js` for local testing until the WASM snapshot is built
- **No REPL**: This is a one-shot compiler, not an interactive environment

## File Structure

```
pages/playground/
├── index.html              Playground UI and JavaScript
├── compile-server.js       Development server (Node.js)
├── samples/
│   ├── hello.pas           "Hello, world!" example
│   ├── fizzbuzz.pas        FizzBuzz example
│   └── fibonacci.pas       Fibonacci example
└── README.md              This file

snapshot/
└── compiler.wasm          WASM snapshot (not yet built)
```

## Browser Compatibility

- Chrome/Edge 74+ (WebAssembly.instantiate)
- Firefox 79+
- Safari 14+
- Opera 61+

Requires JavaScript ES5+ and `navigator.clipboard` API for Paste (graceful fallback for older browsers).

## Testing

To test locally:

```bash
# Terminal 1: Start dev server
node pages/playground/compile-server.js

# Terminal 2: Open in browser
open http://localhost:8080/playground/

# Test flow:
# 1. Load a sample (Hello World)
# 2. Click "Compile" - should show "Successfully compiled" with byte count
# 3. Click "Run" - should show output "Hello, world!"
```

## Implementation Notes

### WASI Memory Layout

The WASI shim manages memory through iovec (scatter-gather) lists:
- Each iovec is an 8-byte struct: (ptr: i32, len: i32)
- `fd_write` collects data from multiple buffers and appends to the fd buffer
- `fd_read` reads sequentially from the fd buffer into multiple buffers

### Error Handling

- **Compiler errors**: Captured on stderr, displayed in modal
- **Syntax errors**: Shown with file/line context from compiler
- **Runtime traps**: Caught as `WasiExit` exception with exit code
- **Graceful fallback**: If compiler unavailable, shows setup instructions

### Session Persistence

Program tabs and content are saved to `localStorage['cpas-playground']` as JSON:

```javascript
[
  { name: 'hello.pas', content: '...' },
  { name: 'myprogram.pas', content: '...' }
]
```

Active tab index is stored in `localStorage['cpas-active']`.

## Future Enhancements

- [ ] Syntax highlighting (CodeMirror, Monaco, or Ace integration)
- [ ] Real-time compilation (as you type)
- [ ] Multi-file projects with include support
- [ ] Disassembly viewer (wasm2wat)
- [ ] Step-through debugger (via DWARF debug info)
- [ ] Collaborative editing (via WebSocket)
- [ ] Share links (generate shareable snippets)
- [ ] Performance profiler (instruction count, CPU time)
