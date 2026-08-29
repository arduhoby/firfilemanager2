import 'package:flutter/material.dart';
import 'cascade_menu_item.dart';

const double _kItemHeight = 32.0;
const double _kDividerHeight = 9.0;
const double _kMenuWidth = 220.0;
const double _kMenuRadius = 10.0;

/// A single rendered layer (the root menu or a submenu) drawn via [Overlay].
class CascadeMenuLayer extends StatefulWidget {
  const CascadeMenuLayer({
    super.key,
    required this.items,
    required this.position,
    required this.onSelect,
    required this.onDismissAll,
    this.parentLayerOpacity,
  });

  /// Items for this layer.
  final List<CascadeMenuItem> items;

  /// Top-left screen position for this menu.
  final Offset position;

  /// Called when the user picks a leaf item (no children). Returns the value.
  final void Function(String value) onSelect;

  /// Called when the entire cascade (all layers) should be dismissed.
  final VoidCallback onDismissAll;

  /// Notifier that controls parent layer's opacity while this layer is active.
  final ValueNotifier<double>? parentLayerOpacity;

  @override
  State<CascadeMenuLayer> createState() => _CascadeMenuLayerState();
}

class _CascadeMenuLayerState extends State<CascadeMenuLayer>
    with SingleTickerProviderStateMixin {
  late AnimationController _animCtrl;
  late Animation<double> _scaleAnim;
  late Animation<double> _fadeAnim;

  OverlayEntry? _subEntry;
  ValueNotifier<double>? _myOpacityNotifier;
  int? _activeChildIndex;

  @override
  void initState() {
    super.initState();
    _animCtrl = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 140),
    );
    _scaleAnim = CurvedAnimation(parent: _animCtrl, curve: Curves.easeOutCubic)
        .drive(Tween(begin: 0.92, end: 1.0));
    _fadeAnim = CurvedAnimation(parent: _animCtrl, curve: Curves.easeOut)
        .drive(Tween(begin: 0.0, end: 1.0));
    _animCtrl.forward();
  }

  @override
  void dispose() {
    _animCtrl.dispose();
    _subEntry?.remove();
    _subEntry = null;
    _myOpacityNotifier?.dispose();
    super.dispose();
  }

  /// Height of the full menu box.
  double get _menuHeight {
    double h = 12; // top + bottom padding
    for (final item in widget.items) {
      h += item.isDivider ? _kDividerHeight : _kItemHeight;
    }
    return h;
  }

  /// Clamp position so the menu never goes off-screen.
  Offset _clamped(Offset raw, Size screen) {
    final x = raw.dx.clamp(8.0, screen.width - _kMenuWidth - 8.0);
    final y = raw.dy.clamp(8.0, screen.height - _menuHeight - 8.0);
    return Offset(x, y);
  }

  void _openSubMenu(
    BuildContext itemContext,
    CascadeMenuItem item,
    int index,
  ) {
    _closeSubMenu();
    setState(() => _activeChildIndex = index);

    // Dim this layer while submenu is open
    _myOpacityNotifier = ValueNotifier(0.45);
    // Also dim parent if requested
    widget.parentLayerOpacity?.value = 0.25;

    // Compute position: to the right of this layer, aligned with the tapped item
    final layerPos = widget.position;
    final itemTop = _itemTopOffset(index);
    final subPos = Offset(layerPos.dx + _kMenuWidth + 2, layerPos.dy + itemTop);

    _subEntry = OverlayEntry(
      builder: (_) => CascadeMenuLayer(
        items: item.children!,
        position: subPos,
        onSelect: (v) {
          _closeSubMenu();
          widget.onSelect(v);
        },
        onDismissAll: () {
          _closeSubMenu();
          widget.onDismissAll();
        },
        parentLayerOpacity: _myOpacityNotifier,
      ),
    );
    Overlay.of(itemContext).insert(_subEntry!);
  }

  void _closeSubMenu() {
    _subEntry?.remove();
    _subEntry = null;
    _myOpacityNotifier?.value = 1.0;
    _myOpacityNotifier?.dispose();
    _myOpacityNotifier = null;
    widget.parentLayerOpacity?.value = 1.0;
    if (mounted) setState(() => _activeChildIndex = null);
  }

  /// Pixel offset from top of menu content to the top of item at [index].
  double _itemTopOffset(int index) {
    double offset = 6; // top padding
    for (int i = 0; i < index; i++) {
      offset += widget.items[i].isDivider ? _kDividerHeight : _kItemHeight;
    }
    return offset;
  }

  @override
  Widget build(BuildContext context) {
    final screen = MediaQuery.sizeOf(context);
    final pos = _clamped(widget.position, screen);
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;

    return ValueListenableBuilder<double>(
      valueListenable: _myOpacityNotifier ?? ValueNotifier(1.0),
      builder: (_, opacity, child) {
        return Stack(
          children: [
            // Full-screen barrier — only fires for taps OUTSIDE the menu box
            // (default HitTestBehavior.opaque — menu box on top intercepts its own taps)
            Positioned.fill(
              child: GestureDetector(
                onTap: () {
                  _closeSubMenu();
                  widget.onDismissAll();
                },
              ),
            ),
            // The menu box itself
            Positioned(
              left: pos.dx,
              top: pos.dy,
              child: AnimatedBuilder(
                animation: _animCtrl,
                builder: (_, child) => Opacity(
                  opacity: _fadeAnim.value * opacity,
                  child: Transform.scale(
                    scale: _scaleAnim.value,
                    alignment: Alignment.topLeft,
                    child: child,
                  ),
                ),
                child: child,
              ),
            ),
          ],
        );
      },
      child: Material(
        elevation: 12,
        borderRadius: BorderRadius.circular(_kMenuRadius),
        color: isDark
            ? const Color(0xFF2A2A2E)
            : const Color(0xFFF5F5F7),
        shadowColor: Colors.black.withValues(alpha: 0.4),
        child: Container(
          width: _kMenuWidth,
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(_kMenuRadius),
            border: Border.all(
              color: isDark
                  ? Colors.white.withValues(alpha: 0.08)
                  : Colors.black.withValues(alpha: 0.08),
              width: 0.5,
            ),
          ),
          child: ClipRRect(
            borderRadius: BorderRadius.circular(_kMenuRadius),
            child: Padding(
              padding: const EdgeInsets.symmetric(vertical: 6),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: List.generate(widget.items.length, (i) {
                  final item = widget.items[i];
                  if (item.isDivider) return _buildDivider(theme);
                  return _buildItem(context, item, i, theme);
                }),
              ),
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildDivider(ThemeData theme) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Divider(
        height: 1,
        thickness: 0.5,
        color: theme.dividerColor.withValues(alpha: 0.5),
        indent: 8,
        endIndent: 8,
      ),
    );
  }

  Widget _buildItem(
    BuildContext context,
    CascadeMenuItem item,
    int index,
    ThemeData theme,
  ) {
    final isActive = _activeChildIndex == index;
    final fgColor = item.isDestructive
        ? Colors.red
        : item.enabled
            ? theme.colorScheme.onSurface
            : theme.colorScheme.onSurface.withValues(alpha: 0.35);
    final activeBg = theme.colorScheme.primary.withValues(alpha: 0.15);

    return SizedBox(
      height: _kItemHeight,
      child: InkWell(
        onTap: item.enabled
            ? () {
                if (item.hasChildren) {
                  _openSubMenu(context, item, index);
                } else {
                  // Only call onSelect. It will complete the future with the value
                  // and the root showCascadeMenu will remove the overlay.
                  widget.onSelect(item.value);
                }
              }
            : null,
        child: Container(
          color: isActive ? activeBg : Colors.transparent,
          padding: const EdgeInsets.symmetric(horizontal: 10),
          child: Row(
            children: [
              if (item.icon != null) ...[
                Icon(item.icon, size: 15, color: fgColor),
                const SizedBox(width: 8),
              ] else
                const SizedBox(width: 23),
              Expanded(
                child: Text(
                  item.label,
                  style: TextStyle(fontSize: 12, color: fgColor),
                  overflow: TextOverflow.ellipsis,
                ),
              ),
              if (item.hasChildren)
                Icon(Icons.chevron_right_rounded, size: 14, color: fgColor),
            ],
          ),
        ),
      ),
    );
  }
}
