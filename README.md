# 🔔 Claude Code Phone Notifications

Send a phone notification when Claude Code needs your attention.

Sub-agent events are ignored.

## 📁 Files

- `notify-pushover.sh` — Pushover notifier
- `notify-telegram.sh` — Telegram notifier
- `pushover-credentials-to-keychain.sh` — saves Pushover credentials
- `telegram-credentials-to-keychain.sh` — saves Telegram credentials
- `claude-settings-file-part.json` — Claude Code hooks
- `app/` — Claude Notifyer Manager menu bar app

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

## 🚦 The `enabled` flag

Every notifier starts with the same gate:

```bash
ENABLED="$(defaults read com.ashatrov.claude-notifyer enabled 2>/dev/null || echo 0)"

[[ "$ENABLED" == "1" ]] || exit 0
```

Nothing is sent until that flag is `1`. A fresh install is silent by design — you
only want your phone buzzing when you are away from the Mac.

Set it by hand with:

```bash
defaults write com.ashatrov.claude-notifyer enabled -bool true
defaults write com.ashatrov.claude-notifyer enabled -bool false
```

Or let the menu bar app manage it for you.

## ☕ Menu bar app

`app/` holds **Claude Notifyer Manager**, a small macOS menu bar app for leaving Claude
Code running unattended. While a session is active it:

- runs `caffeinate -i`, so the Mac will not idle-sleep;
- lets the display sleep normally;
- sets `enabled` to `1` **only while every display is asleep**;
- sets it back to `0` the moment any display wakes;
- stops on its own after the duration you picked.

The point of the display rule: notifications reach your phone while you are away,
and go quiet the second you sit back down. Waking the screen never stops
`caffeinate` — the session keeps running until it times out or you stop it.

The app never talks to Telegram or Pushover. It only owns the `enabled` flag,
which is what keeps the providers interchangeable.

### Install

The built bundle is committed, so no toolchain is required:

```bash
cd app
./install.sh
open ~/Applications/"Claude Notifyer Manager.app"
```

To rebuild after changing the Swift source (needs the Swift toolchain from
Xcode Command Line Tools):

```bash
./build.sh              # arm64
ARCHS="arm64 x86_64" ./build.sh   # universal, also runs on Intel Macs
```

### Use

Click the cup in the menu bar and pick a duration — 1, 2, 4, 8, 10 hours, or
`Custom…` for anything else, decimals included. The icon fills in while a
session is active, and the menu shows the time remaining.

`Turn display off after start` (on by default) runs `pmset displaysleepnow`
right after starting, so you can walk away immediately. While active, the menu
offers `Turn Display Off Now` — which does not change the timeout — and `Stop`.

Stopping, timing out, and quitting all clear `enabled`. The app will not leave
it set.

> 📝 While the app is running it owns the flag. A manual `defaults write` will
> be overwritten at the next display transition.

## 🔄 Switch provider

Replace only `notifyer.sh`.

Example:

```bash
cp notify-telegram.sh ~/.claude/hooks/notifyer.sh
chmod 700 ~/.claude/hooks/notifyer.sh
```

No change to `~/.claude/settings.json` is needed.
