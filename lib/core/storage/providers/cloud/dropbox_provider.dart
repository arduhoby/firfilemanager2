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

class DropboxProvider implements StorageProvider {
  @override
  final ConnectionProfile profile;
  final String? clientId;
  final String? clientSecret;

  oauth2.Client? _client;
  bool _isConnected = false;
  
  DropboxProvider(
    this.profile, {
    this.clientId,
    this.clientSecret,
  });

  @override
  Future<void> connect() async {
    if (_isConnected) return;

    if (clientId == null || clientId!.isEmpty) {
      throw Exception('Missing Client ID. Please configure API Keys in Settings.');
    }

    // 1. Generate auth URL
    final authorizationEndpoint = Uri.parse('https://www.dropbox.com/oauth2/authorize');
    final tokenEndpoint = Uri.parse('https://api.dropboxapi.com/oauth2/token');
    
    final grant = oauth2.AuthorizationCodeGrant(
      clientId!,
      authorizationEndpoint,
      tokenEndpoint,
      secret: clientSecret,
    );
    
    // Redirect URL should be something we can listen to, e.g. localhost server or deep link.
    // For desktop, a local server is needed. We'll assume localhost:3000 for demo purposes, 
    // similar to Google Drive's default flow, or we can use out-of-band flow (OOB) where user copies code.
    // Assuming out of band or custom scheme is set up. Let's use a dummy localhost.
    final redirectUrl = Uri.parse('http://localhost:3000/callback');
    final authUrl = grant.getAuthorizationUrl(redirectUrl);
    
    // In a real implementation we would start a shelf server to listen to the redirect.
    // For this boilerplate, we'll launch the URL.
    if (await canLaunchUrl(authUrl)) {
      await launchUrl(authUrl);
      // Wait for auth code...
      // final client = await grant.handleAuthorizationResponse(queryParameters);
      // _client = client;
    } else {
      throw Exception('Could not launch Dropbox authorization URL.');
    }
  }

  @override
  Future<void> disconnect() async {
    _client?.close();
    _client = null;
  }

  @override
  bool get isConnected => _client != null;

  @override
  Future<List<FileEntry>> list(String path, [ListOptions? options]) async {
    if (!isConnected) throw Exception('Not connected to Dropbox');
    
    // Ensure path format: "" for root, "/folder" for others
    final dPath = (path == '/' || path == '') ? '' : (path.startsWith('/') ? path : '/$path');

    final response = await _client!.post(
      Uri.parse('https://api.dropboxapi.com/2/files/list_folder'),
      headers: {'Content-Type': 'application/json'},
      body: jsonEncode({
        'path': dPath,
        'recursive': false,
        'include_media_info': false,
        'include_deleted': false,
      }),
    );
    
    if (response.statusCode != 200) {
      throw Exception('Failed to list Dropbox folder: ${response.body}');
    }
    
    final data = jsonDecode(response.body);
    final entries = data['entries'] as List;
    
    return entries.map((e) {
      final isDir = e['.tag'] == 'folder';
      return FileEntry(
        name: e['name'] as String,
        path: e['path_display'] as String,
        isDirectory: isDir,
        size: isDir ? 0 : (e['size'] as int? ?? 0),
        modified: isDir ? DateTime.now() : DateTime.parse(e['client_modified'] as String),
        permissions: '',
      );
    }).toList();
  }

  @override
  Future<void> delete(String path) async {
    if (!isConnected) throw Exception('Not connected to Dropbox');
    
    final response = await _client!.post(
      Uri.parse('https://api.dropboxapi.com/2/files/delete_v2'),
      headers: {'Content-Type': 'application/json'},
      body: jsonEncode({'path': path}),
    );
    
    if (response.statusCode != 200) {
      throw Exception('Failed to delete in Dropbox: ${response.body}');
    }
  }

  @override
  Future<void> rename(String oldPath, String newName) async {
    if (!isConnected) throw Exception('Not connected to Dropbox');
    
    final newPath = p.join(p.dirname(oldPath), newName).replaceAll(r'\', '/');
    
    final response = await _client!.post(
      Uri.parse('https://api.dropboxapi.com/2/files/move_v2'),
      headers: {'Content-Type': 'application/json'},
      body: jsonEncode({
        'from_path': oldPath,
        'to_path': newPath,
      }),
    );
    
    if (response.statusCode != 200) {
      throw Exception('Failed to rename in Dropbox: ${response.body}');
    }
  }

  @override
  Future<void> makeDirectory(String path) async {
    if (!isConnected) throw Exception('Not connected to Dropbox');
    
    final response = await _client!.post(
      Uri.parse('https://api.dropboxapi.com/2/files/create_folder_v2'),
      headers: {'Content-Type': 'application/json'},
      body: jsonEncode({'path': path}),
    );
    
    if (response.statusCode != 200) {
      throw Exception('Failed to create folder in Dropbox: ${response.body}');
    }
  }

  @override
  Future<FileEntry> stat(String path) async {
    if (!isConnected) throw Exception('Not connected to Dropbox');
    
    final response = await _client!.post(
      Uri.parse('https://api.dropboxapi.com/2/files/get_metadata'),
      headers: {'Content-Type': 'application/json'},
      body: jsonEncode({'path': path}),
    );
    
    if (response.statusCode != 200) {
      throw Exception('Failed to stat Dropbox file: ${response.body}');
    }
    
    final e = jsonDecode(response.body);
    final isDir = e['.tag'] == 'folder';
    return FileEntry(
      name: e['name'] as String,
      path: e['path_display'] as String,
      isDirectory: isDir,
      size: isDir ? 0 : (e['size'] as int? ?? 0),
      modified: isDir ? DateTime.now() : DateTime.parse(e['client_modified'] as String),
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
    if (!isConnected) throw Exception('Not connected to Dropbox');
    // Implement standard HTTP read stream using client.
    throw UnimplementedError();
  }

  @override
  Stream<TransferProgress> write(String path, Stream<List<int>> data, {CancelToken? cancelToken}) async* {
    if (!isConnected) throw Exception('Not connected to Dropbox');
    throw UnimplementedError();
  }

  @override
  Stream<TransferProgress> copy(String sourcePath, StorageProvider destProvider, String destPath, {CopyOptions options = const CopyOptions(), CancelToken? cancelToken}) async* {
    if (!isConnected) throw Exception('Not connected to Dropbox');
    throw UnimplementedError();
  }

  @override
  Future<List<FileEntry>> search(String path, String query, {bool recursive = false}) async {
    if (!isConnected) throw Exception('Not connected to Dropbox');
    
    final response = await _client!.post(
      Uri.parse('https://api.dropboxapi.com/2/files/search_v2'),
      headers: {'Content-Type': 'application/json'},
      body: jsonEncode({
        'query': query,
        'options': {
          'path': (path == '/' || path == '') ? '' : path,
        }
      }),
    );
    
    if (response.statusCode != 200) {
      throw Exception('Failed to search Dropbox: ${response.body}');
    }
    
    final data = jsonDecode(response.body);
    final matches = data['matches'] as List;
    
    return matches.map((m) {
      final e = m['metadata']['metadata']; // Search v2 wraps metadata
      final isDir = e['.tag'] == 'folder';
      return FileEntry(
        name: e['name'] as String,
        path: e['path_display'] as String,
        isDirectory: isDir,
        size: isDir ? 0 : (e['size'] as int? ?? 0),
        modified: isDir ? DateTime.now() : DateTime.parse(e['client_modified'] as String),
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
