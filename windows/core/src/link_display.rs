//! How the picker names a link: the part that decides where it goes (the host, or a file's name)
//! prominently, the rest quietly. Hosts show as the URL parser normalizes them, so non-ASCII
//! names appear in Punycode and a look-alike doesn't pass for the real one; user info is never
//! shown; a host with characters a host name can't have stays percent-encoded.

use url::{Host, Url};

#[derive(Debug, Clone, PartialEq, Eq, serde::Serialize)]
pub struct LinkDisplay {
    /// Host (with port), or the file name.
    pub primary: String,
    /// Path, query and fragment; for a file its folder, `~` for the home folder.
    pub secondary: String,
}

impl LinkDisplay {
    /// `home` is the user's profile folder (`C:\Users\name`).
    pub fn new(link: &str, home: &str) -> LinkDisplay {
        let Ok(url) = Url::parse(link) else {
            return LinkDisplay { primary: link.to_string(), secondary: String::new() };
        };
        if url.scheme() == "file" {
            let path = percent_decode(url.path()).replace('/', "\\");
            let path = path.trim_start_matches('\\').to_string();
            let path = if path.len() >= 2 && path.as_bytes()[1] == b':' { path } else { format!("\\{path}") };
            let name = crate::paths::file_name(&path).to_string();
            let folder = crate::paths::parent(&path).to_string();
            let home = home.trim_end_matches('\\');
            let shown = if folder.eq_ignore_ascii_case(home)
                || folder.to_lowercase().starts_with(&(home.to_lowercase() + "\\"))
            {
                format!("~{}", &folder[home.len()..])
            } else {
                folder
            };
            return LinkDisplay { primary: name, secondary: shown };
        }
        let host = match url.host() {
            Some(Host::Domain(d)) => d.to_string(),
            Some(Host::Ipv4(a)) => a.to_string(),
            Some(Host::Ipv6(a)) => format!("[{a}]"),
            None => return LinkDisplay { primary: link.to_string(), secondary: String::new() },
        };
        let primary = match url.port() {
            Some(p) => format!("{host}:{p}"),
            None => host,
        };
        let mut rest = url.path().to_string();
        if let Some(q) = url.query() {
            rest.push('?');
            rest.push_str(q);
        }
        if let Some(f) = url.fragment() {
            rest.push('#');
            rest.push_str(f);
        }
        LinkDisplay { primary, secondary: if rest == "/" { String::new() } else { rest } }
    }
}

fn percent_decode(s: &str) -> String {
    let bytes = s.as_bytes();
    let mut out = Vec::with_capacity(bytes.len());
    let mut i = 0;
    while i < bytes.len() {
        if bytes[i] == b'%'
            && i + 2 < bytes.len()
            && let Ok(b) = u8::from_str_radix(&s[i + 1..i + 3], 16)
        {
            out.push(b);
            i += 3;
            continue;
        }
        out.push(bytes[i]);
        i += 1;
    }
    String::from_utf8_lossy(&out).into_owned()
}

#[cfg(test)]
mod tests {
    use super::LinkDisplay;

    fn d(link: &str) -> (String, String) {
        let x = LinkDisplay::new(link, r"C:\Users\anna");
        (x.primary, x.secondary)
    }

    #[test]
    fn web_links() {
        assert_eq!(d("https://example.com/"), ("example.com".into(), "".into()));
        assert_eq!(d("https://example.com:8443/a/b?q=1#f"), ("example.com:8443".into(), "/a/b?q=1#f".into()));
        assert_eq!(d("https://bank.com@evil.io/x").0, "evil.io");
        assert_eq!(d("https://аpple.com/").0, "xn--pple-43d.com");
        assert_eq!(d("http://[::1]:8080/").0, "[::1]:8080");
        // A host that decodes to `/` or `@` doesn't parse, so such a link never reaches the picker.
        assert!(!crate::url_policy::is_allowed("https://apple.com%2Fsignin.evil.io/"));
    }

    #[test]
    fn file_links() {
        assert_eq!(d("file:///C:/Users/anna/Documents/My%20Page.html"), ("My Page.html".into(), r"~\Documents".into()));
        assert_eq!(d("file:///D:/x/y.html"), ("y.html".into(), r"D:\x".into()));
    }
}
