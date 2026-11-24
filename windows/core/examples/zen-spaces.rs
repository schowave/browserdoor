//! Prints the spaces in a `zen-sessions.jsonlz4` as JSON, the way Browserdoor reads them.
//! The Zen contract test compares this with what Zen itself reports.
//! Usage: cargo run -p browserdoor-core --example zen-spaces -- <zen-sessions.jsonlz4>

fn main() {
    let path = std::env::args().nth(1).expect("usage: zen-spaces <zen-sessions.jsonlz4>");
    let data = std::fs::read(&path).unwrap_or_else(|e| panic!("{path}: {e}"));
    let spaces = browserdoor_core::families::zen_spaces_from_session_file(&data).expect("not a Zen session file");
    println!("{}", serde_json::to_string_pretty(&spaces).unwrap());
}
