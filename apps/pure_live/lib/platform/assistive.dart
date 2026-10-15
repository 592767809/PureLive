import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';

/// Whether someone uses the screen through an assistive tool: a screen
/// reader exploring by touch (TalkBack and the like), Switch Access or
/// Voice Access (Android, `pure_live/assistive`, R01.3).
///
/// Flutter's own `accessibleNavigation` cannot tell: it turns true as soon
/// as any accessibility service reads a node, and HyperOS's 小米澎湃AI引擎,
/// on by default, does.
abstract final class AssistiveTech {
  static const MethodChannel _channel = MethodChannel('pure_live/assistive');

  /// The answer, kept up to date once [start] ran; false until then and
  /// off Android.
  static final ValueNotifier<bool> inUse = ValueNotifier(false);

  static bool _started = false;

  /// Asks Android and listens for changes; once, and only on Android.
  static Future<void> start() async {
    if (_started || kIsWeb || defaultTargetPlatform != TargetPlatform.android) return;
    _started = true;
    _channel.setMethodCallHandler((call) async {
      if (call.method == 'changed') inUse.value = call.arguments == true;
    });
    try {
      inUse.value = await _channel.invokeMethod<bool>('state') ?? false;
    } on PlatformException {
      // Unknown: the tree stays gated until a change is heard.
    } on MissingPluginException {
      // Another engine (the background check) has no such channel.
    }
  }
}
