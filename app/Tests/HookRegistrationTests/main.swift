// Tests for HookRegistration. The Command Line Tools ship neither XCTest nor
// the Swift Testing macro plugin, so this is a plain program: `make test`
// compiles it together with HookRegistration.swift and runs it.

import Foundation

var failures = 0

func check(_ name: String, _ ok: Bool) {
    print(ok ? "PASS \(name)" : "FAIL \(name)")
    if !ok { failures += 1 }
}

typealias Status = HookRegistration.Status

let events = HookRegistration.events

func s(_ json: String) -> Status {
    HookRegistration.status(settings: json.data(using: .utf8))
}

/// One entry per event, each running `command` with the event's argument
/// appended. `extra` is spliced into the top-level object, and `override`
/// replaces an event's whole value with raw JSON.
func settings(
    _ registered: [String],
    command: String = "$HOME/.claude/hooks/notifier.sh",
    override: [String: String] = [:],
    extra: String = ""
) -> String {
    let hooks = registered.map { event -> String in
        if let raw = override[event] { return "\"\(event)\": \(raw)" }
        let cmd = "\(command) \(event.lowercased())".replacingOccurrences(of: "\"", with: "\\\"")
        return "\"\(event)\": [{\"hooks\": [{\"type\": \"command\", \"command\": \"\(cmd)\"}]}]"
    }
    let prefix = extra.isEmpty ? "" : "\(extra), "
    return "{\(prefix)\"hooks\": {\(hooks.joined(separator: ", "))}}"
}

// fileMissing
check("fileMissing", HookRegistration.status(settings: nil) == .missing(events))

// noHooksKey
check("noHooksKey", s("{\"theme\":\"dark\"}") == .missing(events))

// allSix
check("allSix", s(settings(events)) == .registered)

// someMissing
check(
    "someMissing",
    s(settings(events.filter { $0 != "Elicitation" && $0 != "Stop" })) == .missing(["Elicitation", "Stop"])
)

// otherHooksInSameEvent
let otherStop = """
[{"hooks": [{"type": "command", "command": "other-plugin.sh"}]},
 {"hooks": [{"type": "command", "command": "$HOME/.claude/hooks/notifier.sh done"}]}]
"""
let withSessionStart = settings(events, override: ["Stop": otherStop])
    .replacingOccurrences(
        of: "\"hooks\": {",
        with: "\"hooks\": {\"SessionStart\": [{\"hooks\": [{\"type\": \"command\", \"command\": \"another.sh\"}]}], "
    )
check("otherHooksInSameEvent", s(withSessionStart) == .registered)

// pathSpellings
check("pathSpellings ~", s(settings(events, command: "~/.claude/hooks/notifier.sh")) == .registered)
check("pathSpellings absolute", s(settings(events, command: "/Users/x/.claude/hooks/notifier.sh")) == .registered)
check("pathSpellings quoted", s(settings(events, command: "\"$HOME/.claude/hooks/notifier.sh\"")) == .registered)

// malformedShapes
check("malformedShapes hooks array", s("{\"hooks\":[]}") == .missing(events))
check("malformedShapes event object", s(settings(events, override: ["Stop": "{}"])) == .missing(["Stop"]))
check(
    "malformedShapes entry without hooks",
    s(settings(events, override: ["Stop": "[{\"matcher\":\"x\"}]"])) == .missing(["Stop"])
)
check(
    "malformedShapes non-string command",
    s(settings(events, override: ["Stop": "[{\"hooks\":[{\"type\":\"command\",\"command\":42}]}]"])) == .missing(["Stop"])
)

// unreadable
check("unreadable array", s("[]") == .unreadable)
check("unreadable string", s("\"x\"") == .unreadable)
// Not a trailing comma: Foundation's parser accepts `{"a":1,}`.
check("unreadable truncated", s("{\"hooks\": {\"Stop\": [") == .unreadable)
check("unreadable empty", s("") == .unreadable)

// disableAllHooks
check("disableAllHooks", s(settings(events, extra: "\"disableAllHooks\": true")) == .allHooksDisabled)
check("disableAllHooksFalse", s(settings(events, extra: "\"disableAllHooks\": false")) == .registered)

// warningText
check("warningText registered", Status.registered.warning == nil)
check("warningText all missing", Status.missing(events).warning == "⚠︎ No notifier hooks in ~/.claude/settings.json")
check(
    "warningText some missing",
    Status.missing(["Elicitation", "Stop"]).warning
        == "⚠︎ Not registered in ~/.claude/settings.json: Elicitation, Stop"
)
check("warningText disabled", Status.allHooksDisabled.warning == "⚠︎ All hooks disabled in ~/.claude/settings.json")
check("warningText unreadable", Status.unreadable.warning == "⚠︎ Could not read ~/.claude/settings.json")

print(failures == 0 ? "All passed" : "\(failures) failed")
exit(failures == 0 ? 0 : 1)
