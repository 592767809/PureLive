import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:live_core/live_core.dart';
import 'package:live_iptv/live_iptv.dart';
import 'package:live_store/live_store.dart';
import 'package:live_ui/live_ui.dart';
import 'package:pure_live/app/iptv_playlists.dart';
import 'package:pure_live/app/services.dart';
import 'package:pure_live/features/popular/popular_catalog.dart';
import 'package:pure_live/i18n/i18n.dart';
import 'package:pure_live/shared/rooms/room_grid.dart';

/// The note of a platform whose directory is not the whole site (the
/// adapter's `LiveDirectoryNotice`), rewritten for the popular page (U.4b
/// c6).
String? popularNoticeOf(LiveSite site) {
  if (site is! LiveDirectoryNotice) return null;
  final key = 'popular_scope_${site.id}';
  return i18nExists(key) ? i18n(key) : i18n((site as LiveDirectoryNotice).directoryNoticeKey);
}

/// One platform's recommendations (3.x `PopularGridView` over
/// `BasePageView`, docs/A-界面设计/A09-浏览界面/A09.2-热门): the shared [RoomFeedView] over the
/// platform's feed, with the popular page's empty state (c4) and its notes.
class PopularPlatformView extends ConsumerWidget {
  /// Creates the view of [platform].
  const new({required this.platform, super.key});

  /// Platform id.
  final String platform;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final catalog = ref.read(popularCatalogProvider);
    final site = ref.read(sitesProvider).of(platform);
    final feed = _feed(catalog, site, ref);
    if (platform != SiteIds.iptv) return feed;
    return Column(
      children: [
        const IptvPopularPlaylists(),
        Expanded(child: feed),
      ],
    );
  }

  Widget _feed(PopularCatalog catalog, LiveSite site, WidgetRef ref) {
    return RoomFeedView(
      feed: catalog.feedOf(platform),
      keyPrefix: 'popular',
      notice: popularNoticeOf(site),
      pageSize: catalog.pageSize,
      onPageSize: (size) => catalog.pageSize = size,
      empty: (
        icon: AppIcons.emptyPopular,
        title: i18n('empty_live_title'),
        subtitle: ({required desktop}) => i18n(desktop ? 'popular_empty_desktop' : 'popular_empty_phone'),
      ),
      hiddenNote: (count) => i18n('popular_hidden_count', args: {'count': '$count'}),
      onShowHidden: () => ref.read(storeProvider).settings.set(Settings.showUnplayableInDiscover, true).ignore(),
    );
  }
}

/// The playlists of the IPTV tab (V02.9, issue #6; 3.x showed only the
/// built-in hot list here, the imported ones only under 分区): the hot list
/// unless it was deleted, then the imported ones in the IPTV page's order;
/// the one shown ticked ([shownIptvPlaylist]); a tap shows another and is
/// remembered. Hidden with fewer than two playlists.
class IptvPopularPlaylists extends ConsumerWidget {
  /// Creates the row.
  const new({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final playlists = ref.watch(iptvPlaylistsProvider).value;
    final removed = watchSetting(ref, Settings.iptvHotRemoved);
    final wanted = watchSetting(ref, Settings.iptvPopularPlaylist);
    if (playlists == null) return const SizedBox.shrink();
    final options = <(String, String)>[
      if (!removed) (IptvPlaylist.hotId, i18n('iptv_hot_playlist')),
      for (final playlist in [...playlists]..sort(compareIptvPlaylists))
        if (!playlist.isHot) (playlist.id, iptvPlaylistName(playlist)),
    ];
    if (options.length < 2) return const SizedBox.shrink();
    final shown = shownIptvPlaylist(playlists, wanted: wanted, hotRemoved: removed);
    // The one chip of the app (U.1c c13), in the follows' tag row (U.4c c2).
    return SizedBox(
      key: const ValueKey('popular-iptv-playlists'),
      height: 48,
      child: ListView(
        scrollDirection: Axis.horizontal,
        physics: const PureLiveBoundedScrollPhysics(),
        padding: const EdgeInsets.symmetric(horizontal: 12),
        children: [
          for (final (id, name) in options)
            Padding(
              padding: const EdgeInsets.only(right: 8),
              child: Center(
                child: AppChip(
                  key: ValueKey('popular-iptv-playlist-$id'),
                  label: name,
                  selected: id == shown,
                  onSelected: id == shown
                      ? () {}
                      : () => ref.read(storeProvider).settings.set(Settings.iptvPopularPlaylist, id).ignore(),
                ),
              ),
            ),
        ],
      ),
    );
  }
}
