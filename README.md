# HA Kiosk

Vollbild-iPad-App (Swift/UIKit, `WKWebView`) für ein Home Assistant Dashboard
im Kiosk-Modus. Deployment Target: iOS 12.0, verifiziert auf einem
**iPad mini 2 (iPad4,4) mit iOS 12.5.7**.

## Quick Start (mit Claude Code o.ä.)

| Voraussetzung | Status |
|---|---|
| **Mac mit Xcode 14.3.1** unter `/Applications/Xcode_14.app` (für den iOS-12-Build — das moderne Standard-Xcode kann das nicht mehr) | siehe [AGENTS.md](AGENTS.md) |
| **iPad, gejailbreakt** (z. B. mit checkra1n), mit **Cydia** + **AppSync Unified** | siehe unten |

1. Repo klonen, Ordner in Claude Code (oder einem anderen Coding-Agent mit
   Shell-Zugriff) öffnen.
2. [`PROMPT.md`](PROMPT.md) einfügen, Platzhalter ausfüllen (iPad-Modell,
   HA-Server-URL, ob bereits gejailbreakt).
3. Der Agent baut (`build_ipa.sh`), installiert (`ideviceinstaller`) und
   verifiziert live auf dem Gerät.

Ohne Agent: Die Befehle aus `build_ipa.sh` und die Install-Schritte unten
funktionieren genauso manuell im Terminal.

## Warum Jailbreak + AppSync Unified (und nicht Sideloadly/App Store)?

Kurzfassung aus echten Tests auf iOS 12.5.7: **Sideloadly** und **Apple
Configurator 2** scheiterten beide mit `ApplicationVerificationFailed` bzw.
„kann nicht installiert werden" — die eigentliche Ursache war ein fehlendes
`application-identifier`-Entitlement, nicht die Tools selbst. Mit einem
jailbroken iPad + **AppSync Unified** (patcht `installd`, akzeptiert
ungültige Signaturen) + **`ldid`-Fakesigning** (liefert das fehlende
Entitlement nach) funktioniert die Installation zuverlässig, ganz ohne
Apple-Entwicklerkonto und ohne die sonst übliche 7-Tage-Ablaufgrenze freier
Apple-IDs. Details und alle Sackgassen: [AGENTS.md](AGENTS.md).

**Falls dein iPad nicht gejailbreakt ist**, geht es auch mit echter
Apple-Signierung — dafür brauchst du eine Xcode-GUI, die sowohl öffnet als
auch iOS 12 als Target erlaubt, und akzeptierst entweder die 7-Tage-Grenze
(kostenlose Apple-ID) oder zahlst für das Apple Developer Program
(99 $/Jahr, Profile ~1 Jahr gültig, dann geht auch Sideloadly normal).

## Build auf deinem Mac

1. Xcode 14.3.1 installieren (Download über
   https://developer.apple.com/download/all/, kostenlose Apple-ID genügt).
   Falls die GUI sich auf deinem macOS nicht öffnen lässt: nicht weiter
   versuchen, das Kommandozeilen-`xcodebuild` reicht völlig.
2. `brew install xcodegen ldid ideviceinstaller`
3. Xcode 14 aktivieren: `sudo xcode-select -s /Applications/Xcode_14.app`
4. Bauen:
   ```bash
   ./build_ipa.sh
   ```
   Baut unsigniert für `iphoneos`, signiert dann mit `ldid` (Hauptbinary +
   alle eingebetteten Swift-Dylibs — notwendig für AppSync Unified, siehe
   AGENTS.md) und packt alles zu `HAKiosk.ipa`.

## Installation (Jailbreak + AppSync Unified)

1. Auf dem iPad: Cydia → Quellen hinzufügen (aktuelle URL für AppSync
   Unified passend zu deiner iOS-Version z. B. über ios.cfw.guide finden,
   ändert sich gelegentlich) → **AppSync Unified** installieren → Respring.
2. Am Mac:
   ```bash
   idevice_id -l                                   # Gerät erkannt?
   ideviceinstaller uninstall com.hakiosk.app || true
   ideviceinstaller install HAKiosk.ipa -w
   ```
3. Bei Problemen: Crash-Reports/Live-Log ziehen (Befehle in AGENTS.md), statt
   zu raten.

## Home-Assistant-URL konfigurieren

- **Erster Start:** Die App fragt automatisch nach der Server-Adresse
  (z. B. `http://192.168.1.50:8123`).
- **Später ändern:** 3 Sekunden lang in die **obere linke Bildschirmecke**
  drücken (unsichtbarer Hotspot, 60×60 Punkte) → Eingabefeld öffnet sich
  erneut, vorausgefüllt mit der aktuellen URL.
- Ohne `http://`/`https://` eingegebene Adressen werden automatisch mit
  `http://` ergänzt (für lokale HA-Server ohne TLS).
- **Dark Mode / Theme** wird komplett in Home Assistant eingestellt (Profil
  → Theme, oder pro Dashboard im Lovelace-Editor) — die App selbst erzwingt
  kein Theme.
- **Selbstsignierte HTTPS-Zertifikate** werden von `WKWebView` bewusst
  weiterhin abgelehnt (Sicherheits-Best-Practice, kein Bypass eingebaut).
  Entweder plain HTTP im LAN nutzen, ein gültiges Zertifikat (z. B. über
  Nabu Casa / Let's Encrypt) einsetzen, oder das HA-Zertifikat unter
  *Einstellungen → Allgemein → Info → Zertifikatsvertrauenseinstellungen*
  auf dem iPad als vertrauenswürdig markieren.

## Kiosk-Modus aktivieren (Guided Access)

Die App kann Guided Access aus Sicherheitsgründen nicht selbst aktivieren
(kein Drittanbieter-API dafür) — einmalig manuell einrichten:

1. *Einstellungen → Bedienungshilfen → Geführter Zugriff* → einschalten.
2. Optional: *Code-Einstellungen* → eigenen Code vergeben, damit niemand
   den Modus ohne Code verlassen kann.
3. Optional: *Einstellungen → Bedienungshilfen → Bedienungshilfen-Kurzbefehl*
   → „Geführter Zugriff" auswählen, damit 3× Seiten-/Home-Taste direkt
   startet.
4. HA Kiosk App öffnen.
5. 3× Seiten-/Home-Taste drücken → *Optionen* (Kreis unten links) bei Bedarf
   anpassen → **Start**.

Solange Guided Access aktiv ist, blockiert iOS selbst Home-Button/App-
Wechsel/Control Center — das übernimmt kein Code in der App.

Da das iPad ohnehin gejailbreakt ist, sind robustere Alternativen (Auto-Start
beim Boot, systemweite Gesten-Sperre per Tweak) möglich, aber noch nicht
umgesetzt — siehe „Offene Schritte" in SESSION_NOTES.md.

## Was die App technisch tut

- `UIApplication.isIdleTimerDisabled = true` → Display schläft nie ein.
- `UIRequiresFullScreen` + ausgeblendete Statusbar → kein Split
  View/Slide Over, kein Multitasking-Einstieg für andere Apps.
- `WKWebView` lädt die konfigurierte HA-URL; Inline-Medienwiedergabe erlaubt
  (Kameras/Media Player in HA-Dashboards).
- **Auto-Reconnect:**
  - `NWPathMonitor` erkennt Netzwerkwechsel und lädt bei Rückkehr der
    Verbindung sofort neu.
  - Bei fehlgeschlagener Navigation: Retry mit exponentiellem Backoff
    (2 s → max. 30 s).
  - Watchdog-Timer (alle 30 s): zwingt einen Reload, wenn seit über 90 s
    kein erfolgreicher Ladevorgang verzeichnet wurde (fängt stille Hänger
    ab, die keinen Navigationsfehler auslösen).
  - Beim Rückkehren in den Vordergrund (`applicationDidBecomeActive`) und
    bei periodischem Legacy-Background-Fetch (iOS-12-kompatibel, kein
    `BGTaskScheduler`) wird ebenfalls geprüft und ggf. neu geladen.
- **Hinweis zu „Hintergrundbetrieb":** Ein Kiosk-Display muss permanent im
  Vordergrund laufen, um etwas anzuzeigen — „echtes" Hintergrundrendering
  ergibt für eine Bildschirmanzeige keinen Sinn. Die oben genannten
  Mechanismen sorgen dafür, dass die App robust reagiert, sobald sie
  (wieder) aktiv ist, statt dauerhaft unsichtbar im Hintergrund zu rechnen.

## Projektstruktur

```
project.yml                      XcodeGen-Spezifikation (Deployment Target 12.0)
build_ipa.sh                     Build, ldid-Fakesigning & Packaging → HAKiosk.ipa
fakesign-entitlements.plist      application-identifier-Entitlement fürs Fakesigning
AGENTS.md                        Agenten-Referenz: Toolchain-Eigenheiten, bekannte Fehler & Fixes
PROMPT.md                        Einfügen in einen frischen Claude-Code-Lauf, um weiterzumachen
SESSION_NOTES.md                 Chronologischer Log vergangener Sessions
Sources/
  Info.plist                     Kiosk-Keys (Vollbild, ATS, Background Modes, …)
  AppDelegate.swift              App-Lifecycle, Idle-Timer, Background Fetch
  DashboardViewController.swift  WebView, Reconnect-Logik, URL-Konfiguration
  ConnectivityMonitor.swift      NWPathMonitor-Wrapper
Resources/
  LaunchScreen.storyboard
  Assets.xcassets/                Platzhalter-Icon-Set (ohne Bilddateien)
```

## Getestet

- ✅ Build (Xcode 14.3.1, CLI) + Fakesigning + Installation auf echtem
  iPad mini 2 / iOS 12.5.7 (jailbroken, AppSync Unified).
- ✅ App startet, zeigt den URL-Konfigurationsdialog korrekt an.
- ❌ **Noch nicht verifiziert:** Laden eines echten HA-Dashboards (kein HA-
  Server in der letzten Session erreichbar), Verhalten bei echtem
  Verbindungsabbruch, Guided-Access-Einrichtung.
