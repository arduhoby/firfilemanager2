import 'package:flutter/material.dart';

import 'double_back_exit_wrapper.dart';
import 'dual_pane_shell.dart';
import 'layout_resolver.dart';
import 'mobile_shell.dart';

/// The adaptive shell that switches between dual-pane and category layouts
/// based on screen size and orientation.
///
/// This is the top-level container for the file manager UI. It wraps the
/// router's child widget and provides the appropriate shell layout.
class ShellAdaptive extends StatelessWidget {
  const ShellAdaptive({
    required this.child,
    super.key,
  });

  /// The router child widget to display inside the shell
  final Widget child;

  @override
  Widget build(BuildContext context) {
    final layout = LayoutResolver.resolve(context);

    return DoubleBackExitWrapper(
      child: switch (layout) {
        ShellLayout.dualPane => DualPaneShell(child: child),
        ShellLayout.category => MobileShell(),
        ShellLayout.singleWithToggle => MobileShell(),
      },
    );
  }

  Widget _buildPlaceholder(BuildContext context, String label) {
    return Scaffold(
      body: Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            const Icon(Icons.folder_outlined, size: 64),
            const SizedBox(height: 16),
            Text(
              'Fir File Manager',
              style: Theme.of(context).textTheme.headlineSmall,
            ),
            const SizedBox(height: 8),
            Text(
              label,
              style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                    color: Theme.of(context).colorScheme.onSurfaceVariant,
                  ),
            ),
          ],
        ),
      ),
    );
  }
}
