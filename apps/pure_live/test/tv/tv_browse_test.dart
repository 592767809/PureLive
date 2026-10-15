// A17.3: TV live browsing — the follows page.
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:live_core/live_core.dart';
import 'package:live_store/live_store.dart';
import 'package:live_ui/live_ui.dart';
import 'package:pure_live/app/services.dart';
import 'package:pure_live/features/favorite/favorite_controller.dart';
import 'package:pure_live/features/favorite/follow_refresher.dart';
import 'package:pure_live/tv/pages/tv_favorites_pane.dart';
import 'package:pure_live/tv/pages/tv_followed_areas_pane.dart';
import 'package:pure_live/tv/pages/tv_history_pane.dart';
import 'package:pure_live/tv/tv_theme.dart';
import 'package:pure_live/tv/widgets/tv_area_card.dart';
import 'package:pure_live/tv/widgets/tv_area_dialog.dart';
import 'package:pure_live/tv/widgets/tv_button.dart';
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

LiveRoom _room(String platform, String id, LiveStatus status) =>
    LiveRoom(platform: platform, roomId: id, nick: '主播$id', title: '标题$id', liveStatus: status);

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

  Future<AppServices> pumpPlain(WidgetTester tester, Widget child) async {
    tester.view
      ..physicalSize = const Size(1920, 1080)
      ..devicePixelRatio = 2;
    addTearDown(tester.view.reset);
    final services = (await tester.runAsync(testServices))!;
    await tester.runAsync(loadStrings);
    final scheme = ColorScheme.fromSeed(seedColor: LiveTheme.brandBlue, brightness: Brightness.dark);
    await tester.pumpWidget(
      ProviderScope(
        overrides: [appServicesProvider.overrideWithValue(services)],
        child: MaterialApp(
          theme: ThemeData(colorScheme: scheme),
          home: TvTheme(
            palette: TvPalette.of(scheme),
            child: Scaffold(body: child),
          ),
        ),
      ),
    );
    await settleBrowse(tester);
    return services;
  }

  Future<void> closePlain(WidgetTester tester, AppServices services) async {
    await tester.pumpWidget(const SizedBox.shrink());
    await tester.runAsync(() => Future<void>.delayed(const Duration(milliseconds: 20)));
    await tester.pump(const Duration(seconds: 5));
    await tester.runAsync(services.close);
  }

  const area = LiveArea(platform: 'bilibili', areaId: '1', areaName: '英雄联盟', typeName: '网游');

  testWidgets('A17.3 c7: a held OK on an area opens the dialog (not a follow); unfollowing asks, "取消" first', (
    tester,
  ) async {
    final services = await pumpPlain(
      tester,
      Consumer(
        builder: (context, ref, _) =>
            TextButton(onPressed: () => showTvAreaDialog(context, ref, area), child: const Text('分区')),
      ),
    );
    final store = services.store.followAreas;
    await tester.tap(find.text('分区'));
    await settleBrowse(tester);
    expect(find.text('英雄联盟'), findsOneWidget);
    expect(find.text('哔哩哔哩 · 网游'), findsOneWidget);
    expect(find.text('打开分区'), findsOneWidget);
    expect(await tester.runAsync(() => store.contains(area)), isFalse, reason: 'nothing happened yet');
    await tester.tap(find.text('关注分区'));
    await settleBrowse(tester);
    expect(await tester.runAsync(() => store.contains(area)), isTrue);

    await tester.tap(find.text('分区'));
    await settleBrowse(tester);
    await tester.tap(find.text('取消关注'));
    await settleBrowse(tester);
    expect(FocusManager.instance.primaryFocus?.context?.findAncestorWidgetOfExactType<TvButton>()?.label, '取消');
    await tester.sendKeyEvent(LogicalKeyboardKey.select);
    await settleBrowse(tester);
    expect(await tester.runAsync(() => store.contains(area)), isTrue, reason: 'cancelled');
    await closePlain(tester, services);
  });

  testWidgets('A17.3 c9: followed areas on their own, "全部" and the platforms that have some, with counts', (
    tester,
  ) async {
    final services = await pumpPlain(tester, const TvFollowedAreasPane());
    expect(find.text('未发现分区'), findsOneWidget);
    await tester.runAsync(() async {
      await services.store.followAreas.add(area);
      await services.store.followAreas.add(
        const LiveArea(platform: 'bilibili', areaId: '2', areaName: '原神', typeName: '手游'),
      );
      await services.store.followAreas.add(
        const LiveArea(platform: 'douyu', areaId: '3', areaName: '王者荣耀', typeName: '手游'),
      );
    });
    await settleBrowse(tester);
    expect(tester.widget<Text>(find.byKey(const ValueKey('tv-tab-all-count'))).data, '3');
    expect(tester.widget<Text>(find.byKey(const ValueKey('tv-tab-bilibili-count'))).data, '2');
    expect(tester.widget<Text>(find.byKey(const ValueKey('tv-tab-douyu-count'))).data, '1');
    expect(find.byType(TvAreaCard), findsNWidgets(3));
    expect(find.text('哔哩哔哩 · 网游'), findsOneWidget, reason: 'in "全部" the platform and category');
    await closePlain(tester, services);
  });

  testWidgets('A17.3 c10: history says "N / 50 条", groups by day, keeps a chosen number (fewer asks first)', (
    tester,
  ) async {
    final services = await pumpPlain(tester, const TvHistoryPane());
    final now = DateTime.now();
    await tester.runAsync(() async {
      final history = services.store.history;
      await history.record(_room('bilibili', '1', LiveStatus.live), now: now);
      await history.record(_room('douyu', '2', LiveStatus.live), now: now.subtract(const Duration(days: 1)));
      await history.record(_room('douyu', '3', LiveStatus.live), now: now.subtract(const Duration(days: 30)));
    });
    await settleBrowse(tester);
    expect(find.text('观看记录 3 / 50 条'), findsOneWidget);
    expect(find.text('今天'), findsOneWidget);
    expect(find.text('昨天'), findsOneWidget);
    expect(find.text('更早'), findsOneWidget);
    expect(tester.widget<Text>(find.byKey(const ValueKey('tv-tab-douyu-count'))).data, '2');
    expect(find.text('保留数量 50'), findsOneWidget);

    await tester.tap(find.byKey(const ValueKey('tv-history-limit')));
    await settleBrowse(tester);
    expect(find.byKey(const ValueKey('tv-option-current')), findsOneWidget);
    await tester.tap(find.text('20'));
    await settleBrowse(tester);
    expect(services.store.settings.get(Settings.historyLimit), 20);
    await closePlain(tester, services);
  });
}

/// Lets the store answer and the frames run.
Future<void> settleBrowse(WidgetTester tester) async {
  for (var i = 0; i < 6; i++) {
    await tester.runAsync(() => Future<void>.delayed(const Duration(milliseconds: 20)));
    await tester.pump(const Duration(milliseconds: 50));
  }
}
