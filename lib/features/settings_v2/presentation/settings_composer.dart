import '../domain/app_settings.dart';
import 'settings_section.dart';

class SettingsComposer {
  const SettingsComposer(this.sections);

  final List<SettingsSection> sections;

  Map<String, Map<String, Object?>> compose(AppSettings settings) =>
      <String, Map<String, Object?>>{
        for (final section in sections) section.id: section.present(settings),
      };
}
