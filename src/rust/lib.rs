// Compact Pascal embeddable compiler and runtime
// Made by a machine. PUBLIC DOMAIN (CC0-1.0)

mod compiler;
mod diagnostic;
mod include;
mod instance;
mod wasi;

pub use compiler::{CompileError, CompileResult, Compiler, Options};
pub use diagnostic::{Diagnostic, Severity};
pub use include::{expand_includes, IncludeError};
pub use instance::{Instance, InstanceBuilder, Limits, RuntimeError};
pub use wasi::{WasiContext, ERRNO_BADF, ERRNO_FAULT, ERRNO_SUCCESS};
