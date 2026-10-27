// Native acceptance fixture: real pages and mpv, generated loopback media,
// in-memory follows/settings and no account or production data access.
import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:live_core/live_core.dart';
import 'package:live_danmaku/live_danmaku.dart';
import 'package:live_net/live_net.dart';
import 'package:live_player/live_player.dart';
import 'package:live_store/live_store.dart';
import 'package:live_ui/live_ui.dart';
import 'package:pure_live/app/bootstrap.dart';
import 'package:pure_live/app/desktop/desktop_window.dart';
import 'package:pure_live/app/launch_args.dart';
import 'package:pure_live/app/services.dart';
import 'package:pure_live/features/live_play/live_play_page.dart';
import 'package:pure_live/features/multiview/logic/multiview_session.dart';
import 'package:pure_live/features/multiview/multiview_page.dart';
import 'package:pure_live/features/settings/settings_model.dart';
import 'package:pure_live/features/settings/settings_section_view.dart';
import 'package:pure_live/i18n/i18n.dart';
import 'package:pure_live/routes/app_navigator.dart';
import 'package:pure_live/routes/route_args.dart';
import 'package:pure_live/routes/route_path.dart';
import 'package:pure_live/tv/room/tv_live_play_page.dart';

final class _NoSecrets implements SecretCipher {
  @override
  Future<Uint8List> seal(String ref, String plain) => throw StateError('No accounts in native fixture');
  @override
  Future<String> open(String ref, Uint8List sealed) => throw StateError('No accounts in native fixture');
}

final class _NoExternalHttp implements LiveHttp {
  @override
  Future<LiveResponse> send(LiveRequest request) => throw StateError('External network disabled');
  @override
  Future<LiveStreamedResponse> open(LiveRequest request) => throw StateError('External network disabled');
  @override
  void close() {}
}

LiveRoom _room(String id, {bool offline = false}) => LiveRoom(
  platform: SiteIds.bilibili,
  roomId: id,
  nick: '本地样本$id',
  title: id == 'a' ? '已下播样本' : '自动换台验证$id',
  liveStatus: offline ? LiveStatus.offline : LiveStatus.live,
);

final class _LocalSite extends LiveSite {
  new(this.port);
  final int port;
  final List<String> details = [];
  @override
  String get id => SiteIds.bilibili;
  @override
  String get name => '本地验证';
  @override
  Future<LiveRoom> getRoomDetail({required String roomId}) async {
    details.add(roomId);
    return _room(roomId, offline: roomId == 'a');
  }

  @override
  Future<List<LivePlayQuality>> getPlayQualities({required LiveRoom detail}) async => const [
    LivePlayQuality(quality: '测试视频', id: 'local'),
  ];
  @override
  Future<List<String>> getPlayUrls({required LiveRoom detail, required LivePlayQuality quality}) async => [
    'http://127.0.0.1:$port/${detail.roomId}.mp4',
  ];
}

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  currentStrings = await AppStrings.load(AppLanguage.zh, rootBundle);
  const encoded = String.fromEnvironment('PURELIVE_PLAYBACK_FIXTURE');
  const fixturePath = String.fromEnvironment('PURELIVE_PLAYBACK_FIXTURE_PATH');
  if (encoded.isEmpty && fixturePath.isEmpty) throw StateError('Provide the generated playback.mp4 fixture');
  const output = String.fromEnvironment('PURELIVE_PROOF_DIR');
  final root = Directory(output.isEmpty ? '${Directory.systemTemp.path}/purelive-issue68-native' : output);
  await root.create(recursive: true);
  // Windows batch build steps cannot carry a whole video in DART_DEFINES.
  final video = encoded.isEmpty ? await File(fixturePath).readAsBytes() : base64Decode(encoded);
  final server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
  server.listen((request) async {
    final response = request.response;
    try {
      final range = request.headers.value(HttpHeaders.rangeHeader);
      final match = range == null ? null : RegExp(r'^bytes=(\d+)-(\d*)$').firstMatch(range);
      final start = match == null ? 0 : int.parse(match.group(1)!);
      final end = match == null || match.group(2)!.isEmpty
          ? video.length - 1
          : int.parse(match.group(2)!).clamp(0, video.length - 1);
      if (start > end || start >= video.length || (range != null && match == null)) {
        response.statusCode = HttpStatus.requestedRangeNotSatisfiable;
        return;
      }
      if (range != null) {
        response.statusCode = HttpStatus.partialContent;
        response.headers.set(HttpHeaders.contentRangeHeader, 'bytes $start-$end/${video.length}');
      }
      response
        ..headers.contentType = ContentType('video', 'mp4')
        ..headers.set(HttpHeaders.acceptRangesHeader, 'bytes')
        ..contentLength = end - start + 1;
      if (request.method != 'HEAD') response.add(video.sublist(start, end + 1));
    } on SocketException {
      // A page replacement closes the old native player's loopback request.
    } finally {
      await response.close().catchError((Object _) {});
    }
  });
  final cipher = _NoSecrets();
  final store = await LiveStore.memory(cipher: cipher);
  await store.settings.setAll({
    Settings.showSplashPage: false,
    Settings.enableAutoCheckUpdate: false,
    Settings.globalVolumeMute: true,
    Settings.useHardStopOnExit: true,
    Settings.floatPlay: false,
    Settings.windowWidth: 1000.0,
    Settings.windowHeight: 760.0,
  });
  for (final id in ['a', 'b', 'busy', 'd']) {
    await store.follows.add(_room(id));
  }
  await writeMultiviewSession(store.meta, {
    'layout': 'dual',
    'smallCellsLowQuality': false,
    'danmaku': false,
    'rooms': [_room('a').toJson(), _room('busy').toJson()],
  });
  final services = AppBootstrap.wire(
    store: store,
    cipher: cipher,
    launch: const LaunchArgs(),
    dataRoot: root,
    http: _NoExternalHttp(),
    background: false,
  );
  await DesktopShell.start(store, primary: false, dataRoot: root, instanceId: 'issue68-native');
  final site = _LocalSite(server.port);
  final sessions = <PlaybackSession>[];
  final engines = <PlaybackSession, MpvEngine>{};
  AppNavigator.toast = (message) => debugPrint('issue68-toast: $message');
  runApp(
    ProviderScope(
      overrides: [
        appServicesProvider.overrideWithValue(services),
        sitesProvider.overrideWithValue(SiteRegistry({SiteIds.bilibili: () => site})),
        danmakuProvider.overrideWithValue(DanmakuRegistry({})),
        playbackSessionFactoryProvider.overrideWithValue(({config}) {
          late final PlaybackSession session;
          session = PlaybackSession(
            engine: () async {
              final engine = await MpvEngine.create(config: config);
              engines[session] = engine;
              return engine;
            },
            opener: services.mediaOpener,
          );
          sessions.add(session);
          return session;
        }),
      ],
      child: MaterialApp(
        theme: const LiveTheme().light,
        home: _Probe(store: store, site: site, sessions: sessions, engines: engines, root: root),
      ),
    ),
  );
}

class _Probe extends StatefulWidget {
  const new({
    required this.store,
    required this.site,
    required this.sessions,
    required this.engines,
    required this.root,
  });
  final LiveStore store;
  final _LocalSite site;
  final List<PlaybackSession> sessions;
  final Map<PlaybackSession, MpvEngine> engines;
  final Directory root;
  @override
  State<_Probe> createState() => _ProbeState();
}

class _ProbeState extends State<_Probe> {
  String _phase = '设置';
  int _firstSession = 0;
  Timer? _watch;
  final Map<String, Object?> _accepted = {};

  @override
  void initState() {
    super.initState();
    _watch = Timer.periodic(const Duration(seconds: 1), (_) => unawaited(_record()));
  }

  Future<void> _record() async {
    final active = widget.sessions.skip(_firstSession).where((session) {
      final engine = widget.engines[session];
      return session.state.status == PlaybackStatus.playing &&
          engine != null &&
          engine.player.state.playing &&
          engine.player.state.position > const Duration(seconds: 1);
    });
    final paths = active.map((session) => session.state.line?.url ?? '').toList();
    final expected = _phase == '多画面' ? ['/b.mp4', '/busy.mp4'] : ['/b.mp4'];
    final passed =
        _phase != '设置' &&
        paths.length == expected.length &&
        expected.every((path) => paths.any((p) => p.endsWith(path)));
    if (passed) _accepted[_phase] = {'paths': paths, 'native_playing': true, 'sessions': paths.length};
    await File('${widget.root.path}/result.json').writeAsString(
      jsonEncode({
        'phase': _phase,
        'platform': Platform.operatingSystem,
        'auto_switch_enabled': widget.store.settings.get(Settings.autoSwitchLiveFollows),
        'current_native_playing': paths,
        'accepted': _accepted,
        'detail_requests': widget.site.details,
        'fixture_only': true,
        'production_data_accessed': false,
      }),
      flush: true,
    );
  }

  @override
  void dispose() {
    _watch?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(
      title: const Text('#68 本地原生验证'),
      bottom: PreferredSize(
        preferredSize: const Size.fromHeight(48),
        child: Row(
          children: [
            for (final phase in ['设置', '单间', '电视', '多画面'])
              Expanded(
                child: TextButton(
                  onPressed: () => setState(() {
                    _firstSession = widget.sessions.length;
                    _phase = phase;
                  }),
                  child: Text(phase),
                ),
              ),
          ],
        ),
      ),
    ),
    body: KeyedSubtree(
      key: ValueKey(_phase),
      child: switch (_phase) {
        '单间' => LivePlayPage(route: RouteArgs(RoutePath.kLivePlay, arguments: _room('a'))),
        '电视' => Theme(
          data: const LiveTheme().dark,
          child: TvLivePlayPage(route: RouteArgs(RoutePath.kLivePlay, arguments: _room('a'))),
        ),
        '多画面' => const MultiviewPage(route: RouteArgs(RoutePath.kMultiview)),
        _ => const SettingsSectionView(section: SettingsSection.video, highlight: 'auto_switch_live_follows'),
      },
    ),
  );
}
