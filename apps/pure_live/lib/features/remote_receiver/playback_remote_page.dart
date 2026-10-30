import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:live_ui/live_ui.dart';
import 'package:pure_live/app/services.dart';
import 'package:pure_live/i18n/i18n.dart';
import 'package:pure_live/routes/route_args.dart';
import 'package:pure_live/shared/qr_scan.dart';
import 'package:pure_live/shared/remote/playback_remote.dart';
import 'package:pure_live/shared/remote/remote_access.dart';
import 'package:pure_live/shared/remote/remote_client.dart';

/// LAN browser/app pairing, link pushes and playback control on every layout.
class PlaybackRemotePage extends ConsumerStatefulWidget {
  /// Creates the remote page.
  const new({required this.route, this.onBack, super.key});

  /// The route which opened this page.
  final RouteArgs route;

  /// Returns from an embedded desktop settings destination.
  final VoidCallback? onBack;

  @override
  ConsumerState<PlaybackRemotePage> createState() => _PlaybackRemotePageState();
}

class _PlaybackRemotePageState extends ConsumerState<PlaybackRemotePage> {
  final _address = TextEditingController();
  final _code = TextEditingController();
  final _link = TextEditingController();
  PlaybackRemoteClient? _client;
  late final PlaybackRemote _receiver;
  List<RemoteControlPeer> _peers = const [];
  Map<String, dynamic>? _status;
  Timer? _timer;
  bool _busy = false;
  bool _polling = false;
  String _message = '';
  double? _dragVolume;

  @override
  void initState() {
    super.initState();
    _receiver = ref.read(appServicesProvider).remoteControl;
    _receiver.addListener(_changed);
    _timer = Timer.periodic(const Duration(seconds: 2), (_) => unawaited(_poll()));
  }

  void _changed() {
    if (mounted) setState(() {});
  }

  @override
  void dispose() {
    _receiver.removeListener(_changed);
    _timer?.cancel();
    final client = _client;
    if (client != null) unawaited(client.disconnect().catchError((Object _) {}));
    _address.dispose();
    _code.dispose();
    _link.dispose();
    super.dispose();
  }

  Future<void> _run(Future<void> Function() action) async {
    if (_busy) return;
    setState(() => _busy = true);
    try {
      await action();
      if (mounted) setState(() => _message = i18n('remote_control_ok'));
    } on RemoteControlAccessDenied {
      if (mounted) setState(() => _message = i18n('remote_control_permission_denied'));
    } on Object {
      if (mounted) setState(() => _message = i18n('remote_control_failed'));
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _poll() async {
    final client = _client;
    if (_polling || _busy || client == null || !client.paired) return;
    _polling = true;
    try {
      final status = await client.status();
      if (mounted && identical(client, _client)) setState(() => _status = status);
    } on Object {
      if (mounted && identical(client, _client)) {
        setState(() {
          _status = null;
          _message = i18n('remote_control_failed');
        });
      }
    } finally {
      _polling = false;
    }
  }

  Future<void> _pair() => _run(() async {
    final uri = remoteControlUri(_address.text);
    if (uri == null) throw const FormatException('invalid receiver');
    final client = PlaybackRemoteClient(uri);
    try {
      await client.pair(_code.text.trim());
      final status = await client.status();
      if (!mounted) {
        client.close();
        return;
      }
      _client?.close();
      _client = client;
      _status = status;
      _code.clear();
    } on Object {
      client.close();
      rethrow;
    }
  });

  Future<void> _command(String command, {double? value}) => _run(() async {
    final target = _status?['targetId'];
    if (target is! String || _client == null) throw StateError('no target');
    await _client!.command(target, command, value: value);
    if (mounted) _status = await _client!.status();
  });

  Future<void> _scan() => _run(() async {
    final text = await scanQrCode(context, hint: i18n('remote_control_scan'));
    if (text == null || !mounted) return;
    final uri = remoteControlUri(text);
    if (uri == null) throw const FormatException('invalid QR');
    _address.text = uri.toString();
  });

  @override
  Widget build(BuildContext context) {
    final state = _status?['state'];
    final fields = state is Map ? state : const <String, Object?>{};
    final available = fields['commands'] is List ? fields['commands'] as List : const <String>[];
    final volume = fields['volume'];
    final selectedVolume = _dragVolume ?? (volume is num ? volume.toDouble().clamp(0.0, 1.0) : 0.5);
    return Scaffold(
      appBar: AppBar(
        title: Text(i18n('remote_control_title')),
        leading: widget.onBack == null ? null : BackButton(onPressed: widget.onBack),
      ),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          Text(i18n('remote_control_receive'), style: Theme.of(context).textTheme.titleLarge),
          SwitchListTile(
            key: const ValueKey('remote-control-enable'),
            title: Text(i18n('remote_control_enable')),
            subtitle: Text(i18n('remote_control_receive_hint')),
            value: _receiver.running,
            onChanged: _busy
                ? null
                : (enabled) => unawaited(
                    _run(() async {
                      if (enabled) {
                        await _receiver.start();
                      } else {
                        await _receiver.stop();
                      }
                    }),
                  ),
          ),
          if (_receiver.running) ...[
            SelectableText(i18n('remote_control_pairing', args: {'code': _receiver.code})),
            if (_receiver.url.isNotEmpty) ...[
              SelectableText(_receiver.url),
              Align(
                alignment: AlignmentDirectional.centerStart,
                child: QrCodeWidget(data: _receiver.url, size: 176),
              ),
              TextButton.icon(
                onPressed: () => unawaited(Clipboard.setData(ClipboardData(text: _receiver.url))),
                icon: const Icon(AppIcons.copy),
                label: Text(i18n('copy')),
              ),
            ] else
              Text(i18n('remote_control_no_lan')),
            Text(i18n('remote_control_sessions', args: {'count': '${_receiver.pairedCount}'})),
            TextButton(onPressed: _receiver.revoke, child: Text(i18n('remote_control_revoke'))),
          ],
          const Divider(height: 32),
          Text(i18n('remote_control_send_title'), style: Theme.of(context).textTheme.titleLarge),
          Text(i18n('remote_control_send_hint')),
          Wrap(
            spacing: 8,
            children: [
              OutlinedButton.icon(
                key: const ValueKey('remote-control-discover'),
                onPressed: _busy
                    ? null
                    : () => unawaited(
                        _run(() async {
                          final peers = await discoverPlaybackRemotes();
                          if (mounted) _peers = peers;
                        }),
                      ),
                icon: const Icon(AppIcons.deviceSync),
                label: Text(i18n('remote_control_discover')),
              ),
              if (QrScan.available)
                OutlinedButton.icon(
                  onPressed: _busy ? null : () => unawaited(_scan()),
                  icon: const Icon(AppIcons.scanQr),
                  label: Text(i18n('remote_control_scan')),
                ),
            ],
          ),
          for (final peer in _peers)
            ListTile(
              title: Text(peer.name),
              subtitle: Text(peer.uri.toString()),
              onTap: () => _address.text = peer.uri.toString(),
            ),
          TextField(
            key: const ValueKey('remote-control-address'),
            controller: _address,
            decoration: InputDecoration(labelText: i18n('remote_control_address')),
            keyboardType: TextInputType.url,
          ),
          TextField(
            key: const ValueKey('remote-control-code'),
            controller: _code,
            keyboardType: TextInputType.number,
            maxLength: 6,
            decoration: InputDecoration(labelText: i18n('remote_control_code')),
          ),
          FilledButton(
            key: const ValueKey('remote-control-pair'),
            onPressed: _busy ? null : () => unawaited(_pair()),
            child: Text(i18n('remote_control_pair')),
          ),
          if (_message.isNotEmpty) Text(_message, key: const ValueKey('remote-control-message')),
          if (_client?.paired ?? false) ...[
            const SizedBox(height: 16),
            Text([fields['nick'], fields['title']].whereType<String>().join(' · ')),
            if (_status?['targetId'] == null) Text(i18n('remote_control_idle')),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: [
                for (final (command, label) in [
                  ('previous', i18n('previous')),
                  ('up', '↑'),
                  ('next', i18n('next')),
                  ('left', '←'),
                  ('ok', 'OK'),
                  ('right', '→'),
                  ('play', i18n('play')),
                  ('down', '↓'),
                  ('pause', i18n('pause')),
                  ('refresh', i18n('refresh')),
                  ('mute', i18n('mute')),
                  ('fullscreen', i18n('fullscreen')),
                  ('danmaku', i18n('danmaku')),
                  ('back', i18n('back')),
                ])
                  OutlinedButton(
                    onPressed: !_busy && available.contains(command) ? () => unawaited(_command(command)) : null,
                    child: Text(label),
                  ),
              ],
            ),
            Slider(
              value: selectedVolume,
              onChanged: !_busy && available.contains('volume') ? (value) => setState(() => _dragVolume = value) : null,
              onChangeEnd: (value) {
                setState(() => _dragVolume = null);
                unawaited(_command('volume', value: value));
              },
            ),
            TextField(
              key: const ValueKey('remote-control-link'),
              controller: _link,
              maxLength: 4096,
              decoration: InputDecoration(labelText: i18n('remote_control_link')),
            ),
            FilledButton(
              onPressed: _busy
                  ? null
                  : () => unawaited(
                      _run(() async {
                        await _client!.sendLink(_link.text.trim());
                        if (mounted) _link.clear();
                      }),
                    ),
              child: Text(i18n('remote_control_send')),
            ),
            TextButton(
              onPressed: _busy
                  ? null
                  : () => unawaited(
                      _run(() async {
                        await _client!.disconnect();
                        _client = null;
                        _status = null;
                      }),
                    ),
              child: Text(i18n('remote_control_unpair')),
            ),
          ],
        ],
      ),
    );
  }
}
