# 🔔 Claude Code Phone Notifications

Send a phone notification when Claude Code needs your attention.

Sub-agent events are ignored.

## 📁 Files

- `notify-pushover.sh` — Pushover notifier
- `notify-telegram.sh` — Telegram notifier
- `pushover-credentials-to-keychain.sh` — saves Pushover credentials
- `telegram-credentials-to-keychain.sh` — saves Telegram credentials
- `claude-settings-file-part.json` — Claude Code hooks

Claude Code always calls:

```text
~/.claude/hooks/notifyer.sh
```

Choose a notifier and copy it with this name.

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

### 2. Configure a provider

#### Pushover

Create an application at https://pushover.net/.

Then run:

```bash
zsh pushover-credentials-to-keychain.sh
```

Enter your:

- User Key
- Application API Token

#### Telegram

Create a bot with `@BotFather`.

Then run:

```bash
zsh telegram-credentials-to-keychain.sh
```

Enter the bot token, send `/start` to the bot, and press Enter.

The script gets the chat ID and saves everything to macOS Keychain.

### 3. Install the notifier

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

> 📝 Keep notifier hooks as separate entries from existing hooks.
>
> If an event already exists, keep it and add the notifier entry next to it.

### 5. Verify

Start Claude Code and run:

```text
/hooks
```

Check that the hooks are registered.

## 🔄 Switch provider

Replace only `notifyer.sh`.

Example:

```bash
cp notify-telegram.sh ~/.claude/hooks/notifyer.sh
chmod 700 ~/.claude/hooks/notifyer.sh
```

No change to `~/.claude/settings.json` is needed.
