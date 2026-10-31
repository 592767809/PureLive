import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:window_manager/window_manager.dart';

/// Restore the complete native layout before runApp can submit its first frame.
/// window_manager's optional callback is void and does not await async work.
Future<void> restoreStartupWindow(WindowOptions options, Future<void> Function() restore) async {
  await windowManager.waitUntilReadyToShow(options);
  await restore();
  if (defaultTargetPlatform == TargetPlatform.windows) {
    await const MethodChannel('pure_live/window_startup').invokeMethod<void>('layoutReady');
  }
}
