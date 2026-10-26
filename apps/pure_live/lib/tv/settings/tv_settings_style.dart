import 'package:flutter/material.dart';
import 'package:live_ui/live_ui.dart';
import 'package:pure_live/features/settings/settings_dialogs.dart';
import 'package:pure_live/shared/settings/settings_text_presenter.dart';
import 'package:pure_live/tv/phone/tv_phone_dialogs.dart';
import 'package:pure_live/tv/settings/tv_color_grid.dart';
import 'package:pure_live/tv/widgets/tv_dialogs.dart';

/// The phone's settings rows and dialogs in their TV look (A17.9 c2, c7):
/// the rows a step larger, with a focus frame inside their bounds, ← off
/// and → on on a switch; a dialog of options is the TV's choice dialog
/// (the current one in the primary colour with a tick and the focus).
class TvSettingsStyle extends StatelessWidget {
  /// Wraps [child].
  const new({required this.child, super.key});

  /// The page.
  final Widget child;

  @override
  Widget build(BuildContext context) => SettingsRowStyle(
    tv: true,
    child: AppOptionPresenter(
      present: presentTvOptions,
      child: SettingsColorPresenter(
        pick: showTvColorGrid,
        child: SettingsTextPresenter(
          prompt: _editText,
          child: TvPhoneBridge(child: child),
        ),
      ),
    ),
  );
}

Future<String?> _editText(BuildContext context, {required String title, required String initial, int? maxLength}) =>
    TvTextInput.prompt(context, title: title, text: initial, maxLength: maxLength);

/// [AppOptionRequest] as [showTvChoice].
Future<Object?> presentTvOptions(BuildContext context, AppOptionRequest request) => showTvChoice<Object?>(
  context,
  title: request.title ?? '',
  subtitle: request.message,
  current: request.selected,
  options: [
    for (final option in request.options)
      TvChoice<Object?>(value: option.value, label: option.label, description: option.description),
  ],
);
