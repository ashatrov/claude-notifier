# 🔔 Claude Code Phone Notifications

This setup sends Pushover notifications to your phone when Claude Code needs your attention.

Events from sub-agents are ignored.

## 📁 Files

- `notify-pusher.sh` — sends notifications to Pushover.
- `settings-part.json` — Claude Code hooks to merge into your real `~/.claude/settings.json`.

## 📲 Notifications

You will get a notification when the main Claude agent:

- ❓ asks a question;
- 🔐 needs permission;
- 🧩 waits for MCP input;
- ⏸️ needs input from a background session;
- ⚠️ stops because of an API error;
- ✅ finishes and waits for you.

Sub-agent events are ignored.

## 🛠️ Setup

### 1. Install dependencies

```bash
brew install jq
```

### 2. Create a Pushover application

Install Pushover on your phone and create an application at:

https://pushover.net/

You need:

- User Key
- Application API Token

### 3. Store Pushover credentials in macOS Keychain

```bash
security add-generic-password \
    -U \
    -a "$(id -un)" \
    -s "claude-pushover-user" \
    -w "YOUR_PUSHOVER_USER_KEY"

security add-generic-password \
    -U \
    -a "$(id -un)" \
    -s "claude-pushover-token" \
    -w "YOUR_PUSHOVER_APP_TOKEN"
```

### 4. Install the notification script

```bash
mkdir -p ~/.claude/hooks

cp notify-pusher.sh ~/.claude/hooks/notify-pusher.sh

chmod 700 ~/.claude/hooks/notify-pusher.sh
```

### 5. Configure Claude Code hooks

Open:

```text
~/.claude/settings.json
```

Merge the hooks from `settings-part.json` into your existing settings.

Do not replace other settings or hooks already present in `settings.json`.

> 📝 **Important:** Keep notification hooks as separate entries from existing hooks, even when they use the same event.
>
> For example, if you already have a `PreToolUse` hook with another matcher, keep it and add the `AskUserQuestion` notification hook as a separate `PreToolUse` entry.
>
> This makes the configuration easier to understand, update, and remove later.

### 6. Verify

Start Claude Code and run:

```text
/hooks
```

Check that all hooks are registered.

## 🔄 Updating

After changing `notify-pusher.sh` in this repository, copy it again:

```bash
cp notify-pusher.sh ~/.claude/hooks/notify-pusher.sh
chmod 700 ~/.claude/hooks/notify-pusher.sh
```
