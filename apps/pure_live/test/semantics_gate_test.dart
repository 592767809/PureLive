// R01.3: on Android the semantics tree goes to the platform only while an
// assistive tool uses the screen (or always with "无障碍兼容"); any
// accessibility service being on (HyperOS's AI engine by default) cost more
// of each frame than layout and paint.
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pure_live/app/semantics_gate.dart';

void main() {
  test('who gets the tree', () {
    expect(SemanticsGate.provides(always: false, android: true, assistive: false), isFalse);
    expect(SemanticsGate.provides(always: false, android: true, assistive: true), isTrue);
    expect(SemanticsGate.provides(always: true, android: true, assistive: false), isTrue);
    expect(SemanticsGate.provides(always: false, android: false, assistive: false), isTrue);
  });

  testWidgets('Android without an assistive tool: the labels stay out of the tree; a tool or the setting brings them', (
    tester,
  ) async {
    final handle = tester.ensureSemantics();
    final tool = ValueNotifier(false);
    var builds = 0;
    Future<void> pump({required bool always, required bool android}) => tester.pumpWidget(
      Directionality(
        textDirection: TextDirection.ltr,
        child: SemanticsGate(
          always: always,
          android: android,
          assistive: tool,
          child: Builder(
            builder: (context) {
              builds++;
              return Semantics(label: '关注', button: true, child: const SizedBox(width: 48, height: 48));
            },
          ),
        ),
      ),
    );
    await pump(always: false, android: true);
    expect(find.bySemanticsLabel('关注'), findsNothing);

    // TalkBack turned on: the tree comes without rebuilding the app.
    final before = builds;
    tool.value = true;
    await tester.pump();
    expect(find.bySemanticsLabel('关注'), findsOneWidget);
    expect(builds, before);

    tool.value = false;
    await pump(always: true, android: true);
    expect(find.bySemanticsLabel('关注'), findsOneWidget);

    await pump(always: false, android: false);
    expect(find.bySemanticsLabel('关注'), findsOneWidget);
    handle.dispose();
  });
}
