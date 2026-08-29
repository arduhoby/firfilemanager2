import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:file_picker/file_picker.dart';
import '../../core/theme/glass_container.dart';
import '../../l10n/generated/app_localizations.dart' as gen;
import 'server_state.dart';

class ServerModePage extends ConsumerStatefulWidget {
  const ServerModePage({super.key});

  @override
  ConsumerState<ServerModePage> createState() => _ServerModePageState();
}

class _ServerModePageState extends ConsumerState<ServerModePage> {
  final _ftpPortController = TextEditingController();
  final _webDavPortController = TextEditingController();
  final _usernameController = TextEditingController();
  final _passwordController = TextEditingController();
  final _sharedFolderController = TextEditingController();
  final _scrollController = ScrollController();

  List<String> _localIps = [];

  @override
  void initState() {
    super.initState();
    _loadLocalIps();
    
    // Initialize text controllers with initial state values
    final serverState = ref.read(serverStateProvider);
    _ftpPortController.text = serverState.ftpPort.toString();
    _webDavPortController.text = serverState.webDavPort.toString();
    _usernameController.text = serverState.username;
    _passwordController.text = serverState.password;
    _sharedFolderController.text = serverState.sharedFolder;
  }

  Future<void> _loadLocalIps() async {
    try {
      final interfaces = await NetworkInterface.list();
      final ips = <String>[];
      for (final interface in interfaces) {
        for (final addr in interface.addresses) {
          if (addr.type == InternetAddressType.IPv4 && !addr.isLoopback) {
            ips.add(addr.address);
          }
        }
      }
      if (mounted) {
        setState(() {
          _localIps = ips;
        });
      }
    } catch (_) {}
  }

  @override
  void dispose() {
    _ftpPortController.dispose();
    _webDavPortController.dispose();
    _usernameController.dispose();
    _passwordController.dispose();
    _sharedFolderController.dispose();
    _scrollController.dispose();
    super.dispose();
  }

  Future<void> _pickDirectory() async {
    print('UI: _pickDirectory() called');
    try {
      final path = await FilePicker.platform.getDirectoryPath();
      print('UI: FilePicker returned path: $path');
      if (path != null) {
        _sharedFolderController.text = path;
        ref.read(serverStateProvider.notifier).updateConfig(sharedFolder: path);
      }
    } catch (e) {
      print('UI: FilePicker error: $e');
    }
  }

  void _saveConfiguration() {
    print('UI: _saveConfiguration() called. folder: ${_sharedFolderController.text}');
    ref.read(serverStateProvider.notifier).updateConfig(
      ftpPort: int.tryParse(_ftpPortController.text) ?? 2121,
      webDavPort: int.tryParse(_webDavPortController.text) ?? 8080,
      username: _usernameController.text,
      password: _passwordController.text,
      sharedFolder: _sharedFolderController.text,
    );
  }

  @override
  Widget build(BuildContext context) {
    final l10n = gen.AppLocalizations.of(context)!;
    final serverState = ref.watch(serverStateProvider);
    final theme = Theme.of(context);

    // Scroll logs to bottom when updated
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (_scrollController.hasClients) {
        _scrollController.jumpTo(_scrollController.position.maxScrollExtent);
      }
    });

    final isAnyRunning = serverState.isFtpRunning || serverState.isWebDavRunning;

    return Scaffold(
      appBar: AppBar(
        title: Text(l10n.navServer),
        actions: [
          IconButton(
            icon: const Icon(Icons.refresh),
            onPressed: () {
              _loadLocalIps();
              ref.read(serverStateProvider.notifier).addLog('Network info refreshed.');
            },
            tooltip: 'Refresh Network Interfaces',
          ),
          IconButton(
            icon: const Icon(Icons.delete_sweep_outlined),
            onPressed: () {
              ref.read(serverStateProvider.notifier).clearLogs();
            },
            tooltip: 'Clear Logs',
          ),
        ],
      ),
      body: Row(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          // Left side: settings & controls
          Expanded(
            flex: 4,
            child: SingleChildScrollView(
              padding: const EdgeInsets.all(16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  // Shared folder configuration
                  _buildSectionTitle(l10n.serverSharedFolder, theme),
                  const SizedBox(height: 8),
                  Row(
                    children: [
                      Expanded(
                        child: TextField(
                          controller: _sharedFolderController,
                          enabled: !isAnyRunning,
                          decoration: InputDecoration(
                            hintText: 'Select folder to share…',
                            border: const OutlineInputBorder(),
                            contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                            fillColor: theme.colorScheme.surfaceContainerLowest,
                            filled: true,
                          ),
                          onChanged: (_) => _saveConfiguration(),
                        ),
                      ),
                      const SizedBox(width: 8),
                      ElevatedButton.icon(
                        onPressed: isAnyRunning ? null : _pickDirectory,
                        icon: const Icon(Icons.folder_open),
                        label: const Text('Browse'),
                        style: ElevatedButton.styleFrom(
                          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 24),

                  // Credentials configuration
                  _buildSectionTitle('Credentials', theme),
                  const SizedBox(height: 8),
                  Row(
                    children: [
                      Expanded(
                        child: TextField(
                          controller: _usernameController,
                          enabled: !isAnyRunning,
                          decoration: InputDecoration(
                            labelText: l10n.serverUsername,
                            border: const OutlineInputBorder(),
                            contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                          ),
                          onChanged: (_) => _saveConfiguration(),
                        ),
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: TextField(
                          controller: _passwordController,
                          enabled: !isAnyRunning,
                          obscureText: true,
                          decoration: InputDecoration(
                            labelText: l10n.serverPassword,
                            border: const OutlineInputBorder(),
                            contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                          ),
                          onChanged: (_) => _saveConfiguration(),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 24),

                  // Server controls
                  _buildSectionTitle('Available Servers', theme),
                  const SizedBox(height: 12),
                  
                  // FTP Server control card
                  _buildServerControlCard(
                    title: l10n.serverFtp,
                    isRunning: serverState.isFtpRunning,
                    portController: _ftpPortController,
                    onToggle: (val) {
                      _saveConfiguration();
                      if (val) {
                        ref.read(serverStateProvider.notifier).startFtp();
                      } else {
                        ref.read(serverStateProvider.notifier).stopFtp();
                      }
                    },
                    theme: theme,
                    l10n: l10n,
                    isEnabled: !serverState.isWebDavRunning,
                  ),
                  const SizedBox(height: 16),

                  // WebDAV Server control card
                  _buildServerControlCard(
                    title: l10n.serverWebdav,
                    isRunning: serverState.isWebDavRunning,
                    portController: _webDavPortController,
                    onToggle: (val) {
                      _saveConfiguration();
                      if (val) {
                        ref.read(serverStateProvider.notifier).startWebDav();
                      } else {
                        ref.read(serverStateProvider.notifier).stopWebDav();
                      }
                    },
                    theme: theme,
                    l10n: l10n,
                    isEnabled: !serverState.isFtpRunning,
                  ),
                  const SizedBox(height: 24),

                  // Connection info URLs
                  if (isAnyRunning) ...[
                    _buildSectionTitle('Connection Addresses', theme),
                    const SizedBox(height: 8),
                    _buildConnectionUrlsCard(serverState, theme),
                  ],
                ],
              ),
            ),
          ),
          
          // Right side: Active Connections & Logs Console
          Expanded(
            flex: 3,
            child: Container(
              decoration: BoxDecoration(
                border: Border(left: BorderSide(color: theme.dividerColor.withValues(alpha: 0.3))),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  // Active Connections
                  Padding(
                    padding: const EdgeInsets.all(12),
                    child: Text(
                      l10n.serverActiveConnections,
                      style: theme.textTheme.titleSmall?.copyWith(fontWeight: FontWeight.w600),
                    ),
                  ),
                  Container(
                    height: 80,
                    margin: const EdgeInsets.symmetric(horizontal: 12),
                    padding: const EdgeInsets.all(8),
                    decoration: BoxDecoration(
                      color: theme.colorScheme.surfaceContainerHigh,
                      borderRadius: BorderRadius.circular(6),
                    ),
                    child: serverState.activeConnections.isEmpty
                        ? Center(
                            child: Text(
                              l10n.serverNoConnections,
                              style: theme.textTheme.bodySmall?.copyWith(color: theme.colorScheme.onSurfaceVariant),
                            ),
                          )
                        : ListView.builder(
                            scrollDirection: Axis.horizontal,
                            itemCount: serverState.activeConnections.length,
                            itemBuilder: (context, index) {
                              return Padding(
                                padding: const EdgeInsets.only(right: 8),
                                child: Chip(
                                  avatar: const Icon(Icons.devices, size: 14),
                                  label: Text(serverState.activeConnections[index]),
                                  backgroundColor: theme.colorScheme.primaryContainer,
                                  labelStyle: TextStyle(color: theme.colorScheme.onPrimaryContainer),
                                  side: BorderSide.none,
                                ),
                              );
                            },
                          ),
                  ),
                  
                  // Logs Title
                  Padding(
                    padding: const EdgeInsets.fromLTRB(12, 16, 12, 4),
                    child: Text(
                      'Server Console Logs',
                      style: theme.textTheme.titleSmall?.copyWith(fontWeight: FontWeight.w600),
                    ),
                  ),

                  // Terminal logs screen
                  Expanded(
                    child: Container(
                      margin: const EdgeInsets.all(12),
                      padding: const EdgeInsets.all(10),
                      decoration: BoxDecoration(
                        color: Colors.black87,
                        borderRadius: BorderRadius.circular(6),
                      ),
                      child: SelectionArea(
                        child: ListView.builder(
                          controller: _scrollController,
                          itemCount: serverState.logs.length,
                          itemBuilder: (context, index) {
                            return Padding(
                              padding: const EdgeInsets.only(bottom: 4),
                              child: Text(
                                serverState.logs[index],
                                style: const TextStyle(
                                  color: Colors.greenAccent,
                                  fontFamily: 'Courier',
                                  fontSize: 12,
                                ),
                              ),
                            );
                          },
                        ),
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildSectionTitle(String title, ThemeData theme) {
    return Text(
      title,
      style: theme.textTheme.titleSmall?.copyWith(fontWeight: FontWeight.bold),
    );
  }

  Widget _buildServerControlCard({
    required String title,
    required bool isRunning,
    required TextEditingController portController,
    required ValueChanged<bool> onToggle,
    required ThemeData theme,
    required gen.AppLocalizations l10n,
    required bool isEnabled,
  }) {
    return GlassContainer(
      borderRadius: BorderRadius.circular(8),
      padding: const EdgeInsets.all(12),
      opacity: 0.1,
      child: Row(
        children: [
          Icon(
            title.contains('FTP') ? Icons.folder_shared : Icons.cloud,
            color: isRunning ? Colors.green : theme.colorScheme.onSurfaceVariant,
            size: 32,
          ),
          const SizedBox(width: 16),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  title,
                  style: theme.textTheme.bodyLarge?.copyWith(fontWeight: FontWeight.w600),
                ),
                Text(
                  isRunning ? l10n.serverRunning : l10n.serverStopped,
                  style: theme.textTheme.bodySmall?.copyWith(
                    color: isRunning ? Colors.green : theme.colorScheme.onSurfaceVariant,
                  ),
                ),
              ],
            ),
          ),
          SizedBox(
            width: 80,
            child: TextField(
              controller: portController,
              enabled: !isRunning && isEnabled,
              keyboardType: TextInputType.number,
              decoration: const InputDecoration(
                labelText: 'Port',
                border: OutlineInputBorder(),
                contentPadding: EdgeInsets.symmetric(horizontal: 8, vertical: 8),
              ),
            ),
          ),
          const SizedBox(width: 16),
          Switch(
            value: isRunning,
            onChanged: isEnabled || isRunning ? onToggle : null,
          ),
        ],
      ),
    );
  }

  Widget _buildConnectionUrlsCard(ServerConfigState serverState, ThemeData theme) {
    final urls = <String>[];
    
    // Fallback if no local IP could be determined
    final ips = _localIps.isEmpty ? ['127.0.0.1'] : _localIps;

    for (final ip in ips) {
      if (serverState.isFtpRunning) {
        urls.add('ftp://$ip:${serverState.ftpPort}');
      }
      if (serverState.isWebDavRunning) {
        urls.add('http://$ip:${serverState.webDavPort}');
      }
    }

    return Card(
      elevation: 0,
      color: theme.colorScheme.secondaryContainer.withValues(alpha: 0.3),
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(8),
        side: BorderSide(color: theme.colorScheme.secondary.withValues(alpha: 0.2)),
      ),
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'Access files from other devices on your LAN:',
              style: theme.textTheme.bodyMedium?.copyWith(fontWeight: FontWeight.w600),
            ),
            const SizedBox(height: 8),
            ...urls.map((url) => Padding(
              padding: const EdgeInsets.only(bottom: 6),
              child: Row(
                children: [
                  Icon(Icons.link, size: 16, color: theme.colorScheme.primary),
                  const SizedBox(width: 8),
                  SelectableText(
                    url,
                    style: TextStyle(
                      fontFamily: 'Courier',
                      fontSize: 14,
                      fontWeight: FontWeight.bold,
                      color: theme.colorScheme.primary,
                    ),
                  ),
                ],
              ),
            )),
          ],
        ),
      ),
    );
  }
}
