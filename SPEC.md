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
- Build mit Swift Package Manager. `mise run app` baut daraus `Doorman.app` (siehe 9). Gebaut wird mit Xcode 16 (Swift 6).
- Die App läuft dauerhaft im Hintergrund:
  - `LSUIElement`, also kein Dock-Icon
  - Menüleisten-Icon (eine angelehnte Tür als Template-Bild, `NSStatusItem`; das Menü wird bei jedem Öffnen neu aufgebaut, damit die Statuszeilen aktuell sind)
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

URLs landen als Kommandozeilen-Argumente bei den Browsern. Deshalb lässt Doorman nur `http`, `https` und `file` durch (`URLPolicy`); alles andere, etwa `--remote-debugging-port=…` oder `javascript:`, wird verworfen. Aus `.webloc`-Dateien kommen nur `http` und `https`, damit eine heruntergeladene Datei keine lokale Datei öffnen kann. Die Prüfung greift beim Empfang und noch einmal beim Bauen der Launch-Kommandos.

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
- Die Datei wird normalerweise über das Einstellungsfenster gepflegt (siehe 6). Es schreibt sie bei jeder Änderung neu (sortierte Schlüssel, stabile Diffs); Einstellungen von Zielen, die gerade nicht erkannt werden, bleiben erhalten.

## 6. Menüleiste, Einstellungen, Updates

**Menüleisten-Menü** (wird bei jedem Öffnen neu aufgebaut, nur billige Abfragen):
- „Auf Doorman X aktualisieren…“, falls ein Update bekannt ist
- Hinweis „Doorman ist nicht Standardbrowser“ plus „Als Standardbrowser festlegen“, nur wenn nötig
- „Einstellungen…“ (⌘,), „Nach Updates suchen…“, Versionszeile, „Doorman beenden“

**Einstellungsfenster** (SwiftUI in einem `NSWindow`; öffnet sich auch, wenn Doorman bei laufender App erneut gestartet wird, z. B. per `doorman`):
- *Allgemein:* Standardbrowser-Status und -Button, „Beim Anmelden starten“ (LaunchAgent; der Haken zeigt nur, ob er existiert, nicht ob er in den Systemeinstellungen blockiert ist), Updates.
- *Ziele:* alle erkannten Ziele mit Icon, per Ziehen sortierbar, ein-/ausblendbar, umbenennbar, eigene Taste (die tatsächlich vergebene Taste steht grau als Platzhalter), Stern für das Standardziel. **+** fügt Apps über einen Auswahldialog hinzu (`extraApps`; sie erscheinen auch ohne https-Registrierung), **−** entfernt eine solche App.
- *Erweitert:* weitere Apps, Zen-Profil, Konfigurationsdatei im Finder zeigen.
- Ein unsichtbares Hauptmenü liefert ⌘C/⌘V/⌘A, ⌘W und ⌘, für das Fenster.

**Updates:** `HEAD https://github.com/schowave/doorman/releases/latest`; die Weiterleitung auf `…/releases/tag/<tag>` nennt das neueste Release (ohne Entwürfe und Pre-Releases). Die API (`api.github.com`) wird bewusst nicht genutzt, weil sie ohne Token nur 60 Anfragen pro Stunde und IP erlaubt. Geprüft wird automatisch höchstens einmal pro 24 h (abschaltbar) und auf Anfrage. Ist die Version neuer (`AppVersion`-Vergleich; Dev-Builds `0.0.0` nie), erscheint ein Dialog. „Im Terminal aktualisieren“ öffnet ein `.command`-Skript: `brew update && brew upgrade doorman`, altes Doorman beenden, neues per `doorman` starten. Ohne Homebrew-Installation gibt es stattdessen die Release-Seite. „Später“ unterdrückt die automatische Meldung für diese Version. Das ist der einzige Netzwerkzugriff von Doorman.

**Sprache:** Englisch und Deutsch nach Systemsprache (`Resources/Localization/*.lproj/Localizable.strings`, Schlüssel = englischer Text). `mise run check-strings` prüft, dass jeder Schlüssel übersetzt ist.

## 7. Erster Start

Beim ersten Start passiert Folgendes:
1. Die App registriert sich bei LaunchServices (`LSRegisterURL`).
2. Ist Doorman nicht Standardbrowser, erscheint ein Dialog. Bei Zustimmung ruft die App `NSWorkspace.setDefaultApplication(at:toOpenURLsWithScheme:)` für http auf. macOS zeigt dann den eigenen Bestätigungsdialog.
3. Der Autostart wird aktiviert (LaunchAgent, siehe unten).

**Stabil über `brew upgrade`:** Homebrew installiert in ein versioniertes Cellar-Verzeichnis, das `brew cleanup` nach einem Upgrade löscht. Deshalb:
- Läuft Doorman aus einem Cellar, legt es bei jedem Start `~/Applications/Doorman.app` als Symlink auf `<brew prefix>/opt/doorman/Doorman.app` an (bzw. korrigiert einen veralteten eigenen Symlink). Eine echte App an dieser Stelle bleibt unangetastet.
- Der Autostart ist ein LaunchAgent `~/Library/LaunchAgents/io.github.schowave.doorman.plist`, der `open -a ~/Applications/Doorman.app` ausführt. `SMAppService.mainApp` würde sich den versionierten Pfad merken; ein solches Login-Item aus früheren Builds wird beim Start entfernt und ersetzt.
- Der Standardbrowser hängt an der Bundle-ID und ist damit pfadunabhängig; jeder Start registriert die laufende Kopie neu (`LSRegisterURL`).
- Nach einem Update trägt Doorman den Pfad der Version, aus der es zuletzt lief, aus LaunchServices aus (`lsregister -u`), wenn er nicht mehr existiert (`brew cleanup` hat ihn gelöscht). Existiert er noch (z. B. ein Dev-Build), bleibt er.

## 8. Architektur

Begriffe: siehe [GLOSSARY.md](GLOSSARY.md). Die Logik steckt in wenigen tiefen Modulen in `DoormanCore`, getestet über ihr Interface; die App (`Sources/Doorman`) rendert und stellt die Adapter für die Seams.

| Modul (DoormanCore) | Besitzt | Seam / Adapter |
|---|---|---|
| `TargetCatalog` | Config-Datei (inkl. unlesbar), Zen-Profilpfad, Discovery, Picker-Einträge, Edit-Zeilen, effektive Tasten, Speichern | `BrowserEnvironment`: `SystemEnvironment` · `FakeEnvironment` |
| `Discovery` | Ziele finden (Allowlist, Pfadfilter, Zen-Versionsprüfung, Chromium-Profile, Extra-Apps) | `BrowserEnvironment` |
| `PickerSession` | Links, Einträge, Auswahl; Eingabe → Effekte (close/open/copy) | in-process |
| `LinkOpener` | Eingehende Items → erlaubte Links; Link + Ziel → Start inkl. Zen läuft/kalt und Aktivierung | `LaunchPort`: `SystemLaunchPort` · `RecordingPort` |
| `Installation` | Homebrew-Fakten, stabiler Link, LaunchAgent, Migration von SMAppService | echtes Dateisystem (Temp-Home in Tests); `LegacyLoginItem`: `SMAppServiceLoginItem` · Fake |
| `UpdatePolicy` | Wann prüfen, was melden, Später, Fehler | `ReleaseSource`: `GitHubReleaseSource` · Stub; `UpdatePreferences`: `UserDefaultsUpdatePreferences` · In-Memory |
| `ZenIconCache` | Icon-Cache je Zen-Version, gemerkte Fehlschläge | Extraktor: `unzip` · Fake |
| Parser | `MozLz4`, `ZenSpaces`, `ZenProfile`, `ChromiumProfiles`, `WeblocParser` | in-process |

App: `AppDelegate` (Menüleiste, Onboarding), `PickerController` (rendert die Session, führt Effekte aus), `Settings` (Fenster über `CatalogState`), `UpdateChecker` (Dialoge, Upgrade im Terminal), `IconProvider` (NSImages, startet die Icon-Extraktion), Adapter (`SystemEnvironment`, `SystemLaunchPort`, `SMAppServiceLoginItem`).

## 9. Build, Distribution, CI

- **Tooling:** mise. `mise.toml` pinnt `actionlint`, `shellcheck` und `swiftformat`. Swift selbst kommt aus Xcode bzw. den Command Line Tools, weil Doorman das macOS-SDK braucht.
- **Tasks:** Sie liegen in `.mise/tasks/` als ausführbare Shell-Skripte mit `#MISE`-Kopfzeilen und ersetzen das frühere Makefile: `test`, `app`, `install`, `run`, `lint`, `format`, `render-formula`, `check-formula`, `next-patch-version`, `app-changed-since-release`, `test-scripts`, `bottle`, `ci`, `clean`. Gemeinsame Einstellungen kommen aus `_lib.sh`. Die Skripte laufen auch ohne mise.
- `mise run app` erzeugt `build/Doorman.app`. Info.plist, App-Icon (`Resources/Icon/AppIcon.icns`) und Menüleisten-Glyph (`MenuBarIcon.svg`, Template-Bild) kommen aus `Resources/`. Das `.icns` wird mit `mise run icons` aus `AppIcon.svg` erzeugt und eingecheckt. Signiert wird ad hoc. Die Version kommt aus `VERSION` oder dem letzten `v*`-Tag.
- **Homebrew:**
  - Die Formula `doorman` liegt im Tap `schowave/homebrew-tap` unter `Formula/`.
  - Nutzer ab macOS 15 bekommen eine Bottle (Apple Silicon und Intel) und brauchen dann kein Xcode. Ohne passende Bottle baut die Formula aus dem Release-Tarball (`depends_on xcode: 16` zum Bauen) und ruft `.mise/tasks/install` direkt auf, also ohne mise, mit `PREFIX`, `VERSION`, `SWIFT_BUILD_FLAGS=--disable-sandbox` und `BIN_APP_PATH` (der stabile `opt`-Pfad für `bin/doorman`, das `open -a` nutzt).
  - Die Vorlage `packaging/homebrew/doorman.rb` nutzt `@URL@`, `@VERSION@` und `@SHA256@`. `render-formula` setzt die Werte ein, `check-formula` prüft das Ergebnis. Den `bottle do`-Block schreibt erst der Release-Workflow hinein. Der Formula-Test prüft auch die Code-Signatur der App, damit eine Bottle sie beim Verschieben nicht beschädigt.
- **CI** (`ci.yml`, macOS-Runner):
  - Job `test`: `mise run ci` mit lint, Unit-Tests, Tests der Release-Skripte, App-Bundle und Formula-Check.
  - Job `formula`: rendert die Formula für einen lokalen Tarball, baut sie mit `.mise/tasks/bottle` als Bottle, führt `brew audit --strict` aus, installiert die Bottle neu (prüft `poured_from_bottle`) und führt `brew test` aus, also den Weg, den Nutzer gehen.
- **Release** (`release.yml`): läuft bei einem Tag `v*` oder wenn ein anderer Workflow es aufruft (`workflow_call`). Ablauf: testen, App bauen, GitHub-Release anlegen (falls noch keines existiert). Danach bauen `macos-15` (arm64) und `macos-15-intel` je eine Bottle (für macOS 14 gibt es keine Runner mehr) und hängen sie ans Release. Zuletzt kommt die Formula mit `bottle do`-Block (`brew bottle --merge`, vorher `brew trust`) in den Tap. Schlägt eine Bottle fehl, wird der Tap trotzdem aktualisiert, nur mit weniger Bottles. Schlagen alle fehl, bleibt der Tap unverändert. Neben jeder Bottle liegt ihr JSON im Release. Ein erneuter Lauf verwendet vorhandene Bottles wieder, damit die sha256-Werte im Tap gültig bleiben. Dafür braucht es das Secret `TAP_GITHUB_TOKEN`. Der Workflow lässt sich erneut ausführen.
- **Renovate** (GitHub App, `renovate.json`):
  - Einmal pro Woche (Montag vor 6 Uhr), je ein PR für GitHub Actions (auf Digests gepinnt) und einer für die mise-Tools. Getrennt, damit eine neue Lint-Regel nicht auch die Action-Updates blockiert.
  - Updates werden erst übernommen, wenn sie 7 Tage alt sind (`minimumReleaseAge`).
  - Majors erstellt Renovate erst nach Freigabe im Dependency Dashboard.
  - Renovate merged die PRs selbst, sobald die CI grün ist.
- **Auto-Release** (`auto-release.yml`):
  - Ein Merge von `renovate[bot]` auf `main` legt den nächsten Patch-Tag an (`next-patch-version`), aber nur, wenn sich seit dem letzten Tag die App geändert hat (`Sources/`, `Resources/`, `Package.swift`/`.resolved`; `app-changed-since-release`). Updates, die nur CI oder Lint-Werkzeuge betreffen, ergeben kein Release.
  - Der Tag entsteht per API; trägt `HEAD` schon einen Tag, passiert nichts. Eine `concurrency`-Gruppe verhindert parallele Releases.
  - Mit dem `GITHUB_TOKEN` angelegte Tags starten selbst keine Workflows, deshalb ruft der Job `release.yml` direkt auf.
  - Ohne vorhandenen `v*`-Tag passiert nichts; das erste Release entsteht von Hand.

## 10. Tests

Folgende Teile des Cores sind abgedeckt:
- MozLz4-Decoder, gegen Fixtures (komprimierte Datei → erwartetes JSON)
- Parser für `zen-sessions`, `profiles.ini` und `Local State`
- Webloc-Parser
- Ordnen, Ausblenden, Labels und Hotkey-Vergabe der Konfiguration
- Discovery: Reihenfolge, Allowlist, `extraApps`, Pfadfilter, Zen-Fallbacks
- Launch-Command je Zieltyp, inklusive Zen-Kaltstart
- Tastenbelegung im Panel (`PickerKeys`), inklusive Feststelltaste
- Entscheidung über den Symlink in `~/Applications` und das Neuschreiben des LaunchAgents
- Release-Skripte (`test-scripts`): nächster Patch-Tag, App-Änderung seit dem letzten Release, URL-Argument von `render-formula`

Die UI wird manuell getestet.
