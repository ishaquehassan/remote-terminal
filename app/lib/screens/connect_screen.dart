import 'dart:math';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../services/terminal_service.dart';
import '../services/language_service.dart';
import '../services/discovery_service.dart';
import '../l10n.dart';
import 'sessions_screen.dart';
import 'pairing_screen.dart';

class ConnectScreen extends StatefulWidget {
  final bool forceShowList;
  const ConnectScreen({super.key, this.forceShowList = false});

  @override
  State<ConnectScreen> createState() => _ConnectScreenState();
}

class _ConnectScreenState extends State<ConnectScreen>
    with TickerProviderStateMixin {
  // Scan state
  final List<DiscoveryResult> _servers = [];
  bool _scanning = false;
  int _scanDone = 0;
  int _scanTotal = 254;

  // Manual entry
  final _hostCtrl = TextEditingController();
  final _portCtrl = TextEditingController(text: '8765');
  final _tokenCtrl = TextEditingController(text: 'xrlabs-remote-terminal-2024');
  bool _showManual = false;
  bool _autoConnecting = false;
  String _savedServerName = '';
  bool _pairingPushed = false;

  // Radar animation
  late final AnimationController _radarCtrl;
  late final AnimationController _pulseCtrl;
  late final Animation<double> _pulse;

  @override
  void initState() {
    super.initState();
    _radarCtrl = AnimationController(
      vsync: this,
      duration: const Duration(seconds: 2),
    )..repeat();
    _pulseCtrl = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 900),
    )..repeat(reverse: true);
    _pulse = Tween(begin: 0.6, end: 1.0).animate(
      CurvedAnimation(parent: _pulseCtrl, curve: Curves.easeInOut),
    );
    _loadPrefs().then((_) {
      if (!widget.forceShowList && _hostCtrl.text.trim().isNotEmpty) {
        _autoConnect();
      } else {
        _scan();
      }
    });
  }

  @override
  void dispose() {
    _radarCtrl.dispose();
    _pulseCtrl.dispose();
    _hostCtrl.dispose();
    _portCtrl.dispose();
    _tokenCtrl.dispose();
    super.dispose();
  }

  Future<void> _loadPrefs() async {
    final prefs = await SharedPreferences.getInstance();
    if (mounted) {
      setState(() {
        _hostCtrl.text = prefs.getString('host') ?? '';
        _portCtrl.text = prefs.getString('port') ?? '8765';
        _tokenCtrl.text = prefs.getString('token') ?? 'xrlabs-remote-terminal-2024';
        _savedServerName = prefs.getString('server_name') ?? '';
      });
    }
  }

  Future<void> _autoConnect() async {
    if (!mounted) return;
    setState(() => _autoConnecting = true);
    final svc = context.read<TerminalService>();
    final host = _hostCtrl.text.trim();
    final port = int.tryParse(_portCtrl.text.trim()) ?? 8765;
    final token = _tokenCtrl.text.trim();
    await svc.connect(
      host, port, token,
      serverName: _savedServerName.isNotEmpty ? _savedServerName : host,
    );
  }

  Future<void> _scan() async {
    if (_scanning) return;
    setState(() {
      _scanning = true;
      _servers.clear();
      _scanDone = 0;
    });

    await DiscoveryService.scan(
      onProgress: (done, total) {
        if (mounted) setState(() { _scanDone = done; _scanTotal = total; });
      },
      onFound: (result) {
        if (mounted) setState(() => _servers.add(result));
      },
    );

    if (mounted) setState(() => _scanning = false);
  }

  Future<void> _save({String? serverName}) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString('host', _hostCtrl.text.trim());
    await prefs.setString('port', _portCtrl.text.trim());
    await prefs.setString('token', _tokenCtrl.text.trim());
    if (serverName != null) await prefs.setString('server_name', serverName);
  }

  Future<void> _connectTo(DiscoveryResult r) async {
    _hostCtrl.text = r.host;
    await _save(serverName: r.displayName);
    if (!mounted) return;
    final svc = context.read<TerminalService>();
    final port = int.tryParse(_portCtrl.text.trim()) ?? 8765;
    final token = _tokenCtrl.text.trim();
    await svc.connect(r.host, port, token, serverName: r.displayName);
  }

  Future<void> _connectManual() async {
    final host = _hostCtrl.text.trim();
    if (host.isEmpty) return;
    await _save(serverName: host);
    if (!mounted) return;
    final svc = context.read<TerminalService>();
    final port = int.tryParse(_portCtrl.text.trim()) ?? 8765;
    final token = _tokenCtrl.text.trim();
    await svc.connect(host, port, token, serverName: host);
  }

  @override
  Widget build(BuildContext context) {
    final svc = context.watch<TerminalService>();
    final lang = context.watch<LanguageService>();
    final s = S(lang.isUrdu);

    if (svc.isConnected) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) {
          Navigator.of(context).pushReplacement(
            MaterialPageRoute(builder: (_) => const SessionsScreen()),
          );
        }
      });
    } else if (svc.isPairRequired && !_pairingPushed) {
      _pairingPushed = true;
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) {
          Navigator.of(context).push(
            MaterialPageRoute(builder: (_) => const PairingScreen()),
          ).then((_) {
            if (mounted) setState(() => _pairingPushed = false);
          });
        }
      });
    } else if (_autoConnecting && !svc.isConnecting && !svc.isConnected) {
      // auto-connect attempt failed — fallback to scan
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) {
          setState(() => _autoConnecting = false);
          _scan();
        }
      });
    }

    return Scaffold(
      backgroundColor: const Color(0xFF0D0B09),
      body: Stack(
        children: [
          // Background glow circles
          Positioned(
            top: -100, right: -60,
            child: Container(
              width: 280, height: 280,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                color: const Color(0xFFE07845).withAlpha(10),
              ),
            ),
          ),
          Positioned(
            bottom: 80, left: -80,
            child: Container(
              width: 200, height: 200,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                color: const Color(0xFFE07845).withAlpha(7),
              ),
            ),
          ),

          SafeArea(
            child: Column(
              children: [
                _buildHeader(lang, s),
                Expanded(
                  child: SingleChildScrollView(
                    padding: const EdgeInsets.fromLTRB(20, 0, 20, 20),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        const SizedBox(height: 24),
                        _autoConnecting
                            ? _buildConnectingCard(svc)
                            : _buildScanCard(s),
                        const SizedBox(height: 20),
                        if (!_autoConnecting && (_servers.isNotEmpty || _scanning))
                          _buildServerSection(s, svc),
                        if (svc.errorMsg != null) ...[
                          const SizedBox(height: 12),
                          _buildError(svc.errorMsg!),
                        ],
                        if (!_autoConnecting) ...[
                          const SizedBox(height: 16),
                          _buildManualToggle(s, svc),
                        ],
                      ],
                    ),
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildHeader(LanguageService lang, S s) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 16, 16, 0),
      child: Row(
        children: [
          Container(
            width: 44, height: 44,
            decoration: BoxDecoration(
              gradient: const LinearGradient(
                colors: [Color(0xFFE07845), Color(0xFFBF5530)],
                begin: Alignment.topLeft,
                end: Alignment.bottomRight,
              ),
              borderRadius: BorderRadius.circular(14),
              boxShadow: [
                BoxShadow(
                  color: const Color(0xFFE07845).withAlpha(70),
                  blurRadius: 12, offset: const Offset(0, 4),
                ),
              ],
            ),
            child: const Icon(Icons.auto_awesome, color: Colors.white, size: 22),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text(
                  'Claude Remote',
                  style: TextStyle(
                    color: Colors.white, fontSize: 18,
                    fontWeight: FontWeight.w700, letterSpacing: -0.3,
                  ),
                ),
                Text(
                  s.appSubtitle,
                  style: const TextStyle(color: Color(0xFF6B7280), fontSize: 11),
                ),
              ],
            ),
          ),
          LangToggle(lang: lang),
        ],
      ),
    );
  }

  Widget _buildConnectingCard(TerminalService svc) {
    final name = _savedServerName.isNotEmpty ? _savedServerName : _hostCtrl.text.trim();
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: const Color(0xFF1A1510),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: const Color(0xFF2A1E0F), width: 1),
      ),
      child: Row(
        children: [
          const SizedBox(
            width: 52, height: 52,
            child: CircularProgressIndicator(
              strokeWidth: 2.5,
              color: Color(0xFFE07845),
            ),
          ),
          const SizedBox(width: 14),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text(
                  'Connecting...',
                  style: TextStyle(
                    color: Colors.white, fontWeight: FontWeight.w600, fontSize: 13,
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  name,
                  style: const TextStyle(
                    color: Color(0xFF6B7280), fontSize: 11, fontFamily: 'JetBrainsMono',
                  ),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
              ],
            ),
          ),
          GestureDetector(
            onTap: () {
              svc.disconnect();
              setState(() => _autoConnecting = false);
              _scan();
            },
            child: Container(
              padding: const EdgeInsets.all(8),
              decoration: BoxDecoration(
                color: const Color(0xFF1F1F1F),
                borderRadius: BorderRadius.circular(10),
                border: Border.all(color: const Color(0xFF2A2A2A), width: 1),
              ),
              child: const Icon(Icons.close, color: Color(0xFF6B7280), size: 16),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildScanCard(S s) {
    final pct = _scanTotal > 0 ? _scanDone / _scanTotal : 0.0;

    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: const Color(0xFF1A1510),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: const Color(0xFF2A1E0F), width: 1),
      ),
      child: Row(
        children: [
          // Radar animation
          SizedBox(
            width: 52, height: 52,
            child: _scanning
                ? AnimatedBuilder(
                    animation: _radarCtrl,
                    builder: (ctx, child) => CustomPaint(
                      painter: _RadarPainter(_radarCtrl.value),
                    ),
                  )
                : FadeTransition(
                    opacity: _pulse,
                    child: Container(
                      width: 52, height: 52,
                      decoration: BoxDecoration(
                        shape: BoxShape.circle,
                        color: const Color(0xFFE07845).withAlpha(20),
                        border: Border.all(color: const Color(0xFFE07845).withAlpha(60), width: 1),
                      ),
                      child: const Icon(Icons.wifi_find, color: Color(0xFFE07845), size: 22),
                    ),
                  ),
          ),
          const SizedBox(width: 14),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  _scanning
                      ? s.scanning(_scanDone, _scanTotal)
                      : _servers.isEmpty
                          ? (context.read<LanguageService>().isUrdu
                              ? 'Koi server nahi mila'
                              : 'No servers found')
                          : (context.read<LanguageService>().isUrdu
                              ? '${_servers.length} server mila!'
                              : '${_servers.length} server${_servers.length == 1 ? '' : 's'} found!'),
                  style: const TextStyle(
                    color: Colors.white, fontWeight: FontWeight.w600, fontSize: 13,
                  ),
                ),
                const SizedBox(height: 6),
                ClipRRect(
                  borderRadius: BorderRadius.circular(3),
                  child: LinearProgressIndicator(
                    value: _scanning ? pct : 1.0,
                    backgroundColor: const Color(0xFF2A2A2A),
                    color: _servers.isNotEmpty
                        ? const Color(0xFFE07845)
                        : _scanning
                            ? const Color(0xFFE07845).withAlpha(180)
                            : const Color(0xFF3A3A3A),
                    minHeight: 4,
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(width: 10),
          // Rescan button
          GestureDetector(
            onTap: _scanning ? null : _scan,
            child: Container(
              padding: const EdgeInsets.all(8),
              decoration: BoxDecoration(
                color: _scanning
                    ? const Color(0xFF1F1F1F)
                    : const Color(0xFFE07845).withAlpha(20),
                borderRadius: BorderRadius.circular(10),
                border: Border.all(
                  color: _scanning
                      ? const Color(0xFF2A2A2A)
                      : const Color(0xFFE07845).withAlpha(80),
                  width: 1,
                ),
              ),
              child: Icon(
                Icons.refresh,
                color: _scanning ? const Color(0xFF3A3A3A) : const Color(0xFFE07845),
                size: 18,
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildServerSection(S s, TerminalService svc) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        if (_servers.isNotEmpty) ...[
          Padding(
            padding: const EdgeInsets.only(bottom: 10),
            child: Text(
              context.read<LanguageService>().isUrdu
                  ? 'Available servers'
                  : 'Available servers',
              style: const TextStyle(
                color: Color(0xFF6B7280), fontSize: 11,
                fontWeight: FontWeight.w500, letterSpacing: 0.5,
              ),
            ),
          ),
          ...List.generate(_servers.length, (i) {
            final r = _servers[i];
            return Padding(
              padding: const EdgeInsets.only(bottom: 10),
              child: _ServerCard(
                result: r,
                isConnecting: svc.isConnecting,
                onTap: svc.isConnecting ? null : () => _connectTo(r),
              ),
            );
          }),
        ],
        if (_scanning && _servers.isEmpty)
          const _SearchingPlaceholder(),
      ],
    );
  }

  Widget _buildError(String msg) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
      decoration: BoxDecoration(
        color: Colors.redAccent.withAlpha(20),
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: Colors.redAccent.withAlpha(50)),
      ),
      child: Row(
        children: [
          const Icon(Icons.error_outline, color: Colors.redAccent, size: 16),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              msg,
              style: const TextStyle(color: Colors.redAccent, fontSize: 12),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildManualToggle(S s, TerminalService svc) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        GestureDetector(
          onTap: () => setState(() => _showManual = !_showManual),
          child: Row(
            children: [
              const Expanded(child: Divider(color: Color(0xFF2A2A2A))),
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 12),
                child: Row(
                  children: [
                    Text(
                      context.read<LanguageService>().isUrdu
                          ? 'ya manually enter karo'
                          : 'or enter manually',
                      style: const TextStyle(color: Color(0xFF4A5568), fontSize: 11),
                    ),
                    const SizedBox(width: 4),
                    Icon(
                      _showManual ? Icons.expand_less : Icons.expand_more,
                      color: const Color(0xFF4A5568), size: 14,
                    ),
                  ],
                ),
              ),
              const Expanded(child: Divider(color: Color(0xFF2A2A2A))),
            ],
          ),
        ),
        if (_showManual) ...[
          const SizedBox(height: 16),
          Container(
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              color: const Color(0xFF1A1510),
              borderRadius: BorderRadius.circular(16),
              border: Border.all(color: const Color(0xFF2A1E0F), width: 1),
            ),
            child: Column(
              children: [
                _field('Mac IP / Host', _hostCtrl, hint: '192.168.x.x'),
                const SizedBox(height: 10),
                _field('Port', _portCtrl, hint: '8765', number: true),
                const SizedBox(height: 10),
                _field('Auth Token', _tokenCtrl, hint: 'token', obscure: true),
                const SizedBox(height: 14),
                SizedBox(
                  width: double.infinity,
                  height: 48,
                  child: ElevatedButton(
                    onPressed: (svc.isConnecting) ? null : _connectManual,
                    style: ElevatedButton.styleFrom(
                      backgroundColor: const Color(0xFFE07845),
                      foregroundColor: Colors.white,
                      disabledBackgroundColor: const Color(0xFF2A1E0F),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(12),
                      ),
                      elevation: 0,
                    ),
                    child: svc.isConnecting
                        ? const SizedBox(
                            width: 18, height: 18,
                            child: CircularProgressIndicator(
                              strokeWidth: 2, color: Color(0xFFE07845),
                            ),
                          )
                        : Text(
                            s.connect,
                            style: const TextStyle(
                              fontSize: 14, fontWeight: FontWeight.w700,
                            ),
                          ),
                  ),
                ),
              ],
            ),
          ),
        ],
      ],
    );
  }

  Widget _field(
    String label,
    TextEditingController ctrl, {
    String? hint,
    bool number = false,
    bool obscure = false,
  }) {
    return TextField(
      controller: ctrl,
      keyboardType: number ? TextInputType.number : TextInputType.text,
      obscureText: obscure,
      style: const TextStyle(color: Colors.white, fontSize: 14),
      decoration: InputDecoration(
        labelText: label,
        hintText: hint,
        labelStyle: const TextStyle(color: Color(0xFF4A5568), fontSize: 13),
        hintStyle: const TextStyle(color: Color(0xFF2D3748)),
        filled: true,
        fillColor: const Color(0xFF0D0A07),
        contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(10),
          borderSide: const BorderSide(color: Color(0xFF2A1E0F)),
        ),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(10),
          borderSide: const BorderSide(color: Color(0xFF2A1E0F)),
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(10),
          borderSide: const BorderSide(color: Color(0xFFE07845), width: 1.5),
        ),
      ),
    );
  }
}

// ── Server Card ────────────────────────────────────────────────────────────────

class _ServerCard extends StatelessWidget {
  final DiscoveryResult result;
  final bool isConnecting;
  final VoidCallback? onTap;
  const _ServerCard({
    required this.result,
    required this.isConnecting,
    this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 200),
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
        decoration: BoxDecoration(
          color: const Color(0xFF1A1510),
          borderRadius: BorderRadius.circular(16),
          border: Border.all(
            color: const Color(0xFFE07845).withAlpha(isConnecting ? 40 : 80),
            width: 1,
          ),
          boxShadow: [
            BoxShadow(
              color: const Color(0xFFE07845).withAlpha(15),
              blurRadius: 12, offset: const Offset(0, 4),
            ),
          ],
        ),
        child: Row(
          children: [
            // PC icon with glow
            Container(
              width: 48, height: 48,
              decoration: BoxDecoration(
                color: const Color(0xFFE07845).withAlpha(18),
                borderRadius: BorderRadius.circular(12),
                border: Border.all(color: const Color(0xFFE07845).withAlpha(50), width: 1),
              ),
              child: const Icon(Icons.computer, color: Color(0xFFE07845), size: 22),
            ),
            const SizedBox(width: 14),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    result.displayName,
                    style: const TextStyle(
                      color: Colors.white,
                      fontSize: 15,
                      fontWeight: FontWeight.w600,
                      letterSpacing: -0.2,
                    ),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                  const SizedBox(height: 3),
                  Row(
                    children: [
                      Container(
                        width: 6, height: 6,
                        decoration: const BoxDecoration(
                          color: Color(0xFF4ADE80),
                          shape: BoxShape.circle,
                        ),
                      ),
                      const SizedBox(width: 5),
                      Text(
                        '${result.host}  ·  :${result.port}',
                        style: const TextStyle(
                          color: Color(0xFF6B7280),
                          fontSize: 11,
                          fontFamily: 'JetBrainsMono',
                        ),
                      ),
                    ],
                  ),
                ],
              ),
            ),
            const SizedBox(width: 8),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
              decoration: BoxDecoration(
                color: const Color(0xFFE07845),
                borderRadius: BorderRadius.circular(20),
              ),
              child: const Text(
                'Connect',
                style: TextStyle(
                  color: Colors.white,
                  fontSize: 11,
                  fontWeight: FontWeight.w700,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

// ── Searching placeholder ──────────────────────────────────────────────────────

class _SearchingPlaceholder extends StatelessWidget {
  const _SearchingPlaceholder();

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: const Color(0xFF1A1510),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: const Color(0xFF2A1E0F), width: 1),
      ),
      child: const Row(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          SizedBox(
            width: 14, height: 14,
            child: CircularProgressIndicator(
              strokeWidth: 1.5, color: Color(0xFF6B7280),
            ),
          ),
          SizedBox(width: 10),
          Text(
            'Looking for servers...',
            style: TextStyle(color: Color(0xFF6B7280), fontSize: 12),
          ),
        ],
      ),
    );
  }
}

// ── Radar painter ──────────────────────────────────────────────────────────────

class _RadarPainter extends CustomPainter {
  final double progress;
  _RadarPainter(this.progress);

  @override
  void paint(Canvas canvas, Size size) {
    final cx = size.width / 2;
    final cy = size.height / 2;
    final r = size.width / 2;

    // Outer circle
    canvas.drawCircle(
      Offset(cx, cy), r - 2,
      Paint()
        ..color = const Color(0xFFE07845).withAlpha(30)
        ..style = PaintingStyle.stroke
        ..strokeWidth = 1,
    );
    // Middle circle
    canvas.drawCircle(
      Offset(cx, cy), (r - 2) * 0.6,
      Paint()
        ..color = const Color(0xFFE07845).withAlpha(20)
        ..style = PaintingStyle.stroke
        ..strokeWidth = 1,
    );
    // Inner circle
    canvas.drawCircle(
      Offset(cx, cy), (r - 2) * 0.3,
      Paint()
        ..color = const Color(0xFFE07845).withAlpha(25)
        ..style = PaintingStyle.stroke
        ..strokeWidth = 1,
    );

    // Rotating sweep
    final angle = progress * 2 * pi;
    final sweepPath = Path()
      ..moveTo(cx, cy)
      ..lineTo(
        cx + (r - 2) * cos(angle - pi / 2),
        cy + (r - 2) * sin(angle - pi / 2),
      )
      ..arcTo(
        Rect.fromCircle(center: Offset(cx, cy), radius: r - 2),
        angle - pi / 2,
        -pi / 2,
        false,
      )
      ..close();

    canvas.drawPath(
      sweepPath,
      Paint()
        ..shader = RadialGradient(
          colors: [
            const Color(0xFFE07845).withAlpha(60),
            const Color(0xFFE07845).withAlpha(0),
          ],
        ).createShader(Rect.fromCircle(center: Offset(cx, cy), radius: r)),
    );

    // Sweep line
    canvas.drawLine(
      Offset(cx, cy),
      Offset(
        cx + (r - 2) * cos(angle - pi / 2),
        cy + (r - 2) * sin(angle - pi / 2),
      ),
      Paint()
        ..color = const Color(0xFFE07845).withAlpha(200)
        ..strokeWidth = 1.5
        ..strokeCap = StrokeCap.round,
    );

    // Center dot
    canvas.drawCircle(
      Offset(cx, cy), 3,
      Paint()..color = const Color(0xFFE07845),
    );
  }

  @override
  bool shouldRepaint(_RadarPainter old) => old.progress != progress;
}
