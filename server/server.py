#!/usr/bin/env python3
"""
Remote Terminal WebSocket Server
Python 3.13 + websockets 16 compatible

Shell sessions  → tmux-backed  → iTerm 'tmux attach' = same exact state
Claude sessions → direct PTY   → iTerm 'claude --continue' = resume conversation

HANG FIX: all subprocess calls are wrapped in asyncio.to_thread() so they
never block the event loop.
"""

import asyncio
import websockets
import pty
import os
import sys
import shutil
import platform
import select as select_module
import json
import fcntl
import termios
import struct
import subprocess
import threading
import uuid
import socket as socket_module
from collections import defaultdict
import random
import time
import urllib.request
import tempfile

PORT = 8765
AUTH_TOKEN = "xrlabs-remote-terminal-2024"
SCROLLBACK_SIZE = 100 * 1024  # 100 KB per session
SERVER_VERSION = "1.4.0"
GITHUB_REPO = "ishaquehassan/claude-remote-terminal"

# tmux path — auto-detect so it works on Mac (brew) and Linux (apt)
TMUX = shutil.which("tmux") or "tmux"
IS_MAC = platform.system() == "Darwin"

sessions = {}
client_queues = defaultdict(list)
all_client_queues = []  # one queue per connected WebSocket — used for global broadcasts

# ── Pairing ────────────────────────────────────────────────────────────────────
PAIRED_FILE = os.path.expanduser("~/.remote-terminal/paired_devices.json")

def load_paired():
    try:
        with open(PAIRED_FILE) as f:
            return set(json.load(f))
    except Exception:
        return set()

def save_paired(devices):
    try:
        os.makedirs(os.path.dirname(PAIRED_FILE), exist_ok=True)
        with open(PAIRED_FILE, "w") as f:
            json.dump(list(devices), f)
    except Exception:
        pass

paired_devices = load_paired()
pending_pairs  = {}  # device_id -> {"code": "1234", "expires": float}


# ── Self-update helpers ────────────────────────────────────────────────────────

def version_gt(a: str, b: str) -> bool:
    """Return True if version string a > b."""
    try:
        return tuple(int(x) for x in a.split(".")) > tuple(int(x) for x in b.split("."))
    except Exception:
        return False


def _fetch_latest_version() -> str:
    """Sync: fetch latest release tag from GitHub API. Returns version string or ''."""
    url = f"https://api.github.com/repos/{GITHUB_REPO}/releases/latest"
    req = urllib.request.Request(url, headers={"User-Agent": "claude-remote-server"})
    with urllib.request.urlopen(req, timeout=10) as resp:
        data = json.loads(resp.read())
    return data.get("tag_name", "").lstrip("v")


def _download_server() -> bytes:
    """Sync: download latest server.py from main branch. Returns raw bytes."""
    url = f"https://raw.githubusercontent.com/{GITHUB_REPO}/main/server/server.py"
    req = urllib.request.Request(url, headers={"User-Agent": "claude-remote-server"})
    with urllib.request.urlopen(req, timeout=30) as resp:
        return resp.read()


async def _startup_update_check():
    """Background task: check for update ~8s after server start, broadcast if available."""
    await asyncio.sleep(8)
    try:
        latest = await asyncio.to_thread(_fetch_latest_version)
        if version_gt(latest, SERVER_VERSION):
            print(f"\033[1;33m[updater] New version available: v{latest} (current: v{SERVER_VERSION})\033[0m")
            msg = json.dumps({"type": "update_available", "current": SERVER_VERSION, "latest": latest})
            for q in all_client_queues:
                q.put_nowait(msg)
        else:
            print(f"[updater] Up to date (v{SERVER_VERSION})")
    except Exception as e:
        print(f"[updater] Startup check failed: {e}")


# ─── PTY helpers ──────────────────────────────────────────────────────────────

def set_winsize(fd, rows, cols):
    try:
        fcntl.ioctl(fd, termios.TIOCSWINSZ, struct.pack("HHHH", rows, cols, 0, 0))
    except Exception:
        pass


# ─── Sync spawn functions (called via to_thread) ──────────────────────────────

def spawn_session(cmd=None, rows=24, cols=80, cwd=None):
    if cmd is None:
        cmd = os.environ.get("SHELL", "/bin/zsh")
    if "claude" in cmd:
        return _spawn_claude(cmd, rows, cols, cwd=cwd)
    else:
        return _spawn_shell(cmd, rows, cols, cwd=cwd)


def _spawn_claude(cmd, rows, cols, cwd=None):
    """Direct PTY — no tmux. Claude --continue used for iTerm."""
    master_fd, slave_fd = pty.openpty()
    set_winsize(master_fd, rows, cols)

    env = os.environ.copy()
    env["TERM"] = "xterm-256color"
    env["COLORTERM"] = "truecolor"
    env.pop("CLAUDECODE", None)
    env.pop("CLAUDE_CODE_ENTRYPOINT", None)

    # cwd priority: client-provided > ~/Desktop > ~
    if cwd and os.path.isdir(cwd):
        pass  # use as-is
    else:
        desktop = os.path.expanduser("~/Desktop")
        cwd = desktop if os.path.isdir(desktop) else os.path.expanduser("~")

    # Support claude --continue flag
    claude_args = ["--continue"] if "--continue" in str(cmd) else []
    proc = subprocess.Popen(
        ["env", "-u", "CLAUDECODE", "-u", "CLAUDE_CODE_ENTRYPOINT", "claude"] + claude_args,
        stdin=slave_fd, stdout=slave_fd, stderr=slave_fd,
        close_fds=True, start_new_session=True, env=env, cwd=cwd,
    )
    os.close(slave_fd)

    sid = str(uuid.uuid4())[:8]
    sessions[sid] = {
        "proc": proc, "fd": master_fd, "cmd": cmd,
        "rows": rows, "cols": cols, "tmux": None, "iterm_tab": None,
        "scrollback": bytearray(),
    }
    print(f"[server] Claude session {sid} spawned pid={proc.pid}")
    return sid


def _spawn_shell(cmd, rows, cols, cwd=None):
    """tmux-backed shell — same state continuable from iTerm."""
    env = os.environ.copy()
    env["TERM"] = "xterm-256color"
    env["COLORTERM"] = "truecolor"

    if cwd and os.path.isdir(cwd):
        pass  # use as-is
    else:
        desktop = os.path.expanduser("~/Desktop")
        cwd = desktop if os.path.isdir(desktop) else os.path.expanduser("~")

    sid = str(uuid.uuid4())[:8]
    tmux_name = f"rt_{sid}"

    subprocess.run(
        [TMUX, "new-session", "-d", "-s", tmux_name,
         "-x", str(cols), "-y", str(rows)],
        env=env, cwd=cwd, stderr=subprocess.DEVNULL,
    )
    subprocess.run([TMUX, "set-option", "-t", tmux_name, "status", "off"],
                   env=env, stderr=subprocess.DEVNULL)
    subprocess.run([TMUX, "set-option", "-t", tmux_name, "mouse", "off"],
                   env=env, stderr=subprocess.DEVNULL)
    subprocess.run([TMUX, "set-option", "-t", tmux_name, "window-size", "manual"],
                   env=env, stderr=subprocess.DEVNULL)

    master_fd, slave_fd = pty.openpty()
    set_winsize(master_fd, rows, cols)
    phone_tty = os.ttyname(slave_fd)  # capture before closing

    proc = subprocess.Popen(
        [TMUX, "attach-session", "-t", tmux_name],
        stdin=slave_fd, stdout=slave_fd, stderr=slave_fd,
        close_fds=True, start_new_session=True, env=env, cwd=cwd,
    )
    os.close(slave_fd)

    sessions[sid] = {
        "proc": proc, "fd": master_fd, "cmd": cmd,
        "rows": rows, "cols": cols, "tmux": tmux_name,
        "iterm_tab": None, "phone_tty": phone_tty,
        "scrollback": bytearray(),
    }
    print(f"[server] Shell session {sid} spawned tmux={tmux_name} pid={proc.pid}")
    return sid


def tmux_resize(tmux_name, cols, rows):
    try:
        subprocess.run(
            [TMUX, "resize-window", "-t", tmux_name,
             "-x", str(cols), "-y", str(rows)],
            stderr=subprocess.DEVNULL,
        )
    except Exception:
        pass


def tmux_cwd(tmux_name):
    """Get current pane path from tmux."""
    try:
        out = subprocess.check_output(
            [TMUX, "display-message", "-p", "-t", tmux_name, "#{pane_current_path}"],
            stderr=subprocess.DEVNULL,
        ).decode().strip()
        return out if out else None
    except Exception:
        return None


def tmux_list_clients(tmux_name):
    """List tty paths of all attached clients for a tmux session."""
    try:
        out = subprocess.check_output(
            [TMUX, "list-clients", "-t", tmux_name, "-F", "#{client_tty}"],
            stderr=subprocess.DEVNULL,
        ).decode().strip()
        return [line for line in out.splitlines() if line]
    except Exception:
        return []


def tmux_detach_client(tty):
    """Detach a specific tmux client by its tty path."""
    try:
        subprocess.run(
            [TMUX, "detach-client", "-t", tty],
            stderr=subprocess.DEVNULL,
        )
    except Exception:
        pass


def get_claude_cwd(session):
    """Get CWD of a direct PTY (claude) session via lsof."""
    try:
        proc = session["proc"]
        children = subprocess.check_output(
            ["pgrep", "-P", str(proc.pid)],
            stderr=subprocess.DEVNULL,
        ).decode().strip().split()
        target_pid = children[0] if children else str(proc.pid)
        lsof_out = subprocess.check_output(
            ["lsof", "-p", target_pid, "-a", "-d", "cwd", "-Fn"],
            stderr=subprocess.DEVNULL,
        ).decode()
        return next(
            (l[1:] for l in lsof_out.splitlines() if l.startswith("n")),
            None,
        )
    except Exception:
        return None


def cleanup_session(sid):
    session = sessions.pop(sid, None)
    if not session:
        return

    # 1. Kill process FIRST — this closes the slave PTY which sends EIO to
    #    the reader thread, letting it exit os.read() cleanly before we
    #    close the master fd. Reversing this order causes macOS PTY deadlock.
    try:
        session["proc"].kill()
        session["proc"].wait(timeout=3)
    except Exception:
        pass

    # 2. Kill tmux session (for shell sessions)
    tmux_name = session.get("tmux")
    if tmux_name:
        try:
            subprocess.run(
                [TMUX, "kill-session", "-t", tmux_name],
                stderr=subprocess.DEVNULL, timeout=5,
            )
        except Exception:
            pass

    # 3. Close master fd AFTER proc is dead — safe now
    try:
        os.close(session["fd"])
    except Exception:
        pass

    client_queues.pop(sid, None)
    print(f"[server] Session {sid} cleaned up")


def open_iterm(shell_cmd, tab_name):
    """Open a terminal window/tab and run shell_cmd. Mac uses iTerm2 or Terminal.app, Linux uses best available."""
    if IS_MAC:
        apple_cmd = shell_cmd.replace('\\', '\\\\').replace('"', '\\"')
        safe_name = tab_name.replace('"', '\\"')
        # Check if iTerm2 is installed
        iterm_installed = os.path.exists("/Applications/iTerm.app") or \
                          os.path.exists(os.path.expanduser("~/Applications/iTerm.app"))
        if iterm_installed:
            script = f"""
tell application "iTerm2"
    activate
    if (count of windows) = 0 then
        create window with default profile
    end if
    tell current window
        create tab with default profile
        tell current session of current tab
            set name to "{safe_name}"
            write text "{apple_cmd}"
        end tell
    end tell
end tell
"""
        else:
            # Fallback: Terminal.app (always available on macOS)
            script = f"""
tell application "Terminal"
    activate
    do script "{apple_cmd}"
end tell
"""
        subprocess.Popen(["osascript", "-e", script])
    else:
        # Linux: try common terminal emulators
        for term, args in [
            ("gnome-terminal", ["--", "bash", "-c", f"{shell_cmd}; exec bash"]),
            ("xterm",          ["-e", f"{shell_cmd}"]),
            ("konsole",        ["-e", f"{shell_cmd}"]),
            ("xfce4-terminal", ["-e", f"{shell_cmd}"]),
            ("xterm",          ["-e", "bash", "-c", f"{shell_cmd}; exec bash"]),
        ]:
            if shutil.which(term):
                subprocess.Popen([term] + args)
                return
        print(f"[server] No terminal emulator found. Run manually: {shell_cmd}")


def sessions_list():
    return [{"id": s, "cmd": v["cmd"]} for s, v in sessions.items()]


# ── Pairing browser page ───────────────────────────────────────────────────────

def open_pair_page(code: str):
    """Write a styled HTML file and open it in the default browser."""
    digit_boxes = "\n".join(
        f'<div class="digit">{d}</div>' for d in code
    )
    html = f"""<!DOCTYPE html>
<html lang="en">
<head>
<meta charset="UTF-8">
<meta name="viewport" content="width=device-width, initial-scale=1">
<title>Claude Remote — Pair Device</title>
<style>
  * {{ margin:0; padding:0; box-sizing:border-box; }}
  body {{
    background: #0D0B09;
    font-family: -apple-system, BlinkMacSystemFont, 'SF Pro Display', 'Helvetica Neue', sans-serif;
    display: flex; align-items: center; justify-content: center;
    min-height: 100vh; color: #fff;
  }}
  .card {{
    text-align: center;
    padding: 52px 48px;
    background: #13100D;
    border: 1px solid #2A1E0F;
    border-radius: 28px;
    box-shadow: 0 32px 80px rgba(0,0,0,.6), 0 0 0 1px rgba(224,120,69,.06);
    max-width: 480px; width: 100%;
  }}
  .logo {{
    width: 68px; height: 68px;
    background: linear-gradient(135deg, #E07845 0%, #BF5530 100%);
    border-radius: 20px;
    display: flex; align-items: center; justify-content: center;
    margin: 0 auto 24px;
    box-shadow: 0 8px 28px rgba(224,120,69,.35);
  }}
  h1 {{ font-size: 26px; font-weight: 700; letter-spacing: -.4px; margin-bottom: 8px; }}
  .sub {{ color: #6B7280; font-size: 14px; margin-bottom: 40px; line-height: 1.5; }}
  .digits {{ display: flex; gap: 14px; justify-content: center; margin-bottom: 32px; }}
  .digit {{
    width: 82px; height: 100px;
    background: #1A1510;
    border: 2px solid #E07845;
    border-radius: 18px;
    display: flex; align-items: center; justify-content: center;
    font-size: 50px; font-weight: 700;
    font-family: 'Courier New', 'Menlo', monospace;
    color: #fff;
    box-shadow: 0 0 28px rgba(224,120,69,.18), inset 0 1px 0 rgba(255,255,255,.04);
    animation: popIn .4s cubic-bezier(.34,1.56,.64,1) both;
  }}
  .digit:nth-child(1) {{ animation-delay: .05s; }}
  .digit:nth-child(2) {{ animation-delay: .12s; }}
  .digit:nth-child(3) {{ animation-delay: .19s; }}
  .digit:nth-child(4) {{ animation-delay: .26s; }}
  @keyframes popIn {{
    from {{ opacity:0; transform: scale(.6) translateY(8px); }}
    to   {{ opacity:1; transform: scale(1) translateY(0); }}
  }}
  .timer-row {{ color: #6B7280; font-size: 13px; margin-bottom: 28px; }}
  #timer {{ color: #E07845; font-weight: 600; font-variant-numeric: tabular-nums; }}
  .progress-wrap {{
    height: 4px; background: #1F1A15; border-radius: 99px;
    margin-bottom: 28px; overflow: hidden;
  }}
  #progress {{
    height: 100%; background: #E07845; border-radius: 99px;
    width: 100%; transition: width 1s linear;
  }}
  .hint {{
    background: #1A1510; border: 1px solid #2A1E0F;
    border-radius: 14px; padding: 16px 20px;
    font-size: 13px; color: #9CA3AF; line-height: 1.65;
  }}
  .hint strong {{ color: #E07845; }}
  .expired {{
    display: none; color: #EF4444; font-size: 14px;
    font-weight: 600; margin-top: 20px;
  }}
  .paired {{
    display: none; color: #4ADE80; font-size: 14px;
    font-weight: 600; margin-top: 20px;
  }}
</style>
</head>
<body>
<div class="card">
  <div class="logo">
    <svg width="32" height="32" viewBox="0 0 24 24" fill="none" xmlns="http://www.w3.org/2000/svg">
      <path d="M12 2L13.8 8.2L20 7L15.8 11.8L18 18L12 14.8L6 18L8.2 11.8L4 7L10.2 8.2L12 2Z"
            fill="white" stroke="white" stroke-width=".5" stroke-linejoin="round"/>
    </svg>
  </div>
  <h1>Pair New Device</h1>
  <p class="sub">A new phone is trying to connect.<br>Enter this code on your phone to allow access.</p>
  <div class="digits">
{digit_boxes}
  </div>
  <div class="progress-wrap"><div id="progress"></div></div>
  <div class="timer-row">Expires in <span id="timer">2:00</span></div>
  <div class="hint">
    Open <strong>Claude Remote</strong> on your Android and<br>
    type this code in the pairing screen.
  </div>
  <div class="expired" id="expired">⏱ Code expired — reconnect from your phone to get a new one</div>
</div>
<script>
  let secs = 120;
  const timerEl  = document.getElementById('timer');
  const progressEl = document.getElementById('progress');
  const expiredEl = document.getElementById('expired');
  const digits = document.querySelectorAll('.digit');

  const tick = setInterval(() => {{
    secs--;
    progressEl.style.width = (secs / 120 * 100) + '%';
    if (secs <= 0) {{
      clearInterval(tick);
      timerEl.parentElement.style.display = 'none';
      expiredEl.style.display = 'block';
      digits.forEach(d => {{
        d.style.borderColor = '#EF4444';
        d.style.color = '#9CA3AF';
      }});
      return;
    }}
    const m = Math.floor(secs / 60);
    const s = secs % 60;
    timerEl.textContent = m + ':' + String(s).padStart(2, '0');
    if (secs <= 30) timerEl.style.color = '#EF4444';
  }}, 1000);
</script>
</body>
</html>"""

    html_dir = os.path.expanduser("~/.remote-terminal/")
    os.makedirs(html_dir, exist_ok=True)
    html_path = os.path.join(html_dir, "pair.html")
    with open(html_path, "w") as f:
        f.write(html)

    file_url = f"file://{html_path}"
    if IS_MAC:
        subprocess.Popen(["open", file_url])
    else:
        subprocess.Popen(["xdg-open", file_url])


# ─── PTY reader thread ────────────────────────────────────────────────────────

def pty_reader_thread(sid, loop):
    session = sessions.get(sid)
    if not session:
        return
    fd = session["fd"]

    while sid in sessions:
        try:
            # select() with timeout — os.read() only called when data is ready.
            # Prevents macOS PTY deadlock: if cleanup closes the fd while we are
            # blocked in os.read(), Darwin goes UN (uninterruptible sleep).
            # With select we are only briefly inside os.read().
            rlist, _, _ = select_module.select([fd], [], [], 1.0)
            if not rlist:
                continue  # timeout, loop back and re-check sid in sessions
            data = os.read(fd, 4096)
            if not data:
                break
            # Update scrollback buffer
            session = sessions.get(sid)
            if session is not None:
                sb = session["scrollback"]
                sb.extend(data)
                if len(sb) > SCROLLBACK_SIZE:
                    del sb[:len(sb) - SCROLLBACK_SIZE]
            text = data.decode("utf-8", errors="replace")
            msg = json.dumps({"type": "output", "session_id": sid, "data": text})
            for q in list(client_queues.get(sid, [])):
                loop.call_soon_threadsafe(q.put_nowait, msg)
        except OSError:
            break
        except Exception as e:
            print(f"[reader:{sid}] error: {e}")
            break

    end_msg = json.dumps({"type": "session_ended", "session_id": sid})
    for q in list(client_queues.get(sid, [])):
        loop.call_soon_threadsafe(q.put_nowait, end_msg)

    # cleanup runs in this thread — fine since it's already in a thread
    cleanup_session(sid)


# ─── WebSocket handler ────────────────────────────────────────────────────────

async def handler(websocket):
    authed = False
    my_queues = {}
    my_global_q = asyncio.Queue()
    all_client_queues.append(my_global_q)

    async def tx(obj):
        await websocket.send(json.dumps(obj))

    async def queue_forwarder(sid, q):
        try:
            while True:
                msg = await q.get()
                await websocket.send(msg)
                if json.loads(msg).get("type") == "session_ended":
                    break
        except Exception:
            pass

    async def global_forwarder():
        """Forward global broadcast messages (e.g. auto_open_session) to this client."""
        try:
            while True:
                msg = await my_global_q.get()
                await websocket.send(msg)
        except Exception:
            pass

    global_task = asyncio.create_task(global_forwarder())

    try:
        async for raw in websocket:
            try:
                msg = json.loads(raw)
            except Exception:
                continue

            t = msg.get("type")

            # ── info — no auth required, used by discovery ────────────────────
            if t == "info":
                await tx({
                    "type": "info_response",
                    "hostname": socket_module.gethostname(),
                    "version": SERVER_VERSION,
                })
                continue

            if t == "auth":
                if msg.get("token") != AUTH_TOKEN:
                    await tx({"type": "auth_fail"})
                    continue
                device_id = msg.get("device_id", "")
                if device_id and device_id in paired_devices:
                    # Already paired — let through
                    authed = True
                    await tx({"type": "auth_ok"})
                    await tx({"type": "sessions_list", "sessions": sessions_list()})
                elif device_id:
                    # New device — generate pairing code
                    code = f"{random.randint(0, 9999):04d}"
                    pending_pairs[device_id] = {
                        "code": code,
                        "expires": time.time() + 120,
                    }
                    # Print on terminal + open browser page
                    digits = "  ".join(list(code))
                    print("\n\033[1;33m" + "╔══════════════════════════════════════╗")
                    print("║                                      ║")
                    print("║   PAIRING REQUEST — New Device       ║")
                    print("║                                      ║")
                    print(f"║        [ {digits} ]              ║")
                    print("║                                      ║")
                    print("║   Enter this code on your phone      ║")
                    print("║   Expires in 2 minutes               ║")
                    print("║                                      ║")
                    print("╚══════════════════════════════════════╝\033[0m\n")
                    await asyncio.to_thread(open_pair_page, code)
                    await tx({"type": "pair_required"})
                else:
                    # No device_id (old client) — allow without pairing
                    authed = True
                    await tx({"type": "auth_ok"})
                    await tx({"type": "sessions_list", "sessions": sessions_list()})
                continue

            if t == "pair_verify":
                device_id = msg.get("device_id", "")
                code      = msg.get("code", "")
                pair      = pending_pairs.get(device_id)
                if pair and time.time() < pair["expires"] and pair["code"] == code:
                    paired_devices.add(device_id)
                    save_paired(paired_devices)
                    pending_pairs.pop(device_id, None)
                    authed = True
                    print(f"\033[1;32m[server] Device {device_id[:8]}... paired successfully\033[0m")
                    await tx({"type": "pair_ok"})
                    await tx({"type": "auth_ok"})
                    await tx({"type": "sessions_list", "sessions": sessions_list()})
                else:
                    # Wrong code or expired — only delete if expired
                    if not pair or time.time() >= pair["expires"]:
                        pending_pairs.pop(device_id, None)
                    await tx({"type": "pair_fail"})
                continue

            if not authed:
                await tx({"type": "error", "msg": "auth required"})
                continue

            # ── new_session ──────────────────────────────────────────────────
            if t == "new_session":
                cmd = msg.get("cmd")
                rows = int(msg.get("rows", 24))
                cols = int(msg.get("cols", 80))
                cwd = msg.get("cwd")  # optional: client can specify working directory
                # spawn in thread — never blocks event loop
                sid = await asyncio.to_thread(spawn_session, cmd, rows=rows, cols=cols, cwd=cwd)
                loop = asyncio.get_running_loop()
                th = threading.Thread(
                    target=pty_reader_thread, args=(sid, loop), daemon=True
                )
                th.start()
                q = asyncio.Queue()
                my_queues[sid] = q
                client_queues[sid].append(q)
                asyncio.create_task(queue_forwarder(sid, q))
                await tx({"type": "session_created", "session_id": sid,
                          "cmd": sessions[sid]["cmd"]})
                await tx({"type": "sessions_list", "sessions": sessions_list()})
                # auto_open: phone ko session_created + auto_open_session dono bhejo
                # (tx() sirf Mac script ko bhejta hai — phone ke liye global broadcast chahiye)
                if msg.get("auto_open"):
                    created = json.dumps({"type": "session_created", "session_id": sid,
                                          "cmd": sessions[sid]["cmd"]})
                    auto_open = json.dumps({"type": "auto_open_session", "session_id": sid})
                    for q in all_client_queues:
                        if q is not my_global_q:
                            q.put_nowait(created)
                            q.put_nowait(auto_open)

            # ── attach ───────────────────────────────────────────────────────
            elif t == "attach":
                sid = msg.get("session_id")
                if sid not in sessions:
                    await tx({"type": "error", "msg": "session not found"})
                    continue

                # Add queue if not already present (first-time attach from another client)
                if sid not in my_queues:
                    q = asyncio.Queue()
                    my_queues[sid] = q
                    client_queues[sid].append(q)
                    asyncio.create_task(queue_forwarder(sid, q))

                rows_a = msg.get("rows")
                cols_a = msg.get("cols")
                if rows_a and cols_a:
                    r, c = int(rows_a), int(cols_a)
                    set_winsize(sessions[sid]["fd"], r, c)
                    sessions[sid]["rows"] = r
                    sessions[sid]["cols"] = c
                    tmux_n = sessions[sid].get("tmux")
                    if tmux_n:
                        await asyncio.to_thread(tmux_resize, tmux_n, c, r)

                # Take Back: detach Mac's tmux client (NOT phone's)
                # iTerm's process exits → iTerm handles the tab naturally (no force-close)
                iterm_tab = sessions[sid].get("iterm_tab")
                tmux_n = sessions[sid].get("tmux")
                phone_tty = sessions[sid].get("phone_tty")
                if tmux_n and iterm_tab:
                    sessions[sid]["iterm_tab"] = None
                    clients = await asyncio.to_thread(tmux_list_clients, tmux_n)
                    for client_tty in clients:
                        if client_tty != phone_tty:
                            await asyncio.to_thread(tmux_detach_client, client_tty)

                # Replay scrollback buffer — client Terminal is fresh (app was killed),
                # send last N KB of PTY output so it shows previous state immediately.
                sb = sessions[sid].get("scrollback")
                if sb:
                    sb_data = bytes(sb).decode("utf-8", errors="replace")
                    if sb_data:
                        await tx({"type": "output", "session_id": sid, "data": sb_data})

                await tx({"type": "attached", "session_id": sid})

                # Force full repaint: same-size SIGWINCH is ignored by Ink/Claude.
                # Change size by 1 row then restore — guarantees two distinct
                # SIGWINCHes so Claude/Ink does a complete screen redraw.
                _sid = sid
                _r   = sessions[sid]["rows"]
                _c   = sessions[sid]["cols"]

                async def _force_repaint(s_id, r0, c0):
                    await asyncio.sleep(0.35)   # let client build TerminalView
                    if s_id not in sessions:
                        return
                    r_tmp = (r0 - 1) if r0 > 5 else (r0 + 1)
                    set_winsize(sessions[s_id]["fd"], r_tmp, c0)
                    await asyncio.sleep(0.15)   # let Claude process first SIGWINCH
                    if s_id not in sessions:
                        return
                    set_winsize(sessions[s_id]["fd"], r0, c0)

                asyncio.create_task(_force_repaint(_sid, _r, _c))

            # ── input ────────────────────────────────────────────────────────
            elif t == "input":
                sid = msg.get("session_id")
                data = msg.get("data", "")
                if sid in sessions:
                    try:
                        os.write(sessions[sid]["fd"], data.encode("utf-8"))
                    except OSError:
                        pass

            # ── resize ───────────────────────────────────────────────────────
            elif t == "resize":
                sid = msg.get("session_id")
                if sid in sessions:
                    r = int(msg.get("rows", 40))
                    c = int(msg.get("cols", 80))
                    set_winsize(sessions[sid]["fd"], r, c)
                    sessions[sid]["rows"] = r
                    sessions[sid]["cols"] = c
                    tmux_n = sessions[sid].get("tmux")
                    if tmux_n:
                        # fire-and-forget in thread — resize events are frequent
                        asyncio.create_task(
                            asyncio.to_thread(tmux_resize, tmux_n, c, r)
                        )

            # ── kill_session ─────────────────────────────────────────────────
            elif t == "kill_session":
                sid = msg.get("session_id")
                if sid:
                    await asyncio.to_thread(cleanup_session, sid)
                    await tx({"type": "sessions_list", "sessions": sessions_list()})

            # ── open_in_iterm ────────────────────────────────────────────────
            elif t == "open_in_iterm":
                sid = msg.get("session_id")
                if sid not in sessions:
                    continue

                session = sessions[sid]
                tmux_name = session.get("tmux")
                cmd_display = session.get("cmd", "")
                is_claude = "claude" in cmd_display.lower()
                tab_name = f"rt-{sid}"

                # Get CWD
                cwd = os.path.expanduser("~")
                if tmux_name:
                    tc = await asyncio.to_thread(tmux_cwd, tmux_name)
                    if tc:
                        cwd = tc
                else:
                    cc = await asyncio.to_thread(get_claude_cwd, session)
                    if cc:
                        cwd = cc

                cwd_esc = cwd.replace("'", "'\\''")

                if tmux_name:
                    shell_cmd = (
                        f"cd '{cwd_esc}' && "
                        f"{TMUX} resize-window -t {tmux_name} -x $(tput cols) -y $(tput lines) && "
                        f"{TMUX} attach-session -t {tmux_name}"
                    )
                elif is_claude:
                    shell_cmd = f"cd '{cwd_esc}' && claude --continue"
                else:
                    shell_cmd = f"cd '{cwd_esc}'"

                # Store tab name so attach handler can close it on Take Back
                sessions[sid]["iterm_tab"] = tab_name

                # Run AppleScript in thread so it never blocks
                await asyncio.to_thread(open_iterm, shell_cmd, tab_name)
                await tx({"type": "iterm_opened", "session_id": sid})

            # ── logout_all_devices ───────────────────────────────────────────
            elif t == "logout_all_devices":
                count = len(paired_devices)
                paired_devices.clear()
                save_paired(paired_devices)
                force_logout_msg = json.dumps({"type": "force_logout"})
                for q in all_client_queues:
                    if q is not my_global_q:
                        q.put_nowait(force_logout_msg)
                print(f"\033[1;33m[server] All devices logged out ({count} cleared)\033[0m")
                await tx({"type": "logout_ok", "count": count})

            # ── list_sessions ────────────────────────────────────────────────
            elif t == "list_sessions":
                await tx({"type": "sessions_list", "sessions": sessions_list()})

            # ── check_update ─────────────────────────────────────────────────
            elif t == "check_update":
                try:
                    latest = await asyncio.to_thread(_fetch_latest_version)
                    if version_gt(latest, SERVER_VERSION):
                        await tx({"type": "update_available", "current": SERVER_VERSION, "latest": latest})
                    else:
                        await tx({"type": "update_status", "up_to_date": True, "version": SERVER_VERSION})
                except Exception as e:
                    await tx({"type": "update_status", "error": str(e)})

            # ── self_update ───────────────────────────────────────────────────
            elif t == "self_update":
                try:
                    latest = await asyncio.to_thread(_fetch_latest_version)
                    if not version_gt(latest, SERVER_VERSION):
                        await tx({"type": "update_status", "up_to_date": True, "version": SERVER_VERSION})
                        continue
                    new_code = await asyncio.to_thread(_download_server)
                    # Basic sanity check
                    if b"asyncio" not in new_code or b"websockets" not in new_code:
                        await tx({"type": "update_status", "error": "downloaded file looks invalid"})
                        continue
                    # Write to temp, then atomically replace self
                    tmp_fd, tmp_path = tempfile.mkstemp(suffix=".py")
                    with os.fdopen(tmp_fd, "wb") as f:
                        f.write(new_code)
                    shutil.move(tmp_path, os.path.abspath(__file__))
                    print(f"\033[1;32m[updater] Updated to v{latest} — restarting in 1s...\033[0m")
                    await tx({"type": "update_done", "version": latest})
                    # Exit after brief delay so the response reaches the client
                    asyncio.get_event_loop().call_later(1.0, lambda: os._exit(0))
                except Exception as e:
                    print(f"[updater] Self-update failed: {e}")
                    await tx({"type": "update_status", "error": str(e)})

    except websockets.exceptions.ConnectionClosed:
        pass
    except Exception as e:
        print(f"[handler error] {e}")
    finally:
        global_task.cancel()
        try:
            all_client_queues.remove(my_global_q)
        except ValueError:
            pass
        for sid, q in my_queues.items():
            if sid in client_queues and q in client_queues[sid]:
                client_queues[sid].remove(q)


async def main():
    print(f"[server] ws://0.0.0.0:{PORT}  v{SERVER_VERSION}")
    print(f"[server] token: {AUTH_TOKEN}")
    async with websockets.serve(handler, "0.0.0.0", PORT):
        asyncio.create_task(_startup_update_check())
        await asyncio.Future()


if __name__ == "__main__":
    asyncio.run(main())
