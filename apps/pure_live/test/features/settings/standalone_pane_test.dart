import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:live_ui/live_ui.dart';
import 'package:pure_live/app/app_log.dart';
import 'package:pure_live/app/services.dart';
import 'package:pure_live/features/backup/backup_page.dart';
import 'package:pure_live/features/backup/log_page.dart';
import 'package:pure_live/features/iptv/iptv_data.dart';
import 'package:pure_live/features/iptv/iptv_page.dart';
import 'package:pure_live/features/live_play/local_interaction/local_interaction_settings_page.dart';
import 'package:pure_live/features/record_settings/record_settings_page.dart';
import 'package:pure_live/features/settings/settings_model.dart';
import 'package:pure_live/features/settings/settings_page.dart';
import 'package:pure_live/features/web_dav/web_dav_page.dart';
import 'package:pure_live/routes/app_navigator.dart';
import 'package:pure_live/routes/route_path.dart';

import 'settings_harness.dart';

Future<void> _open(WidgetTester tester, SettingsSection section) async {
  if (section != SettingsSection.backup) {
    await tapSettings(tester, settingsSection(section));
    return;
  }
  await tester.ensureVisible(settingsSection(section));
  await tester.pumpAndSettle();
  await tester.tap(settingsSection(section));
  await settleSettingsFiles(tester);
}

void main() {
  final destinations = [
    (SettingsSection.iptv, IptvPage, RoutePath.kIptv),
    (SettingsSection.recording, RecordSettingsPage, RoutePath.kRecordSettings),
    (SettingsSection.localInteraction, LocalInteractionSettingsPage, RoutePath.kLocalInteraction),
    (SettingsSection.backup, BackupPage, RoutePath.kBackup),
    (SettingsSection.log, LogPage, RoutePath.kLogs),
  ];
  for (final (section, pageType, _) in destinations) {
    testWidgets('issue56: ${section.name} stays beside the overview in a wide settings window', (tester) async {
      await withPlatform(TargetPlatform.windows, () async {
        final directory = (await tester.runAsync(() => Directory.systemTemp.createTemp('purelive516-pane-')))!;
        addTearDown(() {
          if (directory.existsSync()) directory.deleteSync(recursive: true);
        });
        final h = await pumpSettings(
          tester,
          width: 1280,
          height: 1400,
          overrides: [
            backupDefaultFolderProvider.overrideWithValue(() async => directory),
            iptvImporterProvider.overrideWithValue(null),
            recordingProvider.overrideWithValue(null),
          ],
        );
        await _open(tester, section);
        expect(h.opened, isEmpty, reason: 'the root navigator must not replace the two-pane settings');
        expect(find.byKey(const ValueKey('settings-overview')), findsOneWidget);
        final page = find.byType(pageType);
        expect(page, findsOneWidget);
        expect(tester.getTopLeft(page).dx, greaterThanOrEqualTo(settingsOverviewWidth));
        expect(tester.widget<SettingsLinkRow>(settingsSection(section)).selected, isTrue);
      });
    });
  }
  testWidgets('issue56: a wide log page survives resize and its back button returns to the narrow overview', (
    tester,
  ) async {
    await withPlatform(TargetPlatform.windows, () async {
      final h = await pumpSettings(tester, width: 1280, height: 1400);
      await tapSettings(tester, settingsSection(SettingsSection.log));
      expect(h.opened, isEmpty);
      expect(find.byType(LogPage), findsOneWidget);
      await tester.tap(find.descendant(of: find.byKey(const ValueKey('log-filter')), matching: find.text('警告')));
      await tester.pump();
      tester.view.physicalSize = const Size(600, 1000);
      await settleSettings(tester);
      expect(find.byType(LogPage), findsOneWidget);
      expect(tester.widget<SegmentedButton<LogLevel>>(find.byKey(const ValueKey('log-filter'))).selected, {
        LogLevel.warning,
      });
      expect(find.byKey(const ValueKey('settings-overview')), findsNothing);
      tester.view.physicalSize = const Size(1280, 1400);
      await settleSettings(tester);
      expect(find.byKey(const ValueKey('settings-overview')), findsOneWidget);
      expect(tester.widget<SegmentedButton<LogLevel>>(find.byKey(const ValueKey('log-filter'))).selected, {
        LogLevel.warning,
      });
      tester.view.physicalSize = const Size(600, 1000);
      await settleSettings(tester);
      await tester.tap(find.byType(BackButton));
      await settleSettings(tester);
      expect(find.byKey(const ValueKey('settings-overview')), findsOneWidget);
      expect(find.byType(LogPage), findsNothing);
    });
  });

  testWidgets('issue56: an initially requested routed section uses the wide content pane', (tester) async {
    await pumpSettings(tester, width: 1280, height: 1400, arguments: 'log');
    expect(find.byType(LogPage), findsOneWidget);
    expect(find.byKey(const ValueKey('settings-overview')), findsOneWidget);
    expect(tester.getTopLeft(find.byType(LogPage)).dx, greaterThanOrEqualTo(settingsOverviewWidth));
  });

  testWidgets('issue56: WebDAV opened from embedded backup stays in the content stack and returns there', (
    tester,
  ) async {
    final directory = (await tester.runAsync(() => Directory.systemTemp.createTemp('purelive516-nested-')))!;
    addTearDown(() {
      if (directory.existsSync()) directory.deleteSync(recursive: true);
    });
    final h = await pumpSettings(
      tester,
      width: 1280,
      height: 1400,
      overrides: [backupDefaultFolderProvider.overrideWithValue(() async => directory)],
    );
    await _open(tester, SettingsSection.backup);
    await tester.ensureVisible(find.byKey(const ValueKey('backup-webdav')));
    await tester.tap(find.byKey(const ValueKey('backup-webdav')));
    await settleSettingsFiles(tester);
    expect(h.opened, isEmpty);
    expect(find.byKey(const ValueKey('settings-overview')), findsOneWidget);
    expect(tester.getTopLeft(find.byType(WebDavPage)).dx, greaterThanOrEqualTo(settingsOverviewWidth));
    await tester.binding.handlePopRoute();
    await settleSettingsFiles(tester);
    expect(find.byType(BackupPage), findsOneWidget);
    expect(find.byType(WebDavPage), findsNothing);
    expect(find.byKey(const ValueKey('settings-overview')), findsOneWidget);
  });
  for (final section in [SettingsSection.localInteraction, SettingsSection.log]) {
    testWidgets('issue56: ${section.name} keeps the existing root route on a narrow window', (tester) async {
      final h = await pumpSettings(tester);
      await tapSettings(tester, settingsSection(section));
      expect(h.opened.last, section.route);
      AppNavigator.router.pop();
      await settleSettings(tester);
      expect(find.byKey(const ValueKey('settings-overview')), findsOneWidget);
    });
  }
}
