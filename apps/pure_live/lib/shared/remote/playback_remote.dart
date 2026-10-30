import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:math';

import 'package:flutter/foundation.dart';
import 'package:pure_live/shared/net/lan_address.dart';
import 'package:pure_live/shared/net/mdns_peers.dart';
import 'package:pure_live/shared/remote/remote_access.dart';
import 'package:pure_live/shared/remote/remote_web.dart';

String _nonce() => base64Url.encode(List<int>.generate(32, (_) => Random.secure().nextInt(256))).replaceAll('=', '');

/// A page-owned playback target. Callbacks must read the current controller,
/// rather than capturing one which may have been replaced by a room switch.
final class RemotePlaybackTarget {
  /// Registers a snapshot and a fixed set of commands.
  new({required this.available, required this.snapshot, required this.execute}) : id = _nonce();

  /// Identifies this page instance; a command for a removed page cannot spill
  /// over to the next page that happens to use the same route.
  final String id;

  /// Whether this page can currently receive remote input.
  final bool Function() available;

  /// Public display fields only, never a platform response or cookie.
  final Map<String, Object?> Function() snapshot;

  /// Runs one advertised command, returning false when it cannot apply.
  final Future<bool> Function(String command, double? value) execute;
}

/// Explicitly enabled LAN playback control. Pairing grants playback commands
/// only; this protocol has no settings, account, file or arbitrary URL endpoint.
final class PlaybackRemote extends ChangeNotifier {
  /// Creates a stopped receiver. [now] is replaceable for expiry tests.
  new({DateTime Function()? now}) : _now = now ?? DateTime.now;

  final DateTime Function() _now;
  final List<RemotePlaybackTarget> _targets = [];
  final Map<String, DateTime> _sessions = {};
  HttpServer? _server;
  RawDatagramSocket? _discovery;
  String _code = '';
  int _wrongCodes = 0;
  DateTime? _blockedUntil;
  bool _busy = false;
  int _generation = 0;
  Future<void>? _starting;
  final MdnsPeers _mdns = BonsoirPeers(type: '_purelive-remote._tcp');

  /// Supported commands; the target advertises its applicable subset.
  static const commands = {
    'play',
    'pause',
    'refresh',
    'previous',
    'next',
    'volume',
    'mute',
    'fullscreen',
    'danmaku',
    'up',
    'down',
    'left',
    'right',
    'ok',
    'back',
  };

  /// Discovery is separate from settings sync's UDP port 39889.
  static const discoveryPort = 39891;

  /// Ephemeral id, independent of the account or settings-sync identity.
  final String id = _nonce();

  /// The six-digit pairing code shown only on the receiving device.
  String get code => _code;

  /// Whether remote commands are currently accepted.
  bool get running => _server != null;

  /// Bound HTTP port; zero while stopped.
  int get port => _server?.port ?? 0;

  /// The selected LAN IPv4 address, without account data.
  String address = '';

  /// Browser and QR entry point. The URL deliberately carries no pairing code.
  String get url => running && address.isNotEmpty ? 'http://$address:$port/' : '';

  /// Number of paired sessions still within their twelve-hour lifetime.
  int get pairedCount {
    _expire();
    return _sessions.length;
  }

  /// Resolves a supported live-room share text and opens it. The generation
  /// check must be tested again after any asynchronous link resolution.
  Future<bool> Function(String text, bool Function() authorized)? onLink;

  /// Adds a page. Newest visible targets take precedence over covered pages.
  void register(RemotePlaybackTarget target) => _targets.add(target);

  /// Removes precisely [target], including a page underneath a newer player.
  void unregister(RemotePlaybackTarget target) => _targets.remove(target);

  RemotePlaybackTarget? get _target => _targets.reversed.where((target) => target.available()).firstOrNull;

  /// Enables this receiver until explicitly stopped or the app exits.
  Future<void> start({InternetAddress? bind, bool discovery = true}) =>
      _starting ??= _start(bind: bind, discovery: discovery).whenComplete(() => _starting = null);

  Future<void> _start({required bool discovery, InternetAddress? bind}) async {
    if (running) return;
    final generation = ++_generation;
    await ensurePlaybackRemoteAccess();
    if (generation != _generation) return;
    final server = await HttpServer.bind(bind ?? InternetAddress.anyIPv4, 0);
    if (generation != _generation) {
      await server.close(force: true);
      return;
    }
    _server = server;
    address = bestLanAddress(await localIpv4Addresses());
    if (!identical(_server, server)) return;
    revoke();
    server.listen((request) => unawaited(_handle(request)));
    if (discovery) {
      await _startDiscovery(_generation);
      await _mdns.start(
        name: 'PureLive ${Platform.operatingSystem}',
        port: port,
        attributes: {
          'id': id,
          'name': 'PureLive ${Platform.operatingSystem}',
          'platform': Platform.operatingSystem,
          'ip': address,
        },
        found: (_) {},
        lost: (_) {},
      );
      if (!identical(_server, server)) await _mdns.stop();
    }
    notifyListeners();
  }

  Future<void> _startDiscovery(int generation) async {
    try {
      final socket = await RawDatagramSocket.bind(InternetAddress.anyIPv4, discoveryPort);
      if (generation != _generation || !running) {
        socket.close();
        return;
      }
      _discovery = socket;
      socket.listen((event) {
        if (event != RawSocketEvent.read) return;
        Datagram? packet;
        while ((packet = socket.receive()) != null) {
          final message = packet!;
          if (message.data.length != 27 ||
              ascii.decode(message.data, allowInvalid: true) != 'purelive-remote-discover-v1') {
            continue;
          }
          final data = utf8.encode(
            jsonEncode({
              'protocol': 'purelive-remote-v1',
              'id': id,
              'name': 'PureLive ${Platform.operatingSystem}',
              'port': port,
            }),
          );
          socket.send(data, message.address, message.port);
        }
      });
    } on Object {
      // Manual address / browser / QR remain usable on isolated Wi-Fi or when
      // another local instance already owns the UDP discovery port.
    }
  }

  /// Revokes every paired controller immediately and rotates the pairing code.
  void revoke() {
    _generation++;
    _sessions.clear();
    _code = (100000 + Random.secure().nextInt(900000)).toString();
    _wrongCodes = 0;
    notifyListeners();
  }

  void _expire() => _sessions.removeWhere((_, expires) => !expires.isAfter(_now()));

  bool _authorized(HttpRequest request) {
    _expire();
    final auth = request.headers.value(HttpHeaders.authorizationHeader) ?? '';
    return auth.startsWith('Bearer ') && _sessions.containsKey(auth.substring(7));
  }

  Future<Map<String, dynamic>> _json(HttpRequest request) async {
    if (request.headers.contentType?.mimeType != 'application/json') throw const FormatException('json required');
    final bytes = <int>[];
    await for (final chunk in request.timeout(const Duration(seconds: 10))) {
      bytes.addAll(chunk);
      if (bytes.length > 16384) throw const FormatException('oversized');
    }
    final value = jsonDecode(utf8.decode(bytes));
    if (value is! Map<String, dynamic>) throw const FormatException('object required');
    return value;
  }

  Future<void> _handle(HttpRequest request) async {
    final response = request.response
      ..persistentConnection = false
      ..headers.set(HttpHeaders.cacheControlHeader, 'no-store')
      ..headers.set('x-content-type-options', 'nosniff')
      ..headers.set('x-frame-options', 'DENY')
      ..headers.set('referrer-policy', 'no-referrer');
    try {
      // Consume bounded JSON before replying, including rejected origins and
      // sessions. Leaving a POST body unread can reset a reused HTTP connection.
      final payload = request.method == 'POST' ? await _json(request) : null;
      final origin = request.headers.value('origin');
      final host = request.headers.value(HttpHeaders.hostHeader);
      if (origin != null && origin != 'http://$host') {
        response.statusCode = HttpStatus.forbidden;
      } else if (request.method == 'GET' && request.uri.path == '/') {
        response.headers.contentType = ContentType.html;
        response.headers.set(
          'content-security-policy',
          "default-src 'none'; script-src 'unsafe-inline'; style-src 'unsafe-inline'; connect-src 'self'; frame-ancestors 'none'; base-uri 'none'; form-action 'none'",
        );
        response.write(remoteControlHtml());
      } else if (request.method == 'POST' && request.uri.path == '/api/pair') {
        final data = payload!;
        if (_blockedUntil?.isAfter(_now()) ?? false) {
          response.statusCode = HttpStatus.tooManyRequests;
        } else if (data['code'] != _code) {
          response.statusCode = HttpStatus.forbidden;
          if (++_wrongCodes >= 10) {
            _blockedUntil = _now().add(const Duration(minutes: 1));
            revoke();
          }
        } else if (pairedCount >= 8) {
          response.statusCode = HttpStatus.tooManyRequests;
        } else {
          final token = _nonce();
          _sessions[token] = _now().add(const Duration(hours: 12));
          response.headers.contentType = ContentType.json;
          response.write(jsonEncode({'token': token, 'name': 'PureLive ${Platform.operatingSystem}'}));
          notifyListeners();
        }
      } else if (!_authorized(request)) {
        response.statusCode = HttpStatus.unauthorized;
      } else if (request.method == 'GET' && request.uri.path == '/api/status') {
        final target = _target;
        response.headers.contentType = ContentType.json;
        response.write(jsonEncode({'targetId': target?.id, 'state': target?.snapshot()}));
      } else if (request.method == 'POST' && request.uri.path == '/api/unpair') {
        _sessions.remove(request.headers.value(HttpHeaders.authorizationHeader)!.substring(7));
        notifyListeners();
      } else if (request.method == 'POST' && request.uri.path == '/api/command') {
        final data = payload!;
        final target = _target;
        final command = data['command'];
        final value = data['value'];
        if (!_authorized(request)) {
          response.statusCode = HttpStatus.unauthorized;
        } else if (target == null || target.id != data['targetId']) {
          response.statusCode = HttpStatus.conflict;
        } else if (command is! String ||
            !commands.contains(command) ||
            (value != null && (value is! num || !value.isFinite || value < 0 || value > 1))) {
          response.statusCode = HttpStatus.badRequest;
        } else if (!(target.snapshot()['commands'] as List? ?? const <String>[]).contains(command)) {
          response.statusCode = HttpStatus.conflict;
        } else if (_busy) {
          response.statusCode = HttpStatus.conflict;
        } else {
          _busy = true;
          try {
            if (!await target.execute(command, (value as num?)?.toDouble())) response.statusCode = HttpStatus.conflict;
          } finally {
            _busy = false;
          }
        }
      } else if (request.method == 'POST' && request.uri.path == '/api/link') {
        final data = payload!;
        final text = data['text'];
        if (!_authorized(request)) {
          response.statusCode = HttpStatus.unauthorized;
        } else if (text is! String || text.isEmpty || text.length > 4096) {
          response.statusCode = HttpStatus.badRequest;
        } else if (_busy) {
          response.statusCode = HttpStatus.conflict;
        } else {
          final generation = _generation;
          _busy = true;
          try {
            final opened = await onLink?.call(text, () => running && generation == _generation && _authorized(request));
            if (opened != true) response.statusCode = HttpStatus.unprocessableEntity;
          } finally {
            _busy = false;
          }
        }
      } else {
        response.statusCode = HttpStatus.notFound;
      }
    } on FormatException {
      response.statusCode = HttpStatus.badRequest;
    } on TimeoutException {
      response.statusCode = HttpStatus.requestTimeout;
    } on Object {
      response.statusCode = HttpStatus.serviceUnavailable;
    }
    try {
      await response.close();
    } on Object {
      // The controller may disconnect while a command is being handled.
    }
  }

  /// Disables receiving, revokes all sessions, and closes discovery sockets.
  Future<void> stop() async {
    _generation++;
    final server = _server;
    _server = null;
    _discovery?.close();
    _discovery = null;
    _sessions.clear();
    _code = '';
    await _mdns.stop();
    await server?.close(force: true);
    notifyListeners();
  }
}
