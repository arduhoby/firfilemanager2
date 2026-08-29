import 'dart:io';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:package_info_plus/package_info_plus.dart';

import '../../core/settings/settings_provider.dart';
import '../../core/theme/app_theme.dart';
import '../../l10n/generated/app_localizations.dart';

final packageInfoProvider = FutureProvider<PackageInfo>(
  (ref) => PackageInfo.fromPlatform(),
);

class SettingsDialog extends ConsumerWidget {
  const SettingsDialog({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final settings = ref.watch(settingsProvider);
    final l10n = AppLocalizations.of(context)!;
    final theme = Theme.of(context);
    final packageInfo = ref.watch(packageInfoProvider);

    return AlertDialog(
      title: const Text('Ayarlar'),
      content: SizedBox(
        width: 440,
        child: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // ── Tema ────────────────────────────────────────────────────
              ListTile(
                contentPadding: EdgeInsets.zero,
                title: const Text('Tema'),
                trailing: DropdownButton<AppThemeMode>(
                  value: settings.themeMode,
                  onChanged: (mode) {
                    if (mode != null) {
                      ref.read(settingsProvider.notifier).setThemeMode(mode);
                    }
                  },
                  items: AppThemeMode.values.map((mode) {
                    return DropdownMenuItem(
                      value: mode,
                      child: Text(mode.name),
                    );
                  }).toList(),
                ),
              ),
              const Divider(),

              // ── Dil ─────────────────────────────────────────────────────
              ListTile(
                contentPadding: EdgeInsets.zero,
                title: const Text('Dil'),
                trailing: DropdownButton<Locale?>(
                  value: settings.locale,
                  onChanged: (locale) {
                    ref.read(settingsProvider.notifier).setLocale(locale);
                  },
                  items: const [
                    DropdownMenuItem(value: null, child: Text('Sistem')),
                    DropdownMenuItem(
                      value: Locale('en'),
                      child: Text('English'),
                    ),
                    DropdownMenuItem(
                      value: Locale('tr'),
                      child: Text('Türkçe'),
                    ),
                  ],
                ),
              ),
              const Divider(),

              // ── Tek Panel Modu ───────────────────────────────────────────
              SwitchListTile(
                contentPadding: EdgeInsets.zero,
                title: const Text('Tek Panel Modu'),
                subtitle: const Text('İkili panel yerine tek panel kullan.'),
                value: settings.singlePanelMode,
                onChanged: (val) {
                  ref.read(settingsProvider.notifier).setSinglePanelMode(val);
                },
              ),
              const Divider(),

              // ── Animasyon Sesleri ───────────────────────────────────────
              SwitchListTile(
                contentPadding: EdgeInsets.zero,
                title: const Text('İşlem tamamlanma sesi'),
                subtitle: const Text(
                  'Kopyalama, taşıma veya senkron tamamen bittiğinde bir kez çalar.',
                ),
                value: settings.playAnimationSounds,
                onChanged: (val) {
                  ref
                      .read(settingsProvider.notifier)
                      .setPlayAnimationSounds(val);
                },
              ),
              const Divider(),

              ListTile(
                contentPadding: EdgeInsets.zero,
                title: const Text('Dosya parça boyutu'),
                subtitle: Text(
                  settings.filePartSizeMb > 95
                      ? 'Cloudflare için 95 MB üzeri değerler aktarımı engelleyebilir.'
                      : 'Parçalama ve WebDAV yüklemelerinde kullanılır.',
                ),
                trailing: SizedBox(
                  width: 105,
                  child: TextFormField(
                    key: ValueKey(settings.filePartSizeMb),
                    initialValue: settings.filePartSizeMb.toString(),
                    keyboardType: TextInputType.number,
                    inputFormatters: [FilteringTextInputFormatter.digitsOnly],
                    decoration: const InputDecoration(
                      suffixText: 'MB',
                      isDense: true,
                    ),
                    onFieldSubmitted: (value) {
                      final size = int.tryParse(value);
                      if (size != null && size > 0) {
                        ref
                            .read(settingsProvider.notifier)
                            .setFilePartSizeMb(size);
                      }
                    },
                  ),
                ),
              ),
              const Divider(),

              // ── Arkaplan Resmi ───────────────────────────────────────────
              Padding(
                padding: const EdgeInsets.only(top: 8, bottom: 10),
                child: Text(
                  'Arkaplan Resmi',
                  style: theme.textTheme.titleSmall?.copyWith(
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ),

              // Önizleme
              if (settings.backgroundImagePath != null)
                _WallpaperPreview(
                  path: settings.backgroundImagePath!,
                  opacity: settings.backgroundOpacity,
                )
              else
                _EmptyWallpaperPlaceholder(),

              const SizedBox(height: 10),

              // Seç / Kaldır butonları
              Row(
                children: [
                  FilledButton.tonalIcon(
                    onPressed: () async {
                      final result = await FilePicker.platform.pickFiles(
                        type: FileType.image,
                        allowMultiple: false,
                      );
                      if (result != null && result.files.single.path != null) {
                        await ref
                            .read(settingsProvider.notifier)
                            .setBackgroundImagePath(result.files.single.path!);
                      }
                    },
                    icon: const Icon(Icons.photo_library_outlined, size: 16),
                    label: const Text('Resim Seç'),
                  ),
                  if (settings.backgroundImagePath != null) ...[
                    const SizedBox(width: 8),
                    OutlinedButton.icon(
                      onPressed: () {
                        ref
                            .read(settingsProvider.notifier)
                            .setBackgroundImagePath(null);
                      },
                      icon: const Icon(Icons.delete_outline, size: 16),
                      label: const Text('Kaldır'),
                      style: OutlinedButton.styleFrom(
                        foregroundColor: theme.colorScheme.error,
                        side: BorderSide(
                          color: theme.colorScheme.error.withValues(alpha: 0.5),
                        ),
                      ),
                    ),
                  ],
                ],
              ),

              // Opaklık slider
              const SizedBox(height: 14),
              Row(
                children: [
                  SizedBox(
                    width: 80,
                    child: Text('Şeffaflık', style: theme.textTheme.bodyMedium),
                  ),
                  Expanded(
                    child: Slider(
                      value: settings.backgroundOpacity,
                      min: 0.0,
                      max: 0.95,
                      divisions: 19,
                      label: '${(settings.backgroundOpacity * 100).round()}%',
                      onChanged: (val) {
                        ref
                            .read(settingsProvider.notifier)
                            .setBackgroundOpacity(val);
                      },
                    ),
                  ),
                  SizedBox(
                    width: 38,
                    child: Text(
                      '${(settings.backgroundOpacity * 100).round()}%',
                      style: theme.textTheme.bodySmall,
                      textAlign: TextAlign.right,
                    ),
                  ),
                ],
              ),
              const Divider(),
              ListTile(
                contentPadding: EdgeInsets.zero,
                leading: const Icon(Icons.info_outline),
                title: const Text('Sürüm'),
                trailing: packageInfo.when(
                  data: (info) => Text(
                    info.buildNumber.isEmpty
                        ? info.version
                        : '${info.version} (${info.buildNumber})',
                  ),
                  loading: () => const SizedBox.square(
                    dimension: 18,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  ),
                  error: (error, stackTrace) => const Text('Bilgi alınamadı'),
                ),
              ),
            ],
          ),
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: Text(l10n.actionCancel),
        ),
      ],
    );
  }
}

// ── Wallpaper preview widget ─────────────────────────────────────────────────

class _WallpaperPreview extends StatelessWidget {
  const _WallpaperPreview({required this.path, required this.opacity});

  final String path;
  final double opacity;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;

    return ClipRRect(
      borderRadius: BorderRadius.circular(10),
      child: Stack(
        children: [
          SizedBox(
            width: double.infinity,
            height: 120,
            child: Image.file(
              File(path),
              fit: BoxFit.cover,
              errorBuilder: (_, __, ___) => Container(
                color: theme.colorScheme.surfaceContainerHighest,
                child: const Center(
                  child: Icon(Icons.broken_image_outlined, size: 40),
                ),
              ),
            ),
          ),
          // Show the same overlay that will appear behind the app
          Container(
            width: double.infinity,
            height: 120,
            color: (isDark ? Colors.black : Colors.white).withValues(
              alpha: opacity,
            ),
          ),
        ],
      ),
    );
  }
}

class _EmptyWallpaperPlaceholder extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Container(
      width: double.infinity,
      height: 80,
      decoration: BoxDecoration(
        color: theme.colorScheme.surfaceContainerHighest,
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: theme.colorScheme.outlineVariant, width: 1),
      ),
      child: Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(
              Icons.image_outlined,
              size: 28,
              color: theme.colorScheme.onSurfaceVariant,
            ),
            const SizedBox(height: 4),
            Text(
              'Resim seçilmedi',
              style: theme.textTheme.bodySmall?.copyWith(
                color: theme.colorScheme.onSurfaceVariant,
              ),
            ),
          ],
        ),
      ),
    );
  }
}
