import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:server_box/core/extension/context/locale.dart';
import 'package:server_box/data/ssh/session_manager.dart';

class SshConnectionTitle extends StatelessWidget {
  const SshConnectionTitle({
    super.key,
    required this.title,
    required this.statusListenable,
    this.showStatusText = true,
    this.compact = false,
    this.foregroundColor,
  });

  final String title;
  final ValueListenable<TermSessionStatus> statusListenable;
  final bool showStatusText;
  final bool compact;
  final Color? foregroundColor;

  @override
  Widget build(BuildContext context) {
    return ValueListenableBuilder<TermSessionStatus>(
      valueListenable: statusListenable,
      builder: (context, status, child) {
        final statusColor = switch (status) {
          TermSessionStatus.connecting => Colors.amber.shade700,
          TermSessionStatus.connected => Colors.green.shade500,
          TermSessionStatus.disconnected => Theme.of(context).colorScheme.error,
        };
        final statusText = switch (status) {
          TermSessionStatus.connecting => context.l10n.sshConnecting,
          TermSessionStatus.connected => context.l10n.sshConnected,
          TermSessionStatus.disconnected => context.l10n.sshConnectionLost,
        };
        final titleWidget = Text(
          title,
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          style: TextStyle(
            color: foregroundColor,
            fontSize: compact ? 13 : 16,
            fontWeight: FontWeight.w600,
            height: 1.05,
          ),
        );
        final statusWidget = Semantics(
          label: statusText,
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              AnimatedContainer(
                duration: const Duration(milliseconds: 220),
                width: compact ? 7 : 8,
                height: compact ? 7 : 8,
                decoration: BoxDecoration(
                  color: statusColor,
                  shape: BoxShape.circle,
                  boxShadow: status == TermSessionStatus.connected
                      ? [
                          BoxShadow(
                            color: statusColor.withValues(alpha: 0.38),
                            blurRadius: 5,
                            spreadRadius: 1,
                          ),
                        ]
                      : null,
                ),
              ),
              if (showStatusText) ...[
                const SizedBox(width: 5),
                Flexible(
                  child: Text(
                    statusText,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      color: statusColor,
                      fontSize: compact ? 10 : 11.5,
                      fontWeight: FontWeight.w600,
                      height: 1,
                    ),
                  ),
                ),
              ],
            ],
          ),
        );

        if (!showStatusText) {
          return Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              statusWidget,
              const SizedBox(width: 6),
              Flexible(child: titleWidget),
            ],
          );
        }

        return Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            titleWidget,
            SizedBox(height: compact ? 2 : 3),
            statusWidget,
          ],
        );
      },
    );
  }
}
