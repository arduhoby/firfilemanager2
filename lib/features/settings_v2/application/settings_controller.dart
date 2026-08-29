import '../domain/app_settings.dart';
import '../domain/settings_repository.dart';

typedef SettingsListener = void Function(AppSettings settings);

class SettingsController {
  SettingsController(this._repository);

  final SettingsRepository _repository;
  final List<SettingsListener> _listeners = <SettingsListener>[];
  AppSettings? _settings;

  AppSettings? get current => _settings;

  Future<AppSettings> load() async {
    final loaded = await _repository.load();
    _settings = loaded;
    _notify();
    return loaded;
  }

  Future<void> update(
    AppSettings Function(AppSettings current) transform,
  ) async {
    final currentSettings = _settings;
    if (currentSettings == null) {
      throw StateError('Settings must be loaded before they are updated.');
    }
    final updated = transform(currentSettings);
    await _repository.save(updated);
    _settings = updated;
    _notify();
  }

  void addListener(SettingsListener listener) => _listeners.add(listener);

  void removeListener(SettingsListener listener) => _listeners.remove(listener);

  void _notify() {
    final settings = _settings;
    if (settings == null) return;
    for (final listener in List<SettingsListener>.of(_listeners)) {
      listener(settings);
    }
  }
}
