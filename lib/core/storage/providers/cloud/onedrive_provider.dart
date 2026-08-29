import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:http/http.dart' as http;
import 'package:oauth2/oauth2.dart' as oauth2;
import 'package:path/path.dart' as p;
import 'package:url_launcher/url_launcher.dart';
import 'package:dio/dio.dart' as dio;

import '../../models/connection_profile.dart';
import '../../models/file_entry.dart';
import '../../models/transfer_progress.dart';
import '../../storage_provider.dart';

class OneDriveProvider implements StorageProvider {
  @override
  final ConnectionProfile profile;
  final String? clientId;
  final String? clientSecret;
  
  oauth2.Client? _client;
  
  OneDriveProvider(
    this.profile, {
    this.clientId,
    this.clientSecret,
  });

  @override
  Future<void> connect() async {
    if (clientId == null || clientId!.isEmpty) {
      throw Exception('Missing Client ID. Please configure API Keys in Settings.');
    }

    final authorizationEndpoint = Uri.parse('https://login.microsoftonline.com/common/oauth2/v2.0/authorize');
    final tokenEndpoint = Uri.parse('https://login.microsoftonline.com/common/oauth2/v2.0/token');
    
    final grant = oauth2.AuthorizationCodeGrant(
      clientId!,
      authorizationEndpoint,
      tokenEndpoint,
      secret: clientSecret,
    );
    
    final redirectUrl = Uri.parse('http://localhost:3000/callback');
    final authUrl = grant.getAuthorizationUrl(
      redirectUrl,
      scopes: ['Files.ReadWrite.All', 'offline_access'],
    );
    
    if (await canLaunchUrl(authUrl)) {
      await launchUrl(authUrl);
      // Wait for auth code...
      // final client = await grant.handleAuthorizationResponse(queryParameters);
      // _client = client;
    } else {
      throw Exception('Could not launch OneDrive authorization URL.');
    }
  }

  @override
  Future<void> disconnect() async {
    _client?.close();
    _client = null;
  }

  @override
  bool get isConnected => _client != null;

  String _buildGraphPath(String path) {
    if (path == '/' || path == '') return '/drive/root';
    return '/drive/root:${path.startsWith('/') ? path : '/$path'}';
  }

  @override
  Future<List<FileEntry>> list(String path, [ListOptions? options]) async {
    if (!isConnected) throw Exception('Not connected to OneDrive');
    
    final gPath = _buildGraphPath(path);
    final response = await _client!.get(
      Uri.parse('https://graph.microsoft.com/v1.0/me$gPath/children'),
    );
    
    if (response.statusCode != 200) {
      throw Exception('Failed to list OneDrive folder: ${response.body}');
    }
    
    final data = jsonDecode(response.body);
    final items = data['value'] as List;
    
    return items.map((e) {
      final isDir = (e as Map).containsKey('folder');
      return FileEntry(
        name: e['name'] as String,
        path: p.join(path, e['name'] as String).replaceAll(r'\', '/'),
        isDirectory: isDir,
        size: e['size'] as int? ?? 0,
        modified: DateTime.parse(e['lastModifiedDateTime'] as String),
        permissions: '',
      );
    }).toList();
  }

  @override
  Future<void> delete(String path) async {
    if (!isConnected) throw Exception('Not connected to OneDrive');
    
    final gPath = _buildGraphPath(path);
    final response = await _client!.delete(
      Uri.parse('https://graph.microsoft.com/v1.0/me$gPath'),
    );
    
    if (response.statusCode != 204) {
      throw Exception('Failed to delete in OneDrive: ${response.body}');
    }
  }

  @override
  Future<void> rename(String oldPath, String newName) async {
    if (!isConnected) throw Exception('Not connected to OneDrive');
    
    final gPath = _buildGraphPath(oldPath);
    final response = await _client!.patch(
      Uri.parse('https://graph.microsoft.com/v1.0/me$gPath'),
      headers: {'Content-Type': 'application/json'},
      body: jsonEncode({
        'name': newName,
      }),
    );
    
    if (response.statusCode != 200) {
      throw Exception('Failed to rename in OneDrive: ${response.body}');
    }
  }

  @override
  Future<void> makeDirectory(String path) async {
    if (!isConnected) throw Exception('Not connected to OneDrive');
    
    final parent = p.dirname(path);
    final name = p.basename(path);
    final gPath = _buildGraphPath(parent);
    
    final response = await _client!.post(
      Uri.parse('https://graph.microsoft.com/v1.0/me$gPath/children'),
      headers: {'Content-Type': 'application/json'},
      body: jsonEncode({
        'name': name,
        'folder': {},
        '@microsoft.graph.conflictBehavior': 'rename'
      }),
    );
    
    if (response.statusCode != 201) {
      throw Exception('Failed to create folder in OneDrive: ${response.body}');
    }
  }

  @override
  Future<FileEntry> stat(String path) async {
    if (!isConnected) throw Exception('Not connected to OneDrive');
    
    final gPath = _buildGraphPath(path);
    final response = await _client!.get(
      Uri.parse('https://graph.microsoft.com/v1.0/me$gPath'),
    );
    
    if (response.statusCode != 200) {
      throw Exception('Failed to stat OneDrive file: ${response.body}');
    }
    
    final e = jsonDecode(response.body);
    final isDir = (e as Map).containsKey('folder');
    return FileEntry(
      name: e['name'] as String,
      path: path,
      isDirectory: isDir,
      size: e['size'] as int? ?? 0,
      modified: DateTime.parse(e['lastModifiedDateTime'] as String),
      permissions: '',
    );
  }

  @override
  Future<void> mkdir(String path) async {
    throw UnimplementedError();
  }

  @override
  Future<bool> exists(String path) async {
    try {
      await stat(path);
      return true;
    } catch (_) {
      return false;
    }
  }

  @override
  String basename(String path) => p.basename(path);

  @override
  String dirname(String path) => p.dirname(path);

  @override
  Stream<TransferProgress> read(String path, {CancelToken? cancelToken}) async* {
    if (!isConnected) throw Exception('Not connected to OneDrive');
    throw UnimplementedError();
  }

  @override
  Stream<TransferProgress> write(String path, Stream<List<int>> data, {CancelToken? cancelToken}) async* {
    if (!isConnected) throw Exception('Not connected to OneDrive');
    throw UnimplementedError();
  }

  @override
  Stream<TransferProgress> copy(String sourcePath, StorageProvider destProvider, String destPath, {CopyOptions options = const CopyOptions(), CancelToken? cancelToken}) async* {
    if (!isConnected) throw Exception('Not connected to OneDrive');
    throw UnimplementedError();
  }

  @override
  Future<List<FileEntry>> search(String path, String query, {bool recursive = false}) async {
    if (!isConnected) throw Exception('Not connected to OneDrive');
    
    // Microsoft Graph search API
    final response = await _client!.get(
      Uri.parse('https://graph.microsoft.com/v1.0/me/drive/root/search(q=\'$query\')'),
    );
    
    if (response.statusCode != 200) {
      throw Exception('Failed to search OneDrive: ${response.body}');
    }
    
    final data = jsonDecode(response.body);
    final items = data['value'] as List;
    
    return items.map((e) {
      final isDir = (e as Map).containsKey('folder');
      // Constructing full path is tricky in search results without parsing parentReference
      // We will use name for now, and try to extract path if available.
      final parentPath = e['parentReference']?['path']?.toString() ?? '';
      final decodedPath = Uri.decodeFull(parentPath.replaceFirst('/drive/root:', ''));
      return FileEntry(
        name: e['name'] as String,
        path: p.join(decodedPath, e['name'] as String).replaceAll(r'\', '/'),
        isDirectory: isDir,
        size: e['size'] as int? ?? 0,
        modified: DateTime.parse(e['lastModifiedDateTime'] as String),
        permissions: '',
      );
    }).toList();
  }

  @override
  String get displayName => profile.name;

  @override
  Stream<bool> get connectionStateChanges => const Stream.empty();

  @override
  Future<void> move(String sourcePath, String destPath) async {
    throw UnimplementedError('Move is not implemented yet');
  }

  @override
  Future<DiskSpaceInfo?> getDiskSpaceInfo(String path) async => null;

  @override
  Future<String> get homePath async => '/';

  @override
  String normalizePath(String path) => path;

  @override
  String joinPath(String parent, String child) => '$parent/$child'.replaceAll('//', '/');

  @override
  bool supports(ProviderCapability capability) {
    return [
      ProviderCapability.list,
      ProviderCapability.read,
      ProviderCapability.write,
      ProviderCapability.delete,
      ProviderCapability.mkdir,
    ].contains(capability);
  }
}
