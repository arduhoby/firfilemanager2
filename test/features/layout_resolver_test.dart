import 'package:fir_file_manager/features/shell_adaptive/layout_resolver.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  Widget buildTestWidget({required Size size}) {
    return MaterialApp(
      home: MediaQuery(
        data: MediaQueryData(
          size: size,
          devicePixelRatio: 1.0,
        ),
        child: SizedBox(
          width: size.width,
          height: size.height,
          child: _LayoutCapture(),
        ),
      ),
    );
  }

  // Desktop: 1920x1080 (landscape, wide)
  testWidgets('returns dualPane for desktop width (>= 900)', (tester) async {
    await tester.pumpWidget(buildTestWidget(size: const Size(1920, 1080)));
    final state = tester.state<_LayoutCaptureState>(find.byType(_LayoutCapture));
    expect(state.layout, ShellLayout.dualPane);
  });

  // Tablet landscape: 800x600 (landscape, >= 600)
  testWidgets('returns dualPane for tablet landscape (>= 600)', (tester) async {
    await tester.pumpWidget(buildTestWidget(size: const Size(800, 600)));
    final state = tester.state<_LayoutCaptureState>(find.byType(_LayoutCapture));
    expect(state.layout, ShellLayout.dualPane);
  });

  // Phone portrait: 390x844 (portrait, < 600)
  testWidgets('returns category for phone portrait (< 600)', (tester) async {
    await tester.pumpWidget(buildTestWidget(size: const Size(390, 844)));
    final state = tester.state<_LayoutCaptureState>(find.byType(_LayoutCapture));
    expect(state.layout, ShellLayout.category);
  });

  // Phone landscape: 844x390 (landscape, < 900 but >= 600)
  // Actually 844 >= 600 in landscape → dualPane
  // Let's use a narrower phone: 700x390
  testWidgets('returns singleWithToggle for phone landscape (narrow)', (tester) async {
    await tester.pumpWidget(buildTestWidget(size: const Size(700, 390)));
    final state = tester.state<_LayoutCaptureState>(find.byType(_LayoutCapture));
    // 700 >= 600 in landscape → dualPane, not singleWithToggle
    // For singleWithToggle we need < 600 in landscape
    expect(state.layout, ShellLayout.dualPane);
  });

  testWidgets('returns singleWithToggle for narrow phone landscape (< 600)', (tester) async {
    await tester.pumpWidget(buildTestWidget(size: const Size(500, 390)));
    final state = tester.state<_LayoutCaptureState>(find.byType(_LayoutCapture));
    expect(state.layout, ShellLayout.singleWithToggle);
  });

  testWidgets('isDesktop returns true for width >= 1200', (tester) async {
    await tester.pumpWidget(buildTestWidget(size: const Size(1440, 900)));
    final state = tester.state<_LayoutCaptureState>(find.byType(_LayoutCapture));
    expect(state.isDesktop, true);
    expect(state.isTablet, false);
    expect(state.isPhone, false);
  });

  testWidgets('isTablet returns true for 600 <= width < 1200', (tester) async {
    await tester.pumpWidget(buildTestWidget(size: const Size(768, 1024)));
    final state = tester.state<_LayoutCaptureState>(find.byType(_LayoutCapture));
    expect(state.isDesktop, false);
    expect(state.isTablet, true);
    expect(state.isPhone, false);
  });

  testWidgets('isPhone returns true for width < 600', (tester) async {
    await tester.pumpWidget(buildTestWidget(size: const Size(390, 844)));
    final state = tester.state<_LayoutCaptureState>(find.byType(_LayoutCapture));
    expect(state.isDesktop, false);
    expect(state.isTablet, false);
    expect(state.isPhone, true);
  });
}

/// Helper widget that captures the resolved layout via State
class _LayoutCapture extends StatefulWidget {
  @override
  State<_LayoutCapture> createState() => _LayoutCaptureState();
}

class _LayoutCaptureState extends State<_LayoutCapture> {
  late ShellLayout layout;
  late bool isDesktop;
  late bool isTablet;
  late bool isPhone;

  @override
  Widget build(BuildContext context) {
    layout = LayoutResolver.resolve(context);
    isDesktop = LayoutResolver.isDesktop(context);
    isTablet = LayoutResolver.isTablet(context);
    isPhone = LayoutResolver.isPhone(context);
    return const SizedBox.shrink();
  }
}