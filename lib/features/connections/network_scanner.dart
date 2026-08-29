import 'dart:async';
import 'dart:io';

import 'package:riverpod_annotation/riverpod_annotation.dart';

part 'network_scanner.g.dart';

/// Represents a discovered network service
class DiscoveredService {
  DiscoveredService({
    required this.name,
    required this.host,
    required this.port,
    required this.type,
  });

  final String name;
  final String host;
  final int port;
  final String type;

  @override
  String toString() => 'DiscoveredService(name: $name, host: $host, port: $port, type: $type)';
}

/// Scans the local network for FTP/SFTP/WebDAV services.
///
/// Uses two approaches:
/// 1. Port scanning on common ports (21, 22, 8080, 443) for local IP range
/// 2. mDNS/Bonjour discovery (via bonsoir package — Sprint 4)
@Riverpod(keepAlive: true)
class NetworkScanner extends _$NetworkScanner {
  @override
  List<DiscoveredService> build() {
    return [];
  }

  /// Scan the local network for services.
  ///
  /// Scans the local subnet for common ports:
  /// - 21: FTP
  /// - 22: SFTP/SSH
  /// - 443: WebDAV (HTTPS)
  /// - 8080: WebDAV (HTTP)
  Future<List<DiscoveredService>> scanNetwork() async {
    final results = <DiscoveredService>[];
    state = []; // Clear previous results

    // Get local IP address
    final localIp = await _getLocalIp();
    if (localIp == null) return results;

    // Extract subnet (e.g., 192.168.1)
    final parts = localIp.split('.');
    if (parts.length != 4) return results;
    final subnet = '${parts[0]}.${parts[1]}.${parts[2]}';

    // Common ports to scan
    const ports = [
      (21, 'FTP'),
      (22, 'SFTP'),
      (443, 'WebDAV'),
      (8080, 'WebDAV'),
      (445, 'SMB'),
    ];

    // Scan subnet (1-254) in parallel batches
    const batchSize = 50;
    for (var start = 1; start < 255; start += batchSize) {
      final end = (start + batchSize > 254) ? 254 : start + batchSize;
      final futures = <Future<List<DiscoveredService>>>[];

      for (var i = start; i <= end; i++) {
        final ip = '$subnet.$i';
        futures.add(_scanHost(ip, ports));
      }

      final batchResults = await Future.wait(futures);
      for (final batch in batchResults) {
        results.addAll(batch);
        if (results.isNotEmpty) {
          state = List.from(results); // Update state incrementally
        }
      }
    }

    state = results;
    return results;
  }

  /// Scan a single host for open ports
  Future<List<DiscoveredService>> _scanHost(String ip, List<(int, String)> ports) async {
    final found = <DiscoveredService>[];

    for (final (port, type) in ports) {
      try {
        final socket = await Socket.connect(
          ip,
          port,
          timeout: const Duration(milliseconds: 500),
        );
        socket.destroy();

        found.add(DiscoveredService(
          name: '$type at $ip',
          host: ip,
          port: port,
          type: type,
        ));
      } catch (_) {
        // Port not open or host unreachable
      }
    }

    return found;
  }

  /// Get the local IP address
  Future<String?> _getLocalIp() async {
    try {
      final interfaces = await NetworkInterface.list(
        type: InternetAddressType.IPv4,
      );
      final defaultGateway = await _getDefaultGateway();

      final candidates = <({String ip, int score})>[];
      for (final interface in interfaces) {
        final interfaceName = interface.name.toLowerCase();
        final isVirtual = _virtualInterfaceMarkers.any(interfaceName.contains);
        final isPhysical = _physicalInterfaceMarkers.any(interfaceName.contains);

        for (final addr in interface.addresses) {
          final ip = addr.address;
          if (addr.isLoopback || !_isPrivateIpv4(ip) || _isLinkLocal(ip)) {
            continue;
          }

          var score = _networkRangeScore(ip);
          if (defaultGateway != null && _sameSubnet(ip, defaultGateway)) {
            score += 1000;
          }
          if (isPhysical) score += 100;
          if (isVirtual) score -= 100;
          candidates.add((ip: ip, score: score));
        }
      }

      candidates.sort((a, b) => b.score.compareTo(a.score));
      if (candidates.isNotEmpty) return candidates.first.ip;
    } catch (_) {}
    return null;
  }

  Future<String?> _getDefaultGateway() async {
    if (!Platform.isWindows) return null;
    try {
      final result = await Process.run('route', ['print', '-4']);
      final output = '${result.stdout}\n${result.stderr}';
      final routePattern = RegExp(
        r'^\s*0\.0\.0\.0\s+0\.0\.0\.0\s+'
        r'(\d{1,3}(?:\.\d{1,3}){3})\s+\d{1,3}(?:\.\d{1,3}){3}',
        multiLine: true,
      );
      return routePattern.firstMatch(output)?.group(1);
    } catch (_) {
      return null;
    }
  }

  static const _physicalInterfaceMarkers = [
    'ethernet',
    'wi-fi',
    'wifi',
    'wlan',
    'en0',
    'en1',
    'eth',
  ];

  static const _virtualInterfaceMarkers = [
    'virtual',
    'vethernet',
    'docker',
    'wsl',
    'hyper-v',
    'vmware',
    'virtualbox',
    'loopback',
    'tunnel',
    'vpn',
    'tailscale',
    'zerotier',
    'hamachi',
  ];

  bool _isPrivateIpv4(String ip) {
    final parts = ip.split('.').map(int.tryParse).toList();
    if (parts.length != 4 || parts.any((part) => part == null)) {
      return false;
    }
    final values = parts.cast<int>();
    if (values.any((part) => part < 0 || part > 255)) return false;
    final first = values[0];
    final second = values[1];
    return first == 10 ||
        (first == 172 && second >= 16 && second <= 31) ||
        (first == 192 && second == 168);
  }

  bool _isLinkLocal(String ip) => ip.startsWith('169.254.');

  int _networkRangeScore(String ip) {
    if (ip.startsWith('192.168.')) return 30;
    if (ip.startsWith('10.')) return 20;
    if (ip.startsWith('172.')) return 10;
    return 0;
  }

  bool _sameSubnet(String first, String second) {
    final firstParts = first.split('.');
    final secondParts = second.split('.');
    return firstParts.length == 4 &&
        secondParts.length == 4 &&
        firstParts[0] == secondParts[0] &&
        firstParts[1] == secondParts[1] &&
        firstParts[2] == secondParts[2];
  }

  /// Clear scan results
  void clear() {
    state = [];
  }
}
