// Compiled WASM instance module
// Made by a machine. PUBLIC DOMAIN (CC0-1.0)

use crate::wasi::WasiContext;
use std::error::Error;
use std::fmt;
use wasmi::{Engine, Linker, Module, Instance as WasmiInstance};

#[derive(Debug)]
pub enum RuntimeError {
    Instantiation(String),
    Execution(String),
    FunctionNotFound(String),
}

impl fmt::Display for RuntimeError {
    fn fmt(&self, f: &mut fmt::Formatter) -> fmt::Result {
        match self {
            RuntimeError::Instantiation(e) => write!(f, "instantiation error: {e}"),
            RuntimeError::Execution(e) => write!(f, "execution error: {e}"),
            RuntimeError::FunctionNotFound(e) => write!(f, "function not found: {e}"),
        }
    }
}

impl Error for RuntimeError {}

pub struct Instance {
    store: wasmi::Store<WasiContext>,
    instance: WasmiInstance,
}

impl Instance {
    pub fn new(wasm: &[u8]) -> Result<Self, RuntimeError> {
        let engine = Engine::default();
        let mut linker: Linker<WasiContext> = Linker::new(&engine);

        crate::wasi::add_wasi_imports(&mut linker)
            .map_err(|e| RuntimeError::Instantiation(format!("{e}")))?;

        let ctx = WasiContext::with_real_io();
        let mut store = wasmi::Store::new(&engine, ctx);

        let module = Module::new(&engine, wasm)
            .map_err(|e| RuntimeError::Instantiation(format!("{e}")))?;

        let instance = linker
            .instantiate_and_start(&mut store, &module)
            .map_err(|e| RuntimeError::Instantiation(format!("{e}")))?;

        Ok(Instance { store, instance })
    }

    pub fn run(&mut self) -> Result<(), RuntimeError> {
        self.call("_start")
    }

    pub fn call(&mut self, name: &str) -> Result<(), RuntimeError> {
        let func = self
            .instance
            .get_export(&self.store, name)
            .and_then(|e| e.into_func())
            .ok_or_else(|| RuntimeError::FunctionNotFound(name.into()))?;

        match func.call(&mut self.store, &[], &mut []) {
            Ok(()) => Ok(()),
            Err(e) => {
                let msg = e.to_string();
                if msg.contains("proc_exit(0)") {
                    Ok(())
                } else {
                    Err(RuntimeError::Execution(msg))
                }
            }
        }
    }
}
