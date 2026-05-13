import 'package:flutter/material.dart';

/// Compatibility helper to replace deprecated `withOpacity(double)` uses.
///
/// Using `withAlpha((opacity*255).round())` keeps the visual alpha but
/// avoids the deprecated API and precision-loss warnings.
extension ColorUtils on Color {
  Color withOpacityCompat(double opacity) => withAlpha((opacity * 255).round());
}



