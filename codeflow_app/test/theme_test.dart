import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:codeflow_app/core/theme/app_colors.dart';
import 'package:codeflow_app/core/theme/app_theme.dart';

void main() {
  group('AppTheme Configuration Tests', () {
    test('light theme is configured with white-first background and flat elevations', () {
      final theme = AppTheme.lightTheme;
      expect(theme.brightness, equals(Brightness.light));
      expect(theme.scaffoldBackgroundColor, equals(AppColors.lightBackground));
      expect(theme.appBarTheme.elevation, equals(0));
      expect(theme.filledButtonTheme.style?.elevation?.resolve({}), equals(0));
    });

    test('dark theme is configured with deep charcoal background', () {
      final theme = AppTheme.darkTheme;
      expect(theme.brightness, equals(Brightness.dark));
      expect(theme.scaffoldBackgroundColor, equals(AppColors.darkBackground));
      expect(theme.appBarTheme.elevation, equals(0));
      expect(theme.filledButtonTheme.style?.elevation?.resolve({}), equals(0));
    });
  });
}
