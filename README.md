<div align="center">

<img src="app/android/app/src/main/res/mipmap-xxxhdpi/ic_launcher.png" width="120" alt="Claude Remote" />

## Claude Remote

[![Platform](https://img.shields.io/badge/platform-macOS%20%7C%20Linux%20%7C%20Android-orange?style=flat-square&logo=apple)](https://github.com/ishaquehassan/claude-remote-terminal)
[![Python](https://img.shields.io/badge/python-3.10%2B-yellow?style=flat-square&logo=python)](https://www.python.org/)
[![Flutter](https://img.shields.io/badge/flutter-3.x-54C5F8?style=flat-square&logo=flutter)](https://flutter.dev/)
[![License: MIT](https://img.shields.io/badge/license-MIT-green?style=flat-square)](LICENSE)
[![Claude Code](https://img.shields.io/badge/built%20for-Claude%20Code-E07845?style=flat-square)](https://claude.ai/download)

**Claude Code on your Android phone — resume AI coding sessions anywhere, over WebSocket PTY.**

[Quick Install](#-quick-install) · [Features](#-features) · [Pairing](#-device-pairing--security) · [Slash Commands](#-claude-code-slash-commands) · [Architecture](#-architecture) · [Manual Setup](#-manual-setup)

</div>

---

## What Is This?

Claude Remote turns your Android phone into a full Claude Code terminal. A lightweight Python WebSocket server runs on your Mac or Linux machine — the app auto-discovers it on your local network, shows all available servers with their PC names, and connects in one tap.

Run `claude --continue` sessions from your phone. Type `/continue-remote` in Claude Code on your Mac and the session jumps to your phone automatically, resuming the exact conversation. Full PTY — real colors, real signals, real terminal.

---

## ✨ Features

- 🔍 **Auto-discovery** — App scans your network on startup, shows all available servers with PC hostname. No IP hunting.
- 🤖 **Claude Code first** — Built specifically for Claude Code. One button: "New Claude Session". Nothing else.
- 📲 **`/continue-remote` slash command** — Type it in Claude Code on your Mac, session instantly opens on your phone.
- 🔄 **Auto-reconnect** — App reconnects automatically if the connection drops. Never lose context.
- 💾 **Session history persistence** — Kill the app and reopen it — your terminal history is exactly where you left it. Server keeps a rolling scrollback buffer per session and replays it on re-attach.
- 🍎 **Mac terminal handoff** — Switch a session back to your Mac mid-conversation. Opens in iTerm2 if installed, falls back to Terminal.app automatically.
- ⌨️ **Mobile-optimized keys bar** — Tab, Ctrl+D, Esc, arrow keys — all tap-accessible at the bottom.
- 🏷️ **Session rename** — Name your sessions for easy organization.
- 🌐 **EN / UR language toggle** — Switch UI language on the fly.
- 🔒 **`/remote-devices-logout`** — Kick all paired phones instantly from Claude Code on your Mac.
- 🖥️ **Cross-platform server** — macOS (Homebrew), Linux (apt / pacman / dnf), Windows via WSL.
- ⚡ **Zero-hang async core** — All subprocess calls in `asyncio.to_thread()` — the event loop never blocks.

---

## 🚀 Quick Install

### Step 1 — Run the installer on your Mac or Linux machine

```bash
curl -fsSL https://raw.githubusercontent.com/ishaquehassan/claude-remote-terminal/main/install.sh | bash
```

The installer handles everything:
- Detects your OS (macOS, Debian/Ubuntu, Arch, Fedora, WSL)
- Installs Python 3, `websockets`, and `tmux` if missing
- Optionally installs **Claude Code** (`@anthropic-ai/claude-code`) — includes Node.js if needed
- Sets up `/continue-remote` and `/remote-devices-logout` slash commands
- Creates a global `claude-remote` launcher
- **Starts the server immediately** after setup
- **Registers as a login item** — server auto-starts on every boot/login

**macOS** — LaunchAgent (`~/Library/LaunchAgents/com.xrlabs.claude-remote.plist`) with `KeepAlive: true`

**Linux** — systemd user service (`~/.config/systemd/user/claude-remote.service`) with `Restart=always`

No need to run anything manually — by the time the installer finishes, the server is already running.

### Step 2 — Install the app on your Android phone

Download `claude-remote-v1.4.0.apk` from [Releases](https://github.com/ishaquehassan/claude-remote-terminal/releases/latest) and install it.

---

## 🔁 Updating

Already installed? Just re-run the same installer:

```bash
curl -fsSL https://raw.githubusercontent.com/ishaquehassan/claude-remote-terminal/main/install.sh | bash
```

It re-downloads `server.py`, restarts the LaunchAgent (Mac) or systemd service (Linux), and re-copies the Claude slash commands. Your paired devices are not affected.

For the Android app — download the latest APK from [Releases](https://github.com/ishaquehassan/claude-remote-terminal/releases/latest) and install it over the existing one.

Open the app — it auto-scans your network and shows your Mac by name. Tap to connect.

**That's it.**

---

## 🔄 How It Works

```
1. Install server on Mac        →  curl ... | bash
         ↓                         (server starts automatically + login item registered)
2. Open app on phone            →  auto-scans network
         ↓
3. See your Mac by name         →  "Ishaq's MacBook Pro · 192.168.1.5"
         ↓
4. Tap Connect                  →  authenticated WebSocket PTY
         ↓
5. Tap "New Claude Session"     →  full Claude Code terminal on phone
         ↓
6. (Optional) /continue-remote  →  from Mac Claude session → jumps to phone
         ↓
7. (Optional) Tap laptop icon   →  session hands back to Mac's iTerm2
```

---

## 🔍 Auto-Discovery

When you open the app, it immediately scans your local network for running servers. No need to look up your IP address.

Each found server shows:
- **PC hostname** — e.g. `Ishaq-MacBook-Pro.local`
- **IP address** — e.g. `192.168.1.5`
- A **Connect** button — tap once to connect

If multiple people on the same network have the server running, you'll see all of them — pick the right one by name.

---

## 🔐 Device Pairing & Security

Claude Remote doesn't just connect — it authenticates. Every phone must be paired before it can access your terminal. No random device on your network can ever connect without your approval.

### First-time pairing flow

```
Phone opens app
       ↓
Auto-scans network → finds your Mac by name
       ↓
Taps Connect
       ↓
Server generates a 4-digit pairing code
       ↓
Mac automatically opens a browser page
  ┌─────────────────────────────────┐
  │                                 │
  │   Pair your device              │
  │                                 │
  │       8  4  2  7                │
  │                                 │
  │   ████████████░░░░  45s left    │
  │                                 │
  └─────────────────────────────────┘
       ↓
Phone shows 4-digit input screen
       ↓
User enters the code
       ↓
Server verifies → device saved to paired_devices.json
       ↓
Connected ✓  →  Sessions screen
```

### Every connection after that

```
Phone opens app
       ↓
Auto-scans → finds Mac
       ↓
Taps Connect
       ↓
Server recognizes device ID → connects instantly
       ↓
Sessions screen  (no code, no friction)
```

### Security details

- **Per-device IDs** — each phone has a unique device ID stored in `~/.remote-terminal/paired_devices.json`
- **Wrong code = retry** — entering the wrong code keeps the session alive, you can try again
- **Code expiry** — pairing codes expire automatically if unused within the time window
- **Auth token** — all WebSocket connections require the server auth token (set in `server.py`)
- **LAN only** — server binds to your local network, not exposed to the internet

### Revoking access

Lost your phone? Switching devices? Someone else on the network?

Run this in any Claude Code session on your Mac:

```
/remote-devices-logout
```

What happens instantly:
- Server wipes `~/.remote-terminal/paired_devices.json`
- Every connected phone receives a `force_logout` signal
- All phones are kicked to the server selection screen in real time
- Next connection requires a fresh pairing code

---

## ⚡ Claude Code Slash Commands

Claude Remote installs custom slash commands into Claude Code — type them directly in any Claude session on your Mac. No setup needed, the installer handles everything.

| Command | What it does |
|---------|-------------|
| `/continue-remote` | Push your current Claude session to your phone instantly |
| `/remote-devices-logout` | Kick all paired phones and clear device list |

---

### `/continue-remote`

Type it in any Claude Code session on your Mac. Your phone opens that exact session automatically — `claude --continue` resumes the full conversation from where you left off.

**How it works:**

1. You're deep in a Claude session on your Mac
2. You type `/continue-remote`
3. Claude runs `~/.claude/scripts/continue_remote.py`
4. Script broadcasts the session ID + working directory to your server
5. Your phone receives it and navigates directly to the terminal

**Manual install (if needed):**

```bash
cp commands/continue-remote.md ~/.claude/commands/
mkdir -p ~/.claude/scripts && cp scripts/continue_remote.py ~/.claude/scripts/
```

---

### `/remote-devices-logout`

Type it to instantly revoke access for all paired phones — useful before lending your Mac, changing networks, or rotating your auth token.

**How it works:**

1. Claude runs `~/.claude/scripts/remote_logout.py`
2. Script sends `logout_all_devices` to the local server
3. Server wipes `~/.remote-terminal/paired_devices.json`
4. Every connected phone receives a `force_logout` signal and is automatically redirected to the server selection screen

**Manual install (if needed):**

```bash
cp commands/remote-devices-logout.md ~/.claude/commands/
mkdir -p ~/.claude/scripts && cp scripts/remote_logout.py ~/.claude/scripts/
```

---

## 🏗️ Architecture

```
  +---------------------------------------------------------------+
  |                       YOUR COMPUTER                          |
  |                                                               |
  |  +----------+    +----------------------+    +-------------+  |
  |  |  iTerm2  |<-->|  Python WebSocket    |<-->|  Claude PTY |  |
  |  | (local)  |    |  Server  (asyncio)   |    |  (direct)   |  |
  |  +----------+    +----------------------+    +-------------+  |
  |                            |                                  |
  +----------------------------+----------------------------------+
                               |
                      WebSocket  ws://
                      LAN  (auto-discovered)
                               |
  +----------------------------+----------------------------------+
  |                    ANDROID PHONE                             |
  |                            |                                  |
  |         +------------------+------------------+              |
  |         |           Claude Remote             |              |
  |         |                                     |              |
  |         |  Auto-scan -> Server list -> Connect|              |
  |         |                                     |              |
  |         |  +-------------+ +--------------+   |              |
  |         |  |  Terminal   | | Sessions     |   |              |
  |         |  |  Emulator   | | + /continue  |   |              |
  |         |  +-------------+ +--------------+   |              |
  |         |                                     |              |
  |         |  +---------------------------------+ |              |
  |         |  | Tab  Ctrl+D  Esc  up dn lt rt  | |              |
  |         |  +---------------------------------+ |              |
  |         +-------------------------------------+              |
  +---------------------------------------------------------------+
```

---

## 🔧 Manual Setup

### Server

```bash
git clone https://github.com/ishaquehassan/claude-remote-terminal.git
cd claude-remote-terminal
pip3 install websockets
python3 server/server.py
```

### App (build from source)

```bash
cd app
flutter pub get
flutter build apk --release
```

---

## ⚙️ Configuration

Edit `server/server.py`:

```python
PORT = 8765
AUTH_TOKEN = "xrlabs-remote-terminal-2024"  # change this
```

---

## 🖥️ Platform Support

| Platform | Status | Notes |
|----------|--------|-------|
| macOS | ✅ Full | Primary dev platform, iTerm2 handoff |
| Ubuntu / Debian | ✅ Full | apt |
| Arch Linux | ✅ Full | pacman |
| Fedora / RHEL | ✅ Full | dnf |
| Windows (WSL2) | ✅ Supported | Run installer inside WSL |
| Windows (native) | ❌ | Use WSL |

---

## 📋 Requirements

**Server:** Python 3.10+, tmux, macOS or Linux

**App:** Android 6.0+ (API 23), same local network as server

---

## 📁 Project Structure

```
claude-remote-terminal/
├── server/
│   └── server.py                    # Python WebSocket PTY server
├── app/                             # Flutter Android app
│   └── lib/
├── commands/
│   ├── continue-remote.md           # /continue-remote slash command
│   └── remote-devices-logout.md    # /remote-devices-logout slash command
├── scripts/
│   ├── continue_remote.py           # /continue-remote script
│   └── remote_logout.py             # /remote-devices-logout script
├── test_history.py                  # ADB automation: session history persistence test
├── install.sh                       # One-command installer
├── start.sh                         # Quick server start
└── README.md
```

---

## 🧪 Testing

`test_history.py` is an ADB-driven automation script that verifies session history persists correctly across app kills.

**What it does:**
1. Launches the app fresh
2. Creates a new Claude session
3. Sends N random conversational prompts (mix of short / medium / long, different every run)
4. Kills the app
5. Relaunches and opens the same session
6. Verifies history is rendered — not blank, content matches before kill
7. Cleans up all sessions for a fresh next cycle

**Usage:**
```bash
python3 test_history.py                        # 1 cycle, 4 prompts
python3 test_history.py --cycles 3             # 3 full cycles
python3 test_history.py --cycles 2 --prompts 6 --output ./results
```

**Requirements:** ADB connected device (USB or wireless), server running locally.

---

## 📌 Planned — v1.5.0

> Full implementation details: [docs/qr-pairing-internet-plan.md](docs/qr-pairing-internet-plan.md)

- [ ] **QR Code Pairing** — Replace 4-digit PIN with QR scanner. Mac browser auto-opens QR, phone scans it, paired instantly. No manual code entry.
- [ ] **Auto-close browser page** — Browser pairing page detects successful pair via WebSocket and calls `window.close()` automatically. Shows ✓ success card for 1.5s first.
- [ ] **Tailscale IP in QR** — Server embeds its Tailscale IP (`100.x.x.x`) inside the QR. App saves it alongside local IP.
- [ ] **Auto internet fallback** — App tries local IP first, if it fails (outside home network) automatically falls back to Tailscale IP. Zero manual input ever again.

---

## 🚢 Release Checklist

Before pushing a new version:

1. Bump `SERVER_VERSION` in `server/server.py` — must match the GitHub Release tag exactly (no `v` prefix)
2. Bump `version` in `app/pubspec.yaml` (e.g. `1.5.0+5`)
3. Update `CHANGELOG.md`
4. Build APK: `flutter build apk --release` inside `app/`
5. Commit + push
6. Create GitHub Release with the matching tag (e.g. `v1.5.0`) and attach the APK

> **Why `SERVER_VERSION` matters:** the self-update feature compares this value against the latest GitHub Release tag. If it's not bumped, users will see a false "update available" banner forever — and triggering self_update will just re-download the same file.

---

## 📄 License

MIT — see [LICENSE](LICENSE)

---

<div align="center">

Built by [ishaquehassan](https://github.com/ishaquehassan) · Star the repo if it's useful ⭐

</div>
