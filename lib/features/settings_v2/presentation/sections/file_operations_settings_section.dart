import '../../domain/app_settings.dart';
import '../settings_section.dart';

class FileOperationsSettingsSection implements SettingsSection {
  const FileOperationsSettingsSection();

  @override
  String get id => 'file-operations';

  @override
  String get titleKey => 'settingsFileOperations';

  @override
  Map<String, Object?> present(AppSettings settings) => <String, Object?>{
    'playCompletionSound': settings.playCompletionSound,
    'confirmDelete': settings.confirmDelete,
    'verifyCopies': settings.verifyCopies,
  };
}
