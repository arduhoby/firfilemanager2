import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'api_keys_repository.dart';

class ApiKeysDialog extends ConsumerStatefulWidget {
  const ApiKeysDialog({super.key});

  @override
  ConsumerState<ApiKeysDialog> createState() => _ApiKeysDialogState();
}

class _ApiKeysDialogState extends ConsumerState<ApiKeysDialog> {
  final Map<String, TextEditingController> _clientIdControllers = {};
  final Map<String, TextEditingController> _clientSecretControllers = {};

  final _providers = [
    {
      'key': 'gdrive',
      'name': 'Google Drive',
      'icon': Icons.cloud_queue_outlined,
      'color': Colors.blue,
      'description': 'Google Cloud Console\'dan "Desktop App" tipinde oluşturduğunuz kimlik bilgileri.',
      'secretRequired': false,
    },
    {
      'key': 'onedrive',
      'name': 'OneDrive',
      'icon': Icons.cloud_outlined,
      'color': Colors.blue.shade800,
      'description': 'Microsoft Entra (Azure) portalından oluşturduğunuz istemci bilgileri.',
      'secretRequired': true,
    },
    {
      'key': 'dropbox',
      'name': 'Dropbox',
      'icon': Icons.folder_shared_outlined,
      'color': Colors.indigo,
      'description': 'Dropbox Developer App Console\'dan oluşturduğunuz uygulama bilgileri.',
      'secretRequired': true,
    },
  ];

  @override
  void dispose() {
    for (var c in _clientIdControllers.values) {
      c.dispose();
    }
    for (var c in _clientSecretControllers.values) {
      c.dispose();
    }
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final keysState = ref.watch(apiKeysRepositoryProvider);

    for (var provider in _providers) {
      final key = provider['key'] as String;
      if (!_clientIdControllers.containsKey(key)) {
        _clientIdControllers[key] = TextEditingController(text: keysState[key]?.clientId ?? '');
        _clientSecretControllers[key] = TextEditingController(text: keysState[key]?.clientSecret ?? '');
      }
    }

    final theme = Theme.of(context);

    return Dialog(
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      child: Container(
        width: 600,
        height: 650,
        padding: const EdgeInsets.all(24),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Title section
            Row(
              children: [
                Icon(Icons.vpn_key_rounded, size: 28, color: theme.colorScheme.primary),
                const SizedBox(width: 12),
                Text(
                  'Bulut Servisleri API Anahtarları',
                  style: theme.textTheme.titleLarge?.copyWith(
                    fontWeight: FontWeight.bold,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 8),
            Text(
              'OAuth2 yetkilendirmesi için kendi Client ID ve Secret bilgilerinizi girin. Bu bilgiler cihazınızda şifrelenerek güvenle saklanır.',
              style: theme.textTheme.bodyMedium?.copyWith(
                color: theme.textTheme.bodyMedium?.color?.withOpacity(0.7),
              ),
            ),
            const SizedBox(height: 16),
            const Divider(),
            const SizedBox(height: 8),

            // Form section
            Expanded(
              child: ListView.builder(
                itemCount: _providers.length,
                itemBuilder: (context, index) {
                  final provider = _providers[index];
                  final key = provider['key'] as String;
                  final name = provider['name'] as String;
                  final icon = provider['icon'] as IconData;
                  final color = provider['color'] as Color;
                  final desc = provider['description'] as String;
                  final secretRequired = provider['secretRequired'] as bool;

                  return Container(
                    margin: const EdgeInsets.only(bottom: 20),
                    decoration: BoxDecoration(
                      color: theme.colorScheme.surfaceVariant.withOpacity(0.3),
                      borderRadius: BorderRadius.circular(12),
                      border: Border.all(
                        color: theme.dividerColor.withOpacity(0.1),
                      ),
                    ),
                    child: ExpansionTile(
                      leading: CircleAvatar(
                        backgroundColor: color.withOpacity(0.1),
                        child: Icon(icon, color: color, size: 20),
                      ),
                      title: Text(
                        name,
                        style: const TextStyle(fontWeight: FontWeight.bold),
                      ),
                      subtitle: Text(
                        desc,
                        style: const TextStyle(fontSize: 12),
                      ),
                      initiallyExpanded: key == 'gdrive', // Expand Google Drive by default
                      childrenPadding: const EdgeInsets.all(16),
                      children: [
                        // Client ID Input
                        TextField(
                          controller: _clientIdControllers[key],
                          decoration: InputDecoration(
                            labelText: 'Client ID (İstemci Kimliği)',
                            labelStyle: TextStyle(color: theme.colorScheme.onSurface.withOpacity(0.7)),
                            hintText: 'Girmek için buraya tıklayın...',
                            border: const OutlineInputBorder(),
                            focusedBorder: OutlineInputBorder(
                              borderSide: BorderSide(color: theme.colorScheme.primary, width: 2),
                            ),
                            enabledBorder: OutlineInputBorder(
                              borderSide: BorderSide(color: theme.colorScheme.outline.withOpacity(0.5)),
                            ),
                            prefixIcon: const Icon(Icons.badge_outlined),
                            contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                          ),
                        ),
                        const SizedBox(height: 16),

                        // Client Secret Input
                        TextField(
                          controller: _clientSecretControllers[key],
                          decoration: InputDecoration(
                            labelText: secretRequired
                                ? 'Client Secret (İstemci Parolası)'
                                : 'Client Secret (Masaüstü için genelde boş bırakılır)',
                            labelStyle: TextStyle(color: theme.colorScheme.onSurface.withOpacity(0.7)),
                            hintText: 'Varsa girmek için buraya tıklayın...',
                            border: const OutlineInputBorder(),
                            focusedBorder: OutlineInputBorder(
                              borderSide: BorderSide(color: theme.colorScheme.primary, width: 2),
                            ),
                            enabledBorder: OutlineInputBorder(
                              borderSide: BorderSide(color: theme.colorScheme.outline.withOpacity(0.5)),
                            ),
                            prefixIcon: const Icon(Icons.password_outlined),
                            contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                          ),
                        ),
                      ],
                    ),
                  );
                },
              ),
            ),

            const SizedBox(height: 16),
            const Divider(),
            const SizedBox(height: 8),

            // Actions
            Row(
              mainAxisAlignment: MainAxisAlignment.end,
              children: [
                OutlinedButton(
                  onPressed: () => Navigator.pop(context),
                  style: OutlinedButton.styleFrom(
                    padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 16),
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
                  ),
                  child: const Text('İptal'),
                ),
                const SizedBox(width: 12),
                FilledButton(
                  onPressed: () async {
                    final repo = ref.read(apiKeysRepositoryProvider.notifier);
                    for (var provider in _providers) {
                      final key = provider['key'] as String;
                      await repo.saveKeys(
                        key,
                        _clientIdControllers[key]!.text.trim(),
                        _clientSecretControllers[key]!.text.trim(),
                      );
                    }
                    if (context.mounted) {
                      ScaffoldMessenger.of(context).showSnackBar(
                        const SnackBar(
                          content: Text('API anahtarları başarıyla kaydedildi.'),
                          backgroundColor: Colors.green,
                        ),
                      );
                      Navigator.pop(context);
                    }
                  },
                  style: FilledButton.styleFrom(
                    padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 16),
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
                  ),
                  child: const Text('Kaydet ve Uygula'),
                ),
              ],
            )
          ],
        ),
      ),
    );
  }
}
