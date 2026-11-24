//! The fixtures in `fixtures/` are shared with the Swift tests, so both apps read Zen's files
//! the same way. `fixtures/zen/zen-sessions.jsonlz4` was written by a real Zen (contract test).

use std::path::PathBuf;

use browserdoor_core::families::{ZenSpace, zen_spaces_from_session_file};

fn fixture(name: &str) -> Vec<u8> {
    let path = PathBuf::from(env!("CARGO_MANIFEST_DIR")).join("../../fixtures").join(name);
    std::fs::read(&path).unwrap_or_else(|e| panic!("{}: {e}", path.display()))
}

#[test]
fn reads_the_session_file_zen_wrote() {
    let spaces = zen_spaces_from_session_file(&fixture("zen/zen-sessions.jsonlz4")).unwrap();
    let expected: Vec<serde_json::Value> = serde_json::from_slice(&fixture("zen/spaces.json")).unwrap();
    let actual: Vec<serde_json::Value> = spaces.iter().map(|s: &ZenSpace| serde_json::to_value(s).unwrap()).collect();
    assert_eq!(actual, expected);
}
