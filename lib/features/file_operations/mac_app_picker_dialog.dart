import 'dart:io';
import 'package:flutter/material.dart';

class MacAppPickerDialog extends StatefulWidget {
  const MacAppPickerDialog({super.key});

  static Future<String?> show(BuildContext context) {
    return showDialog<String>(
      context: context,
      builder: (context) => const MacAppPickerDialog(),
    );
  }

  @override
  State<MacAppPickerDialog> createState() => _MacAppPickerDialogState();
}

class _MacAppPickerDialogState extends State<MacAppPickerDialog> {
  List<String> _apps = [];
  List<String> _filteredApps = [];
  bool _isLoading = true;
  String _searchQuery = '';

  @override
  void initState() {
    super.initState();
    _loadApps();
  }

  Future<void> _loadApps() async {
    try {
      final result = await Process.run('mdfind', ["kMDItemContentType == 'com.apple.application-bundle'"]);
      if (result.exitCode == 0) {
        final lines = (result.stdout as String).split('\n');
        
        // Filter out non-user-facing apps to make it more user-friendly
        final apps = lines.where((l) {
          final trimmed = l.trim();
          if (trimmed.isEmpty || !trimmed.endsWith('.app')) return false;
          
          final home = Platform.environment['HOME'];
          if (!trimmed.startsWith('/Applications/') && 
              !trimmed.startsWith('/System/Applications/') &&
              (home == null || !trimmed.startsWith('$home/Applications/'))) {
            return false;
          }
          
          // Exclude hidden/internal system utilities that clutter the list
          if (trimmed.contains('/System/Applications/Utilities/') ||
              trimmed.contains('/CoreServices/')) {
            return false;
          }
          
          return true;
        }).toList();
        
        // Deduplicate by app name to avoid showing multiple versions of the same app
        final uniqueApps = <String, String>{};
        for (final app in apps) {
          final name = app.split('/').last;
          if (!uniqueApps.containsKey(name) || app.startsWith('/Applications/')) {
             uniqueApps[name] = app; // Prefer /Applications over /System/Applications
          }
        }
        
        final finalApps = uniqueApps.values.toList();
        
        // Sort alphabetically by app name
        finalApps.sort((a, b) {
          final aName = a.split('/').last.toLowerCase();
          final bName = b.split('/').last.toLowerCase();
          return aName.compareTo(bName);
        });

        if (mounted) {
          setState(() {
            _apps = finalApps;
            _filteredApps = finalApps;
            _isLoading = false;
          });
        }
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _isLoading = false;
        });
      }
    }
  }

  void _filterApps(String query) {
    setState(() {
      _searchQuery = query;
      if (query.isEmpty) {
        _filteredApps = _apps;
      } else {
        final lowerQuery = query.toLowerCase();
        _filteredApps = _apps.where((app) {
          final name = app.split('/').last.toLowerCase();
          return name.contains(lowerQuery);
        }).toList();
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return AlertDialog(
      title: const Text('Şununla Aç... (Uygulama Seçin)'),
      content: SizedBox(
        width: 400,
        height: 500,
        child: Column(
          children: [
            TextField(
              decoration: InputDecoration(
                hintText: 'Uygulama ara...',
                prefixIcon: const Icon(Icons.search),
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(8),
                ),
                contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
              ),
              onChanged: _filterApps,
            ),
            const SizedBox(height: 12),
            Expanded(
              child: _isLoading
                  ? const Center(child: CircularProgressIndicator())
                  : _filteredApps.isEmpty
                      ? const Center(child: Text('Uygulama bulunamadı.'))
                      : ListView.builder(
                          itemCount: _filteredApps.length,
                          itemBuilder: (context, index) {
                            final appPath = _filteredApps[index];
                            final appName = appPath.split('/').last.replaceAll('.app', '');
                            return ListTile(
                              leading: Container(
                                width: 32,
                                height: 32,
                                decoration: BoxDecoration(
                                  color: theme.colorScheme.primary.withValues(alpha: 0.1),
                                  borderRadius: BorderRadius.circular(8),
                                ),
                                child: Icon(Icons.apps, color: theme.colorScheme.primary, size: 20),
                              ),
                              title: Text(appName, style: const TextStyle(fontWeight: FontWeight.w500)),
                              subtitle: Text(appPath, style: TextStyle(fontSize: 11, color: theme.colorScheme.onSurfaceVariant), maxLines: 1, overflow: TextOverflow.ellipsis),
                              contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
                              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
                              onTap: () {
                                Navigator.of(context).pop(appPath);
                              },
                            );
                          },
                        ),
            ),
          ],
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: const Text('İptal'),
        ),
      ],
    );
  }
}
