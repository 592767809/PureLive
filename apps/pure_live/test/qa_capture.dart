import 'dart:io';
import 'dart:math' as math;
import 'dart:ui' as ui;

import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

/// Optional synthetic widget frames for a local review, never a device claim.
Future<void> captureQaFrame(WidgetTester tester, String name) async {
  final folder = Platform.environment['PURELIVE_QA_DIR'];
  if (folder == null || folder.isEmpty) return;
  final font = Platform.environment['PURELIVE_QA_FONT'];
  if (font != null && font.isNotEmpty) {
    await tester.runAsync(() async {
      final bytes = ByteData.sublistView(await File(font).readAsBytes());
      for (final family in ['Ahem', 'Roboto']) {
        await (FontLoader(family)..addFont(Future.value(bytes))).load();
      }
      await (FontLoader('MaterialIcons')..addFont(rootBundle.load('fonts/MaterialIcons-Regular.otf'))).load();
      await (FontLoader(
        'packages/remixicon/remix',
      )..addFont(rootBundle.load('packages/remixicon/fonts/remix.ttf'))).load();
      await (FontLoader(
        'packages/live_ui/CustomIcons',
      )..addFont(rootBundle.load('packages/live_ui/assets/fonts/CustomIcons.ttf'))).load();
    });
    await tester.pump();
  }
  await tester.pump();
  final view = tester.binding.renderViews.first;
  final layer = view.debugLayer! as OffsetLayer;
  await tester.runAsync(() async {
    final image = await layer.toImage(view.paintBounds, pixelRatio: math.min(1, 1080 / view.paintBounds.width));
    try {
      final bytes = await image.toByteData(format: ui.ImageByteFormat.png);
      if (bytes == null) throw StateError('The widget frame has no PNG data');
      final target = File('$folder/$name.png');
      await target.parent.create(recursive: true);
      await target.writeAsBytes(bytes.buffer.asUint8List());
    } finally {
      image.dispose();
    }
  });
}
