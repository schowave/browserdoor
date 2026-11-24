//! Links in a text, e.g. the clipboard: without surrounding punctuation, and `example.com/x` as
//! `http://example.com/x` (SPEC 6.2, "Open Link from Clipboard"). Pass the result through
//! `url_policy`.

use url::Url;

pub fn urls_in_text(text: &str) -> Vec<String> {
    let mut out: Vec<String> = vec![];
    for word in text.split(|c: char| c.is_whitespace() || matches!(c, '<' | '>' | '"' | '\'')) {
        let word = word
            .trim_matches(|c: char| matches!(c, '(' | ')' | '[' | ']' | '{' | '}' | ',' | '.' | ';' | ':' | '!' | '?'));
        if word.is_empty() {
            continue;
        }
        let lower = word.to_ascii_lowercase();
        let candidate = if lower.starts_with("http://") || lower.starts_with("https://") {
            word.to_string()
        } else if looks_like_domain(word) {
            format!("http://{word}")
        } else {
            continue;
        };
        if let Ok(u) = Url::parse(&candidate)
            && u.host_str().is_some_and(|h| h.contains('.') || h == "localhost")
        {
            let s = u.to_string();
            if !out.contains(&s) {
                out.push(s);
            }
        }
    }
    out
}

/// `example.com`, `www.example.org/path`: a host with a dot and a top-level domain of letters.
fn looks_like_domain(word: &str) -> bool {
    if word.contains('@') || word.contains("://") {
        return false;
    }
    let host = word.split(['/', '?', '#']).next().unwrap_or("");
    let host = host.split(':').next().unwrap_or("");
    let labels: Vec<&str> = host.split('.').collect();
    labels.len() >= 2
        && labels.iter().all(|l| !l.is_empty() && l.chars().all(|c| c.is_alphanumeric() || c == '-'))
        && labels.last().is_some_and(|tld| tld.len() >= 2 && tld.chars().all(char::is_alphabetic))
}

#[cfg(test)]
mod tests {
    use super::urls_in_text;

    #[test]
    fn finds_links() {
        assert_eq!(
            urls_in_text("See (https://example.com/a?b=1). Also example.org/x, and mail me@x.com or 1.5 or file.txt"),
            ["https://example.com/a?b=1", "http://example.org/x", "http://file.txt/"]
        );
        assert!(urls_in_text("nothing here").is_empty());
    }
}
