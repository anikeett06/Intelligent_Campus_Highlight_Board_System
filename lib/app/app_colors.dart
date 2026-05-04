import 'package:flutter/material.dart';

/// Small set of brand accents for hero sections and custom imagery.
/// Prefer [Theme.of(context).colorScheme] for surfaces, text, and controls.
abstract final class AppColors {
  /// Profile / marketing header gradient
  static const Color profileHeaderStart = Color(0xFF1E40AF);
  static const Color profileHeaderEnd = Color(0xFF0F172A);

  /// Subtle placeholders (image fallbacks, empty avatars)
  static const Color placeholderFill = Color(0xFFE2E8F0);
}
