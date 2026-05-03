// Compact Pascal embeddable compiler and runtime
// Made by a machine. PUBLIC DOMAIN (CC0-1.0)

mod compiler;
mod include;
mod instance;
mod wasi;

pub use compiler::{Compiler, CompileResult, CompileError};
pub use include::{expand_includes, IncludeError};
pub use instance::{Instance, InstanceBuilder, RuntimeError};
