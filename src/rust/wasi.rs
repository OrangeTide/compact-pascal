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

/// WASI context holding I/O buffers
pub struct WasiContext {
    pub stdin: StdioBuffer,
    pub stdout: StdioBuffer,
    pub stderr: StdioBuffer,
    pub use_real_io: bool,
}

impl WasiContext {
    pub fn new() -> Self {
        WasiContext {
            stdin: StdioBuffer::new(),
            stdout: StdioBuffer::new(),
            stderr: StdioBuffer::new(),
            use_real_io: false,
        }
    }

    pub fn with_real_io() -> Self {
        WasiContext {
            stdin: StdioBuffer::new(),
            stdout: StdioBuffer::new(),
            stderr: StdioBuffer::new(),
            use_real_io: true,
        }
    }
}

/// Add WASI preview 1 imports to the linker
pub fn add_wasi_imports(
    linker: &mut Linker<WasiContext>,
) -> Result<(), Box<dyn std::error::Error>> {
    linker.func_wrap("wasi_snapshot_preview1", "fd_write",
        |mut caller: Caller<'_, WasiContext>, fd: i32, iovs: i32, iovs_len: i32, nwritten_ptr: i32| -> i32 {
            let memory = match caller.get_export("memory").and_then(|e| e.into_memory()) {
                Some(m) => m,
                None => return 8,
            };

            let mut total: u32 = 0;

            for i in 0..iovs_len as u32 {
                let iov_addr = (iovs as u32) + i * 8;
                let (buf_ptr, buf_len) = match read_iovec(&caller, &memory, iov_addr) {
                    Some(v) => v,
                    None => return 8,
                };

                let chunk = {
                    let data = memory.data(&caller);
                    let end = (buf_ptr + buf_len) as usize;
                    if end > data.len() {
                        return 8;
                    }
                    data[buf_ptr as usize..end].to_vec()
                };

                let ctx = caller.data_mut();
                if ctx.use_real_io && (fd == 1 || fd == 2) {
                    use std::io::Write;
                    if fd == 1 {
                        let _ = std::io::stdout().write_all(&chunk);
                    } else {
                        let _ = std::io::stderr().write_all(&chunk);
                    }
                } else if fd == 1 {
                    ctx.stdout.write(&chunk);
                } else if fd == 2 {
                    ctx.stderr.write(&chunk);
                }
                total += buf_len;
            }

            write_u32(&mut caller, &memory, nwritten_ptr as u32, total);
            0
        }
    )?;

    linker.func_wrap("wasi_snapshot_preview1", "fd_read",
        |mut caller: Caller<'_, WasiContext>, fd: i32, iovs: i32, iovs_len: i32, nread_ptr: i32| -> i32 {
            let memory = match caller.get_export("memory").and_then(|e| e.into_memory()) {
                Some(m) => m,
                None => return 8,
            };

            let mut total: u32 = 0;

            for i in 0..iovs_len as u32 {
                let iov_addr = (iovs as u32) + i * 8;
                let (buf_ptr, buf_len) = match read_iovec(&caller, &memory, iov_addr) {
                    Some(v) => v,
                    None => return 8,
                };

                if fd == 0 {
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
                    if dst + n > mem.len() {
                        return 8;
                    }
                    mem[dst..dst + n].copy_from_slice(&tmp);
                    total += n as u32;
                    if (n as u32) < buf_len {
                        break;
                    }
                }
            }

            write_u32(&mut caller, &memory, nread_ptr as u32, total);
            0
        }
    )?;

    linker.func_wrap("wasi_snapshot_preview1", "proc_exit",
        |_caller: Caller<'_, WasiContext>, code: i32| -> Result<(), wasmi::Error> {
            Err(wasmi::Error::new(format!("proc_exit({})", code)))
        }
    )?;

    linker.func_wrap("wasi_snapshot_preview1", "args_sizes_get",
        |mut caller: Caller<'_, WasiContext>, argc_ptr: i32, argv_buf_size_ptr: i32| -> i32 {
            let memory = match caller.get_export("memory").and_then(|e| e.into_memory()) {
                Some(m) => m,
                None => return 8,
            };
            write_u32(&mut caller, &memory, argc_ptr as u32, 0);
            write_u32(&mut caller, &memory, argv_buf_size_ptr as u32, 0);
            0
        }
    )?;

    linker.func_wrap("wasi_snapshot_preview1", "args_get",
        |_caller: Caller<'_, WasiContext>, _argv_ptr: i32, _argv_buf_ptr: i32| -> i32 {
            0
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

fn write_u32(caller: &mut Caller<'_, WasiContext>, memory: &wasmi::Memory, addr: u32, val: u32) {
    let mem = memory.data_mut(caller);
    let a = addr as usize;
    if a + 4 <= mem.len() {
        mem[a..a + 4].copy_from_slice(&val.to_le_bytes());
    }
}
