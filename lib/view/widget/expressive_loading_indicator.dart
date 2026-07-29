import 'dart:math' as math;

import 'package:flutter/material.dart';

/// A compact Material 3 Expressive-style indeterminate loading indicator.
///
/// Flutter 3.44 does not yet expose the morphing Material loading indicator,
/// so this painter interpolates between soft radial shapes while rotating.
class ExpressiveLoadingIndicator extends StatefulWidget {
  const ExpressiveLoadingIndicator({
    super.key,
    this.size = 48,
    this.color,
    this.semanticsLabel,
  });

  final double size;
  final Color? color;
  final String? semanticsLabel;

  @override
  State<ExpressiveLoadingIndicator> createState() =>
      _ExpressiveLoadingIndicatorState();
}

class _ExpressiveLoadingIndicatorState
    extends State<ExpressiveLoadingIndicator>
    with SingleTickerProviderStateMixin {
  late final AnimationController _controller = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 3200),
  )..repeat();

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final color = widget.color ?? Theme.of(context).colorScheme.primary;
    return Semantics(
      label: widget.semanticsLabel,
      child: SizedBox.square(
        dimension: widget.size,
        child: CustomPaint(
          painter: _ExpressiveLoadingPainter(
            animation: _controller,
            color: color,
          ),
        ),
      ),
    );
  }
}

class _ExpressiveLoadingPainter extends CustomPainter {
  _ExpressiveLoadingPainter({
    required Animation<double> animation,
    required this.color,
  }) : _animation = animation,
       super(repaint: animation);

  static const _shapes = <_ExpressiveShape>[
    _ExpressiveShape(lobes: 3, amplitude: 0.10, xScale: 0.98, yScale: 0.92),
    _ExpressiveShape(
      lobes: 8,
      amplitude: 0.15,
      secondaryLobes: 4,
      secondaryAmplitude: 0.035,
      phase: 0.18,
    ),
    _ExpressiveShape(
      lobes: 4,
      amplitude: 0.12,
      xScale: 0.92,
      yScale: 1,
      phase: 0.39,
    ),
    _ExpressiveShape(
      lobes: 7,
      amplitude: 0.13,
      xScale: 1,
      yScale: 0.94,
      phase: 0.1,
    ),
    _ExpressiveShape(
      lobes: 5,
      amplitude: 0.11,
      xScale: 0.90,
      yScale: 1,
      phase: 0.28,
    ),
    _ExpressiveShape(
      lobes: 10,
      amplitude: 0.12,
      secondaryLobes: 3,
      secondaryAmplitude: 0.025,
    ),
  ];

  final Animation<double> _animation;
  final Color color;

  @override
  void paint(Canvas canvas, Size size) {
    final progress = _animation.value;
    final shapeProgress = progress * _shapes.length;
    final fromIndex = shapeProgress.floor() % _shapes.length;
    final toIndex = (fromIndex + 1) % _shapes.length;
    final morph = Curves.easeInOutCubicEmphasized.transform(
      shapeProgress - shapeProgress.floor(),
    );
    final from = _shapes[fromIndex];
    final to = _shapes[toIndex];
    final radius = math.min(size.width, size.height) * 0.39;
    final center = size.center(Offset.zero);
    final rotation = progress * math.pi * 2.5;
    const sampleCount = 96;
    final path = Path();

    for (var index = 0; index < sampleCount; index++) {
      final theta = index / sampleCount * math.pi * 2;
      final fromPoint = from.pointAt(theta, radius);
      final toPoint = to.pointAt(theta, radius);
      final point = Offset.lerp(fromPoint, toPoint, morph)!;
      final cosRotation = math.cos(rotation);
      final sinRotation = math.sin(rotation);
      final rotated = Offset(
        point.dx * cosRotation - point.dy * sinRotation,
        point.dx * sinRotation + point.dy * cosRotation,
      );
      final target = center + rotated;
      if (index == 0) {
        path.moveTo(target.dx, target.dy);
      } else {
        path.lineTo(target.dx, target.dy);
      }
    }
    path.close();

    canvas.drawPath(
      path,
      Paint()
        ..color = color
        ..style = PaintingStyle.fill
        ..isAntiAlias = true,
    );
  }

  @override
  bool shouldRepaint(_ExpressiveLoadingPainter oldDelegate) {
    return oldDelegate.color != color || oldDelegate._animation != _animation;
  }
}

class _ExpressiveShape {
  const _ExpressiveShape({
    required this.lobes,
    required this.amplitude,
    this.secondaryLobes = 0,
    this.secondaryAmplitude = 0,
    this.xScale = 1,
    this.yScale = 1,
    this.phase = 0,
  });

  final int lobes;
  final double amplitude;
  final int secondaryLobes;
  final double secondaryAmplitude;
  final double xScale;
  final double yScale;
  final double phase;

  Offset pointAt(double theta, double radius) {
    final primaryWave = math.cos(lobes * (theta + phase));
    final secondaryWave = secondaryLobes == 0
        ? 0.0
        : math.cos(secondaryLobes * (theta - phase * 0.7));
    final shapedRadius = radius *
        (1 + amplitude * primaryWave + secondaryAmplitude * secondaryWave);
    return Offset(
      math.cos(theta) * shapedRadius * xScale,
      math.sin(theta) * shapedRadius * yScale,
    );
  }
}
