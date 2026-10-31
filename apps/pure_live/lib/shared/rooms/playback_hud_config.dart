import 'package:flutter/widgets.dart';

/// Persisted, bounded display preferences shared by phone, desktop and TV.
@immutable
final class PlaybackHudConfig {
  /// Creates display preferences without changing playback itself.
  const new({
    this.mode = 'controls',
    this.clock = true,
    this.speed = false,
    this.corner = 'topRight',
    this.size = 18,
    this.color = 0xffffffff,
    this.font = 'app',
  });

  /// Safely reads imported or older configuration values.
  factory fromJson(Map<String, Object?> value) {
    T choice<T>(String key, Set<T> choices, T fallback) => choices.contains(value[key]) ? value[key]! as T : fallback;
    final rawSize = value['size'];
    final rawColor = value['color'];
    return .new(
      mode: choice('mode', modes, 'controls'),
      clock: value['clock'] != false,
      speed: value['speed'] == true,
      corner: choice('corner', corners.keys.toSet(), 'topRight'),
      size: rawSize is num && rawSize.isFinite ? rawSize.toDouble().clamp(12, 48) : 18,
      color: rawColor is int && rawColor >= 0 && rawColor <= 0xffffffff ? rawColor : 0xffffffff,
      font: choice('font', fonts, 'app'),
    );
  }

  /// Visibility: disabled, follows the controls, or always visible.
  final String mode;

  /// Whether to show local wall-clock time.
  final bool clock;

  /// Whether to show the current media input rate.
  final bool speed;

  /// The preferred safe corner.
  final String corner;

  /// Logical font size before accessibility scaling.
  final double size;

  /// ARGB text color; an outline preserves contrast over video.
  final int color;

  /// Application, system sans-serif, or monospace font.
  final String font;

  /// Supported visibility modes.
  static const Set<String> modes = {'off', 'controls', 'always'};

  /// Positions use the same geometry in every layout.
  static const Map<String, Alignment> corners = {
    'topLeft': Alignment.topLeft,
    'topRight': Alignment.topRight,
    'bottomLeft': Alignment.bottomLeft,
    'bottomRight': Alignment.bottomRight,
  };

  /// Portable fonts do not fetch or install anything.
  static const Set<String> fonts = {'app', 'system', 'mono'};

  /// Whether any information should currently be drawn.
  bool visible({required bool controls}) => (clock || speed) && (mode == 'always' || (mode == 'controls' && controls));

  /// Stable values for settings backup and persistence.
  Map<String, Object?> toJson() => {
    'mode': mode,
    'clock': clock,
    'speed': speed,
    'corner': corner,
    'size': size,
    'color': color,
    'font': font,
  };
}
