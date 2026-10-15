import 'dart:async';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:live_core/live_core.dart';
import 'package:live_media/live_media.dart';
import 'package:live_player/live_player.dart';
import 'package:live_store/live_store.dart';
import 'package:live_ui/live_ui.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';
import 'package:pure_live/app/services.dart';
import 'package:pure_live/features/settings/settings_dialogs.dart';
import 'package:pure_live/tv/wallpaper/wallpaper_files.dart';
import 'package:pure_live/tv/wallpaper/wallpaper_model.dart';

/// Sets and changes the TV background; its files in the app's support
/// folder, `tv_wallpaper/`.
final Provider<TvWallpaperStore> tvWallpaperStoreProvider = Provider((ref) {
  final services = ref.watch(appServicesProvider);
  return TvWallpaperStore(
    settings: services.store.settings,
    files: TvWallpaperFiles(
      folder: getApplicationSupportDirectory().then((folder) => Directory(p.join(folder.path, 'tv_wallpaper'))),
      http: services.http,
    ),
  );
});

/// The background now (rebuilt when any of its settings change).
TvWallpaper watchTvWallpaper(WidgetRef ref) {
  for (final setting in <Setting<Object>>[
    Settings.tvWallpaperKind,
    Settings.tvWallpaperValue,
    Settings.tvWallpaperFit,
    Settings.tvWallpaperMask,
  ]) {
    watchSetting(ref, setting);
  }
  return TvWallpaper.of(ref.read(storeProvider).settings);
}

/// Pages that decode video of their own (the live room, a video) hold the
/// video background still while they are open (A17.8, risk: a box decodes
/// one video at a time).
abstract final class TvWallpaperVideo {
  static final ValueNotifier<int> _holds = ValueNotifier(0);

  /// Whether the video background is held still.
  static ValueListenable<int> get holds => _holds;

  /// Holds it still until [release].
  static void hold() => _holds.value++;

  /// Lets it play again (once every holder released it).
  static void release() => _holds.value = (_holds.value - 1).clamp(0, 1 << 20);
}

/// The TV interface's background (A17.8 h1), under every TV page: a colour,
/// a gradient, a picture (blurred already, h7) or a muted looping video,
/// with the dark veil over it. Nothing when there is none (the pages then
/// paint the theme's colour as before).
class TvWallpaperLayer extends ConsumerWidget {
  /// Creates the layer.
  const new({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final wallpaper = watchTvWallpaper(ref);
    if (!wallpaper.active) return const SizedBox.shrink();
    final picture = switch (wallpaper.kind) {
      TvWallpaperKind.color => ColoredBox(color: parseColorHex(wallpaper.value) ?? OnVideoColors.ground),
      TvWallpaperKind.gradient => DecoratedBox(
        decoration: BoxDecoration(gradient: tvGradientOf(wallpaper.value)?.gradient),
      ),
      TvWallpaperKind.image => Image.file(
        File(wallpaper.value),
        key: ValueKey('tv-wallpaper-image-${wallpaper.value}'),
        fit: wallpaper.fit,
        gaplessPlayback: true,
        errorBuilder: (_, _, _) => const SizedBox.shrink(),
      ),
      TvWallpaperKind.video => _VideoWallpaper(
        key: ValueKey(wallpaper.value),
        path: wallpaper.value,
        fit: wallpaper.fit,
      ),
      TvWallpaperKind.none => const SizedBox.shrink(),
    };
    return Stack(
      key: const ValueKey('tv-wallpaper'),
      fit: StackFit.expand,
      children: [
        picture,
        if (wallpaper.kind != TvWallpaperKind.color && wallpaper.kind != TvWallpaperKind.gradient)
          ColoredBox(color: OnVideoColors.ground.withValues(alpha: wallpaper.mask)),
      ],
    );
  }
}

class _VideoWallpaper extends ConsumerStatefulWidget {
  const new({required this.path, required this.fit, super.key});

  final String path;
  final BoxFit fit;

  @override
  ConsumerState<_VideoWallpaper> createState() => _VideoWallpaperState();
}

class _VideoWallpaperState extends ConsumerState<_VideoWallpaper> {
  late final PlaybackSession _session = ref.read(playbackSessionFactoryProvider)();
  StreamSubscription<PlaybackState>? _states;

  @override
  void initState() {
    super.initState();
    TvWallpaperVideo.holds.addListener(_holdChanged);
    _states = _session.states.listen((state) {
      // Loops: the end goes back to the start.
      if (state.status == PlaybackStatus.completed) {
        unawaited(_session.seek(Duration.zero).then((_) => _session.resume()));
      }
    });
    unawaited(_open());
  }

  Future<void> _open() async {
    await _session.open(
      PlaybackRequest(
        site: 'wallpaper',
        volume: 0,
        plan: PlaybackPlan.of(
          LivePlayUrlResolution.lines([LivePlayLine(Uri.file(widget.path).toString())]),
          onDemand: true,
        ),
      ),
    );
    if (TvWallpaperVideo.holds.value > 0) await _session.pause();
  }

  void _holdChanged() => unawaited(TvWallpaperVideo.holds.value > 0 ? _session.pause() : _session.resume());

  @override
  void dispose() {
    TvWallpaperVideo.holds.removeListener(_holdChanged);
    unawaited(_states?.cancel());
    unawaited(_session.dispose());
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => LiveVideoView(session: _session, fit: widget.fit);
}
