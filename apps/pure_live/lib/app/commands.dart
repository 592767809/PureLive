import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:flutter/widgets.dart';
import 'package:pure_live/features/home/home_menu.dart';
import 'package:pure_live/routes/app_navigator.dart';
import 'package:pure_live/routes/route_path.dart';

/// The app's keyboard commands, one table for the Mac's menu bar and the
/// iPad's keyboard (docs/A-界面设计/A18-苹果平台界面: A18.2 c4–c5, A18.1 c10):
/// ⌘, settings, ⌘F search, ⌘L the link parser, ⌘Y the watch history,
/// ⌘1–⌘4 follows, popular, areas and the recording centre, ⌘[ back. The
/// room's own commands are [RoomCommands]; v3's single keys stay where they
/// were (the room's space, R, arrows and Esc).
enum AppCommand {
  /// ⌘, the settings.
  settings(LogicalKeyboardKey.comma),

  /// ⌘F search.
  search(LogicalKeyboardKey.keyF),

  /// ⌘L the link parser.
  openLink(LogicalKeyboardKey.keyL),

  /// ⌘Y the watch history.
  history(LogicalKeyboardKey.keyY),

  /// ⌘1 the follows.
  favorites(LogicalKeyboardKey.digit1),

  /// ⌘2 popular.
  popular(LogicalKeyboardKey.digit2),

  /// ⌘3 the areas.
  areas(LogicalKeyboardKey.digit3),

  /// ⌘4 the recording centre.
  record(LogicalKeyboardKey.digit4),

  /// ⌘[ back.
  back(LogicalKeyboardKey.bracketLeft);

  new(this.key);

  /// The key pressed with ⌘.
  final LogicalKeyboardKey key;

  /// ⌘ and [key].
  SingleActivator get activator => SingleActivator(key, meta: true);

  /// The home destination this command shows, if any.
  HomeMenu? get homeMenu => switch (this) {
    favorites => HomeMenu.favorites,
    popular => HomeMenu.popular,
    areas => HomeMenu.areas,
    record => HomeMenu.record,
    _ => null,
  };

  /// Does it (pages open without waiting for them to close). A home
  /// destination goes back to the home page first.
  void run() {
    if (homeMenu case final menu?) {
      AppNavigator.router.go(RoutePath.kInitial);
      // After the home page is back and listening.
      WidgetsBinding.instance.addPostFrameCallback((_) {
        HomeSignals.select.value = (menu, (HomeSignals.select.value?.$2 ?? 0) + 1);
      });
      WidgetsBinding.instance.scheduleFrame();
      return;
    }
    switch (this) {
      case settings:
        unawaited(AppNavigator.toNamed<void>(RoutePath.kSettings));
      case search:
        unawaited(AppNavigator.toNamed<void>(RoutePath.kSearch));
      case openLink:
        unawaited(AppNavigator.toNamed<void>(RoutePath.kToolbox));
      case history:
        unawaited(AppNavigator.toNamed<void>(RoutePath.kHistory));
      case back:
        // The page's own back first (a room leaves its full screen, a panel
        // closes), as the system's back does.
        final context = AppNavigator.navigatorContext;
        if (context != null) Navigator.maybePop(context);
      case favorites || popular || areas || record:
        break;
    }
  }
}

/// What the open live room offers the Mac's "播放" menu (A18.2 c4); the room
/// page puts its own here while it is on top, so the menu is greyed
/// elsewhere.
abstract interface class RoomCommands {
  /// Pauses or plays (space).
  Future<void> togglePlay();

  /// Loads the room again (⌘R; v3's R).
  Future<void> refresh();

  /// Into or out of the room's full screen (v3's F).
  void toggleFullScreen();

  /// The room on top, or null.
  static final ValueNotifier<RoomCommands?> current = ValueNotifier(null);
}

/// ⌘R, the room's refresh.
const SingleActivator refreshActivator = SingleActivator(LogicalKeyboardKey.keyR, meta: true);

/// The [AppCommand]s as keyboard shortcuts over [child] on an iPad (A18.1
/// c10); elsewhere [child] alone (the Mac has them in its menu bar).
class AppCommandShortcuts extends StatelessWidget {
  /// Wraps [child].
  const new({required this.child, super.key});

  /// The app.
  final Widget child;

  @override
  Widget build(BuildContext context) {
    if (defaultTargetPlatform != TargetPlatform.iOS) return child;
    return CallbackShortcuts(
      bindings: {
        for (final command in AppCommand.values) command.activator: command.run,
        refreshActivator: () => unawaited(RoomCommands.current.value?.refresh()),
      },
      child: child,
    );
  }
}
