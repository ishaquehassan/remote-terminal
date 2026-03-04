# Changelog

All notable changes to Claude Remote are documented here.

---

## [1.4.0] — 2026-03-04

### Added
- **Session history persistence on resume** — Re-opening a session after app kill now shows the full previous terminal state. Server keeps a 100 KB rolling scrollback buffer per session and replays it instantly on re-attach. Works for both Claude and shell sessions.
- **`test_history.py` — ADB automation test script** — Automated session history persistence tester. Launches app, creates a Claude session, sends N dynamic conversational prompts (randomised mix of short / medium / long each run), kills app, relaunches, reopens session, and verifies history is rendered correctly. Smart response detection via PNG size stability polling (no fixed sleeps). Cleans up all sessions after each cycle for a clean next run. Colourful terminal output + JSON report + per-step screenshots.
- **Self-update** — Server checks GitHub Releases on startup and broadcasts `update_available` to all connected clients if a newer version exists. Supports `check_update` (manual check via WebSocket) and `self_update` (download latest `server.py`, replace self, restart via LaunchAgent/systemd) commands. Server version now exposed in `info_response` and startup log.

### Fixed
- **Blank terminal on session resume** — After app kill + relaunch, tapping an existing session showed a blank terminal. Root cause: Flutter's `Terminal` object is in-memory and lost on kill; server's SIGWINCH-only repaint was insufficient when Claude is idle. Fixed by server-side scrollback replay on `attach`.

---

## [1.3.0] — 2026-03-03

### Added
- **Voice input via Groq Whisper** — mic button in extra keys bar, tap to record, tap again to send. Auto-types transcribed text + Enter into terminal. Supports English and Roman Urdu.

---

## [1.2.0] — 2026-03-03

### Added
- **Device pairing system** — 4-digit code pairing on first connect. Mac auto-opens styled browser page with countdown timer. Paired devices connect instantly on subsequent launches.
- **`/remote-devices-logout` slash command** — kick all paired phones from Claude Code, clears paired_devices.json, all connected phones get force_logout signal in real time.
- **Auto-connect** — app auto-connects to last saved server on launch, skips scan screen.
- **Change server button** — swap icon in sessions header to switch servers without restarting.
- **PC name subtitle** — sessions screen header shows connected server hostname.
- **Auto-start on login** — macOS LaunchAgent + Linux systemd service. Server starts automatically on boot, restarts on crash.
- **Launcher renamed** — `remote-terminal` → `claude-remote`.

### Fixed
- Navigation race conditions — moved all navigation to `_onServiceChange()` listener instead of `build()`.
- Duplicate PairingScreen pushes on wrong code entry — `_pairingPushed` flag.
- Wrong pairing code error — `pending_pairs` entry no longer deleted on wrong code, only on expiry.
- Cold start reconnect — `isPairRequired` on SessionsScreen now navigates to ConnectScreen correctly.

---

## [1.1.0] — 2026-03-02

### Added
- Auto-discovery — app scans local network on startup, shows servers by PC hostname.
- Session rename — long tap session card to name it.
- EN/UR language toggle in header.
- iTerm2 handoff — tap laptop icon to move session to Mac terminal.
- Terminal.app fallback — if iTerm2 not installed, uses Terminal.app automatically.
- Linux terminal fallback chain — gnome-terminal → xterm → konsole → xfce4-terminal.

---

## [1.0.0] — 2026-03-01

### Added
- Initial release.
- WebSocket PTY server (Python) on Mac/Linux.
- Flutter Android app with full terminal emulation (xterm).
- Claude Code sessions with `--continue` support.
- `/continue-remote` slash command — session jumps from Mac to phone.
- Auto-reconnect on connection drop.
- Extra keys bar — Tab, Ctrl+D, Esc, arrow keys.
- One-command installer (`install.sh`).
