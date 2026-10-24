# TextSnap product contract

Read this before changing, reviewing, or troubleshooting capture, hotkey, OCR, clipboard, menu, Settings, app-icon artwork, or "Check for Updates".

## One sentence

Press a shortcut, drag a region on screen, the text in it lands in the clipboard.

## Flow

1. User presses the global shortcut (factory: Command Shift 2) or clicks the menu bar icon (left click), or picks Capture from the menu / settings.
2. The system selector appears (`screencapture -i -s`). Esc cancels; nothing happens.
3. On-device Vision reads the captured PNG (accurate level, revision 3, language correction, automatic language detection, Chinese-varieties-first language order). No network.
4. Non-empty text goes straight to the general pasteboard; a short sound confirms. No result window.
5. Empty result, capture failure, or missing screen-recording permission shows a one-shot explanatory alert with a way forward. Never a silent failure, never a retry loop.

## Hotkey

- Factory default is Command Shift 2. User can record a new combination, clear it, or restore the default. Settings apply immediately and survive restart.
- A combination already taken fails loudly in settings; system-reserved combinations are refused with a reason.
- A second press while a capture is already in flight is dropped, never queued.

## Permission

- Screen recording is pure TCC. First capture triggers the system prompt; the usage description explains the capture-then-recognize purpose.
- Denied state is a first-class UI state: what is missing, what breaks, an Open System Settings button, and an explicit retry. Coming back from settings re-checks automatically.
- No other system permission is requested.

## Startup and first-use reliability (2026-10-24)

Reported symptom: after boot, the shortcut seemed unusable for one to two minutes. Measured cause, reproduced on this Mac: Vision's first text-recognition pass in a process loads the macOS 27 recognition model and took 63.5 s in a standalone probe and 91.9 s inside TextSnap; the same request took 0.23 s once the model was loaded. The old code ran that first pass synchronously on the main actor, so recognition, the status menu and the global-shortcut callback all froze for that window. The model load is per process, so it also affects first use after a relaunch, not just after boot.

Adopted contract:

- The global shortcut is registered in `applicationWillFinishLaunching`, before the status item, Sparkle, launch-at-login state or any other launch work. A failed registration retries with bounded backoff (1 s through 120 s) and re-asserts after wake, screen wake, unlock, session activation, and at 5/30/90 s while a login session settles. User-recorded conflicts still fail loudly in Settings and are not retried behind the user's back.
- Text recognition never runs on the main actor. Vision's `supportedRecognitionLanguages()` result is cached for the process, and a launch-time warm-up runs one tiny recognition off-main so the first real capture does not pay the cold-model cost.
- Sparkle starts about two seconds after launch, never in the pre-launch path. Launch-at-login state is read off-main and cached; status menus never synchronously call `SMAppService` (macOS rebuilds them during login).
- Diagnostics are privacy-safe: `log show --last boot --predicate 'subsystem == "top.caozc.TextSnap"' --style compact` shows launch phases, registration attempts/retries, every delivered shortcut press, selector duration, OCR duration and character count. Recognized text and clipboard contents are never logged.

Acceptance: on the installed signed build, the shortcut must respond during the warm-up window (log `pressed` and a selector process within ~1 s), and the first capture after launch must not block the menu or a second press. The warm-up duration is recorded so a future macOS regression is measurable.

## Installed acceptance and delivery (0.2.5)

Root cause evidence: a standalone Vision probe took 63.5 s for its first recognition and 0.23 s immediately afterwards; the in-app first recognition took 91.9 s, and a text-bearing launch warm-up later measured 37.4 s. The old code ran that pass synchronously on the main actor, which is why the shortcut and the whole app appeared dead for one to two minutes. During the 37.4 s warm-up, the refactored app still logged a settle re-registration, and during a 37.7 s real OCR it logged a second hotkey press and the expected "capture already in flight" drop, proving the main thread stayed responsive.

Verification on the Developer ID Release build: eight tests passed and the universal Release build plus `analyze` completed with zero compiler or analyzer warnings. The shortcut registered in `applicationWillFinishLaunching` (same timestamp as the launch callback), the status item was ready 80–110 ms later, Sparkle started about two seconds after launch, and the launch-at-login read completed off-main. A real capture completed the full hotkey → selector → Vision → pasteboard path with 275 characters copied; OCR after the warm-up took 664 ms.

The notarized public export replaced `/Applications/TextSnap.app`; installed version/build read back 0.2.5 / 7, the Developer ID signature and hardened-runtime flag validated, `stapler validate` passed, and `spctl` reported the Developer ID origin while this host still reports security assessment disabled (so that result does not establish stock-Gatekeeper enforcement). The installed process stayed alive with no window. Launch logs showed `launch at login status=on`, the warm-up completed in 367 ms with 21 probe characters, and the updater started after the launch path. The public [0.2.5 release](https://github.com/x0c/TextSnap/releases/tag/v0.2.5) carries the notarized DMG, signed update ZIP and build-7 appcast; the publisher's anonymous downloads verified all three files plus the latest-feed appcast.

Limitations: the final installed interaction acceptance ran while the screen was locked, and macOS does not deliver global shortcuts under screen lock, so post-install hotkey and capture interaction were not repeated on the notarized artifact; the equivalent path was verified on the Developer ID build immediately before locking. The tccd preflight for the notarized build reported no code-requirement mismatch, but the first real capture after an update should still be confirmed once the screen is unlocked. During testing, launching a build-tree copy re-pointed the background-task login record at that copy; the installed app then reported launch-at-login as off until it was re-registered from its menu against `/Applications/TextSnap.app`. Agent builds must not launch DerivedData copies while the login item is registered.

## Menu and settings parity

- Right-click menu: Capture Now / Settings / Launch at Login (tri-state) / Check for Updates / About / Quit. No hide-icon item.
- The single settings window offers the same: shortcut editor, permission state, launch toggle, last result with Copy Again, capture / check updates / about / quit, version.
- Left click is Capture Now.

## Settings layout (2026-10-18)

The October 18 settings revision authorized opening this surface for that revision's installed visual acceptance; the normal silent-launch contract still applies to later tasks. Use one public SwiftUI `Settings` scene, with a 480-point native grouped `Form` sized to its measured content. Four groups contain Capture (shortcut, screen-recording state and Capture Now), Last Result (memory-only text, at most four visible lines, plus Copy Again), General (the existing launch-at-login switch), and the app icon/name/version with About, Check for Updates and Quit. Preserve every existing menu/settings action; do not add a menu-icon visibility setting.

Replace stacked GroupBoxes and standalone action rows with native `Section`, `LabeledContent`, `Toggle`, `Button` and `Menu`. Keep shortcut editing on the existing recorder; its native value button starts recording and its action menu clears or restores the shortcut. Move ordinary recording guidance to help; show conflicts, denied permissions and pending login approval inline. The empty last-result message must not hardcode the factory shortcut because the user can change it. No custom backgrounds, focus frames or control lookalikes. Settings do not scroll; content height follows permission/error/result changes. Escape cancels recording first and otherwise closes Settings. Keep the existing autosave name and MacKit accessory activation session. Preserve the old controller’s visible-screen clamp when attaching the native scene, after content resizing and when it becomes key. A saved window may lie between displays after the display arrangement changes: an isolated window capture still renders its offscreen body, so actual pointer acceptance must confirm that the whole frame is inside a current visible screen.

Reference selection: inspected this product's actual SettingsView, window controller and shortcut/permission/login implementations. Retain their business actions and state, and apply the grouped-Form/content-height recipe in the shared macOS settings and AppKit guides; no other product source is imported. Apple's public [Settings](https://developer.apple.com/documentation/swiftui/settings), [Form](https://developer.apple.com/documentation/swiftui/form) and [LabeledContent](https://developer.apple.com/documentation/swiftui/labeledcontent) APIs fit this macOS 26+ target and are present in the installed Xcode 27.2 SDK. The app's icon is governed by the App icon section below.

Acceptance: inspect the installed window in dark English and light Chinese, including keyboard/AX labels, recording cancellation, permission status, and the about/update actions. Verify settings opens only from explicit entry points, returns to accessory mode when closed, and restores position on normal restart. Run the existing tests and complete Release build/analyze diagnostics. Public signed distribution requires meaningful bilingual release and update notes; the coordinator commits before the archive/install and publishes the whole current workspace.

## App icon

The owner selected Native 02 from the October 4 native previews: a pair of blue glass opening quotation marks on a pale silver-white background. Refine this exact direction and adopt it as the application icon. Preserve the paired silhouette, composition, blue/cyan highlights, pale background and shallow glass depth; improve curves, edges, lighting and small-size clarity, and remove the direction-board border. This selection supersedes the later unselected sticker/eyedropper exploration. The menu-bar viewfinder remains its existing independent template symbol.

Owner correction: Icon Composer is prohibited for TextSnap. Preserve the selected artwork's translucent glass, internal light and cast shadows in the raster master. Do not redraw it as vector shapes, flatten blue color variations or replace its material with system-generated effects. This explicit product decision supersedes the shared layered-icon requirement for this product. The attempted vector/composer reinterpretation was rejected and must not ship.

Keep `design/app-icon/AppIcon-1024.png`, the PNG files in `TextSnap/Assets.xcassets/AppIcon.appiconset/` and the public README icon synchronized with the unchanged refined raster. The existing `.icon` directory is inactive legacy material and excluded from the target. Asset conversion may resize and encode; it must preserve artwork, color, composition and shadows.

Reference: inspected the actual Native 02 preview and its raster refinement. Use the raster directly through the existing macOS asset catalog. The automated contrast heuristic splits the smooth blue foreground into quantized bins below its 4% per-bin cutoff and consequently compares two pale background bins (1.18:1), despite a 48px luminance span of 4.49:1 and 15.4% high-contrast pixels, and a 24px span of 3.99:1 and 14.2% high-contrast pixels. Retain that failed heuristic result as a limitation; do not alter the owner's selected material to make color quantization pass. Inspect the actual 24px/48px artwork and installed Finder icon for recognition and retained shadows.

## Storage

- Settings file: `~/.config/textsnap/settings.json` (`$XDG_CONFIG_HOME` aware). Last recognized text is memory-only, never written to disk.
- No history database, no second copy under Application Support, no home-directory dotfiles.

## Updates

Default is public distribution: GitHub Releases feed the in-app updater (Sparkle); a signed, notarized `.dmg` is the first-install entry. Never claims to be up to date.

## Diagnostics and release notes

Release notes live in [CHANGELOG.md](../CHANGELOG.md); the publisher embeds the matching English and complete Simplified Chinese section in both Sparkle and GitHub. The archive explicitly builds arm64 and x86_64 for the supported Mac architectures. The existing Vision results property is already a typed optional array in the installed SDK, so its no-op conditional downcast is removed without changing recognition order or output.

The Sparkle 2.10.0 runtime warning about background scheduled checks without gentle reminders is retained for this settings revision. Origin: the existing standard updater has no user-driver delegate. Sparkle's [background-app behavior and examples](https://sparkle-project.org/documentation/gentle-reminders/) explain that scheduled alerts appear behind other apps after launch; implementing its background reminder example would add Dock/notification behavior beyond this settings task and the current screen-recording-only permission contract. Manual Check for Updates still uses Sparkle's standard user-initiated UI. Residual risk: a background-only user may miss a scheduled alert. Follow-up: design an in-menu reminder or adopt a separately approved background reminder policy; do not merely return true from the support flag without providing a reminder.

## Installed acceptance and delivery (0.2.3)

Six existing tests passed; the universal Release build and analyze passed without compiler warnings after removing Vision's no-op results cast. The retained Sparkle runtime reminder warning is assessed above. The native grouped Settings layout was inspected in dark English and light Simplified Chinese before the display-clamp correction; the correction affects position only. Shortcut recording and Escape cancellation, About, manual update checking, close/accessory restoration and silent first launch were observed in that unlocked session.

The final committed app and then the notarized public export were installed. A newly opened English Settings window was captured under lock after a bounded display wake: 480 × 462 points, all sections visible, controls aligned, and the previously offscreen saved position clamped into the current display. This proves that artifact's static empty-result surface; the lock shield blocks AX interaction, so it does not count as post-install keyboard, VoiceOver or nonempty-result acceptance. Those paths remain limited until an unlocked interaction session. The user's shortcut and login preference were not changed. No virtual display was created.

The public [0.2.3 release](https://github.com/x0c/TextSnap/releases/tag/v0.2.3) contains the notarized/stapled DMG, signed update ZIP and build-5 appcast. Anonymous downloads succeeded; the full DMG bytes matched the local notarized image, and the installed marketing/internal versions are 0.2.3 / 5. Public release/update notes contain the matching English and Simplified Chinese changes.

## Installed acceptance and delivery (0.2.4)

The blue-glass raster and all ten catalog slots are synchronized; the 1024px slot is byte-identical to the master. The README presentation has rounded transparent outer corners. The actual 1024/180/48/24px images and the macOS 16/32px slots were inspected; paired quotes remain identifiable, with highlights and shadows visible at larger sizes. The contrast-heuristic limitation remains recorded above.

Six existing tests and the clean universal arm64/x86_64 Release build/analyze passed with zero compiler or analyzer warnings. The public archive/export also passed. The release tool retained one macOS beta warning: its existing `hdiutil detach` command is deprecated; detachment nevertheless succeeded and the smoke-test mount was ejected. This does not affect the delivered app or image; migrate that tool invocation to `diskutil eject` in the publisher maintenance task. The expected pre-publication missing-tag notice cleared when the tag was pushed. The leak scan's sole medium-entropy finding is the intentionally public Sparkle EdDSA verification key, not a signing secret.

The source commit is `008c920`. Its Developer ID export and DMG were notarized and stapled. The notarized export replaced `/Applications/TextSnap.app`; installed version/build read back as 0.2.4 / 6, signatures and stapled tickets validated, and installed `AppIcon.icns`/`Assets.car` match the export. `spctl` accepted the app, but this host reports security assessment disabled, so that result does not establish enforcement on a stock Gatekeeper configuration. The installed process remained alive with no application window. Its hotkey log is compiled only in Debug and was observed in the test host; capture and shortcut interaction were not repeated for this asset-only change.

Finder was inspected after final installation through an alias to the installed app, confirming the glass highlights and cast shadows. The initial crowded Applications view showed generic placeholders and was not accepted as icon evidence. TextSnap is a menu-bar app without a persistent Dock tile; its independent menu-bar symbol was unchanged.

The public [0.2.4 release](https://github.com/x0c/TextSnap/releases/tag/v0.2.4) has the DMG, update ZIP and appcast. A transient TLS EOF interrupted the publisher's final verification after upload; subsequent anonymous full downloads of all three assets matched the local notarized/signed bytes. The ordinary latest-feed URL serves build 6 / 0.2.4 with the matching ZIP URL, length and EdDSA signature, and bilingual notes. The local handoff receipt is `build/icon-refinement/verified-handoff.json` (ignored build evidence).
