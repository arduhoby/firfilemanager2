import 'dart:async';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../file_operations/file_operations_state.dart';
import 'panel_controller.dart';

class DoubleBackExitWrapper extends ConsumerStatefulWidget {
  final Widget child;

  const DoubleBackExitWrapper({required this.child, super.key});

  @override
  ConsumerState<DoubleBackExitWrapper> createState() =>
      _DoubleBackExitWrapperState();
}

class _DoubleBackExitWrapperState extends ConsumerState<DoubleBackExitWrapper> {
  DateTime? _lastBackPressTime;

  @override
  Widget build(BuildContext context) {
    if (!Platform.isAndroid) {
      return widget.child;
    }

    return PopScope(
      canPop: false,
      onPopInvokedWithResult: (didPop, result) async {
        if (didPop) return;

        // On mobile, panelA is the primary panel.
        final panelAState = ref.read(panelStateProvider(PanelId.a));
        final controller = ref.read(panelControllerProvider.notifier);

        // If we can go back in history, let's just go back in history.
        if (panelAState.activeTab.historyIndex > 0) {
          await controller.navigateBack(PanelId.a);
          return;
        }

        // If we reached here, we are at the root of history. Require double press to exit.
        final now = DateTime.now();
        final isDoublePress =
            _lastBackPressTime != null &&
            now.difference(_lastBackPressTime!) < const Duration(seconds: 2);

        print('DOUBLE_BACK: isDoublePress=$isDoublePress');

        if (isDoublePress) {
          print('DOUBLE_BACK: Exiting app...');
          unawaited(SystemNavigator.pop());
          // Fallback if SystemNavigator.pop() doesn't work
          unawaited(
            Future.delayed(const Duration(milliseconds: 500), () {
              exit(0);
            }),
          );
        } else {
          print('DOUBLE_BACK: Showing toast');
          _lastBackPressTime = now;
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content: Text('Çıkmak için tekrar geri tuşuna basın'),
              duration: Duration(seconds: 2),
            ),
          );
        }
      },
      child: widget.child,
    );
  }
}
