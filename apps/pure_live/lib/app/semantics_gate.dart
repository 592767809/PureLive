import 'dart:async';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter/widgets.dart';
import 'package:pure_live/platform/assistive.dart';

/// Whether the app gives its semantics tree to the platform (R01.3).
///
/// Android turns Flutter's semantics on for any accessibility service, not
/// only for a screen reader: HyperOS's 小米澎湃AI引擎 is on by default, and
/// password managers and automation apps are common. Keeping the tree then
/// took more of each frame than laying out and painting the text: on the
/// K90, eight page turns on the hot list lost about 100 frames with the
/// service on and 12 with it off. So on Android the tree is given only while
/// an assistive tool uses the screen ([AssistiveTech]), or always when
/// [always] ("无障碍兼容", for any other tool). Other platforms ask for it
/// only for a screen reader, so they always get it.
class SemanticsGate extends StatefulWidget {
  /// Gates [child]'s semantics.
  new({required this.always, required this.child, bool? android, ValueListenable<bool>? assistive, super.key})
    : android = android ?? Platform.isAndroid,
      assistive = assistive ?? AssistiveTech.inUse;

  /// Give the tree to every accessibility service.
  final bool always;

  /// Whether this runs on Android.
  final bool android;

  /// Whether an assistive tool uses the screen.
  final ValueListenable<bool> assistive;

  /// The app.
  final Widget child;

  /// Whether the tree is given.
  static bool provides({required bool always, required bool android, required bool assistive}) =>
      always || !android || assistive;

  @override
  State<SemanticsGate> createState() => _SemanticsGateState();
}

class _SemanticsGateState extends State<SemanticsGate> {
  @override
  void initState() {
    super.initState();
    if (widget.android) unawaited(AssistiveTech.start());
  }

  @override
  Widget build(BuildContext context) => ValueListenableBuilder<bool>(
    valueListenable: widget.assistive,
    // The app is the same widget whether gated or not: no rebuild below.
    child: widget.child,
    builder: (context, assistive, child) => ExcludeSemantics(
      excluding: !SemanticsGate.provides(always: widget.always, android: widget.android, assistive: assistive),
      child: child,
    ),
  );
}
