import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';
import '../services/terminal_service.dart';
import 'sessions_screen.dart';

class PairingScreen extends StatefulWidget {
  const PairingScreen({super.key});

  @override
  State<PairingScreen> createState() => _PairingScreenState();
}

class _PairingScreenState extends State<PairingScreen> {
  final _ctrl = TextEditingController();
  final _focus = FocusNode();
  bool _verifying = false;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) => _focus.requestFocus());
  }

  @override
  void dispose() {
    _ctrl.dispose();
    _focus.dispose();
    super.dispose();
  }

  void _verify() {
    if (_ctrl.text.length != 4) return;
    setState(() => _verifying = true);
    context.read<TerminalService>().verifyPairCode(_ctrl.text);
  }

  @override
  Widget build(BuildContext context) {
    final svc = context.watch<TerminalService>();

    if (svc.isConnected) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) {
          Navigator.of(context).pushReplacement(
            MaterialPageRoute(builder: (_) => const SessionsScreen()),
          );
        }
      });
    }

    if (svc.pairFailed && _verifying) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) {
          setState(() {
            _verifying = false;
            _ctrl.clear();
          });
          _focus.requestFocus();
        }
      });
    }

    final code = _ctrl.text.padRight(4);

    return Scaffold(
      backgroundColor: const Color(0xFF0D0B09),
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 32),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              // Icon
              Container(
                width: 72, height: 72,
                decoration: BoxDecoration(
                  color: const Color(0xFFE07845).withAlpha(20),
                  borderRadius: BorderRadius.circular(20),
                  border: Border.all(color: const Color(0xFFE07845).withAlpha(60), width: 1),
                ),
                child: const Icon(Icons.lock_outline, color: Color(0xFFE07845), size: 32),
              ),
              const SizedBox(height: 28),

              // Title
              const Text(
                'Pairing Required',
                style: TextStyle(
                  color: Colors.white,
                  fontSize: 22,
                  fontWeight: FontWeight.w700,
                ),
              ),
              const SizedBox(height: 10),

              // Subtitle
              const Text(
                'Check your Mac terminal for\nthe 4-digit pairing code',
                textAlign: TextAlign.center,
                style: TextStyle(color: Color(0xFF6B7280), fontSize: 14, height: 1.5),
              ),
              const SizedBox(height: 40),

              // 4 digit boxes (hidden TextField behind)
              Stack(
                alignment: Alignment.center,
                children: [
                  // Hidden input
                  SizedBox(
                    width: 1, height: 1,
                    child: TextField(
                      controller: _ctrl,
                      focusNode: _focus,
                      keyboardType: TextInputType.number,
                      maxLength: 4,
                      inputFormatters: [FilteringTextInputFormatter.digitsOnly],
                      decoration: const InputDecoration(counterText: ''),
                      style: const TextStyle(color: Colors.transparent, fontSize: 1),
                      cursorColor: Colors.transparent,
                      onChanged: (_) => setState(() {}),
                      onSubmitted: (_) => _verify(),
                    ),
                  ),
                  // Visual boxes
                  GestureDetector(
                    onTap: () => _focus.requestFocus(),
                    child: Row(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: List.generate(4, (i) {
                        final filled = i < _ctrl.text.length;
                        final active = i == _ctrl.text.length;
                        return Container(
                          margin: const EdgeInsets.symmetric(horizontal: 8),
                          width: 60, height: 70,
                          decoration: BoxDecoration(
                            color: filled
                                ? const Color(0xFFE07845).withAlpha(20)
                                : const Color(0xFF1A1510),
                            borderRadius: BorderRadius.circular(14),
                            border: Border.all(
                              color: active
                                  ? const Color(0xFFE07845)
                                  : filled
                                      ? const Color(0xFFE07845).withAlpha(80)
                                      : const Color(0xFF2A1E0F),
                              width: active ? 2 : 1,
                            ),
                          ),
                          alignment: Alignment.center,
                          child: Text(
                            filled ? code[i] : '',
                            style: const TextStyle(
                              color: Colors.white,
                              fontSize: 28,
                              fontWeight: FontWeight.w700,
                              fontFamily: 'JetBrainsMono',
                            ),
                          ),
                        );
                      }),
                    ),
                  ),
                ],
              ),

              const SizedBox(height: 16),

              // Error
              AnimatedOpacity(
                opacity: svc.pairFailed ? 1.0 : 0.0,
                duration: const Duration(milliseconds: 200),
                child: Container(
                  padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
                  decoration: BoxDecoration(
                    color: Colors.redAccent.withAlpha(20),
                    borderRadius: BorderRadius.circular(10),
                    border: Border.all(color: Colors.redAccent.withAlpha(60)),
                  ),
                  child: const Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(Icons.close, color: Colors.redAccent, size: 16),
                      SizedBox(width: 8),
                      Text(
                        'Wrong code — try again',
                        style: TextStyle(color: Colors.redAccent, fontSize: 13),
                      ),
                    ],
                  ),
                ),
              ),

              const SizedBox(height: 32),

              // Verify button
              SizedBox(
                width: double.infinity,
                height: 52,
                child: ElevatedButton(
                  onPressed: (_ctrl.text.length == 4 && !_verifying) ? _verify : null,
                  style: ElevatedButton.styleFrom(
                    backgroundColor: const Color(0xFFE07845),
                    foregroundColor: Colors.white,
                    disabledBackgroundColor: const Color(0xFF2A1E0F),
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
                    elevation: 0,
                  ),
                  child: _verifying
                      ? const SizedBox(
                          width: 20, height: 20,
                          child: CircularProgressIndicator(
                            strokeWidth: 2, color: Color(0xFFE07845),
                          ),
                        )
                      : const Text(
                          'Verify',
                          style: TextStyle(fontSize: 16, fontWeight: FontWeight.w700),
                        ),
                ),
              ),

              const SizedBox(height: 16),

              // Cancel
              TextButton(
                onPressed: () {
                  context.read<TerminalService>().disconnect();
                  context.read<TerminalService>().resetPairing();
                  Navigator.of(context).pop();
                },
                child: const Text(
                  'Cancel',
                  style: TextStyle(color: Color(0xFF4A5568), fontSize: 13),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
