# The prompt

Clone this repo and open the folder in Claude Code (or another coding
assistant with shell access) on the Mac you'll build from, then paste the
block below, filling in the blanks. Read `AGENTS.md` first yourself if
you're not pasting this into an agent — it has the same information in
reference form.

This has been built and verified on exactly one setup: a jailbroken
(checkra1n) iPad mini 2 on iOS 12.5.7, installed via AppSync Unified +
ldid fakesigning, no Apple Developer account. If your device differs, say so
up front — the agent should adapt rather than assume.

---

I want to build and install the HA Kiosk app on my iPad from this repo.

My setup:
- iPad model and iOS version: <MODEL + iOS VERSION HERE>
- Is the iPad jailbroken already (checkra1n/unc0ver/etc.), with Cydia and
  AppSync Unified installed? <YES/NO — if unsure, check Cydia's installed
  tweaks list before assuming>
- Home Assistant server URL (leave blank to enter it on first launch via the
  in-app dialog instead): <HA URL HERE, e.g. http://192.168.1.50:8123>
- Do I have a paid Apple Developer Program membership? <YES/NO — changes the
  signing path, see AGENTS.md>

Work on the real device, step by step, and verify each stage with real
command output pulled from the Mac and the iPad — don't report success from
the build log alone. Ask me before anything that depends on my preferences
(e.g. Guided Access passcode, whether to add jailbreak kiosk tweaks beyond
Guided Access).

Build
- Read `AGENTS.md` first — it documents the two-Xcode setup this repo
  needs (recent Xcode can't target iOS 12; `/Applications/Xcode_14.app`'s
  CLI tools can) and the exact failure modes already ruled out. Don't
  rediscover them from scratch.
- Confirm `/Applications/Xcode_14.app` (or an equivalent Xcode whose SDK
  still permits the deployment target in `project.yml`) exists before
  starting. If it doesn't, tell me what Xcode version to install and why
  (deployment target range `xcodebuild -showsdks` reports, vs. what's in
  `project.yml`) rather than silently raising the deployment target.
- Run `./build_ipa.sh` with that Xcode active via `xcode-select`. It
  generates the Xcode project from `project.yml`, builds unsigned, fakesigns
  with `ldid` (main binary + every embedded Swift dylib), and packages
  `HAKiosk.ipa`. If it fails, read the actual error — don't assume it's the
  deployment-target issue again without checking.

Install
- Confirm the iPad is visible via `idevice_id -l` before attempting install.
  Don't reach for `xcrun devicectl` for this device — it speaks a protocol
  iOS 12 doesn't support and will misreport the device as barely-visible.
- If the iPad isn't jailbroken / has no AppSync Unified: stop and tell me
  which signing path we need instead (see AGENTS.md's "if the target device
  is NOT jailbroken" section) rather than attempting an install that will
  fail with ApplicationVerificationFailed.
- Install with `ideviceinstaller install HAKiosk.ipa -w`, uninstalling any
  previous version first. If you hit `ApplicationVerificationFailed ...
  missing the application-identifier entitlement`, that means fakesigning
  didn't happen or didn't cover every binary — check `build_ipa.sh` actually
  ran ldid on both the main executable and `Frameworks/*.dylib`, don't just
  retry the same install.
- Verify with real device data, not just "Install: Complete" in the log:
  pull crash reports (`idevicecrashreport`) and, if behavior looks wrong,
  live syslog (`idevicesyslog`) while reproducing on-device. Both commands
  are in AGENTS.md.

Configure
- First launch should show a URL entry dialog (presented from
  `viewDidAppear`, not `viewDidLoad` — if you ever see a blank white screen
  with no dialog after a fresh install, that regression is back; check
  where the alert is presented before anything else).
- If I gave you an HA URL above, you can also set it directly via
  `UserDefaults` key `ha_server_url` to skip the manual dialog — but tell me
  you did this rather than silently relying on it.

Kiosk lockdown
- Ask me whether I want plain Guided Access (manual, built into iOS,
  described in README.md) or jailbreak-based kiosk tweaks (auto-launch on
  boot, system-wide gesture lockout — more robust, but not implemented yet
  as of this writing, needs researching current compatible tweaks for this
  iOS version). Don't pick for me.

When you're done, tell me plainly what you verified on the real device
(install succeeded, app launched, dashboard loaded with my HA URL or showed
the config dialog) versus what you couldn't test (e.g. no HA server was
reachable this session) — don't blur the two.
