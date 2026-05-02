//! Compiled WASM instance module
//! Made by a machine. PUBLIC DOMAIN (CC0-1.0)

use crate::wasi::WasiContext;
use std::error::Error;
use std::fmt;
use wasmi::{Engine, Linker, Module, Instance as WasmiInstance};

/// Error type for runtime errors
#[derive(Debug)]
pub enum RuntimeError {
    Instantiation(String),
    Execution(String),
    FunctionNotFound(String),
    Other(String),
}

impl fmt::Display for RuntimeError {
    fn fmt(&self, f: &mut fmt::Formatter) -> fmt::Result {
        match self {
            RuntimeError::Instantiation(e) => write!(f, "instantiation error: {}", e),
            RuntimeError::Execution(e) => write!(f, "execution error: {}", e),
            RuntimeError::FunctionNotFound(e) => write!(f, "function not found: {}", e),
            RuntimeError::Other(e) => write!(f, "error: {}", e),
        }
    }
}

impl Error for RuntimeError {}

/// A compiled and instantiated WASM program
pub struct Instance {
    store: wasmi::Store<WasiContext>,
    instance: WasmiInstance,
}

impl Instance {
    /// Create a new instance from compiled WASM bytes
    pub fn new(wasm: &[u8]) -> Result<Self, RuntimeError> {
        let engine = Engine::default();
        let mut linker: Linker<WasiContext> = Linker::new(&engine);

        // Create WASI context
        let wasi_ctx = WasiContext::new();

        // Add WASI imports to linker
        crate::wasi::add_wasi_imports(&mut linker)
            .map_err(|e| RuntimeError::Instantiation(format!("failed to add WASI imports: {}", e)))?;

        // Create store with the WASI context
        let mut store = wasmi::Store::new(&engine, wasi_ctx);

        // Parse and instantiate the module
        let module = Module::new(&engine, wasm)
            .map_err(|e| RuntimeError::Instantiation(format!("failed to parse module: {}", e)))?;

        let instance = linker
            .instantiate_and_start(&mut store, &module)
            .map_err(|e| RuntimeError::Instantiation(format!("failed to instantiate: {}", e)))?;

        Ok(Instance { store, instance })
    }

    /// Run the _start export (entry point)
    pub fn run(&mut self) -> Result<(), RuntimeError> {
        self.call("_start")
    }

    /// Call an exported function by name
    pub fn call(&mut self, name: &str) -> Result<(), RuntimeError> {
        let func = self
            .instance
            .get_export(&self.store, name)
            .and_then(|e: wasmi::Extern| e.into_func())
            .ok_or_else(|| RuntimeError::FunctionNotFound(name.to_string()))?;

        func.call(&mut self.store, &[], &mut [])
            .map_err(|e| RuntimeError::Execution(format!("{}", e)))?;

        Ok(())
    }

    /// Get stdout as a string
    pub fn stdout(&self) -> String {
        String::from_utf8_lossy(&self.store.data().get_stdout_bytes()).to_string()
    }

    /// Get stderr as a string
    pub fn stderr(&self) -> String {
        String::from_utf8_lossy(&self.store.data().get_stderr_bytes()).to_string()
    }
}
