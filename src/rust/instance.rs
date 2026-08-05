// Compiled WASM instance module
// Made by a machine. PUBLIC DOMAIN (CC0-1.0)

use crate::wasi::WasiContext;
use std::error::Error;
use std::fmt;
use std::sync::Arc;
use wasmi::{Engine, FuncType, Linker, Module, Val, ValType, Instance as WasmiInstance};

#[derive(Debug)]
pub enum RuntimeError {
    Instantiation(String),
    /// A memory access through this API failed: the address is outside the
    /// guest's linear memory, the module has no memory export, or a string is
    /// too long or not valid UTF-8. Not raised by execution itself; a program
    /// that fails while running reports Exit or Trapped.
    Memory(String),
    FunctionNotFound(String),
    /// The program called `halt(n)` with a nonzero status. This is an ordinary
    /// way for a Pascal program to end, so it is reported separately from a
    /// trap and carries the status rather than a message about it.
    Exit(i32),
    /// The program trapped. `Trapped` names the WASM trap where one applies:
    /// `unreachable` is what the stack overflow guard, the frame balance
    /// check, and the nil check all raise, so seeing it usually means a check
    /// fired rather than that the module was malformed.
    Trapped(String),
}

impl RuntimeError {
    /// The exit status when the program ended by calling `halt`.
    pub fn exit_status(&self) -> Option<i32> {
        match self {
            RuntimeError::Exit(n) => Some(*n),
            _ => None,
        }
    }
}

impl fmt::Display for RuntimeError {
    fn fmt(&self, f: &mut fmt::Formatter) -> fmt::Result {
        match self {
            RuntimeError::Instantiation(e) => write!(f, "instantiation error: {e}"),
            RuntimeError::Memory(e) => write!(f, "memory error: {e}"),
            RuntimeError::FunctionNotFound(e) => write!(f, "function not found: {e}"),
            RuntimeError::Exit(n) => write!(f, "program exited with status {n}"),
            RuntimeError::Trapped(e) => write!(f, "trap: {e}"),
        }
    }
}

impl Error for RuntimeError {}

/// Turn a wasmi call error into a RuntimeError, treating exit status zero as
/// success. Every call site needs this, and getting it wrong here is how a
/// normal program termination turns into a spurious failure.
fn classify(e: wasmi::Error) -> Option<RuntimeError> {
    match e.i32_exit_status() {
        Some(0) => None,
        Some(n) => Some(RuntimeError::Exit(n)),
        None => Some(RuntimeError::Trapped(e.to_string())),
    }
}

/// Ceilings on what a compiled program may consume.
///
/// The WASM sandbox stops a guest reaching outside itself. It does not stop a
/// guest looping forever or growing memory until instantiation fails. Set
/// these when running source you did not write; leave them unset when the
/// program is your own and the overhead is not worth it.
#[derive(Debug, Clone, Default)]
pub struct Limits {
    /// Units of execution before the program traps. wasmi charges roughly one
    /// unit per instruction, so this bounds time without a wall clock and
    /// without a second thread. Enabling it costs some speed, which is why it
    /// is off unless asked for.
    pub fuel: Option<u64>,
    /// Ceiling on linear memory, in bytes. A guest that tries to grow past it
    /// gets a failed `memory.grow` rather than taking the host's memory with
    /// it. A Pascal program's `{$MAXMEMORY}` is its own ceiling; this one is
    /// the host's, and the lower of the two wins.
    pub memory_bytes: Option<usize>,
    /// Directory the program may open files in. `None`, the default, refuses
    /// every open, so a program compiled with `{$FILES ON}` runs but finds it
    /// has nothing to open. Paths are confined to this directory: `..`, an
    /// absolute path, and a drive prefix are all refused.
    pub preopen_dir: Option<std::path::PathBuf>,
}

impl Limits {
    fn store_limits(&self) -> wasmi::StoreLimits {
        let mut b = wasmi::StoreLimitsBuilder::new();
        if let Some(bytes) = self.memory_bytes {
            b = b.memory_size(bytes);
        }
        b.build()
    }
}

pub struct InstanceBuilder {
    engine: Engine,
    linker: Linker<WasiContext>,
    limits: Limits,
}

impl InstanceBuilder {
    pub fn new() -> Result<Self, RuntimeError> {
        InstanceBuilder::with_limits(Limits::default())
    }

    /// Build with resource ceilings. Fuel metering has to be switched on in
    /// the engine's configuration, so it is decided here rather than being
    /// settable later.
    pub fn with_limits(limits: Limits) -> Result<Self, RuntimeError> {
        let mut config = wasmi::Config::default();
        config.consume_fuel(limits.fuel.is_some());
        let engine = Engine::new(&config);
        let mut linker: Linker<WasiContext> = Linker::new(&engine);

        crate::wasi::add_wasi_imports(&mut linker)
            .map_err(|e| RuntimeError::Instantiation(format!("{e}")))?;

        Ok(InstanceBuilder { engine, linker, limits })
    }

    pub fn register_import<F>(
        &mut self,
        module: &str,
        name: &str,
        n_params: usize,
        has_return: bool,
        callback: F,
    ) -> Result<&mut Self, RuntimeError>
    where
        F: Fn(&[i32]) -> Option<i32> + Send + Sync + 'static,
    {
        let params = vec![ValType::I32; n_params];
        let results = if has_return { vec![ValType::I32] } else { vec![] };
        let ty = FuncType::new(params, results);

        let callback = Arc::new(callback);

        self.linker
            .func_new(module, name, ty, move |_caller, args, results| {
                let i32_args: Vec<i32> = args
                    .iter()
                    .map(|v| match v {
                        Val::I32(n) => *n,
                        _ => 0,
                    })
                    .collect();

                match callback(&i32_args) {
                    Some(ret) => {
                        if !results.is_empty() {
                            results[0] = Val::I32(ret);
                        }
                    }
                    None => {
                        if !results.is_empty() {
                            results[0] = Val::I32(0);
                        }
                    }
                }

                Ok(())
            })
            .map_err(|e| RuntimeError::Instantiation(format!("{e}")))?;

        Ok(self)
    }

    pub fn build(self, wasm: &[u8]) -> Result<Instance, RuntimeError> {
        let mut ctx = WasiContext::with_real_io();
        ctx.limits = self.limits.store_limits();
        ctx.preopen_dir = self.limits.preopen_dir.clone();
        let mut store = wasmi::Store::new(&self.engine, ctx);
        store.limiter(|ctx| &mut ctx.limits);
        if let Some(fuel) = self.limits.fuel {
            store
                .set_fuel(fuel)
                .map_err(|e| RuntimeError::Instantiation(format!("{e}")))?;
        }

        let module = Module::new(&self.engine, wasm)
            .map_err(|e| RuntimeError::Instantiation(format!("{e}")))?;

        let instance = self
            .linker
            .instantiate_and_start(&mut store, &module)
            .map_err(|e| RuntimeError::Instantiation(format!("{e}")))?;

        Ok(Instance { store, instance })
    }
}

impl Default for InstanceBuilder {
    fn default() -> Self {
        InstanceBuilder::new().expect("failed to create InstanceBuilder")
    }
}

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
            Err(e) => match classify(e) {
                Some(err) => Err(err),
                None => Ok(()),
            },
        }
    }

    pub fn call_args(
        &mut self,
        name: &str,
        args: &[i32],
    ) -> Result<Option<i32>, RuntimeError> {
        let func = self
            .instance
            .get_export(&self.store, name)
            .and_then(|e| e.into_func())
            .ok_or_else(|| RuntimeError::FunctionNotFound(name.into()))?;

        let wasm_args: Vec<Val> = args.iter().map(|&v| Val::I32(v)).collect();
        let ty = func.ty(&self.store);
        let n_results = ty.results().len();
        let mut results = vec![Val::I32(0); n_results];

        match func.call(&mut self.store, &wasm_args, &mut results) {
            Ok(()) => {}
            Err(e) => {
                if let Some(err) = classify(e) {
                    return Err(err);
                }
            }
        }

        if n_results > 0 {
            match &results[0] {
                Val::I32(v) => Ok(Some(*v)),
                _ => Ok(None),
            }
        } else {
            Ok(None)
        }
    }

    fn get_memory(&self) -> Result<wasmi::Memory, RuntimeError> {
        self.instance
            .get_export(&self.store, "memory")
            .and_then(|e| e.into_memory())
            .ok_or_else(|| {
                RuntimeError::Memory("memory export not found".into())
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
            return Err(RuntimeError::Memory(
                format!("string too long: {} bytes (max 255)", len)
            ));
        }

        let memory = self.get_memory()?;
        let mem = memory.data_mut(&mut self.store);

        let start = addr as usize;
        let end = start + 1 + len;

        if end > mem.len() {
            return Err(RuntimeError::Memory(
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
            RuntimeError::Memory(format!("invalid UTF-8 in pascal string: {}", e))
        })
    }

    /// Read a Pascal short string as raw bytes (no UTF-8 validation).
    pub fn read_pascal_bytes(&self, addr: u32) -> Result<Vec<u8>, RuntimeError> {
        let memory = self.get_memory()?;
        let mem = memory.data(&self.store);

        let start = addr as usize;

        if start >= mem.len() {
            return Err(RuntimeError::Memory(
                format!("read_pascal_string out of bounds: addr={}", addr)
            ));
        }

        let len = mem[start] as usize;
        let end = start + 1 + len;

        if end > mem.len() {
            return Err(RuntimeError::Memory(
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
        if let Err(RuntimeError::Memory(msg)) = result {
            assert!(msg.contains("string too long"));
        } else {
            panic!("Expected Memory error");
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

    /// The snapshot once hung compiling any source carrying both {$IMPORT}
    /// and `external`, so the FFI tests below shelled out to the native
    /// compiler instead. The cause was for-loop `continue` codegen dropping
    /// the increment, fixed in ee481a9; it was never an I/O problem. This
    /// test pins the wasmi path so the workaround cannot creep back.
    #[test]
    fn snapshot_compiles_import_bearing_source() {
        let source = r#"program T;
{$IMPORT 'host' log}
procedure Log(x: integer); external;
begin
  Log(42);
end.
"#;
        let wasm = compile_source(source);
        assert!(!wasm.is_empty(), "compiler produced no output");
        assert_eq!(&wasm[0..4], b"\0asm", "output is not a WASM module");
    }

    fn compile_source(source: &str) -> Vec<u8> {
        let compiler = crate::compiler::Compiler::new();
        compiler.compile(source).expect("compilation failed").wasm
    }


    #[test]
    fn test_builder_no_imports() -> Result<(), RuntimeError> {
        let wasm = compile_source("program T; begin end.");
        let mut instance = InstanceBuilder::new()?.build(&wasm)?;
        instance.run()
    }

    #[test]
    fn test_import_procedure() -> Result<(), RuntimeError> {
        let source = r#"program T;
{$IMPORT 'host' myProc}
procedure MyProc(x: integer); external;
begin
    MyProc(42)
end."#;
        let wasm = compile_source(source);

        let called = Arc::new(std::sync::Mutex::new(None));
        let called2 = called.clone();

        let mut builder = InstanceBuilder::new()?;
        builder.register_import("host", "myProc", 1, false, move |args| {
            *called2.lock().unwrap() = Some(args[0]);
            None
        })?;

        let mut instance = builder.build(&wasm)?;
        instance.run()?;

        assert_eq!(*called.lock().unwrap(), Some(42));
        Ok(())
    }

    #[test]
    fn test_import_function_with_return() -> Result<(), RuntimeError> {
        let source = r#"program T;
{$IMPORT 'host' addTen}
function AddTen(x: integer): integer; external;
var r: integer;
begin
    r := AddTen(5);
    writeln(r)
end."#;
        let wasm = compile_source(source);

        let mut builder = InstanceBuilder::new()?;
        builder.register_import("host", "addTen", 1, true, |args| {
            Some(args[0] + 10)
        })?;

        let mut instance = builder.build(&wasm)?;
        instance.run()?;
        Ok(())
    }

    #[test]
    fn test_import_multi_param() -> Result<(), RuntimeError> {
        let source = r#"program T;
{$IMPORT 'host' add3}
function Add3(a, b, c: integer): integer; external;
var r: integer;
begin
    r := Add3(1, 2, 3);
    writeln(r)
end."#;
        let wasm = compile_source(source);

        let mut builder = InstanceBuilder::new()?;
        builder.register_import("host", "add3", 3, true, |args| {
            Some(args[0] + args[1] + args[2])
        })?;

        let mut instance = builder.build(&wasm)?;
        instance.run()?;
        Ok(())
    }

    #[test]
    fn test_export_call() -> Result<(), RuntimeError> {
        let source = r#"
            program T;
            {$EXPORT getAnswer}
            function GetAnswer: integer;
            begin
                GetAnswer := 42
            end;
            begin
            end.
        "#;
        let wasm = compile_source(source);

        let mut instance = InstanceBuilder::new()?.build(&wasm)?;
        instance.run()?;

        let result = instance.call_args("getAnswer", &[])?;
        assert_eq!(result, Some(42));
        Ok(())
    }

    #[test]
    fn test_export_with_args() -> Result<(), RuntimeError> {
        let source = r#"
            program T;
            {$EXPORT double}
            function Double(x: integer): integer;
            begin
                Double := x * 2
            end;
            begin
            end.
        "#;
        let wasm = compile_source(source);

        let mut instance = InstanceBuilder::new()?.build(&wasm)?;
        instance.run()?;

        let result = instance.call_args("double", &[7])?;
        assert_eq!(result, Some(14));
        Ok(())
    }

    #[test]
    fn test_import_and_export_roundtrip() -> Result<(), RuntimeError> {
        let source = r#"program T;
{$IMPORT 'host' hostAdd}
function HostAdd(a, b: integer): integer; external;
{$EXPORT compute}
function Compute(x: integer): integer;
begin
    Compute := HostAdd(x, 100)
end;
begin
end."#;
        let wasm = compile_source(source);

        let mut builder = InstanceBuilder::new()?;
        builder.register_import("host", "hostAdd", 2, true, |args| {
            Some(args[0] + args[1])
        })?;

        let mut instance = builder.build(&wasm)?;
        instance.run()?;

        let result = instance.call_args("compute", &[23])?;
        assert_eq!(result, Some(123));
        Ok(())
    }

    #[test]
    fn fuel_bounds_a_runaway_program() {
        let wasm = compile(
            "program T;\nvar i: integer;\nbegin\n  i := 0;\n  while true do i := i + 1;\nend.",
        );
        let builder = InstanceBuilder::with_limits(Limits {
            fuel: Some(100_000),
            ..Limits::default()
        })
        .unwrap();
        let mut i = builder.build(&wasm).unwrap();
        let err = i.run().unwrap_err();
        assert!(matches!(err, RuntimeError::Trapped(_)), "got {err}");
    }

    #[test]
    fn fuel_does_not_disturb_a_program_that_finishes() {
        let wasm = compile("program T;\nvar i, n: integer;\nbegin n := 0;\n  for i := 1 to 10 do n := n + i;\n  halt(n);\nend.");
        let builder = InstanceBuilder::with_limits(Limits {
            fuel: Some(10_000_000),
            ..Limits::default()
        })
        .unwrap();
        let mut i = builder.build(&wasm).unwrap();
        assert_eq!(i.run().unwrap_err().exit_status(), Some(55));
    }

    fn compile(src: &str) -> Vec<u8> {
        crate::compiler::Compiler::new()
            .compile(src)
            .expect("source should compile")
            .wasm
    }

    #[test]
    fn halt_with_a_status_is_reported_as_an_exit() {
        let wasm = compile("program T; begin halt(3); end.");
        let mut i = Instance::new(&wasm).unwrap();
        let err = i.run().unwrap_err();
        assert_eq!(err.exit_status(), Some(3));
    }

    #[test]
    fn halt_zero_is_success() {
        let wasm = compile("program T; begin halt(0); end.");
        let mut i = Instance::new(&wasm).unwrap();
        assert!(i.run().is_ok());
    }

    #[test]
    fn a_nil_dereference_is_reported_as_a_trap_not_an_exit() {
        let wasm = compile(
            "program T;\ntype PInt = ^integer;\nvar p: PInt;\nbegin p := nil; writeln(p^); end.",
        );
        let mut i = Instance::new(&wasm).unwrap();
        let err = i.run().unwrap_err();
        assert!(err.exit_status().is_none(), "got {err}");
        assert!(matches!(err, RuntimeError::Trapped(_)), "got {err}");
    }
}

