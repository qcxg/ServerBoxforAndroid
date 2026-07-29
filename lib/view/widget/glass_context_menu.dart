import 'dart:async';

import 'package:flutter/material.dart';
import 'package:server_box/view/widget/glass_surface.dart';

final class GlassContextMenuAction {
  const GlassContextMenuAction({
    required this.icon,
    required this.label,
    required this.onPressed,
    this.destructive = false,
  });

  final IconData icon;
  final String label;
  final VoidCallback onPressed;
  final bool destructive;
}

Future<void> showGlassContextMenu(
  BuildContext context, {
  required Offset anchor,
  required List<GlassContextMenuAction> actions,
}) async {
  if (actions.isEmpty) return;
  final overlayRenderObject = Overlay.of(
    context,
    rootOverlay: true,
  ).context.findRenderObject();
  final overlayBox = overlayRenderObject is RenderBox
      ? overlayRenderObject
      : null;
  final localAnchor = overlayBox?.globalToLocal(anchor) ?? anchor;
  await showGeneralDialog<void>(
    context: context,
    barrierDismissible: true,
    barrierColor: Colors.transparent,
    barrierLabel: MaterialLocalizations.of(context).modalBarrierDismissLabel,
    transitionDuration: const Duration(milliseconds: 180),
    pageBuilder: (menuContext, _, _) {
      final media = MediaQuery.of(menuContext);
      const width = 190.0;
      final height = actions.length * 42.0 + 8;
      final safeLeft = media.padding.left + 8;
      final safeRight = media.size.width - media.padding.right - 8;
      final safeTop = media.padding.top + 8;
      final bottomInset = media.viewInsets.bottom > media.padding.bottom
          ? media.viewInsets.bottom
          : media.padding.bottom;
      final safeBottom = media.size.height - bottomInset - 8;
      var left = localAnchor.dx + 10;
      if (left + width > safeRight) left = localAnchor.dx - width - 10;
      left = left.clamp(safeLeft, safeRight - width).toDouble();
      var top = localAnchor.dy + 8;
      if (top + height > safeBottom) top = localAnchor.dy - height - 8;
      top = top.clamp(safeTop, safeBottom - height).toDouble();

      return Material(
        type: MaterialType.transparency,
        child: Stack(
          children: [
            Positioned(
              left: left,
              top: top,
              width: width,
              child: GlassSurface(
                shape: const RoundedRectangleBorder(
                  borderRadius: BorderRadius.all(Radius.circular(18)),
                ),
                surfaceAlpha: 166,
                shadow: true,
                child: Padding(
                  padding: const EdgeInsets.symmetric(vertical: 4),
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: actions.map((action) {
                      final color = action.destructive
                          ? Theme.of(menuContext).colorScheme.error
                          : Theme.of(menuContext).colorScheme.onSurfaceVariant;
                      return SizedBox(
                        height: 42,
                        child: InkWell(
                          onTap: () {
                            Navigator.of(menuContext).pop();
                            scheduleMicrotask(action.onPressed);
                          },
                          child: Padding(
                            padding: const EdgeInsets.symmetric(horizontal: 12),
                            child: Row(
                              children: [
                                Icon(action.icon, size: 19, color: color),
                                const SizedBox(width: 10),
                                Expanded(
                                  child: Text(
                                    action.label,
                                    maxLines: 1,
                                    overflow: TextOverflow.ellipsis,
                                    style: TextStyle(
                                      color: color,
                                      fontSize: 13,
                                      fontWeight: FontWeight.w600,
                                    ),
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ),
                      );
                    }).toList(growable: false),
                  ),
                ),
              ),
            ),
          ],
        ),
      );
    },
    transitionBuilder: (context, animation, _, child) {
      final curved = CurvedAnimation(
        parent: animation,
        curve: Curves.easeOutCubic,
        reverseCurve: Curves.easeInCubic,
      );
      return FadeTransition(opacity: curved, child: child);
    },
  );
}
