import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:live_player/live_player.dart';
import 'package:pure_live/shared/rooms/playback_hud.dart';
import 'package:pure_live/shared/rooms/playback_hud_config.dart';
import 'package:pure_live/shared/rooms/playback_telemetry.dart';

void main() {
  test('untrusted imported preferences cannot select an invalid mode, position or size', () {
    final config = PlaybackHudConfig.fromJson(const {
      'mode': 'invalid',
      'corner': 'bad',
      'size': double.nan,
      'color': -1,
    });
    expect(config.mode, 'controls');
    expect(config.corner, 'topRight');
    expect(config.size, 18);
    expect(config.color, 0xffffffff);
    expect(PlaybackHudConfig.fromJson(const {'size': 400}).size, 48);
    expect(PlaybackHudConfig.fromJson(const {'size': 0}).size, 12);
  });

  test('always remains visible without controls; disabling both fields or the layer hides it', () {
    expect(const PlaybackHudConfig(mode: 'always').visible(controls: false), isTrue);
    expect(const PlaybackHudConfig().visible(controls: false), isFalse);
    expect(const PlaybackHudConfig().visible(controls: true), isTrue);
    expect(const PlaybackHudConfig(mode: 'off').visible(controls: true), isFalse);
    expect(const PlaybackHudConfig(mode: 'always', clock: false).visible(controls: false), isFalse);
  });

  test('saved preferences round-trip including font, speed and signed ARGB integer', () {
    const config = PlaybackHudConfig(mode: 'always', corner: 'bottomLeft', speed: true, font: 'mono', size: 32);
    expect(PlaybackHudConfig.fromJson(config.toJson()).toJson(), config.toJson());
  });

  test('unknown throughput is distinct from a measured zero and uses byte units', () {
    expect(playbackHudRate(null), '—');
    expect(playbackHudRate(double.infinity), '—');
    expect(playbackHudRate(-1), '—');
    expect(playbackHudRate(0), '0 B/s');
    expect(playbackHudRate(1024), '1.0 KiB/s');
    expect(playbackHudRate(1048576), '1.0 MiB/s');
  });

  testWidgets('two consumers share one sampler and the last removal stops native reads', (tester) async {
    var reads = 0;
    final telemetry = PlaybackTelemetry(
      read: () async {
        reads++;
        return const PlaybackStats(downloadBytesPerSecond: 1024);
      },
    );
    void first() {}
    void second() {}
    telemetry
      ..addListener(first)
      ..addListener(second);
    await tester.pump();
    expect(reads, 1);
    await tester.pump(const Duration(seconds: 1));
    expect(reads, 2);
    telemetry.removeListener(first);
    await tester.pump(const Duration(seconds: 1));
    expect(reads, 3);
    telemetry.removeListener(second);
    await tester.pump(const Duration(seconds: 3));
    expect(reads, 3);
    telemetry.dispose();
  });

  testWidgets('late statistics cannot appear under the next source', (tester) async {
    var identity = 1;
    final pending = Completer<PlaybackStats?>();
    final telemetry = PlaybackTelemetry(read: () => pending.future, identity: () => identity);
    void changed() {}
    telemetry.addListener(changed);
    identity = 2;
    pending.complete(const PlaybackStats(downloadBytesPerSecond: 999));
    await tester.pump();
    expect(telemetry.value, isNull);
    expect(telemetry.downloadAverage, isNull);
    telemetry
      ..removeListener(changed)
      ..dispose();
  });

  for (final corner in PlaybackHudConfig.corners.keys) {
    testWidgets('HUD at $corner fits a small video with large text and does not intercept taps', (tester) async {
      var taps = 0;
      var reads = 0;
      final telemetry = PlaybackTelemetry(
        read: () async {
          reads++;
          return const PlaybackStats(downloadBytesPerSecond: 2048);
        },
      );
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: Center(
              child: SizedBox(
                width: 240,
                height: 120,
                child: MediaQuery(
                  data: const MediaQueryData(textScaler: TextScaler.linear(2)),
                  child: Stack(
                    children: [
                      Positioned.fill(
                        child: GestureDetector(behavior: HitTestBehavior.opaque, onTap: () => taps++),
                      ),
                      PlaybackHudView(
                        config: PlaybackHudConfig(mode: 'always', speed: true, corner: corner, size: 48),
                        telemetry: telemetry,
                        controls: false,
                        clearance: const EdgeInsets.only(top: 100, bottom: 100),
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ),
        ),
      );
      await tester.pump();
      expect(find.byKey(const ValueKey('live-play-clock')), findsOneWidget);
      expect(find.textContaining('2.0 KiB/s'), findsOneWidget);
      expect(reads, 1);
      expect(tester.takeException(), isNull);
      await tester.tapAt(tester.getCenter(find.byKey(const ValueKey('playback-hud'))));
      expect(taps, 1);
      await tester.pumpWidget(const SizedBox.shrink());
      await tester.pump(const Duration(seconds: 2));
      expect(reads, 1);
      telemetry.dispose();
    });
  }
}
