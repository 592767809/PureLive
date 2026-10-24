import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:live_core/live_core.dart';
import 'package:live_danmaku/live_danmaku.dart';
import 'package:live_store/live_store.dart';
import 'package:live_ui/live_ui.dart';
import 'package:pure_live/app/app.dart';
import 'package:pure_live/app/services.dart';
import 'package:pure_live/app/ui_mode.dart';
import 'package:pure_live/features/home/home_page.dart';
import 'package:pure_live/features/live_play/logic/predictive_back.dart';
import 'package:pure_live/features/live_play/logic/room_controller.dart';
import 'package:pure_live/features/settings/settings_catalog.dart';
import 'package:pure_live/features/settings/settings_model.dart';
import 'package:pure_live/routes/app_navigator.dart';
import 'package:pure_live/shared/danmaku/danmaku_overlay.dart';
import 'package:pure_live/tv/home/tv_home_page.dart';
import 'package:pure_live/tv/room/tv_live_play_page.dart';
import 'package:pure_live/tv/tv_theme.dart';
import 'package:pure_live/tv/widgets/tv_button.dart';
import 'package:pure_live/tv/widgets/tv_dialogs.dart';
import 'package:pure_live/tv/widgets/tv_focusable.dart';
import 'package:pure_live/tv/widgets/tv_room_card.dart';
import 'package:pure_live/tv/widgets/tv_room_row.dart';
import 'package:pure_live/tv/widgets/tv_status.dart';
import 'package:pure_live/tv/widgets/tv_tabs.dart';

import '../features/live_play/live_play_support.dart';
import '../qa_capture.dart';
import '../support.dart';

/// A platform with [count] recommended rooms that all play.
final class _TvSite extends LiveSite {
  new(this.count, {this.offline = const {}});

  final int count;

  /// Rooms off air.
  final Set<int> offline;

  @override
  String get id => SiteIds.bilibili;

  @override
  String get name => '哔哩哔哩';

  LiveRoom room(int n) => LiveRoom(
    platform: SiteIds.bilibili,
    roomId: '$n',
    title: '直播 $n',
    nick: '主播$n',
    popularity: '${1000 - n}',
    audienceMetricType: AudienceMetricType.popularity,
    liveStatus: offline.contains(n) ? LiveStatus.offline : LiveStatus.live,
  );

  @override
  Future<List<LiveRoom>> getRecommendRooms({int page = 1, int pageSize = 30}) async =>
      page == 1 ? [for (var n = 0; n < count; n++) room(n)] : const [];

  @override
  Future<LiveRoom> getRoomDetail({required String roomId}) async => room(int.parse(roomId));

  @override
  Future<List<LiveRoom>> searchRooms(String keyword, {int page = 1, int pageSize = 30}) async => [
    if (page == 1)
      for (var n = 0; n < count; n++)
        if (room(n).title.contains(keyword)) room(n),
  ];

  @override
  Future<List<LiveAnchorItem>> searchAnchors(String keyword, {int page = 1, int pageSize = 30}) async => [
    if (page == 1)
      for (var n = 0; n < count; n++)
        if (room(n).title.contains(keyword))
          LiveAnchorItem(roomId: '$n', avatar: '', userName: '主播$n', liveStatus: n.isOdd),
  ];

  @override
  Future<List<LivePlayQuality>> getPlayQualities({required LiveRoom detail}) async => const [
    LivePlayQuality(quality: '原画', id: 10000),
    LivePlayQuality(quality: '流畅', id: 80),
  ];

  @override
  Future<List<String>> getPlayUrls({required LiveRoom detail, required LivePlayQuality quality}) async => [
    'https://a.example/${detail.roomId}/${quality.id}.flv',
  ];
}

/// A second followed platform without network calls.
final class _ExtraTvSite extends LiveSite {
  new(this.id, this.rooms);

  @override
  final String id;

  @override
  String get name => id;

  final List<LiveRoom> rooms;

  @override
  Future<LiveRoom> getRoomDetail({required String roomId}) async => rooms.firstWhere((room) => room.roomId == roomId);
}

final List<String> _toasts = [];

/// The app on a 1080p panel in [mode] (`uiMode`), on a device that is
/// [television] or not.
Future<AppServices> _pumpApp(
  WidgetTester tester, {
  String mode = 'tv',
  bool television = false,
  int rooms = 10,
  bool noticeAccepted = true,
  List<int> follows = const [],
  Set<int> offline = const {},
  List<LiveSite> extraSites = const [],
  List<LiveRoom> extraFollows = const [],
  bool taggedFollows = false,
}) async {
  tester.view
    ..physicalSize = const Size(1920, 1080)
    ..devicePixelRatio = 1;
  addTearDown(tester.view.reset);
  final base = (await tester.runAsync(testServices))!;
  await tester.runAsync(() async {
    final settings = base.store.settings;
    await settings.set(Settings.showSplashPage, false);
    await settings.set(Settings.enableAutoCheckUpdate, false);
    await settings.set(Settings.hotAreasList, [SiteIds.bilibili, for (final site in extraSites) site.id]);
    await settings.set(Settings.uiMode, mode);
    await settings.set(Settings.language, '简体中文');
    if (noticeAccepted) await base.store.meta.set(TvHomePage.noticeKey, '1');
  });
  final site = _TvSite(rooms, offline: offline);
  await tester.runAsync(() async {
    final rooms = [for (final n in follows) site.room(n), ...extraFollows];
    for (final room in rooms) {
      await base.store.follows.add(room);
    }
    if (taggedFollows) {
      final tag = (await base.store.tags.add('回归分组'))!;
      for (final room in rooms) {
        await base.store.tags.setTagsOf(room, [tag.id]);
      }
    }
  });
  final services = AppServices(
    store: base.store,
    cipher: base.cipher,
    http: base.http,
    proxy: base.proxy,
    cookies: base.cookies,
    sites: SiteRegistry({SiteIds.bilibili: () => site, for (final extra in extraSites) extra.id: () => extra}),
    danmaku: base.danmaku,
    launch: base.launch,
    dataRoot: base.dataRoot,
    followsReady: base.followsReady,
    mediaOpener: base.mediaOpener,
  );
  final strings = (await tester.runAsync(loadStrings))!;
  await tester.pumpWidget(
    ProviderScope(
      overrides: [
        appServicesProvider.overrideWithValue(services),
        televisionDeviceProvider.overrideWithValue(television),
        danmakuProvider.overrideWithValue(DanmakuRegistry({SiteIds.bilibili: FakeDanmaku.new})),
        playbackSessionFactoryProvider.overrideWithValue(({config}) => fakeSession(FakeEngine())),
      ],
      child: PureLiveApp(strings: strings, bundle: FileAssetBundle()),
    ),
  );
  await _settle(tester);
  AppNavigator.toast = _toasts.add;
  return services;
}

/// Lets the store and the fakes answer (real time) and the frames run.
Future<void> _settle(WidgetTester tester, {int rounds = 4}) async {
  for (var i = 0; i < rounds; i++) {
    await tester.runAsync(() => Future<void>.delayed(const Duration(milliseconds: 20)));
    await tester.pump(const Duration(milliseconds: 50));
  }
}

Future<void> _close(WidgetTester tester, AppServices services) async {
  await tester.pumpWidget(const SizedBox.shrink());
  await tester.runAsync(() => Future<void>.delayed(const Duration(milliseconds: 20)));
  await tester.pump(const Duration(seconds: 5));
  await tester.runAsync(services.close);
}

/// Presses [key] (down and up) and lets the app follow.
Future<void> _press(WidgetTester tester, LogicalKeyboardKey key) async {
  await tester.sendKeyEvent(key);
  await _settle(tester, rounds: 2);
}

String? get _focused => FocusManager.instance.primaryFocus?.debugLabel;

void main() {
  testWidgets('issue #35: favorites Back visits the filter, menu and exit on both channels', (tester) async {
    await prepareQaFonts(tester);
    final services = await _pumpApp(tester, follows: [1, 2], offline: {2});
    addTearDown(RoomBackChannel.instance.reset);
    Future<void> back({required bool native}) async {
      if (native) {
        unawaited(
          tester.binding.defaultBinaryMessenger.handlePlatformMessage(
            'pure_live/predictive_back',
            const StandardMethodCodec().encodeMethodCall(const MethodCall('backInvoked')),
            (_) {},
          ),
        );
      } else {
        await tester.binding.handlePopRoute();
      }
      await tester.pump(const Duration(seconds: 1));
    }

    try {
      for (var attempt = 0; attempt < 5 && find.byType(TvRoomCard).evaluate().isEmpty; attempt++) {
        await tester.runAsync(() => Future<void>.delayed(const Duration(seconds: 1)));
        await tester.pump(const Duration(seconds: 1));
      }
      expect(find.byType(TvRoomCard), findsOneWidget);
      for (final native in [false, true]) {
        expect(_focused, 'tv menu favorites');
        tester.widget<TvFocusable>(find.byKey(const ValueKey('tv-tab-live'))).focusNode!.requestFocus();
        await tester.pump(const Duration(seconds: 1));
        expect(_focused, 'tab live');
        await tester.sendKeyEvent(LogicalKeyboardKey.arrowDown);
        await tester.pump(const Duration(seconds: 1));
        expect(_focused, 'cell 0');
        if (native) await captureQaFrame(tester, 'tv-favorites-back-cards');

        await back(native: native);
        expect(_focused, 'tab live', reason: 'first Back restores the filter instead of skipping to the menu');
        expect(find.byType(TvRoomCard), findsOneWidget, reason: 'the live selection is retained');
        if (native) await captureQaFrame(tester, 'tv-favorites-back-filter');
        await back(native: native);
        expect(_focused, 'tv menu favorites', reason: 'second Back reaches the side menu');
        if (native) await captureQaFrame(tester, 'tv-favorites-back-menu');
        await back(native: native);
        expect(find.text('退出纯粹直播？'), findsOneWidget, reason: 'the pane must not steal Back from the menu');
        await back(native: native);
        expect(find.text('退出纯粹直播？'), findsNothing);
        expect(_focused, 'tv menu favorites');
      }
    } finally {
      await _close(tester, services);
    }
  });

  Future<void> waitForFavorite(WidgetTester tester, Finder finder) async {
    for (var attempt = 0; attempt < 6 && finder.evaluate().isEmpty; attempt++) {
      await tester.runAsync(() => Future<void>.delayed(const Duration(seconds: 1)));
      await tester.pump(const Duration(seconds: 1));
    }
    expect(finder, findsWidgets);
  }

  Future<void> pageBack(WidgetTester tester) async {
    await tester.binding.handlePopRoute();
    await tester.pump(const Duration(seconds: 1));
  }

  Future<void> focusTab(WidgetTester tester, String id) async {
    tester.widget<TvFocusable>(find.byKey(ValueKey('tv-tab-$id'))).focusNode!.requestFocus();
    await tester.pump(const Duration(seconds: 1));
  }

  testWidgets('issue #35: unselected platform focus returns without changing the selected filter', (tester) async {
    final other = LiveRoom(
      platform: SiteIds.douyu,
      roomId: '35',
      title: '另一路',
      nick: '测试主播',
      liveStatus: LiveStatus.live,
    );
    final services = await _pumpApp(
      tester,
      follows: [1, 2],
      offline: {2},
      extraSites: [
        _ExtraTvSite(SiteIds.douyu, [other]),
      ],
      extraFollows: [other],
    );
    try {
      await waitForFavorite(tester, find.byType(TvRoomCard));
      await focusTab(tester, SiteIds.douyu);
      await tester.sendKeyEvent(LogicalKeyboardKey.arrowDown);
      await tester.pump(const Duration(seconds: 1));
      expect(_focused, startsWith('cell'));
      expect(find.byType(TvRoomCard), findsNWidgets(2));
      final platforms = find.byWidgetPredicate(
        (widget) => widget is TvTabBar && widget.tabs.any((tab) => tab.id == SiteIds.douyu),
      );
      TvTabBar bar() => tester.widget<TvTabBar>(platforms);
      expect(bar().tabs[bar().selected].id, 'all');
      await pageBack(tester);
      expect(_focused, 'tab douyu');
      expect(bar().tabs[bar().selected].id, 'all', reason: 'focusing the Douyu filter must not select it');
      await pageBack(tester);
      expect(_focused, 'tv menu favorites');
    } finally {
      await _close(tester, services);
    }
  });

  testWidgets('issue #35: offline rows return to their state and other destinations keep their Back', (tester) async {
    final services = await _pumpApp(tester, follows: [1, 2], offline: {2});
    try {
      await waitForFavorite(tester, find.byType(TvRoomCard));
      await focusTab(tester, 'offline');
      await tester.sendKeyEvent(LogicalKeyboardKey.select);
      await tester.pump(const Duration(seconds: 1));
      await waitForFavorite(tester, find.byType(TvRoomRow));
      await tester.sendKeyEvent(LogicalKeyboardKey.arrowDown);
      await tester.pump(const Duration(seconds: 1));
      expect(FocusManager.instance.primaryFocus?.context?.findAncestorWidgetOfExactType<TvRoomRow>(), isNotNull);
      await pageBack(tester);
      expect(_focused, 'tab offline');
      expect(find.byType(TvRoomRow), findsOneWidget);
      await pageBack(tester);
      expect(_focused, 'tv menu favorites');
      await tester.sendKeyEvent(LogicalKeyboardKey.arrowDown);
      await tester.pump(const Duration(seconds: 1));
      await tester.sendKeyEvent(LogicalKeyboardKey.select);
      await tester.pump(const Duration(seconds: 1));
      await waitForFavorite(tester, find.byType(TvRoomCard));
      await tester.sendKeyEvent(LogicalKeyboardKey.arrowDown);
      await tester.pump(const Duration(seconds: 1));
      await pageBack(tester);
      expect(_focused, 'tv menu popular', reason: 'the favorites handler must stay local to favorites');
    } finally {
      await _close(tester, services);
    }
  });

  testWidgets('issue #35: empty states return to the state filter when the platform row is absent', (tester) async {
    for (final follows in <List<int>>[
      [],
      [2],
    ]) {
      final services = await _pumpApp(tester, follows: follows, offline: {2});
      try {
        await waitForFavorite(tester, find.byType(TvStatusView));
        expect(find.byKey(const ValueKey('tv-follow-divider')), findsNothing);
        final status = find.byType(TvStatusView);
        final action = find.descendant(of: status, matching: find.byType(TvButton));
        expect(action, findsOneWidget);
        final text = find.descendant(of: action, matching: find.byType(Text)).first;
        Focus.of(tester.element(text)).requestFocus();
        await tester.pump(const Duration(seconds: 1));
        expect(_focused, isNot('tv menu favorites'));
        await pageBack(tester);
        expect(_focused, 'tab live');
        await pageBack(tester);
        expect(_focused, 'tv menu favorites');
        await pageBack(tester);
        expect(find.text('退出纯粹直播？'), findsOneWidget);
        await pageBack(tester);
        expect(find.text('退出纯粹直播？'), findsNothing);
      } finally {
        await _close(tester, services);
      }
    }
  });

  testWidgets('issue #35: tag and card Back restore the platform header while keeping the tag', (tester) async {
    final other = LiveRoom(
      platform: SiteIds.douyu,
      roomId: '35',
      title: '另一路',
      nick: '测试主播',
      liveStatus: LiveStatus.live,
    );
    final services = await _pumpApp(
      tester,
      follows: [1],
      extraSites: [
        _ExtraTvSite(SiteIds.douyu, [other]),
      ],
      extraFollows: [other],
      taggedFollows: true,
    );
    try {
      await waitForFavorite(tester, find.byType(TvRoomCard));
      final tags = (await tester.runAsync(services.store.tags.all))!;
      final tag = tags.single;
      await focusTab(tester, SiteIds.douyu);
      await tester.sendKeyEvent(LogicalKeyboardKey.arrowDown);
      await tester.pump(const Duration(seconds: 1));
      await focusTab(tester, tag.id);
      await tester.sendKeyEvent(LogicalKeyboardKey.select);
      await tester.pump(const Duration(seconds: 1));
      await tester.sendKeyEvent(LogicalKeyboardKey.arrowDown);
      await tester.pump(const Duration(seconds: 1));
      expect(_focused, startsWith('cell'));
      final tagBars = find.byWidgetPredicate(
        (widget) => widget is TvTabBar && widget.tabs.any((value) => value.id == tag.id),
      );
      TvTabBar tagBar() => tester.widget<TvTabBar>(tagBars);
      await pageBack(tester);
      expect(_focused, 'tab douyu');
      expect(tagBar().tabs[tagBar().selected].id, tag.id);
      await focusTab(tester, tag.id);
      await pageBack(tester);
      expect(_focused, 'tab douyu', reason: 'Back from the tag row also goes to the parent filter');
      expect(tagBar().tabs[tagBar().selected].id, tag.id);
      await pageBack(tester);
      expect(_focused, 'tv menu favorites');
    } finally {
      await _close(tester, services);
    }
    expect(RoomBackChannel.instance.held, isFalse);
  });

  testWidgets('issue #23: the TV remote opens active super chats and scroll keys never change channel', (tester) async {
    final services = await _pumpApp(tester);
    await _press(tester, LogicalKeyboardKey.arrowDown);
    await _press(tester, LogicalKeyboardKey.select);
    await _press(tester, LogicalKeyboardKey.arrowDown);
    await _press(tester, LogicalKeyboardKey.arrowRight);
    await _press(tester, LogicalKeyboardKey.select);
    await _settle(tester);
    final room = tester.state<TvLivePlayPageState>(find.byType(TvLivePlayPage));
    final session = room.controller!.session;
    final now = DateTime.now();
    (room.controller!.danmaku as FakeDanmaku).emit(
      DanmakuReceived(
        LiveMessage(
          type: LiveMessageType.superChat,
          userName: '观众',
          message: '电视也能查看',
          color: LiveMessageColor.white,
          data: LiveSuperChatMessage(
            userName: '观众',
            face: '',
            message: '电视也能查看',
            price: 30,
            startTime: now,
            endTime: now.add(const Duration(minutes: 5)),
            backgroundColor: '#EDF5FF',
            backgroundBottomColor: '#2A60B2',
          ),
        ),
      ),
    );
    await _settle(tester);
    await _press(tester, LogicalKeyboardKey.select);
    final entry = find.byKey(const ValueKey('tv-room-super-chat'));
    expect(entry, findsOneWidget);
    await _press(tester, LogicalKeyboardKey.arrowRight);
    await _press(tester, LogicalKeyboardKey.arrowRight);
    final focused = FocusManager.instance.primaryFocus?.context?.findAncestorWidgetOfExactType<TvButton>();
    expect(focused?.key, const ValueKey('tv-room-super-chat'));
    await _press(tester, LogicalKeyboardKey.select);
    await _settle(tester);
    expect(find.byKey(const ValueKey('panel-super-chats')), findsOneWidget);
    expect(find.text('电视也能查看'), findsOneWidget);
    await captureQaFrame(tester, 'tv-super-chat-panel');
    for (final size in [const Size(3840, 2160), const Size(1280, 720)]) {
      tester.view.physicalSize = size;
      await tester.pump(const Duration(seconds: 1));
      final heading = tester.renderObject<RenderParagraph>(find.byKey(const ValueKey('room-panel-title')));
      expect(
        heading.getMinIntrinsicHeight(heading.size.width),
        lessThanOrEqualTo(heading.size.height + 0.1),
        reason: 'the title must fit inside the panel header at $size',
      );
      await captureQaFrame(tester, size.width == 3840 ? 'tv-super-chat-4k' : 'tv-super-chat-720p');
    }
    final index = room.index;
    await _press(tester, LogicalKeyboardKey.arrowDown);
    expect(room.index, index);
    expect(room.controller!.session, same(session));
    await _press(tester, LogicalKeyboardKey.arrowUp);
    expect(_focused, 'tv super chat history');
    await _press(tester, LogicalKeyboardKey.select);
    expect(find.text('隐藏历史'), findsOneWidget);
    await _press(tester, LogicalKeyboardKey.arrowDown);
    expect(room.index, index);
    await _press(tester, LogicalKeyboardKey.arrowUp);
    await _press(tester, LogicalKeyboardKey.select);
    expect(find.text('显示历史'), findsOneWidget);
    await tester.binding.handlePopRoute();
    await _settle(tester);
    expect(find.byKey(const ValueKey('panel-super-chats')), findsNothing);
    expect(find.byType(TvLivePlayPage), findsOneWidget);
    await _close(tester, services);
  });

  setUp(_toasts.clear);

  test('interface mode: auto follows the device, phone and tv are fixed; rules of the grid', () {
    expect(UiMode.parse('tv'), UiMode.tv);
    expect(UiMode.parse('watch'), UiMode.auto);
    expect(UiMode.auto.showsTv(television: true), isTrue);
    expect(UiMode.auto.showsTv(television: false), isFalse);
    expect(UiMode.phone.showsTv(television: true), isFalse);
    expect(UiMode.tv.showsTv(television: false), isTrue);
    // pure_live_TV: four columns, one fewer up to 130 %, two fewer above.
    expect([1.0, 1.15, 1.3, 1.45, 1.6].map(tvRoomColumns), [4, 3, 3, 2, 2]);
    // A card is its 16:9 cover over two lines (U.15a): at 184 wide on a
    // 1080p television (unit 0.5) the cover is 103.5 high.
    const scale = TvScale(unit: 0.5, textScale: 1);
    expect(TvRoomCard.heightFor(184, scale), closeTo(184 * 9 / 16 + 16 + 42 + 1, 0.01));
    // The settings page has the row.
    expect(settingsCatalog.where((entry) => entry.id == 'ui_mode'), hasLength(1));
  });

  testWidgets('auto shows the TV interface on a television; switching the setting rebuilds at once', (tester) async {
    final services = await _pumpApp(tester, mode: 'auto', television: true);
    expect(find.byType(TvHomePage), findsOneWidget);
    expect(find.byType(HomePage), findsNothing);
    expect(MediaQuery.of(tester.element(find.byType(TvHomePage))).navigationMode, NavigationMode.directional);

    await tester.runAsync(() => services.store.settings.set(Settings.uiMode, 'phone'));
    await _settle(tester);
    expect(find.byType(HomePage), findsOneWidget);
    expect(find.byType(TvHomePage), findsNothing);

    await tester.runAsync(() => services.store.settings.set(Settings.uiMode, 'tv'));
    await _settle(tester);
    expect(find.byType(TvHomePage), findsOneWidget);
    await _close(tester, services);
  });

  testWidgets('home: the menu, OK into a destination, the grid by index, Left back to the menu', (tester) async {
    final services = await _pumpApp(tester);
    expect(_focused, 'tv menu favorites');
    expect(find.text('无关注直播'), findsOneWidget);
    expect(find.text('搜索直播'), findsOneWidget, reason: 'A17.3 c4');

    await _press(tester, LogicalKeyboardKey.arrowDown);
    expect(_focused, 'tv menu popular');
    await _press(tester, LogicalKeyboardKey.select);
    // OK opened the destination and moved into it (the platform tab).
    expect(_focused, 'tab bilibili');
    expect(find.text('直播 0'), findsOneWidget);

    await _press(tester, LogicalKeyboardKey.arrowDown);
    expect(_focused, 'cell 0');
    await _press(tester, LogicalKeyboardKey.arrowRight);
    expect(_focused, 'cell 1');
    await _press(tester, LogicalKeyboardKey.arrowDown);
    expect(_focused, 'cell 5');
    await _press(tester, LogicalKeyboardKey.arrowDown);
    // The last row ends at room 9.
    expect(_focused, 'cell 9');
    await _press(tester, LogicalKeyboardKey.arrowUp);
    await _press(tester, LogicalKeyboardKey.arrowUp);
    expect(_focused, 'cell 1');
    await _press(tester, LogicalKeyboardKey.arrowUp);
    expect(_focused, 'tab bilibili');
    await _press(tester, LogicalKeyboardKey.arrowDown);
    expect(_focused, 'cell 1', reason: 'back into the grid on the card left last');
    await _press(tester, LogicalKeyboardKey.arrowLeft);
    await _press(tester, LogicalKeyboardKey.arrowLeft);
    expect(_focused, 'tv menu popular');
    await _press(tester, LogicalKeyboardKey.arrowRight);
    expect(_focused, 'cell 0', reason: 'Right enters the destination on its last item');
    // A17.2 c2: in the page the menu is a rail of icons, no scrim.
    final rail = tester.getSize(find.byKey(const ValueKey('tv-home-menu'))).width;
    expect(find.byKey(const ValueKey('tv-home-menu-scrim')), findsNothing);
    expect(find.descendant(of: find.byKey(const ValueKey('tv-home-menu')), matching: find.text('热门')), findsNothing);

    // Back steps out: the destination, then the menu (opened over the
    // dimmed page, with the names), then the exit question (A17.2 c8).
    await tester.binding.handlePopRoute();
    await _settle(tester);
    expect(_focused, 'tv menu popular');
    expect(tester.getSize(find.byKey(const ValueKey('tv-home-menu'))).width, greaterThan(rail * 2));
    expect(find.byKey(const ValueKey('tv-home-menu-scrim')), findsOneWidget);
    expect(find.descendant(of: find.byKey(const ValueKey('tv-home-menu')), matching: find.text('热门')), findsOneWidget);
    await tester.binding.handlePopRoute();
    await _settle(tester);
    expect(find.text('退出纯粹直播？'), findsOneWidget);
    expect(_focused, isNot(startsWith('tv menu')), reason: 'the main button "退出" has the focus');
    // Back is cancel: the home stays, the focus is back on the menu.
    await tester.binding.handlePopRoute();
    await _settle(tester);
    await tester.pump(const Duration(milliseconds: 400));
    expect(find.text('退出纯粹直播？'), findsNothing);
    expect(find.byType(TvHomePage), findsOneWidget);
    expect(_focused, 'tv menu popular');

    // "导航栏始终展开": the menu keeps its names beside the page.
    await tester.runAsync(() => services.store.settings.set(Settings.tvMenuAlwaysExpanded, true));
    await _settle(tester);
    await _press(tester, LogicalKeyboardKey.arrowRight);
    expect(_focused, startsWith('cell'));
    expect(find.descendant(of: find.byKey(const ValueKey('tv-home-menu')), matching: find.text('热门')), findsOneWidget);
    expect(find.byKey(const ValueKey('tv-home-menu-scrim')), findsNothing);
    await _close(tester, services);
  });

  testWidgets('A17.5 c12: 链接放映 sits between 关注分区 and 搜索; its field types with the remote', (tester) async {
    final services = await _pumpApp(tester);
    for (var i = 0; i < 4; i++) {
      await _press(tester, LogicalKeyboardKey.arrowDown);
    }
    expect(_focused, 'tv menu link');
    await _press(tester, LogicalKeyboardKey.select);
    await _settle(tester);
    expect(find.byKey(const ValueKey('tv-link-field')), findsOneWidget);
    expect(find.text('支持各平台的直播间链接、短链接和纯粹直播的分享口令，按 OK 用遥控器输入'), findsOneWidget);
    // Nothing typed: "播放" waits.
    expect(tester.widget<TvButton>(find.byKey(const ValueKey('tv-link-play'))).onTap, isNull);
    await _close(tester, services);
  });

  testWidgets("A17.2 c8: Android's Back (the native channel) asks before leaving; over a page it pops the page", (
    tester,
  ) async {
    final services = await _pumpApp(tester);
    addTearDown(RoomBackChannel.instance.reset);
    // Not awaited: the handler waits while the exit question is open.
    Future<void> nativeBack() async {
      unawaited(
        tester.binding.defaultBinaryMessenger.handlePlatformMessage(
          'pure_live/predictive_back',
          const StandardMethodCodec().encodeMethodCall(const MethodCall('backInvoked')),
          (_) {},
        ),
      );
      await _settle(tester);
      await tester.pump(const Duration(milliseconds: 400));
    }

    expect(RoomBackChannel.instance.held, isTrue, reason: 'the home takes Back from Android');
    await nativeBack();
    expect(find.text('退出纯粹直播？'), findsOneWidget);
    // Over the dialog, Back closes it.
    await nativeBack();
    expect(find.text('退出纯粹直播？'), findsNothing);
    expect(find.byType(TvHomePage), findsOneWidget);
    await _close(tester, services);
  });

  testWidgets('A17.2 c10: the first start shows the notice once; agreeing opens the home', (tester) async {
    final services = await _pumpApp(tester, noticeAccepted: false);
    expect(find.byKey(const ValueKey('tv-notice')), findsOneWidget);
    expect(find.text('已阅读并同意'), findsOneWidget);
    // Down scrolls the words; the focus stays on the buttons.
    await _press(tester, LogicalKeyboardKey.arrowDown);
    expect(find.byKey(const ValueKey('tv-notice')), findsOneWidget);
    await _press(tester, LogicalKeyboardKey.select);
    await _settle(tester);
    await tester.pump(const Duration(milliseconds: 400));
    expect(find.byKey(const ValueKey('tv-notice')), findsNothing);
    expect(_focused, 'tv menu favorites');
    expect(await tester.runAsync(() => services.store.meta.get(TvHomePage.noticeKey)), '1');
    await _close(tester, services);
  });

  testWidgets('issue #14 room: touch and remote show controls; switching and Back keep working', (tester) async {
    final services = await _pumpApp(tester);
    await _press(tester, LogicalKeyboardKey.arrowDown);
    await _press(tester, LogicalKeyboardKey.select);
    await _press(tester, LogicalKeyboardKey.arrowDown);
    await _press(tester, LogicalKeyboardKey.arrowRight);
    expect(_focused, 'cell 1');

    await _press(tester, LogicalKeyboardKey.select);
    await _settle(tester);
    final room = tester.state<TvLivePlayPageState>(find.byType(TvLivePlayPage));
    expect(room.index, 1);
    expect(room.playlist, hasLength(10));
    expect(room.controller!.room.roomId, '1');
    // D05.2: the picture's danmaku follow "同屏最大弹幕条数" (48 by default).
    expect(tester.widget<DanmakuOverlay>(find.byType(DanmakuOverlay)).maxVisible, 48);
    await tester.runAsync(() => services.store.settings.set(Settings.danmakuMaxVisibleCount, 30));
    await _settle(tester);
    expect(tester.widget<DanmakuOverlay>(find.byType(DanmakuOverlay)).maxVisible, 30);

    // Two presses inside the window: one switch of two rooms.
    await tester.sendKeyEvent(LogicalKeyboardKey.arrowDown);
    await tester.sendKeyEvent(LogicalKeyboardKey.arrowDown);
    await tester.pump(const Duration(seconds: 1));
    await _settle(tester);
    expect(room.index, 3);
    expect(room.controller!.room.roomId, '3');
    expect(find.byKey(const ValueKey('tv-room-banner')), findsOneWidget);
    await _press(tester, LogicalKeyboardKey.arrowUp);
    await tester.pump(const Duration(seconds: 1));
    await _settle(tester, rounds: 10);
    expect(room.index, 2);
    expect(room.controller!.stage, RoomStage.playing);
    // History records the rooms shown.
    final history = (await tester.runAsync(services.store.history.all))!;
    expect(history.map((room) => room.roomId), containsAll(['1', '2', '3']));

    // OK: the controls, focus on the first button; Back hides them.
    await _press(tester, LogicalKeyboardKey.select);
    expect(find.byKey(const ValueKey('tv-room-controls')), findsOneWidget);
    expect(find.text('画质 原画'), findsOneWidget);
    expect(_focused, 'tv room first control');
    // Left and Right walk the buttons; Up/Down still switch rooms.
    await _press(tester, LogicalKeyboardKey.arrowRight);
    expect(FocusManager.instance.primaryFocus?.context?.widget, isNot(isA<TvLivePlayPage>()));
    await tester.binding.handlePopRoute();
    await _settle(tester);
    expect(find.byKey(const ValueKey('tv-room-controls')), findsNothing);

    // Issue #14: touching the picture can open and close the controls.
    await tester.tapAt(const Offset(960, 400));
    await _settle(tester);
    expect(find.byKey(const ValueKey('tv-room-controls')), findsOneWidget);
    await tester.tapAt(const Offset(960, 400));
    await _settle(tester);
    expect(find.byKey(const ValueKey('tv-room-controls')), findsNothing);

    // A17.4 c3, c7: Right opens the play settings on the right: the
    // phone's danmaku settings, the block list and recording; Back closes.
    await _press(tester, LogicalKeyboardKey.arrowRight);
    await _settle(tester);
    expect(find.byKey(const ValueKey('tv-room-settings')), findsOneWidget);
    expect(find.text('播放设置'), findsOneWidget);
    expect(tester.getTopRight(find.byKey(const ValueKey('tv-room-settings'))).dx, 1920);
    expect(tester.getTopLeft(find.byKey(const ValueKey('tv-room-settings'))).dx, greaterThan(960));
    expect(find.byKey(const ValueKey('tv-room-settings-danmaku')), findsOneWidget);
    expect(_focused, isNot('tv room keys'), reason: 'the focus is in the panel');
    await tester.binding.handlePopRoute();
    await _settle(tester);
    expect(find.byKey(const ValueKey('tv-room-settings')), findsNothing);

    // Left: the room list on the left with the room shown; OK on another
    // switches.
    await _press(tester, LogicalKeyboardKey.arrowLeft);
    expect(find.byKey(const ValueKey('tv-room-panel')), findsOneWidget);
    expect(tester.getTopLeft(find.byKey(const ValueKey('tv-room-panel'))).dx, 0);
    expect(_focused, 'tv room list current');
    await _press(tester, LogicalKeyboardKey.arrowDown);
    await _press(tester, LogicalKeyboardKey.select);
    await _settle(tester);
    expect(room.index, 3);
    expect(find.byKey(const ValueKey('tv-room-panel')), findsNothing);

    // Back leaves; the grid's focus lands on the room shown last.
    await tester.binding.handlePopRoute();
    await _settle(tester);
    await tester.pump(const Duration(seconds: 1));
    await _settle(tester);
    expect(find.byType(TvLivePlayPage), findsNothing);
    expect(_focused, 'cell 3');
    await _close(tester, services);
  });

  testWidgets('a held OK opens the card dialog instead of the room; the menu key too', (tester) async {
    final services = await _pumpApp(tester);
    await _press(tester, LogicalKeyboardKey.arrowDown);
    await _press(tester, LogicalKeyboardKey.select);
    await _press(tester, LogicalKeyboardKey.arrowDown);
    expect(_focused, 'cell 0');

    await tester.sendKeyDownEvent(LogicalKeyboardKey.select);
    await tester.pump(const Duration(seconds: 1));
    await tester.sendKeyUpEvent(LogicalKeyboardKey.select);
    await _settle(tester);
    expect(find.byKey(const ValueKey('tv-room-dialog')), findsOneWidget);
    expect(find.byType(TvLivePlayPage), findsNothing);
    // The dialog took the focus (no arrow needed): "设置标签" (U.15a c9).
    expect(FocusManager.instance.primaryFocus?.context?.findAncestorWidgetOfExactType<Dialog>(), isNotNull);
    expect(
      FocusManager.instance.primaryFocus?.context?.findAncestorWidgetOfExactType<TvButton>()?.key,
      const ValueKey('tv-room-dialog-tags'),
    );

    await _press(tester, LogicalKeyboardKey.escape);
    await _settle(tester);
    expect(find.byKey(const ValueKey('tv-room-dialog')), findsNothing);
    expect(_focused, 'cell 0');

    // The remote's menu key is the same as a held OK (U.15a c10).
    await _press(tester, LogicalKeyboardKey.contextMenu);
    await _settle(tester);
    expect(find.byKey(const ValueKey('tv-room-dialog')), findsOneWidget);
    await tester.binding.handlePopRoute();
    await _settle(tester);
    expect(_focused, 'cell 0');
    await _close(tester, services);
  });

  testWidgets('search: OK on the field types through the input, results in a grid, Back to the history', (
    tester,
  ) async {
    final asked = <String>[];
    TvTextInput.prompt =
        (context, {required title, hint = '', text = '', subtitle, numeric = false, suffix, maxLength}) async {
          asked.add(title);
          return ' 直播 7 ';
        };
    addTearDown(() => TvTextInput.prompt = TvTextInput.defaultPrompt);
    final services = await _pumpApp(tester);
    for (var i = 0; i < 5; i++) {
      await _press(tester, LogicalKeyboardKey.arrowDown);
    }
    expect(_focused, 'tv menu search');
    await _press(tester, LogicalKeyboardKey.select);
    expect(find.text('按 OK 打开输入框，用遥控器或语音输入要找的内容'), findsOneWidget);
    expect(_focused, 'tv search field');

    await _press(tester, LogicalKeyboardKey.select);
    await _settle(tester, rounds: 6);
    expect(asked, ['搜索直播间、主播或房间号']);
    expect(find.text('直播 7'), findsWidgets);
    expect(find.text('主播7'), findsOneWidget);

    // Back: from the results to the field, the word kept in the history.
    await tester.binding.handlePopRoute();
    await _settle(tester);
    expect(find.byKey(const ValueKey('tv-search-word-直播 7')), findsOneWidget);
    expect(find.byType(TvHomePage), findsOneWidget);
    await _close(tester, services);
  });

  testWidgets('A17.3 c11, c12: one search page — filters, streamers as rows, up to the platforms, clear asks first', (
    tester,
  ) async {
    TvTextInput.prompt = (
      context, {
      required title,
      hint = '',
      text = '',
      subtitle,
      numeric = false,
      suffix,
      maxLength,
    }) async => '直播 7';
    addTearDown(() => TvTextInput.prompt = TvTextInput.defaultPrompt);
    final services = await _pumpApp(tester);
    for (var i = 0; i < 5; i++) {
      await _press(tester, LogicalKeyboardKey.arrowDown);
    }
    await _press(tester, LogicalKeyboardKey.select);
    expect(_focused, 'tv search field');
    // The filters are on the page before a search.
    for (final key in [
      'tv-search-mode-rooms',
      'tv-search-mode-anchors',
      'tv-search-offline',
      'tv-search-sort',
      'tv-search-phone',
    ]) {
      expect(find.byKey(ValueKey(key)), findsOneWidget, reason: key);
    }
    expect(find.byKey(const ValueKey('tv-search-scope')), findsOneWidget);

    await _press(tester, LogicalKeyboardKey.select);
    await _settle(tester, rounds: 6);
    expect(find.byType(TvRoomCard), findsWidgets);
    // OK searched: the focus is on the first result.
    expect(_focused, 'cell 0');

    // "主播": the same words again; rows, not blown-up avatars; no order.
    await tester.tap(find.byKey(const ValueKey('tv-search-mode-anchors')));
    await _settle(tester, rounds: 6);
    expect(find.byType(TvRoomRow), findsOneWidget);
    expect(find.byType(TvRoomCard), findsNothing);
    expect(find.text('主播7'), findsOneWidget);
    expect(find.textContaining('正在直播'), findsOneWidget);
    expect(find.byKey(const ValueKey('tv-search-sort')), findsNothing);
    // Up from the results goes back to the platforms.
    await _press(tester, LogicalKeyboardKey.arrowDown);
    await _press(tester, LogicalKeyboardKey.arrowDown);
    await _press(tester, LogicalKeyboardKey.arrowDown);
    await _press(tester, LogicalKeyboardKey.arrowDown);
    expect(FocusManager.instance.primaryFocus?.context?.findAncestorWidgetOfExactType<TvRoomRow>(), isNotNull);
    await _press(tester, LogicalKeyboardKey.arrowUp);
    expect(_focused, 'tab all');

    // Back to the recent words; "清空" asks with the focus on cancel.
    await tester.binding.handlePopRoute();
    await _settle(tester);
    await tester.tap(find.byKey(const ValueKey('tv-search-clear')));
    await _settle(tester);
    expect(find.text('清空最近搜索'), findsOneWidget);
    expect(
      FocusManager.instance.primaryFocus?.context?.findAncestorWidgetOfExactType<TvButton>()?.key,
      const ValueKey('tv-confirm-no'),
    );
    await _press(tester, LogicalKeyboardKey.select);
    await _settle(tester);
    expect(find.byKey(const ValueKey('tv-search-word-直播 7')), findsOneWidget);
    await _close(tester, services);
  });

  testWidgets('follows off air: ← from the first column of rows goes to the rail', (tester) async {
    final services = await _pumpApp(tester, follows: [1, 2, 3], offline: {2, 3});
    expect(_focused, 'tv menu favorites');
    await _press(tester, LogicalKeyboardKey.arrowRight);
    // Up to the states, across to "未开播", OK, down into the rows.
    await _press(tester, LogicalKeyboardKey.arrowUp);
    await _press(tester, LogicalKeyboardKey.arrowRight);
    await _press(tester, LogicalKeyboardKey.arrowRight);
    await _press(tester, LogicalKeyboardKey.select);
    await _settle(tester);
    await _press(tester, LogicalKeyboardKey.arrowDown);
    expect(FocusManager.instance.primaryFocus?.context?.findAncestorWidgetOfExactType<TvRoomRow>(), isNotNull);
    await _press(tester, LogicalKeyboardKey.arrowLeft);
    expect(_focused, 'tv menu favorites');
    await _close(tester, services);
  });

  testWidgets('rail: up and down follow the rail, not the page rows under the opened rail', (tester) async {
    final services = await _pumpApp(tester);
    for (var i = 0; i < TvPane.menu.length; i++) {
      await _press(tester, LogicalKeyboardKey.arrowDown);
    }
    expect(_focused, 'tv menu settings');
    await _press(tester, LogicalKeyboardKey.select);
    expect(find.byKey(const ValueKey('tv-setting-ui_mode')), findsOneWidget);
    // Down into the page, then back to the rail's 设置 and up along it.
    await _press(tester, LogicalKeyboardKey.arrowDown);
    await _press(tester, LogicalKeyboardKey.arrowDown);
    await _press(tester, LogicalKeyboardKey.arrowLeft);
    expect(_focused, 'tv menu settings');
    final menu = TvPane.menuOf().where((pane) => pane != TvPane.settings).toList();
    await _press(tester, LogicalKeyboardKey.arrowUp);
    expect(_focused, 'tv menu ${menu.last.name}');
    await _press(tester, LogicalKeyboardKey.arrowUp);
    expect(_focused, 'tv menu ${menu[menu.length - 2].name}');
    await _press(tester, LogicalKeyboardKey.arrowDown);
    await _press(tester, LogicalKeyboardKey.arrowDown);
    expect(_focused, 'tv menu settings');
    // The top of the rail is the mode button.
    for (var i = 0; i < menu.length + 2; i++) {
      await _press(tester, LogicalKeyboardKey.arrowUp);
    }
    expect(_focused, 'tv menu mode');
    await _close(tester, services);
  });

  testWidgets('TV settings: OK opens the choices on the current value; picking phone switches', (tester) async {
    final services = await _pumpApp(tester);
    for (var i = 0; i < TvPane.menu.length; i++) {
      await _press(tester, LogicalKeyboardKey.arrowDown);
    }
    expect(_focused, 'tv menu settings');
    await _press(tester, LogicalKeyboardKey.select);
    expect(find.byKey(const ValueKey('tv-setting-ui_mode')), findsOneWidget);
    // The first row has the focus; OK opens the choices with the focus on
    // the current one (tv), Up moves to phone, OK picks it (U.15a row 13).
    await _press(tester, LogicalKeyboardKey.select);
    expect(find.byKey(const ValueKey('tv-option-current')), findsOneWidget);
    expect(
      FocusManager.instance.primaryFocus?.context?.findAncestorWidgetOfExactType<TvOptionRow>()?.key,
      const ValueKey('tv-choice-2'),
    );
    await _press(tester, LogicalKeyboardKey.arrowUp);
    await _press(tester, LogicalKeyboardKey.select);
    await _settle(tester);
    expect(services.store.settings.get(Settings.uiMode), 'phone');
    expect(find.byType(HomePage), findsOneWidget);
    await _close(tester, services);
  });

  testWidgets('A17.9: the TV settings are the phone\'s overview after the TV rows, "关于" last', (tester) async {
    final services = await _pumpApp(tester);
    for (var i = 0; i < TvPane.menu.length; i++) {
      await _press(tester, LogicalKeyboardKey.arrowDown);
    }
    await _press(tester, LogicalKeyboardKey.select);
    String? row() =>
        (FocusManager.instance.primaryFocus?.context?.findAncestorWidgetOfExactType<TvFocusable>()?.key
                as ValueKey<String>?)
            ?.value
            .substring('tv-setting-'.length);
    final rows = [row()];
    var navigationWords = false;
    while (true) {
      await _press(tester, LogicalKeyboardKey.arrowDown);
      if (row() == rows.last) break;
      rows.add(row());
      // "导航栏" manages the TV's side rail, and says so.
      if (row() == 'section-navigation') navigationWords = find.text('左边导航栏显示哪些入口、顺序和图标').evaluate().isNotEmpty;
    }
    expect(navigationWords, isTrue);
    expect(rows, [
      'ui_mode',
      'focus_zoom',
      'wallpaper',
      'menu_expanded',
      for (final area in SettingsArea.values)
        for (final section in SettingsSection.values)
          if (section.area == area && section != SettingsSection.pipDanmaku) 'section-${section.name}',
      'about',
    ]);
    await _close(tester, services);
  });

  testWidgets("A17.9: a settings page is the phone's rows in the TV look; ← off, → on; Back to its row", (
    tester,
  ) async {
    final services = await _pumpApp(tester);
    addTearDown(RoomBackChannel.instance.reset);
    final settings = services.store.settings;
    // Android's Back, as the device sends it (the TV home holds it).
    Future<void> nativeBack() async {
      unawaited(
        tester.binding.defaultBinaryMessenger.handlePlatformMessage(
          'pure_live/predictive_back',
          const StandardMethodCodec().encodeMethodCall(const MethodCall('backInvoked')),
          (_) {},
        ),
      );
      await _settle(tester, rounds: 6);
      await tester.pump(const Duration(milliseconds: 400));
    }

    for (var i = 0; i < TvPane.menu.length; i++) {
      await _press(tester, LogicalKeyboardKey.arrowDown);
    }
    await _press(tester, LogicalKeyboardKey.select);
    // ui_mode, focus_zoom, wallpaper, menu_expanded, appearance, navigation, platforms, refresh.
    for (var i = 0; i < 7; i++) {
      await _press(tester, LogicalKeyboardKey.arrowDown);
    }
    expect(
      FocusManager.instance.primaryFocus?.context?.findAncestorWidgetOfExactType<TvFocusable>()?.key,
      const ValueKey('tv-setting-section-refresh'),
    );
    await _press(tester, LogicalKeyboardKey.select);
    await _settle(tester, rounds: 6);
    expect(find.byKey(const ValueKey('tv-settings-page-refresh')), findsOneWidget);
    expect(find.text('刷新设置'), findsWidgets);
    // The first row ("开启关注自动刷新") has the focus, in the TV look.
    final focused = FocusManager.instance.primaryFocus?.context;
    expect(focused?.findAncestorWidgetOfExactType<SettingsSwitchRow>()?.title, '开启关注自动刷新');
    expect(SettingsRowStyle.tvOf(focused!), isTrue);
    expect(settings.get(Settings.autoRefreshFavorite), isFalse);
    await _press(tester, LogicalKeyboardKey.arrowRight);
    expect(settings.get(Settings.autoRefreshFavorite), isTrue);
    await _press(tester, LogicalKeyboardKey.arrowRight);
    expect(settings.get(Settings.autoRefreshFavorite), isTrue, reason: 'already on: stays');
    await _press(tester, LogicalKeyboardKey.arrowLeft);
    expect(settings.get(Settings.autoRefreshFavorite), isFalse);
    expect(find.byKey(const ValueKey('tv-settings-page-refresh')), findsOneWidget, reason: 'the focus stayed');

    // The interval (on again) opens the TV's choices on the current value.
    await _press(tester, LogicalKeyboardKey.arrowRight);
    await _press(tester, LogicalKeyboardKey.arrowDown);
    await _press(tester, LogicalKeyboardKey.select);
    await _settle(tester);
    expect(find.byType(TvOptionRow), findsWidgets);
    expect(find.byKey(const ValueKey('tv-option-current')), findsOneWidget);
    await nativeBack();
    expect(find.byType(TvOptionRow), findsNothing);
    expect(find.byKey(const ValueKey('tv-settings-page-refresh')), findsOneWidget);

    await nativeBack();
    expect(find.byKey(const ValueKey('tv-settings-page-refresh')), findsNothing);
    expect(
      FocusManager.instance.primaryFocus?.context?.findAncestorWidgetOfExactType<TvFocusable>()?.key,
      const ValueKey('tv-setting-section-refresh'),
      reason: 'back on the row that opened it',
    );
    await _close(tester, services);
  });

  testWidgets('A17.9 c14: a web address on the TV shows its code for a phone instead of a browser', (tester) async {
    final services = await _pumpApp(tester);
    final opened = AppNavigator.openExternal(Uri.parse('https://mpv.io/manual/stable/'));
    await _settle(tester);
    expect(find.byKey(const ValueKey('tv-link-dialog')), findsOneWidget);
    expect(find.text('https://mpv.io/manual/stable/'), findsOneWidget);
    await _press(tester, LogicalKeyboardKey.select);
    await _settle(tester);
    expect(find.byKey(const ValueKey('tv-link-dialog')), findsNothing);
    expect(await opened, isTrue);
    await _close(tester, services);
  });

  testWidgets('A17.6 X1: the mode button switches to videos: 搜索、我的、首页、分区、影视, behind the login', (tester) async {
    final services = await _pumpApp(tester);
    expect(_focused, 'tv menu favorites');
    await _press(tester, LogicalKeyboardKey.arrowUp);
    expect(_focused, 'tv menu mode');
    expect(find.text('直播'), findsOneWidget);
    await _press(tester, LogicalKeyboardKey.select);
    await _settle(tester);
    expect(find.byType(TvOptionRow), findsNWidgets(3), reason: '直播, 视频, 音乐');
    await _press(tester, LogicalKeyboardKey.arrowDown);
    await _press(tester, LogicalKeyboardKey.select);
    await _settle(tester, rounds: 6);
    expect(services.store.settings.get(Settings.tvMode), 'video');
    final menu = [
      for (final element
          in find
              .byWidgetPredicate(
                (widget) =>
                    widget.key is ValueKey<String> && (widget.key! as ValueKey<String>).value.startsWith('tv-menu-'),
              )
              .evaluate())
        (element.widget.key! as ValueKey<String>).value,
    ];
    expect(menu, [
      'tv-menu-mode',
      'tv-menu-videoSearch',
      'tv-menu-videoMine',
      'tv-menu-videoHome',
      'tv-menu-videoAreas',
      'tv-menu-videoCinema',
      'tv-menu-settings',
    ]);
    expect(_focused, 'tv menu videoSearch');
    expect(find.byKey(const ValueKey('tv-video-login-gate')), findsOneWidget, reason: 'signed out');

    // A17.7: music lands on "我的".
    for (var i = 0; i < 6; i++) {
      if (_focused == 'tv menu mode') break;
      await _press(tester, LogicalKeyboardKey.arrowUp);
    }
    expect(_focused, 'tv menu mode');
    await _press(tester, LogicalKeyboardKey.select);
    await _settle(tester);
    await _press(tester, LogicalKeyboardKey.arrowDown);
    await _press(tester, LogicalKeyboardKey.select);
    await _settle(tester, rounds: 6);
    expect(services.store.settings.get(Settings.tvMode), 'music');
    expect(_focused, 'tv menu musicMine');
    expect(find.byKey(const ValueKey('tv-menu-musicNow')), findsOneWidget);
    await _close(tester, services);
  });

  testWidgets('a focusable: OK taps at once without a long press; with one, a hold never also taps', (tester) async {
    var taps = 0;
    var holds = 0;
    await tester.pumpWidget(
      MaterialApp(
        home: Column(
          children: [
            TvFocusable(autofocus: true, onTap: () => taps++, builder: (_, _) => const Text('plain')),
            TvFocusable(onTap: () => taps++, onLongPress: () => holds++, builder: (_, _) => const Text('card')),
          ],
        ),
      ),
    );
    await tester.pump();
    await tester.sendKeyEvent(LogicalKeyboardKey.select);
    expect(taps, 1);
    await tester.sendKeyEvent(LogicalKeyboardKey.arrowDown);
    await tester.pump();
    await tester.sendKeyEvent(LogicalKeyboardKey.enter);
    expect((taps, holds), (2, 0));
    await tester.sendKeyDownEvent(LogicalKeyboardKey.select);
    await tester.pump(const Duration(seconds: 1));
    await tester.sendKeyRepeatEvent(LogicalKeyboardKey.select);
    await tester.sendKeyUpEvent(LogicalKeyboardKey.select);
    expect((taps, holds), (2, 1));
    // Android's long press is the first repeat (about 400 ms, before the
    // timer): it holds, the release does not tap, and more repeats do nothing.
    await tester.sendKeyDownEvent(LogicalKeyboardKey.select);
    await tester.pump(const Duration(milliseconds: 400));
    await tester.sendKeyRepeatEvent(LogicalKeyboardKey.select);
    await tester.sendKeyRepeatEvent(LogicalKeyboardKey.select);
    await tester.sendKeyUpEvent(LogicalKeyboardKey.select);
    await tester.pump(const Duration(seconds: 1));
    expect((taps, holds), (2, 2));
  });
}
