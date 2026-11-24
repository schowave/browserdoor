// English and German according to the Windows display language (SPEC 2), key = English text,
// as in Resources/Localization on macOS.
const de: Record<string, string> = {
  "Copy URL": "URL kopieren",
  "Copied": "Kopiert",
  "No visible targets": "Keine sichtbaren Ziele",
  "Settings…": "Einstellungen…",
  "{n} links": "{n} Links",
  "The configuration file can't be read; defaults are in use.":
    "Die Konfigurationsdatei ist nicht lesbar; es gelten die Standardwerte.",
  "General": "Allgemein",
  "Targets": "Ziele",
  "Advanced": "Erweitert",
  "Default browser": "Standardbrowser",
  "Browserdoor is your default browser.": "Browserdoor ist dein Standardbrowser.",
  "Browserdoor is not your default browser.": "Browserdoor ist nicht dein Standardbrowser.",
  "Make Default Browser…": "Als Standardbrowser festlegen…",
  "Windows asks you to choose Browserdoor in Settings › Apps › Default apps.":
    "Windows lässt dich Browserdoor unter Einstellungen › Apps › Standard-Apps auswählen.",
  "Start at login": "Beim Anmelden starten",
  "Show in notification area": "Im Infobereich anzeigen",
  "Without the icon, start Browserdoor again to open the settings.":
    "Ohne Symbol öffnet ein erneuter Start von Browserdoor die Einstellungen.",
  "Updates": "Updates",
  "Check for updates automatically": "Automatisch nach Updates suchen",
  "Check Now": "Jetzt suchen",
  "Checking…": "Suche…",
  "Browserdoor {v} is up to date.": "Browserdoor {v} ist aktuell.",
  "Browserdoor {v} is available.": "Browserdoor {v} ist verfügbar.",
  "Update…": "Aktualisieren…",
  "Release notes": "Versionshinweise",
  "Version {v}": "Version {v}",
  "Show": "Zeigen",
  "Name": "Name",
  "Key": "Taste",
  "Default": "Standard",
  "Press a key": "Taste drücken",
  "Add App…": "App hinzufügen…",
  "Remove": "Entfernen",
  "Remove App": "App entfernen",
  "Rename": "Umbenennen",
  "Make Default Target": "Als Standardziel festlegen",
  "Remove as Default Target": "Nicht mehr Standardziel",
  "Hide in Picker": "Im Picker ausblenden",
  "Show in Picker": "Im Picker zeigen",
  "Added apps that aren't listed:": "Hinzugefügte Apps, die nicht in der Liste stehen:",
  "{key} moved here from {name}.": "{key} ist von {name} hierher gewandert.",
  "Drag to sort. Esc cancels a key, Delete removes it.":
    "Ziehen zum Sortieren. Esc bricht die Tasteneingabe ab, Entf entfernt die Taste.",
  "Zen profile": "Zen-Profil",
  "Zen's default profile": "Zens Standardprofil",
  "Choose Folder…": "Ordner wählen…",
  "Use Default": "Standard verwenden",
  "Configuration file": "Konfigurationsdatei",
  "Show in Explorer": "Im Explorer zeigen",
  "Default target": "Standardziel",
  "Hidden": "Ausgeblendet",
};

const german = (navigator.language || "en").toLowerCase().startsWith("de");

export function t(key: string, args: Record<string, string | number> = {}): string {
  let s = (german && de[key]) || key;
  for (const [k, v] of Object.entries(args)) s = s.replaceAll(`{${k}}`, String(v));
  return s;
}

export const lang = german ? "de" : "en";
