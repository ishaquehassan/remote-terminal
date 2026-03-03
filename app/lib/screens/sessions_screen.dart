import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../services/terminal_service.dart';
import '../services/language_service.dart';
import '../l10n.dart';
import 'terminal_screen.dart';

class SessionsScreen extends StatelessWidget {
  const SessionsScreen({super.key});

  static const double _fontSize = 11.0;
  static const double _charWidth = _fontSize * 0.60;
  static const double _charHeight = _fontSize * 1.2;

  ({int cols, int rows}) _calcSize(BuildContext context) {
    final mq = MediaQuery.of(context);
    // statusBar + AppBar + ExtraKeysBar — yahi subtract hoti hai terminal view se
    final usedH = mq.padding.top + kToolbarHeight + 42;
    final availH = mq.size.height - usedH;
    final cols = ((mq.size.width - 8) / _charWidth).floor().clamp(40, 220);
    final rows = (availH / _charHeight).floor().clamp(10, 120);
    return (cols: cols, rows: rows);
  }

  Future<void> _newSession(BuildContext context, TerminalService svc, {String? cmd}) async {
    if (!svc.isConnected) return;
    final (:cols, :rows) = _calcSize(context);
    final sid = await svc.newSessionFuture(cmd: cmd, rows: rows, cols: cols);
    if (context.mounted) {
      Navigator.of(context).push(MaterialPageRoute(
        builder: (_) => TerminalScreen(sessionId: sid),
      ));
    }
  }

  @override
  Widget build(BuildContext context) {
    final svc = context.watch<TerminalService>();
    final lang = context.watch<LanguageService>();
    final s = S(lang.isUrdu);

    // /continue-remote command ne auto_open_session bheja — seedha navigate karo
    final autoSid = svc.autoOpenSessionId;
    if (autoSid != null && svc.sessions.containsKey(autoSid)) {
      svc.clearAutoOpen();
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (context.mounted) {
          final (:cols, :rows) = _calcSize(context);
          svc.attachSession(autoSid, rows: rows, cols: cols); // PTY output subscribe karo
          Navigator.of(context).push(MaterialPageRoute(
            builder: (_) => TerminalScreen(sessionId: autoSid),
          ));
        }
      });
    }

    return Scaffold(
      backgroundColor: const Color(0xFF080B12),
      body: Column(
        children: [
          _Header(svc: svc, lang: lang, s: s),
          if (!svc.isConnected) _ConnectionBanner(isReconnecting: svc.isReconnecting, s: s),
          Expanded(
            child: svc.sessions.isEmpty
                ? _EmptyState(isReconnecting: svc.isReconnecting, s: s)
                : _SessionList(svc: svc, calcSize: _calcSize),
          ),
        ],
      ),
      floatingActionButton: svc.isConnected
          ? FloatingActionButton.extended(
              heroTag: 'claude',
              onPressed: () => _newSession(context, svc, cmd: 'claude'),
              backgroundColor: const Color(0xFFE07845),
              icon: const Icon(Icons.auto_awesome, color: Colors.white, size: 18),
              label: const Text(
                'New Claude Session',
                style: TextStyle(color: Colors.white, fontWeight: FontWeight.w600, fontSize: 13),
              ),
            )
          : null,
    );
  }
}

class _Header extends StatelessWidget {
  final TerminalService svc;
  final LanguageService lang;
  final S s;
  const _Header({required this.svc, required this.lang, required this.s});

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: const BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [Color(0xFF0D1117), Color(0xFF111827)],
        ),
        border: Border(bottom: BorderSide(color: Color(0xFF1E2A3A), width: 1)),
      ),
      child: SafeArea(
        bottom: false,
        child: Padding(
          padding: const EdgeInsets.fromLTRB(20, 12, 12, 12),
          child: Row(
            children: [
              Container(
                width: 36, height: 36,
                decoration: BoxDecoration(
                  color: const Color(0xFFE07845).withAlpha(20),
                  borderRadius: BorderRadius.circular(10),
                  border: Border.all(color: const Color(0xFFE07845).withAlpha(60), width: 1),
                ),
                child: const Icon(Icons.terminal, color: Color(0xFFE07845), size: 18),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Text(
                  s.sessions,
                  style: const TextStyle(
                    color: Colors.white,
                    fontSize: 17,
                    fontWeight: FontWeight.w600,
                    letterSpacing: 0.3,
                  ),
                ),
              ),
              // Language toggle
              LangToggle(lang: lang),
              const SizedBox(width: 6),
              // Connection dot
              Container(
                width: 8, height: 8,
                margin: const EdgeInsets.only(left: 6, right: 4),
                decoration: BoxDecoration(
                  color: svc.isConnected
                      ? const Color(0xFFE07845)
                      : svc.isReconnecting
                          ? Colors.orange
                          : Colors.redAccent,
                  shape: BoxShape.circle,
                  boxShadow: [
                    BoxShadow(
                      color: (svc.isConnected ? const Color(0xFFE07845) : Colors.orange)
                          .withAlpha(svc.isConnected ? 120 : 60),
                      blurRadius: 6,
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _ConnectionBanner extends StatelessWidget {
  final bool isReconnecting;
  final S s;
  const _ConnectionBanner({required this.isReconnecting, required this.s});

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
      color: isReconnecting
          ? Colors.orange.withAlpha(30)
          : Colors.red.withAlpha(30),
      child: Row(
        children: [
          if (isReconnecting)
            const SizedBox(
              width: 12, height: 12,
              child: CircularProgressIndicator(
                strokeWidth: 1.5, color: Colors.orange,
              ),
            )
          else
            const Icon(Icons.wifi_off, color: Colors.redAccent, size: 14),
          const SizedBox(width: 8),
          Text(
            isReconnecting ? s.reconnectingBanner : s.disconnectedBanner,
            style: TextStyle(
              color: isReconnecting ? Colors.orange : Colors.redAccent,
              fontSize: 12,
            ),
          ),
        ],
      ),
    );
  }
}

class _EmptyState extends StatelessWidget {
  final bool isReconnecting;
  final S s;
  const _EmptyState({required this.isReconnecting, required this.s});

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(
            width: 72, height: 72,
            decoration: BoxDecoration(
              color: const Color(0xFFE07845).withAlpha(15),
              borderRadius: BorderRadius.circular(20),
              border: Border.all(
                color: const Color(0xFFE07845).withAlpha(40), width: 1,
              ),
            ),
            child: Icon(
              isReconnecting ? Icons.wifi : Icons.terminal,
              color: const Color(0xFFE07845).withAlpha(160),
              size: 32,
            ),
          ),
          const SizedBox(height: 20),
          Text(
            isReconnecting ? s.reconnecting : s.noSessions,
            style: const TextStyle(
              color: Colors.white,
              fontSize: 16,
              fontWeight: FontWeight.w500,
            ),
          ),
          const SizedBox(height: 6),
          Text(
            isReconnecting ? s.waitingForServer : s.noSessionsHint,
            style: const TextStyle(color: Color(0xFF4A5568), fontSize: 13),
          ),
        ],
      ),
    );
  }
}

class _SessionList extends StatelessWidget {
  final TerminalService svc;
  final ({int cols, int rows}) Function(BuildContext) calcSize;
  const _SessionList({required this.svc, required this.calcSize});

  void _showRenameDialog(BuildContext context, TerminalSession session) {
    final ctrl = TextEditingController(
      text: svc.sessionNames[session.id] ?? '',
    );
    showDialog(
      context: context,
      builder: (_) => AlertDialog(
        backgroundColor: const Color(0xFF0F1621),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        title: const Text('Session ka naam', style: TextStyle(color: Colors.white, fontSize: 15)),
        content: TextField(
          controller: ctrl,
          autofocus: true,
          style: const TextStyle(color: Colors.white, fontFamily: 'JetBrainsMono', fontSize: 13),
          decoration: InputDecoration(
            hintText: session.cmd,
            hintStyle: const TextStyle(color: Color(0xFF4A5568)),
            filled: true,
            fillColor: const Color(0xFF0D1117),
            contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
            border: OutlineInputBorder(
              borderRadius: BorderRadius.circular(10),
              borderSide: const BorderSide(color: Color(0xFF1E2A3A)),
            ),
            enabledBorder: OutlineInputBorder(
              borderRadius: BorderRadius.circular(10),
              borderSide: const BorderSide(color: Color(0xFF1E2A3A)),
            ),
            focusedBorder: OutlineInputBorder(
              borderRadius: BorderRadius.circular(10),
              borderSide: const BorderSide(color: Color(0xFFE07845), width: 1.5),
            ),
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Cancel', style: TextStyle(color: Color(0xFF4A5568))),
          ),
          TextButton(
            onPressed: () {
              svc.renameSession(session.id, ctrl.text);
              Navigator.pop(context);
            },
            child: const Text('Save', style: TextStyle(color: Color(0xFFE07845), fontWeight: FontWeight.w600)),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final sessions = svc.sessions.values.toList();
    return ListView.builder(
      padding: const EdgeInsets.fromLTRB(16, 16, 16, 100),
      itemCount: sessions.length,
      itemBuilder: (ctx, i) {
        final session = sessions[i];
        final isClaude = session.cmd.contains('claude');
        final displayName = svc.sessionNames[session.id];
        return Padding(
          padding: const EdgeInsets.only(bottom: 10),
          child: _SessionCard(
            session: session,
            isClaude: isClaude,
            displayName: displayName,
            onTap: () {
              final (:cols, :rows) = calcSize(context);
              svc.attachSession(session.id, rows: rows, cols: cols);
              Navigator.of(context).push(MaterialPageRoute(
                builder: (_) => TerminalScreen(sessionId: session.id),
              ));
            },
            onKill: () => svc.killSession(session.id),
            onRename: () => _showRenameDialog(context, session),
          ),
        );
      },
    );
  }
}

class _SessionCard extends StatelessWidget {
  final TerminalSession session;
  final bool isClaude;
  final String? displayName;
  final VoidCallback onTap;
  final VoidCallback onKill;
  final VoidCallback onRename;
  const _SessionCard({
    required this.session,
    required this.isClaude,
    required this.onTap,
    required this.onKill,
    required this.onRename,
    this.displayName,
  });

  @override
  Widget build(BuildContext context) {
    final accent = const Color(0xFFE07845);
    final title = displayName ?? session.cmd;
    return GestureDetector(
      onTap: onTap,
      child: Container(
        decoration: BoxDecoration(
          color: const Color(0xFF0F1621),
          borderRadius: BorderRadius.circular(14),
          border: Border.all(color: const Color(0xFF1E2A3A), width: 1),
        ),
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
          child: Row(
            children: [
              Container(
                width: 40, height: 40,
                decoration: BoxDecoration(
                  color: accent.withAlpha(20),
                  borderRadius: BorderRadius.circular(10),
                  border: Border.all(color: accent.withAlpha(50), width: 1),
                ),
                child: Icon(
                  isClaude ? Icons.auto_awesome : Icons.terminal,
                  color: accent,
                  size: 18,
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      title,
                      style: const TextStyle(
                        color: Colors.white,
                        fontFamily: 'JetBrainsMono',
                        fontSize: 13,
                        fontWeight: FontWeight.w500,
                      ),
                    ),
                    const SizedBox(height: 3),
                    Text(
                      displayName != null ? session.cmd : session.id,
                      style: const TextStyle(
                        color: Color(0xFF4A5568),
                        fontFamily: 'JetBrainsMono',
                        fontSize: 10,
                      ),
                    ),
                  ],
                ),
              ),
              // Rename button
              IconButton(
                icon: const Icon(Icons.edit_outlined, color: Color(0xFF3D4A5C), size: 16),
                onPressed: onRename,
                splashRadius: 16,
                padding: const EdgeInsets.all(6),
                constraints: const BoxConstraints(minWidth: 32, minHeight: 32),
              ),
              // Kill button
              IconButton(
                icon: const Icon(Icons.delete_outline, color: Color(0xFF3D4A5C), size: 18),
                onPressed: onKill,
                splashRadius: 18,
                padding: const EdgeInsets.all(6),
                constraints: const BoxConstraints(minWidth: 32, minHeight: 32),
              ),
              const Icon(Icons.chevron_right, color: Color(0xFF2D3748), size: 20),
            ],
          ),
        ),
      ),
    );
  }
}

