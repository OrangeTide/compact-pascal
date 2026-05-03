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

    fn get_memory(&self) -> Result<wasmi::Memory, RuntimeError> {
        self.instance
            .get_export(&self.store, "memory")
            .and_then(|e| e.into_memory())
            .ok_or_else(|| {
                RuntimeError::Execution("memory export not found".into())
            })
    }

    /// Write a Rust string into WASM memory as a Pascal short string at `addr`.
    /// Returns the number of bytes written (1 + len), or error if len > 255 or out of bounds.
    ///
    /// Pascal short string layout:
    /// - Byte 0: length (0-255)
    /// - Bytes 1..1+length: string data
    pub fn write_pascal_string(&mut self, addr: u32, s: &str) -> Result<usize, RuntimeError> {
        let bytes = s.as_bytes();
        let len = bytes.len();

        if len > 255 {
            return Err(RuntimeError::Execution(
                format!("string too long: {} bytes (max 255)", len)
            ));
        }

        let memory = self.get_memory()?;
        let mem = memory.data_mut(&mut self.store);

        let start = addr as usize;
        let end = start + 1 + len;

        if end > mem.len() {
            return Err(RuntimeError::Execution(
                format!("write_pascal_string out of bounds: addr={} len={}", addr, len)
            ));
        }

        mem[start] = len as u8;
        mem[start + 1..end].copy_from_slice(bytes);

        Ok(1 + len)
    }

    /// Read a Pascal short string from WASM memory at `addr` into a Rust String.
    /// Returns error if the string extends past memory bounds or contains invalid UTF-8.
    pub fn read_pascal_string(&self, addr: u32) -> Result<String, RuntimeError> {
        let bytes = self.read_pascal_bytes(addr)?;
        String::from_utf8(bytes).map_err(|e| {
            RuntimeError::Execution(format!("invalid UTF-8 in pascal string: {}", e))
        })
    }

    /// Read a Pascal short string as raw bytes (no UTF-8 validation).
    pub fn read_pascal_bytes(&self, addr: u32) -> Result<Vec<u8>, RuntimeError> {
        let memory = self.get_memory()?;
        let mem = memory.data(&self.store);

        let start = addr as usize;

        if start >= mem.len() {
            return Err(RuntimeError::Execution(
                format!("read_pascal_string out of bounds: addr={}", addr)
            ));
        }

        let len = mem[start] as usize;
        let end = start + 1 + len;

        if end > mem.len() {
            return Err(RuntimeError::Execution(
                format!("read_pascal_string out of bounds: addr={} len={}", addr, len)
            ));
        }

        Ok(mem[start + 1..end].to_vec())
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    fn create_test_instance() -> Result<Instance, RuntimeError> {
        // Use the compiler to create a minimal WASM module with memory
        let compiler = crate::compiler::Compiler::new();
        let result = compiler
            .compile("program T; begin end.")
            .map_err(|e| RuntimeError::Instantiation(format!("{}", e)))?;

        Instance::new(&result.wasm)
    }

    #[test]
    fn test_write_and_read_pascal_string() -> Result<(), RuntimeError> {
        let mut instance = create_test_instance()?;

        instance.write_pascal_string(0, "hello")?;
        let result = instance.read_pascal_string(0)?;

        assert_eq!(result, "hello");
        Ok(())
    }

    #[test]
    fn test_empty_pascal_string() -> Result<(), RuntimeError> {
        let mut instance = create_test_instance()?;

        instance.write_pascal_string(0, "")?;
        let result = instance.read_pascal_string(0)?;

        assert_eq!(result, "");
        Ok(())
    }

    #[test]
    fn test_max_length_pascal_string() -> Result<(), RuntimeError> {
        let mut instance = create_test_instance()?;

        let max_str = "a".repeat(255);
        instance.write_pascal_string(0, &max_str)?;
        let result = instance.read_pascal_string(0)?;

        assert_eq!(result.len(), 255);
        assert_eq!(result, max_str);
        Ok(())
    }

    #[test]
    fn test_string_too_long_error() {
        let mut instance = create_test_instance().unwrap();

        let too_long = "a".repeat(256);
        let result = instance.write_pascal_string(0, &too_long);

        assert!(result.is_err());
        if let Err(RuntimeError::Execution(msg)) = result {
            assert!(msg.contains("string too long"));
        } else {
            panic!("Expected Execution error");
        }
    }

    #[test]
    fn test_roundtrip_with_spaces() -> Result<(), RuntimeError> {
        let mut instance = create_test_instance()?;

        let test_str = "hello world with spaces";
        instance.write_pascal_string(100, test_str)?;
        let result = instance.read_pascal_string(100)?;

        assert_eq!(result, test_str);
        Ok(())
    }

    #[test]
    fn test_read_pascal_bytes() -> Result<(), RuntimeError> {
        let mut instance = create_test_instance()?;

        instance.write_pascal_string(0, "test")?;
        let bytes = instance.read_pascal_bytes(0)?;

        assert_eq!(bytes, b"test".to_vec());
        Ok(())
    }

    #[test]
    fn test_multiple_strings_in_memory() -> Result<(), RuntimeError> {
        let mut instance = create_test_instance()?;

        instance.write_pascal_string(0, "first")?;
        instance.write_pascal_string(100, "second")?;

        let s1 = instance.read_pascal_string(0)?;
        let s2 = instance.read_pascal_string(100)?;

        assert_eq!(s1, "first");
        assert_eq!(s2, "second");
        Ok(())
    }
}
