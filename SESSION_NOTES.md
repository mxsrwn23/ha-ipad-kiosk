# HA Kiosk — Stand & Notizen aus dieser Session

Datum: 2026-11-02

## Status: Funktioniert

Die App ist gebaut, signiert, auf dem iPad installiert, startet und zeigt den
URL-Eingabedialog korrekt an. Home Assistant selbst war in dieser Session
nicht erreichbar, daher noch nicht live mit echtem Dashboard getestet.

## Zielgerät

- **iPad4,4** (iPad mini 2) — eines der Modelle, die bei iOS 12.5.7 gedeckelt sind
- iOS 12.5.7, **gejailbreakt mit checkra1n**, Cydia installiert
- Tweak **AppSync Unified** installiert (patcht `installd`, akzeptiert ungültige/fehlende Signaturen)

## Wichtigste Erkenntnisse / Stolpersteine

1. **Das Standard-Xcode auf diesem Mac (macOS „Golden Gate") kann kein iOS 12
   als Deployment Target mehr bauen** (Minimum liegt bei 15.0). Dafür wurde
   zusätzlich **Xcode 14.3.1** installiert unter `/Applications/Xcode_14.app`.
2. **Die GUI von Xcode 14 lässt sich auf macOS Golden Gate nicht öffnen**
   („nicht kompatibel"-Dialog). Die Kommandozeilen-Tools (`xcodebuild`)
   funktionieren aber einwandfrei, sobald sie per `xcode-select` aktiviert sind.
   → Für Builds **immer vorher umschalten**:
   ```bash
   sudo xcode-select -s /Applications/Xcode_14.app
   ```
   Für alles andere (z.B. `xcrun devicectl`) wieder zurück:
   ```bash
   sudo xcode-select -s /Applications/Xcode.app
   ```
3. **`xcrun devicectl` funktioniert nicht zuverlässig mit iOS-12-Geräten**
   (nutzt das neue CoreDevice/RemoteXPC-Protokoll, das iOS 12 nicht spricht;
   zeigt nur eine ECID statt vollständiger Geräteinfo). Für iOS 12 stattdessen
   die klassischen **libimobiledevice**-Tools nutzen (`brew install
   ideviceinstaller`): `idevice_id`, `ideviceinstaller`, `idevicesyslog`,
   `idevicecrashreport`.
4. **Reine unsignierte `.ipa` reicht nicht, auch nicht mit AppSync Unified.**
   AppSync akzeptiert zwar *ungültige* Signaturen, verlangt aber trotzdem,
   dass überhaupt eine Signatur mit `application-identifier`-Entitlement
   vorhanden ist. Fehlerbild ohne das: `ApplicationVerificationFailed ...
   missing the application-identifier entitlement`.
   → Lösung: **Fakesigning mit `ldid`** (`brew install ldid`), und zwar für
   **alle** Mach-O-Binaries im Bundle — die Hauptbinary (mit Entitlements-Plist)
   **und** alle eingebetteten Swift-Runtime-`.dylib`s in `Frameworks/`
   (ad-hoc, ohne Entitlements). Ist jetzt automatisiert in `build_ipa.sh`.
5. **Erster weißer Bildschirm nach Install** war ein Bug im Code: Der
   URL-Eingabedialog wurde in `viewDidLoad()` präsentiert — beim Kaltstart ist
   die View da aber noch nicht zuverlässig im Fenster verankert, iOS hat die
   Präsentation stillschweigend verworfen. Fix: Dialog wird jetzt in
   `viewDidAppear()` gezeigt (siehe `DashboardViewController.swift`).
6. **Kein Apple-Developer-Account nötig** dank Jailbreak + AppSync + Fakesigning
   — damit entfällt auch die sonst übliche 7-Tage-Ablaufgrenze freier
   Apple-IDs. Einmal installiert, bleibt die App installiert, bis du sie
   manuell neu baust/installierst (z.B. für Code-Änderungen).

## Projektstruktur

```
~/Documents/projekte/ha-ipad-kiosk/
  project.yml                      XcodeGen-Spec (Deployment Target iOS 12.0)
  build_ipa.sh                     Kompletter Build: xcodegen → xcodebuild →
                                    ldid-Fakesigning → Payload/ → HAKiosk.ipa
  fakesign-entitlements.plist      Entitlements fürs Fakesigning (application-identifier)
  HAKiosk.ipa                      Aktuell gebaute, installierte Version
  Sources/
    Info.plist                     Kiosk-Keys (Vollbild, Statusbar aus, ATS, Background Fetch)
    AppDelegate.swift               App-Lifecycle, Idle-Timer deaktiviert, Background Fetch
    DashboardViewController.swift   WKWebView, Reconnect-Logik, URL-Konfiguration,
                                     Dialog-Fix in viewDidAppear
    ConnectivityMonitor.swift       NWPathMonitor-Wrapper für Auto-Reconnect
  Resources/
    LaunchScreen.storyboard
    Assets.xcassets/                Icon-Platzhalter (keine echten Bilder)
  README.md                        Ausführliche Anleitung (Build, Sideload, Guided Access)
```

## Wie man die App nach Code-Änderungen neu baut & installiert

```bash
cd ~/Documents/projekte/ha-ipad-kiosk

# 1. Richtiges Xcode aktivieren (iOS-12-fähig)
sudo xcode-select -s /Applications/Xcode_14.app

# 2. Bauen + Fakesignen + Paketieren (alles automatisiert)
./build_ipa.sh

# 3. Alte Version entfernen + neu installieren
ideviceinstaller uninstall com.hakiosk.app || true
ideviceinstaller install HAKiosk.ipa -w

# 4. Optional zurückschalten für andere Aufgaben (z.B. devicectl)
sudo xcode-select -s /Applications/Xcode.app
```

## Debugging-Befehle, die geholfen haben

```bash
# Verbundenes Gerät prüfen
idevice_id -l

# Crash-Reports vom Gerät holen (für com.hakiosk.app filtern)
mkdir -p /tmp/hakiosk_crashes
idevicecrashreport -e -k /tmp/hakiosk_crashes

# Live-Systemlog mitschneiden (während die App auf dem iPad neu gestartet wird)
idevicesyslog > /tmp/hakiosk_syslog.txt &
# ... App auf dem iPad neu starten ...
kill %1
grep -i "hakiosk" /tmp/hakiosk_syslog.txt
```

## Offene / nächste Schritte

- [ ] **Mit echtem Home-Assistant-Server testen** (sobald HA wieder läuft):
      URL im Dialog eintragen (`http://<ha-ip>:8123`), prüfen ob Dashboard lädt.
- [ ] **Dark Mode / Theme**: wird komplett in Home Assistant selbst eingestellt
      (Profil-Menü → Theme, oder pro Dashboard im Lovelace-Editor), nicht in der App.
- [ ] **Kiosk-Lockdown einrichten** — zwei Optionen, noch nicht umgesetzt:
      1. **Guided Access** (Bordmittel): Einstellungen → Bedienungshilfen →
         Geführter Zugriff aktivieren, dann in der App 3× Seitentaste.
      2. **Jailbreak-Tweaks** (robuster, da Jailbreak eh vorhanden): Auto-Start
         beim Boot, SpringBoard-Gesten systemweit deaktivieren. Noch nicht
         umgesetzt — bei Bedarf in neuer Session vertiefen.
- [ ] URL später ändern: 3 Sekunden Long-Press oben links auf dem Bildschirm
      öffnet den Konfigurationsdialog erneut.
- [ ] Reconnect-/Watchdog-Verhalten unter echten Netzwerkausfällen testen
      (bisher nur Code-seitig implementiert, nicht live verifiziert).

## Technische Details der App (zur Erinnerung)

- Swift/UIKit, kein SwiftUI (iOS 12 kompatibel), `WKWebView` als Dashboard-Anzeige
- `UIApplication.isIdleTimerDisabled = true` → Bildschirm schläft nie ein
- `UIRequiresFullScreen` + versteckte Statusbar → kein Split View/Slide Over
- Auto-Reconnect: `NWPathMonitor` + Retry mit exponentiellem Backoff (2s–30s)
  + 90s-Watchdog-Timer + Reload bei App-Rückkehr in den Vordergrund
- Bundle-ID: `com.hakiosk.app`
- HA-Server-URL wird in `UserDefaults` gespeichert (Key `ha_server_url`)
