enum AppThemePreference { system, light, dark }

class AppSettings {
  const AppSettings({
    required this.schemaVersion,
    this.theme = AppThemePreference.system,
    this.localeCode,
    this.initialPanelCount = 2,
    this.showHiddenByDefault = false,
    this.playCompletionSound = true,
    this.confirmDelete = true,
    this.verifyCopies = true,
  });

  static const currentSchemaVersion = 1;

  final int schemaVersion;
  final AppThemePreference theme;
  final String? localeCode;
  final int initialPanelCount;
  final bool showHiddenByDefault;
  final bool playCompletionSound;
  final bool confirmDelete;
  final bool verifyCopies;

  AppSettings copyWith({
    AppThemePreference? theme,
    String? localeCode,
    int? initialPanelCount,
    bool? showHiddenByDefault,
    bool? playCompletionSound,
    bool? confirmDelete,
    bool? verifyCopies,
  }) => AppSettings(
    schemaVersion: schemaVersion,
    theme: theme ?? this.theme,
    localeCode: localeCode ?? this.localeCode,
    initialPanelCount: initialPanelCount ?? this.initialPanelCount,
    showHiddenByDefault: showHiddenByDefault ?? this.showHiddenByDefault,
    playCompletionSound: playCompletionSound ?? this.playCompletionSound,
    confirmDelete: confirmDelete ?? this.confirmDelete,
    verifyCopies: verifyCopies ?? this.verifyCopies,
  );
}
