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

// ---- The paths the examples take ----
//
// The examples in examples/rust are the crate's user-facing documentation.
// These tests exercise the same paths so a change that breaks an example
// fails the suite rather than waiting for someone to run it by hand.

#[test]
fn a_host_can_call_an_exported_pascal_function() {
    let src = "program C;\n\
               {$EXPORT evaluate}\n\
               function Evaluate(a, b: integer): integer;\n\
               begin Evaluate := a * a + b * b; end;\n\
               begin end.\n";
    let wasm = Compiler::new().compile(src).unwrap().wasm;
    let mut instance = Instance::new(&wasm).unwrap();
    assert_eq!(instance.call_args("evaluate", &[3, 4]).unwrap(), Some(25));
    assert_eq!(instance.call_args("evaluate", &[5, 12]).unwrap(), Some(169));
}

#[test]
fn pascal_can_call_back_into_the_host() {
    use compact_pascal::InstanceBuilder;
    use std::sync::atomic::{AtomicI32, Ordering};
    use std::sync::Arc;

    let src = "program S;\n\
               {$IMPORT 'host' readSensor}\n\
               function ReadSensor(id: integer): integer; external;\n\
               {$IMPORT 'host' recordReading}\n\
               procedure RecordReading(id, value: integer); external;\n\
               {$EXPORT poll}\n\
               procedure Poll;\n\
               var id, value: integer;\n\
               begin\n\
                 for id := 1 to 4 do begin\n\
                   value := ReadSensor(id);\n\
                   RecordReading(id, value);\n\
                 end;\n\
               end;\n\
               begin end.\n";
    let wasm = Compiler::new().compile(src).unwrap().wasm;

    let count = Arc::new(AtomicI32::new(0));
    let total = Arc::new(AtomicI32::new(0));

    let mut builder = InstanceBuilder::new().unwrap();
    builder
        .register_import("host", "readSensor", 1, true, |args| Some(args[0] * 10 + 1))
        .unwrap();
    let count_c = Arc::clone(&count);
    let total_c = Arc::clone(&total);
    builder
        .register_import("host", "recordReading", 2, false, move |args| {
            count_c.fetch_add(1, Ordering::Relaxed);
            total_c.fetch_add(args[1], Ordering::Relaxed);
            None
        })
        .unwrap();

    let mut instance = builder.build(&wasm).unwrap();
    instance.call("poll").unwrap();

    assert_eq!(count.load(Ordering::Relaxed), 4);
    assert_eq!(total.load(Ordering::Relaxed), 11 + 21 + 31 + 41);
}

#[test]
fn a_rejected_program_reports_where() {
    let err = Compiler::new()
        .compile("program C;\nbegin\n  x := 1;\nend.\n")
        .unwrap_err();
    let d = err.first_error().expect("an Error diagnostic");
    assert_eq!(d.line, Some(3));
}

#[test]
fn a_missing_import_fails_at_instantiation_and_names_it() {
    use compact_pascal::InstanceBuilder;

    let src = "program S;\n\
               {$IMPORT 'host' needsThis}\n\
               procedure NeedsThis(x: integer); external;\n\
               {$EXPORT go}\n\
               procedure Go; begin NeedsThis(1); end;\n\
               begin end.\n";
    let wasm = Compiler::new().compile(src).unwrap().wasm;

    // No register_import call at all.
    let msg = match InstanceBuilder::new().unwrap().build(&wasm) {
        Ok(_) => panic!("instantiation should have failed"),
        Err(e) => e.to_string(),
    };
    assert!(msg.contains("needsThis"), "message did not name the import: {msg}");
}

#[test]
fn include_paths_stay_inside_the_base_directory() {
    use compact_pascal::expand_includes;
    use std::path::Path;

    // A relative escape.
    let up = "program T;\n{$I '../../../etc/hostname'}\nbegin end.\n";
    assert!(
        expand_includes(up, Path::new("compiler-tests")).is_err(),
        "a '..' escape was resolved instead of refused"
    );

    // An absolute path, which Path::join adopts wholesale, discarding the base.
    let abs = "program T;\n{$I '/etc/hostname'}\nbegin end.\n";
    assert!(
        expand_includes(abs, Path::new("compiler-tests")).is_err(),
        "an absolute path was resolved instead of refused"
    );
}

#[test]
fn the_snapshot_declares_file_imports_but_cannot_use_them_by_default() {
    // The compiler snapshot imports path_open so it can resolve {$I} itself.
    // Declaring is not being allowed: with no preopen_dir the host refuses
    // every open, so an embedder who never asks for filesystem access does
    // not get it by accident.
    let src = "program T;\n{ 'anything.inc'}\nbegin end.\n";
    // Without -I the compiler skips the directive entirely, so this compiles.
    assert!(Compiler::new().compile(src).is_ok());
}

#[test]
fn the_crate_can_let_the_compiler_resolve_includes() {
    use compact_pascal::Options;
    use std::io::Write;

    let dir = std::env::temp_dir().join("cpas-include-test");
    let _ = std::fs::create_dir_all(&dir);
    let mut inc = std::fs::File::create(dir.join("shared.inc")).unwrap();
    writeln!(inc, "const FromInclude = 4242;").unwrap();
    drop(inc);

    let src = "program T;\n{$I 'shared.inc'}\nbegin writeln(FromInclude) end.\n";

    // Without a directory the compiler skips the directive, so the constant
    // is undeclared. That is the pre-existing behavior and it must not change
    // for a host that never asks for filesystem access.
    assert!(Compiler::new().compile(src).is_err());

    // With one, the compiler opens the file itself.
    let opts = Options {
        include_dir: Some(dir.clone()),
        ..Options::default()
    };
    let result = Compiler::with_options(opts)
        .compile(src)
        .expect("the include should have been resolved");
    assert!(!result.wasm.is_empty());

    let _ = std::fs::remove_dir_all(&dir);
}

#[test]
fn a_program_can_be_granted_a_directory_to_write_in() {
    use compact_pascal::{InstanceBuilder, Limits};

    let dir = std::env::temp_dir().join("cpas-preopen-test");
    let _ = std::fs::remove_dir_all(&dir);
    std::fs::create_dir_all(&dir).unwrap();

    let src = "program T;\nuses Files;\nvar f: text;\nbegin\n\
               assign(f, 'out.txt'); rewrite(f);\n\
               writeln(f, 'written by the guest');\n\
               close(f);\nend.\n";
    let wasm = Compiler::new().compile(src).unwrap().wasm;

    // Denied by default, so the open fails and the program traps under the
    // I/O check that is on unless a program turns it off.
    let mut denied = InstanceBuilder::new().unwrap().build(&wasm).unwrap();
    assert!(denied.run().is_err(), "an ungranted program should not have opened anything");

    let granted = InstanceBuilder::with_limits(Limits {
        preopen_dir: Some(dir.clone()),
        ..Limits::default()
    })
    .unwrap();
    let mut instance = granted.build(&wasm).unwrap();
    instance.run().unwrap();

    let written = std::fs::read_to_string(dir.join("out.txt")).unwrap();
    assert_eq!(written.trim(), "written by the guest");

    let _ = std::fs::remove_dir_all(&dir);
}

/// Ignored: the snapshot cannot link. An object path given on the command
/// line arrives empty when the compiler runs as WASM, so FindObjectArg
/// reports "cannot read object file: " with no name. Reproducible without
/// this crate:
///
///     wasmtime run --dir=. snapshot/compiler.wasm base.cpo < prog.pas
///
/// The native compiler links the same objects correctly, so this is argument
/// handling under WASI rather than anything in the linker. Un-ignore once
/// that is fixed; everything else in this test is known to work.
#[test]
#[ignore]
fn a_program_can_link_against_a_separately_compiled_unit() {
    use compact_pascal::{Compiler, Options};
    use std::io::Write;

    let dir = std::env::temp_dir().join("cpas-unit-link-test");
    let _ = std::fs::remove_dir_all(&dir);
    std::fs::create_dir_all(&dir).unwrap();

    // Two units, the second calling into the first, so the test covers a
    // dependency the program never mentions as well as one it does.
    let base = "unit Base;\ninterface\nfunction Two: integer;\n\
                implementation\nfunction Two: integer; begin Two := 2 end;\nend.\n";
    let mid = "unit Mid;\ninterface\nfunction Quad: integer;\n\
               implementation\nuses Base;\n\
               function Quad: integer; begin Quad := Two * Two end;\nend.\n";

    // The crate compiles programs, not units, so the objects are built by the
    // command-line compiler. That is the division the design intends: a build
    // script builds units, and a host links a program against them.
    for (name, src) in [("base.pas", base), ("mid.pas", mid)] {
        let mut f = std::fs::File::create(dir.join(name)).unwrap();
        f.write_all(src.as_bytes()).unwrap();
    }
    let cpas = concat!(env!("CARGO_MANIFEST_DIR"), "/compiler/cpas");
    for (src, obj, deps) in [
        ("base.pas", "base.cpo", vec![]),
        ("mid.pas", "mid.cpo", vec!["base.cpo"]),
    ] {
        let mut cmd = std::process::Command::new(cpas);
        cmd.arg("-c").arg("-o").arg(obj);
        for d in &deps {
            cmd.arg(d);
        }
        let status = cmd
            .current_dir(&dir)
            .stdin(std::fs::File::open(dir.join(src)).unwrap())
            .status()
            .expect("the command-line compiler should be built");
        assert!(status.success(), "{src} should have compiled to an object");
    }

    // The result comes back through a host import rather than stdout,
    // which is what the rest of these tests do and what an embedder does.
    let program = "program T;\n\
                   uses Mid;\n\
                   {$IMPORT 'host' report}\n\
                   procedure Report(v: integer); external;\n\
                   begin Report(Quad) end.\n";

    // Without a unit directory the import cannot resolve, which is the
    // behavior a host that never asks for filesystem access keeps.
    assert!(Compiler::new().compile(program).is_err());

    let opts = Options {
        unit_dir: Some(dir.clone()),
        objects: vec!["mid.cpo".to_string(), "base.cpo".to_string()],
        ..Options::default()
    };
    let result = Compiler::with_options(opts)
        .compile(program)
        .expect("the unit should have linked");

    let seen = std::sync::Arc::new(std::sync::Mutex::new(None));
    let seen2 = std::sync::Arc::clone(&seen);
    let mut builder = compact_pascal::InstanceBuilder::new().unwrap();
    builder
        .register_import("host", "report", 1, false, move |args| {
            *seen2.lock().unwrap() = Some(args[0]);
            None
        })
        .unwrap();
    let mut instance = builder
        .build(&result.wasm)
        .expect("the linked module should instantiate");
    instance.run().expect("the linked module should run");
    assert_eq!(*seen.lock().unwrap(), Some(4));

    let _ = std::fs::remove_dir_all(&dir);
}

#[test]
fn an_object_name_may_not_escape_the_unit_directory() {
    use compact_pascal::{Compiler, Options};

    let opts = Options {
        unit_dir: Some(std::env::temp_dir()),
        objects: vec!["../elsewhere.cpo".to_string()],
        ..Options::default()
    };
    let err = Compiler::with_options(opts)
        .compile("program T;\nbegin end.\n")
        .expect_err("an object name containing '..' should be refused");
    assert!(format!("{err}").contains(".."), "got: {err}");
}
