// A17.8: the TV background — sources, files (blurred once), the layer and
// the preview.
import 'dart:async';
import 'dart:io';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:live_store/live_store.dart';
import 'package:live_ui/live_ui.dart';
import 'package:pure_live/app/services.dart';
import 'package:pure_live/tv/tv_theme.dart';
import 'package:pure_live/tv/wallpaper/tv_wallpaper_layer.dart';
import 'package:pure_live/tv/wallpaper/tv_wallpaper_preview.dart';
import 'package:pure_live/tv/wallpaper/wallpaper_files.dart';
import 'package:pure_live/tv/wallpaper/wallpaper_model.dart';
import 'package:pure_live/tv/wallpaper/wallpaper_sources.dart';

import '../support.dart';

/// A small red PNG, drawn here.
Future<List<int>> _png() async {
  final recorder = ui.PictureRecorder();
  ui.Canvas(recorder).drawRect(const ui.Rect.fromLTWH(0, 0, 8, 8), ui.Paint()..color = const ui.Color(0xFFFF0000));
  final image = await recorder.endRecording().toImage(8, 8);
  final bytes = await image.toByteData(format: ui.ImageByteFormat.png);
  return bytes!.buffer.asUint8List();
}

void main() {
  group('sources', () {
    test('no source of the removed kind is offered (D-032)', () {
      final names = [
        for (final group in tvRandomGroups)
          for (final source in group.sources) '${source.name} ${source.url}',
      ];
      for (final word in ['黑丝', '白丝', '美女', '美囡', '性感', 'heisi', 'baisi', 'meinv', 'sexy']) {
        expect(names.where((name) => name.contains(word)), isEmpty, reason: word);
      }
      expect(tvRandomGroups.map((group) => group.id), isNot(contains('sexy')));
    });

    test("a random answer: the picture's address wherever the JSON puts it; JSON APIs are asked with their key", () {
      expect(randomPictureUrl({'code': 200, 'data': 'https://a/1.jpg'}), 'https://a/1.jpg');
      expect(
        randomPictureUrl({
          'data': [
            {'url': 'https://a/2.jpg'},
          ],
        }),
        'https://a/2.jpg',
      );
      expect(randomPictureUrl({'image_url': 'https://a/3.jpg'}), 'https://a/3.jpg');
      expect(randomPictureUrl({'msg': 'nope'}), isNull);
      final keyed = tvRandomGroups.expand((group) => group.sources).firstWhere((source) => source.apiKey != null);
      final url = randomRequestUrl(keyed);
      expect(url.queryParameters['type'], 'json');
      expect(url.queryParameters['apiKey'], keyed.apiKey);
    });

    test('Wallhaven is asked for safe-for-work pictures only', () {
      for (final category in const WallhavenWallpapers().categories) {
        expect(WallhavenWallpapers.queryOf(category.id, 1)['purity'], '100');
        expect(WallhavenWallpapers.queryOf(category.id, 1)['categories'], isNot(endsWith('1')), reason: 'no people');
      }
    });

    test('the stored background: defaults as pure_live_TV, unknown names fall back', () async {
      final store = await LiveStore.memory(cipher: FakeCipher());
      addTearDown(store.close);
      final wallpaper = TvWallpaper.of(store.settings);
      expect(wallpaper.active, isFalse);
      expect((wallpaper.fit, wallpaper.mask, wallpaper.blur), (BoxFit.cover, 0.35, 0.0));
      expect(tvWallpaperFitOf('nope'), BoxFit.cover);
      expect(TvWallpaperKind.of('nope'), TvWallpaperKind.none);
      expect(tvGradients.first.gradient.colors, tvGradients.first.colors);
    });
  });

  group('files', () {
    late Directory folder;
    late LiveStore live;
    late TvWallpaperStore store;
    setUp(() async {
      folder = Directory.systemTemp.createTempSync('tv_wallpaper');
      live = await LiveStore.memory(cipher: FakeCipher());
      store = TvWallpaperStore(
        settings: live.settings,
        files: TvWallpaperFiles(folder: Future.value(folder), http: NoNetworkHttp()),
      );
    });
    tearDown(() async {
      await live.close();
      folder.deleteSync(recursive: true);
    });

    testWidgets('a picture is blurred once when set; the old files go; clearing removes them', (tester) async {
      await tester.runAsync(() async {
        final picked = File('${folder.path}/scratch-1.png')..writeAsBytesSync(await _png());
        await store.setPicture(Uri.file(picked.path).toString(), fit: BoxFit.contain, mask: 0.6, blur: 4);
        final now = store.current;
        expect(now.kind, TvWallpaperKind.image);
        expect((now.fit, now.mask, now.blur), (BoxFit.contain, 0.6, 4.0));
        expect(now.value, contains('blur-'));
        expect(File(now.value).existsSync(), isTrue);
        expect(store.files.blurs, 1);

        await store.setBlur(4);
        expect(store.files.blurs, 1, reason: 'the same blur is not computed again');
        await store.setBlur(0);
        expect(store.current.value, picked.path, reason: 'no blur: the picture itself');

        await store.setGradient(tvGradients.first.name);
        expect(store.current.kind, TvWallpaperKind.gradient);
        expect(folder.listSync(), isEmpty, reason: 'the picture files went');
        await store.clear();
        expect(store.current.active, isFalse);
      });
    });
  });

  group('screen', () {
    // Lets the store answer (real time) and the frames run.
    Future<void> settle(WidgetTester tester) async {
      for (var i = 0; i < 4; i++) {
        await tester.runAsync(() => Future<void>.delayed(const Duration(milliseconds: 20)));
        await tester.pump(const Duration(milliseconds: 50));
      }
    }

    // Unmounted before the store closes (as tv_test's _close).
    Future<void> close(WidgetTester tester, AppServices services) async {
      await tester.pumpWidget(const SizedBox.shrink());
      await tester.runAsync(() => Future<void>.delayed(const Duration(milliseconds: 20)));
      await tester.pump(const Duration(seconds: 5));
      await tester.runAsync(services.close);
    }

    Future<(AppServices, TvWallpaperStore)> pump(WidgetTester tester, Widget child) async {
      tester.view
        ..physicalSize = const Size(1920, 1080)
        ..devicePixelRatio = 2;
      addTearDown(tester.view.reset);
      final services = (await tester.runAsync(testServices))!;
      await tester.runAsync(loadStrings);
      final folder = Directory.systemTemp.createTempSync('tv_wallpaper');
      addTearDown(() => folder.deleteSync(recursive: true));
      final store = TvWallpaperStore(
        settings: services.store.settings,
        files: TvWallpaperFiles(folder: Future.value(folder), http: NoNetworkHttp()),
      );
      final scheme = ColorScheme.fromSeed(seedColor: LiveTheme.brandBlue, brightness: Brightness.dark);
      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            appServicesProvider.overrideWithValue(services),
            tvWallpaperStoreProvider.overrideWithValue(store),
          ],
          child: MaterialApp(
            theme: ThemeData(colorScheme: scheme),
            home: Builder(
              builder: (context) => MediaQuery(
                data: MediaQuery.of(context).copyWith(navigationMode: NavigationMode.directional),
                child: TvTheme(
                  palette: TvPalette.of(scheme),
                  child: Scaffold(body: child),
                ),
              ),
            ),
          ),
        ),
      );
      await tester.pump();
      return (services, store);
    }

    testWidgets('the layer: nothing without a background, a colour with one', (tester) async {
      final (services, store) = await pump(tester, const TvWallpaperLayer());
      expect(find.byKey(const ValueKey('tv-wallpaper')), findsNothing);
      unawaited(store.setColor('FF2AD39A'));
      await settle(tester);
      expect(find.byKey(const ValueKey('tv-wallpaper')), findsOneWidget);
      final box = tester.widget<ColoredBox>(
        find.descendant(of: find.byKey(const ValueKey('tv-wallpaper')), matching: find.byType(ColoredBox)).first,
      );
      expect(box.color, const Color(0xFF2AD39A));
      expect(services.store.settings.get(Settings.tvWallpaperKind), 'color');
      await close(tester, services);
    });

    testWidgets('the preview: what is tried there is not kept by Back; "设为背景" keeps it with the picture', (
      tester,
    ) async {
      final folder = Directory.systemTemp.createTempSync('tv_preview');
      addTearDown(() => folder.deleteSync(recursive: true));
      final picture = File('${folder.path}/a.png')..writeAsBytesSync((await tester.runAsync(_png))!);
      final items = [TvWallpaperItem(url: Uri.file(picture.path).toString())];
      final (services, store) = await pump(
        tester,
        Builder(
          builder: (context) => TextButton(
            onPressed: () =>
                Navigator.of(context)
                    .push<void>(MaterialPageRoute(builder: (_) => TvWallpaperPreviewPage(items: items, index: 0))),
            child: const Text('打开'),
          ),
        ),
      );
      final settings = services.store.settings;

      Future<void> open() async {
        await tester.tap(find.text('打开'));
        await tester.pump();
        await tester.pump(const Duration(milliseconds: 400));
      }

      Future<void> press(LogicalKeyboardKey key) async {
        await tester.sendKeyEvent(key);
        await tester.pump();
        await tester.pump(const Duration(milliseconds: 400));
      }

      await open();
      expect(find.text('遮罩 · 35%'), findsOneWidget);
      // The veil to 60 % from its button.
      await tester.tap(find.byKey(const ValueKey('tv-wallpaper-mask')));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 400));
      await tester.ensureVisible(find.text('60%'));
      await tester.pump();
      await tester.tap(find.text('60%'));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 400));
      expect(find.text('遮罩 · 60%'), findsOneWidget);
      await tester.binding.handlePopRoute();
      await settle(tester);
      await tester.pump(const Duration(milliseconds: 400));
      expect(find.byKey(const ValueKey('tv-wallpaper-preview')), findsNothing);
      expect(settings.get(Settings.tvWallpaperMask), 0.35, reason: 'Back keeps the background as it was');
      expect(settings.get(Settings.tvWallpaperKind), 'none');

      // Immersive: OK leaves it.
      await open();
      await tester.tap(find.byKey(const ValueKey('tv-wallpaper-immersive-button')));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 400));
      expect(find.byKey(const ValueKey('tv-wallpaper-immersive')), findsOneWidget);
      await press(LogicalKeyboardKey.select);
      expect(find.byKey(const ValueKey('tv-wallpaper-immersive')), findsNothing);

      await tester.tap(find.byKey(const ValueKey('tv-wallpaper-mask')));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 400));
      await tester.ensureVisible(find.text('60%'));
      await tester.pump();
      await tester.tap(find.text('60%'));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 400));
      await tester.tap(find.byKey(const ValueKey('tv-wallpaper-apply')));
      for (var i = 0; i < 4; i++) {
        await settle(tester);
      }
      expect(store.current.kind, TvWallpaperKind.image);
      expect(store.current.mask, 0.6);
      expect(store.current.source, items.first.url);
      await close(tester, services);
    });
  });
}
