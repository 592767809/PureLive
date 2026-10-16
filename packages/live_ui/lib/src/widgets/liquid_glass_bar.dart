import 'dart:async';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/physics.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:live_ui/src/theme/motion.dart';
import 'package:live_ui/src/widgets/glass.dart';

/// The liquid glass shader (A01.6), loaded once; null where a shader
/// cannot filter the backdrop (Flutter without Impeller, tests) or the
/// shader failed to load.
abstract final class LiquidGlassShader {
  static Future<ui.FragmentProgram?>? _loading;
  static ui.FragmentProgram? _program;

  /// The program once loaded.
  static ui.FragmentProgram? get program => _program;

  /// Loads the program (once); null when it cannot be used here.
  static Future<ui.FragmentProgram?> load() => _loading ??= _load();

  static Future<ui.FragmentProgram?> _load() async {
    if (!ui.ImageFilter.isShaderFilterSupported) return null;
    try {
      return _program = await ui.FragmentProgram.fromAsset('packages/live_ui/shaders/liquid_glass.frag');
    } on Object catch (error) {
      debugPrint('liquid glass: shader not loaded: $error');
      return null;
    }
  }
}

/// A destination of [LiquidGlassBar].
@immutable
class LiquidGlassBarItem {
  /// Creates the destination.
  const new({required this.icon, required this.selectedIcon, required this.label, this.key});

  /// The icon.
  final IconData icon;

  /// The icon while chosen.
  final IconData selectedIcon;

  /// The name under the icon.
  final String label;

  /// The destination's key (tests).
  final Key? key;
}

/// A floating bar of liquid glass (A01.6): a capsule that bends the page
/// behind it at its edges, with a drop of clearer glass over the chosen
/// destination. The drop springs to a tapped destination, stretching as it
/// goes; held and dragged along the bar it follows the finger (heavier past
/// the ends) and settles on the nearest destination when let go.
///
/// Where the shader cannot run ([LiquidGlassShader]) the bar is frosted
/// glass ([blur]) or, without [blur], a plain tint, and the drop a tinted
/// pill.
class LiquidGlassBar extends StatefulWidget {
  /// Creates the bar.
  const new({
    required this.items,
    required this.selectedIndex,
    required this.onSelected,
    this.blur = true,
    this.refraction = true,
    super.key,
  });

  /// The destinations.
  final List<LiquidGlassBarItem> items;

  /// The chosen destination.
  final int selectedIndex;

  /// A destination was chosen.
  final ValueChanged<int> onSelected;

  /// Whether the page behind is blurred.
  final bool blur;

  /// Whether the shader's refraction may be used.
  final bool refraction;

  @override
  State<LiquidGlassBar> createState() => _LiquidGlassBarState();
}

class _LiquidGlassBarState extends State<LiquidGlassBar> with TickerProviderStateMixin {
  /// The drop's centre, in logical pixels from the bar's left.
  late final AnimationController _drop = AnimationController.unbounded(vsync: this);

  /// Held (1) or not (0).
  late final AnimationController _press = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 160),
    reverseDuration: const Duration(milliseconds: 260),
  );

  ui.FragmentProgram? _program = LiquidGlassShader.program;
  double _width = 0;
  bool _placed = false;
  int? _dragIndex;

  @override
  void initState() {
    super.initState();
    if (_program == null && widget.refraction) {
      unawaited(
        LiquidGlassShader.load().then((program) {
          if (mounted && program != null) setState(() => _program = program);
        }),
      );
    }
  }

  @override
  void didUpdateWidget(LiquidGlassBar oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.selectedIndex != widget.selectedIndex && _dragIndex == null) _settle(widget.selectedIndex);
  }

  @override
  void dispose() {
    _drop.dispose();
    _press.dispose();
    super.dispose();
  }

  double get _slot => _width / widget.items.length;

  double _centreOf(int index) => _slot * (index + 0.5);

  int _indexAt(double x) => (x / _slot).floor().clamp(0, widget.items.length - 1);

  bool get _still => MediaQuery.maybeDisableAnimationsOf(context) ?? false;

  void _settle(int index, {double velocity = 0}) {
    final target = _centreOf(index);
    if (_still || _width == 0) {
      _drop.value = target;
      return;
    }
    _drop.animateWith(SpringSimulation(AppMotion.dropSpring, _drop.value, target, velocity));
  }

  void _onDragStart(DragStartDetails details) {
    _drop.stop();
    _dragIndex = _indexAt(details.localPosition.dx);
    _press.forward();
  }

  void _onDragUpdate(DragUpdateDetails details) {
    final min = _centreOf(0);
    final max = _centreOf(widget.items.length - 1);
    final raw = _drop.value + details.delta.dx;
    // Past the first or last destination the drop follows ever more
    // heavily (the lists' rubber band).
    final next = raw < min
        ? min + AppMotion.rubberBand(raw - min, _slot)
        : raw > max
        ? max + AppMotion.rubberBand(raw - max, _slot)
        : raw;
    _drop.value = next;
    final index = _indexAt(next);
    if (index != _dragIndex) {
      _dragIndex = index;
      unawaited(HapticFeedback.selectionClick());
    }
  }

  void _onDragEnd(DragEndDetails details) {
    final velocity = details.velocity.pixelsPerSecond.dx;
    // Where a throw would carry it, a fifth of a second on.
    final index = _indexAt(_drop.value + velocity * 0.2);
    _dragIndex = null;
    _press.reverse();
    _settle(index, velocity: velocity);
    if (index != widget.selectedIndex) widget.onSelected(index);
  }

  void _onTap(int index) {
    unawaited(_press.forward().then((_) => _press.reverse()));
    // The chosen one tapped again is told too: the follows refresh (3.x).
    if (index != widget.selectedIndex) _settle(index);
    widget.onSelected(index);
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final dark = theme.brightness == Brightness.dark;
    final route = ModalRoute.of(context);
    // The glass is placed in screen pixels when painted: it paints again
    // whenever its route moves (A03.5's slide), not only when it changes.
    final moves = Listenable.merge([_drop, _press, ?route?.animation, ?route?.secondaryAnimation]);
    return LayoutBuilder(
      builder: (context, constraints) {
        _width = constraints.maxWidth;
        if (!_placed && _width > 0) {
          _placed = true;
          _drop.value = _centreOf(widget.selectedIndex);
        }
        return GestureDetector(
          behavior: HitTestBehavior.opaque,
          onHorizontalDragStart: _onDragStart,
          onHorizontalDragUpdate: _onDragUpdate,
          onHorizontalDragEnd: _onDragEnd,
          child: _LiquidGlass(
            program: widget.refraction ? _program : null,
            blur: widget.blur,
            dark: dark,
            tint: dark ? scheme.surfaceContainer : scheme.surfaceContainerHighest,
            dropColor: scheme.primary,
            moves: moves,
            drop: _dropRect,
            child: AnimatedBuilder(
              animation: _drop,
              builder: (context, _) => Row(
                children: [
                  for (final (index, item) in widget.items.indexed) Expanded(child: _destination(context, index, item)),
                ],
              ),
            ),
          ),
        );
      },
    );
  }

  /// The drop's rectangle in the bar, stretched along its way by its speed.
  Rect _dropRect() {
    if (_width == 0) return Rect.zero;
    final speed = _still ? 0.0 : _drop.velocity.abs();
    final stretch = (speed / 2400).clamp(0.0, 0.45);
    final lift = 1 + 0.08 * _press.value;
    final width = (_slot - 10) * (1 + stretch) * lift;
    final height = (GlassMetrics.barHeight - 12) * (1 - stretch * 0.25) * lift;
    return Rect.fromCenter(center: Offset(_drop.value, GlassMetrics.barHeight / 2), width: width, height: height);
  }

  Widget _destination(BuildContext context, int index, LiquidGlassBarItem item) {
    final scheme = Theme.of(context).colorScheme;
    // How near the drop is: the colour follows it across the bar.
    final near = _width == 0
        ? (index == widget.selectedIndex ? 1.0 : 0.0)
        : (1 - ((_drop.value - _centreOf(index)).abs() / _slot)).clamp(0.0, 1.0);
    // The icon takes the drop's colour; the name stays onSurface, which
    // keeps 4.5:1 over the glass (the primary colour did not).
    final colour = Color.lerp(scheme.onSurfaceVariant, scheme.primary, near)!;
    final chosen = index == widget.selectedIndex;
    // The whole slot takes the tap; the destination's node is the drop's
    // place at rest (5 in at the sides, 6 at the top and bottom): big
    // enough to tap, and the name read against what is behind it there.
    return GestureDetector(
      key: item.key,
      behavior: HitTestBehavior.opaque,
      excludeFromSemantics: true,
      onTap: () => _onTap(index),
      child: SizedBox(
        height: GlassMetrics.barHeight,
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 6),
          child: Semantics(
            container: true,
            button: true,
            selected: chosen,
            label: item.label,
            onTap: () => _onTap(index),
            excludeSemantics: true,
            // The name grows with the system text at most 1.3× (Material's
            // bar), and the pair shrinks rather than overflow the glass.
            child: MediaQuery.withClampedTextScaling(
              maxScaleFactor: 1.3,
              child: FittedBox(
                fit: BoxFit.scaleDown,
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Icon(near > 0.5 ? item.selectedIcon : item.icon, size: 24, color: colour),
                    const SizedBox(height: 4),
                    Text(
                      item.label,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: Theme.of(context).textTheme.labelMedium?.copyWith(
                        color: scheme.onSurface,
                        fontWeight: chosen ? FontWeight.w600 : FontWeight.w500,
                        height: 1.2,
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _LiquidGlass extends SingleChildRenderObjectWidget {
  const new({
    required this.program,
    required this.blur,
    required this.dark,
    required this.tint,
    required this.dropColor,
    required this.moves,
    required this.drop,
    required super.child,
  });

  final ui.FragmentProgram? program;
  final bool blur;
  final bool dark;
  final Color tint;
  final Color dropColor;
  final Listenable moves;
  final Rect Function() drop;

  @override
  RenderLiquidGlass createRenderObject(BuildContext context) => RenderLiquidGlass(
    program: program,
    blur: blur,
    dark: dark,
    tint: tint,
    dropColor: dropColor,
    moves: moves,
    drop: drop,
    devicePixelRatio: MediaQuery.devicePixelRatioOf(context),
  );

  @override
  void updateRenderObject(BuildContext context, RenderLiquidGlass renderObject) {
    renderObject
      ..program = program
      ..blur = blur
      ..dark = dark
      ..tint = tint
      ..dropColor = dropColor
      ..moves = moves
      ..drop = drop
      ..devicePixelRatio = MediaQuery.devicePixelRatioOf(context);
  }
}

/// Paints [LiquidGlassBar]'s glass under its child: the shader as a
/// backdrop filter clipped to the bar, or the frosted fallback.
class RenderLiquidGlass extends RenderProxyBox {
  /// Creates the render object.
  new({
    required this._program,
    required this._blur,
    required this._dark,
    required this._tint,
    required this._dropColor,
    required this._moves,
    required this._drop,
    required this._devicePixelRatio,
  });

  ui.FragmentProgram? _program;
  ui.FragmentShader? _shader;

  /// See the widget.
  ui.FragmentProgram? get program => _program;
  set program(ui.FragmentProgram? value) {
    if (value == _program) return;
    _program = value;
    _shader?.dispose();
    _shader = null;
    markNeedsPaint();
  }

  bool _blur;

  /// See the widget.
  bool get blur => _blur;
  set blur(bool value) {
    if (value == _blur) return;
    _blur = value;
    markNeedsPaint();
  }

  bool _dark;

  /// See the widget.
  bool get dark => _dark;
  set dark(bool value) {
    if (value == _dark) return;
    _dark = value;
    markNeedsPaint();
  }

  Color _tint;

  /// See the widget.
  Color get tint => _tint;
  set tint(Color value) {
    if (value == _tint) return;
    _tint = value;
    markNeedsPaint();
  }

  Color _dropColor;

  /// See the widget.
  Color get dropColor => _dropColor;
  set dropColor(Color value) {
    if (value == _dropColor) return;
    _dropColor = value;
    markNeedsPaint();
  }

  Listenable _moves;

  /// See the widget.
  Listenable get moves => _moves;
  set moves(Listenable value) {
    if (value == _moves) return;
    if (attached) _moves.removeListener(markNeedsPaint);
    _moves = value;
    if (attached) _moves.addListener(markNeedsPaint);
    markNeedsPaint();
  }

  Rect Function() _drop;

  /// See the widget.
  Rect Function() get drop => _drop;
  set drop(Rect Function() value) {
    _drop = value;
    markNeedsPaint();
  }

  double _devicePixelRatio;

  /// See the widget.
  double get devicePixelRatio => _devicePixelRatio;
  set devicePixelRatio(double value) {
    if (value == _devicePixelRatio) return;
    _devicePixelRatio = value;
    markNeedsPaint();
  }

  final LayerHandle<BackdropFilterLayer> _backdrop = LayerHandle();

  @override
  void attach(PipelineOwner owner) {
    super.attach(owner);
    _moves.addListener(markNeedsPaint);
  }

  @override
  void detach() {
    _moves.removeListener(markNeedsPaint);
    super.detach();
  }

  @override
  void dispose() {
    _backdrop.layer = null;
    _shader?.dispose();
    super.dispose();
  }

  @override
  bool get alwaysNeedsCompositing => true;

  double get _radius => GlassMetrics.barRadius;

  /// How far around the glass the backdrop is read.
  static const double _margin = 16;

  @override
  void paint(PaintingContext context, Offset offset) {
    final bounds = offset & size;
    final drop = _drop().shift(offset);
    final program = _program;
    final filter = program == null ? _frostedFilter() : _shaderFilter(program, drop.shift(-offset));
    if (filter != null) {
      // The backdrop is read a little beyond the glass: the blur and the
      // bent edge need the page around it (read only within the clip,
      // they darkened the edge).
      final clip = program == null ? Offset.zero & size : (Offset.zero & size).inflate(_margin);
      context.pushClipRect(needsCompositing, offset, clip, (context, offset) {
        final layer = (_backdrop.layer ??= BackdropFilterLayer())..filter = filter;
        context.pushLayer(layer, (context, offset) {
          if (program == null) _paintFallback(context.canvas, offset & size, drop.shift(offset - bounds.topLeft));
          super.paint(context, offset);
        }, offset);
      });
      return;
    }
    // Neither: the plain tint.
    _paintFallback(context.canvas, bounds, drop);
    super.paint(context, offset);
  }

  ui.ImageFilter? _frostedFilter() => _blur
      ? ui.ImageFilter.blur(sigmaX: GlassMetrics.blurSigma, sigmaY: GlassMetrics.blurSigma, tileMode: TileMode.mirror)
      : null;

  /// The shader in the screen's pixels: where the bar is on screen now.
  ui.ImageFilter _shaderFilter(ui.FragmentProgram program, Rect drop) {
    final shader = _shader ??= program.fragmentShader();
    final ratio = _devicePixelRatio;
    final toScreen = getTransformTo(null);
    final pane = MatrixUtils.transformRect(toScreen, Offset.zero & size);
    final dropOnScreen = MatrixUtils.transformRect(toScreen, drop);
    final scale = pane.width / size.width;
    final tint = _tint;
    var i = 2; // 0, 1: the backdrop's size, set by the engine.
    void set(double value) => shader.setFloat(i++, value);
    set(pane.left * ratio);
    set(pane.top * ratio);
    set(pane.width * ratio);
    set(pane.height * ratio);
    set(dropOnScreen.left * ratio);
    set(dropOnScreen.top * ratio);
    set(dropOnScreen.width * ratio);
    set(dropOnScreen.height * ratio);
    final px = ratio * scale;
    set(_radius * px);
    set(dropOnScreen.height / 2 * ratio);
    set(drop.isEmpty ? 0 : (_dark ? 0.9 : 0.85));
    set(1.12);
    set(20 * px); // edge band
    set(12 * px); // refraction
    set(1.4 * px); // rim width
    set(0.08); // colour split
    set(tint.r);
    set(tint.g);
    set(tint.b);
    set(_dark ? 0.32 : 0.28);
    set(-0.6);
    set(-0.8);
    set(_dark ? 0.55 : 0.95); // rim strength
    set(1.18); // saturation
    final glass = ui.ImageFilter.shader(shader);
    if (!_blur) return glass;
    const sigma = 4.0;
    return ui.ImageFilter.compose(
      outer: glass,
      inner: ui.ImageFilter.blur(sigmaX: sigma, sigmaY: sigma, tileMode: TileMode.mirror),
    );
  }

  /// The frosted glass and the drop as a tinted pill, without the shader.
  void _paintFallback(Canvas canvas, Rect bounds, Rect drop) {
    final shape = RRect.fromRectAndRadius(bounds, Radius.circular(_radius));
    final alpha = _blur ? (_dark ? 0.66 : 0.74) : 0.94;
    canvas.drawRRect(shape, Paint()..color = _tint.withValues(alpha: alpha));
    if (!drop.isEmpty) {
      canvas.drawRRect(
        RRect.fromRectAndRadius(drop, Radius.circular(drop.height / 2)),
        Paint()..color = _dropColor.withValues(alpha: _dark ? 0.22 : 0.14),
      );
    }
    canvas.drawRRect(
      shape.deflate(0.5),
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = 1
        ..color = Colors.white.withValues(alpha: _dark ? 0.16 : 0.5),
    );
  }
}
