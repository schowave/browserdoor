//! Browserdoor for Windows: the domain, without any Windows API.
//!
//! The terms follow `GLOSSARY.md`; the behaviour follows `SPEC.md` (sections marked "Windows"
//! where it differs from macOS). Everything the system provides comes in through two seams:
//! [`BrowserEnvironment`] (discovery) and [`LaunchPort`] (opening links). The app crate
//! implements them with the registry, the file system and `CreateProcess`; tests use fakes.

pub mod badge;
pub mod catalog;
pub mod config;
pub mod discovery;
pub mod families;
pub mod ini;
pub mod link_display;
pub mod links;
pub mod listing;
pub mod mozlz4;
pub mod opener;
pub mod paths;
pub mod picker;
pub mod placement;
pub mod target;
pub mod target_id;
pub mod update;
pub mod url_policy;

pub use catalog::{CatalogState, PickerEntry, TargetCatalog, TargetSetting};
pub use config::Config;
pub use discovery::{BrowserEnvironment, Discovery, ExeInfo, RegisteredApp};
pub use opener::{LaunchPort, LinkOpener};
pub use picker::{PickerEffect, PickerInput, PickerSession};
pub use target::{LaunchCommand, Target, TargetKind};
pub use target_id::TargetId;
