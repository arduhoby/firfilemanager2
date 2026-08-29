import 'package:flutter/material.dart';

/// A single item in a [CascadeMenu].
class CascadeMenuItem {
  const CascadeMenuItem({
    required this.value,
    required this.label,
    this.icon,
    this.children,
    this.enabled = true,
    this.isDivider = false,
    this.isDestructive = false,
  });

  /// Creates a visual divider (separator line). All other fields are ignored.
  const CascadeMenuItem.divider()
      : value = '',
        label = '',
        icon = null,
        children = null,
        enabled = true,
        isDivider = true,
        isDestructive = false;

  final String value;
  final String label;
  final IconData? icon;

  /// If non-null, this item shows a ▶ indicator and opens a submenu on tap.
  final List<CascadeMenuItem>? children;

  final bool enabled;
  final bool isDivider;

  /// Red-tinted destructive styling (e.g. Delete).
  final bool isDestructive;

  bool get hasChildren => children != null && children!.isNotEmpty;
}
