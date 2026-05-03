// Integration tests for compact-pascal Rust crate
// Made by a machine. PUBLIC DOMAIN (CC0-1.0)

use compact_pascal::{Compiler, Instance};

#[test]
fn test_compile_hello() {
    let compiler = Compiler::new();
    let result = compiler.compile(
        "program Hello; begin writeln('Hello!') end."
    );

    assert!(result.is_ok(), "Failed to compile hello world");
    let result = result.unwrap();

    // Verify WASM is non-empty
    assert!(!result.wasm.is_empty(), "Compiled WASM is empty");

    // Verify WASM magic bytes
    assert!(result.wasm.len() >= 4, "WASM too short for magic bytes");
    assert_eq!(&result.wasm[0..4], b"\0asm", "WASM magic bytes incorrect");
}

#[test]
fn test_compile_and_run() {
    let compiler = Compiler::new();
    let result = compiler.compile("program T; begin end.");

    assert!(result.is_ok(), "Failed to compile trivial program");
    let result = result.unwrap();

    let instance = Instance::new(&result.wasm);
    assert!(instance.is_ok(), "Failed to instantiate compiled WASM");

    let mut instance = instance.unwrap();
    let run_result = instance.run();
    assert!(run_result.is_ok(), "Failed to run compiled program");
}

#[test]
fn test_compile_writeln() {
    let compiler = Compiler::new();
    let result = compiler.compile("program T; begin writeln('test') end.");

    assert!(result.is_ok(), "Failed to compile writeln program");
    let result = result.unwrap();

    let instance = Instance::new(&result.wasm);
    assert!(instance.is_ok(), "Failed to instantiate");

    let mut instance = instance.unwrap();
    let run_result = instance.run();
    assert!(run_result.is_ok(), "Failed to run writeln program");
}

#[test]
fn test_compile_arithmetic() {
    let source = r#"
        program Arith;
        var x: integer;
        begin
            x := 5 + 3;
            writeln(x)
        end.
    "#;

    let compiler = Compiler::new();
    let result = compiler.compile(source);

    assert!(result.is_ok(), "Failed to compile arithmetic program");
    let result = result.unwrap();

    let instance = Instance::new(&result.wasm);
    assert!(instance.is_ok(), "Failed to instantiate");

    let mut instance = instance.unwrap();
    let run_result = instance.run();
    assert!(run_result.is_ok(), "Failed to run arithmetic program");
}

#[test]
fn test_compile_error() {
    let compiler = Compiler::new();
    let result = compiler.compile("program T; begin xyz end.");

    assert!(result.is_err(), "Expected compilation to fail");
}

#[test]
fn test_compile_if_else() {
    let source = r#"
        program IfElse;
        var x: integer;
        begin
            x := 5;
            if x > 3 then
                writeln('yes')
            else
                writeln('no')
        end.
    "#;

    let compiler = Compiler::new();
    let result = compiler.compile(source);

    assert!(result.is_ok(), "Failed to compile if/else program");
    let result = result.unwrap();

    let instance = Instance::new(&result.wasm);
    assert!(instance.is_ok(), "Failed to instantiate");

    let mut instance = instance.unwrap();
    let run_result = instance.run();
    assert!(run_result.is_ok(), "Failed to run if/else program");
}

#[test]
fn test_compile_for_loop() {
    let source = r#"
        program ForLoop;
        var i: integer;
        begin
            for i := 1 to 5 do
                writeln(i)
        end.
    "#;

    let compiler = Compiler::new();
    let result = compiler.compile(source);

    assert!(result.is_ok(), "Failed to compile for loop program");
    let result = result.unwrap();

    let instance = Instance::new(&result.wasm);
    assert!(instance.is_ok(), "Failed to instantiate");

    let mut instance = instance.unwrap();
    let run_result = instance.run();
    assert!(run_result.is_ok(), "Failed to run for loop program");
}

#[test]
fn test_compile_procedure() {
    let source = r#"
        program WithProc;

        procedure greet;
        begin
            writeln('Hello from procedure')
        end;

        begin
            greet
        end.
    "#;

    let compiler = Compiler::new();
    let result = compiler.compile(source);

    assert!(result.is_ok(), "Failed to compile procedure program");
    let result = result.unwrap();

    let instance = Instance::new(&result.wasm);
    assert!(instance.is_ok(), "Failed to instantiate");

    let mut instance = instance.unwrap();
    let run_result = instance.run();
    assert!(run_result.is_ok(), "Failed to run procedure program");
}

#[test]
fn test_compile_function() {
    let source = r#"
        program WithFunc;

        function add(a: integer; b: integer): integer;
        begin
            add := a + b
        end;

        begin
            writeln(add(2, 3))
        end.
    "#;

    let compiler = Compiler::new();
    let result = compiler.compile(source);

    assert!(result.is_ok(), "Failed to compile function program");
    let result = result.unwrap();

    let instance = Instance::new(&result.wasm);
    assert!(instance.is_ok(), "Failed to instantiate");

    let mut instance = instance.unwrap();
    let run_result = instance.run();
    assert!(run_result.is_ok(), "Failed to run function program");
}

#[test]
fn test_wasm_valid() {
    let source = r#"
        program Complex;
        var i, sum: integer;
        begin
            sum := 0;
            for i := 1 to 10 do
                sum := sum + i;
            writeln(sum)
        end.
    "#;

    let compiler = Compiler::new();
    let result = compiler.compile(source);

    assert!(result.is_ok(), "Failed to compile complex program");
    let result = result.unwrap();

    // Verify WASM magic bytes
    assert!(result.wasm.len() >= 8, "WASM too short");
    assert_eq!(&result.wasm[0..4], b"\0asm", "WASM magic incorrect");

    // Verify WASM version
    assert_eq!(&result.wasm[4..8], b"\x01\x00\x00\x00", "WASM version incorrect");
}
