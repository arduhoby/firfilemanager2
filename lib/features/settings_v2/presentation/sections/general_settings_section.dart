import '../../domain/app_settings.dart';
import '../settings_section.dart';

class GeneralSettingsSection implements SettingsSection {
  const GeneralSettingsSection();

  @override
  String get id => 'general';

  @override
  String get titleKey => 'settingsGeneral';

  @override
  Map<String, Object?> present(AppSettings settings) => <String, Object?>{
    'localeCode': settings.localeCode,
    'initialPanelCount': settings.initialPanelCount,
    'showHiddenByDefault': settings.showHiddenByDefault,
  };
}
