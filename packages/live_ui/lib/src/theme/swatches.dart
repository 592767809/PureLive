import 'package:flutter/material.dart';
import 'package:live_ui/src/theme/live_theme.dart';

/// The colours of the TV's colour grid (A17.9 c12): a row of common ones
/// (the brand blue first, pure_live_TV's presets, then the phone's
/// favourites) and a palette of 18 hues in three shades.
abstract final class LiveSwatches {
  /// The common row: 18 colours.
  static const List<Color> common = [
    LiveTheme.brandBlue,
    Color(0xFF00D4FF), // pure_live_TV tech blue
    Color(0xFFFF66CC), // anime pink
    Color(0xFF2AD39A), // cyberpunk green
    Color(0xFFFF9F43), // warm orange
    Color(0xFF9C6BFF), // violet
    Color(0xFF2196F3), // 3.x's blue
    Color(0xFFE53935),
    Color(0xFFD81B60),
    Color(0xFF8E24AA),
    Color(0xFF3949AB),
    Color(0xFF039BE5),
    Color(0xFF00897B),
    Color(0xFF43A047),
    Color(0xFFC0CA33),
    Color(0xFFFDD835),
    Color(0xFFFB8C00),
    Color(0xFF6D4C41),
  ];

  /// The palette: Material's 18 hues, each light (200), middle (500) and
  /// dark (800), as three rows.
  static List<List<Color>> get palette => [
    for (final shade in const [200, 500, 800]) [for (final swatch in Colors.primaries) swatch[shade]!],
  ];
}
