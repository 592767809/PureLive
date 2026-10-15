import 'package:flutter/material.dart';
import 'package:pure_live/features/settings/settings_model.dart';
import 'package:pure_live/features/settings/settings_section_view.dart';
import 'package:pure_live/i18n/i18n.dart';
import 'package:pure_live/tv/settings/tv_settings_style.dart';
import 'package:pure_live/tv/tv_theme.dart';
import 'package:pure_live/tv/widgets/tv_page_header.dart';

/// One page of the TV settings (A17.9 c2–c6): the phone's rows of
/// [section] (the catalogue, so the words, icons and order are the phone's)
/// in their TV look, in the TV's safe area (48 and 28 of the 960 × 540
/// panel), one column at most 720 wide in the middle. The first row has the
/// focus when it opens; Back goes back to the catalogue, onto the row that
/// opened it.
class TvSettingsSectionPage extends StatefulWidget {
  /// Creates the page.
  const new({required this.section, super.key});

  /// The page shown.
  final SettingsSection section;

  @override
  State<TvSettingsSectionPage> createState() => _TvSettingsSectionPageState();
}

class _TvSettingsSectionPageState extends State<TvSettingsSectionPage> {
  final FocusNode _body = FocusNode(debugLabel: 'tv settings page', skipTraversal: true, canRequestFocus: false);

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      for (final node in _body.traversalDescendants) {
        if (node.canRequestFocus) {
          node.requestFocus();
          return;
        }
      }
    });
  }

  @override
  void dispose() {
    _body.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final palette = TvTheme.of(context);
    final scale = TvScale.of(context);
    return Scaffold(
      key: ValueKey('tv-settings-page-${widget.section.name}'),
      backgroundColor: palette.background,
      body: Padding(
        padding: EdgeInsets.symmetric(horizontal: scale.px(96), vertical: scale.px(56)),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            TvPageHeader(title: i18n(widget.section.titleKey), subtitle: i18n('tv_menu_settings')),
            SizedBox(height: scale.px(16)),
            Expanded(
              child: Focus(
                focusNode: _body,
                child: TvSettingsStyle(child: SettingsSectionView(section: widget.section)),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
