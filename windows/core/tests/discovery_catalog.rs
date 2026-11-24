//! Discovery and the target catalog through their interfaces, against a fake Windows.

use std::collections::HashMap;

use browserdoor_core::{
    BrowserEnvironment, CatalogState, Config, ExeInfo, PickerSession, RegisteredApp, TargetCatalog, TargetKind, mozlz4,
};

const LOCAL: &str = r"C:\Users\anna\AppData\Local";
const ROAMING: &str = r"C:\Users\anna\AppData\Roaming";
const ZEN_EXE: &str = r"C:\Program Files\Zen Browser\zen.exe";
const CHROME_EXE: &str = r"C:\Program Files\Google\Chrome\Application\chrome.exe";
const EDGE_EXE: &str = r"C:\Program Files (x86)\Microsoft\Edge\Application\msedge.exe";
const FIREFOX_EXE: &str = r"C:\Program Files\Mozilla Firefox\firefox.exe";

#[derive(Default)]
struct FakeWindows {
    apps: Vec<RegisteredApp>,
    files: HashMap<String, Vec<u8>>,
    exes: HashMap<String, String>,
}

impl FakeWindows {
    fn app(&mut self, app_id: &str, name: &str, exe: &str) -> &mut Self {
        self.apps.push(RegisteredApp { app_id: app_id.into(), name: name.into(), exe: exe.into() });
        self
    }
    fn file(&mut self, path: &str, data: impl Into<Vec<u8>>) -> &mut Self {
        self.files.insert(path.to_lowercase(), data.into());
        self
    }
}

impl BrowserEnvironment for FakeWindows {
    fn local_app_data(&self) -> String {
        LOCAL.into()
    }
    fn roaming_app_data(&self) -> String {
        ROAMING.into()
    }
    fn own_app_id(&self) -> String {
        "Browserdoor".into()
    }
    fn registered_browsers(&self) -> Vec<RegisteredApp> {
        self.apps.clone()
    }
    fn contents(&self, path: &str) -> Option<Vec<u8>> {
        self.files.get(&path.to_lowercase()).cloned()
    }
    fn exe_info(&self, exe: &str) -> Option<ExeInfo> {
        self.exes.get(exe).map(|n| ExeInfo { name: n.clone() })
    }
}

fn zen_session(spaces: &str) -> Vec<u8> {
    mozlz4::wrap_literal(format!(r#"{{"spaces":[{spaces}]}}"#).as_bytes())
}

fn windows() -> FakeWindows {
    let mut w = FakeWindows::default();
    w.app("Browserdoor", "Browserdoor", r"C:\Users\anna\scoop\apps\browserdoor\current\browserdoor.exe")
        .app("Microsoft Edge", "Microsoft Edge", EDGE_EXE)
        .app("Firefox-308046B0AF4A39CB", "Firefox", FIREFOX_EXE)
        .app("Zen Browser", "Zen", ZEN_EXE)
        .app("Google Chrome", "Google Chrome", CHROME_EXE)
        .app("Opera", "Opera", r"C:\Users\anna\AppData\Local\Programs\Opera\opera.exe")
        .app("IEXPLORE.EXE", "Internet Explorer", r"C:\Program Files\Internet Explorer\iexplore.exe")
        .file(r"C:\Program Files\Zen Browser\application.ini", "[App]\nVersion=1.24.3b\n")
        .file(&format!(r"{ROAMING}\zen\profiles.ini"), "[Install1]\nDefault=Profiles/z.Default (release)\n")
        .file(
            &format!(r"{ROAMING}\zen\Profiles\z.Default (release)\zen-sessions.jsonlz4"),
            zen_session(r#"{"uuid":"{w}","name":"Work","icon":"💼"},{"uuid":"{h}","name":"Home"}"#),
        )
        .file(
            &format!(r"{LOCAL}\Google\Chrome\User Data\Local State"),
            r#"{"profile":{"info_cache":{"Default":{"name":"Anna"},"Profile 1":{"name":"Client"}}}}"#,
        )
        .file(&format!(r"{LOCAL}\Microsoft\Edge\User Data\Local State"), r#"{"profile":{"info_cache":{"Default":{"name":"Me"}}}}"#)
        .file(
            &format!(r"{ROAMING}\Mozilla\Firefox\profiles.ini"),
            "[Profile0]\nName=default-release\nPath=Profiles/a.default-release\n[Profile1]\nName=Work\nPath=Profiles/b.work\n",
        );
    w
}

fn catalog_in(env: &FakeWindows, dir: &tempfile::TempDir) -> CatalogState {
    TargetCatalog { environment: env, config_path: dir.path().join("config.json") }.load()
}

#[test]
fn discovers_spaces_profiles_and_browsers_in_default_order() {
    let env = windows();
    let dir = tempfile::tempdir().unwrap();
    let state = catalog_in(&env, &dir);
    let ids: Vec<&str> = state.targets.iter().map(|t| t.id.as_str()).collect();
    assert_eq!(
        ids,
        [
            "zen:{w}",
            "zen:{h}",
            "chromium:Google Chrome:Default",
            "chromium:Google Chrome:Profile 1",
            "chromium:Microsoft Edge:Default",
            "firefox:Firefox-308046B0AF4A39CB:Profiles/a.default-release",
            "firefox:Firefox-308046B0AF4A39CB:Profiles/b.work",
            "app:Opera",
        ]
    );
    let names: Vec<&str> = state.targets.iter().map(|t| t.name.as_str()).collect();
    assert_eq!(names[2], "Google Chrome › Anna");
    assert_eq!(names[4], "Microsoft Edge", "a single profile shows only the app name");
    assert_eq!(names[6], "Firefox › Work");
    match &state.targets[0].kind {
        TargetKind::ZenSpace { icon, exe, .. } => {
            assert_eq!(icon.as_deref(), Some("💼"));
            assert_eq!(exe, ZEN_EXE);
        }
        k => panic!("{k:?}"),
    }
    match &state.targets[6].kind {
        TargetKind::FirefoxProfile { profile, .. } => {
            assert_eq!(profile, &format!(r"{ROAMING}\Mozilla\Firefox\Profiles\b.work"))
        }
        k => panic!("{k:?}"),
    }
}

#[test]
fn old_zen_or_missing_session_is_one_plain_entry() {
    let mut env = windows();
    env.file(r"C:\Program Files\Zen Browser\application.ini", "[App]\nVersion=1.23.9b\n");
    let dir = tempfile::tempdir().unwrap();
    let state = catalog_in(&env, &dir);
    assert_eq!(state.targets[0].id, "app:Zen Browser");

    let mut env = windows();
    env.files.retain(|k, _| !k.ends_with("zen-sessions.jsonlz4"));
    assert_eq!(catalog_in(&env, &dir).targets[0].id, "app:Zen Browser");
}

#[test]
fn zen_profile_override_reads_that_profile_and_addresses_it() {
    let mut env = windows();
    env.file(r"D:\zen\other\zen-sessions.jsonlz4", zen_session(r#"{"uuid":"{o}","name":"Other"}"#));
    let dir = tempfile::tempdir().unwrap();
    let mut state = catalog_in(&env, &dir);
    state.set_zen_profile(Some(r"D:\zen\other"));
    let catalog = TargetCatalog { environment: &env, config_path: dir.path().join("config.json") };
    let state = catalog.save(&state).unwrap();
    assert_eq!(state.targets[0].id, "zen:{o}");
    let cmd = state.targets[0].launch_commands(&["https://a.com/".into()], true);
    assert_eq!(cmd[0].args, ["--profile", r"D:\zen\other", "--space", "{o}", "https://a.com/"]);
}

#[test]
fn extra_apps_are_listed_by_path_and_unlisted_when_gone() {
    let mut env = windows();
    env.exes.insert(r"C:\Tools\Wrap\wrap.exe".into(), "Wrap".into());
    let dir = tempfile::tempdir().unwrap();
    let catalog = TargetCatalog { environment: &env, config_path: dir.path().join("config.json") };
    let mut state = catalog.load();
    state.add_extra_apps(&[r"C:\Tools\Wrap\wrap.exe".into(), r"C:\Gone\gone.exe".into()]);
    let state = catalog.save(&state).unwrap();
    assert!(state.targets.iter().any(|t| t.id == r"app:C:\Tools\Wrap\wrap.exe" && t.name == "Wrap"));
    assert_eq!(state.unlisted_extra_apps(), [r"C:\Gone\gone.exe"]);
    assert_eq!(state.extra_app_for_target(r"app:C:\Tools\Wrap\wrap.exe").as_deref(), Some(r"C:\Tools\Wrap\wrap.exe"));
    assert_eq!(state.extra_app_for_target("app:Opera"), None);
}

#[test]
fn edits_are_saved_and_survive_targets_that_are_missing_now() {
    let env = windows();
    let dir = tempfile::tempdir().unwrap();
    let path = dir.path().join("config.json");
    Config { order: Some(vec!["zen:{gone}".into()]), hidden: Some(vec!["zen:{gone}".into()]), ..Default::default() }
        .save(&path)
        .unwrap();
    let catalog = TargetCatalog { environment: &env, config_path: path.clone() };
    let mut state = catalog.load();
    state.rename("app:Opera", "O");
    state.set_hidden("zen:{h}", true);
    state.toggle_default("chromium:Google Chrome:Profile 1");
    state.move_row(7, 0);
    assert_eq!(state.set_hotkey("app:Opera", "2"), Some("Work".into()), "Work had the automatic 2");
    catalog.save(&state).unwrap();

    let config = Config::load(&path).unwrap();
    assert_eq!(config.order.as_ref().unwrap()[0], "app:Opera");
    assert_eq!(config.order.as_ref().unwrap().last().unwrap(), "zen:{gone}");
    assert_eq!(config.hidden.unwrap(), ["zen:{h}", "zen:{gone}"]);
    assert_eq!(config.targets.unwrap()["app:Opera"].label.as_deref(), Some("O"));

    let state = catalog.load();
    let entries = state.picker_entries();
    assert_eq!(entries[0].label, "O");
    assert_eq!(entries[0].hotkey, Some('2'));
    assert_eq!(entries[1].hotkey, Some('1'), "the first free number key");
    assert!(entries.iter().all(|e| e.target.id != "zen:{h}"));
    let session = PickerSession::from_catalog(vec!["https://a.com/".into()], &state);
    assert_eq!(session.entries[session.selection].target.id, "chromium:Google Chrome:Profile 1");
    assert_eq!(session.badges.len(), 4, "two Chrome and two Firefox profiles");
}

#[test]
fn unreadable_config_falls_back_to_defaults_and_says_so() {
    let env = windows();
    let dir = tempfile::tempdir().unwrap();
    std::fs::write(dir.path().join("config.json"), "{ broken").unwrap();
    let state = catalog_in(&env, &dir);
    assert!(state.config_is_unreadable);
    assert_eq!(state.targets.len(), 8);
    let listing = browserdoor_core::listing::listing(&state, &|_| false);
    assert!(listing.starts_with("# config file unreadable"));
    assert!(listing.contains(
        "zen:{w}\tWork\tdefault\t\"C:\\Program Files\\Zen Browser\\zen.exe\" --space {w} https://example.com/"
    ));
}
