import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'package:path/path.dart' as p;
import 'package:shelf/shelf.dart';
import 'package:shelf/shelf_io.dart' as io;

class WebDavServerInstance {
  final String sharedRoot;
  final int port;
  final String username;
  final String password;
  final void Function(String log) onLog;
  final void Function(String clientIp, bool connected) onClientConnection;

  HttpServer? _server;

  WebDavServerInstance({
    required this.sharedRoot,
    required this.port,
    required this.username,
    required this.password,
    required this.onLog,
    required this.onClientConnection,
  });

  Future<void> start() async {
    final pipeline = const Pipeline()
        .addMiddleware(logRequests())
        .addMiddleware(_authMiddleware)
        .addHandler(_handleRequest);

    _server = await io.serve(pipeline, InternetAddress.anyIPv4, port);
    onLog('WebDAV Server listening on port $port');
  }

  Future<void> stop() async {
    await _server?.close(force: true);
    _server = null;
    onLog('WebDAV Server stopped');
  }

  Middleware get _authMiddleware {
    return (innerHandler) {
      return (request) async {
        if (username.isEmpty && password.isEmpty) {
          return innerHandler(request);
        }

        final authHeader = request.headers['Authorization'] ?? request.headers['authorization'];
        if (authHeader == null || !authHeader.startsWith('Basic ')) {
          return Response(
            401,
            headers: {
              'WWW-Authenticate': 'Basic realm="Fir WebDAV"',
              'Content-Type': 'text/plain',
            },
            body: 'Unauthorized',
          );
        }

        try {
          final credentials = utf8.decode(base64.decode(authHeader.substring(6))).split(':');
          if (credentials.length == 2 && credentials[0] == username && credentials[1] == password) {
            return innerHandler(request);
          }
        } catch (_) {}

        return Response(
          401,
          headers: {
            'WWW-Authenticate': 'Basic realm="Fir WebDAV"',
            'Content-Type': 'text/plain',
          },
          body: 'Unauthorized',
        );
      };
    };
  }

  Future<Response> _handleRequest(Request request) async {
    final clientIp = request.context['shelf.io.connection_info'] is HttpConnectionInfo
        ? (request.context['shelf.io.connection_info'] as HttpConnectionInfo).remoteAddress.address
        : 'unknown';

    onClientConnection(clientIp, true);
    onLog('[WebDAV] <- ${request.method} ${request.requestedUri.path}');

    try {
      final method = request.method.toUpperCase();
      final ftpPath = Uri.decodeComponent(request.requestedUri.path);
      final localPath = _getAbsolutePath(ftpPath);

      switch (method) {
        case 'OPTIONS':
          return Response(200, headers: {
            'DAV': '1, 2',
            'Allow': 'OPTIONS, GET, HEAD, POST, PUT, DELETE, PROPFIND, MKCOL, COPY, MOVE',
            'Content-Length': '0',
          });
        case 'PROPFIND':
          return await _handlePropfind(localPath, request.requestedUri.path, request);
        case 'GET':
          return await _handleGet(localPath);
        case 'PUT':
          return await _handlePut(localPath, request);
        case 'DELETE':
          return await _handleDelete(localPath);
        case 'MKCOL':
          return await _handleMkcol(localPath);
        case 'MOVE':
          return await _handleMoveOrCopy(localPath, request, isMove: true);
        case 'COPY':
          return await _handleMoveOrCopy(localPath, request, isMove: false);
        default:
          return Response(501, body: 'Method Not Implemented');
      }
    } catch (e) {
      onLog('[WebDAV] Error handling request: $e');
      return Response(500, body: 'Internal Server Error: $e');
    } finally {
      onClientConnection(clientIp, false);
    }
  }

  String _getAbsolutePath(String requestPath) {
    final normalized = p.normalize(p.join('/', requestPath));
    return p.normalize(p.join(sharedRoot, normalized.startsWith('/') ? normalized.substring(1) : normalized));
  }

  Future<Response> _handlePropfind(String localPath, String requestPath, Request request) async {
    final depthHeader = request.headers['Depth'] ?? request.headers['depth'] ?? '1';
    final isCollection = Directory(localPath).existsSync();

    if (!isCollection && !File(localPath).existsSync()) {
      return Response(404, body: 'Not Found');
    }

    final buffer = StringBuffer();
    buffer.write('<?xml version="1.0" encoding="utf-8" ?>\n');
    buffer.write('<d:multistatus xmlns:d="DAV:">\n');

    Future<void> addEntry(FileSystemEntity entity, String reqPath) async {
      final stat = await entity.stat();
      final isDir = stat.type == FileSystemEntityType.directory;
      final name = p.basename(entity.path);
      final size = stat.size;
      final modified = stat.modified.toUtc().toIso8601String();

      // Ensure directory URLs end with a slash
      final displayPath = isDir ? (reqPath.endsWith('/') ? reqPath : '$reqPath/') : reqPath;

      buffer.write('  <d:response>\n');
      buffer.write('    <d:href>${Uri.encodeFull(displayPath)}</d:href>\n');
      buffer.write('    <d:propstat>\n');
      buffer.write('      <d:prop>\n');
      if (isDir) {
        buffer.write('        <d:resourcetype><d:collection/></d:resourcetype>\n');
      } else {
        buffer.write('        <d:resourcetype/>\n');
        buffer.write('        <d:getcontentlength>$size</d:getcontentlength>\n');
      }
      buffer.write('        <d:getlastmodified>${stat.modified.toUtc()}</d:getlastmodified>\n');
      buffer.write('        <d:displayname>$name</d:displayname>\n');
      buffer.write('      </d:prop>\n');
      buffer.write('      <d:status>HTTP/1.1 200 OK</d:status>\n');
      buffer.write('    </d:propstat>\n');
      buffer.write('  </d:response>\n');
    }

    // Add requested resource itself
    await addEntry(
      isCollection ? Directory(localPath) : File(localPath),
      requestPath,
    );

    // If it's a directory and Depth is not '0', add its children
    if (isCollection && depthHeader != '0') {
      final dir = Directory(localPath);
      await for (final child in dir.list()) {
        final childReqPath = p.normalize(p.join(requestPath, p.basename(child.path)));
        await addEntry(child, childReqPath);
      }
    }

    buffer.write('</d:multistatus>');

    return Response(
      207,
      headers: {'Content-Type': 'application/xml; charset="utf-8"'},
      body: buffer.toString(),
    );
  }

  Future<Response> _handleGet(String localPath) async {
    final file = File(localPath);
    if (!await file.exists()) {
      return Response(404, body: 'File Not Found');
    }

    return Response.ok(
      file.openRead(),
      headers: {
        'Content-Type': 'application/octet-stream',
        'Content-Length': (await file.length()).toString(),
      },
    );
  }

  Future<Response> _handlePut(String localPath, Request request) async {
    final file = File(localPath);
    final parent = Directory(p.dirname(localPath));

    if (!await parent.exists()) {
      await parent.create(recursive: true);
    }

    try {
      final ios = file.openWrite();
      await ios.addStream(request.read());
      await ios.close();
      return Response(201, body: 'Created');
    } catch (e) {
      return Response(500, body: 'Failed to write file: $e');
    }
  }

  Future<Response> _handleDelete(String localPath) async {
    if (Directory(localPath).existsSync()) {
      await Directory(localPath).delete(recursive: true);
      return Response(204, body: 'No Content');
    } else if (File(localPath).existsSync()) {
      await File(localPath).delete();
      return Response(204, body: 'No Content');
    }
    return Response(404, body: 'Not Found');
  }

  Future<Response> _handleMkcol(String localPath) async {
    final dir = Directory(localPath);
    if (await dir.exists()) {
      return Response(405, body: 'Method Not Allowed (Already Exists)');
    }
    await dir.create(recursive: true);
    return Response(201, body: 'Created');
  }

  Future<Response> _handleMoveOrCopy(String localPath, Request request, {required bool isMove}) async {
    final destinationHeader = request.headers['Destination'] ?? request.headers['destination'];
    if (destinationHeader == null) {
      return Response(400, body: 'Missing Destination Header');
    }

    final destUri = Uri.parse(destinationHeader);
    final destFtpPath = Uri.decodeComponent(destUri.path);
    final destLocalPath = _getAbsolutePath(destFtpPath);

    final destParent = Directory(p.dirname(destLocalPath));
    if (!await destParent.exists()) {
      return Response(409, body: 'Conflict (Parent Directory Missing)');
    }

    final overwrite = (request.headers['Overwrite'] ?? request.headers['overwrite'] ?? 'T').toUpperCase() == 'T';

    if (FileSystemEntity.isFileSync(destLocalPath) || FileSystemEntity.isDirectorySync(destLocalPath)) {
      if (!overwrite) {
        return Response(412, body: 'Precondition Failed (Overwrite is false)');
      }
      // Delete existing
      if (FileSystemEntity.isDirectorySync(destLocalPath)) {
        await Directory(destLocalPath).delete(recursive: true);
      } else {
        await File(destLocalPath).delete();
      }
    }

    if (isMove) {
      if (FileSystemEntity.isDirectorySync(localPath)) {
        await Directory(localPath).rename(destLocalPath);
      } else {
        await File(localPath).rename(destLocalPath);
      }
    } else {
      // Copy implementation
      if (FileSystemEntity.isDirectorySync(localPath)) {
        await _copyDirectory(Directory(localPath), Directory(destLocalPath));
      } else {
        await File(localPath).copy(destLocalPath);
      }
    }

    return Response(isMove ? 201 : 204, body: isMove ? 'Created' : 'No Content');
  }

  Future<void> _copyDirectory(Directory source, Directory destination) async {
    await destination.create(recursive: true);
    await for (final entity in source.list(recursive: false)) {
      if (entity is Directory) {
        final newDirectory = Directory(p.join(destination.absolute.path, p.basename(entity.path)));
        await _copyDirectory(entity, newDirectory);
      } else if (entity is File) {
        await entity.copy(p.join(destination.path, p.basename(entity.path)));
      }
    }
  }
}
