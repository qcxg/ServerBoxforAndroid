import 'dart:ui';

import 'package:flutter/material.dart';

class GlassSurface extends StatelessWidget {
  const GlassSurface({
    super.key,
    required this.child,
    required this.shape,
    this.blur = 18,
    this.surfaceAlpha = 148,
    this.borderAlpha = 54,
    this.shadow = false,
  });

  final Widget child;
  final ShapeBorder shape;
  final double blur;
  final int surfaceAlpha;
  final int borderAlpha;
  final bool shadow;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final outlinedShape = shape is OutlinedBorder
        ? (shape as OutlinedBorder).copyWith(
            side: BorderSide(
              color: scheme.outlineVariant.withAlpha(borderAlpha),
              width: 0.7,
            ),
          )
        : shape;
    final surface = ClipPath(
      clipper: ShapeBorderClipper(shape: outlinedShape),
      child: BackdropFilter(
        filter: ImageFilter.blur(sigmaX: blur, sigmaY: blur),
        child: DecoratedBox(
          decoration: ShapeDecoration(
            color: scheme.surface.withAlpha(surfaceAlpha),
            shape: outlinedShape,
          ),
          child: child,
        ),
      ),
    );
    if (!shadow) return surface;
    return DecoratedBox(
      decoration: ShapeDecoration(
        color: Colors.transparent,
        shape: shape,
        shadows: [
          BoxShadow(
            color: scheme.shadow.withAlpha(22),
            blurRadius: 18,
            offset: const Offset(0, 6),
          ),
        ],
      ),
      child: surface,
    );
  }
}
