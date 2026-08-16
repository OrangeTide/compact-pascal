// Compact Pascal Rust embedding example: a calculator whose rules are Pascal
// Made by a machine. PUBLIC DOMAIN (CC0-1.0)
//
// The point of this example is that the *program* is data. The host knows
// nothing about what the expression means; it hands source to the compiler,
// gets a module back, and calls an exported function. Swapping the formula
// means swapping a string, not rebuilding the host.
//
// Run with:  cargo run --example calculator

use compact_pascal::{CompileError, Compiler, Instance, Options};

/// The rule the calculator applies. `{$EXPORT}` makes the function callable
/// from the host by name; without it the function exists but is not in the
/// module's export table.
const RULE: &str = r#"
program Calculator;

{$EXPORT evaluate}
function Evaluate(a, b: integer): integer;
begin
  Evaluate := a * a + b * b;
end;

begin
end.
"#;

fn main() -> Result<(), Box<dyn std::error::Error>> {
    // Range checks on: this is a calculator taking numbers from outside, and
    // the cost of the checks is not worth the debugging they save being
    // skipped.
    let compiler = Compiler::with_options(Options::new().with_range_checks(true));

    let result = match compiler.compile(RULE) {
        Ok(r) => r,
        Err(e) => {
            // A rejected program reports where. Print the position rather than
            // the whole stderr blob.
            if let Some(d) = e.first_error() {
                if let (Some(line), Some(col)) = (d.line, d.column) {
                    eprintln!("rule rejected at line {line}, column {col}: {}", d.message);
                } else {
                    eprintln!("rule rejected: {}", d.message);
                }
            } else {
                eprintln!("{e}");
            }
            return Err(Box::new(e) as Box<dyn std::error::Error>);
        }
    };

    for w in result.warnings() {
        eprintln!("warning from the rule: {}", w.message);
    }

    let mut instance = Instance::new(&result.wasm)?;

    for (a, b) in [(3, 4), (5, 12), (8, 15)] {
        let answer = instance
            .call_args("evaluate", &[a, b])?
            .expect("evaluate returns an integer");
        println!("f({a}, {b}) = {answer}");
    }

    // The same host, a different rule. Nothing below this line knew what the
    // arithmetic was going to be when the host was built.
    let doubled = Compiler::new().compile(
        "program Calculator;\n\
         {$EXPORT evaluate}\n\
         function Evaluate(a, b: integer): integer;\n\
         begin Evaluate := 2 * (a + b); end;\n\
         begin end.\n",
    )?;
    let mut instance = Instance::new(&doubled.wasm)?;
    println!(
        "a different rule, same host: f(3, 4) = {}",
        instance.call_args("evaluate", &[3, 4])?.unwrap()
    );

    // And a rule that does not compile, to show what that looks like.
    let broken = Compiler::new().compile("program C;\nbegin\n  x := 1;\nend.\n");
    match broken {
        Ok(_) => println!("unexpected: the broken rule compiled"),
        Err(e @ CompileError::Rejected { .. }) => {
            let d = e.first_error().unwrap();
            println!(
                "a broken rule reports its position: line {}, {}",
                d.line.unwrap(),
                d.message
            );
        }
        Err(e) => println!("unexpected failure kind: {e}"),
    }

    Ok(())
}
