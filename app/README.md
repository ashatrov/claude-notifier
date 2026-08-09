# ☕ Claude Notifier Manager

A small app that lives in the macOS menu bar.

It manages the notifier scripts in the folder above. It does not send messages
itself. It turns them on and off for you.

## 🎯 What it is for

You leave Claude Code working and walk away.

You want two things:

- the Mac must stay awake;
- your phone must ring when Claude needs you.

This app does both. Pick a time, walk away.

While it runs:

- the Mac does not fall asleep;
- the screen may turn off;
- phone notifications turn **on** when the screen is off;
- phone notifications turn **off** when the screen is on;
- everything stops when the time is up.

The screen rule is the whole idea. You are away, so the screen is off, so your
phone rings. You come back and touch the Mac, the screen wakes, and your phone
goes quiet.

That is **Auto**, the default. You can also make the phone ring for the whole
session whatever the screen is doing, or mute it entirely — see
[Notify: On, Auto, Off](#notify-on-auto-off).

Waking the screen does **not** end the session. The Mac stays awake until the
time runs out or you press Stop.

The app only sets one flag:

```bash
defaults read com.ashatrov.claude-notifier enabled
```

The scripts in the folder above read that flag and send the message.

> 📝 `com.ashatrov.claude-notifier` is where the flag is saved. Do not change
> it, or the scripts will stop working — and they will stop quietly, with no
> error anywhere.

## 🗺️ How it works

The app and the scripts never talk to each other. They only share one flag.

The app writes it. The scripts read it.

```text
        ── the app writes the flag ──

     you click the cup and pick a time
                    │
                    ↓
      Claude Notifier Manager.app
                    │
                    ├─ caffeinate ....... Mac stays awake
                    ├─ timer ............ ends when time is up
                    └─ display check .... every 2 seconds
                    │
                    │ writes
                    ↓
      com.ashatrov.claude-notifier  enabled

            Auto + screen off  →  enabled = 1
            Auto + screen on   →  enabled = 0
            On                 →  enabled = 1  (screen ignored)
            Off                →  enabled = 0  (muted)


        ── the script reads the flag ──

         Claude Code needs you
                    │
                    ↓
              hook fires
                    │
                    ↓
      ~/.claude/hooks/notifier.sh
                    │
                    │ reads
                    ↓
      com.ashatrov.claude-notifier  enabled
                    │
            ┌───────┴───────┐
            ↓               ↓
      enabled = 1     enabled = 0
            │               │
            ↓               ↓
     Telegram or         nothing
      Pushover
            │
            ↓
       your phone 📱
```

### The full rule

`caffeinate` is on while a session runs. It keeps the Mac awake.

This table is for **Auto**, the default mode.

| `caffeinate` | Screen | Phone notifications |
|:---|:---|:---|
| off | on | 🔕 off |
| off | off | 🔕 off |
| on | on | 🔕 off |
| on | off | 🔔 **on** |

Only one row rings. Both things must be true: a session is running **and** the
screen is off.

Unless you change the mode. See below.

The last two rows are the ones you move between all day. You walk away, the
screen sleeps, your phone rings. You come back, the screen wakes, your phone
goes quiet.

The screen never changes the first column. Waking the screen does not stop
`caffeinate`. The Mac stays awake until the time is up or you press Stop.

### Notify: On, Auto, Off

The screen rule is not always what you want. Sometimes you want the phone to
ring while you are still at the Mac — you are reading, or in a meeting, and the
Mac is on the desk next to you. Sometimes you want the Mac kept awake and the
phone left alone.

The menu has a three-way switch for exactly this:

```text
Notify  [ On | Auto | Off ]
```

| Mode | What it does |
|:---|:---|
| **On** | Ring for the whole session. The screen is ignored. |
| **Auto** | Ring only while the screen is off. The default, and the rule above. |
| **Off** | Never ring. The Mac still stays awake. |

The full picture:

| `caffeinate` | Mode | Screen | Phone notifications |
|:---|:---|:---|:---|
| on | Auto | on | 🔕 off |
| on | Auto | off | 🔔 on |
| on | **On** | on | 🔔 **on** |
| on | **On** | off | 🔔 **on** |
| on | **Off** | any | 🔕 **off** |
| off | any | any | 🔕 off |

Look at the last row. **Every mode still needs a session.** With no session the
phone stays quiet, whatever the switch says. On is not a way to turn the phone
on by itself.

You can move the switch before you start, or while a session runs. It works
right away — you do not have to wait for the screen. The menu stays open so you
can see the top line change:

```text
Notifications: 🔔 on — always
Notifications: 🔔 on — screen is off
Notifications: 🔕 off — screen is on
Notifications: 🔕 off — muted
```

So you always know why your phone is ringing, or why it is not.

> 📝 The switch is remembered after you close the app. Put it back to **Auto**
> when you go back to normal work — left on **On** your phone rings every time
> you start a session, and left on **Off** it never rings at all. Nothing in the
> menu bar shows that it is muted; you have to open the menu to see it.

### When the time reaches 0

`caffeinate` was started with a time limit, so it quits on its own. The app
watches for that and cleans up.

```text
        time reaches 0
              │
              ↓
   caffeinate quits by itself
              │
              ↓
      the app sees it quit
              │
              ├─ screen checks stop
              ├─ enabled = 0        phone goes quiet
              ├─ cup goes empty
              └─ Mac may sleep again
              │
              ↓
   the app stays in the menu bar
```

You are back to the first two rows of the table. **Even if the screen is still
off, the phone stays quiet.** No session, no notifications.

The app does not close. It waits in the menu bar for the next time you need it.

**Stop** does all of the same steps, just sooner. **Quit** does them too, and
then closes the app. So there is no way to end up with the phone still ringing.

### If the app goes away

| How it ends | Phone notifications |
|:---|:---|
| Quit from the menu, or ⌘Q | 🔕 turned off |
| `kill` or `pkill` | 🔕 turned off |
| Closing the terminal that started it | 🔕 turned off |
| Restarting the Mac | 🔕 turned off |
| **Force Quit**, `kill -9`, power cut | 🔔 **stay on** |

Every normal way of closing the app cleans up. The app catches the "please exit"
signals and runs the same shutdown as the Quit menu item.

Force Quit is the exception. Nothing can catch it, so:

- `caffeinate` keeps running with no app watching it. It still stops on its own
  when its time runs out.
- The phone keeps ringing on every Claude hook.

**The fix is to open the app again.** It sets `enabled = 0` the moment it
starts.

Because they share only a flag, you can swap Telegram for Pushover and the app
does not care. And the scripts still work if you never open the app — you just
set the flag by hand.

## 🔨 Build

You only need this if you change the Swift code.

You need the Swift tools:

```bash
xcode-select --install
```

Then:

```bash
./build.sh
```

This makes `Claude Notifier Manager.app` in this folder.

For a Mac with an Intel chip, build for both chips:

```bash
ARCHS="arm64 x86_64" ./build.sh
```

## 🎨 The icon

The icon is a white cup on a warm rounded square. It is the same cup you see in
the menu bar — the very same SF Symbol — so the two can never look different.

It is already drawn and saved in git. You only need this if you want to change
it:

```bash
./make-icon.swift
```

That writes `AppIcon.icns`. Then run `./build.sh` again.

> 📝 macOS remembers old icons. If you still see the old one, run
> `killall Dock`.

## 📦 Install

The app is already built and saved in git. So you can just run:

```bash
./install.sh
```

It copies the app to `~/Applications`.

No password. No admin rights.

Then open it:

```bash
open ~/Applications/"Claude Notifier Manager.app"
```

Quit the app first if it is already running. The script will tell you.

```bash
pkill -x ClaudeNotifierManager
```

See [Quit from the terminal](#quit-from-the-terminal).

## 🖱️ Use

Look for the cup in the menu bar.

Empty cup = off. Full cup = on.

### Start

Click the cup and pick a time:

```text
Awake for 1 hour
Awake for 2 hours
Awake for 4 hours
Awake for 8 hours
Awake for 12 hours
Custom...
```

`Custom...` takes any number. You can use `1.5` for one and a half hours.

Below the times there is a tick box and a switch:

- **Turn display off after start** — the screen goes off right away, so you can
  just walk away. On by default.
- **Notify [ On | Auto | Off ]** — when the phone rings. **Auto** by default.
  See [Notify: On, Auto, Off](#notify-on-auto-off).

### While it runs

Click the cup again:

```text
Claude Notifier Manager — Active
Notifications: 🔕 off — screen is on
Remaining: 3h 42m 10s

Notify  [ On | Auto | Off ]

Turn Display Off Now
Stop
```

The seconds count down while the menu is open.

The top line tells you if your phone will ring right now. On **Auto** it says
**off** almost every time you look at it. That is correct: you can only read the
menu when the screen is on, and the screen being on is what keeps the phone
quiet. It turns to 🔔 **on** a moment after you walk away.

- **Notify [ On | Auto | Off ]** — when the phone rings. Works right away, and
  the menu stays open so you can see the top line follow.
- **Turn Display Off Now** — turns the screen off. Does not change the time.
- **Stop** — ends it now.

### Settings

Click the cup, then **Settings…**

This is where you put your Telegram or Pushover credentials. It replaces the two
old shell scripts.

```text
┌ Claude Notifier Manager Settings ─────┐
│  Provider:  [ Telegram | Pushover ]   │
│                                       │
│  Bot token:  [__________________]     │
│  Chat ID:    [________] [Get from bot]│
│                                       │
│  Hook installed: Telegram             │
│  ✓ Saved to keychain.                 │
│                                       │
│      [ Send test ]      [ Save ]      │
└───────────────────────────────────────┘
```

**Telegram** — paste the bot token from `@BotFather`. Send `/start` to your bot,
then press **Get from bot**. The app asks Telegram for your chat ID and fills it
in. Press **Save**.

**Pushover** — paste your user key and application API token. Press **Save**.

**Send test** runs your real `~/.claude/hooks/notifier.sh`. It is not a copy of
the send code, it is the same script Claude Code runs. If your phone buzzes, the
whole chain works. It sends with no session running and even under `Off` — it
passes `CLAUDE_NOTIFIER_TEST=1` to the script rather than touching `enabled`, so
a test can neither be muted nor disturb a session that is already running.

The line above the buttons tells you which notifier is installed and whether its
credentials are saved.

> 📝 Saved secrets show as `••••••••`. Leave a box empty to keep what is already
> stored. The app never reads a saved secret back, so opening Settings never asks
> for keychain permission.

### End

It ends by itself when the time is up. The cup goes empty and the phone goes
quiet. See [When the time reaches 0](#when-the-time-reaches-0).

Stop, time up, and Quit all turn the phone notifications off. The app never
leaves them on.

### Quit from the terminal

You do not need the mouse. This does the same as **Quit** in the menu:

```bash
pkill -x ClaudeNotifierManager
```

The app catches the signal, stops `caffeinate`, and turns the phone
notifications off. `kill <pid>` and closing the terminal that started it work
the same way.

Useful in a script, or before `./install.sh`, which will not replace the app
while it is running.

> ⚠️ Do not use `kill -9`. No app can catch it, so nothing is cleaned up and
> your phone keeps ringing. Open the app again to fix it. See
> [If the app goes away](#if-the-app-goes-away).

## 📁 Files

```text
app/
├── README.md                 this file
├── Package.swift             build settings for Swift
├── Info.plist                app name, ID, and "no Dock icon" flag
├── build.sh                  builds the app
├── install.sh                copies the app to ~/Applications
├── make-icon.swift           draws the app icon
├── AppIcon.icns              the app icon, saved in git
├── .gitignore                hides build leftovers from git
│
├── Sources/ClaudeNotifierManager/
│   ├── main.swift                    starts the app
│   ├── AppDelegate.swift             startup and shutdown
│   ├── StatusBarController.swift     the cup icon and the menu
│   ├── UnattendedModeController.swift  runs the timer and keeps the Mac awake
│   ├── DisplayMonitor.swift          checks if the screen is off
│   ├── Preferences.swift             saves settings
│   ├── SettingsWindowController.swift  the Settings window
│   ├── Keychain.swift                saves secrets with /usr/bin/security
│   ├── TelegramAPI.swift             gets your chat ID from Telegram
│   └── NotifierHook.swift            finds and runs ~/.claude/hooks/notifier.sh
│
└── Claude Notifier Manager.app/   the built app, saved in git so you need not build
```
