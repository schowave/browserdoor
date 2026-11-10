/// Bundle IDs of real web browsers. Only these (plus `extraApps` from the config) show up
/// as targets — LaunchServices also lists terminals, web-app wrappers, test builds etc.
public enum KnownBrowsers {
    public static let bundleIds: Set<String> = [
        // WebKit
        "com.apple.Safari",
        "com.apple.SafariTechnologyPreview",
        "com.kagi.kagimacOS", // Orion
        "com.duckduckgo.macos.browser",
        // Gecko
        "org.mozilla.firefox",
        "org.mozilla.firefoxdeveloperedition",
        "org.mozilla.nightly",
        "app.zen-browser.zen",
        "one.ablaze.floorp",
        "io.gitlab.librewolf-community",
        "net.waterfox.waterfox",
        "org.torproject.torbrowser",
        // Chromium
        "com.google.Chrome",
        "com.google.Chrome.beta",
        "com.google.Chrome.dev",
        "com.google.Chrome.canary",
        "org.chromium.Chromium",
        "com.brave.Browser",
        "com.brave.Browser.beta",
        "com.brave.Browser.nightly",
        "com.microsoft.edgemac",
        "com.microsoft.edgemac.Beta",
        "com.microsoft.edgemac.Dev",
        "com.microsoft.edgemac.Canary",
        "com.vivaldi.Vivaldi",
        "com.operasoftware.Opera",
        "com.operasoftware.OperaGX",
        "company.thebrowser.Browser", // Arc
        "company.thebrowser.dia",
        "com.sigmaos.sigmaos.macos",
        "com.naver.Whale",
        "ru.yandex.desktop.yandex-browser",
    ]
}
