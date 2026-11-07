import 'package:flutter/material.dart';

/// Motion used across the app. Everything here turns itself off when the phone's
/// "Remove animations" accessibility setting is on.
bool reduceMotion(BuildContext context) => MediaQuery.maybeDisableAnimationsOf(context) ?? false;

const kEaseOut = Curves.easeOutCubic;

/// Fades and lifts its child into place when first shown. [index] staggers a list:
/// each item starts a little after the previous one (capped, so long lists don't drag).
class FadeSlideIn extends StatefulWidget {
  const FadeSlideIn({super.key, required this.child, this.index = 0, this.offset = 18});
  final Widget child;
  final int index;
  final double offset;

  @override
  State<FadeSlideIn> createState() => _FadeSlideInState();
}

class _FadeSlideInState extends State<FadeSlideIn> with SingleTickerProviderStateMixin {
  // The stagger delay is the start of an Interval, so no timers are involved.
  static const _runMs = 460;
  late final int _delayMs = 40 * widget.index.clamp(0, 8);
  late final AnimationController _c = AnimationController(vsync: this, duration: Duration(milliseconds: _delayMs + _runMs));
  late final Animation<double> _t = CurvedAnimation(parent: _c, curve: Interval(_delayMs / (_delayMs + _runMs), 1, curve: kEaseOut));

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (_c.status != AnimationStatus.dismissed) return;
    if (reduceMotion(context)) {
      _c.value = 1;
    } else {
      _c.forward();
    }
  }

  @override
  void dispose() {
    _c.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => AnimatedBuilder(
        animation: _t,
        child: widget.child,
        builder: (_, child) => Opacity(
          opacity: _t.value,
          child: Transform.translate(offset: Offset(0, (1 - _t.value) * widget.offset), child: child),
        ),
      );
}

/// Wraps each item of a column/list in a staggered [FadeSlideIn]. Spacers are left alone.
List<Widget> staggered(List<Widget> items) {
  var i = 0;
  return [for (final w in items) w is SizedBox && w.child == null ? w : FadeSlideIn(index: i++, child: w)];
}

/// Shrinks slightly while pressed, then springs back: tactile feedback for cards.
class Pressable extends StatefulWidget {
  const Pressable({super.key, required this.child, this.enabled = true, this.scale = .975});
  final Widget child;
  final bool enabled;
  final double scale;
  @override
  State<Pressable> createState() => _PressableState();
}

class _PressableState extends State<Pressable> {
  bool _down = false;
  void _set(bool v) {
    if (_down != v && mounted) setState(() => _down = v);
  }

  @override
  Widget build(BuildContext context) {
    if (!widget.enabled || reduceMotion(context)) return widget.child;
    return Listener(
      onPointerDown: (_) => _set(true),
      onPointerUp: (_) => _set(false),
      onPointerCancel: (_) => _set(false),
      child: AnimatedScale(
        scale: _down ? widget.scale : 1,
        duration: Duration(milliseconds: _down ? 90 : 220),
        curve: _down ? Curves.easeOut : Curves.easeOutBack,
        child: widget.child,
      ),
    );
  }
}

/// Like [IndexedStack] (every tab keeps its state and scroll position), but the
/// newly selected tab fades and rises in.
class FadeIndexedStack extends StatefulWidget {
  const FadeIndexedStack({super.key, required this.index, required this.children});
  final int index;
  final List<Widget> children;
  @override
  State<FadeIndexedStack> createState() => _FadeIndexedStackState();
}

class _FadeIndexedStackState extends State<FadeIndexedStack> with SingleTickerProviderStateMixin {
  late final AnimationController _c = AnimationController(vsync: this, duration: const Duration(milliseconds: 280), value: 1);

  @override
  void didUpdateWidget(FadeIndexedStack old) {
    super.didUpdateWidget(old);
    if (old.index != widget.index && !reduceMotion(context)) _c.forward(from: 0);
  }

  @override
  void dispose() {
    _c.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final t = CurvedAnimation(parent: _c, curve: kEaseOut);
    return FadeTransition(
      opacity: t,
      child: AnimatedBuilder(
        animation: t,
        builder: (_, child) => Transform.translate(offset: Offset(0, (1 - t.value) * 10), child: child),
        child: IndexedStack(index: widget.index, children: [for (var i = 0; i < widget.children.length; i++) TickerMode(enabled: i == widget.index, child: widget.children[i])]),
      ),
    );
  }
}

/// Page push: the new page fades in while sliding up a touch; the old one dims back.
class FadeSlidePageTransitionsBuilder extends PageTransitionsBuilder {
  const FadeSlidePageTransitionsBuilder();
  @override
  Widget buildTransitions<T>(PageRoute<T> route, BuildContext context, Animation<double> animation, Animation<double> secondaryAnimation, Widget child) {
    final inT = CurvedAnimation(parent: animation, curve: kEaseOut, reverseCurve: Curves.easeInCubic);
    final outT = CurvedAnimation(parent: secondaryAnimation, curve: kEaseOut);
    return FadeTransition(
      opacity: Tween<double>(begin: 1, end: .6).animate(outT),
      child: SlideTransition(
        position: Tween<Offset>(begin: const Offset(0, .04), end: Offset.zero).animate(inT),
        child: FadeTransition(opacity: inT, child: child),
      ),
    );
  }
}
