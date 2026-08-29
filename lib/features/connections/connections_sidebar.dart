import 'dart:async';
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
  bool _networkExpanded = true;
  bool _savedExpanded = true;
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
        if (collapsed)
          SliverToBoxAdapter(
            child: _SidebarTile(
              icon: Icons.account_tree_outlined,
              name: 'Network Tree',
              subtitle: 'Ağ bağlantıları',
              color: Colors.blueAccent,
              collapsed: true,
              onTap: _isScanning ? () {} : () => _scanNetwork(context),
            ),
          )
        else ...[
          SliverToBoxAdapter(
            child: _TreeBranchTile(
              icon: Icons.account_tree_outlined,
              label: 'Network',
              count: connections.length + discoveredServices.length,
              expanded: _networkExpanded,
              depth: 0,
              trailing: IconButton(
                tooltip: 'Ağı Tara',
                icon: _isScanning
                    ? const SizedBox(
                        width: 15,
                        height: 15,
                        child: CircularProgressIndicator(strokeWidth: 2),
                      )
                    : const Icon(Icons.refresh_rounded, size: 17),
                onPressed: _isScanning ? null : () => _scanNetwork(context),
              ),
              onTap: () => setState(() => _networkExpanded = !_networkExpanded),
            ),
          ),
          if (_networkExpanded) ...[
            SliverToBoxAdapter(
              child: _TreeBranchTile(
                icon: Icons.bookmarks_outlined,
                label: 'Kayıtlı Bağlantılar',
                count: connections.length,
                expanded: _savedExpanded,
                depth: 1,
                onTap: () => setState(() => _savedExpanded = !_savedExpanded),
              ),
            ),
            if (_savedExpanded)
              SliverList(
                delegate: SliverChildBuilderDelegate((context, index) {
                  final profile = connections[index];
                  final isConnected =
                      registry[profile.id]?.isConnected ?? false;
                  final isConnecting = _connectingIds.contains(profile.id);
                  return Padding(
                    padding: const EdgeInsets.only(left: 24),
                    child: _SidebarTile(
                      icon: _getIconForType(profile.type),
                      name: profile.name,
                      subtitle: profile.host == null
                          ? profile.type.name.toUpperCase()
                          : '${profile.host}:${profile.effectivePort}',
                      color: _getColorForType(profile.type, theme),
                      isConnected: isConnected,
                      isConnecting: isConnecting,
                      collapsed: false,
                      onTap: () => _connect(context, profile),
                      onDisconnect: isConnected
                          ? () async {
                              await ref
                                  .read(
                                    storageProviderRegistryProvider.notifier,
                                  )
                                  .unregister(profile.id);
                              if (mounted) setState(() {});
                            }
                          : null,
                      onContextMenu: () =>
                          _showSidebarConnectionMenu(context, profile),
                      onEdit: () => _showEditDialog(context, profile),
                      onDelete: () => _deleteConnection(context, profile),
                    ),
                  );
                }, childCount: connections.length),
              ),
            if (_savedExpanded && connections.isEmpty)
              SliverToBoxAdapter(
                child: Padding(
                  padding: const EdgeInsets.fromLTRB(44, 6, 12, 8),
                  child: OutlinedButton.icon(
                    onPressed: () => _showAddDialog(context),
                    icon: const Icon(Icons.add, size: 15),
                    label: Text(l10n.connectionAddNew),
                  ),
                ),
              ),
            SliverToBoxAdapter(
              child: _TreeBranchTile(
                icon: Icons.radar_rounded,
                label: 'Ağda Bulunanlar',
                count: discoveredServices.length,
                expanded: _discoveredExpanded,
                depth: 1,
                onTap: () =>
                    setState(() => _discoveredExpanded = !_discoveredExpanded),
              ),
            ),
            if (_discoveredExpanded)
              SliverList(
                delegate: SliverChildBuilderDelegate(
                  (ctx, i) => Padding(
                    padding: const EdgeInsets.only(left: 28),
                    child: _DiscoveredTile(
                      service: discoveredServices[i],
                      onTap: () => _addDiscoveredAsConnection(
                        context,
                        discoveredServices[i],
                      ),
                    ),
                  ),
                  childCount: discoveredServices.length,
                ),
              ),
            if (_discoveredExpanded &&
                discoveredServices.isEmpty &&
                !_isScanning)
              SliverToBoxAdapter(
                child: Padding(
                  padding: const EdgeInsets.fromLTRB(44, 4, 12, 10),
                  child: Text(
                    'Tarama yaparak FTP, SFTP, WebDAV ve SMB servislerini bul.',
                    style: theme.textTheme.bodySmall?.copyWith(
                      color: theme.colorScheme.onSurfaceVariant,
                    ),
                  ),
                ),
              ),
          ],
        ],
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

  void _showSidebarConnectionMenu(
    BuildContext context,
    ConnectionProfile profile,
  ) {
    final connected =
        ref.read(storageProviderRegistryProvider)[profile.id]?.isConnected ??
        false;
    unawaited(
      showMenu<String>(
        context: context,
        position: const RelativeRect.fromLTRB(220, 140, 0, 0),
        items: [
          PopupMenuItem(
            value: connected ? 'disconnect' : 'connect',
            child: Row(
              children: [
                Icon(connected ? Icons.link_off : Icons.link, size: 16),
                const SizedBox(width: 8),
                Text(connected ? 'Unmount / Bağlantıyı Kes' : 'Bağlan'),
              ],
            ),
          ),
          const PopupMenuItem(
            value: 'properties',
            child: Row(
              children: [
                Icon(Icons.info_outline, size: 16),
                SizedBox(width: 8),
                Text('Özellikler'),
              ],
            ),
          ),
          const PopupMenuItem(
            value: 'edit',
            child: Row(
              children: [
                Icon(Icons.edit, size: 16),
                SizedBox(width: 8),
                Text('Düzenle'),
              ],
            ),
          ),
        ],
      ).then((value) {
        if (!context.mounted || value == null) return;
        switch (value) {
          case 'connect':
            _connect(context, profile);
          case 'disconnect':
            ref
                .read(storageProviderRegistryProvider.notifier)
                .unregister(profile.id);
          case 'edit':
            _showEditDialog(context, profile);
          case 'properties':
            _showConnectionProperties(context, profile);
        }
      }),
    );
  }

  Future<void> _showConnectionProperties(
    BuildContext context,
    ConnectionProfile profile,
  ) async {
    await showDialog<void>(
      context: context,
      builder: (_) => AlertDialog(
        title: Text(profile.name),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            _propertyRow('Tür', profile.type.name.toUpperCase()),
            if (profile.host != null) _propertyRow('Sunucu', profile.host!),
            if (profile.host != null)
              _propertyRow('Port', '${profile.effectivePort}'),
            if (profile.username != null)
              _propertyRow('Kullanıcı', profile.username!),
            _propertyRow('Varsayılan yol', profile.defaultPath),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Kapat'),
          ),
        ],
      ),
    );
  }

  Widget _propertyRow(String label, String value) => Padding(
    padding: const EdgeInsets.symmetric(vertical: 4),
    child: Row(
      children: [
        SizedBox(width: 100, child: Text(label)),
        Expanded(child: Text(value)),
      ],
    ),
  );

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
    this.onDisconnect,
    this.onContextMenu,
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
  final VoidCallback? onDisconnect;
  final VoidCallback? onContextMenu;
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
          onSecondaryTapDown: widget.onContextMenu == null
              ? null
              : (_) => widget.onContextMenu!.call(),
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
                if (_hovered && widget.onDisconnect != null)
                  IconButton(
                    icon: const Icon(Icons.link_off, size: 15),
                    tooltip: 'Bağlantıyı Kes / Unmount',
                    visualDensity: VisualDensity.compact,
                    padding: EdgeInsets.zero,
                    onPressed: widget.onDisconnect,
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

class _TreeBranchTile extends StatelessWidget {
  const _TreeBranchTile({
    required this.icon,
    required this.label,
    required this.count,
    required this.expanded,
    required this.depth,
    required this.onTap,
    this.trailing,
  });

  final IconData icon;
  final String label;
  final int count;
  final bool expanded;
  final int depth;
  final VoidCallback onTap;
  final Widget? trailing;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return InkWell(
      onTap: onTap,
      child: Container(
        height: 38,
        padding: EdgeInsets.only(left: 8 + depth * 16, right: 5),
        child: Row(
          children: [
            Icon(
              expanded ? Icons.keyboard_arrow_down : Icons.chevron_right,
              size: 17,
              color: theme.colorScheme.onSurfaceVariant,
            ),
            Icon(icon, size: 17, color: theme.colorScheme.primary),
            const SizedBox(width: 7),
            Expanded(
              child: Text(
                label,
                style: theme.textTheme.bodySmall?.copyWith(
                  fontWeight: depth == 0 ? FontWeight.w700 : FontWeight.w600,
                ),
              ),
            ),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 1),
              decoration: BoxDecoration(
                color: theme.colorScheme.surfaceContainerHighest,
                borderRadius: BorderRadius.circular(10),
              ),
              child: Text('$count', style: theme.textTheme.labelSmall),
            ),
            if (trailing != null) trailing!,
          ],
        ),
      ),
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
