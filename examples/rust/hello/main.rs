// Compact Pascal Rust embedding example: Hello World
// Made by a machine. PUBLIC DOMAIN (CC0-1.0)

use compact_pascal::{Compiler, Instance};

fn main() -> Result<(), Box<dyn std::error::Error>> {
    let compiler = Compiler::new();
    let result = compiler.compile(
        "program Hello; begin writeln('Hello from Compact Pascal!') end."
    )?;

    let mut instance = Instance::new(&result.wasm)?;
    instance.run()?;

    Ok(())
}
