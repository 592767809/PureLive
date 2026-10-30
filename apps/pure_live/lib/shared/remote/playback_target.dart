import 'package:live_core/live_core.dart';
import 'package:live_player/live_player.dart';
import 'package:pure_live/shared/remote/playback_remote.dart';

/// Binds shared playback commands to phone, TV and multiview pages.
/// Page-specific navigation stays with the page that owns it.
RemotePlaybackTarget playbackRemoteTarget({
  required bool Function() available,
  required LiveRoom? Function() room,
  required PlaybackSession? Function() session,
  required Future<void> Function() refresh,
  required Future<void> Function(double) volume,
  required Map<String, Future<bool> Function()> navigation,
}) {
  var lastVolume = 0.5;
  String? mutedRoom;
  return RemotePlaybackTarget(
    available: () => available() && room() != null && session() != null,
    snapshot: () {
      final current = room();
      final state = session()?.state;
      return {
        'nick': current?.nick,
        'title': current?.title,
        'platform': current?.platform,
        'paused': state?.status == PlaybackStatus.paused,
        'volume': state?.volume,
        'commands': ['play', 'pause', 'refresh', 'volume', 'mute', ...navigation.keys],
      };
    },
    execute: (command, value) async {
      if (!available()) return false;
      final player = session();
      final current = room();
      if (player == null || current == null) return false;
      if (navigation[command] case final callback?) return await callback();
      switch (command) {
        case 'play':
          await player.resume();
        case 'pause':
          await player.pause();
        case 'refresh':
          await refresh();
        case 'volume':
          if (value == null) return false;
          await volume(value);
        case 'mute':
          final level = player.state.volume;
          if (level > 0) {
            lastVolume = level;
            mutedRoom = current.identityKey;
            await volume(0);
          } else {
            await volume(mutedRoom == current.identityKey ? lastVolume : 0.5);
          }
        default:
          return false;
      }
      return true;
    },
  );
}
