// WASI preview 1 implementation for wasmi
// Made by a machine. PUBLIC DOMAIN (CC0-1.0)

use wasmi::{Caller, Linker};

/// WASI I/O buffer for capturing/providing data
pub struct StdioBuffer {
    data: Vec<u8>,
    read_pos: usize,
}

impl StdioBuffer {
    pub fn new() -> Self {
        StdioBuffer {
            data: Vec::new(),
            read_pos: 0,
        }
    }

    pub fn from_bytes(bytes: &[u8]) -> Self {
        StdioBuffer {
            data: bytes.to_vec(),
            read_pos: 0,
        }
    }

    pub fn write(&mut self, data: &[u8]) -> usize {
        self.data.extend_from_slice(data);
        data.len()
    }

    pub fn read(&mut self, buf: &mut [u8]) -> usize {
        if self.read_pos >= self.data.len() {
            return 0;
        }
        let remaining = self.data.len() - self.read_pos;
        let n = buf.len().min(remaining);
        buf[..n].copy_from_slice(&self.data[self.read_pos..self.read_pos + n]);
        self.read_pos += n;
        n
    }

    pub fn into_bytes(self) -> Vec<u8> {
        self.data
    }
}

/// WASI `errno` values this bridge can return. WASI defines many more; these
/// are the ones reachable from the three calls a Compact Pascal program makes.
pub const ERRNO_SUCCESS: i32 = 0;
/// `EBADF` — the file descriptor is not one this host serves.
pub const ERRNO_BADF: i32 = 8;
/// `EFAULT` — a pointer or length from the guest is outside linear memory.
pub const ERRNO_FAULT: i32 = 21;

/// WASI context holding I/O buffers and the argument vector.
pub struct WasiContext {
    pub stdin: StdioBuffer,
    pub stdout: StdioBuffer,
    pub stderr: StdioBuffer,
    pub use_real_io: bool,
    /// Arguments visible to the guest through `args_sizes_get`/`args_get`.
    /// By convention `args[0]` is the program name.
    pub args: Vec<String>,
    /// Ceiling on growable resources. wasmi asks for this through the store's
    /// limiter hook, which is why it lives on the context rather than beside
    /// the engine.
    pub limits: wasmi::StoreLimits,
}

impl WasiContext {
    pub fn new() -> Self {
        WasiContext {
            stdin: StdioBuffer::new(),
            stdout: StdioBuffer::new(),
            stderr: StdioBuffer::new(),
            use_real_io: false,
            args: Vec::new(),
            limits: wasmi::StoreLimitsBuilder::new().build(),
        }
    }

    pub fn with_real_io() -> Self {
        WasiContext {
            stdin: StdioBuffer::new(),
            stdout: StdioBuffer::new(),
            stderr: StdioBuffer::new(),
            use_real_io: true,
            args: Vec::new(),
            limits: wasmi::StoreLimitsBuilder::new().build(),
        }
    }

    /// Total bytes `args_get` will write into the argument buffer: every
    /// argument as a NUL-terminated C string, laid out end to end.
    fn args_buf_size(&self) -> u32 {
        self.args.iter().map(|a| a.len() as u32 + 1).sum()
    }
}

impl Default for WasiContext {
    fn default() -> Self {
        WasiContext::new()
    }
}

impl Default for StdioBuffer {
    fn default() -> Self {
        StdioBuffer::new()
    }
}

/// Add WASI preview 1 imports to the linker
pub fn add_wasi_imports(
    linker: &mut Linker<WasiContext>,
) -> Result<(), Box<dyn std::error::Error>> {
    linker.func_wrap("wasi_snapshot_preview1", "fd_write",
        |mut caller: Caller<'_, WasiContext>, fd: i32, iovs: i32, iovs_len: i32, nwritten_ptr: i32| -> i32 {
            // Only stdout and stderr exist. Anything else is reported rather
            // than accepted and dropped, which would look to the guest like a
            // successful write to a file that was never opened.
            if fd != 1 && fd != 2 {
                return ERRNO_BADF;
            }

            let memory = match caller.get_export("memory").and_then(|e| e.into_memory()) {
                Some(m) => m,
                None => return ERRNO_FAULT,
            };

            let mut total: u32 = 0;

            for i in 0..iovs_len as u32 {
                let iov_addr = (iovs as u32) + i * 8;
                let (buf_ptr, buf_len) = match read_iovec(&caller, &memory, iov_addr) {
                    Some(v) => v,
                    None => return ERRNO_FAULT,
                };

                let chunk = {
                    let data = memory.data(&caller);
                    let end = (buf_ptr as u64 + buf_len as u64) as usize;
                    if end > data.len() {
                        return ERRNO_FAULT;
                    }
                    data[buf_ptr as usize..end].to_vec()
                };

                let ctx = caller.data_mut();
                if ctx.use_real_io {
                    use std::io::Write;
                    if fd == 1 {
                        let _ = std::io::stdout().write_all(&chunk);
                    } else {
                        let _ = std::io::stderr().write_all(&chunk);
                    }
                } else if fd == 1 {
                    ctx.stdout.write(&chunk);
                } else {
                    ctx.stderr.write(&chunk);
                }
                total += buf_len;
            }

            if !write_u32(&mut caller, &memory, nwritten_ptr as u32, total) {
                return ERRNO_FAULT;
            }
            ERRNO_SUCCESS
        }
    )?;

    linker.func_wrap("wasi_snapshot_preview1", "fd_read",
        |mut caller: Caller<'_, WasiContext>, fd: i32, iovs: i32, iovs_len: i32, nread_ptr: i32| -> i32 {
            // Only stdin exists. Previously any other fd fell through the loop
            // and reported a successful read of zero bytes, which a guest
            // reads as end of file rather than as a bad descriptor.
            if fd != 0 {
                return ERRNO_BADF;
            }

            let memory = match caller.get_export("memory").and_then(|e| e.into_memory()) {
                Some(m) => m,
                None => return ERRNO_FAULT,
            };

            let mut total: u32 = 0;

            for i in 0..iovs_len as u32 {
                let iov_addr = (iovs as u32) + i * 8;
                let (buf_ptr, buf_len) = match read_iovec(&caller, &memory, iov_addr) {
                    Some(v) => v,
                    None => return ERRNO_FAULT,
                };

                let mut tmp = vec![0u8; buf_len as usize];
                let n = if caller.data().use_real_io {
                    use std::io::Read;
                    std::io::stdin().read(&mut tmp).unwrap_or(0)
                } else {
                    caller.data_mut().stdin.read(&mut tmp)
                };
                tmp.truncate(n);
                let mem = memory.data_mut(&mut caller);
                let dst = buf_ptr as usize;
                if dst as u64 + n as u64 > mem.len() as u64 {
                    return ERRNO_FAULT;
                }
                mem[dst..dst + n].copy_from_slice(&tmp);
                total += n as u32;
                if (n as u32) < buf_len {
                    break;
                }
            }

            if !write_u32(&mut caller, &memory, nread_ptr as u32, total) {
                return ERRNO_FAULT;
            }
            ERRNO_SUCCESS
        }
    )?;

    // proc_exit unwinds as a wasmi i32 exit status rather than a message. The
    // status survives as structured data, so a caller reads the exit code
    // instead of matching on the text of an error string.
    linker.func_wrap("wasi_snapshot_preview1", "proc_exit",
        |_caller: Caller<'_, WasiContext>, code: i32| -> Result<(), wasmi::Error> {
            Err(wasmi::Error::i32_exit(code))
        }
    )?;

    linker.func_wrap("wasi_snapshot_preview1", "args_sizes_get",
        |mut caller: Caller<'_, WasiContext>, argc_ptr: i32, argv_buf_size_ptr: i32| -> i32 {
            let memory = match caller.get_export("memory").and_then(|e| e.into_memory()) {
                Some(m) => m,
                None => return ERRNO_FAULT,
            };
            let argc = caller.data().args.len() as u32;
            let buf_size = caller.data().args_buf_size();
            if !write_u32(&mut caller, &memory, argc_ptr as u32, argc)
                || !write_u32(&mut caller, &memory, argv_buf_size_ptr as u32, buf_size)
            {
                return ERRNO_FAULT;
            }
            ERRNO_SUCCESS
        }
    )?;

    // Writes the argument strings end to end into argv_buf, each terminated by
    // NUL, and a pointer to each into argv. The guest is expected to have
    // called args_sizes_get first and sized both buffers from the answer.
    linker.func_wrap("wasi_snapshot_preview1", "args_get",
        |mut caller: Caller<'_, WasiContext>, argv_ptr: i32, argv_buf_ptr: i32| -> i32 {
            let memory = match caller.get_export("memory").and_then(|e| e.into_memory()) {
                Some(m) => m,
                None => return ERRNO_FAULT,
            };

            // Lay the strings out first so the loop below only copies bytes.
            let args: Vec<Vec<u8>> = caller
                .data()
                .args
                .iter()
                .map(|a| {
                    let mut b = a.as_bytes().to_vec();
                    b.push(0);
                    b
                })
                .collect();

            let mut buf_at = argv_buf_ptr as u32;
            for (i, bytes) in args.iter().enumerate() {
                if !write_u32(&mut caller, &memory, argv_ptr as u32 + (i as u32) * 4, buf_at) {
                    return ERRNO_FAULT;
                }
                {
                    let mem = memory.data_mut(&mut caller);
                    let start = buf_at as usize;
                    let end = start + bytes.len();
                    if end > mem.len() {
                        return ERRNO_FAULT;
                    }
                    mem[start..end].copy_from_slice(bytes);
                }
                buf_at += bytes.len() as u32;
            }
            ERRNO_SUCCESS
        }
    )?;

    Ok(())
}

fn read_iovec(caller: &Caller<'_, WasiContext>, memory: &wasmi::Memory, addr: u32) -> Option<(u32, u32)> {
    let data = memory.data(caller);
    let a = addr as usize;
    if a + 8 > data.len() {
        return None;
    }
    let buf_ptr = u32::from_le_bytes(data[a..a + 4].try_into().unwrap());
    let buf_len = u32::from_le_bytes(data[a + 4..a + 8].try_into().unwrap());
    Some((buf_ptr, buf_len))
}

/// Returns false when the address is outside linear memory, so the caller can
/// answer EFAULT instead of reporting a success that never happened.
fn write_u32(caller: &mut Caller<'_, WasiContext>, memory: &wasmi::Memory, addr: u32, val: u32) -> bool {
    let mem = memory.data_mut(caller);
    let a = addr as usize;
    if a + 4 > mem.len() {
        return false;
    }
    mem[a..a + 4].copy_from_slice(&val.to_le_bytes());
    true
}
