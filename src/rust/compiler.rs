//! Compact Pascal compiler module
//! Made by a machine. PUBLIC DOMAIN (CC0-1.0)

use crate::wasi::{WasiContext, StdioBuffer};
use std::error::Error;
use std::fmt;
use wasmi::{Engine, Linker, Module};

/// Error type for compilation
#[derive(Debug)]
pub enum CompileError {
    Instantiation(String),
    Execution(String),
    Io(String),
    Other(String),
}

impl fmt::Display for CompileError {
    fn fmt(&self, f: &mut fmt::Formatter) -> fmt::Result {
        match self {
            CompileError::Instantiation(e) => write!(f, "instantiation error: {}", e),
            CompileError::Execution(e) => write!(f, "execution error: {}", e),
            CompileError::Io(e) => write!(f, "I/O error: {}", e),
            CompileError::Other(e) => write!(f, "error: {}", e),
        }
    }
}

impl Error for CompileError {}

/// Result of compilation
pub struct CompileResult {
    pub wasm: Vec<u8>,
    pub stderr: String,
}

/// Compact Pascal compiler
pub struct Compiler {
    snapshot: Vec<u8>,
}

impl Compiler {
    /// Create a new compiler with the embedded snapshot
    pub fn new() -> Self {
        let snapshot = include_bytes!("../../snapshot/compiler.wasm").to_vec();
        Compiler { snapshot }
    }

    /// Compile Pascal source to WASM
    ///
    /// The compiler reads the Pascal source, compiles it to WASM,
    /// and captures any error messages from stderr.
    pub fn compile(&self, source: &str) -> Result<CompileResult, CompileError> {
        // Create engine and linker
        let engine = Engine::default();
        let mut linker: Linker<WasiContext> = Linker::new(&engine);

        // Create buffers for stdin (source), stdout (wasm), and stderr (errors)
        let stdin_buf = StdioBuffer::from_bytes(source.as_bytes());
        let stdout_buf = StdioBuffer::new(256 * 1024); // 256 KB for output
        let stderr_buf = StdioBuffer::new(8 * 1024);   // 8 KB for errors

        // Create WASI context
        let mut wasi_ctx = WasiContext::new();
        wasi_ctx.set_stdin(stdin_buf);
        wasi_ctx.set_stdout(stdout_buf);
        wasi_ctx.set_stderr(stderr_buf);

        // Add WASI imports to linker
        crate::wasi::add_wasi_imports(&mut linker)
            .map_err(|e| CompileError::Io(format!("failed to add WASI imports: {}", e)))?;

        // Create a store with the WASI context
        let mut store = wasmi::Store::new(&engine, wasi_ctx);

        // Parse the compiler snapshot
        let module = Module::new(&engine, &self.snapshot)
            .map_err(|e| CompileError::Instantiation(format!("failed to parse module: {}", e)))?;

        // Instantiate and start the compiler with WASI imports
        let instance = linker
            .instantiate_and_start(&mut store, &module)
            .map_err(|e| CompileError::Instantiation(format!("failed to instantiate: {}", e)))?;

        // Get the _start export and call it
        let start = instance
            .get_export(&store, "_start")
            .and_then(|e: wasmi::Extern| e.into_func())
            .ok_or_else(|| CompileError::Instantiation("_start function not found".to_string()))?;

        // Execute the compiler
        start
            .call(&mut store, &[], &mut [])
            .map_err(|e| CompileError::Execution(format!("execution failed: {}", e)))?;

        // Collect the output
        let stdout_data = store.data().get_stdout_bytes();
        let stderr_data = store.data().get_stderr_bytes();
        let stderr_str = String::from_utf8_lossy(&stderr_data).to_string();

        Ok(CompileResult {
            wasm: stdout_data,
            stderr: stderr_str,
        })
    }
}

impl Default for Compiler {
    fn default() -> Self {
        Compiler::new()
    }
}
