// Parsing of the compiler's tagged diagnostic stream
// Made by a machine. PUBLIC DOMAIN (CC0-1.0)

use std::fmt;

/// How seriously to take a diagnostic.
///
/// The compiler writes every diagnostic to stderr with a leading tag, which is
/// what makes this parseable rather than guessed at. See the "Compiler
/// Diagnostics" section of the language reference for the format.
#[derive(Debug, Clone, Copy, PartialEq, Eq, PartialOrd, Ord)]
pub enum Severity {
    /// Compilation stopped here. At most one appears, and it is always last.
    Error,
    /// Compilation continued. The program is legal but probably not intended.
    Warning,
    /// Requested with `-v`. Describes what the compiler decided.
    Info,
    /// Requested with `-debug`. Internal detail, not a statement about the
    /// program.
    Debug,
    /// Requested with `-progress`. Reports how far along the compiler is.
    Progress,
}

impl Severity {
    fn tag(&self) -> &'static str {
        match self {
            Severity::Error => "Error",
            Severity::Warning => "Warning",
            Severity::Info => "Info",
            Severity::Debug => "Debug",
            Severity::Progress => "Progress",
        }
    }
}

impl fmt::Display for Severity {
    fn fmt(&self, f: &mut fmt::Formatter) -> fmt::Result {
        f.write_str(self.tag())
    }
}

/// One line of the compiler's stderr, taken apart.
///
/// `line` and `column` are 1-based and present only when the compiler supplied
/// them. Errors always carry a position; the other severities usually do not.
#[derive(Debug, Clone, PartialEq, Eq)]
pub struct Diagnostic {
    pub severity: Severity,
    pub line: Option<u32>,
    pub column: Option<u32>,
    pub message: String,
}

impl fmt::Display for Diagnostic {
    fn fmt(&self, f: &mut fmt::Formatter) -> fmt::Result {
        write!(f, "{}: ", self.severity)?;
        if let (Some(l), Some(c)) = (self.line, self.column) {
            write!(f, "{l}:{c}: ")?;
        }
        f.write_str(&self.message)
    }
}

impl Diagnostic {
    /// Parse one line. Returns `None` for a line that carries no known tag,
    /// which is how output from a host-registered import or from a program
    /// writing to stderr on its own stays out of the diagnostic list.
    pub fn parse_line(line: &str) -> Option<Diagnostic> {
        const SEVERITIES: [Severity; 5] = [
            Severity::Error,
            Severity::Warning,
            Severity::Info,
            Severity::Debug,
            Severity::Progress,
        ];

        for severity in SEVERITIES {
            let prefix = format!("{}: ", severity.tag());
            let Some(rest) = line.strip_prefix(&prefix) else {
                continue;
            };
            let (line_no, column, message) = split_position(rest);
            return Some(Diagnostic {
                severity,
                line: line_no,
                column,
                message: message.to_string(),
            });
        }
        None
    }

    /// Parse a whole stderr capture, keeping only the tagged lines and their
    /// original order.
    pub fn parse(stderr: &str) -> Vec<Diagnostic> {
        stderr.lines().filter_map(Diagnostic::parse_line).collect()
    }
}

/// Split a leading `line:column: ` off a message.
///
/// Both numbers must parse, otherwise the whole string is the message. That
/// rule is what keeps a message containing a colon, `unknown type: TFOO`, from
/// being read as a position, and it is why the split is on `": "` rather than
/// on `':'`: the position's own colon has no space after it.
fn split_position(rest: &str) -> (Option<u32>, Option<u32>, &str) {
    let Some((head, message)) = rest.split_once(": ") else {
        return (None, None, rest);
    };
    let Some((line_str, col_str)) = head.split_once(':') else {
        return (None, None, rest);
    };
    match (line_str.parse::<u32>(), col_str.parse::<u32>()) {
        (Ok(l), Ok(c)) => (Some(l), Some(c), message),
        _ => (None, None, rest),
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn parses_an_error_with_a_position() {
        let d = Diagnostic::parse_line("Error: 12:5: unknown identifier: FOO").unwrap();
        assert_eq!(d.severity, Severity::Error);
        assert_eq!(d.line, Some(12));
        assert_eq!(d.column, Some(5));
        assert_eq!(d.message, "unknown identifier: FOO");
    }

    #[test]
    fn keeps_colons_inside_the_message() {
        let d = Diagnostic::parse_line("Error: 3:1: unknown type: TFOO").unwrap();
        assert_eq!(d.message, "unknown type: TFOO");
    }

    #[test]
    fn parses_a_warning_without_a_position() {
        let d = Diagnostic::parse_line("Warning: unreachable code after halt").unwrap();
        assert_eq!(d.severity, Severity::Warning);
        assert_eq!(d.line, None);
        assert_eq!(d.column, None);
        assert_eq!(d.message, "unreachable code after halt");
    }

    #[test]
    fn ignores_untagged_output() {
        assert!(Diagnostic::parse_line("some host wrote this").is_none());
        assert!(Diagnostic::parse_line("").is_none());
    }

    #[test]
    fn a_message_that_looks_like_a_position_is_not_one() {
        let d = Diagnostic::parse_line("Warning: ratio 3:4 is unusual").unwrap();
        assert_eq!(d.line, None);
        assert_eq!(d.message, "ratio 3:4 is unusual");
    }

    #[test]
    fn parses_a_stream_in_order() {
        let s = "Info: mode tp\nWarning: shadowed name X\nError: 9:2: ';' expected\n";
        let ds = Diagnostic::parse(s);
        assert_eq!(ds.len(), 3);
        assert_eq!(ds[0].severity, Severity::Info);
        assert_eq!(ds[2].line, Some(9));
    }

    #[test]
    fn round_trips_through_display() {
        let s = "Error: 9:2: ';' expected";
        assert_eq!(Diagnostic::parse_line(s).unwrap().to_string(), s);
    }
}
