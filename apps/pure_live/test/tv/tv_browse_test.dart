// A17.3: TV live browsing — the follows page.
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:live_core/live_core.dart';
import 'package:live_ui/live_ui.dart';
import 'package:pure_live/app/services.dart';
import 'package:pure_live/features/favorite/favorite_controller.dart';
import 'package:pure_live/features/favorite/follow_refresher.dart';
import 'package:pure_live/tv/pages/tv_favorites_pane.dart';
import 'package:pure_live/tv/tv_theme.dart';
import 'package:pure_live/tv/widgets/tv_room_card.dart';
import 'package:pure_live/tv/widgets/tv_room_row.dart';

import '../support.dart';

final class _Site extends LiveSite {
  new(this.id, this.rooms);

  @override
  final String id;

  @override
  String get name => id;

  final Map<String, LiveRoom> rooms;

  @override
  Future<LiveRoom> getRoomDetail({required String roomId}) async => rooms[roomId]!;
}

LiveRoom _room(String platform, String id, LiveStatus status) => LiveRoom(
  platform: platform,
  roomId: id,
  nick: '主播$id',
  title: '标题$id',
  liveStatus: status,
);

void main() {
  testWidgets('A17.3 c2, c3: states and platforms on one line with counts; off air as two columns of rows', (
    tester,
  ) async {
    tester.view
      ..physicalSize = const Size(1920, 1080)
      ..devicePixelRatio = 2;
    addTearDown(tester.view.reset);
    final bilibili = {
      '1': _room('bilibili', '1', LiveStatus.live),
      '2': _room('bilibili', '2', LiveStatus.offline),
      '3': _room('bilibili', '3', LiveStatus.offline),
    };
    final douyu = {'4': _room('douyu', '4', LiveStatus.live), '5': _room('douyu', '5', LiveStatus.offline)};
    final services = (await tester.runAsync(() async {
      final services = await testServices();
      for (final room in [...bilibili.values, ...douyu.values]) {
        await services.store.follows.add(room);
      }
      return services;
    }))!;
    await tester.runAsync(loadStrings);
    final sites = SiteRegistry({'bilibili': () => _Site('bilibili', bilibili), 'douyu': () => _Site('douyu', douyu)});
    final controller = FavoriteController(
      store: services.store,
      refresher: FollowRefresher(sites: sites),
    );
    final scheme = ColorScheme.fromSeed(seedColor: LiveTheme.brandBlue, brightness: Brightness.dark);
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          appServicesProvider.overrideWithValue(services),
          favoriteControllerProvider.overrideWith((ref) {
            ref.onDispose(controller.dispose);
            return controller..start();
          }),
        ],
        child: MaterialApp(
          theme: ThemeData(colorScheme: scheme),
          home: TvTheme(
            palette: TvPalette.of(scheme),
            child: const Scaffold(body: TvFavoritesPane()),
          ),
        ),
      ),
    );
    for (var i = 0; i < 8; i++) {
      await tester.runAsync(() => Future<void>.delayed(const Duration(milliseconds: 30)));
      await tester.pump(const Duration(milliseconds: 50));
    }
    expect(find.text('已开播'), findsOneWidget);
    expect(find.text('录播'), findsOneWidget);
    expect(find.text('未开播'), findsOneWidget);
    final live = tester.getCenter(find.byKey(const ValueKey('tv-tab-live')));
    final douyuTab = tester.getCenter(find.byKey(const ValueKey('tv-tab-douyu')));
    expect(live.dy, douyuTab.dy, reason: 'one line');
    expect(find.byKey(const ValueKey('tv-follow-divider')), findsOneWidget);
    final liveCount = tester.widget<Text>(find.byKey(const ValueKey('tv-tab-live-count'))).data;
    expect(liveCount, '2');
    expect(tester.widget<Text>(find.byKey(const ValueKey('tv-tab-douyu-count'))).data, '1', reason: 'live in douyu');
    expect(find.byType(TvRoomCard), findsNWidgets(2));

    await tester.tap(find.text('未开播'));
    for (var i = 0; i < 4; i++) {
      await tester.pump(const Duration(milliseconds: 50));
    }
    expect(find.byType(TvRoomCard), findsNothing);
    expect(find.byType(TvRoomRow), findsNWidgets(3));
    final first = tester.getRect(find.byType(TvRoomRow).at(0));
    final second = tester.getRect(find.byType(TvRoomRow).at(1));
    expect(first.top, second.top, reason: 'two to a line');
    expect(find.text('主播2'), findsOneWidget);

    await tester.pumpWidget(const SizedBox.shrink());
    await tester.runAsync(() => Future<void>.delayed(const Duration(milliseconds: 20)));
    await tester.pump(const Duration(seconds: 5));
    await tester.runAsync(services.close);
  });
}
