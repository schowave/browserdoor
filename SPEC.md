# Doorman — Spezifikation v1

Doorman ist ein macOS-Link-Picker in der Art von Browserosaurus. Er wird als Standardbrowser registriert. Beim Klick auf einen Link erscheint an der Mausposition ein Panel. Darin wählt man das Ziel: einen **Zen-Workspace**, ein **Chromium-Profil** oder einen anderen installierten Browser.

## 1. Ziele und Nicht-Ziele

**v1 umfasst**
- Standardbrowser für `http`, `https`, `.html` und `.webloc`
- Panel mit einer gemischten Zielliste: Zen-Workspaces, Chromium-Browser × Profile, übrige Browser
- Konfiguration als JSON-Datei
- Installation per Homebrew-Formula aus einem eigenen Tap

**Nicht in v1**
- Regel-Engine (à la Finicky)
- Bypass per Modifier-Taste
- Einstellungsfenster (GUI)
- Code-Signierung und Cask
- editierbare URL im Panel
- `mailto:`
- mehrere Zen-Profile
- Firefox-Container als eigene Ziele
- Safari-Profile (Safari hat dafür kein CLI)

## 2. Plattform und Technik

- Swift 6, SwiftUI und AppKit, **macOS 14+**.
- Build mit Swift Package Manager. `make app` baut daraus `Doorman.app`. Ein vollständiges Xcode ist nicht nötig.
- Die App läuft dauerhaft im Hintergrund:
  - `LSUIElement`, also kein Dock-Icon
  - Menüleisten-Icon (`NSStatusItem`; das Menü wird bei jedem Öffnen neu aufgebaut, damit die Statuszeilen aktuell sind)
  - Autostart über einen LaunchAgent (siehe 7)
- Lizenz: MIT. Das Repo liegt öffentlich auf GitHub.

## 3. Ziele (Targets)

Ein **Ziel** ist ein Eintrag im Panel. Jedes Ziel hat eine stabile `id`, einen Anzeigenamen, ein Icon und eine Methode zum Öffnen.

| Art | ID-Schema | Öffnen |
|---|---|---|
| Zen-Workspace | `zen:{<uuid>}` | Zen läuft: `<Zen.app>/Contents/MacOS/zen --space "{uuid}" <url>` je URL. Zen läuft nicht: `open -a <Zen.app> --args --space "{uuid}" <url…>` |
| Zen ohne Workspace-Support | `app:app.zen-browser.zen` | wie ein normaler Browser |
| Chromium-Profil | `chromium:<bundleId>:<profileDir>` | `open -na <App> --args --profile-directory=<dir> <url…>` |
| Normaler Browser | `app:<bundleId>` | `NSWorkspace.open(urls, withApplicationAt:)` |

### 3.1 Zen

- **App finden**: über die Bundle-ID `app.zen-browser.zen` unter den https-Handlern (siehe 3.3, Pfadfilter).
- **Profil**: Gelesen wird `~/Library/Application Support/zen/profiles.ini`. Maßgeblich ist die `Default=`-Zeile der `[Install…]`-Sektion. Gibt es sie nicht, gilt das Profil mit `Default=1`. In der Konfiguration lässt sich das Profil mit `zen.profilePath` überschreiben.
- **Workspaces**: Sie stehen in `<profile>/zen-sessions.jsonlz4`.
  - Format: mozLz4. Die Datei beginnt mit der Magic `mozLz40\0` (8 Byte), danach folgt die Größe als uint32 LE, danach ein rohes LZ4-Block-Payload.
  - Daraus wird `spaces[]` gelesen, jeweils mit `uuid`, `name`, `icon` und `theme.gradientColors`.
  - Die Datei wird **bei jedem Öffnen des Panels** neu gelesen.
- **Icons**: `icon` ist eine `chrome://browser/skin/zen-icons/selectable/<name>.svg`-URL, ein Emoji oder leer.
  - Die SVGs liegen in `<Zen.app>/Contents/Resources/browser/omni.ja` (ein Zip) unter `chrome/browser/skin/classic/browser/zen-icons/selectable/`.
  - Sie werden einmalig pro Zen-Version nach `~/Library/Caches/io.github.schowave.doorman/zen-icons/<version>/` extrahiert.
  - Fallback: Ist das Icon ein Emoji, wird es direkt angezeigt. Sonst erscheint der Anfangsbuchstabe auf der Theme-Farbe.
- **Versionsprüfung**: `--space` gibt es ab Zen 1.24 (PR zen-browser/desktop#15074). Ist die Version älter (`CFBundleShortVersionString`) oder kann die Datei nicht gelesen werden, erscheint Zen als ein einzelnes `app:`-Ziel.
- **Zen läuft nicht**: Doorman startet Zen über LaunchServices (`open -a … --args --space …`), damit Zen kein Kindprozess von Doorman wird. Zen merkt sich den Space für den Start (`zen.workspaces.cmdline-initial-workspace`).
- **Zen läuft**: Der direkte Aufruf übergibt an die laufende Instanz und kehrt sofort zurück (getestet mit 1.24.1b). Danach aktiviert Doorman Zen.

### 3.2 Chromium-Browser

- **Unterstützte Browser** (`bundleId` → Datenverzeichnis unter `~/Library/Application Support/`):
  - `com.google.Chrome` → `Google/Chrome`
  - `com.google.Chrome.beta` → `Google/Chrome Beta`
  - `com.google.Chrome.canary` → `Google/Chrome Canary`
  - `com.brave.Browser` → `BraveSoftware/Brave-Browser`
  - `com.microsoft.edgemac` → `Microsoft Edge`
  - `com.vivaldi.Vivaldi` → `Vivaldi`
  - `org.chromium.Chromium` → `Chromium`
- **Profile**: Sie stehen in `<datadir>/Local State` unter `profile.info_cache`, als Abbildung `<profileDir>` → `{name}`.
- Gibt es **genau ein** Profil, erscheint der Browser als ein einzelner Eintrag ohne Profilnamen. Das Ziel-ID-Schema bleibt dann `chromium:<bundleId>:<profileDir>`.

### 3.3 Übrige Browser

- Grundlage sind alle Apps, die `https` öffnen können (`NSWorkspace.urlsForApplications(toOpen:)`).
- **Pfadfilter**: Es zählen nur Apps unter `/Applications`, `~/Applications` oder `/System`. Kopien in Caches oder Snapshots (Playwright, Puppeteer, …) fliegen raus. Gibt es eine Bundle-ID mehrfach, gewinnt die erste erlaubte Kopie.
- **Allowlist**: Gezeigt werden nur bekannte Browser (`KnownBrowsers`, analog zu Browserosaurus), plus die Bundle-IDs aus `extraApps` in der Konfiguration. LaunchServices listet sonst auch Terminals, Web-App-Wrapper, Finicky/Browserosaurus usw.
- Ausgenommen sind Doorman selbst sowie Zen und die Chromium-Browser, wenn sie schon über 3.1 oder 3.2 abgedeckt sind.

### 3.4 Erlaubte URLs

URLs landen als Kommandozeilen-Argumente bei den Browsern. Deshalb lässt Doorman nur `http`, `https` und `file` durch (`URLPolicy`); alles andere, auch `.webloc`-Inhalte wie `--remote-debugging-port=…` oder `javascript:`, wird verworfen. Die Prüfung greift beim Empfang und noch einmal beim Bauen der Launch-Kommandos.

Ist `zen.profilePath` gesetzt, bekommt jeder Zen-Aufruf zusätzlich `--profile <pfad>`, damit `--space` die Instanz mit diesem Profil erreicht.

## 4. Panel (UI)

- Ein schwebendes, randloses `NSPanel` an der Mausposition. Es wird auf den sichtbaren Bildschirmbereich begrenzt.
- **Inhalt**:
  - oben die URL, nicht editierbar und gekürzt; bei mehreren Links „N Links“ mit Tooltip
  - darunter die Liste der Ziele: Icon, Name, Hotkey
  - Button „URL kopieren“
- **Bedienung**:
  - Hotkey eines Eintrags öffnet dieses Ziel.
  - ↑ und ↓ bewegen die Auswahl, Enter öffnet die Auswahl. Vorausgewählt ist das Default-Ziel, sonst der erste Eintrag.
  - Esc oder ein Klick außerhalb schließt das Panel.
  - ⌘C kopiert die URL(s).
- **Hotkeys**: Ohne Konfiguration gilt `1`–`9`, dann `0` in Listenreihenfolge. In der Konfiguration lassen sie sich pro Ziel überschreiben.
- **Mehrere Links**: Treffen weitere URLs ein, solange das Panel offen ist, werden sie gesammelt. Eine Auswahl öffnet alle.

## 5. Konfiguration

Die Datei liegt unter `~/.config/doorman/config.json`. Sie ist optional; fehlt sie, gelten die Defaults. Unbekannte Felder werden ignoriert.

```json
{
  "defaultTarget": "zen:{b4ac0402-9e47-4873-89b6-5dfeffe77a7e}",
  "order": ["zen:{3d0f4d74-...}", "zen:{b4ac0402-...}", "app:com.apple.Safari"],
  "hidden": ["app:com.google.Chrome.beta"],
  "extraApps": ["com.googlecode.iterm2"],
  "targets": {
    "zen:{b4ac0402-9e47-4873-89b6-5dfeffe77a7e}": { "label": "David", "hotkey": "d" }
  },
  "zen": { "profilePath": null }
}
```

- **`order`**: Diese Ziele stehen zuerst, in der angegebenen Reihenfolge. Alle übrigen folgen in der Erkennungsreihenfolge:
  1. Zen-Workspaces in Zens Reihenfolge
  2. Chromium-Browser
  3. übrige Browser alphabetisch
- **`extraApps`**: Bundle-IDs von Apps, die keine bekannten Browser sind, aber trotzdem als Ziel erscheinen sollen.
- **`targets.<id>.label`**: Überschreibt den Anzeigenamen. Gleichzeitig ist es der lesbare Zusatz zur UUID.
- **Menüeintrag „Konfiguration öffnen“**: Er öffnet die Datei. Fehlt sie, legt er sie mit allen aktuell erkannten Ziel-IDs als Vorlage an.

## 6. Menüleiste

Die Menüleiste enthält folgende Einträge:
- Status: „Standardbrowser: ja/nein“, bei „nein“ mit dem Eintrag „Als Standardbrowser setzen“
- „Beim Login starten“ (Toggle)
- „Konfiguration öffnen“ (in TextEdit bzw. dem Standard-Texteditor)
- Versionsanzeige
- „Beenden“

## 7. Erster Start

Beim ersten Start passiert Folgendes:
1. Die App registriert sich bei LaunchServices (`LSRegisterURL`).
2. Ist Doorman nicht Standardbrowser, erscheint ein Dialog. Bei Zustimmung ruft die App `NSWorkspace.setDefaultApplication(at:toOpenURLsWithScheme:)` für http auf. macOS zeigt dann den eigenen Bestätigungsdialog.
3. Der Autostart wird aktiviert (LaunchAgent, siehe unten).

**Stabil über `brew upgrade`:** Homebrew installiert in ein versioniertes Cellar-Verzeichnis, das `brew cleanup` nach einem Upgrade löscht. Deshalb:
- Läuft Doorman aus einem Cellar, legt es bei jedem Start `~/Applications/Doorman.app` als Symlink auf `<brew prefix>/opt/doorman/Doorman.app` an (bzw. korrigiert einen veralteten eigenen Symlink). Eine echte App an dieser Stelle bleibt unangetastet.
- Der Autostart ist ein LaunchAgent `~/Library/LaunchAgents/io.github.schowave.doorman.plist`, der `open -a ~/Applications/Doorman.app` ausführt. `SMAppService.mainApp` würde sich den versionierten Pfad merken; ein solches Login-Item aus früheren Builds wird beim Start entfernt und ersetzt.
- Der Standardbrowser hängt an der Bundle-ID und ist damit pfadunabhängig; jeder Start registriert die laufende Kopie neu (`LSRegisterURL`).

## 8. Architektur

```
Sources/
  DoormanCore/   reine Logik, ohne AppKit-UI, vollständig getestet
    MozLz4            Decoder
    ZenProfile        profiles.ini → Profilpfad
    ZenSpaces         zen-sessions.jsonlz4 → [ZenSpace]
    ChromiumProfiles  Local State → [ChromiumProfile]
    Config            Laden, Defaults, Ordnen, Ausblenden, Hotkeys
    Target            Modell + Launch-Command je Ziel
    Discovery         Ziele ermitteln (über das Protokoll BrowserEnvironment)
    KnownBrowsers     Allowlist der Browser-Bundle-IDs
    WeblocParser      .webloc → URL
  Doorman/       App: AppDelegate + Menüleiste, Panel, Icons, Launcher, SystemEnvironment
Tests/DoormanCoreTests/
```

Seiteneffekte wie Dateisystem, `NSWorkspace` und `Process` stecken hinter kleinen Protokollen. Der Core bleibt so testbar.

## 9. Build, Distribution, CI

- `make app` führt `swift build -c release` aus und erzeugt `build/Doorman.app`. Die Info.plist kommt dabei aus `Resources/` (ein eigenes App-Icon gibt es in v1 noch nicht). Signiert wird ad hoc (`codesign -s -`).
- `make install PREFIX=…` legt die App unter `$PREFIX/Doorman.app` ab und ein Startskript unter `$PREFIX/bin/doorman`.
- **Homebrew**:
  - Die Formula `doorman` liegt im Tap `schowave/homebrew-tap`.
  - Sie baut aus dem Release-Tarball, mit `depends_on macos: :sonoma`.
  - Die caveats beschreiben den ersten Start (`open $(brew --prefix)/opt/doorman/Doorman.app`).
  - Eine Vorlage liegt in `packaging/homebrew/doorman.rb`.
- **CI** (GitHub Actions, macOS-Runner):
  - `swift test` und `make app`
  - `scripts/check-formula.sh` rendert die Formula-Vorlage probeweise und prüft sie.
  - Bei einem Tag `v*`: testen, App bauen, GitHub-Release anlegen (falls noch nicht vorhanden) und die Formula im Tap aktualisieren. Die Vorlage nutzt die Platzhalter `@VERSION@` und `@SHA256@`, gerendert von `scripts/render-formula.sh`. Der Workflow ist wiederholbar.

## 10. Tests

Folgende Teile des Cores sind abgedeckt:
- MozLz4-Decoder, gegen Fixtures (komprimierte Datei → erwartetes JSON)
- Parser für `zen-sessions`, `profiles.ini` und `Local State`
- Webloc-Parser
- Ordnen, Ausblenden, Labels und Hotkey-Vergabe der Konfiguration
- Discovery: Reihenfolge, Allowlist, `extraApps`, Pfadfilter, Zen-Fallbacks
- Launch-Command je Zieltyp, inklusive Zen-Kaltstart

Die UI wird manuell getestet.
