import AppKit
import BrowserdoorCore

// `Browserdoor --list-targets`: print the discovered targets and the command each would run, without UI.
if CommandLine.arguments.dropFirst().contains("--list-targets") {
    let state = TargetCatalog(environment: SystemEnvironment()).load()
    print(state.listing(isRunning: SystemLaunchPort().isRunning))
    exit(0)
}

MainActor.assumeIsolated {
    let app = NSApplication.shared
    let delegate = AppDelegate()
    app.delegate = delegate
    app.setActivationPolicy(.accessory)
    app.run()
}
