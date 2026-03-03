```
██████╗ ███████╗███╗   ███╗ ██████╗ ████████╗███████╗
██╔══██╗██╔════╝████╗ ████║██╔═══██╗╚══██╔══╝██╔════╝
██████╔╝█████╗  ██╔████╔██║██║   ██║   ██║   █████╗
██╔══██╗██╔══╝  ██║╚██╔╝██║██║   ██║   ██║   ██╔══╝
██║  ██║███████╗██║ ╚═╝ ██║╚██████╔╝   ██║   ███████╗
╚═╝  ╚═╝╚══════╝╚═╝     ╚═╝ ╚═════╝   ╚═╝   ╚══════╝

████████╗███████╗██████╗ ███╗   ███╗██╗███╗   ██╗ █████╗ ██╗
╚══██╔══╝██╔════╝██╔══██╗████╗ ████║██║████╗  ██║██╔══██╗██║
   ██║   █████╗  ██████╔╝██╔████╔██║██║██╔██╗ ██║███████║██║
   ██║   ██╔══╝  ██╔══██╗██║╚██╔╝██║██║██║╚██╗██║██╔══██║██║
   ██║   ███████╗██║  ██║██║ ╚═╝ ██║██║██║ ╚████║██║  ██║███████╗
   ╚═╝   ╚══════╝╚═╝  ╚═╝╚═╝     ╚═╝╚═╝╚═╝  ╚═══╝╚═╝  ╚═╝╚══════╝
```

<div align="center">

[![Platform](https://img.shields.io/badge/platform-macOS%20%7C%20Linux%20%7C%20Android-blue?style=flat-square&logo=apple)](https://github.com/ishaquehassan/claude-remote-terminal)
[![Python](https://img.shields.io/badge/python-3.10%2B-yellow?style=flat-square&logo=python)](https://www.python.org/)
[![Flutter](https://img.shields.io/badge/flutter-3.x-54C5F8?style=flat-square&logo=flutter)](https://flutter.dev/)
[![License: MIT](https://img.shields.io/badge/license-MIT-green?style=flat-square)](LICENSE)
[![WebSocket](https://img.shields.io/badge/protocol-WebSocket-orange?style=flat-square)](https://developer.mozilla.org/en-US/docs/Web/API/WebSockets_API)
[![tmux](https://img.shields.io/badge/backed%20by-tmux-1BB91F?style=flat-square)](https://github.com/tmux/tmux)

**Control your Mac or Linux terminal from your Android phone — over WebSocket, in real time.**

[Quick Install](#-quick-install) · [Features](#-features) · [Architecture](#-architecture) · [/continue-remote](#-continue-remote) · [Manual Setup](#-manual-setup)

</div>

---

## What Is This?

Remote Terminal turns your Android phone into a full terminal client for your Mac or Linux machine. A lightweight Python WebSocket server runs on your computer, exposing real PTY sessions to a Flutter app on your phone. Shell sessions are backed by **tmux** — so whatever you start on your phone, you can pick up exactly where you left off in iTerm2 on your desktop, and vice versa. Claude Code sessions run as direct PTY with `--continue` support, letting you hand off AI coding sessions between devices seamlessly.

---

## ✨ Features

- 🔌 **WebSocket PTY** — Full terminal emulation over WebSocket. Real PTY, real signals, real colors.
- 🧠 **tmux-backed shell sessions** — Start a session on your phone, continue it on your Mac. Same state, same history, same everything.
- 🤖 **Claude Code integration** — Run `claude --continue` sessions directly from your phone. Resumable AI sessions across devices.
- 📲 **`/continue-remote` slash command** — Inside Claude Code on your Mac, run `/continue-remote` and your active session instantly appears on your phone.
- 🔄 **Auto-reconnect** — The Flutter app automatically reconnects if the connection drops. Never lose context.
- 🏷️ **Session rename** — Name your tmux sessions from the app for easy organization.
- 🌐 **Language toggle** — Switch the app UI between English and Urdu (Roman) on the fly.
- ⌨️ **Extra keys bar** — Tap-accessible special keys: Tab, Ctrl, Escape, arrow keys, and more — built for mobile use.
- 🍎 **iTerm2 handoff** — Shell sessions seamlessly hand off to iTerm2 via `tmux attach`. Claude sessions hand off via `claude --continue`.
- 🖥️ **Cross-platform server** — macOS (Homebrew), Linux (apt / pacman / dnf), Windows via WSL.
- ⚡ **Zero-hang async core** — All subprocess calls wrapped in `asyncio.to_thread()` — the event loop never blocks.

---

## 📸 Demo

> Screenshots and screen recordings are available in the [`/screenshots`](screenshots/) directory.

The Flutter app connects to your server over your local network (or via SSH tunnel for remote access). You get a full terminal with proper color support, resize handling, and session management — all from your phone.

---

## 🚀 Quick Install

### Step 1 — Run the installer on your Mac or Linux machine

```bash
curl -fsSL https://raw.githubusercontent.com/ishaquehassan/claude-remote-terminal/main/install.sh | bash
```

That's it. The installer will:
- Detect your OS (macOS, Debian/Ubuntu, Arch, Fedora, WSL)
- Install Python 3, `websockets`, and `tmux` if missing
- Optionally install **Claude Code** (`@anthropic-ai/claude-code`) — includes Node.js if needed
- Set up the `/continue-remote` slash command for Claude Code
- Print your local IP and the command to start the server

### Step 2 — Install the APK on your Android phone

Download the latest APK from [Releases](https://github.com/ishaquehassan/claude-remote-terminal/releases) and install it on your phone.

Open the app, enter your computer's local IP address (printed by the installer), and connect.

**That's the entire setup.**

---

## 🔧 Manual Setup

If you prefer to clone and run manually:

### Prerequisites

| Tool | Version | Required For |
|------|---------|-------------|
| Python | 3.10+ | Server runtime |
| pip | latest | Python deps |
| tmux | any | Shell sessions |
| Flutter | 3.x | Building the app |

### Server Setup

```bash
# Clone the repo
git clone https://github.com/ishaquehassan/claude-remote-terminal.git
cd remote-terminal

# Install Python dependencies
pip3 install -r server/requirements.txt

# Run the server
python3 server/server.py
```

### App Setup

```bash
cd app

# Get Flutter dependencies
flutter pub get

# Run on connected Android device
flutter run

# Or build APK
flutter build apk --release
```

---

## ⚙️ Configuration

Open `server/server.py` and edit the top-level constants:

```python
PORT = 8765                            # WebSocket port — change if 8765 is taken
AUTH_TOKEN = "xrlabs-remote-terminal-2024"  # Change this to something secret
```

In the Flutter app, enter the same IP, port, and token in the connection screen.

For remote access over the internet, run the server behind an SSH tunnel:

```bash
# On your phone, tunnel via SSH to your Mac
ssh -L 8765:localhost:8765 user@your-mac-ip
# Then connect the app to localhost:8765
```

---

## 🤖 /continue-remote

`/continue-remote` is a custom Claude Code slash command that hands off your current Claude session to your phone in one step.

### How It Works

1. You are working in a Claude Code session on your Mac
2. You type `/continue-remote` in Claude Code
3. Claude executes `python3 ~/.claude/scripts/continue_remote.py`
4. The script broadcasts the current session info (cwd, session ID) to all connected WebSocket clients
5. Your phone receives the signal and opens the Claude session automatically — with `--continue`, resuming the exact conversation

### Setup

The installer copies the command definition into `~/.claude/commands/continue-remote.md` and the script into `~/.claude/scripts/continue_remote.py` automatically.

If you installed manually:

```bash
# Copy the command definition
cp commands/continue-remote.md ~/.claude/commands/

# Copy the script
mkdir -p ~/.claude/scripts
cp scripts/continue_remote.py ~/.claude/scripts/
```

### Usage

```
# Inside any Claude Code session on your Mac:
/continue-remote
```

Your phone receives the session within seconds. Open the Remote Terminal app and the Claude session is already there, resumable with full context.

---

## 🏗️ Architecture

```
┌─────────────────────────────────────────────────────────────────┐
│                         YOUR COMPUTER                           │
│                                                                 │
│   ┌──────────┐    ┌──────────────────────┐    ┌─────────────┐  │
│   │  iTerm2  │◄──►│   tmux session(s)    │◄──►│    Shell    │  │
│   │  (local) │    └──────────────────────┘    │  (zsh/bash) │  │
│   └──────────┘              ▲                 └─────────────┘  │
│                             │                                   │
│   ┌──────────┐    ┌─────────┴────────────┐    ┌─────────────┐  │
│   │  Claude  │◄──►│  Python WebSocket    │◄──►│  Claude PTY │  │
│   │ (local)  │    │  Server (asyncio)    │    │  (direct)   │  │
│   └──────────┘    └──────────────────────┘    └─────────────┘  │
│                             ▲                                   │
└─────────────────────────────│───────────────────────────────────┘
                              │ WebSocket (ws://)
                              │ LAN / SSH tunnel
┌─────────────────────────────│───────────────────────────────────┐
│                    ANDROID PHONE                                │
│                             │                                   │
│              ┌──────────────▼──────────────┐                   │
│              │     Flutter App             │                   │
│              │                             │                   │
│              │  ┌─────────┐ ┌───────────┐  │                   │
│              │  │Terminal │ │ Sessions  │  │                   │
│              │  │Emulator │ │  Manager  │  │                   │
│              │  └─────────┘ └───────────┘  │                   │
│              │                             │                   │
│              │  ┌─────────────────────┐    │                   │
│              │  │   Extra Keys Bar    │    │                   │
│              │  │ Tab Ctrl Esc ↑↓←→  │    │                   │
│              │  └─────────────────────┘    │                   │
│              └─────────────────────────────┘                   │
└─────────────────────────────────────────────────────────────────┘

Session Types
─────────────
Shell session  →  spawned inside tmux  →  persistent, resumable from iTerm2
Claude session →  direct PTY, no tmux  →  resumable via `claude --continue`
```

### Message Protocol

All communication is JSON over WebSocket:

```jsonc
// Client → Server: create session
{ "type": "create_session", "cmd": "zsh", "rows": 40, "cols": 100 }

// Client → Server: input
{ "type": "input", "session_id": "abc123", "data": "ls -la\r" }

// Client → Server: resize
{ "type": "resize", "session_id": "abc123", "rows": 50, "cols": 120 }

// Server → Client: output
{ "type": "output", "session_id": "abc123", "data": "..." }

// Server → Client: session list
{ "type": "sessions", "sessions": [...] }
```

---

## 🖥️ Platform Support

| Platform | Status | Package Manager | Notes |
|----------|--------|----------------|-------|
| macOS | ✅ Full support | Homebrew | Primary dev platform |
| Ubuntu / Debian | ✅ Full support | apt | Tested on 22.04+ |
| Arch Linux | ✅ Full support | pacman | |
| Fedora / RHEL | ✅ Full support | dnf | |
| Windows (WSL2) | ✅ Supported | apt (inside WSL) | Run installer inside WSL terminal |
| Windows (native) | ❌ Not supported | — | Use WSL |

---

## 📋 Requirements

### Server (your computer)

- Python 3.10 or higher
- `websockets` >= 12.0 (installed automatically)
- `tmux` (installed automatically by the installer)
- macOS or Linux (or WSL on Windows)

### Client (your phone)

- Android 6.0 (API 23) or higher
- Connected to the same local network as the server, or via SSH tunnel

### Building the App (optional)

- Flutter 3.x SDK
- Android SDK / Android Studio
- A connected Android device or emulator

---

## 📁 Project Structure

```
remote-terminal/
├── server/
│   ├── server.py          # Python WebSocket PTY server
│   └── requirements.txt   # Python dependencies (websockets)
├── app/                   # Flutter Android app
│   ├── lib/               # Dart source code
│   ├── android/           # Android-specific config
│   └── pubspec.yaml       # Flutter dependencies
├── commands/
│   └── continue-remote.md # Claude Code slash command definition
├── scripts/
│   └── continue_remote.py # Script called by /continue-remote
├── setup.sh               # Manual setup script
├── start.sh               # Quick start script
└── README.md
```

---

## 🤝 Contributing

Pull requests are welcome. For major changes, open an issue first to discuss what you want to change.

1. Fork the repo
2. Create a feature branch (`git checkout -b feature/your-feature`)
3. Commit your changes
4. Push to the branch and open a Pull Request

---

## 📄 License

MIT License — see [LICENSE](LICENSE) for details.

---

<div align="center">

Built by [ishaquehassan](https://github.com/ishaquehassan) · Star the repo if it's useful ⭐

</div>
