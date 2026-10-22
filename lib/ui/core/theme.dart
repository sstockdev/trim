import 'package:flutter/material.dart';

/// Colours shared across screens, close to the iOS system palette the Swift version used.
abstract final class TrimColors {
  static const orange = Color(0xFFFF9500);
  static const green = Color(0xFF34C759);
  static const teal = Color(0xFF30B0C7);
  static const indigo = Color(0xFF5856D6);
  static const red = Color(0xFFFF3B30);
  static const yellow = Color(0xFFFFCC00);
  static const blue = Color(0xFF007AFF);
}

abstract final class TrimTheme {
  static ThemeData get light => _theme(Brightness.light);
  static ThemeData get dark => _theme(Brightness.dark);

  static ThemeData _theme(Brightness b) => ThemeData(
    colorScheme: ColorScheme.fromSeed(seedColor: TrimColors.blue, brightness: b),
    scaffoldBackgroundColor: b == Brightness.light ? const Color(0xFFF2F2F7) : Colors.black,
  );
}

extension ThemeShortcuts on BuildContext {
  ColorScheme get colors => Theme.of(this).colorScheme;
  TextTheme get text => Theme.of(this).textTheme;
  Color get secondaryText => colors.onSurfaceVariant;
  Color get fill => colors.surfaceContainerHighest;
}
