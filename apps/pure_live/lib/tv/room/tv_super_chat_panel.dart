import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:pure_live/features/live_play/danmaku/super_chat_panel.dart';
import 'package:pure_live/features/live_play/logic/room_controller.dart';
import 'package:pure_live/tv/tv_theme.dart';

/// The same super-chat panel with remote scrolling, without channel keys.
class TvSuperChatPanel extends StatefulWidget {
  /// Creates the panel.
  const new({required this.controller, required this.onClose, this.focusNode, super.key});

  /// The current room; the panel never opens another playback session.
  final LiveRoomController controller;

  /// Closes only the panel.
  final VoidCallback onClose;

  /// The page focuses this after mounting the panel.
  final FocusNode? focusNode;

  @override
  State<TvSuperChatPanel> createState() => _TvSuperChatPanelState();
}

class _TvSuperChatPanelState extends State<TvSuperChatPanel> {
  final ScrollController _scroll = ScrollController();

  @override
  void dispose() {
    _scroll.dispose();
    super.dispose();
  }

  KeyEventResult _key(FocusNode node, KeyEvent event) {
    if (event is KeyUpEvent) return KeyEventResult.ignored;
    final key = event.logicalKey;
    final down = key == LogicalKeyboardKey.arrowDown || key == LogicalKeyboardKey.pageDown;
    final up = key == LogicalKeyboardKey.arrowUp || key == LogicalKeyboardKey.pageUp;
    if (!down && !up) return KeyEventResult.ignored;
    if (_scroll.hasClients) {
      final page = key == LogicalKeyboardKey.pageDown || key == LogicalKeyboardKey.pageUp;
      final step = page ? _scroll.position.viewportDimension * 0.8 : 120.0;
      _scroll.jumpTo((_scroll.offset + (down ? step : -step)).clamp(0.0, _scroll.position.maxScrollExtent));
    }
    return KeyEventResult.handled;
  }

  @override
  Widget build(BuildContext context) => MediaQuery(
    data: MediaQuery.of(context)
        .copyWith(textScaler: TextScaler.linear(MediaQuery.textScalerOf(context).scale(1) * TvScale.of(context).unit)),
    child: Focus(
      focusNode: widget.focusNode,
      autofocus: true,
      onKeyEvent: _key,
      child: RoomSuperChatPanel(
        key: const ValueKey('panel-super-chats'),
        controller: widget.controller,
        scrollController: _scroll,
        onClose: widget.onClose,
      ),
    ),
  );
}
