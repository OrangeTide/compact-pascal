// Compact Pascal Rust embedding example: Hello World
// Made by a machine. PUBLIC DOMAIN (CC0-1.0)

use compact_pascal::Compiler;

fn main() -> Result<(), Box<dyn std::error::Error>> {
    // Create a compiler
    let compiler = Compiler::new();

    // Pascal source: print "Hello from Compact Pascal!"
    let source = "program Hello;\nbegin\n  writeln('Hello from Compact Pascal!')\nend.";

    // Compile to WASM
    println!("Compiling...");
    let result = compiler.compile(source)?;

    // Check for compilation errors
    if !result.stderr.is_empty() {
        eprintln!("Compilation error:\n{}", result.stderr);
        return Ok(());
    }

    println!("Compilation succeeded ({} bytes)", result.wasm.len());

    // Run the compiled program
    println!("Running...");
    let mut instance = compact_pascal::Instance::new(&result.wasm)?;
    instance.run()?;

    // Print any output
    let output = instance.stdout();
    if !output.is_empty() {
        print!("{}", output);
    }

    Ok(())
}
