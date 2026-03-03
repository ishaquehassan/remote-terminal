<div align="center">

<img src="app/android/app/src/main/res/mipmap-xxxhdpi/ic_launcher.png" width="120" alt="Claude Remote" />

## Claude Remote

[![Platform](https://img.shields.io/badge/platform-macOS%20%7C%20Linux%20%7C%20Android-orange?style=flat-square&logo=apple)](https://github.com/ishaquehassan/claude-remote-terminal)
[![Python](https://img.shields.io/badge/python-3.10%2B-yellow?style=flat-square&logo=python)](https://www.python.org/)
[![Flutter](https://img.shields.io/badge/flutter-3.x-54C5F8?style=flat-square&logo=flutter)](https://flutter.dev/)
[![License: MIT](https://img.shields.io/badge/license-MIT-green?style=flat-square)](LICENSE)
[![Claude Code](https://img.shields.io/badge/built%20for-Claude%20Code-E07845?style=flat-square)](https://claude.ai/download)

**Claude Code on your Android phone — resume AI coding sessions anywhere, over WebSocket PTY.**

[Quick Install](#-quick-install) · [Features](#-features) · [Slash Commands](#-claude-code-slash-commands) · [Architecture](#-architecture) · [Manual Setup](#-manual-setup)

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
- 🍎 **iTerm2 handoff** — Switch a Claude session back to your Mac's iTerm2 mid-conversation.
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
- Sets up the `/continue-remote` slash command
- Creates a global `claude-remote` launcher

Then start the server:

```bash
claude-remote
```

### Step 2 — Install the app on your Android phone

Download `claude-remote-v1.0.0.apk` from [Releases](https://github.com/ishaquehassan/claude-remote-terminal/releases/latest) and install it.

Open the app — it auto-scans your network and shows your Mac by name. Tap to connect.

**That's it.**

---

## 🔄 How It Works

```
1. Install server on Mac        →  curl ... | bash
         ↓
2. Start server                 →  claude-remote
         ↓
3. Open app on phone            →  auto-scans network
         ↓
4. See your Mac by name         →  "Ishaq's MacBook Pro · 192.168.1.5"
         ↓
5. Tap Connect                  →  authenticated WebSocket PTY
         ↓
6. Tap "New Claude Session"     →  full Claude Code terminal on phone
         ↓
7. (Optional) /continue-remote  →  from Mac Claude session → jumps to phone
         ↓
8. (Optional) Tap laptop icon   →  session hands back to Mac's iTerm2
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
├── install.sh                       # One-command installer
├── start.sh                         # Quick server start
└── README.md
```

---

## 📄 License

MIT — see [LICENSE](LICENSE)

---

<div align="center">

Built by [ishaquehassan](https://github.com/ishaquehassan) · Star the repo if it's useful ⭐

</div>
