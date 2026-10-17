import 'dart:async';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:flutter/widgets.dart';
import 'package:live_core/live_core.dart';
import 'package:live_store/live_store.dart';

/// What keeps a playing room on screen when the app is left
/// (docs/A-界面设计/A07-直播间界面/A07.25-应用悬浮窗): nothing (the room plays on or
/// pauses as "后台播放" says), the system's picture-in-picture, or the app's
/// own floating window over the other apps.
enum LeaveAppWindow {
  /// Nothing (the default, as before).
  none,

  /// The system's picture-in-picture (`autoPipOnLeave`).
  pip,

  /// The app's floating window (`floatOverAppsOnLeave`).
  overlay,
}

/// The user's choice in [settings]; the floating window wins when both are
/// set.
LeaveAppWindow leaveAppWindow(SettingsStore settings) {
  if (settings.get(Settings.floatOverAppsOnLeave)) return LeaveAppWindow.overlay;
  if (settings.get(Settings.autoPipOnLeave)) return LeaveAppWindow.pip;
  return LeaveAppWindow.none;
}

/// Writes [choice] to the two settings behind it.
Future<void> setLeaveAppWindow(SettingsStore settings, LeaveAppWindow choice) => settings.setAll({
  Settings.floatOverAppsOnLeave: choice == LeaveAppWindow.overlay,
  Settings.autoPipOnLeave: choice == LeaveAppWindow.pip,
});

/// The app's own floating window over other apps on Android (A07.25; native
/// `FloatingOverlay`, channel `pure_live/overlay`): when the app is left
/// while it is armed, the app's one engine draws in a small window above the
/// other apps; the in-app floating window fills it ([active]) with its own
/// buttons. Needs "显示在其他应用的上层" ([permitted], [openSettings]).
abstract final class OverlayWindow {
  static const MethodChannel _channel = MethodChannel('pure_live/overlay');

  /// Whether to treat this as Android (tests); null asks the platform.
  @visibleForTesting
  static bool? debugAndroid;

  static bool get _android => debugAndroid ?? (!kIsWeb && Platform.isAndroid);

  /// Whether the app draws in the floating window now.
  static final ValueNotifier<bool> active = ValueNotifier(false);

  /// Whether "显示在其他应用的上层" is given (looked at on start and every
  /// return to the app).
  static final ValueNotifier<bool> permitted = ValueNotifier(false);

  /// The room whose page the window took over (it opens again when the app
  /// comes back), or null.
  static LiveRoom? fromRoomPage;

  static bool _started = false;
  static Object? _owner;

  /// Listens to the native side; once, at start (Android only).
  static void start() {
    if (!_android || _started) return;
    _started = true;
    _channel.setMethodCallHandler((call) async {
      if (call.method == 'changed') active.value = call.arguments == true;
    });
    AppLifecycleListener(onResume: () => unawaited(refresh()));
    unawaited(refresh());
  }

  /// Looks at the permission again.
  static Future<bool> refresh() async {
    if (!_android) return false;
    permitted.value = await _invoke<bool>('status') ?? false;
    return permitted.value;
  }

  /// Opens the system's "显示在其他应用的上层" page for this app.
  static Future<bool> openSettings() async => await _invoke<bool>('openSettings') ?? false;

  /// Lets leaving the app (home, recents) show the floating window at
  /// [window] (its place on the screen in logical pixels, [pixelRatio]
  /// physical ones each); [enabled] false stops that. [owner] is who arms
  /// it: only the one that armed it last can disarm it (a room page closing
  /// as the in-app floating window takes over does not undo the window's).
  static Future<void> arm({required bool enabled, Rect? window, double pixelRatio = 1, Object? owner}) async {
    if (!_android) return;
    if (enabled) {
      _owner = owner;
    } else if (owner != null && !identical(owner, _owner)) {
      return;
    } else {
      _owner = null;
    }
    final place = enabled ? window : null;
    await _invoke<void>('arm', {
      'enabled': place != null,
      'x': ((place?.left ?? 0) * pixelRatio).round(),
      'y': ((place?.top ?? 0) * pixelRatio).round(),
      'width': ((place?.width ?? 0) * pixelRatio).round(),
      'height': ((place?.height ?? 0) * pixelRatio).round(),
    });
  }

  /// The window's ✕: it goes, the app stays in the background.
  static Future<void> close() => _invoke<void>('close');

  /// Back to the app.
  static Future<bool> backToApp() async => await _invoke<bool>('backToApp') ?? false;

  /// A drag on the picture began: the native side moves the window with
  /// the finger.
  static Future<void> dragStart() => _invoke<void>('dragStart');

  /// A resize from the grip began (the native side sizes the window with
  /// the finger, the picture's shape kept); [left] for a grip at the left.
  static Future<void> resizeStart({required bool left}) => _invoke<void>('resizeStart', {'left': left, 'top': false});

  static Future<T?> _invoke<T>(String method, [Object? arguments]) async {
    if (!_android) return null;
    try {
      return await _channel.invokeMethod<T>(method, arguments);
    } on PlatformException {
      return null;
    } on MissingPluginException {
      return null;
    }
  }
}
