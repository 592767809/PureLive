import 'dart:async';

import 'package:live_core/live_core.dart';
import 'package:live_media/live_media.dart';
import 'package:live_player/live_player.dart';
import 'package:live_store/live_store.dart';

/// Room reservations shared by the cells of one multi-view.
final class AutoRoomSwitchGroup {
  final Map<Object, String> _rooms = {};

  /// Whether another cell already owns [room].
  bool available(Object owner, LiveRoom room) =>
      !_rooms.entries.any((entry) => entry.key != owner && entry.value == room.identityKey);

  /// Claims a room synchronously, before another asynchronous lookup finishes.
  void claim(Object owner, LiveRoom room) => _rooms[owner] = room.identityKey;

  /// Releases a removed cell.
  void release(Object owner) => _rooms.remove(owner);
}

/// Opt-in, bounded switching through freshly confirmed online follows.
///
/// Existing player recovery always runs first. Network-loss errors continue
/// probing in PlaybackSession and therefore never trigger this scheduler.
/// A failed candidate is tried once until playback stays healthy for 30 seconds
/// or the user chooses a room or toggles the setting. No polling starts after
/// the candidate list is exhausted.
final class AutoRoomSwitch {
  /// Creates a scheduler for one room page or multi-view cell.
  new({
    required this.store,
    required this.siteOf,
    required this.onSwitch,
    required this.maySwitch,
    this.onExhausted,
    AutoRoomSwitchGroup? group,
    this.lookupTimeout = const Duration(seconds: 10),
  }) : _group = group ?? AutoRoomSwitchGroup() {
    _settings = store.settings.watch(Settings.autoSwitchLiveFollows).skip(1).listen((_) {
      _cancel();
      _attempted.clear();
      _exhausted = false;
      _evaluate();
    });
  }

  /// Local follows and the opt-in preference.
  final LiveStore store;

  /// Platform adapter lookup.
  final LiveSite? Function(String platform) siteOf;

  /// Replaces this room without changing the surrounding layout or audio focus.
  final void Function(LiveRoom room) onSwitch;

  /// The owning page's lifecycle and background-play policy.
  final bool Function() maySwitch;

  /// Called once when this round has no usable candidate.
  final void Function()? onExhausted;

  /// Maximum time for one database or platform lookup.
  final Duration lookupTimeout;

  final AutoRoomSwitchGroup _group;
  final Object _owner = Object();
  final Set<String> _attempted = {};
  String? _checking;
  late final StreamSubscription<bool> _settings;
  Timer? _pending;
  Timer? _healthy;
  LiveRoom? _room;
  PlaybackState _playback = const PlaybackState();
  bool _resolving = true;
  bool _unavailable = false;
  bool _replay = false;
  bool _held = false;
  bool _suspended = false;
  bool _exhausted = false;
  bool _searching = false;
  bool _disposed = false;
  int _epoch = 0;

  /// A round stopped after trying every available online follow.
  bool get exhausted => _exhausted;

  /// Binds a new room; explicit user choices start a fresh round.
  void setRoom(LiveRoom room, {bool automatic = false}) {
    _cancel();
    _healthy?.cancel();
    _healthy = null;
    _room = room;
    _playback = const PlaybackState();
    _resolving = true;
    _unavailable = false;
    _replay = false;
    _held = false;
    if (!automatic) {
      _attempted.clear();
      _exhausted = false;
    }
    _group.claim(_owner, room);
  }

  /// Supplies actual controller and player state, never inferred UI text.
  void update({
    required LiveRoom room,
    required PlaybackState playback,
    required bool resolving,
    required bool unavailable,
    bool replay = false,
  }) {
    if (_disposed) return;
    _room = room;
    _group.claim(_owner, room);
    _playback = playback;
    _resolving = resolving;
    _unavailable = unavailable;
    _replay = replay;
    if (playback.status == PlaybackStatus.paused ||
        (playback.status == PlaybackStatus.stopped && !resolving && !unavailable && !room.isExplicitlyOfflineNow)) {
      _held = true;
    } else if (playback.status == PlaybackStatus.opening || playback.status == PlaybackStatus.playing) {
      _held = false;
    }
    if (store.settings.get(Settings.autoSwitchLiveFollows) &&
        playback.status == PlaybackStatus.playing &&
        room.isLiveNow &&
        !replay &&
        !unavailable) {
      _healthy ??= Timer(const Duration(seconds: 30), () {
        _healthy = null;
        _attempted.clear();
        _exhausted = false;
      });
    } else {
      _healthy?.cancel();
      _healthy = null;
    }
    _evaluate();
  }

  /// Pauses candidate lookups while another page temporarily owns playback.
  void suspend({required bool value}) {
    _suspended = value;
    _evaluate();
  }

  /// Empties a reusable cell and releases its reservation.
  void clear() {
    _cancel();
    _healthy?.cancel();
    _healthy = null;
    _room = null;
    _attempted.clear();
    _exhausted = false;
    _group.release(_owner);
  }

  bool get _eligible {
    final room = _room;
    if (_disposed || _suspended || _held || _resolving || _exhausted || room == null) return false;
    if (!store.settings.get(Settings.autoSwitchLiveFollows) || !maySwitch()) return false;
    if (_replay || room.catchUp.isActive || _playback.onDemand || room.effectiveLiveStatus == LiveStatus.replay) {
      return false;
    }
    if (_playback.status == PlaybackStatus.paused || _playback.recovering) return false;
    if (_playback.error case PlayerException(code: networkLostCode)) return false;
    return room.isExplicitlyOfflineNow || _unavailable || _playback.status == PlaybackStatus.error;
  }

  void _evaluate() {
    if (!_eligible) {
      _cancel();
    } else if (!_searching && _pending == null) {
      // Avoid replacing widgets inside a synchronous controller notification.
      _pending = Timer(const Duration(seconds: 1), () {
        _pending = null;
        if (_eligible) unawaited(_next());
      });
    }
  }

  void _cancel() {
    if (_checking case final identity?) _attempted.remove(identity);
    _checking = null;
    _epoch++;
    _pending?.cancel();
    _pending = null;
    _searching = false;
  }

  bool _current(int epoch) => epoch == _epoch && _eligible;

  Future<void> _next() async {
    final epoch = ++_epoch;
    _searching = true;
    final current = _room!;
    _attempted.add(current.identityKey);
    try {
      final follows = await store.follows.all().timeout(lookupTimeout);
      if (!_current(epoch)) return;
      final at = follows.indexWhere(current.hasSameIdentity);
      final ordered = at < 0 ? follows : [...follows.skip(at + 1), ...follows.take(at + 1)];
      for (final candidate in ordered) {
        if (!_current(epoch)) return;
        if (!candidate.isLiveNow ||
            _attempted.contains(candidate.identityKey) ||
            !_group.available(_owner, candidate)) {
          continue;
        }
        final site = siteOf(candidate.platform);
        if (site == null) continue;
        _attempted.add(candidate.identityKey);
        _checking = candidate.identityKey;
        LiveRoom detail;
        try {
          detail = await site.getRoomDetail(roomId: candidate.roomId).timeout(lookupTimeout);
        } on TimeoutException {
          if (epoch == _epoch) _checking = null;
          // A slow or lost network must not produce a cascade of room opens.
          break;
        } on Object {
          if (epoch == _epoch) _checking = null;
          continue;
        }
        if (!_current(epoch)) return;
        if (!detail.isLiveNow || detail.isRestricted || !_group.available(_owner, detail)) {
          _checking = null;
          continue;
        }
        final followed = await store.follows.contains(candidate).timeout(lookupTimeout);
        if (!_current(epoch)) return;
        _checking = null;
        if (!followed || !_group.available(_owner, detail)) continue;
        detail = detail.fillFromDetail(candidate);
        _attempted.add(detail.identityKey);
        _group.claim(_owner, detail);
        onSwitch(detail);
        return;
      }
      if (_current(epoch)) {
        _exhausted = true;
        onExhausted?.call();
      }
    } on Object {
      if (_current(epoch)) {
        _exhausted = true;
        onExhausted?.call();
      }
    } finally {
      if (epoch == _epoch) {
        _checking = null;
        _searching = false;
      }
    }
  }

  /// Cancels pending work; late platform responses cannot replace another room.
  void dispose() {
    _disposed = true;
    _cancel();
    _healthy?.cancel();
    unawaited(_settings.cancel());
    _group.release(_owner);
  }
}
