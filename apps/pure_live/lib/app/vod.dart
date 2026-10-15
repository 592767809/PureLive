import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:live_vod/live_vod.dart';
import 'package:pure_live/app/services.dart';

/// The Bilibili video-on-demand plumbing (M14.0 `live_vod`): the app's HTTP
/// client (same proxy and rate rules as the live platform, site id
/// `bilibili`) and the live login cookie, so signing in once serves live
/// rooms and videos alike.
final Provider<BilibiliVodClient> vodClientProvider = Provider((ref) {
  final services = ref.watch(appServicesProvider);
  return BilibiliVodClient(services.http, cookies: services.cookies);
});

/// Video (UGC) endpoints: catalogs, detail, streams, comments, spaces,
/// favourites, history, search.
final Provider<BilibiliUgcApi> vodUgcProvider = Provider((ref) => BilibiliUgcApi(ref.watch(vodClientProvider)));

/// PGC endpoints: anime and film index, seasons, episode streams, followed
/// seasons.
final Provider<BilibiliPgcApi> vodPgcProvider = Provider((ref) => BilibiliPgcApi(ref.watch(vodClientProvider)));
