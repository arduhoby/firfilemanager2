import '../domain/app_settings.dart';

abstract interface class SettingsSection {
  String get id;

  String get titleKey;

  Map<String, Object?> present(AppSettings settings);
}
