// Compact Pascal Playground - WASM Program Runner Worker

var currentInstance = null;
var isRunning = false;

// WASI context for the running program
var WasiContext = {
  fdState: {
    0: { data: null, pos: 0 },  // stdin (empty in initial version)
    1: { data: [], pos: 0 },    // stdout
    2: { data: [], pos: 0 }     // stderr
  },

  fdWrite: function(fd, iovsPtr, iovsLen, nwrittenPtr, memory) {
    var written = 0;
    var view = new Uint8Array(memory.buffer);
    var dataView = new DataView(memory.buffer);

    for (var i = 0; i < iovsLen; i++) {
      var iovPtr = iovsPtr + (i * 8);
      var bufPtr = dataView.getUint32(iovPtr, true);
      var bufLen = dataView.getUint32(iovPtr + 4, true);

      var chunk = view.slice(bufPtr, bufPtr + bufLen);

      // Decode and send to main thread
      var text = new TextDecoder().decode(chunk);
      if (fd === 1) {
        // stdout
        self.postMessage({ type: 'stdout', data: text });
      } else if (fd === 2) {
        // stderr
        self.postMessage({ type: 'stderr', data: text });
      }

      written += bufLen;
    }

    dataView.setUint32(nwrittenPtr, written, true);
    return 0;
  },

  fdRead: function(fd, iovsPtr, iovsLen, nreadPtr, memory) {
    // In initial version, no stdin support. Return EOF immediately.
    var dataView = new DataView(memory.buffer);
    dataView.setUint32(nreadPtr, 0, true);
    return 0;
  },

  reset: function() {
    this.fdState[0].pos = 0;
    this.fdState[0].data = new Uint8Array(0);
    this.fdState[1].data = [];
    this.fdState[2].data = [];
  }
};

function WasiExit(code) {
  this.code = code;
  this.message = 'WASI exit code ' + code;
}

// Handle messages from main thread
self.onmessage = function(ev) {
  var msg = ev.data;
  if (msg.type === 'run') {
    runProgram(msg.wasmBytes);
  }
};

function runProgram(wasmBytes) {
  if (isRunning) return;
  isRunning = true;

  try {
    WasiContext.reset();

    // Create WASI imports
    var wasmImports = {
      wasi_snapshot_preview1: {
        fd_write: function(fd, iovs, iovs_len, nwritten) {
          return WasiContext.fdWrite(fd, iovs, iovs_len, nwritten, currentInstance.exports.memory);
        },
        fd_read: function(fd, iovs, iovs_len, nread) {
          return WasiContext.fdRead(fd, iovs, iovs_len, nread, currentInstance.exports.memory);
        },
        proc_exit: function(code) {
          throw new WasiExit(code);
        },
        args_get: function(argv, buf) {
          return 0;
        },
        args_sizes_get: function(argc, buf_size) {
          var dv = new DataView(currentInstance.exports.memory.buffer);
          dv.setUint32(argc, 0, true);
          dv.setUint32(buf_size, 0, true);
          return 0;
        }
      }
    };

    // Instantiate and run
    var module = new WebAssembly.Module(wasmBytes);
    currentInstance = new WebAssembly.Instance(module, wasmImports);

    try {
      currentInstance.exports._start();
    } catch (e) {
      if (!(e instanceof WasiExit)) throw e;
      // Exit via proc_exit
      self.postMessage({ type: 'exit', code: e.code });
      isRunning = false;
      return;
    }

    // If no exception, assume success
    self.postMessage({ type: 'exit', code: 0 });
    isRunning = false;
  } catch (e) {
    self.postMessage({ type: 'error', message: String(e) });
    isRunning = false;
  }
}
