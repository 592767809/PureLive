import 'dart:async';

import 'package:live_core/live_core.dart';
import 'package:pure_live/app/intake/system_intake.dart';
import 'package:pure_live/app/services.dart';
import 'package:pure_live/routes/app_navigator.dart';
import 'package:pure_live/routes/route_args.dart';
import 'package:pure_live/routes/route_observer.dart';
import 'package:pure_live/routes/route_path.dart';

/// Wires LAN link pushes to the same supported-platform parser as system shares.
/// Revoking pairing while a short link resolves prevents late navigation.
void installPlaybackRemote(AppServices services) {
  services.remoteControl.onLink = (text, authorized) async {
    if (!authorized()) return false;
    final link = await LinkParser(services.sites, services.http).parse(text);
    if (link == null || !authorized()) return false;
    final context = await appNavigatorReady();
    if (context == null || !context.mounted || !authorized()) return false;
    final room = LiveRoom(platform: link.platform, roomId: link.roomId);
    final follows = await services.store.follows.all();
    if (!authorized()) return false;
    final args = LiveRoomArgs(
      room: room,
      playlist: [room, ...follows.where((other) => other.identityKey != room.identityKey)],
    );
    final open = liveRouteObserver.topPage.value?.name == RoutePath.kLivePlay
        ? AppNavigator.offAndToNamed<void>(RoutePath.kLivePlay, arguments: args)
        : AppNavigator.toNamed<void>(RoutePath.kLivePlay, arguments: args);
    unawaited(open);
    return true;
  };
}
