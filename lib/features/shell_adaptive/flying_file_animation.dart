import 'package:flutter/material.dart';

class FlyingFileAnimation {
  static void show(
    BuildContext context, {
    required Offset start,
    required Offset end,
    required IconData icon,
    required Color color,
  }) {
    final overlay = Overlay.of(context);
    late OverlayEntry entry;

    entry = OverlayEntry(
      builder: (context) {
        return TweenAnimationBuilder<double>(
          tween: Tween(begin: 0.0, end: 1.0),
          duration: const Duration(milliseconds: 600),
          curve: Curves.easeInOutCubic,
          onEnd: () {
            if (entry.mounted) {
              entry.remove();
            }
          },
          builder: (context, value, child) {
            final x = start.dx + (end.dx - start.dx) * value;
            // Add a slight arc to the y coordinate for a "flying" effect
            final arc = (value - 0.5) * (value - 0.5) * -200 + 50;
            final y = start.dy + (end.dy - start.dy) * value - arc;

            // Fade out at the end
            final opacity = value > 0.8
                ? ((1.0 - value) * 5).clamp(0.0, 1.0)
                : 1.0;

            return Positioned(
              left: x - 24, // Center the 48x48 icon
              top: y - 24,
              child: IgnorePointer(
                child: Opacity(
                  opacity: opacity,
                  child: Container(
                    padding: const EdgeInsets.all(12),
                    decoration: BoxDecoration(
                      color: color.withValues(alpha: 0.2),
                      shape: BoxShape.circle,
                      boxShadow: [
                        BoxShadow(
                          color: color.withValues(alpha: 0.3),
                          blurRadius: 12,
                          spreadRadius: 2,
                        ),
                      ],
                    ),
                    child: Icon(icon, color: color, size: 24),
                  ),
                ),
              ),
            );
          },
        );
      },
    );

    overlay.insert(entry);
  }
}
