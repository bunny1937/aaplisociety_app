import 'package:flutter/material.dart';

// Theme-aware helpers so every screen adapts to light / dark automatically.
extension ThemeX on BuildContext {
  Color get surface => Theme.of(this).cardColor;
  Color get headline => Theme.of(this).colorScheme.onSurface;
  bool get isDark => Theme.of(this).brightness == Brightness.dark;
}
