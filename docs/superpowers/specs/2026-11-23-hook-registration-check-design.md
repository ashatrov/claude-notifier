# Hook registration check — design

## Why

Settings said "Hook installed: Telegram", but `~/.claude/settings.json` had lost
its `hooks` block, so Claude Code never ran the script. Send test still worked,
because it runs the script directly. The app checked one link of the chain (the
script on disk) and reported the whole chain as healthy.

## Goal

The app warns when Claude Code is not wired to call `notifier.sh`.

- Simple: no matcher or argument validation.
- Tolerant: other hooks from other plugins or apps, in the same events or other
  events, never cause a warning.

## Non-goals / anti-goals

- The app never writes `~/.claude/settings.json` (README promise stays true).
  No "Register hooks" button — option B was rejected.
- No checking of `settings.local.json`, project or managed settings.

## Approaches

- **A. Warn only** — chosen. Keeps the README promise, no risk of damaging the
  user's config.
- **B. Warn + "Register hooks" button** that merges the missing entries —
  rejected: the app would start writing the user's config, more code and risk.

## Design

New read-only check in `NotifierHook` (e.g. `missingHookEvents() -> [String]`):

1. Read and parse `~/.claude/settings.json` with `JSONSerialization`.
2. For each of the six events — `PreToolUse`, `PermissionRequest`,
   `Elicitation`, `Notification`, `StopFailure`, `Stop` — the event counts as
   registered if any entry under `hooks.<Event>[].hooks[]` has a `command`
   string containing `.claude/hooks/notifier.sh`. Everything else is ignored.
3. Return the events that are not registered.

Edge cases (my calls):

- File missing → all six missing.
- File unreadable or invalid JSON → one distinct warning
  ("could not read ~/.claude/settings.json"), not a list of events.
- `"disableAllHooks": true` → warn "all hooks disabled in settings.json"; same
  failure class, one extra line.

Where it shows:

- **Settings** status line (`refreshHookStatus`): append
  `⚠︎ Not registered in ~/.claude/settings.json: Stop, …` — or
  `⚠︎ No hooks in ~/.claude/settings.json` when all six are missing.
- **Menu bar** (`addHookWarning`): when the script is current but hooks are
  missing, show `⚠︎ Register hooks…`, opening Settings. Script problems keep
  priority (one warning row at most).
- README: one short section on what the check looks for and that hooks must be
  merged by hand from `claude-settings-file-part.json`.

## Left to the builder

- Exact Swift naming and where the event list lives (single constant, shared
  with nothing else — the JSON template stays the source for users).
- Whether to unit-test the parser: the package has no test target today; a
  small pure function taking `Data` keeps it testable if one is added.
