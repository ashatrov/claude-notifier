# 🔔 Claude Code Phone Notifications

Send a phone notification when Claude Code needs your attention.

Sub-agent events are ignored.

## 📁 Files

- `notify-pushover.sh` — Pushover notifier
- `notify-telegram.sh` — Telegram notifier
- `claude-settings-file-part.json` — hooks to merge into `~/.claude/settings.json`

Claude Code always calls:

```text
~/.claude/hooks/notifyer.sh
```

Choose one notifier and copy it with this name.

## 📲 Notifications

You get a notification when the main Claude agent:

- ❓ asks a question
- 🔐 needs permission
- 🧩 waits for MCP input
- ⏸️ needs input from a background session
- ⚠️ stops because of an API error
- ✅ finishes and waits for you

## 🛠️ Setup

### 1. Install dependency

```bash
brew install jq
```

### 2. Configure a notification provider

#### Pushover

Create an app at https://pushover.net/ and get:

- User Key
- Application API Token

Store them in macOS Keychain:

```bash
security add-generic-password -U \
    -a "$(id -un)" \
    -s "claude-pushover-user" \
    -w "YOUR_PUSHOVER_USER_KEY"

security add-generic-password -U \
    -a "$(id -un)" \
    -s "claude-pushover-token" \
    -w "YOUR_PUSHOVER_APP_TOKEN"
```

#### Telegram

Create a bot with `@BotFather` and send `/start` to it.

Store the bot token:

```bash
security add-generic-password -U \
    -a "$(id -un)" \
    -s "claude-telegram-bot-token" \
    -w "YOUR_TELEGRAM_BOT_TOKEN"
```

Get your chat ID:

```bash
BOT_TOKEN="$(security find-generic-password \
    -a "$(id -un)" \
    -s "claude-telegram-bot-token" \
    -w)"

curl -s "https://api.telegram.org/bot${BOT_TOKEN}/getUpdates" \
    | jq '.result[-1].message.chat.id'
```

Store it:

```bash
security add-generic-password -U \
    -a "$(id -un)" \
    -s "claude-telegram-chat-id" \
    -w "YOUR_CHAT_ID"
```

### 3. Install the notifier

Create the hooks directory:

```bash
mkdir -p ~/.claude/hooks
```

For Pushover:

```bash
cp notify-pushover.sh ~/.claude/hooks/notifyer.sh
```

For Telegram:

```bash
cp notify-telegram.sh ~/.claude/hooks/notifyer.sh
```

Then:

```bash
chmod 700 ~/.claude/hooks/notifyer.sh
```

### 4. Configure Claude Code

Merge the `hooks` from:

```text
claude-settings-file-part.json
```

into:

```text
~/.claude/settings.json
```

> 📝 Keep these hooks as separate entries from existing hooks.
>
> If an event already exists in your settings, keep it and add the notifier entry next to it. Do not replace the existing hook.

### 5. Verify

Start Claude Code and run:

```text
/hooks
```

Check that the hooks are registered.

## 🔄 Switch provider

Just replace `notifyer.sh`.

For example, switch to Telegram:

```bash
cp notify-telegram.sh ~/.claude/hooks/notifyer.sh
chmod 700 ~/.claude/hooks/notifyer.sh
```

No change to `~/.claude/settings.json` is needed.
