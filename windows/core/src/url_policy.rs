//! Which URLs Browserdoor hands to browsers.
//!
//! URLs become command-line arguments (`zen.exe --space … <url>`), so anything that is not a
//! plain web or file URL (a `--flag`, `javascript:`) must never get through.

use url::Url;

pub fn is_allowed(url: &str) -> bool {
    if url.starts_with('-') {
        return false;
    }
    match Url::parse(url) {
        Ok(u) => matches!(u.scheme(), "http" | "https" | "file"),
        Err(_) => false,
    }
}

pub fn filter(urls: &[String]) -> Vec<String> {
    urls.iter().filter(|u| is_allowed(u)).cloned().collect()
}

/// What the system hands Browserdoor on the command line, as a link: a URL, or the path of an
/// `.html`/`.htm` file (turned into a `file:` URL). None for anything else.
pub fn link_from_argument(arg: &str) -> Option<String> {
    let arg = arg.trim().trim_matches('"');
    if arg.is_empty() || arg.starts_with('-') {
        return None;
    }
    let lower = arg.to_ascii_lowercase();
    let is_path = crate::paths::is_absolute(arg) && !lower.starts_with("http") && !lower.starts_with("file:");
    if is_path {
        if !(lower.ends_with(".html") || lower.ends_with(".htm") || lower.ends_with(".xhtml")) {
            return None;
        }
        return file_url(arg);
    }
    let parsed = Url::parse(arg).ok()?;
    let s = parsed.to_string();
    is_allowed(&s).then_some(s)
}

/// `C:\a b\x.html` → `file:///C:/a%20b/x.html`, on any host.
fn file_url(path: &str) -> Option<String> {
    let forward = path.replace('\\', "/");
    let raw = if forward.starts_with("//") { format!("file:{forward}") } else { format!("file:///{forward}") };
    Url::parse(&raw).ok().map(|u| u.to_string())
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn allows_web_and_file_only() {
        assert!(is_allowed("https://example.com"));
        assert!(is_allowed("HTTP://example.com/x"));
        assert!(is_allowed("file:///C:/x.html"));
        for bad in ["javascript:alert(1)", "--remote-debugging-port=9222", "mailto:a@b.c", "ftp://x", "", "-https://x"]
        {
            assert!(!is_allowed(bad), "{bad}");
        }
    }

    #[test]
    fn arguments_become_links() {
        assert_eq!(link_from_argument("https://example.com").as_deref(), Some("https://example.com/"));
        assert_eq!(
            link_from_argument(r"C:\Users\a\My Page.html").as_deref(),
            Some("file:///C:/Users/a/My%20Page.html")
        );
        assert_eq!(link_from_argument(r#""C:\x\y.htm""#).as_deref(), Some("file:///C:/x/y.htm"));
        assert_eq!(link_from_argument(r"C:\x\evil.exe"), None);
        assert_eq!(link_from_argument("--background"), None);
        assert_eq!(link_from_argument("javascript:alert(1)"), None);
        assert_eq!(link_from_argument("not a url"), None);
    }
}
