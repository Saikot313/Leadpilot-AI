import 'dart:async';

import 'package:flutter/material.dart';

import '../../core/utils/motion.dart';

class StaggeredEntrance extends StatefulWidget {
  const StaggeredEntrance(
      {super.key, required this.child, this.index = 0, this.offsetY = 14});

  final Widget child;

  /// Position in the list. Delay is capped so long lists do not feel slow.
  final int index;
  final double offsetY;

  @override
  State<StaggeredEntrance> createState() => _StaggeredEntranceState();
}

class _StaggeredEntranceState extends State<StaggeredEntrance>
    with SingleTickerProviderStateMixin {
  late final AnimationController _controller =
      AnimationController(vsync: this, duration: Motion.slow);
  late final Animation<double> _curve =
      CurvedAnimation(parent: _controller, curve: Motion.standard);
  Timer? _timer;
  bool _started = false;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (_started) return;
    _started = true;
    if (Motion.reduced(context)) {
      _controller.value = 1;
      return;
    }
    final delay = Motion.stagger * widget.index.clamp(0, 8);
    if (delay == Duration.zero) {
      _controller.forward();
    } else {
      _timer = Timer(delay, () {
        if (mounted) _controller.forward();
      });
    }
  }

  @override
  void dispose() {
    _timer?.cancel();
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: _curve,
      child: widget.child,
      builder: (context, child) => Opacity(
        opacity: _curve.value.clamp(0.0, 1.0),
        child: Transform.translate(
            offset: Offset(0, (1 - _curve.value) * widget.offsetY),
            child: child),
      ),
    );
  }
}
