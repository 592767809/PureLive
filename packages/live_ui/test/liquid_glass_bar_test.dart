// A01.6: the liquid glass bar. The shader does not run here (no Impeller),
// so this is the frosted fallback; the choices and the drag are the same.
import 'dart:ui' show Tristate;

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:live_ui/live_ui.dart';

void main() {
  Future<List<int>> pump(WidgetTester tester, {int selected = 0, bool still = false}) async {
    final chosen = <int>[];
    var index = selected;
    await tester.pumpWidget(
      MaterialApp(
        builder: (context, child) => MediaQuery(
          data: MediaQuery.of(context).copyWith(disableAnimations: still),
          child: child!,
        ),
        theme: const LiveTheme().light,
        home: Scaffold(
          body: Align(
            alignment: Alignment.bottomCenter,
            child: SizedBox(
              width: 400,
              height: GlassMetrics.barHeight,
              child: StatefulBuilder(
                builder: (context, setState) => LiquidGlassBar(
                  selectedIndex: index,
                  onSelected: (next) => setState(() {
                    chosen.add(next);
                    index = next;
                  }),
                  items: [
                    for (final name in ['关注', '热门', '分区', '录制中心'])
                      LiquidGlassBarItem(icon: Icons.circle_outlined, selectedIcon: Icons.circle, label: name),
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    );
    return chosen;
  }

  Finder item(String name) => find.text(name);

  testWidgets('a tap chooses; the chosen one tapped again is told too', (tester) async {
    final chosen = await pump(tester);
    await tester.tap(item('分区'));
    await tester.pumpAndSettle();
    await tester.tap(item('分区'));
    await tester.pumpAndSettle();
    expect(chosen, [2, 2]);
  });

  testWidgets('dragged along the bar the choice follows the finger; far past the end it is the last', (tester) async {
    final chosen = await pump(tester);
    await tester.dragFrom(tester.getCenter(item('关注')), tester.getCenter(item('分区')) - tester.getCenter(item('关注')));
    await tester.pumpAndSettle();
    expect(chosen, [2]);
    await tester.dragFrom(tester.getCenter(item('分区')), const Offset(800, 0));
    await tester.pumpAndSettle();
    expect(chosen, [2, 3]);
    // A drag that ends over the chosen one changes nothing.
    await tester.dragFrom(tester.getCenter(item('录制中心')), const Offset(-40, 0));
    await tester.pumpAndSettle();
    expect(chosen, [2, 3]);
  });

  testWidgets('each destination is a labelled button at least 48 high, the chosen one selected', (tester) async {
    final handle = tester.ensureSemantics();
    await pump(tester, selected: 1);
    final hot = tester.getSemantics(find.bySemanticsLabel('热门'));
    expect(hot.flagsCollection.isSelected, Tristate.isTrue);
    expect(hot.flagsCollection.isButton, isTrue);
    expect(hot.rect.height, greaterThanOrEqualTo(48));
    expect(tester.getSemantics(find.bySemanticsLabel('关注')).flagsCollection.isSelected, Tristate.isFalse);
    handle.dispose();
  });

  double held(WidgetTester tester) => tester
      .renderObject<RenderLiquidGlass>(
        find.byWidgetPredicate((widget) => widget.runtimeType.toString() == '_LiquidGlass'),
      )
      .held();

  testWidgets('A01.7: held, the pill turns into a lens and back when let go; the bar swells a little', (tester) async {
    await pump(tester);
    expect(held(tester), 0);
    final touch = await tester.startGesture(tester.getCenter(item('关注')));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 150));
    expect(held(tester), greaterThan(0.9));
    final scale = tester.widget<Transform>(
      find.descendant(of: find.byType(LiquidGlassBar), matching: find.byType(Transform)).at(1),
    );
    expect(scale.transform.getMaxScaleOnAxis(), greaterThan(1));
    await touch.up();
    await tester.pumpAndSettle();
    expect(held(tester), closeTo(0, 0.01));
  });

  testWidgets('A01.7: chosen elsewhere, the drop goes there as a lens and rests as a pill', (tester) async {
    await pump(tester);
    await tester.tap(item('录制中心'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 60));
    expect(held(tester), greaterThan(0.5));
    await tester.pumpAndSettle();
    expect(held(tester), closeTo(0, 0.01));
  });

  testWidgets('A01.7: with animations off the drop is always a pill', (tester) async {
    final chosen = await pump(tester, still: true);
    final touch = await tester.startGesture(tester.getCenter(item('热门')));
    await tester.pump(const Duration(milliseconds: 150));
    expect(held(tester), 0);
    await touch.up();
    await tester.pump();
    expect(chosen, [1]);
    expect(held(tester), 0);
  });

  testWidgets('A01.7: one name and one pair of icons per destination (the chosen colour only under the drop)', (
    tester,
  ) async {
    await pump(tester, selected: 2);
    for (final name in ['关注', '热门', '分区', '录制中心']) {
      expect(item(name), findsOneWidget);
    }
    expect(find.byIcon(Icons.circle), findsNWidgets(4));
    expect(find.byIcon(Icons.circle_outlined), findsNWidgets(4));
  });
}
