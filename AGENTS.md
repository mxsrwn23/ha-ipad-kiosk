# Agent guide: HA Kiosk

A Swift/UIKit iPad app that shows a Home Assistant dashboard full-screen in a
`WKWebView`, for an iPad stuck on an old iOS version (built and tested against
an **iPad mini 2 / iPad4,4 on iOS 12.5.7**). This file is what an agent should
read before touching the repo — it's the condensed result of actually
building, signing and installing this on real, old, jailbroken hardware, not
a guess at how it should work in theory. If something here conflicts with
what you observe, trust the device and update this file.

If you are a fresh agent picking this up: the three documents to know about
are this one (how the toolchain and device actually behave), `PROMPT.md`
(paste-in kickoff prompt for a new session), and `SESSION_NOTES.md` (dated
log of what happened in past sessions — read for history, not as instructions).

## What you're working with

- **Mac**: current/default Xcode is very recent and **cannot build for iOS
  12** (minimum supported deployment target is 15.0 — it hard-rejects
  `IPHONEOS_DEPLOYMENT_TARGET` below that at the project level). A second,
  older Xcode (**14.3.1**) is kept at `/Applications/Xcode_14.app`
  specifically to build this target.
- **iPad**: jailbroken with **checkra1n**, has **Cydia** and **AppSync
  Unified** installed. This is what makes installing a non-Apple-signed app
  possible at all without a paid Apple Developer account.
- Deployment target in `project.yml` is `12.0` — do not raise it "to make
  the build easier." That defeats the entire point of this project.

## The two-Xcode dance

Xcode 14's **GUI will not launch** on this Mac's macOS version (blocked by
an OS compatibility check — a "needs the latest version" dialog). Its
**command-line tools work fine**. The default/current Xcode's GUI opens
fine, but can't target iOS 12. So:

```bash
# Building (needs iOS-12-capable toolchain):
sudo xcode-select -s /Applications/Xcode_14.app
./build_ipa.sh

# Installing / device inspection (needs modern CLI tools, e.g. for ideviceinstaller
# to be found on PATH alongside a working xcrun — actually ideviceinstaller itself
# is a separate Homebrew formula and doesn't care about xcode-select, but switch
# back for anything that calls into Xcode's own device tooling):
sudo xcode-select -s /Applications/Xcode.app
```

Do not try to make Xcode 14's GUI open (compatibility-check workarounds like
launching the raw binary directly were tried and did not reliably help) —
the CLI path is the supported route here. Do not try `xcrun devicectl` for
this device either (next section).

## Installing on the device: use libimobiledevice, not devicectl

`xcrun devicectl` targets the modern CoreDevice/RemoteXPC protocol
(iOS 17+). Against this iPad it only resolves an ECID, not a usable
UDID/state, and cannot install anything. Use the classic
**libimobiledevice** tools instead (`brew install ideviceinstaller` pulls in
`idevice_id`, `ideviceinstaller`, `idevicesyslog`, `idevicecrashreport`):

```bash
idevice_id -l                                  # confirm the device is seen
ideviceinstaller uninstall com.hakiosk.app || true
ideviceinstaller install HAKiosk.ipa -w
```

## Code signing: fakesigning is mandatory, not optional

AppSync Unified patches `installd` to accept **invalid** signatures (wrong
team, expired, self-signed) — it does **not** accept a binary with **no**
signature/entitlements at all. A plain `CODE_SIGNING_ALLOWED=NO` build will
install-fail with:

```
ERROR: Install failed. Got error "ApplicationVerificationFailed" with code
0x00000000: Application is missing the application-identifier entitlement.
```

Fix: fakesign with `ldid` (`brew install ldid`) — **the main executable
with an entitlements plist containing `application-identifier`, and every
embedded Swift runtime `.dylib` in `Frameworks/` ad-hoc (no entitlements
needed there, just a valid signature structure)**. `build_ipa.sh` already
does this automatically using `fakesign-entitlements.plist`; if you hand-roll
a build, replicate both steps — signing only the main binary and skipping
the `Frameworks/*.dylib` files leaves `dyld` unable to load them.

If you ever see `ApplicationVerificationFailed` again after a code change,
check first whether `ldid` actually ran (it silently does nothing useful if
it's missing from PATH — `build_ipa.sh` checks for this and exits with a
clear message, don't bypass that check).

## If the target device is NOT jailbroken

Everything above assumes jailbreak + AppSync. Without that, you're back to
real Apple code signing, which means either:
- A free Apple ID: Xcode's automatic signing (GUI-only, so needs a working
  Xcode GUI — use the modern Xcode if its deployment-target floor allows
  your actual target OS, otherwise this whole two-Xcode problem reappears).
  Apps expire after **7 days** and need reinstalling.
- A paid Apple Developer Program membership ($99/yr): proper ad-hoc
  distribution, works with Sideloadly etc., profiles valid ~1 year, no
  jailbreak/AppSync/fakesigning needed at all.

Don't assume jailbreak is available on a new target device — ask.

## Known-bad paths (tried, don't repeat)

- **Sideloadly** on this specific iOS 12 device produced
  `ApplicationVerificationFailed` / `0xe800800d` / "error communicating with
  your device" — root cause was ultimately the missing entitlement (see
  above), not Sideloadly itself, but Sideloadly's own resigning didn't fix
  it either. ldid + ideviceinstaller is the path that actually worked.
- **Apple Configurator 2** installed the icon but the app wouldn't open
  ("kann nicht installiert werden") for the same underlying signing reason.
- Presenting the first-launch URL-entry `UIAlertController` from
  `viewDidLoad()` silently no-ops on a cold launch (view not reliably
  attached to the window yet) — it's presented from `viewDidAppear()`
  instead (see `DashboardViewController.swift`). If you add other
  first-run UI, present it from `viewDidAppear`, not `viewDidLoad`.

## Build → install → verify loop

```bash
sudo xcode-select -s /Applications/Xcode_14.app
./build_ipa.sh
sudo xcode-select -s /Applications/Xcode.app   # optional, only if you need devicectl/other modern tooling next

ideviceinstaller uninstall com.hakiosk.app || true
ideviceinstaller install HAKiosk.ipa -w
```

To debug a launch that doesn't behave as expected, don't guess — pull real
data from the device:

```bash
# Crash reports (empty for com.hakiosk.app strongly implies a logic bug,
# not a crash — e.g. the viewDidLoad/viewDidAppear issue above):
mkdir -p /tmp/hakiosk_crashes && idevicecrashreport -e -k /tmp/hakiosk_crashes

# Live syslog while reproducing on-device:
idevicesyslog > /tmp/hakiosk_syslog.txt &
# ... reproduce on the iPad ...
kill %1
grep -i hakiosk /tmp/hakiosk_syslog.txt
```

## Repo map

```
project.yml                      XcodeGen spec (source of truth; .xcodeproj is generated, gitignored)
build_ipa.sh                     xcodegen generate → xcodebuild (unsigned) → ldid fakesign → zip → HAKiosk.ipa
fakesign-entitlements.plist      application-identifier entitlement used for fakesigning
Sources/
  Info.plist                     Kiosk keys: full screen, hidden status bar, ATS exception, background fetch
  AppDelegate.swift              Idle timer disabled, legacy background fetch (no BGTaskScheduler — iOS 12)
  DashboardViewController.swift  WKWebView, reconnect/backoff/watchdog, hidden long-press URL config
  ConnectivityMonitor.swift      NWPathMonitor wrapper
Resources/                       LaunchScreen.storyboard, Assets.xcassets (icon placeholders, no real images)
README.md                        Human-facing setup/sideload/Guided-Access instructions
PROMPT.md                        Paste this into a fresh Claude Code session to pick up where you left off
SESSION_NOTES.md                 Dated narrative log of past sessions — history, not instructions
```

## App behavior worth knowing before changing code

- Bundle ID `com.hakiosk.app`. HA server URL lives in `UserDefaults`
  key `ha_server_url`, editable in-app via a 3-second long-press in the
  top-left 60×60pt corner (there's no nav chrome in kiosk mode to put a
  settings button on).
- Reconnect strategy: `NWPathMonitor` reload-on-reachable, navigation-failure
  retry with exponential backoff (2s → 30s cap), a 90s watchdog that forces
  a reload if nothing has loaded successfully in that window, plus a reload
  check on `applicationDidBecomeActive` and on legacy background-fetch wakes.
- No code in this app enables Guided Access — Apple doesn't expose that to
  third-party apps. It's a manual one-time device setting (see README).
- Dark mode / theming is entirely controlled from the Home Assistant side
  (Profile → Theme, or per-dashboard in the Lovelace editor) — the app
  imposes no theme of its own beyond a black loading backdrop.
