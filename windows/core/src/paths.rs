//! Windows paths as strings, so the domain behaves the same on any host (tests run on macOS too).

/// `base` joined with `rel`, which may use `/` (as `profiles.ini` does) or `\`.
pub fn join(base: &str, rel: &str) -> String {
    let mut out = base.trim_end_matches(['\\', '/']).to_string();
    for part in rel.split(['\\', '/']).filter(|p| !p.is_empty()) {
        out.push('\\');
        out.push_str(part);
    }
    out
}

/// `C:\…`, `C:/…`, `\\server\…` or `/…`.
pub fn is_absolute(path: &str) -> bool {
    let b = path.as_bytes();
    (b.len() >= 3 && b[0].is_ascii_alphabetic() && b[1] == b':' && (b[2] == b'\\' || b[2] == b'/'))
        || path.starts_with("\\\\")
        || path.starts_with('/')
}

/// The folder that holds `path`.
pub fn parent(path: &str) -> &str {
    match path.rfind(['\\', '/']) {
        Some(i) => &path[..i],
        None => "",
    }
}

/// The last component of `path`.
pub fn file_name(path: &str) -> &str {
    match path.rfind(['\\', '/']) {
        Some(i) => &path[i + 1..],
        None => path,
    }
}

/// For comparisons: backslashes, lowercase.
pub fn normalized(path: &str) -> String {
    path.replace('/', "\\").to_lowercase()
}

/// `ends_with` on normalized paths, so `C:\Program Files\Google\Chrome\Application\chrome.exe`
/// matches `\google\chrome\application\chrome.exe`.
pub fn ends_with(path: &str, suffix: &str) -> bool {
    normalized(path).ends_with(&normalized(suffix))
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn joins_with_backslashes() {
        assert_eq!(
            join(r"C:\Users\a\AppData\Roaming\", "zen/Profiles/x.Default"),
            r"C:\Users\a\AppData\Roaming\zen\Profiles\x.Default"
        );
        assert_eq!(join(r"C:\a", r"b\c"), r"C:\a\b\c");
    }

    #[test]
    fn absolute_paths() {
        assert!(is_absolute(r"C:\x"));
        assert!(is_absolute("D:/x"));
        assert!(is_absolute(r"\\server\share"));
        assert!(!is_absolute("Profiles/x"));
        assert!(!is_absolute("C:x"));
    }

    #[test]
    fn parent_and_name() {
        assert_eq!(parent(r"C:\Program Files\Zen Browser\zen.exe"), r"C:\Program Files\Zen Browser");
        assert_eq!(file_name(r"C:\Program Files\Zen Browser\zen.exe"), "zen.exe");
        assert!(ends_with(
            r"C:\Program Files\Google\Chrome\Application\chrome.exe",
            r"\google\chrome\application\chrome.exe"
        ));
    }
}
