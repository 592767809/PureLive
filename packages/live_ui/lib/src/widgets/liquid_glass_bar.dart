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
  /// The drop's centre, in logical pixels from the bar's left; a spring
  /// carries it, also under the finger (A01.7).
  late final AnimationController _drop = AnimationController.unbounded(vsync: this);

  /// How much the drop is held: 0 a pill at rest, 1 a lens.
  late final AnimationController _press = AnimationController.unbounded(vsync: this);

  /// The drop's growth across and up, each on its own spring.
  late final AnimationController _growX = AnimationController.unbounded(vsync: this, value: 1);
  late final AnimationController _growY = AnimationController.unbounded(vsync: this, value: 1);

  /// The drop's speed as its shape feels it (px/s, along its way).
  late final AnimationController _squash = AnimationController.unbounded(vsync: this);

  /// How far a drag has pulled the bar (px); the bar leans a few pixels.
  late final AnimationController _lean = AnimationController.unbounded(vsync: this);

  ui.FragmentProgram? _program = LiquidGlassShader.program;
  double _width = 0;
  bool _placed = false;
  int? _dragIndex;
  double _dragTarget = 0;
  bool _touching = false;
  double _heading = 1;
  final GlobalKey _barKey = GlobalKey(debugLabel: 'liquid glass bar');

  @override
  void initState() {
    super.initState();
    _drop.addListener(_feelSpeed);
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
    if (_arriving case final arriving?) _drop.removeListener(arriving);
    _drop.dispose();
    _press.dispose();
    _growX.dispose();
    _growY.dispose();
    _squash.dispose();
    _lean.dispose();
    super.dispose();
  }

  double get _slot => _width / widget.items.length;

  double _centreOf(int index) => _slot * (index + 0.5);

  int _indexAt(double x) => (x / _slot).floor().clamp(0, widget.items.length - 1);

  bool get _still => MediaQuery.maybeDisableAnimationsOf(context) ?? false;

  static void _spring(AnimationController controller, SpringDescription spring, double target) {
    controller.animateWith(SpringSimulation(spring, controller.value, target, controller.velocity));
  }

  /// The shape follows the drop's speed through an under-damped spring.
  void _feelSpeed() {
    final speed = _drop.velocity;
    if (speed.abs() > 1) _heading = speed.sign;
    if (_still) return;
    _spring(_squash, AppMotion.glassSquashSpring, speed);
  }

  /// Held: the pill turns into a lens and swells; let go: back.
  void _hold(bool held) {
    if (_still) return;
    final grow = held ? AppMotion.glassHeldScale : 1.0;
    _spring(_press, AppMotion.glassPressSpring, held ? 1 : 0);
    _spring(_growX, AppMotion.glassGrowXSpring, grow);
    _spring(_growY, AppMotion.glassGrowYSpring, grow);
  }

  /// To [index]: the drop goes as a lens and turns back into a pill as it
  /// arrives, unless a finger still holds it.
  void _settle(int index) {
    final target = _centreOf(index);
    if (_still || _width == 0) {
      _drop.value = target;
      return;
    }
    _hold(true);
    _drop.animateWith(SpringSimulation(AppMotion.glassPlaceSpring, _drop.value, target, _drop.velocity));
    _letGoNear(target);
  }

  VoidCallback? _arriving;

  /// The lens turns back into a pill once the drop is within 2.5 % of the
  /// bar's run from [target] (Kyant's release), not when the spring's last
  /// fraction of a pixel is done.
  void _letGoNear(double target) {
    if (_arriving case final previous?) _drop.removeListener(previous);
    final near = (_centreOf(widget.items.length - 1) - _centreOf(0)) * 0.025;
    void check() {
      if ((_drop.value - target).abs() > near && _drop.isAnimating) return;
      _drop.removeListener(check);
      if (identical(_arriving, check)) _arriving = null;
      if (mounted && !_touching && _dragIndex == null) _hold(false);
    }

    _arriving = check;
    _drop.addListener(check);
  }

  void _onPointerDown(PointerDownEvent event) {
    _touching = true;
    _hold(true);
  }

  void _onPointerUp(PointerEvent event) {
    _touching = false;
    // Let go while the drop is still on its way: it lets go as it arrives.
    if (_arriving == null && _dragIndex == null) _hold(false);
  }

  void _onDragStart(DragStartDetails details) {
    _dragTarget = _drop.value;
    _dragIndex = _indexAt(_dragTarget);
    _hold(true);
  }

  void _onDragUpdate(DragUpdateDetails details) {
    final min = _centreOf(0);
    final max = _centreOf(widget.items.length - 1);
    _dragTarget += details.delta.dx;
    // Past the first or last destination the drop follows ever more
    // heavily (the lists' rubber band).
    final raw = _dragTarget;
    final next = raw < min
        ? min + AppMotion.rubberBand(raw - min, _slot)
        : raw > max
        ? max + AppMotion.rubberBand(raw - max, _slot)
        : raw;
    if (_still) {
      _drop.value = next;
    } else {
      _drop.animateWith(SpringSimulation(AppMotion.glassPlaceSpring, _drop.value, next, _drop.velocity));
      _lean.value += details.delta.dx;
    }
    final index = _indexAt(next);
    if (index != _dragIndex) {
      _dragIndex = index;
      unawaited(HapticFeedback.selectionClick());
    }
  }

  void _onDragEnd(DragEndDetails details) {
    final velocity = details.velocity.pixelsPerSecond.dx;
    // Where a throw would carry it, a fifth of a second on.
    final index = _indexAt(_dragTarget.clamp(_centreOf(0), _centreOf(widget.items.length - 1)) + velocity * 0.2);
    _dragIndex = null;
    _touching = false;
    if (!_still) _spring(_lean, AppMotion.glassLeanSpring, 0);
    _settle(index);
    if (index != widget.selectedIndex) widget.onSelected(index);
  }

  void _onTap(int index) {
    // The chosen one tapped again is told too: the follows refresh (3.x).
    if (index != widget.selectedIndex) _settle(index);
    widget.onSelected(index);
  }

  double get _held => _press.value.clamp(0.0, 1.0);

  /// The bar leans a few pixels with a drag, easing off (Kyant's 4 dp).
  double get _leanOffset {
    if (_width == 0) return 0;
    final fraction = (_lean.value / _width).clamp(-1.0, 1.0);
    return 4 * fraction.sign * Curves.easeOut.transform(fraction.abs());
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final dark = theme.brightness == Brightness.dark;
    final route = ModalRoute.of(context);
    // The glass is placed in screen pixels when painted: it paints again
    // whenever its route moves (A03.5's slide), not only when it changes.
    final moves = Listenable.merge([
      _drop,
      _press,
      _growX,
      _growY,
      _squash,
      _lean,
      ?route?.animation,
      ?route?.secondaryAnimation,
    ]);
    return LayoutBuilder(
      builder: (context, constraints) {
        _width = constraints.maxWidth;
        if (!_placed && _width > 0) {
          _placed = true;
          _drop.value = _centreOf(widget.selectedIndex);
        }
        // The shadow only floating layers have (UI.md §9.3), soft and close.
        final bar = DecoratedBox(
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(GlassMetrics.barRadius),
            boxShadow: [
              BoxShadow(
                color: Colors.black.withValues(alpha: dark ? 0.32 : 0.12),
                blurRadius: 24,
                offset: const Offset(0, 8),
              ),
            ],
          ),
          child: GestureDetector(
            behavior: HitTestBehavior.opaque,
            onHorizontalDragStart: _onDragStart,
            onHorizontalDragUpdate: _onDragUpdate,
            onHorizontalDragEnd: _onDragEnd,
            child: _LiquidGlass(
              program: widget.refraction ? _program : null,
              blur: widget.blur,
              dark: dark,
              tint: dark ? scheme.surfaceContainer : scheme.surfaceContainerHighest,
              moves: moves,
              drop: _dropRect,
              held: () => _held,
              child: KeyedSubtree(
                key: _barKey,
                child: Row(
                  children: [
                    for (final (index, item) in widget.items.indexed)
                      Expanded(child: _destination(context, index, item, moves)),
                  ],
                ),
              ),
            ),
          ),
        );
        return Listener(
          onPointerDown: _onPointerDown,
          onPointerUp: _onPointerUp,
          onPointerCancel: _onPointerUp,
          child: AnimatedBuilder(
            animation: Listenable.merge([_press, _lean]),
            // Held, the whole bar swells a little (16 px across) and leans
            // with the drag.
            builder: (context, child) => Transform.translate(
              offset: Offset(_leanOffset, 0),
              child: Transform.scale(scale: 1 + (_width == 0 ? 0 : 16 / _width) * _held, child: child),
            ),
            child: bar,
          ),
        );
      },
    );
  }

  /// The drop's rectangle in the bar: grown while held, squeezed along its
  /// way by its speed and once the other way when it stops.
  Rect _dropRect() {
    if (_width == 0) return Rect.zero;
    // The speed in destinations per second, a tenth of it (Kyant's scale).
    final speed = _slot == 0 ? 0.0 : _squash.value * _heading / _slot / 10;
    final across = _growX.value / (1 - (speed * 0.75).clamp(-0.2, 0.2));
    final up = _growY.value * (1 - (speed * 0.25).clamp(-0.2, 0.2));
    final width = (_slot - 10) * across;
    final height = (GlassMetrics.barHeight - 12) * up;
    return Rect.fromCenter(center: Offset(_drop.value, GlassMetrics.barHeight / 2), width: width, height: height);
  }

  Widget _destination(BuildContext context, int index, LiquidGlassBarItem item, Listenable moves) {
    final scheme = Theme.of(context).colorScheme;
    final chosen = index == widget.selectedIndex;
    // The icon twice: as it is outside the drop, and chosen, in the chosen
    // colour, inside it, so a destination takes the colour exactly as far as
    // the drop covers it, also on its way (CoolApk). The name stays
    // onSurface, which keeps 4.5:1 over the glass (the primary colour did
    // not).
    Widget part({required bool inside, required Widget child}) =>
        _UnderDrop(bar: _barKey, drop: _dropRect, moves: moves, inside: inside, child: child);
    final icon = Stack(
      children: [
        part(inside: false, child: Icon(item.icon, size: 24, color: scheme.onSurfaceVariant)),
        part(
          inside: true,
          child: ExcludeSemantics(child: Icon(item.selectedIcon, size: 24, color: scheme.primary)),
        ),
      ],
    );
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
                    icon,
                    const SizedBox(height: 4),
                    Text(
                      item.label,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: Theme.of(context).textTheme.labelMedium?.copyWith(
                        color: scheme.onSurface,
                        fontWeight: chosen ? FontWeight.w600 : FontWeight.w400,
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

/// Shows its child only inside the drop ([inside]) or only outside it,
/// the drop being given in the bar's coordinates; clipped again as the drop
/// moves.
class _UnderDrop extends SingleChildRenderObjectWidget {
  const new({required this.bar, required this.drop, required this.moves, required this.inside, required super.child});

  final GlobalKey bar;
  final Rect Function() drop;
  final Listenable moves;
  final bool inside;

  @override
  _RenderUnderDrop createRenderObject(BuildContext context) =>
      _RenderUnderDrop(bar: bar, drop: drop, moves: moves, inside: inside);

  @override
  void updateRenderObject(BuildContext context, _RenderUnderDrop renderObject) {
    renderObject
      ..bar = bar
      ..drop = drop
      ..moves = moves
      ..inside = inside;
  }
}

class _RenderUnderDrop extends RenderProxyBox {
  new({required this.bar, required this.drop, required this._moves, required this._inside});

  GlobalKey bar;
  Rect Function() drop;

  Listenable _moves;
  Listenable get moves => _moves;
  set moves(Listenable value) {
    if (value == _moves) return;
    if (attached) _moves.removeListener(markNeedsPaint);
    _moves = value;
    if (attached) _moves.addListener(markNeedsPaint);
    markNeedsPaint();
  }

  bool _inside;
  bool get inside => _inside;
  set inside(bool value) {
    if (value == _inside) return;
    _inside = value;
    markNeedsPaint();
  }

  final LayerHandle<ClipPathLayer> _clip = LayerHandle();

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
    _clip.layer = null;
    super.dispose();
  }

  @override
  void paint(PaintingContext context, Offset offset) {
    final box = bar.currentContext?.findRenderObject();
    final rect = drop();
    if (box is! RenderBox || !box.attached || rect.isEmpty) {
      _clip.layer = null;
      if (!_inside) super.paint(context, offset);
      return;
    }
    // The drop in this box's own coordinates (the slot's padding and the
    // fitted scale between them).
    final toBar = getTransformTo(box);
    if (toBar.invert() == 0) {
      _clip.layer = null;
      if (!_inside) super.paint(context, offset);
      return;
    }
    final local = MatrixUtils.transformRect(toBar, rect);
    final bounds = Offset.zero & size;
    if (!local.overlaps(bounds)) {
      _clip.layer = null;
      if (!_inside) super.paint(context, offset);
      return;
    }
    final capsule = Path()..addRRect(RRect.fromRectAndRadius(local, Radius.circular(local.shortestSide / 2)));
    final path = _inside
        ? capsule
        : (Path()
            ..fillType = PathFillType.evenOdd
            ..addRect(bounds.inflate(1))
            ..addPath(capsule, Offset.zero));
    _clip.layer = context.pushClipPath(needsCompositing, offset, bounds, path, super.paint, oldLayer: _clip.layer);
  }
}

class _LiquidGlass extends SingleChildRenderObjectWidget {
  const new({
    required this.program,
    required this.blur,
    required this.dark,
    required this.tint,
    required this.moves,
    required this.drop,
    required this.held,
    required super.child,
  });

  final ui.FragmentProgram? program;
  final bool blur;
  final bool dark;
  final Color tint;
  final Listenable moves;
  final Rect Function() drop;
  final double Function() held;

  @override
  RenderLiquidGlass createRenderObject(BuildContext context) => RenderLiquidGlass(
    program: program,
    blur: blur,
    dark: dark,
    tint: tint,
    moves: moves,
    drop: drop,
    held: held,
    devicePixelRatio: MediaQuery.devicePixelRatioOf(context),
  );

  @override
  void updateRenderObject(BuildContext context, RenderLiquidGlass renderObject) {
    renderObject
      ..program = program
      ..blur = blur
      ..dark = dark
      ..tint = tint
      ..moves = moves
      ..drop = drop
      ..held = held
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
    required this._moves,
    required this._drop,
    required this._held,
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

  double Function() _held;

  /// See the widget: how much the drop is held, 0 to 1.
  double Function() get held => _held;
  set held(double Function() value) {
    _held = value;
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
          final here = drop.shift(offset - bounds.topLeft);
          if (program == null) {
            _paintFallback(context.canvas, offset & size, here);
          } else {
            _paintTouch(context.canvas, offset & size, here);
          }
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
    // The drop is a lens only while held (A01.7); at rest a pill.
    final held = _held();
    set(drop.isEmpty ? 0 : held);
    set(1 + 0.12 * held);
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

  /// Over the shader's glass: the pill fading as the lens comes, and the
  /// light of the touch.
  void _paintTouch(Canvas canvas, Rect bounds, Rect drop) {
    _paintPill(canvas, drop, lens: true);
    _paintGlow(canvas, bounds, drop);
    _paintLensDepth(canvas, drop);
  }

  /// A held lens stands off the glass: a soft shadow around it (24 across,
  /// 4 down, 10 %) and a shade along its top edge inside (8 across, 15 %),
  /// both growing as it is held (Kyant's shadow and inner shadow). Without
  /// them a clear lens over a white page could not be seen.
  void _paintLensDepth(Canvas canvas, Rect drop) {
    final held = _held().clamp(0.0, 1.0);
    if (held <= 0 || drop.isEmpty) return;
    final lens = RRect.fromRectAndRadius(drop, Radius.circular(drop.shortestSide / 2));
    final around = Path()
      ..fillType = PathFillType.evenOdd
      ..addRect(drop.inflate(48))
      ..addRRect(lens);
    canvas
      ..save()
      ..clipPath(around)
      ..drawRRect(
        lens.shift(const Offset(0, 4)),
        Paint()
          ..color = Colors.black.withValues(alpha: 0.10 * held)
          ..maskFilter = MaskFilter.blur(BlurStyle.normal, Shadow.convertRadiusToSigma(24)),
      )
      ..restore();
    final radius = 8 * held;
    final inner = Path()
      ..fillType = PathFillType.evenOdd
      ..addRect(drop.inflate(radius * 3 + 8))
      ..addRRect(lens.shift(Offset(0, radius)));
    canvas
      ..save()
      ..clipRRect(lens)
      ..drawPath(
        inner,
        Paint()
          ..color = Colors.black.withValues(alpha: 0.15 * held)
          ..maskFilter = MaskFilter.blur(BlurStyle.normal, Shadow.convertRadiusToSigma(radius)),
      )
      ..restore();
  }

  /// The drop at rest: a pill of shade, black on light glass and white on
  /// dark (CoolApk's 10 %); with a lens it gives way as the drop is held.
  void _paintPill(Canvas canvas, Rect drop, {required bool lens}) {
    if (drop.isEmpty) return;
    final held = _held().clamp(0.0, 1.0);
    final pill = RRect.fromRectAndRadius(drop, Radius.circular(drop.shortestSide / 2));
    final shade = (_dark ? Colors.white : Colors.black).withValues(alpha: lens ? 0.10 * (1 - held) : 0.10);
    canvas.drawRRect(pill, Paint()..color = shade);
    // Held, a touch of shade inside the lens (or on the pill without one).
    if (held > 0) canvas.drawRRect(pill, Paint()..color = Colors.black.withValues(alpha: (lens ? 0.03 : 0.04) * held));
  }

  /// While held the glass lights up where the drop is: a faint wash and a
  /// soft round light (Kyant's interactive highlight).
  void _paintGlow(Canvas canvas, Rect bounds, Rect drop) {
    final held = _held().clamp(0.0, 1.0);
    if (held <= 0 || drop.isEmpty) return;
    canvas
      ..save()
      ..clipRRect(RRect.fromRectAndRadius(bounds, Radius.circular(_radius)))
      ..drawRect(
        bounds,
        Paint()
          ..blendMode = BlendMode.plus
          ..color = Colors.white.withValues(alpha: 0.08 * held),
      );
    final radius = bounds.shortestSide * 1.5;
    canvas
      ..drawRect(
        bounds,
        Paint()
          ..blendMode = BlendMode.plus
          ..shader = ui.Gradient.radial(
            drop.center,
            radius,
            [
              Colors.white.withValues(alpha: 0.15 * held),
              Colors.white.withValues(alpha: 0.15 * held),
              const Color(0x00FFFFFF),
            ],
            [0, 0.5, 1],
          ),
      )
      ..restore();
  }

  /// The frosted glass and the drop as a tinted pill, without the shader.
  void _paintFallback(Canvas canvas, Rect bounds, Rect drop) {
    final shape = RRect.fromRectAndRadius(bounds, Radius.circular(_radius));
    final alpha = _blur ? (_dark ? 0.66 : 0.74) : 0.94;
    canvas.drawRRect(shape, Paint()..color = _tint.withValues(alpha: alpha));
    // No lens here: the drop stays a pill, a little stronger when held.
    _paintPill(canvas, drop, lens: false);
    _paintGlow(canvas, bounds, drop);
    canvas.drawRRect(
      shape.deflate(0.5),
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = 1
        ..color = Colors.white.withValues(alpha: _dark ? 0.16 : 0.5),
    );
  }
}
