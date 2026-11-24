//! What `browserdoor.exe --list-targets` prints (SPEC 12): one tab-separated line per target in
//! picker order, hidden ones included, with key, ID, name, flags and the command a link would
//! open with. Nothing is launched.

use crate::catalog::CatalogState;
use crate::target::LaunchCommand;

pub fn listing(state: &CatalogState, is_running: &dyn Fn(&str) -> bool) -> String {
    let entries = state.picker_entries();
    let keys = state.effective_keys();
    let default_id = state.default_index(&entries).map(|i| entries[i].target.id.clone());
    let sample = vec!["https://example.com/".to_string()];
    let mut lines = vec![];
    if state.config_is_unreadable {
        lines.push("# config file unreadable, defaults in use".to_string());
    }
    for row in &state.rows {
        let mut flags = vec![];
        if Some(&row.target.id) == default_id.as_ref() {
            flags.push("default");
        }
        if row.hidden {
            flags.push("hidden");
        }
        let commands = row.target.launch_commands(&sample, is_running(row.target.exe()));
        lines.push(
            [
                keys.iter()
                    .find(|(id, _)| *id == row.target.id)
                    .map(|(_, k)| k.to_string())
                    .unwrap_or_else(|| "-".into()),
                row.target.id.clone(),
                row.display_name().to_string(),
                if flags.is_empty() { "-".into() } else { flags.join(",") },
                commands.iter().map(command_line).collect::<Vec<_>>().join(" ; "),
            ]
            .join("\t"),
        );
    }
    lines.join("\n")
}

/// The command as it would be typed in a terminal.
pub fn command_line(c: &LaunchCommand) -> String {
    std::iter::once(&c.exe).chain(c.args.iter()).map(|w| quote(w)).collect::<Vec<_>>().join(" ")
}

fn quote(word: &str) -> String {
    if !word.is_empty() && !word.contains([' ', '\t', '"']) {
        word.to_string()
    } else {
        format!("\"{}\"", word.replace('"', "\\\""))
    }
}
