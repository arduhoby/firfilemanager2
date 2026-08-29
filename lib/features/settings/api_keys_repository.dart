import 'dart:convert';
import 'dart:io';

import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:path_provider/path_provider.dart';
import 'package:path/path.dart' as p;
import 'package:riverpod_annotation/riverpod_annotation.dart';

part 'api_keys_repository.g.dart';

class ApiKeyCredentials {
  final String clientId;
  final String clientSecret;

  const ApiKeyCredentials({required this.clientId, required this.clientSecret});

  Map<String, dynamic> toJson() => {
        'clientId': clientId,
        'clientSecret': clientSecret,
      };

  factory ApiKeyCredentials.fromJson(Map<String, dynamic> json) => ApiKeyCredentials(
        clientId: json['clientId'] as String? ?? '',
        clientSecret: json['clientSecret'] as String? ?? '',
      );
}

/// Repository for managing cloud OAuth2 Client IDs and Secrets
@Riverpod(keepAlive: true)
class ApiKeysRepository extends _$ApiKeysRepository {
  final _secureStorage = const FlutterSecureStorage(
    aOptions: AndroidOptions(encryptedSharedPreferences: true),
  );

  @override
  Map<String, ApiKeyCredentials> build() {
    _loadKeys();
    return {};
  }

  Future<void> _loadKeys() async {
    try {
      final json = await _secureStorage.read(key: 'api_keys');
      if (json != null) {
        final map = jsonDecode(json) as Map<String, dynamic>;
        state = map.map((key, value) => MapEntry(key, ApiKeyCredentials.fromJson(value as Map<String, dynamic>)));
      }
    } catch (e, st) {
      print('Secure Storage Read Error: $e\n$st');
    }
  }

  Future<void> saveKeys(String providerKey, String clientId, String clientSecret) async {
    final newCreds = ApiKeyCredentials(clientId: clientId, clientSecret: clientSecret);
    final newState = Map<String, ApiKeyCredentials>.from(state);
    newState[providerKey] = newCreds;
    state = newState;

    try {
      final json = jsonEncode(state.map((k, v) => MapEntry(k, v.toJson())));
      await _secureStorage.write(key: 'api_keys', value: json);
    } catch (e, st) {
      print('Secure Storage Write Error: $e\n$st');
    }
  }

  ApiKeyCredentials? getKeys(String providerKey) {
    return state[providerKey];
  }
}
