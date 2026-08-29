import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:path/path.dart' as p;
import 'package:shared_preferences/shared_preferences.dart';

/// One preferences contract for the whole application.
///
/// Normal installations keep using the platform preferences plugin. The
/// PortableApps launcher sets FIR_FILE_MANAGER_PORTABLE_DATA to the package's
/// Data directory, which switches this store to a JSON file inside that
/// directory without changing callers.
class AppPreferences {
  AppPreferences._(this._portableFile, this._sharedPreferences);

  static AppPreferences? _instance;
  static Future<AppPreferences>? _initializing;

  final File? _portableFile;
  final SharedPreferences? _sharedPreferences;
  Map<String, dynamic> _values = {};
  Future<void> _writeQueue = Future<void>.value();

  static Future<AppPreferences> getInstance() async {
    if (_instance != null) return _instance!;
    _initializing ??= _create();
    _instance = await _initializing!;
    return _instance!;
  }

  static Future<AppPreferences> _create() async {
    var dataPath = Platform.environment['FIR_FILE_MANAGER_PORTABLE_DATA'];
    if ((dataPath == null || dataPath.trim().isEmpty) && Platform.isWindows) {
      final executableDirectory = File(Platform.resolvedExecutable).parent;
      final marker = File(p.join(executableDirectory.path, 'portable.flag'));
      if (marker.existsSync()) {
        dataPath = p.join(executableDirectory.path, 'UserData');
      }
    }
    if (dataPath != null && dataPath.trim().isNotEmpty) {
      final file = File(p.join(dataPath, 'settings.json'));
      final preferences = AppPreferences._(file, null);
      await preferences._loadPortable();
      return preferences;
    }

    return AppPreferences._(null, await SharedPreferences.getInstance());
  }

  Future<void> _loadPortable() async {
    try {
      if (await _portableFile!.exists()) {
        final decoded = jsonDecode(await _portableFile.readAsString());
        if (decoded is Map<String, dynamic>) _values = decoded;
      }
    } catch (_) {
      _values = {};
    }
  }

  String? getString(String key) =>
      _sharedPreferences?.getString(key) ?? _values[key] as String?;
  bool? getBool(String key) =>
      _sharedPreferences?.getBool(key) ?? _values[key] as bool?;
  double? getDouble(String key) =>
      _sharedPreferences?.getDouble(key) ?? (_values[key] as num?)?.toDouble();
  int? getInt(String key) =>
      _sharedPreferences?.getInt(key) ?? (_values[key] as num?)?.toInt();
  List<String>? getStringList(String key) {
    final value = _sharedPreferences?.getStringList(key) ?? _values[key];
    return value is List ? value.whereType<String>().toList() : null;
  }

  Future<bool> setString(String key, String value) =>
      _set(key, value, () => _sharedPreferences!.setString(key, value));
  Future<bool> setBool(String key, bool value) =>
      _set(key, value, () => _sharedPreferences!.setBool(key, value));
  Future<bool> setDouble(String key, double value) =>
      _set(key, value, () => _sharedPreferences!.setDouble(key, value));
  Future<bool> setInt(String key, int value) =>
      _set(key, value, () => _sharedPreferences!.setInt(key, value));
  Future<bool> setStringList(String key, List<String> value) =>
      _set(key, value, () => _sharedPreferences!.setStringList(key, value));

  Future<bool> remove(String key) async {
    if (_portableFile == null) return _sharedPreferences!.remove(key);
    _values.remove(key);
    await _flush();
    return true;
  }

  Future<bool> _set(
    String key,
    dynamic value,
    Future<bool> Function() nativeWrite,
  ) async {
    if (_portableFile == null) return nativeWrite();
    _values[key] = value;
    await _flush();
    return true;
  }

  Future<void> _flush() {
    _writeQueue = _writeQueue.then((_) async {
      await _portableFile!.parent.create(recursive: true);
      final temp = File('${_portableFile.path}.tmp');
      await temp.writeAsString(
        const JsonEncoder.withIndent('  ').convert(_values),
      );
      await temp.rename(_portableFile.path);
    });
    return _writeQueue;
  }
}
