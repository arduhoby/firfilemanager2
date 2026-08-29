import 'dart:io';
import 'package:riverpod_annotation/riverpod_annotation.dart';
import '../../core/server/ftp_server.dart';
import '../../core/server/webdav_server.dart';

part 'server_state.g.dart';

enum ServerType { ftp, webdav }

class ServerConfigState {
  final bool isFtpRunning;
  final bool isWebDavRunning;
  final String sharedFolder;
  final int ftpPort;
  final int webDavPort;
  final String username;
  final String password;
  final List<String> activeConnections;
  final List<String> logs;

  const ServerConfigState({
    this.isFtpRunning = false,
    this.isWebDavRunning = false,
    this.sharedFolder = '',
    this.ftpPort = 2121,
    this.webDavPort = 8080,
    this.username = 'admin',
    this.password = 'admin',
    this.activeConnections = const [],
    this.logs = const [],
  });

  ServerConfigState copyWith({
    bool? isFtpRunning,
    bool? isWebDavRunning,
    String? sharedFolder,
    int? ftpPort,
    int? webDavPort,
    String? username,
    String? password,
    List<String>? activeConnections,
    List<String>? logs,
  }) {
    return ServerConfigState(
      isFtpRunning: isFtpRunning ?? this.isFtpRunning,
      isWebDavRunning: isWebDavRunning ?? this.isWebDavRunning,
      sharedFolder: sharedFolder ?? this.sharedFolder,
      ftpPort: ftpPort ?? this.ftpPort,
      webDavPort: webDavPort ?? this.webDavPort,
      username: username ?? this.username,
      password: password ?? this.password,
      activeConnections: activeConnections ?? this.activeConnections,
      logs: logs ?? this.logs,
    );
  }
}

@Riverpod(keepAlive: true)
class ServerState extends _$ServerState {
  FtpServerInstance? _ftpServer;
  WebDavServerInstance? _webDavServer;

  @override
  ServerConfigState build() {
    String defaultFolder = '';
    try {
      if (Platform.isMacOS || Platform.isLinux) {
        defaultFolder = Platform.environment['HOME'] ?? '';
      } else if (Platform.isWindows) {
        defaultFolder = Platform.environment['USERPROFILE'] ?? '';
      }
    } catch (_) {}
    return ServerConfigState(sharedFolder: defaultFolder);
  }

  void updateConfig({
    String? sharedFolder,
    int? ftpPort,
    int? webDavPort,
    String? username,
    String? password,
  }) {
    state = state.copyWith(
      sharedFolder: sharedFolder,
      ftpPort: ftpPort,
      webDavPort: webDavPort,
      username: username,
      password: password,
    );
  }

  void addLog(String message) {
    final timeStr = DateTime.now().toLocal().toString().split(' ')[1].substring(0, 8);
    state = state.copyWith(
      logs: [...state.logs, '[$timeStr] $message'],
    );
    // Print to Flutter console so the developer can see it in terminal logs
    print('SERVER LOG: $message');
  }

  void clearLogs() {
    state = state.copyWith(logs: []);
  }

  Future<void> startFtp() async {
    if (state.isFtpRunning) return;
    if (state.sharedFolder.isEmpty) {
      addLog('Error: Shared folder is not set.');
      return;
    }

    try {
      _ftpServer = FtpServerInstance(
        sharedRoot: state.sharedFolder,
        port: state.ftpPort,
        username: state.username,
        password: state.password,
        onLog: (msg) {
          addLog('[FTP] $msg');
        },
        onClientConnection: (ip, connected) {
          final current = List<String>.from(state.activeConnections);
          if (connected) {
            if (!current.contains(ip)) {
              current.add(ip);
            }
          } else {
            current.remove(ip);
          }
          state = state.copyWith(activeConnections: current);
        },
      );

      await _ftpServer!.start();
      state = state.copyWith(isFtpRunning: true);
      addLog('FTP Server successfully started.');
    } catch (e) {
      addLog('Failed to start FTP Server: $e');
      _ftpServer = null;
    }
  }

  Future<void> stopFtp() async {
    if (!state.isFtpRunning) return;
    try {
      await _ftpServer?.stop();
      _ftpServer = null;
      state = state.copyWith(
        isFtpRunning: false,
        activeConnections: [],
      );
      addLog('FTP Server stopped.');
    } catch (e) {
      addLog('Error stopping FTP Server: $e');
    }
  }

  Future<void> startWebDav() async {
    if (state.isWebDavRunning) return;
    if (state.sharedFolder.isEmpty) {
      addLog('Error: Shared folder is not set.');
      return;
    }

    try {
      _webDavServer = WebDavServerInstance(
        sharedRoot: state.sharedFolder,
        port: state.webDavPort,
        username: state.username,
        password: state.password,
        onLog: (msg) {
          addLog('[WebDAV] $msg');
        },
        onClientConnection: (ip, connected) {
          final current = List<String>.from(state.activeConnections);
          if (connected) {
            if (!current.contains(ip)) {
              current.add(ip);
            }
          } else {
            current.remove(ip);
          }
          state = state.copyWith(activeConnections: current);
        },
      );

      await _webDavServer!.start();
      state = state.copyWith(isWebDavRunning: true);
      addLog('WebDAV Server successfully started.');
    } catch (e) {
      addLog('Failed to start WebDAV Server: $e');
      _webDavServer = null;
    }
  }

  Future<void> stopWebDav() async {
    if (!state.isWebDavRunning) return;
    try {
      await _webDavServer?.stop();
      _webDavServer = null;
      state = state.copyWith(
        isWebDavRunning: false,
        activeConnections: [],
      );
      addLog('WebDAV Server stopped.');
    } catch (e) {
      addLog('Error stopping WebDAV Server: $e');
    }
  }
}
