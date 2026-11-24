//! Link opening: links + target → launch, behind the `LaunchPort` seam.

use crate::target::{LaunchCommand, Target};

/// Everything opening links needs from the system. The app's adapter uses `CreateProcess` and
/// the process list; tests record the calls.
pub trait LaunchPort {
    /// Whether the `.exe` runs right now. Must not err towards false: a running Zen taken for
    /// closed gets a cold-start command.
    fn is_running(&self, exe: &str) -> bool;
    /// Starts a detached process, without waiting for it.
    fn run(&self, command: &LaunchCommand);
    /// Brings the app's window to the front.
    fn activate(&self, exe: &str);
}

pub struct LinkOpener<'a> {
    pub port: &'a dyn LaunchPort,
}

impl LinkOpener<'_> {
    /// Opens `links` in `target` with its family's commands, then brings the app forward if the
    /// family asks for it.
    pub fn open(&self, links: &[String], target: &Target) {
        let running = self.port.is_running(target.exe());
        let commands = target.launch_commands(links, running);
        for c in &commands {
            self.port.run(c);
        }
        if running && !commands.is_empty() && target.activates_after_remote_command() {
            self.port.activate(target.exe());
        }
    }
}

#[cfg(test)]
mod tests {
    use std::cell::RefCell;

    use super::*;
    use crate::target::TargetKind;

    #[derive(Default)]
    struct Recording {
        running: bool,
        calls: RefCell<Vec<String>>,
    }

    impl LaunchPort for Recording {
        fn is_running(&self, _: &str) -> bool {
            self.running
        }
        fn run(&self, c: &LaunchCommand) {
            self.calls.borrow_mut().push(format!("run {} {}", c.exe, c.args.join(" ")));
        }
        fn activate(&self, exe: &str) {
            self.calls.borrow_mut().push(format!("activate {exe}"));
        }
    }

    #[test]
    fn zen_running_is_activated_after_the_remote_commands() {
        let port = Recording { running: true, ..Default::default() };
        let t = Target {
            id: "zen:{u}".into(),
            name: "W".into(),
            kind: TargetKind::ZenSpace {
                exe: "zen.exe".into(),
                uuid: "{u}".into(),
                profile: None,
                icon: None,
                color: None,
            },
        };
        LinkOpener { port: &port }.open(&["https://a.com/".into()], &t);
        assert_eq!(*port.calls.borrow(), ["run zen.exe --space {u} https://a.com/", "activate zen.exe"]);
    }

    #[test]
    fn nothing_runs_for_rejected_links() {
        let port = Recording { running: true, ..Default::default() };
        let t = Target { id: "app:X".into(), name: "X".into(), kind: TargetKind::App { exe: "x.exe".into() } };
        LinkOpener { port: &port }.open(&["javascript:x".into()], &t);
        assert!(port.calls.borrow().is_empty());
    }
}
