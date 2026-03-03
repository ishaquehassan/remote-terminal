import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'package:web_socket_channel/web_socket_channel.dart';

class DiscoveryResult {
  final String host;
  final int port;
  final String? hostname;
  DiscoveryResult(this.host, this.port, {this.hostname});

  String get displayName => hostname ?? host;
}

class DiscoveryService {
  static const int _port = 8765;
  static const Duration _tcpTimeout = Duration(milliseconds: 400);
  static const Duration _wsTimeout = Duration(milliseconds: 800);

  /// Scan current subnet for open port 8765.
  /// [onFound] fires as each server is discovered (with hostname).
  static Future<List<DiscoveryResult>> scan({
    void Function(int done, int total)? onProgress,
    void Function(DiscoveryResult)? onFound,
  }) async {
    final localIp = await _getLocalIp();
    if (localIp == null) return [];

    final parts = localIp.split('.');
    if (parts.length != 4) return [];
    final subnet = '${parts[0]}.${parts[1]}.${parts[2]}';

    final openHosts = <String>[];
    final total = 254;
    int done = 0;

    // Phase 1: TCP scan in batches of 30 (fast)
    for (int batch = 1; batch <= 254; batch += 30) {
      final futures = <Future>[];
      for (int i = batch; i < batch + 30 && i <= 254; i++) {
        final ip = '$subnet.$i';
        futures.add(
          _checkPort(ip, _port).then((ok) {
            if (ok) openHosts.add(ip);
            done++;
            onProgress?.call(done, total);
          }),
        );
      }
      await Future.wait(futures);
    }

    // Phase 2: WS info query for each found host (parallel)
    final results = <DiscoveryResult>[];
    await Future.wait(openHosts.map((host) async {
      final hostname = await _fetchHostname(host, _port);
      final result = DiscoveryResult(host, _port, hostname: hostname);
      results.add(result);
      onFound?.call(result);
    }));

    return results;
  }

  /// Quick WebSocket connect → send {"type":"info"} → get hostname back.
  /// Server responds without auth for info requests.
  static Future<String?> _fetchHostname(String host, int port) async {
    WebSocketChannel? channel;
    try {
      channel = WebSocketChannel.connect(Uri.parse('ws://$host:$port'));
      channel.sink.add(json.encode({'type': 'info'}));
      final msg = await channel.stream.first.timeout(_wsTimeout);
      final data = json.decode(msg as String);
      if (data['type'] == 'info_response') {
        return data['hostname'] as String?;
      }
    } catch (_) {
    } finally {
      channel?.sink.close();
    }
    return null;
  }

  static Future<bool> _checkPort(String host, int port) async {
    try {
      final sock = await Socket.connect(host, port, timeout: _tcpTimeout);
      await sock.close();
      return true;
    } catch (_) {
      return false;
    }
  }

  static Future<String?> _getLocalIp() async {
    try {
      final interfaces = await NetworkInterface.list(
        type: InternetAddressType.IPv4,
        includeLoopback: false,
      );
      for (final iface in interfaces) {
        for (final addr in iface.addresses) {
          if (!addr.isLoopback) return addr.address;
        }
      }
    } catch (_) {}
    return null;
  }
}
