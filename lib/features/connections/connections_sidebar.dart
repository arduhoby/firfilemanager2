import 'dart:ui';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../settings/settings_dialog.dart';

import 'package:go_router/go_router.dart';
import '../../core/persistence/app_preferences.dart';

import '../../l10n/generated/app_localizations.dart' as gen;
import '../../core/storage/models/connection_profile.dart';
import '../../core/storage/storage_provider.dart';
import '../../core/storage/storage_provider_service.dart';
import '../file_operations/file_operations_state.dart';
import '../shell_adaptive/panel_controller.dart';

import 'connection_dialog.dart';
import 'connection_repository.dart';
import 'network_scanner.dart';

// ─── Sidebar collapsed state provider ──────────────────────────────────────
final sidebarCollapsedProvider =
    StateNotifierProvider<_SidebarCollapsedNotifier, bool>(
      (ref) => _SidebarCollapsedNotifier(),
    );

class _SidebarCollapsedNotifier extends StateNotifier<bool> {
  static const _key = 'sidebar_collapsed';

  _SidebarCollapsedNotifier() : super(false) {
    _load();
  }

  Future<void> _load() async {
    final prefs = await AppPreferences.getInstance();
    state = prefs.getBool(_key) ?? false;
  }

  Future<void> toggle() async {
    state = !state;
    final prefs = await AppPreferences.getInstance();
    await prefs.setBool(_key, state);
  }
}

// ─── Sidebar widths ─────────────────────────────────────────────────────────
const double _kExpandedWidth = 220;
const double _kCollapsedWidth = 56;

/// A sidebar widget that shows saved connections and allows connecting to them.
/// Supports animated collapse to icon-only mode.
class ConnectionsSidebar extends ConsumerStatefulWidget {
  const ConnectionsSidebar({super.key});

  @override
  ConsumerState<ConnectionsSidebar> createState() => _ConnectionsSidebarState();
}

class _ConnectionsSidebarState extends ConsumerState<ConnectionsSidebar>
    with SingleTickerProviderStateMixin {
  final _connectingIds = <String>{};
  bool _isScanning = false;
  bool _discoveredExpanded = true;
  late AnimationController _animController;
  late Animation<double> _widthAnim;

  @override
  void initState() {
    super.initState();
    _animController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 240),
    );
    _widthAnim = CurvedAnimation(
      parent: _animController,
      curve: Curves.easeInOut,
    );

    // Sync initial animation state
    WidgetsBinding.instance.addPostFrameCallback((_) {
      final collapsed = ref.read(sidebarCollapsedProvider);
      if (collapsed) _animController.value = 1.0;
    });
  }

  @override
  void dispose() {
    _animController.dispose();
    super.dispose();
  }

  void _onCollapseChanged(bool collapsed) {
    if (collapsed) {
      _animController.forward();
    } else {
      _animController.reverse();
    }
  }

  @override
  Widget build(BuildContext context) {
    final l10n = gen.AppLocalizations.of(context)!;
    final connections = ref.watch(connectionRepositoryProvider);
    final registry = ref.watch(storageProviderRegistryProvider);
    final discoveredServices = ref.watch(networkScannerProvider);
    final theme = Theme.of(context);
    final collapsed = ref.watch(sidebarCollapsedProvider);
    final isDark = theme.brightness == Brightness.dark;

    // Drive animation on state change
    ref.listen(sidebarCollapsedProvider, (_, next) => _onCollapseChanged(next));

    return AnimatedBuilder(
      animation: _widthAnim,
      builder: (context, child) {
        final width =
            _kExpandedWidth -
            (_kExpandedWidth - _kCollapsedWidth) * _widthAnim.value;
        return SizedBox(
          width: width,
          child: ClipRect(
            child: BackdropFilter(
              filter: ImageFilter.blur(sigmaX: 24, sigmaY: 24),
              child: Container(
                decoration: BoxDecoration(
                  color: isDark
                      ? const Color(0xCC1C1C1E)
                      : const Color(0xCCF5F5F7),
                  border: Border(
                    right: BorderSide(
                      color: isDark
                          ? const Color(0x33FFFFFF)
                          : const Color(0x22000000),
                      width: 0.5,
                    ),
                  ),
                ),
                child: Column(
                  children: [
                    _buildHeader(context, l10n, theme, collapsed, isDark),
                    Expanded(
                      child: _buildBody(
                        context,
                        l10n,
                        theme,
                        connections,
                        registry,
                        discoveredServices,
                        collapsed,
                      ),
                    ),
                    _buildFooter(context, l10n, theme, collapsed),
                  ],
                ),
              ),
            ),
          ),
        );
      },
    );
  }

  Widget _buildHeader(
    BuildContext context,
    gen.AppLocalizations l10n,
    ThemeData theme,
    bool collapsed,
    bool isDark,
  ) {
    return Container(
      height: 44,
      padding: const EdgeInsets.symmetric(horizontal: 8),
      decoration: BoxDecoration(
        border: Border(
          bottom: BorderSide(
            color: isDark ? const Color(0x22FFFFFF) : const Color(0x18000000),
            width: 0.5,
          ),
        ),
      ),
      child: Row(
        children: [
          // App icon / collapse button
          Tooltip(
            message: collapsed ? 'Expand sidebar' : 'Collapse sidebar',
            child: InkWell(
              borderRadius: BorderRadius.circular(8),
              onTap: () => ref.read(sidebarCollapsedProvider.notifier).toggle(),
              child: Padding(
                padding: const EdgeInsets.all(6),
                child: AnimatedRotation(
                  turns: collapsed ? 0.5 : 0,
                  duration: const Duration(milliseconds: 240),
                  child: Icon(
                    Icons.chevron_left,
                    size: 20,
                    color: theme.colorScheme.onSurfaceVariant,
                  ),
                ),
              ),
            ),
          ),
          if (!collapsed) ...[
            const SizedBox(width: 4),
            Icon(
              Icons.cloud_outlined,
              size: 16,
              color: theme.colorScheme.primary,
            ),
            const SizedBox(width: 6),
            Expanded(
              child: Text(
                l10n.navConnections,
                style: theme.textTheme.titleSmall?.copyWith(
                  fontWeight: FontWeight.w600,
                ),
                overflow: TextOverflow.ellipsis,
              ),
            ),
            _IconBtn(
              icon: _isScanning
                  ? const SizedBox(
                      width: 16,
                      height: 16,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    )
                  : const Icon(Icons.wifi_find, size: 16),
              tooltip: 'Scan Network',
              onPressed: _isScanning ? null : () => _scanNetwork(context),
            ),
            _IconBtn(
              icon: const Icon(Icons.add, size: 16),
              tooltip: l10n.connectionAddNew,
              onPressed: () => _showAddDialog(context),
            ),
          ],
        ],
      ),
    );
  }

  Widget _buildBody(
    BuildContext context,
    gen.AppLocalizations l10n,
    ThemeData theme,
    List<ConnectionProfile> connections,
    Map<String, StorageProvider> registry,
    List<DiscoveredService> discoveredServices,
    bool collapsed,
  ) {
    return CustomScrollView(
      slivers: [
        // Local
        SliverToBoxAdapter(
          child: _SidebarTile(
            icon: Icons.computer_outlined,
            name: l10n.navLocal,
            subtitle: 'Local filesystem',
            color: theme.colorScheme.primary,
            isConnected: true,
            collapsed: collapsed,
            onTap: () {
              final activeSide = ref.read(activePanelProvider);
              ref
                  .read(panelControllerProvider.notifier)
                  .navigate(activeSide, '/', providerId: 'local');
              context.go('/');
            },
          ),
        ),
        SliverToBoxAdapter(child: _Divider()),
        // Server Mode
        SliverToBoxAdapter(
          child: _SidebarTile(
            icon: Icons.share_outlined,
            name: l10n.navServer,
            subtitle: 'FTP / WebDAV server',
            color: Colors.teal,
            collapsed: collapsed,
            onTap: () => context.go('/server'),
          ),
        ),
        SliverToBoxAdapter(child: _Divider()),
        SliverToBoxAdapter(
          child: _SidebarTile(
            icon: Icons.sync_lock_outlined,
            name: l10n.syncJobsTitle,
            subtitle: l10n.syncJobsSubtitle,
            color: Colors.indigo,
            collapsed: collapsed,
            onTap: () => context.go('/sync'),
          ),
        ),
        SliverToBoxAdapter(child: _Divider()),
        // Network Scan
        SliverToBoxAdapter(
          child: _SidebarTile(
            icon: Icons.wifi_find_outlined,
            name: 'Network Devices',
            subtitle: _isScanning ? 'Scanning...' : 'Browse LAN',
            color: Colors.blueAccent,
            isConnecting: _isScanning,
            collapsed: collapsed,
            onTap: _isScanning ? () {} : () => _scanNetwork(context),
          ),
        ),
        SliverToBoxAdapter(child: _Divider()),
        // Section label
        if (!collapsed && connections.isNotEmpty)
          SliverToBoxAdapter(
            child: Padding(
              padding: const EdgeInsets.fromLTRB(14, 10, 14, 2),
              child: Text(
                'SAVED',
                style: theme.textTheme.labelSmall?.copyWith(
                  color: theme.colorScheme.onSurfaceVariant.withValues(
                    alpha: 0.6,
                  ),
                  fontWeight: FontWeight.w700,
                  letterSpacing: 0.8,
                  fontSize: 10,
                ),
              ),
            ),
          ),
        // Empty state
        if (connections.isEmpty &&
            !_isScanning &&
            discoveredServices.isEmpty &&
            !collapsed)
          SliverToBoxAdapter(
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Column(
                children: [
                  const SizedBox(height: 16),
                  Icon(
                    Icons.cloud_off,
                    size: 28,
                    color: theme.colorScheme.onSurfaceVariant.withValues(
                      alpha: 0.4,
                    ),
                  ),
                  const SizedBox(height: 8),
                  Text(
                    'No connections yet',
                    style: theme.textTheme.bodySmall?.copyWith(
                      color: theme.colorScheme.onSurfaceVariant,
                    ),
                  ),
                  const SizedBox(height: 12),
                  FilledButton.icon(
                    onPressed: () => _showAddDialog(context),
                    icon: const Icon(Icons.add, size: 14),
                    label: Text(
                      l10n.connectionAddNew,
                      style: const TextStyle(fontSize: 12),
                    ),
                  ),
                ],
              ),
            ),
          ),
        // Saved connections
        SliverList(
          delegate: SliverChildBuilderDelegate((context, index) {
            final profile = connections[index];
            final isConnected = registry[profile.id]?.isConnected ?? false;
            final isConnecting = _connectingIds.contains(profile.id);
            return _SidebarTile(
              icon: _getIconForType(profile.type),
              name: profile.name,
              subtitle: '${profile.host ?? ""}:${profile.effectivePort}',
              color: _getColorForType(profile.type, theme),
              isConnected: isConnected,
              isConnecting: isConnecting,
              collapsed: collapsed,
              onTap: () => _connect(context, profile),
              onEdit: () => _showEditDialog(context, profile),
              onDelete: () => _deleteConnection(context, profile),
            );
          }, childCount: connections.length),
        ),
        // Discovered
        if (discoveredServices.isNotEmpty && !collapsed) ...[
          SliverToBoxAdapter(
            child: InkWell(
              onTap: () =>
                  setState(() => _discoveredExpanded = !_discoveredExpanded),
              child: Padding(
                padding: const EdgeInsets.fromLTRB(14, 10, 14, 2),
                child: Row(
                  children: [
                    Expanded(
                      child: Text(
                        'DISCOVERED',
                        style: theme.textTheme.labelSmall?.copyWith(
                          color: theme.colorScheme.onSurfaceVariant.withValues(
                            alpha: 0.6,
                          ),
                          fontWeight: FontWeight.w700,
                          letterSpacing: 0.8,
                          fontSize: 10,
                        ),
                      ),
                    ),
                    Icon(
                      _discoveredExpanded
                          ? Icons.keyboard_arrow_up
                          : Icons.keyboard_arrow_down,
                      size: 14,
                      color: theme.colorScheme.onSurfaceVariant.withValues(
                        alpha: 0.6,
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
          if (_discoveredExpanded)
            SliverList(
              delegate: SliverChildBuilderDelegate(
                (ctx, i) => _DiscoveredTile(
                  service: discoveredServices[i],
                  onTap: () => _addDiscoveredAsConnection(
                    context,
                    discoveredServices[i],
                  ),
                ),
                childCount: discoveredServices.length,
              ),
            ),
        ],
        if (_isScanning)
          const SliverToBoxAdapter(
            child: Padding(
              padding: EdgeInsets.all(16),
              child: Center(
                child: Column(
                  children: [
                    CircularProgressIndicator(strokeWidth: 2),
                    SizedBox(height: 8),
                    Text('Scanning…', style: TextStyle(fontSize: 12)),
                  ],
                ),
              ),
            ),
          ),
      ],
    );
  }

  Widget _buildFooter(
    BuildContext context,
    gen.AppLocalizations l10n,
    ThemeData theme,
    bool collapsed,
  ) {
    final isDark = theme.brightness == Brightness.dark;
    return Container(
      decoration: BoxDecoration(
        border: Border(
          top: BorderSide(
            color: isDark ? const Color(0x22FFFFFF) : const Color(0x18000000),
            width: 0.5,
          ),
        ),
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          _SidebarTile(
            icon: Icons.settings_outlined,
            name: 'Settings',
            subtitle: 'App preferences',
            color: theme.colorScheme.onSurfaceVariant,
            collapsed: collapsed,
            onTap: () => showDialog(
              context: context,
              builder: (_) => const SettingsDialog(),
            ),
          ),
        ],
      ),
    );
  }

  // ─── Actions ───────────────────────────────────────────────────────────────

  void _showAddDialog(BuildContext context) =>
      showDialog(context: context, builder: (_) => const ConnectionDialog());

  void _showEditDialog(BuildContext context, ConnectionProfile profile) =>
      showDialog(
        context: context,
        builder: (_) => ConnectionDialog(existingProfile: profile),
      );

  Future<void> _deleteConnection(
    BuildContext context,
    ConnectionProfile profile,
  ) async {
    final l10n = gen.AppLocalizations.of(context)!;
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (_) => AlertDialog(
        title: Text(l10n.actionRemove),
        content: Text('${l10n.actionRemove} "${profile.name}"?'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: Text(l10n.actionCancel),
          ),
          FilledButton(
            style: FilledButton.styleFrom(backgroundColor: Colors.red),
            onPressed: () => Navigator.pop(context, true),
            child: Text(l10n.actionRemove),
          ),
        ],
      ),
    );
    if (confirmed != true) return;
    await ref
        .read(connectionRepositoryProvider.notifier)
        .deleteConnection(profile.id);
    await ref
        .read(storageProviderRegistryProvider.notifier)
        .unregister(profile.id);
  }

  Future<void> _connect(BuildContext context, ConnectionProfile profile) async {
    final l10n = gen.AppLocalizations.of(context)!;
    final registry = ref.read(storageProviderRegistryProvider.notifier);
    final repo = ref.read(connectionRepositoryProvider.notifier);
    final activeSide = ref.read(activePanelProvider);
    setState(() => _connectingIds.add(profile.id));
    try {
      final password = await repo.getPassword(profile.id);
      final privateKey = await repo.getPrivateKey(profile.id);
      final clientId = await repo.getClientId(profile.id);
      final clientSecret = await repo.getClientSecret(profile.id);
      final provider = await registry.getOrCreate(
        profile,
        password: password,
        privateKey: privateKey,
        clientId: clientId,
        clientSecret: clientSecret,
      );
      final homePath = await provider.homePath;
      await ref
          .read(panelControllerProvider.notifier)
          .navigate(activeSide, homePath, providerId: profile.id);
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('${l10n.connectionTestSuccess}: ${profile.name}'),
            duration: const Duration(seconds: 2),
          ),
        );
      }
    } catch (e, stack) {
      debugPrint('CONNECTION FAILURE: $e\n$stack');
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(l10n.connectionTestFailed(e.toString())),
            backgroundColor: Theme.of(context).colorScheme.error,
            duration: const Duration(seconds: 5),
          ),
        );
      }
    } finally {
      if (mounted) setState(() => _connectingIds.remove(profile.id));
    }
  }

  Future<void> _scanNetwork(BuildContext context) async {
    setState(() => _isScanning = true);
    try {
      final scanner = ref.read(networkScannerProvider.notifier);
      await scanner.scanNetwork();
      if (context.mounted) {
        final results = ref.read(networkScannerProvider);
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('${results.length} service(s) found'),
            duration: const Duration(seconds: 2),
          ),
        );
      }
    } catch (e) {
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Scan failed: $e'),
            backgroundColor: Theme.of(context).colorScheme.error,
          ),
        );
      }
    } finally {
      if (mounted) setState(() => _isScanning = false);
    }
  }

  void _addDiscoveredAsConnection(
    BuildContext context,
    DiscoveredService service,
  ) {
    final type = switch (service.type) {
      'FTP' => ConnectionType.ftp,
      'SFTP' => ConnectionType.sftp,
      'WebDAV' => ConnectionType.webdav,
      'SMB' => ConnectionType.smb,
      '_smb._tcp' => ConnectionType.smb,
      _ => ConnectionType.ftp,
    };
    final profile = ConnectionProfile(
      name: service.name,
      type: type,
      host: service.host,
      port: service.port,
      defaultPath: '/',
    );
    showDialog(
      context: context,
      builder: (_) => ConnectionDialog(existingProfile: profile),
    );
  }

  IconData _getIconForType(ConnectionType type) => switch (type) {
    ConnectionType.sftp => Icons.terminal,
    ConnectionType.ftp => Icons.folder_shared,
    ConnectionType.ftps => Icons.folder_shared,
    ConnectionType.webdav => Icons.cloud,
    ConnectionType.smb => Icons.computer,
    ConnectionType.gdrive => Icons.cloud_upload,
    ConnectionType.dropbox => Icons.cloud_queue,
    ConnectionType.onedrive => Icons.cloud_circle,
    ConnectionType.nextcloud => Icons.cloud_sync,
    ConnectionType.local => Icons.computer_outlined,
  };

  Color _getColorForType(ConnectionType type, ThemeData theme) =>
      switch (type) {
        ConnectionType.sftp => Colors.green,
        ConnectionType.ftp => Colors.orange,
        ConnectionType.ftps => Colors.deepOrange,
        ConnectionType.webdav => Colors.blue,
        ConnectionType.smb => Colors.purple,
        ConnectionType.gdrive => Colors.red,
        ConnectionType.dropbox => Colors.indigo,
        ConnectionType.onedrive => Colors.blueAccent,
        ConnectionType.nextcloud => Colors.lightBlue,
        ConnectionType.local => theme.colorScheme.primary,
      };
}

// ─── Sidebar tile ───────────────────────────────────────────────────────────

/// A single sidebar tile that adapts between expanded (icon+text) and
/// collapsed (icon-only with tooltip) modes.
class _SidebarTile extends StatefulWidget {
  const _SidebarTile({
    required this.icon,
    required this.name,
    required this.subtitle,
    required this.color,
    required this.onTap,
    required this.collapsed,
    this.isConnected = false,
    this.isConnecting = false,
    this.onEdit,
    this.onDelete,
  });

  final IconData icon;
  final String name;
  final String subtitle;
  final Color color;
  final VoidCallback onTap;
  final bool collapsed;
  final bool isConnected;
  final bool isConnecting;
  final VoidCallback? onEdit;
  final VoidCallback? onDelete;

  @override
  State<_SidebarTile> createState() => _SidebarTileState();
}

class _SidebarTileState extends State<_SidebarTile> {
  bool _hovered = false;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;

    final leadingWidget = widget.isConnecting
        ? SizedBox(
            width: 18,
            height: 18,
            child: CircularProgressIndicator(
              strokeWidth: 2,
              color: widget.color,
            ),
          )
        : Icon(widget.icon, size: 18, color: widget.color);

    if (widget.collapsed) {
      return Tooltip(
        message: widget.name,
        preferBelow: false,
        child: InkWell(
          onTap: widget.onTap,
          child: Container(
            height: 44,
            alignment: Alignment.center,
            child: Stack(
              clipBehavior: Clip.none,
              children: [
                leadingWidget,
                if (widget.isConnected)
                  Positioned(
                    right: -4,
                    bottom: -2,
                    child: Container(
                      width: 7,
                      height: 7,
                      decoration: BoxDecoration(
                        color: Colors.green,
                        shape: BoxShape.circle,
                        border: Border.all(
                          color: isDark
                              ? const Color(0xFF1C1C1E)
                              : const Color(0xFFF5F5F7),
                          width: 1,
                        ),
                      ),
                    ),
                  ),
              ],
            ),
          ),
        ),
      );
    }

    return MouseRegion(
      onEnter: (_) => setState(() => _hovered = true),
      onExit: (_) => setState(() => _hovered = false),
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 150),
        decoration: BoxDecoration(
          color: _hovered
              ? (isDark ? const Color(0x18FFFFFF) : const Color(0x10000000))
              : Colors.transparent,
          borderRadius: BorderRadius.circular(8),
        ),
        margin: const EdgeInsets.symmetric(horizontal: 6, vertical: 1),
        child: InkWell(
          borderRadius: BorderRadius.circular(8),
          onTap: widget.onTap,
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 7),
            child: Row(
              children: [
                SizedBox(
                  width: 20,
                  child: Stack(
                    clipBehavior: Clip.none,
                    children: [
                      leadingWidget,
                      if (widget.isConnected)
                        Positioned(
                          right: -3,
                          bottom: -2,
                          child: Container(
                            width: 7,
                            height: 7,
                            decoration: BoxDecoration(
                              color: Colors.green,
                              shape: BoxShape.circle,
                              border: Border.all(
                                color: isDark
                                    ? const Color(0xFF1C1C1E)
                                    : const Color(0xFFF5F5F7),
                                width: 1,
                              ),
                            ),
                          ),
                        ),
                    ],
                  ),
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Text(
                        widget.name,
                        style: theme.textTheme.bodySmall?.copyWith(
                          fontWeight: FontWeight.w500,
                          fontSize: 12.5,
                        ),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                      Text(
                        widget.subtitle,
                        style: theme.textTheme.bodySmall?.copyWith(
                          color: theme.colorScheme.onSurfaceVariant.withValues(
                            alpha: 0.7,
                          ),
                          fontSize: 10.5,
                        ),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                    ],
                  ),
                ),
                if (widget.onEdit != null || widget.onDelete != null)
                  _TileMenu(onEdit: widget.onEdit, onDelete: widget.onDelete),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _TileMenu extends StatelessWidget {
  const _TileMenu({this.onEdit, this.onDelete});

  final VoidCallback? onEdit;
  final VoidCallback? onDelete;

  @override
  Widget build(BuildContext context) {
    return PopupMenuButton<String>(
      icon: Icon(
        Icons.more_vert,
        size: 14,
        color: Theme.of(context).colorScheme.onSurfaceVariant,
      ),
      padding: EdgeInsets.zero,
      constraints: const BoxConstraints(),
      itemBuilder: (_) => [
        if (onEdit != null)
          PopupMenuItem(
            value: 'edit',
            child: Row(
              children: [
                const Icon(Icons.edit, size: 14),
                const SizedBox(width: 8),
                Text(
                  gen.AppLocalizations.of(context)!.actionEdit,
                  style: const TextStyle(fontSize: 13),
                ),
              ],
            ),
          ),
        if (onDelete != null)
          PopupMenuItem(
            value: 'delete',
            child: Row(
              children: [
                const Icon(Icons.delete, size: 14, color: Colors.red),
                const SizedBox(width: 8),
                Text(
                  gen.AppLocalizations.of(context)!.actionRemove,
                  style: const TextStyle(color: Colors.red, fontSize: 13),
                ),
              ],
            ),
          ),
      ],
      onSelected: (v) {
        if (v == 'edit') onEdit?.call();
        if (v == 'delete') onDelete?.call();
      },
    );
  }
}

class _Divider extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    return Container(
      height: 0.5,
      margin: const EdgeInsets.symmetric(horizontal: 8),
      color: isDark ? const Color(0x22FFFFFF) : const Color(0x18000000),
    );
  }
}

class _IconBtn extends StatelessWidget {
  const _IconBtn({required this.icon, required this.tooltip, this.onPressed});
  final Widget icon;
  final String tooltip;
  final VoidCallback? onPressed;

  @override
  Widget build(BuildContext context) {
    return IconButton(
      icon: icon,
      onPressed: onPressed,
      visualDensity: VisualDensity.compact,
      tooltip: tooltip,
      iconSize: 16,
    );
  }
}

/// A tile for a discovered network service
class _DiscoveredTile extends StatelessWidget {
  const _DiscoveredTile({required this.service, required this.onTap});

  final DiscoveredService service;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final color = switch (service.type) {
      'FTP' => Colors.orange,
      'SFTP' => Colors.green,
      'WebDAV' => Colors.blue,
      _ => Colors.grey,
    };
    final icon = switch (service.type) {
      'FTP' => Icons.folder_shared,
      'SFTP' => Icons.terminal,
      'WebDAV' => Icons.cloud,
      _ => Icons.computer,
    };

    return ListTile(
      leading: Icon(icon, size: 18, color: color),
      title: Text(
        service.type,
        style: theme.textTheme.bodySmall?.copyWith(fontWeight: FontWeight.w500),
      ),
      subtitle: Text(
        '${service.host}:${service.port}',
        style: theme.textTheme.bodySmall?.copyWith(
          color: theme.colorScheme.onSurfaceVariant,
          fontSize: 10,
        ),
      ),
      trailing: Icon(
        Icons.add_circle_outline,
        size: 14,
        color: theme.colorScheme.primary,
      ),
      onTap: onTap,
      dense: true,
    );
  }
}
