//! WASI preview 1 implementation for wasmi
//! Made by a machine. PUBLIC DOMAIN (CC0-1.0)

use std::cell::RefCell;
use std::rc::Rc;
use std::sync::{Arc, Mutex};
use wasmi::{AsContextMut, Caller, Linker};

/// WASI I/O buffer for capturing/providing data
#[derive(Clone)]
pub struct StdioBuffer {
    data: Rc<RefCell<Vec<u8>>>,
    read_pos: Rc<RefCell<usize>>,
}

impl StdioBuffer {
    pub fn new(capacity: usize) -> Self {
        StdioBuffer {
            data: Rc::new(RefCell::new(Vec::with_capacity(capacity))),
            read_pos: Rc::new(RefCell::new(0)),
        }
    }

    pub fn from_bytes(bytes: &[u8]) -> Self {
        let buf = StdioBuffer::new(bytes.len());
        *buf.data.borrow_mut() = bytes.to_vec();
        buf
    }

    pub fn write(&self, data: &[u8]) -> std::io::Result<usize> {
        self.data.borrow_mut().extend_from_slice(data);
        Ok(data.len())
    }

    pub fn read(&self, buf: &mut [u8]) -> std::io::Result<usize> {
        let data = self.data.borrow();
        let mut pos = self.read_pos.borrow_mut();

        if *pos >= data.len() {
            return Ok(0);
        }

        let remaining = data.len() - *pos;
        let to_read = buf.len().min(remaining);
        buf[..to_read].copy_from_slice(&data[*pos..*pos + to_read]);
        *pos += to_read;
        Ok(to_read)
    }

    pub fn get_bytes(&self) -> Vec<u8> {
        self.data.borrow().clone()
    }
}

/// WASI context holding I/O buffers
pub struct WasiContext {
    stdin: Arc<Mutex<StdioBuffer>>,
    stdout: Arc<Mutex<StdioBuffer>>,
    stderr: Arc<Mutex<StdioBuffer>>,
}

impl WasiContext {
    pub fn new() -> Self {
        WasiContext {
            stdin: Arc::new(Mutex::new(StdioBuffer::new(0))),
            stdout: Arc::new(Mutex::new(StdioBuffer::new(256 * 1024))),
            stderr: Arc::new(Mutex::new(StdioBuffer::new(8 * 1024))),
        }
    }

    pub fn set_stdin(&mut self, buf: StdioBuffer) {
        self.stdin = Arc::new(Mutex::new(buf));
    }

    pub fn set_stdout(&mut self, buf: StdioBuffer) {
        self.stdout = Arc::new(Mutex::new(buf));
    }

    pub fn set_stderr(&mut self, buf: StdioBuffer) {
        self.stderr = Arc::new(Mutex::new(buf));
    }

    pub fn get_stdout_bytes(&self) -> Vec<u8> {
        self.stdout.lock().unwrap().get_bytes()
    }

    pub fn get_stderr_bytes(&self) -> Vec<u8> {
        self.stderr.lock().unwrap().get_bytes()
    }
}

impl Default for WasiContext {
    fn default() -> Self {
        WasiContext::new()
    }
}

/// Add WASI preview 1 imports to the linker
pub fn add_wasi_imports(
    linker: &mut Linker<WasiContext>,
) -> Result<(), Box<dyn std::error::Error>> {
    // fd_write: write to file descriptor
    linker.func_wrap("wasi_snapshot_preview1", "fd_write",
        |mut caller: Caller<'_, WasiContext>, fd: i32, iovs: i32, iovs_len: i32, nwritten_ptr: i32| -> i32 {
            let memory = match caller.get_export("memory").and_then(|e| e.into_memory()) {
                Some(m) => m,
                None => return 8, // EBADF
            };

            let mut total_written = 0u32;

            for i in 0..iovs_len as u32 {
                let iov_addr = (iovs as u32) + i * 8;

                // Read iovec: [buf_ptr: u32, buf_len: u32]
                let buf_ptr_bytes = match read_mem(&caller, &memory, iov_addr, 4) {
                    Ok(b) => b,
                    Err(_) => return 8,
                };
                let buf_ptr = u32::from_le_bytes([buf_ptr_bytes[0], buf_ptr_bytes[1], buf_ptr_bytes[2], buf_ptr_bytes[3]]);

                let buf_len_bytes = match read_mem(&caller, &memory, iov_addr + 4, 4) {
                    Ok(b) => b,
                    Err(_) => return 8,
                };
                let buf_len = u32::from_le_bytes([buf_len_bytes[0], buf_len_bytes[1], buf_len_bytes[2], buf_len_bytes[3]]);

                // Read buffer data
                let buf_data = match read_mem(&caller, &memory, buf_ptr, buf_len) {
                    Ok(b) => b,
                    Err(_) => return 8,
                };

                // Write to appropriate output
                let ctx = caller.data_mut();
                if fd == 1 {
                    // stdout
                    let _ = ctx.stdout.lock().unwrap().write(&buf_data).ok();
                } else if fd == 2 {
                    // stderr
                    let _ = ctx.stderr.lock().unwrap().write(&buf_data).ok();
                }

                total_written += buf_len;
            }

            // Write nwritten
            let nwritten_bytes = total_written.to_le_bytes().to_vec();
            if write_mem(&mut caller, &memory, nwritten_ptr as u32, &nwritten_bytes).is_err() {
                return 8;
            }

            0
        }
    )?;

    // fd_read: read from file descriptor
    linker.func_wrap("wasi_snapshot_preview1", "fd_read",
        |mut caller: Caller<'_, WasiContext>, fd: i32, iovs: i32, iovs_len: i32, nread_ptr: i32| -> i32 {
            let memory = match caller.get_export("memory").and_then(|e| e.into_memory()) {
                Some(m) => m,
                None => return 8,
            };

            let mut total_read = 0u32;

            for i in 0..iovs_len as u32 {
                let iov_addr = (iovs as u32) + i * 8;

                // Read iovec: [buf_ptr: u32, buf_len: u32]
                let buf_ptr_bytes = match read_mem(&caller, &memory, iov_addr, 4) {
                    Ok(b) => b,
                    Err(_) => return 8,
                };
                let buf_ptr = u32::from_le_bytes([buf_ptr_bytes[0], buf_ptr_bytes[1], buf_ptr_bytes[2], buf_ptr_bytes[3]]);

                let buf_len_bytes = match read_mem(&caller, &memory, iov_addr + 4, 4) {
                    Ok(b) => b,
                    Err(_) => return 8,
                };
                let buf_len = u32::from_le_bytes([buf_len_bytes[0], buf_len_bytes[1], buf_len_bytes[2], buf_len_bytes[3]]);

                // Read from stdin if fd == 0
                if fd == 0 {
                    let mut buf = vec![0u8; buf_len as usize];
                    let n = {
                        let ctx = caller.data();
                        ctx.stdin.lock().unwrap().read(&mut buf).unwrap_or(0)
                    };
                    buf.truncate(n);
                    if write_mem(&mut caller, &memory, buf_ptr, &buf).is_err() {
                        return 8;
                    }
                    total_read += n as u32;

                    if n < buf_len as usize {
                        break; // short read
                    }
                }
            }

            // Write nread
            let nread_bytes = total_read.to_le_bytes().to_vec();
            if write_mem(&mut caller, &memory, nread_ptr as u32, &nread_bytes).is_err() {
                return 8;
            }

            0
        }
    )?;

    // proc_exit: exit the program (just returns, allowing natural exit)
    linker.func_wrap("wasi_snapshot_preview1", "proc_exit",
        |_caller: Caller<'_, WasiContext>, _code: i32| {
            // In the compiler context, we don't actually exit; we let the program complete
        }
    )?;

    // args_sizes_get: return argc and argv buffer size
    linker.func_wrap("wasi_snapshot_preview1", "args_sizes_get",
        |mut caller: Caller<'_, WasiContext>, argc_ptr: i32, argv_buf_size_ptr: i32| -> i32 {
            let memory = match caller.get_export("memory").and_then(|e| e.into_memory()) {
                Some(m) => m,
                None => return 8,
            };

            // Return argc = 0, argv_buf_size = 0
            let zero = 0u32.to_le_bytes().to_vec();
            if write_mem(&mut caller, &memory, argc_ptr as u32, &zero).is_err() {
                return 8;
            }
            if write_mem(&mut caller, &memory, argv_buf_size_ptr as u32, &zero).is_err() {
                return 8;
            }

            0
        }
    )?;

    // args_get: get command-line arguments (empty for now)
    linker.func_wrap("wasi_snapshot_preview1", "args_get",
        |_caller: Caller<'_, WasiContext>, _argv_ptr: i32, _argv_buf_ptr: i32| {
            // argc=0, so no arguments to provide
            0i32
        }
    )?;

    Ok(())
}

/// Helper: read bytes from WASM memory
fn read_mem(
    caller: &Caller<'_, WasiContext>,
    memory: &wasmi::Memory,
    addr: u32,
    len: u32,
) -> Result<Vec<u8>, ()> {
    let data = memory.data(&caller);
    let addr = addr as usize;
    let len = len as usize;

    if addr + len > data.len() {
        return Err(());
    }

    Ok(data[addr..addr + len].to_vec())
}

/// Helper: write bytes to WASM memory
fn write_mem(
    caller: &mut Caller<'_, WasiContext>,
    memory: &wasmi::Memory,
    addr: u32,
    data: &[u8],
) -> Result<(), ()> {
    let addr = addr as usize;
    let data_len = data.len();

    let mut ctx = caller.as_context_mut();
    let mem = memory.data_mut(&mut ctx);
    if addr + data_len > mem.len() {
        return Err(());
    }

    mem[addr..addr + data_len].copy_from_slice(data);
    Ok(())
}
