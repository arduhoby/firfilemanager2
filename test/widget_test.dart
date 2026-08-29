import 'package:fir_file_manager/core/theme/app_theme.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('AppTheme.light returns valid ThemeData', () {
    expect(AppTheme.light, isA<ThemeData>());
    expect(AppTheme.light.useMaterial3, true);
  });

  test('AppTheme.dark returns valid ThemeData', () {
    expect(AppTheme.dark, isA<ThemeData>());
    expect(AppTheme.dark.useMaterial3, true);
  });

  test('AppTheme.glassColor returns correct color for brightness', () {
    expect(AppTheme.glassColor(Brightness.light), AppTheme.glassLight);
    expect(AppTheme.glassColor(Brightness.dark), AppTheme.glassDark);
  });
}