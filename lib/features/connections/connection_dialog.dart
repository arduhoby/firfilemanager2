import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../l10n/generated/app_localizations.dart' as gen;
import '../../core/storage/models/connection_profile.dart';
import 'connection_repository.dart';
import '../settings/api_keys_repository.dart';

/// Dialog for adding or editing a connection profile.
class ConnectionDialog extends ConsumerStatefulWidget {
  const ConnectionDialog({
    this.existingProfile,
    super.key,
  });

  final ConnectionProfile? existingProfile;

  @override
  ConsumerState<ConnectionDialog> createState() => _ConnectionDialogState();
}

class _ConnectionDialogState extends ConsumerState<ConnectionDialog> {
  late TextEditingController _nameController;
  late TextEditingController _hostController;
  late TextEditingController _portController;
  late TextEditingController _usernameController;
  late TextEditingController _passwordController;
  late TextEditingController _pathController;
  late TextEditingController _keyController;
  late TextEditingController _clientIdController;
  late TextEditingController _clientSecretController;

  ConnectionType _selectedType = ConnectionType.sftp;
  AuthMethod _selectedAuth = AuthMethod.password;
  bool _obscurePassword = true;
  bool _isSaving = false;
  bool _autoConnect = false;

  @override
  String _getDefaultName(ConnectionType type) {
    switch (type) {
      case ConnectionType.local: return 'local';
      case ConnectionType.sftp: return 'sftp';
      case ConnectionType.ftp: return 'ftp';
      case ConnectionType.ftps: return 'ftps';
      case ConnectionType.webdav: return 'webdav';
      case ConnectionType.smb: return 'smb';
      case ConnectionType.gdrive: return 'gdrive';
      case ConnectionType.onedrive: return 'onedrive';
      case ConnectionType.dropbox: return 'dropbox';
      case ConnectionType.nextcloud: return 'nextcloud';
    }
  }

  Future<void> _loadSecureCredentials(String id) async {
    final repo = ref.read(connectionRepositoryProvider.notifier);
    final clientId = await repo.getClientId(id);
    final clientSecret = await repo.getClientSecret(id);
    final password = await repo.getPassword(id);
    final privateKey = await repo.getPrivateKey(id);
    if (mounted) {
      setState(() {
        _clientIdController.text = clientId ?? '';
        _clientSecretController.text = clientSecret ?? '';
        _passwordController.text = password ?? '';
        _keyController.text = privateKey ?? '';
      });
    }
  }

  @override
  void initState() {
    super.initState();
    final p = widget.existingProfile;
    if (p != null) {
      _selectedType = p.type;
      _selectedAuth = p.authMethod;
      _autoConnect = p.autoConnect;
    }
    _nameController = TextEditingController(text: p?.name ?? _getDefaultName(_selectedType));
    _hostController = TextEditingController(text: p?.host ?? '');
    _portController = TextEditingController(text: p?.port?.toString() ?? '');
    _usernameController = TextEditingController(text: p?.username ?? '');
    _passwordController = TextEditingController();
    _pathController = TextEditingController(text: p?.defaultPath ?? '/');
    _keyController = TextEditingController();
    _clientIdController = TextEditingController();
    _clientSecretController = TextEditingController();

    if (p != null) {
      _loadSecureCredentials(p.id);
    } else {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        // Fallback import
        try {
          final keysState = ref.read(apiKeysRepositoryProvider);
          final key = _selectedType.name;
          final globalKeys = keysState[key];
          if (globalKeys != null) {
            _clientIdController.text = globalKeys.clientId;
            _clientSecretController.text = globalKeys.clientSecret;
          }
        } catch (_) {}
      });
    }

    _nameController.addListener(() => setState(() {}));
    _hostController.addListener(() => setState(() {}));
  }

  @override
  void dispose() {
    _nameController.dispose();
    _hostController.dispose();
    _portController.dispose();
    _usernameController.dispose();
    _passwordController.dispose();
    _pathController.dispose();
    _keyController.dispose();
    _clientIdController.dispose();
    _clientSecretController.dispose();
    super.dispose();
  }

  int? get _effectivePort {
    final text = _portController.text.trim();
    if (text.isEmpty) return null;
    return int.tryParse(text);
  }

  ConnectionProfile _buildProfile() {
    return ConnectionProfile(
      id: widget.existingProfile?.id,
      name: _nameController.text.trim(),
      type: _selectedType,
      host: _hostController.text.trim().isEmpty ? null : _hostController.text.trim(),
      port: _effectivePort,
      username: _usernameController.text.trim().isEmpty ? null : _usernameController.text.trim(),
      authMethod: _selectedAuth,
      defaultPath: _pathController.text.trim().isEmpty ? '/' : _pathController.text.trim(),
      autoConnect: _autoConnect,
    );
  }

  bool _validate() {
    if (_nameController.text.trim().isEmpty) return false;
    if (_selectedType.requiresHost && _hostController.text.trim().isEmpty) return false;
    return true;
  }

  Future<void> _save() async {
    if (!_validate() || _isSaving) return;

    setState(() => _isSaving = true);

    try {
      final profile = _buildProfile();
      final repo = ref.read(connectionRepositoryProvider.notifier);

      final password = _passwordController.text.isEmpty ? null : _passwordController.text;
      final privateKey = _keyController.text.isEmpty ? null : _keyController.text;
      final clientId = _clientIdController.text.trim();
      final clientSecret = _clientSecretController.text.trim();

      final existingProfiles = ref.read(connectionRepositoryProvider);

      if (widget.existingProfile == null || repo.getById(widget.existingProfile!.id) == null) {
        // Check for duplicates
        final isDuplicate = existingProfiles.any((p) {
          if (_selectedType == ConnectionType.gdrive ||
              _selectedType == ConnectionType.dropbox ||
              _selectedType == ConnectionType.onedrive) {
            return p.type == _selectedType;
          }
          if (_selectedType.requiresHost) {
            return p.type == _selectedType &&
                p.host?.toLowerCase() == profile.host?.toLowerCase() &&
                p.username?.toLowerCase() == profile.username?.toLowerCase();
          }
          return false;
        });

        if (isDuplicate) {
          final typeName = _selectedType == ConnectionType.gdrive ? 'Google Drive' : profile.name;
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text('$typeName bağlantısı zaten ekli! Tekrar eklenemez.'),
              backgroundColor: Colors.orange.shade800,
            ),
          );
          setState(() => _isSaving = false);
          return;
        }

        await repo.addConnection(
          profile,
          password: password,
          privateKey: privateKey,
          clientId: clientId,
          clientSecret: clientSecret,
        );
      } else {
        await repo.updateConnection(
          profile,
          password: password,
          privateKey: privateKey,
          clientId: clientId,
          clientSecret: clientSecret,
        );
      }

      if (mounted) Navigator.pop(context, profile);
    } catch (e) {
      if (mounted) {
        setState(() => _isSaving = false);
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Hata: $e'),
            backgroundColor: Theme.of(context).colorScheme.error,
          ),
        );
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final l10n = gen.AppLocalizations.of(context)!;
    final theme = Theme.of(context);

    return AlertDialog(
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      title: Row(
        children: [
          Icon(
            widget.existingProfile == null ? Icons.add_link_rounded : Icons.edit_note_rounded,
            color: theme.colorScheme.primary,
          ),
          const SizedBox(width: 10),
          Text(widget.existingProfile == null ? l10n.connectionAddNew : l10n.connectionEdit),
        ],
      ),
      content: SizedBox(
        width: 450,
        child: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              // Connection type dropdown
              DropdownButtonFormField<ConnectionType>(
                value: _selectedType,
                decoration: const InputDecoration(
                  labelText: 'Tür',
                  border: OutlineInputBorder(),
                  prefixIcon: Icon(Icons.compare_arrows_rounded),
                ),
                items: [
                  DropdownMenuItem(value: ConnectionType.sftp, child: Text(l10n.connectionTypeSftp)),
                  DropdownMenuItem(value: ConnectionType.ftp, child: Text(l10n.connectionTypeFtp)),
                  DropdownMenuItem(value: ConnectionType.ftps, child: const Text('FTPS')),
                  DropdownMenuItem(value: ConnectionType.webdav, child: Text(l10n.connectionTypeWebdav)),
                  DropdownMenuItem(value: ConnectionType.smb, child: const Text('SMB')),
                  DropdownMenuItem(value: ConnectionType.gdrive, child: const Text('Google Drive')),
                  DropdownMenuItem(value: ConnectionType.onedrive, child: const Text('OneDrive')),
                  DropdownMenuItem(value: ConnectionType.dropbox, child: const Text('Dropbox')),
                  DropdownMenuItem(value: ConnectionType.nextcloud, child: const Text('Nextcloud')),
                ],
                onChanged: (value) {
                  if (value != null) {
                    setState(() {
                      final oldDefault = _getDefaultName(_selectedType);
                      final currentVal = _nameController.text.trim();
                      if (currentVal.isEmpty || currentVal == oldDefault) {
                        _nameController.text = _getDefaultName(value);
                      }
                      _selectedType = value;
                      if (value == ConnectionType.gdrive ||
                          value == ConnectionType.onedrive ||
                          value == ConnectionType.dropbox) {
                        _selectedAuth = AuthMethod.oauth2;
                        
                        try {
                          final keysState = ref.read(apiKeysRepositoryProvider);
                          final globalKeys = keysState[value.name];
                          if (globalKeys != null && _clientIdController.text.isEmpty) {
                            _clientIdController.text = globalKeys.clientId;
                            _clientSecretController.text = globalKeys.clientSecret;
                          }
                        } catch (_) {}
                      } else if (_selectedAuth == AuthMethod.oauth2) {
                        _selectedAuth = AuthMethod.password;
                      }
                      if (_portController.text.isEmpty) {
                        _portController.text = ConnectionProfile(
                          type: value,
                          name: '',
                        ).defaultPort.toString();
                      }
                    });
                  }
                },
              ),
              const SizedBox(height: 16),

              // Name Field
              TextField(
                controller: _nameController,
                decoration: InputDecoration(
                  labelText: l10n.connectionName,
                  hintText: _getDefaultName(_selectedType),
                  border: const OutlineInputBorder(),
                  prefixIcon: const Icon(Icons.drive_file_rename_outline_rounded),
                  errorText: _nameController.text.trim().isEmpty ? 'Zorunlu alan' : null,
                ),
              ),
              const SizedBox(height: 16),

              // Host + Port Fields (Only show if type requires host)
              if (_selectedType.requiresHost) ...[
                Row(
                  children: [
                    Expanded(
                      flex: 3,
                      child: TextField(
                        controller: _hostController,
                        decoration: InputDecoration(
                          labelText: l10n.connectionHost,
                          border: const OutlineInputBorder(),
                          prefixIcon: const Icon(Icons.dns_outlined),
                          errorText: _hostController.text.trim().isEmpty ? 'Zorunlu alan' : null,
                        ),
                      ),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      flex: 1,
                      child: TextField(
                        controller: _portController,
                        decoration: InputDecoration(
                          labelText: l10n.connectionPort,
                          border: const OutlineInputBorder(),
                        ),
                        keyboardType: TextInputType.number,
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 16),
              ],

              // Username Field (Only show if auth is not OAuth2)
              if (_selectedAuth != AuthMethod.oauth2) ...[
                TextField(
                  controller: _usernameController,
                  decoration: InputDecoration(
                    labelText: l10n.connectionUsername,
                    border: const OutlineInputBorder(),
                    prefixIcon: const Icon(Icons.person_outline_rounded),
                  ),
                ),
                const SizedBox(height: 16),
              ],

              // Auth method dropdown (Only show if applicable)
              if (_selectedAuth != AuthMethod.oauth2) ...[
                DropdownButtonFormField<AuthMethod>(
                  value: _selectedAuth,
                  decoration: InputDecoration(
                    labelText: l10n.connectionAuthMethod,
                    border: const OutlineInputBorder(),
                    prefixIcon: const Icon(Icons.security_rounded),
                  ),
                  items: [
                    DropdownMenuItem(value: AuthMethod.password, child: Text(l10n.connectionAuthPassword)),
                    if (_selectedType == ConnectionType.sftp)
                      DropdownMenuItem(value: AuthMethod.privateKey, child: Text(l10n.connectionAuthKey)),
                    const DropdownMenuItem(value: AuthMethod.anonymous, child: Text('Anonim')),
                    if (_selectedType == ConnectionType.gdrive ||
                        _selectedType == ConnectionType.onedrive ||
                        _selectedType == ConnectionType.dropbox)
                      const DropdownMenuItem(value: AuthMethod.oauth2, child: Text('OAuth2')),
                  ],
                  onChanged: (value) {
                    if (value != null) setState(() => _selectedAuth = value);
                  },
                ),
                const SizedBox(height: 16),
              ],

              // Password/Key/OAuth description fields
              if (_selectedAuth == AuthMethod.password)
                TextField(
                  controller: _passwordController,
                  decoration: InputDecoration(
                    labelText: l10n.connectionPassword,
                    border: const OutlineInputBorder(),
                    prefixIcon: const Icon(Icons.lock_outline_rounded),
                    suffixIcon: IconButton(
                      icon: Icon(_obscurePassword ? Icons.visibility : Icons.visibility_off),
                      onPressed: () => setState(() => _obscurePassword = !_obscurePassword),
                    ),
                  ),
                  obscureText: _obscurePassword,
                )
              else if (_selectedAuth == AuthMethod.privateKey)
                TextField(
                  controller: _keyController,
                  decoration: const InputDecoration(
                    labelText: 'Özel Anahtar (Private Key)',
                    border: OutlineInputBorder(),
                    hintText: '-----BEGIN OPENSSH PRIVATE KEY-----\n...',
                  ),
                  maxLines: 4,
                )
              else if (_selectedAuth == AuthMethod.oauth2) ...[
                if (_selectedType != ConnectionType.gdrive) ...[
                  TextField(
                    controller: _clientIdController,
                    decoration: const InputDecoration(
                      labelText: 'Client ID (İstemci Kimliği)',
                      border: OutlineInputBorder(),
                      prefixIcon: Icon(Icons.badge_outlined),
                    ),
                  ),
                  const SizedBox(height: 16),
                  TextField(
                    controller: _clientSecretController,
                    decoration: const InputDecoration(
                      labelText: 'Client Secret (Boş bırakılabilir)',
                      border: OutlineInputBorder(),
                      prefixIcon: Icon(Icons.password_outlined),
                    ),
                  ),
                  const SizedBox(height: 16),
                ],
                Container(
                  padding: const EdgeInsets.all(12),
                  decoration: BoxDecoration(
                    color: theme.colorScheme.primaryContainer.withOpacity(0.3),
                    borderRadius: BorderRadius.circular(8),
                    border: Border.all(color: theme.colorScheme.primary.withOpacity(0.2)),
                  ),
                  child: Row(
                    children: [
                      Icon(Icons.info_outline_rounded, color: theme.colorScheme.primary),
                      const SizedBox(width: 10),
                      const Expanded(
                        child: Text(
                          'Yetkilendirme işlemi tarayıcınızda açılacak web sayfası üzerinden gerçekleştirilecektir.',
                          style: TextStyle(fontSize: 12),
                        ),
                      ),
                    ],
                  ),
                ),
              ],
              const SizedBox(height: 16),

              // Default path Field
              TextField(
                controller: _pathController,
                decoration: const InputDecoration(
                  labelText: 'Varsayılan Dizin (Default Path)',
                  border: OutlineInputBorder(),
                  prefixIcon: Icon(Icons.folder_open_rounded),
                ),
              ),
              const SizedBox(height: 12),

              // Auto connect Checkbox
              CheckboxListTile(
                title: const Text('Başlangıçta Otomatik Bağlan'),
                subtitle: const Text('Uygulama açıldığında arka planda bağlanır', style: TextStyle(fontSize: 11)),
                value: _autoConnect,
                onChanged: (val) {
                  if (val != null) setState(() => _autoConnect = val);
                },
                controlAffinity: ListTileControlAffinity.leading,
                contentPadding: EdgeInsets.zero,
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
              ),
            ],
          ),
        ),
      ),
      actions: [
        OutlinedButton(
          onPressed: _isSaving ? null : () => Navigator.pop(context),
          child: Text(l10n.actionCancel),
        ),
        FilledButton(
          onPressed: _validate() && !_isSaving ? _save : null,
          child: _isSaving
              ? const SizedBox(width: 16, height: 16, child: CircularProgressIndicator(strokeWidth: 2))
              : Text(l10n.actionSave),
        ),
      ],
    );
  }
}