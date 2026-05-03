// Compact Pascal compiler module
// Made by a machine. PUBLIC DOMAIN (CC0-1.0)

use crate::wasi::{WasiContext, StdioBuffer};
use std::error::Error;
use std::fmt;
use wasmi::{Engine, Linker, Module};

#[derive(Debug)]
pub enum CompileError {
    Instantiation(String),
    Compilation(String),
}

impl fmt::Display for CompileError {
    fn fmt(&self, f: &mut fmt::Formatter) -> fmt::Result {
        match self {
            CompileError::Instantiation(e) => write!(f, "instantiation error: {e}"),
            CompileError::Compilation(e) => write!(f, "compilation error: {e}"),
        }
    }
}

impl Error for CompileError {}

pub struct CompileResult {
    pub wasm: Vec<u8>,
    pub stderr: String,
}

pub struct Compiler {
    snapshot: &'static [u8],
}

impl Compiler {
    pub fn new() -> Self {
        Compiler {
            snapshot: include_bytes!("../../snapshot/compiler.wasm"),
        }
    }

    pub fn compile(&self, source: &str) -> Result<CompileResult, CompileError> {
        let engine = Engine::default();
        let mut linker: Linker<WasiContext> = Linker::new(&engine);

        crate::wasi::add_wasi_imports(&mut linker)
            .map_err(|e| CompileError::Instantiation(format!("{e}")))?;

        let mut ctx = WasiContext::new();
        ctx.stdin = StdioBuffer::from_bytes(source.as_bytes());
        let mut store = wasmi::Store::new(&engine, ctx);

        let module = Module::new(&engine, self.snapshot)
            .map_err(|e| CompileError::Instantiation(format!("{e}")))?;

        let instance = linker
            .instantiate_and_start(&mut store, &module)
            .map_err(|e| CompileError::Instantiation(format!("{e}")))?;

        let start = instance
            .get_export(&store, "_start")
            .and_then(|e| e.into_func())
            .ok_or_else(|| CompileError::Instantiation("_start not found".into()))?;

        // proc_exit traps — a successful compilation exits with code 0
        let run_err = start.call(&mut store, &[], &mut []).err();

        let ctx = store.into_data();
        let stderr_str = String::from_utf8_lossy(&ctx.stderr.into_bytes()).into_owned();
        let wasm = ctx.stdout.into_bytes();

        if let Some(e) = run_err {
            let msg = e.to_string();
            if !msg.contains("proc_exit(0)") {
                return Err(CompileError::Compilation(
                    if stderr_str.is_empty() { msg } else { stderr_str }
                ));
            }
        }

        Ok(CompileResult { wasm, stderr: stderr_str })
    }
}

impl Default for Compiler {
    fn default() -> Self {
        Compiler::new()
    }
}
