import 'dart:async';

import 'package:flutter/material.dart';
import 'cascade_menu_item.dart';
import 'cascade_menu_layer.dart';

export 'cascade_menu_item.dart';

/// Shows a cascade-style context menu anchored at [position].
///
/// Unlike Flutter's built-in [showMenu], this keeps the root layer visible
/// (dimmed) while a submenu is open, creating a native "cascade" feel.
///
/// Returns the [CascadeMenuItem.value] of the selected leaf item,
/// or `null` if the user dismissed without selecting.
Future<String?> showCascadeMenu({
  required BuildContext context,
  required Offset position,
  required List<CascadeMenuItem> items,
}) async {
  final completer = _MenuCompleter<String?>();
  OverlayEntry? rootEntry;

  void dismiss() {
    rootEntry?.remove();
    rootEntry = null;
    if (!completer.isCompleted) completer.complete(null);
  }

  void select(String value) {
    rootEntry?.remove();
    rootEntry = null;
    if (!completer.isCompleted) completer.complete(value);
  }

  rootEntry = OverlayEntry(
    builder: (_) => CascadeMenuLayer(
      items: items,
      position: position,
      onSelect: select,
      onDismissAll: dismiss,
    ),
  );

  Overlay.of(context).insert(rootEntry!);
  return completer.future;
}

/// Minimal completer wrapper to guard against double-completion.
class _MenuCompleter<T> {
  final _inner = Completer<T>();
  bool get isCompleted => _inner.isCompleted;
  Future<T> get future => _inner.future;
  void complete(T value) {
    if (!isCompleted) _inner.complete(value);
  }
}
