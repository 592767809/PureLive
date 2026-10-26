import 'dart:async';

import 'package:flutter/material.dart';
import 'package:live_ui/live_ui.dart';
import 'package:pure_live/features/settings/settings_model.dart';
import 'package:pure_live/features/settings/settings_section_view.dart';
import 'package:pure_live/i18n/i18n.dart';
import 'package:pure_live/shared/danmaku/chat_list_settings.dart';
import 'package:pure_live/shared/danmaku/danmaku_settings_content.dart';
import 'package:pure_live/shared/danmaku/setting_rows.dart';
import 'package:pure_live/tv/settings/tv_settings_style.dart';
import 'package:pure_live/tv/tv_theme.dart';
import 'package:pure_live/tv/widgets/tv_page_header.dart';

/// A page of the TV settings (A17.9 c3, c4): the title, then [child] in the
/// TV's safe area (48 and 28 of the 960 × 540 panel); the first focusable
/// of [child] has the focus when it opens, and Back goes back onto the row
/// that opened it.
class TvSettingsScaffold extends StatefulWidget {
  /// Creates the page.
  const new({required this.title, required this.child, this.pageKey, this.contentHasHeader = false, super.key});

  /// The title.
  final String title;

  /// The content.
  final Widget child;

  /// The scaffold's key (`tv-settings-page-<name>`).
  final Key? pageKey;

  /// The shared page supplies a header through [SettingsPageHeaderScope].
  final bool contentHasHeader;

  @override
  State<TvSettingsScaffold> createState() => _TvSettingsScaffoldState();
}

class _TvSettingsScaffoldState extends State<TvSettingsScaffold> {
  final FocusScopeNode _body = FocusScopeNode(debugLabel: 'tv settings page', skipTraversal: true);
  bool _focusedInitially = false;

  @override
  void initState() {
    super.initState();
    FocusManager.instance.addListener(_followFocus);
    _focusFirst();
  }

  void _focusFirst() {
    WidgetsBinding.instance.addPostFrameCallback(
      (_) => scheduleMicrotask(() {
        if (!mounted || _focusedInitially || !(ModalRoute.of(context)?.isCurrent ?? true)) return;
        final primary = FocusManager.instance.primaryFocus;
        if (_body.hasFocus && primary is! FocusScopeNode) {
          _focusedInitially = true;
          return;
        }
        for (final node in _body.traversalDescendants) {
          if (node is! FocusScopeNode &&
              node.context != null &&
              node.context!.findAncestorWidgetOfExactType<TvPageHeader>() == null) {
            _focusedInitially = true;
            node.requestFocus();
            return;
          }
        }
        // A shared page may load for many frames before attaching targets.
        // Wait on its next actual frame; never request frames while idle.
        _focusFirst();
      }),
    );
  }

  void _followFocus() {
    if (!_body.hasFocus) return;
    final target = FocusManager.instance.primaryFocus?.context;
    if (target == null || Scrollable.maybeOf(target) == null) return;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted && target.mounted) {
        Scrollable.ensureVisible(target, alignmentPolicy: ScrollPositionAlignmentPolicy.keepVisibleAtEnd).ignore();
      }
    });
  }

  @override
  void dispose() {
    FocusManager.instance.removeListener(_followFocus);
    _body.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final scale = TvScale.of(context);
    return Scaffold(
      key: widget.pageKey,
      backgroundColor: TvTheme.pageOf(context),
      body: Padding(
        padding: EdgeInsets.symmetric(horizontal: scale.px(96), vertical: scale.px(56)),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            if (!widget.contentHasHeader) ...[
              TvPageHeader(title: widget.title, subtitle: i18n('tv_menu_settings')),
              SizedBox(height: scale.px(16)),
            ],
            Expanded(
              child: FocusScope(
                node: _body,
                child: TvSettingsStyle(
                  child: SettingsPageHeaderScope(
                    builder: _header,
                    child: Theme(
                      data: Theme.of(context).copyWith(scaffoldBackgroundColor: OnVideoColors.clear),
                      child: widget.child,
                    ),
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  PreferredSizeWidget _header(
    BuildContext context, {
    required String title,
    String? subtitle,
    List<Widget> actions = const [],
    PreferredSizeWidget? bottom,
  }) {
    final scale = TvScale.of(context);
    return PreferredSize(
      preferredSize: Size.fromHeight(scale.pxText(76) + (bottom?.preferredSize.height ?? 0)),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          TvPageHeader(title: title, subtitle: subtitle ?? i18n('tv_menu_settings'), actions: actions),
          SizedBox(height: scale.px(16)),
          ?bottom,
        ],
      ),
    );
  }
}

/// One page of the TV settings (A17.9 c2–c6): the phone's rows of
/// [section] (the catalogue, so the words, icons and order are the phone's)
/// in their TV look, one column at most 720 wide in the middle.
class TvSettingsSectionPage extends StatelessWidget {
  /// Creates the page.
  const new({required this.section, super.key});

  /// The page shown.
  final SettingsSection section;

  @override
  Widget build(BuildContext context) => TvSettingsScaffold(
    pageKey: ValueKey('tv-settings-page-${section.name}'),
    title: i18n(section.titleKey),
    child: SettingsSectionView(section: section),
  );
}

/// A TV settings page of its own content, one column at most 720 wide in
/// the middle, scrolling.
class TvSettingsColumn extends StatelessWidget {
  /// Creates the column.
  const new({required this.children, super.key});

  /// The rows and groups.
  final List<Widget> children;

  @override
  Widget build(BuildContext context) => Align(
    alignment: Alignment.topCenter,
    child: ConstrainedBox(
      constraints: BoxConstraints(maxWidth: TvScale.of(context).px(1440)),
      child: ListView(children: children),
    ),
  );
}

/// "弹幕" of the TV settings (A17.9 c13, D1 A): the phone's danmaku settings
/// (`DanmakuSettingsContent`, the same as the room's panel) with the chat
/// list group; no floating-window group, a TV has no floating windows.
class TvDanmakuSettingsPage extends StatelessWidget {
  /// Creates the page.
  const new({super.key});

  @override
  Widget build(BuildContext context) => TvSettingsScaffold(
    pageKey: const ValueKey('tv-settings-page-danmaku'),
    title: i18n(SettingsSection.danmaku.titleKey),
    child: Align(
      alignment: Alignment.topCenter,
      child: ConstrainedBox(
        constraints: BoxConstraints(maxWidth: TvScale.of(context).px(1440)),
        child: DanmakuSettingsContent(
          hint: i18n('danmaku_settings_live_hint'),
          extra: [PanelGroupTitle(i18n('danmaku_list')), const ChatListSettings()],
        ),
      ),
    ),
  );
}
