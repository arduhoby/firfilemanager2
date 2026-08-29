import 'dart:ui';

import 'package:flutter/material.dart';

import 'app_theme.dart';

/// A container widget that applies a macOS-style glass (frosted glass) effect
/// using [BackdropFilter] with a semi-transparent background.
///
/// Use this for floating panels, toolbars, sidebars, and overlays where a
/// translucent, blurred appearance is desired.
class GlassContainer extends StatelessWidget {
  const GlassContainer({
    required this.child,
    super.key,
    this.blurSigma,
    this.opacity,
    this.borderRadius,
    this.border,
    this.padding,
    this.margin,
    this.shape,
    this.showBorder = true,
  });

  /// The child widget to display on top of the glass surface
  final Widget child;

  /// Blur intensity (defaults to [AppTheme.glassBlurSigma])
  final double? blurSigma;

  /// Background opacity override (0.0 to 1.0)
  final double? opacity;

  /// Border radius for the glass surface
  final BorderRadius? borderRadius;

  /// Custom border; if null and [showBorder] is true, a default glass border is used
  final Border? border;

  /// Inner padding
  final EdgeInsetsGeometry? padding;

  /// Outer margin
  final EdgeInsetsGeometry? margin;

  /// Shape override (takes precedence over [borderRadius])
  final ShapeBorder? shape;

  /// Whether to show the default glass border
  final bool showBorder;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final brightness = theme.brightness;
    final sigma = blurSigma ?? AppTheme.glassBlurSigma;
    final radius = borderRadius ?? BorderRadius.zero;

    return ClipRRect(
      borderRadius: radius,
      child: BackdropFilter(
        filter: ImageFilter.blur(sigmaX: sigma, sigmaY: sigma),
        child: Container(
          margin: margin,
          padding: padding,
          decoration: BoxDecoration(
            color: AppTheme.glassColor(brightness).withValues(alpha: opacity ?? 1.0),
            borderRadius: radius,
            border: showBorder
                ? border ??
                    Border.all(
                      color: AppTheme.glassBorderColor(brightness),
                      width: 0.5,
                    )
                : null,
            shape: shape != null ? BoxShape.rectangle : BoxShape.rectangle,
          ),
          child: child,
        ),
      ),
    );
  }
}

/// A sliver version of [GlassContainer] for use in [CustomScrollView]s.
class SliverGlassContainer extends StatelessWidget {
  const SliverGlassContainer({
    required this.child,
    super.key,
    this.blurSigma,
    this.opacity,
    this.borderRadius,
    this.padding,
    this.showBorder = true,
  });

  final Widget child;
  final double? blurSigma;
  final double? opacity;
  final BorderRadius? borderRadius;
  final EdgeInsetsGeometry? padding;
  final bool showBorder;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final brightness = theme.brightness;
    final sigma = blurSigma ?? AppTheme.glassBlurSigma;
    final radius = borderRadius ?? BorderRadius.zero;

    return SliverToBoxAdapter(
      child: ClipRRect(
        borderRadius: radius,
        child: BackdropFilter(
          filter: ImageFilter.blur(sigmaX: sigma, sigmaY: sigma),
          child: Container(
            padding: padding,
            decoration: BoxDecoration(
              color: AppTheme.glassColor(brightness).withValues(alpha: opacity ?? 1.0),
              borderRadius: radius,
              border: showBorder
                  ? Border.all(
                      color: AppTheme.glassBorderColor(brightness),
                      width: 0.5,
                    )
                  : null,
            ),
            child: child,
          ),
        ),
      ),
    );
  }
}