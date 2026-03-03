import 'dart:async';
import 'dart:math';
import 'package:shared_preferences/shared_preferences.dart';
import 'dart:convert';
import 'package:flutter/foundation.dart';
import 'package:web_socket_channel/web_socket_channel.dart';
import 'package:xterm/xterm.dart';

class TerminalSession {
  final String id;
  final String cmd;
  final Terminal terminal;
  bool isActive;

  TerminalSession({
    required this.id,
    required this.cmd,
    required this.terminal,
    this.isActive = true,
  });
}

class TerminalService extends ChangeNotifier {
  WebSocketChannel? _channel;
  StreamSubscription? _sub;

  bool isConnected = false;
  bool isConnecting = false;
  bool isReconnecting = false;
  String? errorMsg;

  // Reconnect ke liye saved params
  String? _savedHost;
  int _savedPort = 8765;
  String? _savedToken;
  Timer? _reconnectTimer;

  final Map<String, TerminalSession> sessions = {};
  final Map<String, String> sessionNames = {};
  final Set<String> itermSessions = {}; // sessions currently open in iTerm (Mac has taken over)
  final Set<String> autoOpenSessions = {}; // sessions opened via /continue-remote (no iTerm option)
  final Map<String, ({int rows, int cols})> _sizes = {}; // last known size per session
  String? activeSessionId;

  Completer<String>? _pendingNewSession;
  String? autoOpenSessionId; // set when server requests auto-navigation

  // Pairing
  bool isPairRequired = false;
  bool pairFailed = false;
  String? _deviceId;

  Future<String> _getDeviceId() async {
    if (_deviceId != null) return _deviceId!;
    final prefs = await SharedPreferences.getInstance();
    var id = prefs.getString('device_id');
    if (id == null) {
      final rng = Random.secure();
      id = List.generate(16, (_) => rng.nextInt(256).toRadixString(16).padLeft(2, '0')).join();
      await prefs.setString('device_id', id);
    }
    _deviceId = id;
    return id;
  }

  Future<void> verifyPairCode(String code) async {
    pairFailed = false;
    notifyListeners();
    _send({'type': 'pair_verify', 'device_id': _deviceId ?? '', 'code': code});
  }

  void resetPairing() {
    isPairRequired = false;
    pairFailed = false;
    notifyListeners();
  }

  Future<void> connect(String host, int port, String token) async {
    _savedHost = host;
    _savedPort = port;
    _savedToken = token;

    isConnecting = true;
    errorMsg = null;
    notifyListeners();

    try {
      final uri = Uri.parse('ws://$host:$port');
      _channel = WebSocketChannel.connect(uri);
      await _channel!.ready;

      _sub = _channel!.stream.listen(
        _onMessage,
        onError: _onError,
        onDone: _onDone,
      );

      final deviceId = await _getDeviceId();
      _send({'type': 'auth', 'token': token, 'device_id': deviceId});
    } catch (e) {
      errorMsg = 'Connection failed: $e';
      isConnecting = false;
      isConnected = false;
      notifyListeners();
      // Agar pehle connected tha, retry karo
      if (isReconnecting) _scheduleReconnect();
    }
  }

  void _scheduleReconnect() {
    _reconnectTimer?.cancel();
    _reconnectTimer = Timer(const Duration(seconds: 3), () {
      if (!isConnected && _savedHost != null) {
        _attemptReconnect();
      }
    });
  }

  Future<void> _attemptReconnect() async {
    if (isConnected || isConnecting || _savedHost == null) return;
    isConnecting = true;
    notifyListeners();

    try {
      final uri = Uri.parse('ws://$_savedHost:$_savedPort');
      _channel = WebSocketChannel.connect(uri);
      await _channel!.ready;

      _sub?.cancel();
      _sub = _channel!.stream.listen(
        _onMessage,
        onError: _onError,
        onDone: _onDone,
      );

      final deviceId = await _getDeviceId();
      _send({'type': 'auth', 'token': _savedToken ?? '', 'device_id': deviceId});
    } catch (e) {
      isConnecting = false;
      notifyListeners();
      _scheduleReconnect(); // retry karo
    }
  }

  void _onMessage(dynamic raw) {
    try {
      final msg = jsonDecode(raw as String) as Map<String, dynamic>;
      final type = msg['type'] as String;

      switch (type) {
        case 'auth_ok':
          isConnected = true;
          isConnecting = false;
          isReconnecting = false;
          errorMsg = null;
          notifyListeners();
          break;

        case 'auth_fail':
          errorMsg = 'Invalid token';
          isConnecting = false;
          isReconnecting = false;
          _savedHost = null; // wrong token, stop retrying
          disconnect();
          notifyListeners();
          break;

        case 'sessions_list':
          final list = (msg['sessions'] as List?) ?? [];
          final serverIds = list.map((s) => s['id'] as String).toSet();
          for (final s in list) {
            final sid = s['id'] as String;
            if (!sessions.containsKey(sid)) {
              _createLocalSession(sid, s['cmd'] as String? ?? 'shell');
            }
          }
          sessions.removeWhere((sid, _) => !serverIds.contains(sid));
          if (activeSessionId != null && !sessions.containsKey(activeSessionId)) {
            activeSessionId = sessions.keys.isNotEmpty ? sessions.keys.first : null;
          }
          notifyListeners();
          break;

        case 'session_created':
          final sid = msg['session_id'] as String;
          final cmd = msg['cmd'] as String? ?? 'shell';
          _createLocalSession(sid, cmd);
          activeSessionId = sid;
          _pendingNewSession?.complete(sid);
          _pendingNewSession = null;
          notifyListeners();
          // 600ms: TerminalView onResize fire ho chuka hoga — PTY correct size pe hai
          Future.delayed(const Duration(milliseconds: 600), () {
            sendInput(sid, '\r');
            Future.delayed(const Duration(milliseconds: 200), () {
              sendInput(sid, '\x0c');
            });
          });
          break;

        case 'attached':
          final attachedSid = msg['session_id'] as String;
          activeSessionId = attachedSid;
          notifyListeners();
          Future.delayed(const Duration(milliseconds: 800), () {
            sendInput(attachedSid, '\r');
            Future.delayed(const Duration(milliseconds: 200), () {
              sendInput(attachedSid, '\x0c');
            });
          });
          break;

        case 'output':
          final sid = msg['session_id'] as String;
          final data = msg['data'] as String;
          sessions[sid]?.terminal.write(data);
          break;

        case 'iterm_opened':
          final sid = msg['session_id'] as String;
          itermSessions.add(sid);
          notifyListeners();
          break;

        case 'auto_open_session':
          final sid = msg['session_id'] as String;
          autoOpenSessions.add(sid);
          autoOpenSessionId = sid;
          notifyListeners();
          break;

        case 'pair_required':
          isPairRequired = true;
          pairFailed = false;
          isConnecting = false;
          notifyListeners();
          break;

        case 'pair_ok':
          isPairRequired = false;
          pairFailed = false;
          notifyListeners();
          break;

        case 'pair_fail':
          pairFailed = true;
          notifyListeners();
          break;

        case 'session_ended':
          final sid = msg['session_id'] as String;
          sessions.remove(sid);
          sessionNames.remove(sid);
          itermSessions.remove(sid);
          autoOpenSessions.remove(sid);
          _sizes.remove(sid);
          if (activeSessionId == sid) {
            activeSessionId = sessions.keys.isNotEmpty ? sessions.keys.first : null;
          }
          notifyListeners();
          break;
      }
    } catch (e) {
      debugPrint('[TerminalService] parse error: $e');
    }
  }

  void _createLocalSession(String sid, String cmd) {
    if (sessions.containsKey(sid)) return;
    final term = Terminal(
      maxLines: 10000,
      onOutput: (data) => sendInput(sid, data),
    );
    term.onResize = (cols, rows, pw, ph) {
      _sizes[sid] = (rows: rows, cols: cols);
      resize(sid, rows, cols);
    };
    sessions[sid] = TerminalSession(id: sid, cmd: cmd, terminal: term);
  }

  ({int rows, int cols})? sizeOf(String sid) => _sizes[sid];

  Future<String> newSessionFuture({String? cmd, int rows = 24, int cols = 80}) {
    _pendingNewSession = Completer<String>();
    final payload = <String, dynamic>{
      'type': 'new_session',
      'rows': rows,
      'cols': cols,
    };
    if (cmd != null) payload['cmd'] = cmd;
    _send(payload);
    return _pendingNewSession!.future;
  }

  void newSession({String? cmd, int rows = 24, int cols = 80}) {
    if (!isConnected) return;
    newSessionFuture(cmd: cmd, rows: rows, cols: cols);
  }

  void clearAutoOpen() {
    autoOpenSessionId = null;
  }

  void renameSession(String sessionId, String name) {
    if (name.trim().isEmpty) {
      sessionNames.remove(sessionId);
    } else {
      sessionNames[sessionId] = name.trim();
    }
    notifyListeners();
  }

  void attachSession(String sessionId, {int? rows, int? cols}) {
    final size = _sizes[sessionId];
    final r = rows ?? size?.rows ?? 24;
    final c = cols ?? size?.cols ?? 80;
    itermSessions.remove(sessionId);
    notifyListeners();
    _send({'type': 'attach', 'session_id': sessionId, 'rows': r, 'cols': c});
  }

  void openInIterm(String sessionId) {
    _send({'type': 'open_in_iterm', 'session_id': sessionId});
  }

  void sendInput(String sessionId, String data) {
    _send({'type': 'input', 'session_id': sessionId, 'data': data});
  }

  void resize(String sessionId, int rows, int cols) {
    _send({
      'type': 'resize',
      'session_id': sessionId,
      'rows': rows,
      'cols': cols,
    });
  }

  void killSession(String sessionId) {
    _send({'type': 'kill_session', 'session_id': sessionId});
    sessions.remove(sessionId);
    sessionNames.remove(sessionId);
    itermSessions.remove(sessionId);
    autoOpenSessions.remove(sessionId);
    _sizes.remove(sessionId);
    if (activeSessionId == sessionId) {
      activeSessionId = sessions.keys.isNotEmpty ? sessions.keys.first : null;
    }
    notifyListeners();
  }

  void _send(Map<String, dynamic> data) {
    if (_channel == null) return;
    try {
      _channel!.sink.add(jsonEncode(data));
    } catch (_) {}
  }

  void _onError(dynamic error) {
    debugPrint('[TerminalService] error: $error');
    isConnected = false;
    isConnecting = false;
    if (_savedHost != null) {
      isReconnecting = true;
      notifyListeners();
      _scheduleReconnect();
    } else {
      notifyListeners();
    }
  }

  void _onDone() {
    isConnected = false;
    isConnecting = false;
    if (_savedHost != null) {
      isReconnecting = true;
      notifyListeners();
      _scheduleReconnect();
    } else {
      notifyListeners();
    }
  }

  void disconnect() {
    _reconnectTimer?.cancel();
    _savedHost = null;
    isReconnecting = false;
    _sub?.cancel();
    _channel?.sink.close();
    _channel = null;
    isConnected = false;
    isConnecting = false;
    sessions.clear();
    sessionNames.clear();
    itermSessions.clear();
    autoOpenSessions.clear();
    _sizes.clear();
    activeSessionId = null;
    isPairRequired = false;
    pairFailed = false;
    notifyListeners();
  }

  TerminalSession? get activeSession =>
      activeSessionId != null ? sessions[activeSessionId] : null;

  @override
  void dispose() {
    _reconnectTimer?.cancel();
    super.dispose();
  }
}
