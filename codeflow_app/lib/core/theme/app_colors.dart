import 'package:flutter/material.dart';

/// App Color Tokens for CodeFlow
/// Minimal, Flat, White-First Light Mode + Deep Charcoal Dark Mode
class AppColors {
  // Brand Accent (Single restrained blue)
  static const Color accentLight = Color(0xFF2563EB); // Royal Blue
  static const Color accentDark = Color(0xFF3B82F6);  // Bright Slate Blue
  static const Color accentHover = Color(0xFF1D4ED8);

  // Light Theme Palette (White-First)
  static const Color lightBackground = Color(0xFFFFFFFF);
  static const Color lightSurface = Color(0xFFF9FAFB);
  static const Color lightSurfaceSecondary = Color(0xFFF3F4F6);
  static const Color lightBorder = Color(0xFFE5E7EB);
  static const Color lightBorderSubtle = Color(0xFFF3F4F6);
  static const Color lightTextPrimary = Color(0xFF111827);
  static const Color lightTextSecondary = Color(0xFF4B5563);
  static const Color lightTextMuted = Color(0xFF9CA3AF);

  // Dark Theme Palette (Deep Charcoal)
  static const Color darkBackground = Color(0xFF121212);
  static const Color darkSurface = Color(0xFF1E1E1E);
  static const Color darkSurfaceSecondary = Color(0xFF282828);
  static const Color darkBorder = Color(0xFF2E2E2E);
  static const Color darkBorderSubtle = Color(0xFF1F1F1F);
  static const Color darkTextPrimary = Color(0xFFF3F4F6);
  static const Color darkTextSecondary = Color(0xFF9CA3AF);
  static const Color darkTextMuted = Color(0xFF6B7280);

  // Status Colors (Restrained, Flat)
  static const Color statusSuccess = Color(0xFF10B981);
  static const Color statusWarning = Color(0xFFF59E0B);
  static const Color statusError = Color(0xFFEF4444);
  static const Color statusInfo = Color(0xFF3B82F6);

  // Code & Language Badge Colors (Subtle, Muted)
  static const Color badgeDart = Color(0xFF0075C9);
  static const Color badgePython = Color(0xFF3776AB);
  static const Color badgeKotlin = Color(0xFF7F52FF);
  static const Color badgeJson = Color(0xFFCA8A04);
  static const Color badgeMarkdown = Color(0xFF4B5563);
  static const Color badgeGeneric = Color(0xFF6B7280);
}
