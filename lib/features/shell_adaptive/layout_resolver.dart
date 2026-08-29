import 'dart:io';
import 'package:flutter/material.dart';

/// Determines which shell layout to use based on screen size and orientation.
///
/// - Width >= 900px (or landscape on tablets) → [ShellLayout.dualPane]
/// - Width < 600px portrait → [ShellLayout.category]
/// - 600-900px → [ShellLayout.dualPane] if landscape, [ShellLayout.category] if portrait
enum ShellLayout {
  /// Two panels side by side (desktop, tablet landscape)
  dualPane,

  /// Category-based single panel (phone portrait)
  category,

  /// Single panel with optional second panel toggle (phone landscape, small tablet)
  singleWithToggle,
}

class LayoutResolver {
  LayoutResolver._();

  /// Determine the shell layout from the given [BuildContext]
  static ShellLayout resolve(BuildContext context) {
    final size = MediaQuery.sizeOf(context);
    final orientation = MediaQuery.orientationOf(context);
    final isAndroid = Theme.of(context).platform == TargetPlatform.android || Platform.isAndroid;

    // On Android in portrait mode, always show single panel
    if (isAndroid && orientation == Orientation.portrait) {
      return ShellLayout.category;
    }

    // Desktop and large tablets
    if (size.width >= 900) {
      return ShellLayout.dualPane;
    }

    // Phone landscape or small tablet landscape
    if (orientation == Orientation.landscape && size.width >= 600) {
      return ShellLayout.dualPane;
    }

    // Phone landscape (narrow)
    if (orientation == Orientation.landscape) {
      return ShellLayout.singleWithToggle;
    }

    // Phone portrait
    return ShellLayout.category;
  }

  /// Whether the current layout should show dual pane by default
  static bool isDualPane(BuildContext context) {
    return resolve(context) == ShellLayout.dualPane;
  }

  /// Whether the device is a desktop (width >= 1200)
  static bool isDesktop(BuildContext context) {
    return MediaQuery.sizeOf(context).width >= 1200;
  }

  /// Whether the device is a tablet (600 <= width < 1200)
  static bool isTablet(BuildContext context) {
    final width = MediaQuery.sizeOf(context).width;
    return width >= 600 && width < 1200;
  }

  /// Whether the device is a phone (width < 600)
  static bool isPhone(BuildContext context) {
    return MediaQuery.sizeOf(context).width < 600;
  }
}