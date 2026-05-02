//! Compact Pascal embeddable compiler and runtime
//! Made by a machine. PUBLIC DOMAIN (CC0-1.0)

mod compiler;
mod instance;
mod wasi;

pub use compiler::{Compiler, CompileResult, CompileError};
pub use instance::{Instance, RuntimeError};

// Re-export commonly used types
pub type Result<T> = std::result::Result<T, Box<dyn std::error::Error>>;
