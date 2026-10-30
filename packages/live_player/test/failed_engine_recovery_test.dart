import 'dart:async';

import 'package:fake_async/fake_async.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:live_core/live_core.dart';
import 'package:live_media/live_media.dart';
import 'package:live_player/live_player.dart';

import 'support/fake_engine.dart';

PlaybackRequest _request(String host) => PlaybackRequest(
  site: 'fixture',
  plan: PlaybackPlan.of(LivePlayUrlResolution.lines([LivePlayLine('https://$host.example/live.flv')])),
);

void main() {
  test('G02.11: an immediate room switch cannot wait forever behind a queued volume command', () {
    fakeAsync((async) {
      final pending = Completer<void>();
      final engines = <FakeEngine>[];
      final session = PlaybackSession(
        opener: MediaOpener(),
        engine: () async {
          final engine = FakeEngine();
          engines.add(engine);
          return engine;
        },
      );
      unawaited(session.open(_request('good')));
      async.flushMicrotasks();
      engines.first.onOpen = (_) => pending.future;
      unawaited(session.open(_request('failed')));
      async.flushMicrotasks();
      engines.first.onVolume = (_) => pending.future;
      unawaited(session.open(_request('good')));
      async.elapse(const Duration(seconds: 19));
      expect(engines, hasLength(2));
      expect(session.state.status, PlaybackStatus.playing);
      pending.complete();
      async.flushMicrotasks();
      expect(session.engine, same(engines.last));
      expect(engines.first.opens, hasLength(2), reason: 'the obsolete volume reply must not open another source');
      unawaited(session.dispose());
      async.flushMicrotasks();
    });
  });

  test('G02.11: engine initialization has a deadline without allocating replacements repeatedly', () {
    fakeAsync((async) {
      final creating = Completer<PlayerEngine>();
      var creations = 0;
      final session = PlaybackSession(
        opener: MediaOpener(),
        engine: () {
          creations++;
          return creating.future;
        },
      );
      unawaited(session.open(_request('good')));
      async.elapse(const Duration(seconds: 19));
      expect(session.state.status, PlaybackStatus.error);
      expect((session.state.error! as PlayerException).code, 'engine_create_timeout');
      unawaited(session.retry());
      async.elapse(const Duration(seconds: 19));
      expect(creations, 1);
      creating.complete(FakeEngine());
      async.flushMicrotasks();
      unawaited(session.retry());
      async.flushMicrotasks();
      expect(session.state.status, PlaybackStatus.playing);
      unawaited(session.dispose());
      async.flushMicrotasks();
    });
  });

  test('G02.11: a stuck native disposal cannot block the replacement engine', () {
    fakeAsync((async) {
      final pendingOpen = Completer<void>();
      final pendingDispose = Completer<void>();
      final engines = <FakeEngine>[];
      final session = PlaybackSession(
        opener: MediaOpener(),
        engine: () async {
          final engine = FakeEngine();
          engines.add(engine);
          if (engines.length == 1) {
            engine
              ..onOpen = ((_) => pendingOpen.future)
              ..onDispose = (() => pendingDispose.future);
          }
          return engine;
        },
      );
      unawaited(session.open(_request('good')));
      async.elapse(const Duration(seconds: 24));
      expect(engines, hasLength(2));
      expect(session.state.status, PlaybackStatus.playing);
      pendingOpen.complete();
      pendingDispose.complete();
      async.flushMicrotasks();
      expect(identical(session.engine, engines.last), isTrue);
      expect(session.state.status, PlaybackStatus.playing);
      unawaited(session.dispose());
      async.flushMicrotasks();
    });
  });

  test('G02.11: stalled retirements cap native allocations and late cleanup permits a later retry', () {
    fakeAsync((async) {
      final pendingOpen = Completer<void>();
      final pendingDispose = Completer<void>();
      final engines = <FakeEngine>[];
      final session = PlaybackSession(
        opener: MediaOpener(),
        timings: const SessionTimings(
          sourceOpen: Duration(seconds: 1),
          engineRelease: Duration(seconds: 1),
          liveRetryDelays: [],
        ),
        engine: () async {
          final engine = FakeEngine();
          engines.add(engine);
          if (engines.length <= 2) {
            engine
              ..onOpen = ((_) => pendingOpen.future)
              ..onDispose = (() => pendingDispose.future);
          }
          return engine;
        },
      );
      for (var attempt = 0; attempt < 5; attempt++) {
        unawaited(session.open(_request('good')));
        async.elapse(const Duration(seconds: 4));
      }
      expect(engines, hasLength(2), reason: 'repeated user retries must not allocate unlimited native players');
      expect(session.state.status, PlaybackStatus.error);
      expect((session.state.error! as PlayerException).code, 'engine_release_pending');
      pendingOpen.complete();
      pendingDispose.complete();
      async.flushMicrotasks();
      unawaited(session.retry());
      async.flushMicrotasks();
      expect(engines, hasLength(3));
      expect(session.state.status, PlaybackStatus.playing);
      unawaited(session.dispose());
      async.flushMicrotasks();
    });
  });

  test('G02.11: an unfinished engine open cannot poison all later room opens', () {
    fakeAsync((async) {
      final pending = Completer<void>();
      final engines = <FakeEngine>[];
      var poisoned = false;
      final session = PlaybackSession(
        opener: MediaOpener(),
        engine: () async {
          final engine = FakeEngine();
          engines.add(engine);
          if (engines.length == 1) {
            engine.onOpen = (media) async {
              poisoned |= media.uri.host == 'failed.example';
              if (poisoned) {
                await pending.future;
              } else {
                engine.playing();
              }
            };
          }
          return engine;
        },
      );
      unawaited(session.open(_request('good')));
      async.flushMicrotasks();
      expect(session.state.status, PlaybackStatus.playing);
      unawaited(session.open(_request('failed')));
      async.elapse(const Duration(seconds: 19));
      unawaited(session.open(_request('good')));
      async.flushMicrotasks();
      expect(session.state.status, PlaybackStatus.playing, reason: 'returning to A must not queue behind stuck B');
      expect(engines.first.disposed, isTrue);
      expect(engines, hasLength(2));
      pending.complete();
      async.flushMicrotasks();
      expect(session.state.status, PlaybackStatus.playing, reason: 'late B completion must not replace A');
      unawaited(session.dispose());
      async.flushMicrotasks();
    });
  });

  test('G02.11: a buffering engine that cannot recover is replaced once', () {
    fakeAsync((async) {
      final engines = <FakeEngine>[];
      final session = PlaybackSession(
        opener: MediaOpener(),
        engine: () async {
          final engine = FakeEngine();
          engines.add(engine);
          if (engines.length == 1) {
            engine.onOpen = (_) async {
              engine
                ..emit(const EnginePlaying(playing: true))
                ..emit(const EngineBuffering(buffering: true));
            };
          }
          return engine;
        },
      );
      unawaited(session.open(_request('good')));
      async.elapse(const Duration(seconds: 13));
      expect(engines, hasLength(2));
      expect(engines.first.disposed, isTrue);
      expect(session.state.status, PlaybackStatus.playing);
      unawaited(session.dispose());
      async.flushMicrotasks();
    });
  });

  test('G02.11: a normal transport error keeps the healthy engine and advances the line', () {
    fakeAsync((async) {
      final engines = <FakeEngine>[];
      final session = PlaybackSession(
        opener: MediaOpener(),
        engine: () async {
          final engine = FakeEngine();
          engines.add(engine);
          return engine;
        },
      );
      unawaited(
        session.open(
          PlaybackRequest(
            site: 'fixture',
            plan: PlaybackPlan.of(
              LivePlayUrlResolution.lines(const [
                LivePlayLine('https://a.example/live.flv'),
                LivePlayLine('https://b.example/live.flv'),
              ]),
            ),
          ),
        ),
      );
      async.flushMicrotasks();
      engines.single.emit(
        const EngineError(PlayerException(message: '404', type: PlayerErrorType.network, code: 'http_404')),
      );
      async.flushMicrotasks();
      expect(engines, hasLength(1));
      expect(engines.single.disposed, isFalse);
      expect(engines.single.opens.last.uri.host, 'b.example');
      unawaited(session.dispose());
      async.flushMicrotasks();
    });
  });
}
