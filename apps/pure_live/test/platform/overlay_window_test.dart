import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:live_store/live_store.dart';
import 'package:pure_live/features/live_play/logic/background_playback.dart';
import 'package:pure_live/i18n/i18n.dart';
import 'package:pure_live/platform/overlay_window.dart';

import '../features/settings/settings_harness.dart';
import '../support.dart';

const _pip = MethodChannel('pure_live/pip');
const _overlay = MethodChannel('pure_live/overlay');

void main() {
  setUpAll(() async => currentStrings = await loadStrings());

  test('A07.25: one choice over two settings; the floating window wins, none is as before', () async {
    final store = await LiveStore.memory(cipher: FakeCipher());
    addTearDown(store.close);
    final settings = store.settings;
    expect(leaveAppWindow(settings), LeaveAppWindow.none, reason: 'old users see nothing new');
    await settings.set(Settings.autoPipOnLeave, true);
    expect(leaveAppWindow(settings), LeaveAppWindow.pip, reason: 'an old "自动画中画" stays');
    await setLeaveAppWindow(settings, LeaveAppWindow.overlay);
    expect(leaveAppWindow(settings), LeaveAppWindow.overlay);
    expect(settings.get(Settings.autoPipOnLeave), isFalse);
    await setLeaveAppWindow(settings, LeaveAppWindow.none);
    expect((settings.get(Settings.autoPipOnLeave), settings.get(Settings.floatOverAppsOnLeave)), (false, false));
  });

  group('arming', () {
    late List<MethodCall> calls;

    setUp(() {
      calls = [];
      PictureInPicture.debugAndroid = true;
      OverlayWindow.debugAndroid = true;
      for (final channel in [_pip, _overlay]) {
        TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger.setMockMethodCallHandler(channel, (
          call,
        ) async {
          calls.add(call);
          return null;
        });
      }
    });

    tearDown(() {
      PictureInPicture.debugAndroid = null;
      OverlayWindow.debugAndroid = null;
      OverlayWindow.permitted.value = false;
      for (final channel in [_pip, _overlay]) {
        TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger.setMockMethodCallHandler(channel, null);
      }
    });

    /// Whether the last [method] call armed it; false when there was none
    /// (a disarm by someone who did not arm sends nothing).
    bool armed(String method) {
      final call = calls.where((call) => call.method == method).lastOrNull;
      return (call?.arguments as Map?)?['enabled'] == true;
    }

    final owner = Object();

    Future<void> arm(LeaveAppWindow choice, {bool playing = true}) => armLeaveWindow(
      choice: choice,
      playing: playing,
      width: 16,
      height: 9,
      window: const Rect.fromLTWH(10, 20, 320, 180),
      pixelRatio: 3,
      owner: owner,
    );

    test('the floating window, with the permission: armed at the place in pixels, the system one not', () async {
      OverlayWindow.permitted.value = true;
      await arm(LeaveAppWindow.overlay);
      expect(armed('setAutoEnter'), isFalse);
      expect(calls.lastWhere((call) => call.method == 'arm').arguments, {
        'enabled': true,
        'x': 30,
        'y': 60,
        'width': 960,
        'height': 540,
      });
    });

    test('the floating window without the permission: neither (nothing appears, as before)', () async {
      await arm(LeaveAppWindow.overlay);
      expect(armed('setAutoEnter'), isFalse);
      expect(armed('arm'), isFalse);
    });

    test("the system's picture-in-picture: that one, not the floating window; nothing while not playing", () async {
      OverlayWindow.permitted.value = true;
      await arm(LeaveAppWindow.pip);
      expect(armed('setAutoEnter'), isTrue);
      expect(armed('arm'), isFalse);
      await arm(LeaveAppWindow.pip, playing: false);
      expect(armed('setAutoEnter'), isFalse);
    });
  });

  testWidgets('A07.25: "离开应用后" offers three on Android; the floating window asks for the permission', (tester) async {
    final h = await pumpSettings(tester, height: 2600, arguments: 'video');
    final row = settingsRow('auto_pip');
    await tester.ensureVisible(row);
    expect(find.descendant(of: row, matching: find.text('不保留画面')), findsOneWidget);
    await tapSettings(tester, row);
    for (final label in ['不保留画面', '系统画中画', '应用悬浮窗']) {
      expect(find.text(label), findsWidgets, reason: label);
    }
    await tapSettings(tester, find.text('系统画中画').last);
    expect(h.services.store.settings.get(Settings.autoPipOnLeave), isTrue);
    expect(find.descendant(of: row, matching: find.text('系统画中画')), findsOneWidget);
  });
}
