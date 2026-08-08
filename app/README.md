# ☕ Claude Notifyer Manager

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

Waking the screen does **not** end the session. The Mac stays awake until the
time runs out or you press Stop.

The app only sets one flag:

```bash
defaults read com.ashatrov.claude-notifyer enabled
```

The scripts in the folder above read that flag and send the message.

> 📝 The app is named "Claude Notifyer Manager" but its ID is still
> `com.ashatrov.claude-notifyer`. That ID is where the flag is saved. Do not
> change it, or the scripts will stop working.

## 🗺️ How it works

The app and the scripts never talk to each other. They only share one flag.

The app writes it. The scripts read it.

```text
        ── the app writes the flag ──

     you click the cup and pick a time
                    │
                    ↓
      Claude Notifyer Manager.app
                    │
                    ├─ caffeinate ....... Mac stays awake
                    ├─ timer ............ ends when time is up
                    └─ display check .... every 2 seconds
                    │
                    │ writes
                    ↓
      com.ashatrov.claude-notifyer  enabled

            screen off  →  enabled = 1
            screen on   →  enabled = 0
            forced      →  enabled = 1  (screen ignored)


        ── the script reads the flag ──

         Claude Code needs you
                    │
                    ↓
              hook fires
                    │
                    ↓
      ~/.claude/hooks/notifyer.sh
                    │
                    │ reads
                    ↓
      com.ashatrov.claude-notifyer  enabled
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

| `caffeinate` | Screen | Phone notifications |
|:---|:---|:---|
| off | on | 🔕 off |
| off | off | 🔕 off |
| on | on | 🔕 off |
| on | off | 🔔 **on** |

Only one row rings. Both things must be true: a session is running **and** the
screen is off.

Unless you force it. See below.

The last two rows are the ones you move between all day. You walk away, the
screen sleeps, your phone rings. You come back, the screen wakes, your phone
goes quiet.

The screen never changes the first column. Waking the screen does not stop
`caffeinate`. The Mac stays awake until the time is up or you press Stop.

### Force notifications

Sometimes you want the phone to ring while you are still at the Mac. Maybe you
are reading, or in a meeting, and the Mac is on the desk next to you.

Tick **Force notifications** in the menu. It skips the screen rule.

| `caffeinate` | Force | Screen | Phone notifications |
|:---|:---|:---|:---|
| on | off | on | 🔕 off |
| on | off | off | 🔔 on |
| on | **on** | on | 🔔 **on** |
| on | **on** | off | 🔔 **on** |
| off | on | any | 🔕 off |

Look at the last row. **Force still needs a session.** With no session the phone
stays quiet, no matter what. Force is not a way to turn the phone on by itself.

You can tick it before you start, or while a session runs. It works right away —
you do not have to wait for the screen.

The top line of the menu then says:

```text
Notifications: 🔔 on — forced
```

So you always know why your phone is ringing.

> 📝 Force stays ticked until you untick it. It is remembered after you close
> the app. Untick it when you go back to normal work, or your phone will ring
> every time you start a session.

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

This makes `Claude Notifyer Manager.app` in this folder.

For a Mac with an Intel chip, build for both chips:

```bash
ARCHS="arm64 x86_64" ./build.sh
```

## 📦 Install

The app is already built and saved in git. So you can just run:

```bash
./install.sh
```

It copies the app to `~/Applications`.

No password. No admin rights.

Then open it:

```bash
open ~/Applications/"Claude Notifyer Manager.app"
```

Quit the app first if it is already running. The script will tell you.

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
Awake for 10 hours
Custom...
```

`Custom...` takes any number. You can use `1.5` for one and a half hours.

Below the times there are two tick boxes:

- **Turn display off after start** — the screen goes off right away, so you can
  just walk away. On by default.
- **Force notifications** — ring the phone even when the screen is on. Off by
  default. See [Force notifications](#force-notifications).

### While it runs

Click the cup again:

```text
Claude Notifyer Manager — Active
Notifications: 🔕 off — screen is on
Remaining: 3h 42m 10s

☐ Force notifications

Turn Display Off Now
Stop
```

The seconds count down while the menu is open.

The top line tells you if your phone will ring right now. It says **off** almost
every time you look at it. That is correct: you can only read the menu when the
screen is on, and the screen being on is what keeps the phone quiet. It turns to
🔔 **on** a moment after you walk away.

- **Force notifications** — ring even with the screen on. Works right away.
- **Turn Display Off Now** — turns the screen off. Does not change the time.
- **Stop** — ends it now.

### Settings

Click the cup, then **Settings…**

This is where you put your Telegram or Pushover credentials. It replaces the two
old shell scripts.

```text
┌ Claude Notifyer Manager Settings ─────┐
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

**Send test** runs your real `~/.claude/hooks/notifyer.sh`. It is not a copy of
the send code, it is the same script Claude Code runs. If your phone buzzes, the
whole chain works.

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

## 📁 Files

```text
app/
├── README.md                 this file
├── Package.swift             build settings for Swift
├── Info.plist                app name, ID, and "no Dock icon" flag
├── build.sh                  builds the app
├── install.sh                copies the app to ~/Applications
├── .gitignore                hides build leftovers from git
│
├── Sources/ClaudeNotifyerManager/
│   ├── main.swift                    starts the app
│   ├── AppDelegate.swift             startup and shutdown
│   ├── StatusBarController.swift     the cup icon and the menu
│   ├── UnattendedModeController.swift  runs the timer and keeps the Mac awake
│   ├── DisplayMonitor.swift          checks if the screen is off
│   ├── Preferences.swift             saves settings
│   ├── SettingsWindowController.swift  the Settings window
│   ├── Keychain.swift                saves secrets with /usr/bin/security
│   ├── TelegramAPI.swift             gets your chat ID from Telegram
│   └── NotifierHook.swift            finds and runs ~/.claude/hooks/notifyer.sh
│
└── Claude Notifyer Manager.app/   the built app, saved in git so you need not build
```
