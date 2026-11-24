//! The INI dialect of `profiles.ini` and `application.ini`.

use std::collections::HashMap;

#[derive(Debug, Clone, PartialEq, Eq)]
pub struct Section {
    pub name: String,
    pub values: HashMap<String, String>,
}

impl Section {
    pub fn get(&self, key: &str) -> Option<&str> {
        self.values.get(key).map(String::as_str)
    }
}

/// Sections in file order. Comments (`;`, `#`) and lines before the first section are skipped.
pub fn parse(text: &str) -> Vec<Section> {
    let mut sections: Vec<Section> = Vec::new();
    for raw in text.lines() {
        let line = raw.trim().trim_start_matches('\u{feff}');
        if line.is_empty() || line.starts_with(';') || line.starts_with('#') {
            continue;
        }
        if line.starts_with('[') && line.ends_with(']') {
            sections.push(Section { name: line[1..line.len() - 1].to_string(), values: HashMap::new() });
        } else if let (Some(eq), Some(section)) = (line.find('='), sections.last_mut()) {
            section.values.insert(line[..eq].trim().to_string(), line[eq + 1..].trim().to_string());
        }
    }
    sections
}

#[cfg(test)]
mod tests {
    #[test]
    fn parses_sections_and_skips_comments() {
        let s = super::parse("\u{feff}; c\nx=1\n[App]\nVersion = 1.24.3b\n# c\n[B]\nk=v=w\n");
        assert_eq!(s.len(), 2);
        assert_eq!(s[0].get("Version"), Some("1.24.3b"));
        assert_eq!(s[1].get("k"), Some("v=w"));
    }
}
