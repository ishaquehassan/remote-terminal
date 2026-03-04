# QR Pairing + Internet Access — Implementation Plan

> **Status:** Planned — not yet implemented
> **Target version:** v1.5.0

---

## Goal

Replace 4-digit PIN pairing with QR code scanning. Simultaneously embed Tailscale IP in the QR so the app can auto-connect over the internet (outside home network) without any manual IP entry.

---

## Full User Flow (After Implementation)

```
[ONE TIME SETUP]
Mac:   brew install tailscale && tailscale up
Phone: Install Tailscale app → login with same account

─────────────────────────────────────────────

[EVERY TIME — First pair on a new device]

App open
  ↓
Auto-discovery → server found
  ↓
Phone: QR Scanner screen opens (camera)
  ↓
Mac: Browser auto-opens with QR code
  ┌─────────────────────────────────┐
  │   Pair New Device               │
  │                                 │
  │   [ ██▀▀██ ░░██ ▀▀██ ]        │
  │   [    QR CODE HERE   ]        │
  │                                 │
  │   Expires in 2:00  ████░░       │
  └─────────────────────────────────┘
  ↓
Phone scans QR
  ↓
Auto-pair (no code entry)
Browser shows ✓ "Device Paired!" → window.close() after 1.5s
  ↓
App → Sessions screen ✅

─────────────────────────────────────────────

[EVERY TIME — Already paired device]

App open → auto-connect → Sessions screen
(no scan, no code, same as before)

─────────────────────────────────────────────

[OUTSIDE HOME NETWORK]

App open
  ↓
Saved local IP fails (timeout ~3s)
  ↓
App auto-falls back to saved Tailscale IP (100.x.x.x)
  ↓
Connected over internet ✅
(No manual input ever needed again)
```

---

## QR Code Contents

The QR encodes a deep link URL:

```
claude-remote://pair?
  code=a8f3d2c1        ← one-time pair token (random, expires 2min)
  &host=192.168.1.5    ← local LAN IP
  &remote=100.94.x.x   ← Tailscale IP (omitted if Tailscale not installed)
  &port=8765
  &token=xrlabs-remote-terminal-2024
  &device_id=xxxx      ← phone's device ID
```

---

## Server Side Changes (`server/server.py`)

### 1. Dependencies
```bash
pip3 install qrcode pillow
```
Add to `install.sh` pip install step.

### 2. Tailscale IP Detection
```python
def get_tailscale_ip() -> str:
    """Returns Tailscale IP if available, else empty string."""
    try:
        out = subprocess.check_output(
            ["tailscale", "ip", "-4"],
            stderr=subprocess.DEVNULL, timeout=3
        ).decode().strip()
        return out if out else ""
    except Exception:
        return ""
```

### 3. QR Code Generation
```python
import qrcode
import base64
from io import BytesIO

def generate_qr_b64(data: str) -> str:
    """Generate QR code as base64 PNG string."""
    qr = qrcode.QRCode(box_size=8, border=2)
    qr.add_data(data)
    qr.make(fit=True)
    img = qr.make_image(fill_color="#E07845", back_color="#13100D")
    buf = BytesIO()
    img.save(buf, format="PNG")
    return base64.b64encode(buf.getvalue()).decode()
```

### 4. `open_pair_page(code, device_id)` — Replace PIN with QR
- Get local IP via `socket.getsockname()` or `socket.getfqdn()`
- Get Tailscale IP via `get_tailscale_ip()`
- Build deep link URL with all params
- Generate QR as base64 PNG
- Render in HTML as `<img src="data:image/png;base64,...">`
- Remove digit boxes from current HTML
- Add WebSocket listener JS (same pattern as before):
  - Page connects to `ws://localhost:8765`
  - Sends `{"type": "pair_watch", "device_id": "xxx"}`
  - On `pair_done` → show success card → `window.close()` after 1.5s

### 5. `pair_watchers` Dict
```python
pair_watchers = defaultdict(list)  # device_id -> [Queue, ...]
```

### 6. New WebSocket Message: `pair_watch`
No auth required (browser page can't auth).
```python
if t == "pair_watch":
    watch_device_id = msg.get("device_id", "")
    if watch_device_id:
        watch_q = asyncio.Queue()
        pair_watchers[watch_device_id].append(watch_q)
        async def _watcher_fwd(q, did):
            try:
                m = await asyncio.wait_for(q.get(), timeout=130)
                await websocket.send(json.dumps(m))
            except Exception:
                pass
            finally:
                if did in pair_watchers and q in pair_watchers[did]:
                    pair_watchers[did].remove(q)
        asyncio.create_task(_watcher_fwd(watch_q, watch_device_id))
    continue
```

### 7. `pair_verify` Success — Notify Watchers
```python
# After paired_devices.add(device_id):
for wq in pair_watchers.pop(device_id, []):
    wq.put_nowait({"type": "pair_done"})
```

---

## App Side Changes (Flutter)

### 1. New Dependency — `pubspec.yaml`
```yaml
dependencies:
  mobile_scanner: ^5.x.x   # QR scanner with camera
```
Also add camera permission to `AndroidManifest.xml`:
```xml
<uses-permission android:name="android.permission.CAMERA"/>
```

### 2. New Screen — `qr_scanner_screen.dart`
- `MobileScanner` widget (full screen camera)
- `onDetect` callback — parse QR URL
- Parse deep link:
  ```dart
  final uri = Uri.parse(scannedUrl);
  final code     = uri.queryParameters['code']!;
  final host     = uri.queryParameters['host']!;
  final remote   = uri.queryParameters['remote'] ?? '';
  final port     = int.parse(uri.queryParameters['port'] ?? '8765');
  final token    = uri.queryParameters['token']!;
  final deviceId = uri.queryParameters['device_id'] ?? '';
  ```
- On successful parse → call `svc.connectAndPairQR(host, remote, port, token, code)`
- Show scanning animation / torch toggle button

### 3. `connect_screen.dart` — Navigate to QR Scanner
Replace current PIN screen navigation:
```dart
// Currently on server found → connect tap:
// Navigator.push(...PairingScreen...)

// New:
Navigator.push(...QRScannerScreen(serverHost: host, port: port)...)
```

### 4. `terminal_service.dart` — QR Pair + Fallback Connect

New method `connectAndPairQR()`:
```dart
Future<void> connectAndPairQR(
  String localHost, String remoteHost,
  int port, String token, String pairCode
) async {
  // Save both IPs
  prefs.setString('host', localHost);
  prefs.setString('remote_host', remoteHost);  // Tailscale
  prefs.setString('port', port.toString());
  prefs.setString('token', token);

  await connect(localHost, port, token);
  _send({'type': 'pair_verify', 'device_id': deviceId, 'code': pairCode});
}
```

Modify `connect()` with fallback logic:
```dart
Future<void> connect(String host, int port, String token) async {
  try {
    await _tryConnect(host, port, token, timeout: Duration(seconds: 3));
  } catch (_) {
    // Local failed — try Tailscale remote
    final remoteHost = prefs.getString('remote_host') ?? '';
    if (remoteHost.isNotEmpty) {
      await _tryConnect(remoteHost, port, token);
    } else {
      rethrow;
    }
  }
}
```

---

## `install.sh` Changes

```bash
# Add to pip install section:
pip3 install qrcode pillow
```

---

## What Stays Manual (One-Time Only)

| Step | Required For |
|------|-------------|
| `brew install tailscale && tailscale up` on Mac | Internet access outside home |
| Install Tailscale app on phone + login same account | Internet access outside home |

> If Tailscale is not installed, everything still works on local network — QR just won't contain a `remote` param, app won't have fallback IP, internet access won't work. No crashes.

---

## Files To Change — Summary

| File | Change |
|------|--------|
| `server/server.py` | QR generation, `pair_watchers`, `pair_watch` handler, `pair_verify` notify, Tailscale IP detect |
| `install.sh` | `pip3 install qrcode pillow` |
| `app/pubspec.yaml` | Add `mobile_scanner` |
| `app/android/app/src/main/AndroidManifest.xml` | Camera permission |
| `app/lib/screens/qr_scanner_screen.dart` | New screen (QR camera UI) |
| `app/lib/screens/connect_screen.dart` | Navigate to QR scanner instead of pairing screen |
| `app/lib/services/terminal_service.dart` | `connectAndPairQR()`, fallback connect logic, save `remote_host` |

---

## Version Target

- **v1.5.0** — QR pairing + Tailscale auto-fallback
- CHANGELOG entry to be written on implementation
