import '../../domain/app_settings.dart';
import '../settings_section.dart';

class AppearanceSettingsSection implements SettingsSection {
  const AppearanceSettingsSection();

  @override
  String get id => 'appearance';

  @override
  String get titleKey => 'settingsAppearance';

  @override
  Map<String, Object?> present(AppSettings settings) => <String, Object?>{
    'theme': settings.theme.name,
  };
}
