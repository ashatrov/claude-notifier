# Hook Registration Check Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Claude Notifier Manager warns when `~/.claude/settings.json` does not register `notifier.sh` for the six notifier events.

**Architecture:** A new Foundation-only file `HookRegistration.swift` holds a pure function from settings-file bytes to a status, plus the warning text. Settings and the menu bar call it and show its warning. The app only reads the file.

**Tech Stack:** Swift 5.9 package, AppKit, Foundation `JSONSerialization`. Command Line Tools only — no Xcode, so no XCTest and no Swift Testing (the `TestingMacros` plugin is missing from CLT; verified). Tests are a plain `main.swift` compiled with `swiftc` next to the file under test.

**Spec:** `docs/superpowers/specs/2026-11-23-hook-registration-check-design.md`

## Global Constraints

- The app never writes `~/.claude/settings.json`.
- Only `~/.claude/settings.json` is checked — not `settings.local.json`, project or managed settings.
- Events, in this order: `PreToolUse`, `PermissionRequest`, `Elicitation`, `Notification`, `StopFailure`, `Stop`.
- An event is registered when any `hooks.<Event>[].hooks[].command` string contains `.claude/hooks/notifier.sh`. Matchers and arguments are not checked. Other entries are ignored.
- At most one `⚠︎` row in the menu; script problems take priority over hook registration.
- The built bundle `app/Claude Notifier Manager.app` is committed; source changes ship with a rebuilt bundle (`make build`).

## Review Focus

1. Another plugin's hook sits in the same event (e.g. a second `Stop` entry before ours) → still registered, no warning. *(Task 1 test `otherHooksInSameEvent`)*
2. The command spells the path differently — `~/.claude/hooks/notifier.sh`, `/Users/x/.claude/hooks/notifier.sh`, or with a different argument → registered. *(Task 1 test `pathSpellings`)*
3. Hand-edited file with wrong shapes — `"hooks": []`, `"Stop": {}`, an entry without `hooks`, a non-string `command` → those events count as missing; no crash. *(Task 1 test `malformedShapes`)*
4. Top-level JSON that is valid but not an object (`[]`, `"x"`) or a JSON5-ish file with a trailing comma → `.unreadable`, not "all missing". *(Task 1 test `unreadable`)*
5. `disableAllHooks: false` is present → behaves as if absent. *(Task 1 test `disableAllHooksFalse`)*

---

### Task 1: `HookRegistration` — parse settings and produce the warning

**Files:**
- Create: `app/Sources/ClaudeNotifierManager/HookRegistration.swift`
- Create: `app/Tests/HookRegistrationTests/main.swift`
- Modify: `Makefile` (add `test` target, add to `.PHONY`)

**Interfaces:**
- Produces:
  ```swift
  enum HookRegistration {
      static let events: [String]            // the six, in Global Constraints order
      static let commandMarker: String       // ".claude/hooks/notifier.sh"
      static let settingsURL: URL            // ~/.claude/settings.json

      enum Status: Equatable {
          case registered
          case missing([String])             // in `events` order, never empty
          case allHooksDisabled
          case unreadable
      }

      /// nil data = file does not exist.
      static func status(settings data: Data?) -> Status
      /// Reads settingsURL; a read failure other than "no such file" is .unreadable.
      static func current() -> Status

      // on Status:
      var warning: String?                   // nil for .registered
  }
  ```
  `HookRegistration.swift` imports Foundation only (it is compiled standalone by the test runner).

- [ ] **Step 1: Write the failing tests** in `app/Tests/HookRegistrationTests/main.swift`

  A tiny harness: `func check(_ name: String, _ ok: Bool)` that prints `PASS`/`FAIL name`, counts failures, and the file ends with `exit(failures == 0 ? 0 : 1)`. A helper `func s(_ json: String) -> HookRegistration.Status { HookRegistration.status(settings: json.data(using: .utf8)) }` and a helper building a full valid settings JSON for a given list of events (command `"$HOME/.claude/hooks/notifier.sh <arg>"`).

  Cases (name → assertion):
  - `fileMissing` → `status(settings: nil) == .missing(HookRegistration.events)`
  - `noHooksKey` → `s("{\"theme\":\"dark\"}") == .missing(events)`
  - `allSix` → full JSON for all six `== .registered`
  - `someMissing` → JSON with all but `Elicitation` and `Stop` `== .missing(["Elicitation", "Stop"])`
  - `otherHooksInSameEvent` → `Stop` has two entries, first `{"hooks":[{"type":"command","command":"other-plugin.sh"}]}`, second ours; plus an unrelated event `SessionStart` with another command; all six present `== .registered`
  - `pathSpellings` → three settings, each all six, commands using `~/.claude/hooks/notifier.sh done`, `/Users/x/.claude/hooks/notifier.sh`, `"$HOME/.claude/hooks/notifier.sh" question` → each `== .registered`
  - `malformedShapes` → `{"hooks":[]}` `== .missing(events)`; all six valid except `"Stop": {}` `== .missing(["Stop"])`; all six valid except `Stop` entry `{"matcher":"x"}` (no `hooks`) `== .missing(["Stop"])`; all six valid except `Stop` command is `42` `== .missing(["Stop"])`
  - `unreadable` → `s("[]")`, `s("\"x\"")`, `s("{\"a\":1,}")`, `s("")` each `== .unreadable`
  - `disableAllHooks` → all six valid plus `"disableAllHooks": true` `== .allHooksDisabled`
  - `disableAllHooksFalse` → all six valid plus `"disableAllHooks": false` `== .registered`
  - `warningText` →
    - `Status.registered.warning == nil`
    - `Status.missing(events).warning == "⚠︎ No hooks in ~/.claude/settings.json"`
    - `Status.missing(["Elicitation", "Stop"]).warning == "⚠︎ Not registered in ~/.claude/settings.json: Elicitation, Stop"`
    - `Status.allHooksDisabled.warning == "⚠︎ All hooks disabled in ~/.claude/settings.json"`
    - `Status.unreadable.warning == "⚠︎ Could not read ~/.claude/settings.json"`

- [ ] **Step 2: Add the `test` target to `Makefile`**

  ```make
  # Compile HookRegistration with its tests and run them (no Xcode needed)
  test:
  	mkdir -p app/.build
  	swiftc app/Sources/ClaudeNotifierManager/HookRegistration.swift app/Tests/HookRegistrationTests/main.swift -o app/.build/hook-registration-tests
  	./app/.build/hook-registration-tests
  ```
  Add `test` to `.PHONY`. (`app/.build/` is already git-ignored by `app/.gitignore`.)

- [ ] **Step 3: Run to verify it fails**

  Run: `make test`
  Expected: compile error — `HookRegistration.swift` does not exist / `cannot find 'HookRegistration' in scope`.

- [ ] **Step 4: Implement `HookRegistration` in `app/Sources/ClaudeNotifierManager/HookRegistration.swift`**

  `status(settings:)`: nil → `.missing(events)`. `JSONSerialization.jsonObject` failing or top level not `[String: Any]` → `.unreadable`. `disableAllHooks as? Bool == true` → `.allHooksDisabled`. Otherwise for each event: `(hooks[event] as? [Any])` → entries `as? [String: Any]` → `entry["hooks"] as? [Any]` → items `as? [String: Any]` → `item["command"] as? String` containing `commandMarker`. Any cast failing means "not found" for that event, never an error. No missing → `.registered`.

  `current()`: `Data(contentsOf: settingsURL)`; on error, `CocoaError.fileReadNoSuchFile` → `status(settings: nil)`, any other error → `.unreadable`.

  `warning`: exact strings from Step 1. Use `"No hooks"` when the missing list equals `events`.

  Doc comment on the type: why it exists (Send test bypasses Claude Code, so a script check alone can say "installed" while nothing ever runs it) and that the app only reads this file.

- [ ] **Step 5: Run to verify it passes**

  Run: `make test`
  Expected: every line `PASS`, exit status 0.

- [ ] **Step 6: Confirm the app still builds**

  Run: `cd app && swift build`
  Expected: `Build complete!`

- [ ] **Step 7: Commit**

  ```bash
  git add app/Sources/ClaudeNotifierManager/HookRegistration.swift app/Tests/HookRegistrationTests/main.swift Makefile
  git commit -m "Check that settings.json registers the notifier hooks"
  ```

---

### Task 2: Show the warning in Settings and the menu bar, document it, rebuild

**Files:**
- Modify: `app/Sources/ClaudeNotifierManager/SettingsWindowController.swift:209-231` (`refreshHookStatus`)
- Modify: `app/Sources/ClaudeNotifierManager/StatusBarController.swift:110-127` (`addHookWarning`)
- Modify: `README.md` (section `## 🩺 How the app knows what is installed`, after line 234's section body)
- Modify: `app/Claude Notifier Manager.app` (rebuilt bundle)

**Interfaces:**
- Consumes: `HookRegistration.current() -> HookRegistration.Status`, `Status.warning: String?`, `Status.registered`.

- [ ] **Step 1: Settings status line**

  In `refreshHookStatus`, after the jq check and before joining: `if let warning = HookRegistration.current().warning { parts.append(warning) }`. Shown whatever the script state is. Install button logic unchanged.

- [ ] **Step 2: Menu bar row**

  In `addHookWarning`, the `.current` case no longer returns unconditionally: return only when `HookRegistration.current() == .registered`, otherwise title `"⚠︎ Register hooks…"` (opens Settings, same selector). Other cases unchanged — they win because they are matched first. Update the doc comment: no row when the script is current *and* the hooks are registered.

- [ ] **Step 3: README**

  Add a short subsection under `## 🩺 How the app knows what is installed`:
  - Settings also reads `~/.claude/settings.json` and checks that each of the six events has at least one hook whose command contains `.claude/hooks/notifier.sh`. Other hooks are ignored.
  - The app never writes that file; if a warning appears, merge the `hooks` from `claude-settings-file-part.json` by hand (link to step 4 of Setup).
  - Add one row to the menu-bar behaviour: `⚠︎ Register hooks…` when the script is fine but hooks are missing.
  - Mention `make test` in the Install section's rebuild paragraph.

- [ ] **Step 4: Rebuild the bundle**

  Run: `make build`
  Expected: `Building Claude Notifier Manager (arm64)...` and a refreshed `app/Claude Notifier Manager.app` with no errors.

- [ ] **Step 5: Manual check against the real file (read-only)**

  Run the rebuilt app straight from the repo bundle (quit the installed one first):
  `open "app/Claude Notifier Manager.app"`
  - With the current `~/.claude/settings.json` (all six registered): menu has no `⚠︎` row; Settings line has no hook warning.
  - Point check without touching the user's file: `make test` already covers missing/unreadable; do **not** edit `~/.claude/settings.json` to provoke the warning.

- [ ] **Step 6: Commit**

  ```bash
  git add app/Sources/ClaudeNotifierManager/SettingsWindowController.swift app/Sources/ClaudeNotifierManager/StatusBarController.swift README.md "app/Claude Notifier Manager.app"
  git commit -m "Warn in Settings and the menu when notifier hooks are not registered"
  ```

Installing the rebuilt app into `~/Applications` (`make install`) is left to the user.
