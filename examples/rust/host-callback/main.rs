// Compact Pascal Rust embedding example: Pascal calling back into the host
// Made by a machine. PUBLIC DOMAIN (CC0-1.0)
//
// The other direction. Here the Pascal program is the one asking for things:
// it declares procedures the host must supply, and the host registers Rust
// closures to satisfy them. This is how a scripted program reaches capability
// it could not have on its own, and how the host stays in control of what that
// capability is.
//
// Run with:  cargo run --example host-callback

use compact_pascal::{Compiler, InstanceBuilder};
use std::sync::atomic::{AtomicI32, Ordering};
use std::sync::Arc;

/// `{$IMPORT 'host' name}` declares that the next routine comes from outside,
/// from the WASM import module `host` under the name `name`. `external` marks
/// it as having no body here.
const SCRIPT: &str = r#"
program Sensors;

{$IMPORT 'host' readSensor}
function ReadSensor(id: integer): integer; external;

{$IMPORT 'host' recordReading}
procedure RecordReading(id, value: integer); external;

{$EXPORT poll}
procedure Poll;
var id, value, total: integer;
begin
  total := 0;
  for id := 1 to 4 do begin
    value := ReadSensor(id);
    RecordReading(id, value);
    total := total + value;
  end;
  writeln('the script saw a total of ', total);
end;

begin
end.
"#;

fn main() -> Result<(), Box<dyn std::error::Error>> {
    let result = Compiler::new().compile(SCRIPT)?;

    // Shared with the closures below. The host decides what a "sensor" is; the
    // script only knows it can ask for one by number.
    let readings = Arc::new(AtomicI32::new(0));
    let sum = Arc::new(AtomicI32::new(0));

    let mut builder = InstanceBuilder::new()?;

    // A function: takes one argument, returns one value.
    builder.register_import("host", "readSensor", 1, true, move |args| {
        let id = args[0];
        // A real host would read hardware. This one is deterministic so the
        // example's output can be checked.
        Some(id * 10 + 1)
    })?;

    // A procedure: takes two arguments, returns nothing. The closure captures
    // host state, which is the whole reason to register one rather than let
    // the script compute the answer itself.
    let readings_for_closure = Arc::clone(&readings);
    let sum_for_closure = Arc::clone(&sum);
    builder.register_import("host", "recordReading", 2, false, move |args| {
        readings_for_closure.fetch_add(1, Ordering::Relaxed);
        sum_for_closure.fetch_add(args[1], Ordering::Relaxed);
        println!("host recorded sensor {} = {}", args[0], args[1]);
        None
    })?;

    let mut instance = builder.build(&result.wasm)?;
    instance.call("poll")?;

    println!(
        "host state after the call: {} readings, total {}",
        readings.load(Ordering::Relaxed),
        sum.load(Ordering::Relaxed)
    );

    Ok(())
}
