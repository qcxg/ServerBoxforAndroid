import 'package:flutter/material.dart';
import 'package:server_box/core/chan.dart';
import 'package:server_box/core/extension/context/locale.dart';
import 'package:server_box/data/model/server/server.dart';
import 'package:server_box/data/model/server/server_private_info.dart';
import 'package:server_box/data/ssh/server_reachability.dart';

Future<bool> guardServerReachability(
  BuildContext context,
  Spi spi,
  ServerConn connection,
) async {
  switch (reachabilityFromServerConnection(connection)) {
    case ServerReachability.online:
      offlineConnectionGate.clear(spi.id);
      return true;
    case ServerReachability.checking:
      offlineConnectionGate.clear(spi.id);
      await MethodChans.showToast(context.l10n.serverCheckingTip);
      return false;
    case ServerReachability.offline:
      if (offlineConnectionGate.consumeConfirmation(spi.id)) return true;
      await MethodChans.showToast(context.l10n.serverOfflineForceTip);
      return false;
  }
}

class ServerReachabilityDot extends StatelessWidget {
  const ServerReachabilityDot({
    super.key,
    required this.connection,
    this.size = 9,
    this.borderColor,
    this.borderWidth = 0,
    this.glow = false,
  });

  final ServerConn connection;
  final double size;
  final Color? borderColor;
  final double borderWidth;
  final bool glow;

  @override
  Widget build(BuildContext context) {
    final state = reachabilityFromServerConnection(connection);
    final color = serverReachabilityColor(context, state);
    final label = switch (state) {
      ServerReachability.checking => context.l10n.serverChecking,
      ServerReachability.online => context.l10n.serverOnline,
      ServerReachability.offline => context.l10n.serverOffline,
    };
    return Semantics(
      label: label,
      child: AnimatedContainer(
        duration: Durations.short3,
        width: size,
        height: size,
        decoration: BoxDecoration(
          color: color,
          shape: BoxShape.circle,
          border: borderWidth > 0
              ? Border.all(
                  color: borderColor ?? Colors.transparent,
                  width: borderWidth,
                )
              : null,
          boxShadow: glow && state == ServerReachability.online
              ? [
                  BoxShadow(
                    color: color.withValues(alpha: 0.38),
                    blurRadius: 5,
                    spreadRadius: 1,
                  ),
                ]
              : null,
        ),
      ),
    );
  }
}

Color serverReachabilityColor(
  BuildContext context,
  ServerReachability state,
) {
  final theme = Theme.of(context);
  return switch (state) {
    ServerReachability.checking => Colors.amber.shade700,
    ServerReachability.online => theme.brightness == Brightness.dark
        ? Colors.greenAccent.shade400
        : Colors.green.shade600,
    ServerReachability.offline => theme.colorScheme.error,
  };
}
