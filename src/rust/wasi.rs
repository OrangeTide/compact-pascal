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
/// `EINVAL` — the guest passed something malformed, such as a non-UTF-8 path.
pub const ERRNO_INVAL: i32 = 28;
/// `ENOENT` — no such file.
pub const ERRNO_NOENT: i32 = 44;
/// `ENOTCAPABLE` — the host has not granted this capability.
pub const ERRNO_NOTCAPABLE: i32 = 76;

/// Map a host I/O error onto a WASI errno. Only the cases a guest can act on
/// are distinguished; everything else is reported as EIO.
fn io_errno(e: &std::io::Error) -> i32 {
    match e.kind() {
        std::io::ErrorKind::NotFound => ERRNO_NOENT,
        std::io::ErrorKind::PermissionDenied => 2,
        _ => 29,
    }
}

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
    /// Directory the guest may open files in. `None`, the default, refuses
    /// every open: the compiler snapshot declares path_open so it can resolve
    /// includes, and declaring is not the same as being allowed.
    pub preopen_dir: Option<std::path::PathBuf>,
    open_files: std::collections::HashMap<i32, std::fs::File>,
    next_fd: i32,
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
            preopen_dir: None,
            open_files: std::collections::HashMap::new(),
            next_fd: 4,
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
            preopen_dir: None,
            open_files: std::collections::HashMap::new(),
            next_fd: 4,
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
            // stdout, stderr, or a file this host opened. Anything else is
            // reported rather than accepted and dropped, which would look to
            // the guest like a successful write to a file it never opened.
            if fd != 1 && fd != 2 && !caller.data().open_files.contains_key(&fd) {
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
                if let Some(file) = ctx.open_files.get_mut(&fd) {
                    use std::io::Write;
                    if file.write_all(&chunk).is_err() {
                        return 29;
                    }
                } else if ctx.use_real_io {
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
            // stdin, or a file this host opened. Previously any other fd fell
            // through the loop and reported a successful read of zero bytes,
            // which a guest reads as end of file rather than as an error.
            if fd != 0 && !caller.data().open_files.contains_key(&fd) {
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
                let n = if let Some(file) = caller.data_mut().open_files.get_mut(&fd) {
                    use std::io::Read;
                    file.read(&mut tmp).unwrap_or(0)
                } else if caller.data().use_real_io {
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

    // The compiler snapshot imports path_open and fd_close so it can resolve
    // {$I} includes itself. A module declares those whether or not it calls
    // them, so they must be linked or nothing instantiates.
    //
    // Both refuse by default. A host that wants a guest to reach the
    // filesystem opts in by setting WasiContext::preopen_dir, which is the
    // same shape as `uses Files` on the guest side: capability is
    // granted, never assumed.
    linker.func_wrap("wasi_snapshot_preview1", "path_open",
        |mut caller: Caller<'_, WasiContext>,
         _dirfd: i32, _dirflags: i32, path_ptr: i32, path_len: i32,
         oflags: i32, _rights: i64, _inheriting: i64, _fdflags: i32,
         opened_fd_ptr: i32| -> i32 {
            let Some(dir) = caller.data().preopen_dir.clone() else {
                return ERRNO_NOTCAPABLE;
            };
            let memory = match caller.get_export("memory").and_then(|e| e.into_memory()) {
                Some(m) => m,
                None => return ERRNO_FAULT,
            };

            let name = {
                let data = memory.data(&caller);
                let start = path_ptr as usize;
                let end = start + path_len as usize;
                if end > data.len() {
                    return ERRNO_FAULT;
                }
                match std::str::from_utf8(&data[start..end]) {
                    Ok(s) => s.to_string(),
                    Err(_) => return ERRNO_INVAL,
                }
            };

            // The guest's path is confined to the granted directory, for the
            // same reason expand_includes confines its own: joining an
            // absolute path onto a base discards the base.
            let requested = std::path::Path::new(&name);
            for component in requested.components() {
                match component {
                    std::path::Component::Normal(_) | std::path::Component::CurDir => {}
                    _ => return ERRNO_NOTCAPABLE,
                }
            }

            // oflags bit 0 is CREAT, bit 3 is TRUNC; the guest sets both to
            // rewrite and neither to read.
            let for_write = oflags & 0b1001 != 0;
            let path = dir.join(requested);
            let opened = if for_write {
                std::fs::File::create(&path)
            } else {
                std::fs::File::open(&path)
            };
            let file = match opened {
                Ok(f) => f,
                Err(e) => return io_errno(&e),
            };

            let ctx = caller.data_mut();
            let fd = ctx.next_fd;
            ctx.next_fd += 1;
            ctx.open_files.insert(fd, file);

            if !write_u32(&mut caller, &memory, opened_fd_ptr as u32, fd as u32) {
                return ERRNO_FAULT;
            }
            ERRNO_SUCCESS
        }
    )?;

    // The guest walks fd_prestat_get upward from 3 to find the directory it
    // was granted, because WASI does not fix which descriptor that is. This
    // host offers exactly one, on 3, and only when the caller granted it.
    //
    // Answering EBADF when nothing was granted is what makes the walk end
    // instead of running to its limit.
    linker.func_wrap("wasi_snapshot_preview1", "fd_prestat_get",
        |mut caller: Caller<'_, WasiContext>, fd: i32, prestat_ptr: i32| -> i32 {
            let Some(dir) = caller.data().preopen_dir.clone() else {
                return ERRNO_BADF;
            };
            if fd != 3 {
                return ERRNO_BADF;
            }
            let memory = match caller.get_export("memory").and_then(|e| e.into_memory()) {
                Some(m) => m,
                None => return ERRNO_FAULT,
            };
            // prestat is { tag: u8, pad, name_len: u32 }. Tag 0 is a
            // directory; the name is "." as far as a guest is concerned,
            // since every path it opens is already relative to this one.
            let name_len = dir.as_os_str().len().min(u32::MAX as usize) as u32;
            {
                let mem = memory.data_mut(&mut caller);
                let at = prestat_ptr as usize;
                if at + 8 > mem.len() {
                    return ERRNO_FAULT;
                }
                mem[at] = 0;
                mem[at + 1] = 0;
                mem[at + 2] = 0;
                mem[at + 3] = 0;
            }
            if !write_u32(&mut caller, &memory, prestat_ptr as u32 + 4, name_len) {
                return ERRNO_FAULT;
            }
            ERRNO_SUCCESS
        }
    )?;

    linker.func_wrap("wasi_snapshot_preview1", "fd_close",
        |mut caller: Caller<'_, WasiContext>, fd: i32| -> i32 {
            match caller.data_mut().open_files.remove(&fd) {
                Some(_) => ERRNO_SUCCESS,
                None => ERRNO_BADF,
            }
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
