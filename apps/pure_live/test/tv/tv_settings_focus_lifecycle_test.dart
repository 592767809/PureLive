import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pure_live/tv/settings/tv_settings_section_page.dart';
import 'package:pure_live/tv/tv_theme.dart';
import 'package:pure_live/tv/widgets/tv_button.dart';

import '../support.dart';

void main() {
  testWidgets('settings loaded under a dialog receive their initial focus when it closes', (tester) async {
    await tester.runAsync(loadStrings);
    final navigator = GlobalKey<NavigatorState>();
    final ready = ValueNotifier(false);
    final first = FocusNode(debugLabel: 'loaded settings row');
    final second = FocusNode(debugLabel: 'user selected row');
    addTearDown(ready.dispose);
    addTearDown(first.dispose);
    addTearDown(second.dispose);
    await tester.pumpWidget(
      MaterialApp(
        navigatorKey: navigator,
        builder: (context, child) => MediaQuery(
          data: MediaQuery.of(context).copyWith(navigationMode: NavigationMode.directional),
          child: TvTheme(palette: TvPalette.of(Theme.of(context).colorScheme), child: child!),
        ),
        home: const Scaffold(body: Text('Home')),
      ),
    );
    navigator.currentState!.push<void>(
      MaterialPageRoute(
        builder: (context) => TvSettingsScaffold(
          title: 'Settings',
          child: ValueListenableBuilder<bool>(
            valueListenable: ready,
            builder: (context, loaded, _) => loaded
                ? Column(
                    children: [
                      TvButton(label: 'Loaded row', focusNode: first, onTap: () {}),
                      TvButton(label: 'Second row', focusNode: second, onTap: () {}),
                    ],
                  )
                : const Center(child: CircularProgressIndicator()),
          ),
        ),
      ),
    );
    await tester.pump();
    unawaited(
      showDialog<void>(
        context: navigator.currentContext!,
        builder: (context) => AlertDialog(
          title: const Text('Temporary dialog'),
          actions: [TextButton(onPressed: () => Navigator.of(context).pop(), child: const Text('Close'))],
        ),
      ),
    );
    await tester.pump(const Duration(seconds: 1));
    ready.value = true;
    await tester.pump();
    expect(first.hasFocus, isFalse, reason: 'the loading page must not steal the dialog focus');
    navigator.currentState!.pop();
    await tester.pumpAndSettle();
    expect(first.hasFocus, isTrue, reason: 'the first usable row is now attached and uncovered');
    second.requestFocus();
    await tester.pump();
    unawaited(
      showDialog<void>(
        context: navigator.currentContext!,
        builder: (context) => const AlertDialog(title: Text('Another dialog')),
      ),
    );
    await tester.pump(const Duration(seconds: 1));
    navigator.currentState!.pop();
    await tester.pumpAndSettle();
    expect(second.hasFocus, isTrue, reason: 'returning later must preserve the user selected row');
    await tester.pumpWidget(const SizedBox.shrink());
  });
}
