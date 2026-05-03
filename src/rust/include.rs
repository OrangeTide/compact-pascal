// Include file preprocessing for Compact Pascal
// Made by a machine. PUBLIC DOMAIN (CC0-1.0)

use std::error::Error;
use std::fmt;
use std::fs;
use std::path::{Path, PathBuf};

const MAX_INCLUDE_DEPTH: usize = 16;

#[derive(Debug)]
pub enum IncludeError {
    NestingTooDeep,
    FileNotFound(String),
    IoError(std::io::Error),
}

impl fmt::Display for IncludeError {
    fn fmt(&self, f: &mut fmt::Formatter) -> fmt::Result {
        match self {
            IncludeError::NestingTooDeep => {
                write!(f, "include nesting too deep (max {})", MAX_INCLUDE_DEPTH)
            }
            IncludeError::FileNotFound(path) => write!(f, "cannot open include file: {}", path),
            IncludeError::IoError(e) => write!(f, "I/O error: {}", e),
        }
    }
}

impl Error for IncludeError {}

struct ExpandState {
    buffer: String,
    depth: usize,
}

/// Expands `{$I filename}` and `{$INCLUDE filename}` directives in Pascal source.
///
/// Behavior:
/// - Scans through source character by character
/// - Skips over string literals (`'...'` with `''` escape for embedded quotes)
/// - Skips over `(* ... *)` comments (no expansion inside comments)
/// - When encountering `{$I filename}` or `{$INCLUDE filename}`, resolves relative to `base_dir`
/// - Recursively expands includes in included files
/// - Max nesting depth: 16
/// - Non-matching `{...}` braces are passed through verbatim
pub fn expand_includes(source: &str, base_dir: &Path) -> Result<String, IncludeError> {
    let mut state = ExpandState {
        buffer: String::new(),
        depth: 0,
    };

    expand_includes_impl(&mut state, source, base_dir)?;
    Ok(state.buffer)
}

fn expand_includes_impl(
    state: &mut ExpandState,
    source: &str,
    base_dir: &Path,
) -> Result<(), IncludeError> {
    let bytes = source.as_bytes();
    let mut pos = 0;

    while pos < bytes.len() {
        match bytes[pos] {
            // String literal
            b'\'' | b'"' => {
                let string_start = pos;
                pos = find_string_end(source, pos)?;
                state.buffer.push_str(&source[string_start..pos]);
            }
            // Comment
            b'(' if pos + 1 < bytes.len() && bytes[pos + 1] == b'*' => {
                let comment_start = pos;
                pos += 2;
                while pos < bytes.len() {
                    if pos + 1 < bytes.len() && bytes[pos] == b'*' && bytes[pos + 1] == b')' {
                        pos += 2;
                        break;
                    }
                    pos += 1;
                }
                state.buffer.push_str(&source[comment_start..pos]);
            }
            // Possible include directive
            b'{' => {
                match scan_and_expand(state, source, base_dir, &mut pos)? {
                    true => {
                        // Directive was expanded
                    }
                    false => {
                        // Not an include directive, pass through as-is
                        state.buffer.push('{');
                    }
                }
            }
            // Regular character (including lone '(')
            _ => {
                let start = pos;
                while pos < bytes.len() {
                    match bytes[pos] {
                        b'\'' | b'"' | b'{' => break,
                        b'(' if pos + 1 < bytes.len() && bytes[pos + 1] == b'*' => break,
                        _ => pos += 1,
                    }
                }
                state.buffer.push_str(&source[start..pos]);
            }
        }
    }

    Ok(())
}

/// Scans a `{...}` block starting at `pos` to check if it's an include directive.
/// Returns true if it was an include directive (and pos is updated), false otherwise.
fn scan_and_expand(
    state: &mut ExpandState,
    source: &str,
    base_dir: &Path,
    pos: &mut usize,
) -> Result<bool, IncludeError> {
    let bytes = source.as_bytes();

    // Must start with '{'
    if *pos >= bytes.len() || bytes[*pos] != b'{' {
        *pos += 1;
        return Ok(false);
    }
    let mut p = *pos + 1;

    // Must be followed by '$'
    if p >= bytes.len() || bytes[p] != b'$' {
        *pos += 1;
        return Ok(false);
    }
    p += 1;

    // Check for {$I ...} (short form)
    if p < bytes.len() && (bytes[p] == b'I' || bytes[p] == b'i')
        && p + 1 < bytes.len() && (bytes[p + 1] == b' ' || bytes[p + 1] == b'\'' || bytes[p + 1] == b'"') {
        return handle_include_directive(state, source, base_dir, pos, p + 1);
    }

    // Check for {$INCLUDE ...} (long form)
    if p + 6 < bytes.len() {
        let slice = &bytes[p..p + 7];
        if (slice == b"INCLUDE" || slice == b"include")
            && p + 7 < bytes.len() && (bytes[p + 7] == b' ' || bytes[p + 7] == b'\t') {
            return handle_include_directive(state, source, base_dir, pos, p + 7);
        }
    }

    // Not an include directive
    *pos += 1;
    Ok(false)
}

fn handle_include_directive(
    state: &mut ExpandState,
    source: &str,
    base_dir: &Path,
    pos: &mut usize,
    mut p: usize,
) -> Result<bool, IncludeError> {
    let bytes = source.as_bytes();

    // Skip whitespace
    while p < bytes.len() && (bytes[p] == b' ' || bytes[p] == b'\t') {
        p += 1;
    }

    if p >= bytes.len() {
        *pos += 1;
        return Ok(false);
    }

    // Check for quote character
    let has_quote = bytes[p] == b'\'' || bytes[p] == b'"';
    let quote_char = bytes[p];

    if has_quote {
        p += 1;
    }

    let filename_start = p;

    // Read filename until quote/brace
    while p < bytes.len() {
        if has_quote {
            if bytes[p] == quote_char {
                break;
            }
        } else {
            if bytes[p] == b'}' {
                break;
            }
        }
        p += 1;
    }

    let mut filename_end = p;

    // For unquoted filenames, trim trailing whitespace before '}'
    if !has_quote {
        while filename_end > filename_start && (bytes[filename_end - 1] == b' ' || bytes[filename_end - 1] == b'\t' || bytes[filename_end - 1] == b'}') {
            filename_end -= 1;
        }
    }

    // Validate format
    if !has_quote && p >= bytes.len() {
        *pos += 1;
        return Ok(false);
    }

    if !has_quote && bytes[p] != b'}' {
        *pos += 1;
        return Ok(false);
    }

    if has_quote && p >= bytes.len() {
        *pos += 1;
        return Ok(false);
    }

    if has_quote && bytes[p] != quote_char {
        *pos += 1;
        return Ok(false);
    }

    if has_quote {
        p += 1;
    }

    // Find closing brace
    while p < bytes.len() && bytes[p] != b'}' {
        p += 1;
    }

    if p >= bytes.len() || bytes[p] != b'}' {
        *pos += 1;
        return Ok(false);
    }
    p += 1;

    // Extract filename
    let filename = &source[filename_start..filename_end];

    // Check nesting depth
    if state.depth >= MAX_INCLUDE_DEPTH {
        return Err(IncludeError::NestingTooDeep);
    }

    // Build full path
    let full_path = build_path(base_dir, filename)?;

    // Read file
    let file_content = fs::read_to_string(&full_path).map_err(|_e| {
        IncludeError::FileNotFound(full_path.to_string_lossy().to_string())
    })?;

    // Recursively expand
    state.depth += 1;
    let result = expand_includes_impl(state, &file_content, base_dir);
    state.depth -= 1;
    result?;

    *pos = p;
    Ok(true)
}

/// Finds the end of a string literal, handling Pascal escaping ('' = escaped quote)
fn find_string_end(source: &str, mut pos: usize) -> Result<usize, IncludeError> {
    let bytes = source.as_bytes();

    if pos >= bytes.len() {
        return Err(IncludeError::IoError(std::io::Error::new(
            std::io::ErrorKind::InvalidData,
            "string literal not terminated",
        )));
    }

    let quote = bytes[pos];
    pos += 1;

    while pos < bytes.len() {
        if bytes[pos] == quote {
            pos += 1;
            // Check for escaped quote ('' inside '...')
            if pos < bytes.len() && bytes[pos] == quote {
                pos += 1;
            } else {
                return Ok(pos);
            }
        } else {
            pos += 1;
        }
    }

    // Unterminated string
    Err(IncludeError::IoError(std::io::Error::new(
        std::io::ErrorKind::InvalidData,
        "string literal not terminated",
    )))
}

/// Builds a full path by joining base_dir and filename
fn build_path(base_dir: &Path, filename: &str) -> Result<PathBuf, IncludeError> {
    if filename.is_empty() {
        return Err(IncludeError::FileNotFound("empty filename".to_string()));
    }

    let path = base_dir.join(filename);
    Ok(path)
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn test_passthrough_no_directives() {
        let source = "program Hello;\nbegin\n  write('test');\nend.";
        let result = expand_includes(source, Path::new(".")).unwrap();
        assert_eq!(result, source);
    }

    #[test]
    fn test_string_with_include_text() {
        let source = "s := '{$I foo.pas}';";
        let result = expand_includes(source, Path::new(".")).unwrap();
        assert_eq!(result, source);
    }

    #[test]
    fn test_comment_with_include_text() {
        let source = "(* {$I foo.pas} *) program test;";
        let result = expand_includes(source, Path::new(".")).unwrap();
        assert_eq!(result, source);
    }

    #[test]
    fn test_escaped_quote_in_string() {
        let source = "s := 'it''s';";
        let result = expand_includes(source, Path::new(".")).unwrap();
        assert_eq!(result, source);
    }

    #[test]
    fn test_braces_passthrough() {
        // Non-directive braces should pass through
        let source = "{ this is a comment }";
        let result = expand_includes(source, Path::new(".")).unwrap();
        assert_eq!(result, source);
    }

    #[test]
    fn test_file_not_found() {
        let source = "{$I nonexistent_file_xyz.pas}";
        let result = expand_includes(source, Path::new("/tmp"));
        assert!(matches!(result, Err(IncludeError::FileNotFound(_))));
    }
}
