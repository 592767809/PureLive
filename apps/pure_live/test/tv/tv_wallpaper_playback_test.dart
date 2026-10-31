import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:live_media/live_media.dart';
import 'package:live_player/live_player.dart';
import 'package:live_store/live_store.dart';
import 'package:pure_live/app/services.dart';
import 'package:pure_live/tv/wallpaper/tv_wallpaper_layer.dart';

import '../features/live_play/live_play_support.dart' show FakeEngine;
import '../support.dart';

void main() {
  Future<void> hold(WidgetTester tester) async {
    var completed = false;
    unawaited(TvWallpaperVideo.hold().then((_) => completed = true));
    for (var i = 0; i < 12 && !completed; i++) {
      await tester.runAsync(() => Future<void>.delayed(const Duration(seconds: 1)));
      await tester.pump(const Duration(seconds: 1));
    }
    expect(completed, isTrue, reason: 'wallpaper retirement is bounded');
  }

  Future<(AppServices, List<FakeEngine>)> pump(WidgetTester tester) async {
    final services = (await tester.runAsync(testServices))!;
    await tester.runAsync(() async {
      await services.store.settings.set(Settings.tvWallpaperKind, 'video');
      await services.store.settings.set(Settings.tvWallpaperValue, '/generated/wallpaper.mp4');
    });
    final engines = <FakeEngine>[];
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          appServicesProvider.overrideWithValue(services),
          playbackSessionFactoryProvider.overrideWithValue(({config}) {
            final engine = FakeEngine();
            engines.add(engine);
            return PlaybackSession(
              engine: () async {
                return engine;
              },
              opener: MediaOpener(),
            );
          }),
        ],
        child: const MaterialApp(home: Scaffold(body: TvWallpaperLayer())),
      ),
    );
    await tester.runAsync(() => Future<void>.delayed(const Duration(seconds: 1)));
    await tester.pumpAndSettle();
    addTearDown(() async {
      await hold(tester);
      await tester.pumpWidget(const SizedBox.shrink());
      while (TvWallpaperVideo.holds.value > 0) {
        TvWallpaperVideo.release();
      }
      await tester.pump(const Duration(seconds: 12));
      await tester.pumpAndSettle();
      await tester.runAsync(services.close);
    });
    return (services, engines);
  }

  testWidgets('A17.24: held wallpaper never allocates a playback session', (tester) async {
    unawaited(TvWallpaperVideo.hold());
    final (_, engines) = await pump(tester);
    expect(engines, isEmpty, reason: 'a foreground video owns the decoder already');
  });

  testWidgets('A17.24: holding retires the decoder rather than pausing it', (tester) async {
    final (_, engines) = await pump(tester);
    expect(engines, hasLength(1));
    await hold(tester);
    await tester.pumpAndSettle();
    expect(engines.single.disposed, isTrue, reason: 'a paused wallpaper still owns native decoding resources');
    TvWallpaperVideo.release();
    await tester.pumpAndSettle();
    expect(engines, hasLength(2));
    expect(engines.last.disposed, isFalse);
  });

  testWidgets('A17.24: nested holders only restart after the last release', (tester) async {
    final (_, engines) = await pump(tester);
    unawaited(TvWallpaperVideo.hold());
    await hold(tester);
    await tester.pumpAndSettle();
    expect(engines.single.disposed, isTrue);
    TvWallpaperVideo.release();
    await tester.pumpAndSettle();
    expect(engines, hasLength(1));
    TvWallpaperVideo.release();
    await tester.pumpAndSettle();
    expect(engines, hasLength(2));
  });
}
