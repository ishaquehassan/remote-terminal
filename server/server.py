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

PORT = 8765
AUTH_TOKEN = "xrlabs-remote-terminal-2024"

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
    """Open a terminal window/tab and run shell_cmd. Mac uses iTerm2, Linux uses best available."""
    if IS_MAC:
        apple_cmd = shell_cmd.replace('\\', '\\\\').replace('"', '\\"')
        safe_name = tab_name.replace('"', '\\"')
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
        subprocess.Popen(["osascript", "-e", script])
    else:
        # Linux: try common terminal emulators
        for term, args in [
            ("gnome-terminal", ["--", "bash", "-c", f"{shell_cmd}; exec bash"]),
            ("xterm",          ["-e", f"{shell_cmd}"]),
            ("konsole",        ["-e", f"{shell_cmd}"]),
            ("xfce4-terminal", ["-e", f"{shell_cmd}"]),
        ]:
            if shutil.which(term):
                subprocess.Popen([term] + args)
                return
        print(f"[server] No terminal emulator found. Run manually: {shell_cmd}")


def sessions_list():
    return [{"id": s, "cmd": v["cmd"]} for s, v in sessions.items()]


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
                    "version": "1.0",
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
                    # Print on Mac terminal — very visible
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

                await tx({"type": "attached", "session_id": sid})

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

            # ── list_sessions ────────────────────────────────────────────────
            elif t == "list_sessions":
                await tx({"type": "sessions_list", "sessions": sessions_list()})

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
    print(f"[server] ws://0.0.0.0:{PORT}")
    print(f"[server] token: {AUTH_TOKEN}")
    async with websockets.serve(handler, "0.0.0.0", PORT):
        await asyncio.Future()


if __name__ == "__main__":
    asyncio.run(main())
