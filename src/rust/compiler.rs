// Compact Pascal compiler module
// Made by a machine. PUBLIC DOMAIN (CC0-1.0)

use crate::diagnostic::{Diagnostic, Severity};
use crate::include;
use crate::wasi::{StdioBuffer, WasiContext};
use std::error::Error;
use std::fmt;
use std::path::Path;
use wasmi::{Engine, Linker, Module};

/// Why a compilation did not produce a module.
#[derive(Debug)]
pub enum CompileError {
    /// The compiler rejected the program. `diagnostics` holds every tagged
    /// line the compiler wrote, in order, so a host can point at the offending
    /// source position rather than printing a blob of text.
    Rejected {
        diagnostics: Vec<Diagnostic>,
        stderr: String,
    },
    /// The compiler exited with a status other than zero and said nothing this
    /// crate could parse. Reaching this means the snapshot and this crate
    /// disagree about something, which is a bug worth reporting.
    Exit { status: i32, stderr: String },
    /// The snapshot itself could not be loaded or started. Not a fault in the
    /// program being compiled.
    Instantiation(String),
    /// An include directive could not be resolved.
    Include(String),
}

impl CompileError {
    /// The diagnostics the compiler produced, empty when the failure happened
    /// before or outside compilation.
    pub fn diagnostics(&self) -> &[Diagnostic] {
        match self {
            CompileError::Rejected { diagnostics, .. } => diagnostics,
            _ => &[],
        }
    }

    /// The first error diagnostic, which is the one a user wants to see.
    pub fn first_error(&self) -> Option<&Diagnostic> {
        self.diagnostics()
            .iter()
            .find(|d| d.severity == Severity::Error)
    }
}

impl fmt::Display for CompileError {
    fn fmt(&self, f: &mut fmt::Formatter) -> fmt::Result {
        match self {
            CompileError::Rejected { diagnostics, stderr } => {
                match diagnostics.iter().find(|d| d.severity == Severity::Error) {
                    Some(d) => write!(f, "{d}"),
                    None => write!(f, "compilation failed: {}", stderr.trim_end()),
                }
            }
            CompileError::Exit { status, stderr } => {
                if stderr.is_empty() {
                    write!(f, "compiler exited with status {status}")
                } else {
                    write!(f, "compiler exited with status {status}: {}", stderr.trim_end())
                }
            }
            CompileError::Instantiation(e) => write!(f, "instantiation error: {e}"),
            CompileError::Include(e) => write!(f, "include error: {e}"),
        }
    }
}

impl Error for CompileError {}

/// A successful compilation.
#[derive(Debug, Clone)]
pub struct CompileResult {
    /// The compiled WASM module.
    pub wasm: Vec<u8>,
    /// Everything the compiler wrote to stderr, verbatim.
    pub stderr: String,
    /// The tagged lines of `stderr`, taken apart. A successful compilation can
    /// still carry warnings, and ignoring them is the caller's decision to
    /// make rather than this crate's.
    pub diagnostics: Vec<Diagnostic>,
}

impl CompileResult {
    /// Warnings only, in order.
    pub fn warnings(&self) -> impl Iterator<Item = &Diagnostic> {
        self.diagnostics
            .iter()
            .filter(|d| d.severity == Severity::Warning)
    }
}

/// Compiler switches, passed to the snapshot the same way a command line
/// would pass them.
///
/// The defaults match the compiler's own defaults, so `Options::default()`
/// compiles exactly as the `cpas` binary does with no arguments.
/// Reject an object name that could reach outside the unit directory.
///
/// The same rule include paths follow, and for the same reason: the compiler
/// resolves the name against a preopened directory, and a name containing
/// `..` or an absolute path would leave it.
fn check_object_name(name: &str) -> Result<(), CompileError> {
    if name.is_empty() {
        return Err(CompileError::Instantiation("an object name may not be empty".to_string()));
    }
    for component in std::path::Path::new(name).components() {
        match component {
            std::path::Component::Normal(_) | std::path::Component::CurDir => {}
            std::path::Component::ParentDir => {
                return Err(CompileError::Instantiation(format!(
                    "{name}: an object name may not contain '..'"
                )))
            }
            std::path::Component::RootDir | std::path::Component::Prefix(_) => {
                return Err(CompileError::Instantiation(format!(
                    "{name}: an object name must be relative to the unit directory"
                )))
            }
        }
    }
    Ok(())
}

/// Adding a field must not be a breaking change, so this cannot be built with
/// a struct literal that names every field. Use `..Options::default()`. Marked
/// before 1.0 deliberately: after it, the first new option would have cost a
/// major version.
#[non_exhaustive]
#[derive(Debug, Clone)]
pub struct Options {
    /// Runtime range checks on array indexing and subrange assignment
    /// (`{$R+}`). Off by default, as in the language.
    pub range_checks: bool,
    /// Stack overflow guard, frame balance check, and nil check (`{$S+}`).
    /// On by default: silent memory corruption costs more to find than the
    /// instructions cost to run.
    pub stack_checks: bool,
    /// Conditional compilation symbols, as `-dNAME`. `CPAS` is always defined.
    pub defines: Vec<String>,
    /// Emit `Info:` lines describing what the compiler decided.
    pub verbose: bool,
    /// Directory the compiler may read `{$I}` include files from. `None`, the
    /// default, leaves includes to the host: `expand_includes` or nothing.
    /// Setting it passes `-I` and grants the compiler that one directory,
    /// confined the same way `expand_includes` confines its own.
    pub include_dir: Option<std::path::PathBuf>,
    /// Directory the compiler may read separately compiled unit objects
    /// (`.cpo`) from. `None`, the default, means a program may not import a
    /// Pascal unit: only the system units are available.
    ///
    /// Objects are named in `objects` relative to this directory, confined
    /// the same way includes are. If `include_dir` is also set the two must
    /// name the same directory, because a module gets one preopen.
    pub unit_dir: Option<std::path::PathBuf>,
    /// Objects to link against, as file names relative to `unit_dir`.
    ///
    /// Naming an object a program never imports costs nothing: the compiler
    /// reads its unit name to see whether a `uses` clause wants it, and
    /// links only what is reached. A unit's own dependencies are pulled in
    /// whether or not the program mentions them, so a build script names
    /// every object it built without working out which are needed.
    pub objects: Vec<String>,
}

impl Default for Options {
    fn default() -> Self {
        Options {
            range_checks: false,
            stack_checks: true,
            defines: Vec::new(),
            verbose: false,
            include_dir: None,
            unit_dir: None,
            objects: Vec::new(),
        }
    }
}

impl Options {
    /// Compiler switches at their defaults, the same as `Options::default()`.
    ///
    /// The `with_` methods below exist because `Options` is `#[non_exhaustive]`,
    /// which stops another crate building it with a struct literal even when
    /// that literal ends in `..Options::default()`. That restriction is the
    /// point: a field added later is then not a breaking change. The cost is
    /// that construction needs methods, and this is them.
    pub fn new() -> Self {
        Self::default()
    }

    /// `{$R+}`: check array indices and subrange assignments at run time.
    pub fn with_range_checks(mut self, on: bool) -> Self {
        self.range_checks = on;
        self
    }

    /// `{$S+}`: stack overflow guard, frame balance check, and nil check.
    pub fn with_stack_checks(mut self, on: bool) -> Self {
        self.stack_checks = on;
        self
    }

    /// A conditional compilation symbol, as `-dNAME`. Call more than once to
    /// define more than one.
    pub fn with_define(mut self, name: impl Into<String>) -> Self {
        self.defines.push(name.into());
        self
    }

    /// Emit `Info:` lines describing what the compiler decided.
    pub fn with_verbose(mut self, on: bool) -> Self {
        self.verbose = on;
        self
    }

    /// Let the compiler resolve `{$I}` itself, against this one directory.
    pub fn with_include_dir(mut self, dir: impl Into<std::path::PathBuf>) -> Self {
        self.include_dir = Some(dir.into());
        self
    }

    /// The directory holding unit objects, which `objects` names relative to.
    pub fn with_unit_dir(mut self, dir: impl Into<std::path::PathBuf>) -> Self {
        self.unit_dir = Some(dir.into());
        self
    }

    /// An object to link against, named relative to `unit_dir`. Call more than
    /// once to name more than one.
    pub fn with_object(mut self, name: impl Into<String>) -> Self {
        self.objects.push(name.into());
        self
    }
}

impl Options {
    fn to_args(&self) -> Vec<String> {
        // argv[0] is the program name by convention. The compiler skips it.
        let mut args = vec!["cpas".to_string()];
        args.push(if self.range_checks { "-R+" } else { "-R-" }.to_string());
        args.push(if self.stack_checks { "-S+" } else { "-S-" }.to_string());
        if self.verbose {
            args.push("-v".to_string());
        }
        if self.include_dir.is_some() {
            args.push("-I".to_string());
        }
        for d in &self.defines {
            args.push(format!("-d{d}"));
        }
        // Objects come last, as bare arguments. The compiler takes anything
        // not starting with a dash as an object to link against.
        for o in &self.objects {
            args.push(o.clone());
        }
        args
    }
}

/// The Compact Pascal compiler, as an embedded WASM module.
///
/// The snapshot is compiled into this crate, so nothing is read from disk and
/// no Pascal toolchain is needed at build or run time.
pub struct Compiler {
    snapshot: &'static [u8],
    options: Options,
}

impl Compiler {
    pub fn new() -> Self {
        Compiler {
            snapshot: include_bytes!("../../snapshot/compiler.wasm"),
            options: Options::default(),
        }
    }

    /// Build a compiler with non-default switches.
    pub fn with_options(options: Options) -> Self {
        Compiler {
            snapshot: include_bytes!("../../snapshot/compiler.wasm"),
            options,
        }
    }

    pub fn options(&self) -> &Options {
        &self.options
    }

    pub fn set_options(&mut self, options: Options) {
        self.options = options;
    }

    pub fn compile(&self, source: &str) -> Result<CompileResult, CompileError> {
        let engine = Engine::default();
        let mut linker: Linker<WasiContext> = Linker::new(&engine);

        crate::wasi::add_wasi_imports(&mut linker)
            .map_err(|e| CompileError::Instantiation(format!("{e}")))?;

        let mut ctx = WasiContext::new();
        ctx.stdin = StdioBuffer::from_bytes(source.as_bytes());
        ctx.args = self.options.to_args();
        // One preopen serves both includes and objects. Which one it is
        // depends on what the host asked for, and asking for two different
        // directories is refused rather than silently granting one.
        for o in &self.options.objects {
            check_object_name(o)?;
        }
        ctx.preopen_dir = match (&self.options.unit_dir, &self.options.include_dir) {
            (Some(u), Some(i)) if u != i => {
                return Err(CompileError::Instantiation(
                    "unit_dir and include_dir must name the same directory: \
                     a compiled module gets one preopened directory"
                        .to_string(),
                ))
            }
            (Some(u), _) => Some(u.clone()),
            (None, i) => i.clone(),
        };
        let mut store = wasmi::Store::new(&engine, ctx);

        let module = Module::new(&engine, self.snapshot)
            .map_err(|e| CompileError::Instantiation(format!("{e}")))?;

        let instance = linker
            .instantiate_and_start(&mut store, &module)
            .map_err(|e| CompileError::Instantiation(format!("{e}")))?;

        let start = instance
            .get_export(&store, "_start")
            .and_then(|e| e.into_func())
            .ok_or_else(|| CompileError::Instantiation("_start not found".into()))?;

        // The compiler ends by calling proc_exit, which unwinds. A status of
        // zero is the success path, not an error.
        let run_err = start.call(&mut store, &[], &mut []).err();

        let ctx = store.into_data();
        let stderr = String::from_utf8_lossy(&ctx.stderr.into_bytes()).into_owned();
        let wasm = ctx.stdout.into_bytes();
        let diagnostics = Diagnostic::parse(&stderr);

        if let Some(e) = run_err {
            match e.i32_exit_status() {
                Some(0) => {}
                Some(status) => {
                    if diagnostics.iter().any(|d| d.severity == Severity::Error) {
                        return Err(CompileError::Rejected { diagnostics, stderr });
                    }
                    return Err(CompileError::Exit { status, stderr });
                }
                None => {
                    // A trap rather than an exit: the compiler itself failed.
                    return Err(CompileError::Instantiation(e.to_string()));
                }
            }
        }

        Ok(CompileResult { wasm, stderr, diagnostics })
    }

    pub fn compile_with_includes(
        &self,
        source: &str,
        base_dir: &Path,
    ) -> Result<CompileResult, CompileError> {
        let expanded = include::expand_includes(source, base_dir)
            .map_err(|e| CompileError::Include(format!("{e}")))?;
        self.compile(&expanded)
    }
}

impl Default for Compiler {
    fn default() -> Self {
        Compiler::new()
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn test_compile_simple() {
        let c = Compiler::new();
        let r = c.compile("program T; begin end.").unwrap();
        assert!(!r.wasm.is_empty());
    }

    #[test]
    fn test_compile_with_import() {
        let c = Compiler::new();
        let src = "program T;\n{$IMPORT 'host' myProc}\nprocedure MyProc(x: integer); external;\nbegin end.";
        let r = c.compile(src).unwrap();
        assert!(!r.wasm.is_empty());
    }

    #[test]
    fn test_compile_error() {
        let c = Compiler::new();
        let r = c.compile("program T; begin");
        assert!(r.is_err());
    }

    #[test]
    fn error_carries_a_source_position() {
        let c = Compiler::new();
        let err = c.compile("program T;\nbegin\n  writeln(nosuchvar);\nend.").unwrap_err();
        let d = err.first_error().expect("an Error diagnostic");
        assert_eq!(d.line, Some(3));
        assert!(d.message.to_lowercase().contains("nosuchvar"), "{}", d.message);
    }

    #[test]
    fn options_reach_the_compiler() {
        // -R+ makes an out-of-range index trap at runtime. Compiling the same
        // source both ways must produce different modules, which is the
        // cheapest proof the argument vector arrived.
        let src = "program T;\nvar a: array[1..3] of integer; i: integer;\nbegin i := 1; a[i] := 0; end.";
        let off = Compiler::new().compile(src).unwrap();
        let on = Compiler::with_options(Options {
            range_checks: true,
            ..Options::default()
        })
        .compile(src)
        .unwrap();
        assert_ne!(off.wasm, on.wasm, "-R+ did not change the generated module");
    }

    #[test]
    fn stack_checks_can_be_turned_off() {
        let src = "program T;\nprocedure P;\nvar x: integer;\nbegin x := 1; end;\nbegin P; end.";
        let on = Compiler::new().compile(src).unwrap();
        let off = Compiler::with_options(Options {
            stack_checks: false,
            ..Options::default()
        })
        .compile(src)
        .unwrap();
        assert!(off.wasm.len() < on.wasm.len(), "-S- did not shrink the module");
    }

    #[test]
    fn defines_reach_the_compiler() {
        let src = "program T;\nbegin\n{$IFDEF FEATURE}\n  writeln('on');\n{$ENDIF}\nend.";
        let plain = Compiler::new().compile(src).unwrap();
        let defined = Compiler::with_options(Options {
            defines: vec!["FEATURE".to_string()],
            ..Options::default()
        })
        .compile(src)
        .unwrap();
        assert_ne!(plain.wasm, defined.wasm, "-dFEATURE had no effect");
    }
}
