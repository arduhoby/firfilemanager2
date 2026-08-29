import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'package:path/path.dart' as p;

class FtpConnection {
  final Socket controlSocket;
  final String sharedRoot;
  final String username;
  final String password;
  final void Function(String) onLog;

  bool _isAuthenticated = false;
  String _currentDir = '/';
  
  // Data connection info
  InternetAddress? _dataAddress;
  int? _dataPort;
  ServerSocket? _passiveServer;
  Socket? _dataSocket;

  FtpConnection(
    this.controlSocket, {
    required this.sharedRoot,
    required this.username,
    required this.password,
    required this.onLog,
  }) {
    controlSocket.cast<List<int>>().transform(utf8.decoder).transform(const LineSplitter()).listen(
      _handleCommand,
      onError: (e) {
        onLog('Connection error: $e');
        close();
      },
      onDone: () {
        close();
      },
    );
    _sendReply(220, 'Fir FTP Server ready.');
  }

  Future<void> _sendReply(int code, String message) async {
    onLog('<- $code $message');
    try {
      controlSocket.write('$code $message\r\n');
      await controlSocket.flush();
    } catch (e) {
      onLog('Failed to send reply (socket closed): $e');
    }
  }

  String _getAbsolutePath(String ftpPath) {
    // Resolve relative path to absolute physical path
    final normalized = p.normalize(p.join('/', ftpPath));
    return p.normalize(p.join(sharedRoot, normalized.startsWith('/') ? normalized.substring(1) : normalized));
  }

  String _getFtpPath(String absolutePath) {
    final relative = p.relative(absolutePath, from: sharedRoot);
    if (relative == '.') return '/';
    return p.normalize(p.join('/', relative));
  }

  Future<void> _handleCommand(String line) async {
    onLog('-> $line');
    final trimmed = line.trim();
    if (trimmed.isEmpty) return;

    final parts = trimmed.split(' ');
    final cmd = parts[0].toUpperCase();
    final args = parts.skip(1).join(' ');

    try {
      if (cmd == 'USER') {
        if (args == username || username.isEmpty) {
          if (username.isEmpty) {
            _isAuthenticated = true;
            _sendReply(230, 'User logged in, proceed.');
          } else {
            _sendReply(331, 'User name okay, need password.');
          }
        } else {
          _sendReply(530, 'Invalid username.');
        }
        return;
      }

      if (cmd == 'PASS') {
        if (args == password || password.isEmpty) {
          _isAuthenticated = true;
          _sendReply(230, 'User logged in, proceed.');
        } else {
          _sendReply(530, 'Invalid password.');
        }
        return;
      }

      if (!_isAuthenticated) {
        _sendReply(530, 'Not logged in.');
        return;
      }

      switch (cmd) {
        case 'SYST':
          _sendReply(215, 'UNIX Type: L8');
          break;
        case 'PWD':
          _sendReply(257, '"$_currentDir" is current directory.');
          break;
        case 'TYPE':
          _sendReply(200, 'Type set to $args.');
          break;
        case 'PASV':
          await _setupPassiveMode();
          break;
        case 'PORT':
          _setupActiveMode(args);
          break;
        case 'LIST':
          await _handleList(args);
          break;
        case 'RETR':
          await _handleRetrieve(args);
          break;
        case 'STOR':
          await _handleStore(args);
          break;
        case 'DELE':
          await _handleDelete(args);
          break;
        case 'MKD':
          await _handleMakeDirectory(args);
          break;
        case 'RMD':
          await _handleRemoveDirectory(args);
          break;
        case 'CWD':
          _handleChangeDirectory(args);
          break;
        case 'CDUP':
          _handleChangeDirectory('..');
          break;
        case 'NOOP':
          _sendReply(200, 'NOOP ok.');
          break;
        case 'QUIT':
          _sendReply(221, 'Goodbye.');
          close();
          break;
        default:
          _sendReply(502, 'Command not implemented: $cmd');
      }
    } catch (e) {
      onLog('Error handling command $cmd: $e');
      _sendReply(550, 'Action failed: $e');
    }
  }

  Future<void> _setupPassiveMode() async {
    // Close existing passive server if any
    await _passiveServer?.close();
    _passiveServer = null;

    final server = await ServerSocket.bind(InternetAddress.anyIPv4, 0);
    _passiveServer = server;

    final port = server.port;
    final ipParts = controlSocket.address.address == '::1' || controlSocket.address.address == '127.0.0.1'
        ? [127, 0, 0, 1]
        : controlSocket.address.rawAddress;

    final p1 = port >> 8;
    final p2 = port & 0xFF;

    _sendReply(227, 'Entering Passive Mode (${ipParts.join(",")},$p1,$p2).');
  }

  void _setupActiveMode(String arg) {
    final parts = arg.split(',');
    if (parts.length != 6) {
      _sendReply(501, 'Syntax error in IP/port.');
      return;
    }
    final ip = parts.take(4).join('.');
    final p1 = int.parse(parts[4]);
    final p2 = int.parse(parts[5]);
    final port = (p1 << 8) + p2;

    _dataAddress = InternetAddress(ip);
    _dataPort = port;
    _sendReply(200, 'PORT command successful.');
  }

  Future<Socket?> _getDataConnection() async {
    if (_passiveServer != null) {
      try {
        final socket = await _passiveServer!.first.timeout(const Duration(seconds: 10));
        _dataSocket = socket;
        return socket;
      } catch (e) {
        onLog('Data connection timeout or error: $e');
        return null;
      } finally {
        await _passiveServer?.close();
        _passiveServer = null;
      }
    } else if (_dataAddress != null && _dataPort != null) {
      try {
        final socket = await Socket.connect(_dataAddress!, _dataPort!).timeout(const Duration(seconds: 10));
        _dataSocket = socket;
        return socket;
      } catch (e) {
        onLog('Could not connect to client data port: $e');
        return null;
      }
    }
    return null;
  }

  Future<void> _handleList(String arg) async {
    // Parse arguments and strip out any flags starting with '-' (e.g., -a, -la)
    final pathParts = arg.trim().split(' ').where((p) => !p.startsWith('-') && p.isNotEmpty).toList();
    final cleanArg = pathParts.join(' ');

    final targetPath = p.normalize(p.join(_currentDir, cleanArg));
    final localPath = _getAbsolutePath(targetPath);
    print('FTP SERVER: _handleList for targetPath="$targetPath" resolved to localPath="$localPath"');

    final dir = Directory(localPath);
    if (!await dir.exists()) {
      print('FTP SERVER: Directory does not exist: $localPath');
      _sendReply(550, 'Directory not found.');
      return;
    }

    _sendReply(150, 'Opening ASCII mode data connection for file list.');
    final dataSocket = await _getDataConnection();
    if (dataSocket == null) {
      print('FTP SERVER: Data connection was null!');
      _sendReply(425, 'Can\'t open data connection.');
      return;
    }

    try {
      final list = <String>[];
      await for (final entity in dir.list()) {
        final stat = await entity.stat();
        final name = p.basename(entity.path);
        final isDir = stat.type == FileSystemEntityType.directory;
        
        // Standard UNIX 10-character permissions string (e.g. drwxr-xr-x / -rwxr-xr-x)
        final typeChar = isDir ? 'd' : '-';
        final perms = isDir ? 'rwxr-xr-x' : 'rwxr-xr-x';
        final size = stat.size;
        final dateStr = _formatDate(stat.modified);
        
        list.add('$typeChar$perms   1 owner    group    $size $dateStr $name');
      }

      print('FTP SERVER: Found ${list.length} items to return.');
      dataSocket.write('${list.join("\r\n")}\r\n');
      await dataSocket.flush();
      _sendReply(226, 'Transfer complete.');
    } catch (e) {
      onLog('List error: $e');
      _sendReply(550, 'Could not list directory.');
    } finally {
      await dataSocket.close();
      _dataSocket = null;
    }
  }

  Future<void> _handleRetrieve(String arg) async {
    final targetPath = p.normalize(p.join(_currentDir, arg));
    final localPath = _getAbsolutePath(targetPath);

    final file = File(localPath);
    if (!await file.exists()) {
      _sendReply(550, 'File not found.');
      return;
    }

    _sendReply(150, 'Opening BINARY mode data connection for $arg.');
    final dataSocket = await _getDataConnection();
    if (dataSocket == null) {
      _sendReply(425, 'Can\'t open data connection.');
      return;
    }

    try {
      await dataSocket.addStream(file.openRead());
      await dataSocket.flush();
      _sendReply(226, 'Transfer complete.');
    } catch (e) {
      onLog('Retrieve error: $e');
      _sendReply(550, 'Error transferring file.');
    } finally {
      await dataSocket.close();
      _dataSocket = null;
    }
  }

  Future<void> _handleStore(String arg) async {
    final targetPath = p.normalize(p.join(_currentDir, arg));
    final localPath = _getAbsolutePath(targetPath);

    final file = File(localPath);
    
    // Ensure parent directory exists
    final parentDir = Directory(p.dirname(localPath));
    if (!await parentDir.exists()) {
      _sendReply(550, 'Parent directory does not exist.');
      return;
    }

    _sendReply(150, 'Opening BINARY mode data connection for $arg.');
    final dataSocket = await _getDataConnection();
    if (dataSocket == null) {
      _sendReply(425, 'Can\'t open data connection.');
      return;
    }

    try {
      final ios = file.openWrite();
      await ios.addStream(dataSocket);
      await ios.close();
      _sendReply(226, 'Transfer complete.');
    } catch (e) {
      onLog('Store error: $e');
      _sendReply(550, 'Error writing file.');
    } finally {
      await dataSocket.close();
      _dataSocket = null;
    }
  }

  Future<void> _handleDelete(String arg) async {
    final targetPath = p.normalize(p.join(_currentDir, arg));
    final localPath = _getAbsolutePath(targetPath);
    final file = File(localPath);

    if (await file.exists()) {
      await file.delete();
      _sendReply(250, 'File deleted successfully.');
    } else {
      _sendReply(550, 'File not found.');
    }
  }

  Future<void> _handleMakeDirectory(String arg) async {
    final targetPath = p.normalize(p.join(_currentDir, arg));
    final localPath = _getAbsolutePath(targetPath);
    final dir = Directory(localPath);

    if (await dir.exists()) {
      _sendReply(550, 'Directory already exists.');
    } else {
      await dir.create(recursive: true);
      _sendReply(257, '"$targetPath" directory created.');
    }
  }

  Future<void> _handleRemoveDirectory(String arg) async {
    final targetPath = p.normalize(p.join(_currentDir, arg));
    final localPath = _getAbsolutePath(targetPath);
    final dir = Directory(localPath);

    if (await dir.exists()) {
      await dir.delete(recursive: true);
      _sendReply(250, 'Directory deleted successfully.');
    } else {
      _sendReply(550, 'Directory not found.');
    }
  }

  void _handleChangeDirectory(String arg) {
    final targetPath = p.normalize(p.join(_currentDir, arg));
    final localPath = _getAbsolutePath(targetPath);
    
    if (Directory(localPath).existsSync()) {
      _currentDir = targetPath;
      _sendReply(250, 'Directory changed to $_currentDir');
    } else {
      _sendReply(550, 'Directory not found.');
    }
  }

  String _formatDate(DateTime dt) {
    final months = ['Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun', 'Jul', 'Aug', 'Sep', 'Oct', 'Nov', 'Dec'];
    final month = months[dt.month - 1];
    final day = dt.day.toString().padLeft(2, ' ');
    final hour = dt.hour.toString().padLeft(2, '0');
    final minute = dt.minute.toString().padLeft(2, '0');
    return '$month $day $hour:$minute';
  }

  void close() {
    controlSocket.close();
    _dataSocket?.close();
    _passiveServer?.close();
  }
}

class FtpServerInstance {
  final String sharedRoot;
  final int port;
  final String username;
  final String password;
  final void Function(String log) onLog;
  final void Function(String clientIp, bool connected) onClientConnection;

  ServerSocket? _serverSocket;
  final List<FtpConnection> _connections = [];

  FtpServerInstance({
    required this.sharedRoot,
    required this.port,
    required this.username,
    required this.password,
    required this.onLog,
    required this.onClientConnection,
  });

  Future<void> start() async {
    _serverSocket = await ServerSocket.bind(InternetAddress.anyIPv4, port);
    onLog('FTP Server listening on port $port');

    _serverSocket!.listen((socket) {
      final clientIp = socket.remoteAddress.address;
      onLog('Client connected: $clientIp:${socket.remotePort}');
      onClientConnection(clientIp, true);

      final connection = FtpConnection(
        socket,
        sharedRoot: sharedRoot,
        username: username,
        password: password,
        onLog: (msg) => onLog('[$clientIp] $msg'),
      );

      _connections.add(connection);

      socket.done.then((_) {
        onLog('Client disconnected: $clientIp');
        onClientConnection(clientIp, false);
        _connections.remove(connection);
      });
    }, onError: (e) {
      onLog('FTP Server error: $e');
    });
  }

  Future<void> stop() async {
    for (final conn in List.from(_connections)) {
      conn.close();
    }
    _connections.clear();
    await _serverSocket?.close();
    _serverSocket = null;
    onLog('FTP Server stopped');
  }
}
