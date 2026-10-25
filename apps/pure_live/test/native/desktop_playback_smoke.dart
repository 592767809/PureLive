// Hosted macOS integration: generated loopback video, real mpv, actual
// window occlusion/minimization and the production room background policy.
import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:live_core/live_core.dart';
import 'package:live_danmaku/live_danmaku.dart';
import 'package:live_media/live_media.dart';
import 'package:live_player/live_player.dart';
import 'package:live_store/live_store.dart';
import 'package:pure_live/app/desktop/desktop_window.dart';
import 'package:pure_live/features/live_play/logic/background_playback.dart';
import 'package:pure_live/features/live_play/logic/room_controller.dart';
import 'package:window_manager/window_manager.dart';

import '../features/live_play/live_play_support.dart' show FakeSite;

final class _NoSecrets implements SecretCipher {
  @override
  Future<Uint8List> seal(String ref, String plain) => throw StateError('No secrets in native fixture');
  @override
  Future<String> open(String ref, Uint8List sealed) => throw StateError('No secrets in native fixture');
}

final class _LocalSite extends FakeSite {
  new(this.url)
    : super(LiveRoom(platform: SiteIds.bilibili, roomId: 'fixture', nick: '测试视频', liveStatus: LiveStatus.live));
  final String url;
  @override
  Future<List<String>> getPlayUrls({required LiveRoom detail, required LivePlayQuality quality}) async => [url];
}

final class _Lifecycle with WidgetsBindingObserver {
  final List<String> states = [];
  @override
  void didChangeAppLifecycleState(AppLifecycleState state) => states.add(state.name);
}

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  final root = Directory('${Directory.systemTemp.path}/purelive-desktop-playback-smoke');
  await root.create(recursive: true);
  Future<void> stage(String name) =>
      File('${root.path}/stage.json').writeAsString(jsonEncode({'stage': name}), flush: true);
  Future<void> until(bool Function() ready, String name) async {
    final clock = Stopwatch()..start();
    while (!ready()) {
      if (clock.elapsed > const Duration(seconds: 45)) throw StateError('Timeout: $name');
      await Future<void>.delayed(const Duration(seconds: 1));
    }
  }

  final result = <String, Object?>{'operating_system': Platform.operatingSystem, 'passed': false};
  HttpServer? server;
  LiveStore? store;
  PlaybackSession? session;
  LiveRoomController? controller;
  RoomBackgroundPolicy? policy;
  final lifecycle = _Lifecycle();
  WidgetsBinding.instance.addObserver(lifecycle);
  try {
    if (!Platform.isMacOS) throw StateError('This probe requires hosted macOS');
    final video = File('${root.path}/fixture.y4m');
    final output = await video.open(mode: FileMode.write);
    await output.writeString('YUV4MPEG2 W160 H90 F10:1 Ip A1:1 C420jpeg\n');
    final pixels = Uint8List(160 * 90 * 3 ~/ 2)..fillRange(160 * 90, 160 * 90 * 3 ~/ 2, 128);
    for (var frame = 0; frame < 2400; frame++) {
      pixels.fillRange(0, 160 * 90, 32 + frame % 180);
      await output.writeString('FRAME\n');
      await output.writeFrom(pixels);
    }
    await output.close();
    server = (await HttpServer.bind(InternetAddress.loopbackIPv4, 0))
      ..listen((request) async {
        final response = request.response;
        try {
          response
            ..headers.contentType = ContentType('video', 'x-yuv4mpeg')
            ..contentLength = await video.length();
          await response.addStream(video.openRead());
        } on HttpException {
          // A disposed player may stop reading the generated stream.
        } on SocketException {
          // The local client may disconnect after the probe completes.
        } finally {
          await response.close().catchError((Object _) {});
        }
      });
    store = await LiveStore.memory(cipher: _NoSecrets());
    await DesktopShell.start(store, primary: false);
    final engine = await MpvEngine.create();
    session = PlaybackSession(engine: () async => engine, opener: MediaOpener());
    final room = LiveRoom(platform: SiteIds.bilibili, roomId: 'fixture', nick: '测试视频');
    controller = LiveRoomController(
      room: room,
      site: _LocalSite('http://127.0.0.1:${server.port}/fixture.y4m'),
      session: session,
      danmaku: EmptyDanmakuConnection(),
      danmakuSupported: false,
      store: store,
      toast: (_) {},
      refreshInterval: Duration.zero,
    );
    policy = RoomBackgroundPolicy(
      controller: controller,
      settings: store.settings,
      desktop: true,
      desktopMinimized: DesktopWindow.minimized,
    )..start();
    runApp(
      MaterialApp(
        home: Scaffold(body: LiveVideoView(session: session, keepScreenOn: false)),
      ),
    );
    await controller.start();
    await until(() => engine.player.state.playing && engine.player.state.position > Duration.zero, 'native playback');
    await windowManager.show();
    await windowManager.focus();
    await until(
      () =>
          WidgetsBinding.instance.lifecycleState == AppLifecycleState.resumed ||
          WidgetsBinding.instance.lifecycleState == AppLifecycleState.inactive,
      'initial visible window',
    );
    lifecycle.states.clear();
    final before = engine.player.state.position;
    await stage('cover_now');
    await until(() => lifecycle.states.contains('hidden'), 'real window occlusion');
    await Future<void>.delayed(const Duration(seconds: 5));
    if (!engine.player.state.playing || engine.player.state.position <= before + const Duration(seconds: 2)) {
      throw StateError('Occlusion paused native playback');
    }
    result['occlusion'] = {'native_playing': true, 'position_advanced': true, 'hidden_event_seen': true};
    await stage('uncover_now');
    await until(
      () =>
          WidgetsBinding.instance.lifecycleState == AppLifecycleState.resumed ||
          WidgetsBinding.instance.lifecycleState == AppLifecycleState.inactive,
      'uncover',
    );
    await windowManager.minimize();
    await until(() => DesktopWindow.minimized.value, 'native minimize');
    final minimizedAt = engine.player.state.position;
    await Future<void>.delayed(const Duration(seconds: 3));
    if (!engine.player.state.playing || engine.player.state.position <= minimizedAt + const Duration(seconds: 1)) {
      throw StateError('Default minimize unexpectedly paused');
    }
    result['default_minimize_plays'] = true;
    await windowManager.restore();
    await until(() => !DesktopWindow.minimized.value, 'native restore');
    await store.settings.set(Settings.desktopPauseWhenMinimized, true);
    await windowManager.minimize();
    await until(() => DesktopWindow.minimized.value && !engine.player.state.playing, 'opt-in minimize pause');
    result['opt_in_minimize_pauses'] = true;
    await windowManager.restore();
    await until(() => !DesktopWindow.minimized.value && engine.player.state.playing, 'opt-in restore resumes');
    result['restore_resumes_policy_pause'] = true;
    await session.pause();
    await windowManager.minimize();
    await until(() => DesktopWindow.minimized.value, 'manual pause minimize');
    await Future<void>.delayed(const Duration(seconds: 2));
    await windowManager.restore();
    await until(() => !DesktopWindow.minimized.value, 'manual pause restore');
    await Future<void>.delayed(const Duration(seconds: 2));
    if (engine.player.state.playing) throw StateError('Restore resumed a user pause');
    result.addAll({'manual_pause_preserved': true, 'passed': true});
  } on Object catch (error, stack) {
    result.addAll({'error': error.toString(), 'stack': stack.toString()});
  } finally {
    result['lifecycle_states'] = lifecycle.states;
    WidgetsBinding.instance.removeObserver(lifecycle);
    policy?.dispose();
    controller?.dispose();
    await session?.dispose();
    await server?.close(force: true);
    await DesktopShell.current?.dispose();
    await store?.close();
    await File('${root.path}/result.json').writeAsString(jsonEncode(result), flush: true);
  }
}
