// Compact Pascal Playground - WASM Program Runner Worker

var currentInstance = null;
var isRunning = false;

// WASI context for the running program
var WasiContext = {
  fdState: {
    0: { data: null, pos: 0 },  // stdin
    1: { data: [], pos: 0 },    // stdout (raw bytes)
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

      if (fd === 2) {
        // stderr — always text, send immediately
        self.postMessage({ type: 'stderr', data: new TextDecoder().decode(chunk) });
      } else if (fd === 1) {
        // stdout — accumulate raw bytes
        for (var j = 0; j < chunk.length; j++) {
          this.fdState[1].data.push(chunk[j]);
        }
      }

      written += bufLen;
    }

    dataView.setUint32(nwrittenPtr, written, true);
    return 0;
  },

  fdRead: function(fd, iovsPtr, iovsLen, nreadPtr, memory) {
    var dataView = new DataView(memory.buffer);
    var view = new Uint8Array(memory.buffer);

    if (fd !== 0 || !this.fdState[0].data) {
      dataView.setUint32(nreadPtr, 0, true);
      return 0;
    }

    var src = this.fdState[0].data;
    var srcPos = this.fdState[0].pos;
    var nread = 0;

    for (var i = 0; i < iovsLen; i++) {
      var iovPtr = iovsPtr + (i * 8);
      var bufPtr = dataView.getUint32(iovPtr, true);
      var bufLen = dataView.getUint32(iovPtr + 4, true);

      var remaining = src.length - srcPos;
      var toRead = Math.min(bufLen, remaining);

      for (var j = 0; j < toRead; j++) {
        view[bufPtr + j] = src[srcPos + j];
      }

      srcPos += toRead;
      nread += toRead;

      if (toRead < bufLen) break;  // EOF reached
    }

    this.fdState[0].pos = srcPos;
    dataView.setUint32(nreadPtr, nread, true);
    return 0;
  },

  reset: function() {
    this.fdState[0].pos = 0;
    this.fdState[0].data = null;
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
    runProgram(msg.wasmBytes, msg.stdinData || null);
  }
};

function runProgram(wasmBytes, stdinData) {
  if (isRunning) return;
  isRunning = true;

  try {
    WasiContext.reset();
    if (stdinData) {
      WasiContext.fdState[0].data = stdinData;
    }

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

    var exitCode = 0;
    try {
      currentInstance.exports._start();
    } catch (e) {
      if (!(e instanceof WasiExit)) throw e;
      exitCode = e.code;
    }

    // Send stdout results
    var rawBytes = new Uint8Array(WasiContext.fdState[1].data);
    if (rawBytes.length > 0) {
      // Check if output looks like text (all bytes are printable ASCII/UTF-8)
      var isText = true;
      for (var i = 0; i < Math.min(rawBytes.length, 256); i++) {
        var b = rawBytes[i];
        if (b < 0x09 || (b > 0x0d && b < 0x20 && b !== 0x1b)) {
          isText = false;
          break;
        }
      }
      if (isText) {
        self.postMessage({ type: 'stdout', data: new TextDecoder().decode(rawBytes) });
      } else {
        self.postMessage({ type: 'stdout-binary', size: rawBytes.length, data: rawBytes.buffer }, [rawBytes.buffer]);
      }
    }

    self.postMessage({ type: 'exit', code: exitCode });
    isRunning = false;
  } catch (e) {
    self.postMessage({ type: 'error', message: String(e) });
    isRunning = false;
  }
}
