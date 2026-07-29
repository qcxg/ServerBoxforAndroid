part of 'tab.dart';

final class _TopBar extends ConsumerWidget implements PreferredSizeWidget {
  final ValueNotifier<Set<String>> tags;
  final void Function(String) onTagChanged;
  final String initTag;
  final VoidCallback onAddServer;
  final bool useStatusGlass;
  final bool expandedStatus;

  const _TopBar({
    required this.initTag,
    required this.onTagChanged,
    required this.tags,
    required this.onAddServer,
    required this.useStatusGlass,
    required this.expandedStatus,
  });

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final servers = ref.watch(serversProvider);
    final order = servers.serverOrder;
    var connected = 0;
    for (final id in order) {
      final conn = ref.watch(
        serverProvider(id).select((value) => value.conn),
      );
      if (conn.index >= ServerConn.connected.index) connected++;
    }
    final total = order.length;

    if (useStatusGlass) {
      final hasTags = tags.value.isNotEmpty;
      final scheme = Theme.of(context).colorScheme;
      final statusBarHeight = MediaQuery.paddingOf(context).top;
      return SizedBox(
        height: mobileHeightWithStatus(context, hasTags),
        child: ClipRect(
          child: Stack(
            fit: StackFit.expand,
            children: [
              BackdropFilter(
                filter: ImageFilter.blur(sigmaX: 18, sigmaY: 18),
                child: DecoratedBox(
                  decoration: BoxDecoration(
                    color: scheme.surface.withAlpha(148),
                    border: Border(
                      bottom: BorderSide(
                        color: scheme.outlineVariant.withAlpha(42),
                        width: 0.7,
                      ),
                    ),
                  ),
                ),
              ),
              Padding(
                padding: EdgeInsets.fromLTRB(16, statusBarHeight + 4, 8, 0),
                child: Column(
                  children: [
                    SizedBox(
                      height: expandedStatus
                          ? _expandedTitleHeight
                          : _mobileTitleHeight,
                      child: Row(
                        children: [
                          Expanded(
                            child: Row(
                              children: [
                                Flexible(
                                  child: Text(
                                    BuildData.name,
                                    maxLines: 1,
                                    overflow: TextOverflow.ellipsis,
                                    style:
                                        (expandedStatus
                                                ? Theme.of(
                                                    context,
                                                  ).textTheme.headlineMedium
                                                : Theme.of(
                                                    context,
                                                  ).textTheme.headlineSmall)
                                            ?.copyWith(
                                              fontWeight: FontWeight.w800,
                                              letterSpacing: -0.5,
                                            ),
                                  ),
                                ),
                                SizedBox(width: expandedStatus ? 14 : 7),
                                if (expandedStatus)
                                  _ConnectionSummaryCard(
                                    connected: connected,
                                    total: total,
                                  )
                                else
                                  _ConnectionStatusPill(
                                    connected: connected,
                                    total: total,
                                  ),
                              ],
                            ),
                          ),
                          _TopBarActionButton(
                            tooltip: libL10n.add,
                            foregroundColor: scheme.onSurfaceVariant,
                            backgroundColor: scheme.surfaceContainerHighest,
                            onPressed: onAddServer,
                            icon: const Icon(Icons.add_rounded),
                            compact: !expandedStatus,
                          ),
                          const SizedBox(width: 4),
                          _TopBarActionButton(
                            tooltip: libL10n.setting,
                            foregroundColor: scheme.onSecondaryContainer,
                            backgroundColor: scheme.secondaryContainer,
                            onPressed: () => SettingsPage.route.go(context),
                            icon: const Icon(Icons.settings_rounded),
                            compact: !expandedStatus,
                          ),
                          const SizedBox(width: 4),
                          _TopBarActionButton(
                            tooltip: libL10n.exit,
                            foregroundColor: scheme.onErrorContainer,
                            backgroundColor: scheme.errorContainer,
                            onPressed: () => _confirmExit(context, ref),
                            icon: const Icon(Icons.power_settings_new_rounded),
                            compact: !expandedStatus,
                          ),
                        ],
                      ),
                    ),
                    if (hasTags)
                      SizedBox(
                        height: TagSwitcher.kTagBtnHeight,
                        child: TagSwitcher(
                          tags: tags,
                          onTagChanged: onTagChanged,
                          initTag: initTag,
                          singleLine: true,
                          padding: EdgeInsets.zero,
                        ),
                      ),
                  ],
                ),
              ),
            ],
          ),
        ),
      );
    }

    final scheme = Theme.of(context).colorScheme;
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 7, 10, 7),
      child: Row(
        children: [
          Text(
            BuildData.name,
            maxLines: 1,
            style: Theme.of(context).textTheme.titleLarge?.copyWith(
              fontWeight: FontWeight.w800,
              letterSpacing: -0.35,
            ),
          ),
          const SizedBox(width: 16),
          _ConnectionSummaryCard(connected: connected, total: total),
          const SizedBox(width: 12),
          TagSwitcher(
            tags: tags,
            onTagChanged: onTagChanged,
            initTag: initTag,
            singleLine: true,
            reversed: true,
          ).expanded(),
          const SizedBox(width: 8),
          _TopBarActionButton(
            tooltip: libL10n.add,
            foregroundColor: scheme.onSurfaceVariant,
            backgroundColor: scheme.surfaceContainerHighest,
            onPressed: onAddServer,
            icon: const Icon(Icons.add_rounded),
          ),
          const SizedBox(width: 6),
          _TopBarActionButton(
            tooltip: libL10n.exit,
            foregroundColor: scheme.onErrorContainer,
            backgroundColor: scheme.errorContainer,
            onPressed: () => _confirmExit(context, ref),
            icon: const Icon(Icons.power_settings_new_rounded),
          ),
        ],
      ),
    );
  }

  Future<void> _confirmExit(BuildContext context, WidgetRef ref) async {
    final confirmed = await context.showRoundDialog<bool>(
      title: libL10n.exit,
      child: Text(context.l10n.exitBackgroundDescription),
      actions: [
        TextButton(
          onPressed: () => context.pop(false),
          child: Text(libL10n.cancel),
        ),
        FilledButton.icon(
          onPressed: () => context.pop(true),
          icon: const Icon(Icons.power_settings_new_rounded),
          label: Text(context.l10n.stopAndExit),
        ),
      ],
    );
    if (confirmed != true) return;

    final serverNotifier = ref.read(serversProvider.notifier);
    final serverIds = ref.read(serversProvider).serverOrder.toList();
    serverNotifier.stopAutoRefresh();
    ref.read(sftpProvider.notifier).dispose();
    TermSessionManager.stopAllConnections();
    for (final id in serverIds) {
      ref.read(portForwardProvider(id).notifier).dispose();
    }
    serverNotifier.closeServer();
    await WakelockPlus.disable();
    await MethodChans.exitApp();
  }

  static const _mobileTitleHeight = 54.0;
  static const _expandedTitleHeight = 68.0;

  static double mobileHeight(bool hasTags, {bool expanded = false}) {
    return (expanded ? _expandedTitleHeight : _mobileTitleHeight) +
        4 +
        (hasTags ? TagSwitcher.kTagBtnHeight : 0);
  }

  static double mobileHeightWithStatus(BuildContext context, bool hasTags) {
    final expanded = !AppLayout.useCompactNavigation(
      MediaQuery.sizeOf(context).width,
    );
    return MediaQuery.paddingOf(context).top +
        mobileHeight(hasTags, expanded: expanded);
  }

  @override
  Size get preferredSize => Size.fromHeight(
    useStatusGlass
        ? mobileHeight(tags.value.isNotEmpty, expanded: expandedStatus)
        : 64,
  );
}

final class _ConnectionStatusPill extends StatelessWidget {
  const _ConnectionStatusPill({required this.connected, required this.total});

  final int connected;
  final int total;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final statusColor = _connectionSummaryColor(context, connected, total);
    return Tooltip(
      message: context.l10n.connectionStats,
      child: Material(
        color: scheme.surfaceContainerHighest.withAlpha(205),
        shape: const StadiumBorder(),
        clipBehavior: Clip.antiAlias,
        child: InkWell(
          customBorder: const StadiumBorder(),
          onTap: () => ConnectionStatsPage.route.go(context),
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 5),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Container(
                  width: 7,
                  height: 7,
                  decoration: BoxDecoration(
                    color: statusColor,
                    shape: BoxShape.circle,
                  ),
                ),
                const SizedBox(width: 5),
                Text(
                  '$connected/$total ${context.libL10n.conn}',
                  maxLines: 1,
                  style: Theme.of(context).textTheme.labelSmall?.copyWith(
                    color: scheme.onSurfaceVariant,
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

final class _ConnectionSummaryCard extends StatelessWidget {
  const _ConnectionSummaryCard({required this.connected, required this.total});

  final int connected;
  final int total;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final statusColor = _connectionSummaryColor(context, connected, total);
    final progress = total == 0 ? 0.0 : connected / total;
    return Tooltip(
      message: context.l10n.connectionStatsDesc,
      child: Material(
        color: Color.alphaBlend(
          statusColor.withAlpha(12),
          scheme.surfaceContainerHigh,
        ),
        shape: RoundedSuperellipseBorder(
          borderRadius: const BorderRadius.all(Radius.circular(18)),
          side: BorderSide(
            color: scheme.outlineVariant.withAlpha(70),
            width: 0.7,
          ),
        ),
        clipBehavior: Clip.antiAlias,
        child: InkWell(
          onTap: () => ConnectionStatsPage.route.go(context),
          child: SizedBox(
            width: 196,
            height: 48,
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 11, vertical: 7),
              child: Row(
                children: [
                  Container(
                    width: 29,
                    height: 29,
                    decoration: BoxDecoration(
                      color: statusColor.withAlpha(28),
                      shape: BoxShape.circle,
                    ),
                    child: Icon(
                      Icons.lan_rounded,
                      size: 17,
                      color: statusColor,
                    ),
                  ),
                  const SizedBox(width: 9),
                  Expanded(
                    child: Column(
                      mainAxisAlignment: MainAxisAlignment.center,
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          '$connected/$total ${context.libL10n.conn}',
                          maxLines: 1,
                          style: Theme.of(context).textTheme.labelLarge?.copyWith(
                            color: scheme.onSurface,
                            fontWeight: FontWeight.w700,
                          ),
                        ),
                        const SizedBox(height: 5),
                        LinearProgressIndicator(
                          value: progress,
                          minHeight: 3,
                          borderRadius: BorderRadius.circular(3),
                          color: statusColor,
                          backgroundColor: scheme.surfaceContainerHighest,
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(width: 6),
                  Icon(
                    Icons.chevron_right_rounded,
                    size: 18,
                    color: scheme.onSurfaceVariant,
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

final class _TopBarActionButton extends StatelessWidget {
  const _TopBarActionButton({
    required this.tooltip,
    required this.foregroundColor,
    required this.backgroundColor,
    required this.onPressed,
    required this.icon,
    this.compact = false,
  });

  final String tooltip;
  final Color foregroundColor;
  final Color backgroundColor;
  final VoidCallback onPressed;
  final Widget icon;
  final bool compact;

  @override
  Widget build(BuildContext context) {
    final dimension = compact ? 40.0 : 44.0;
    return SizedBox.square(
      dimension: dimension,
      child: IconButton(
        tooltip: tooltip,
        style: IconButton.styleFrom(
          foregroundColor: foregroundColor,
          backgroundColor: backgroundColor,
          minimumSize: Size.square(dimension),
          maximumSize: Size.square(dimension),
          padding: EdgeInsets.zero,
        ),
        onPressed: onPressed,
        icon: icon,
      ),
    );
  }
}

Color _connectionSummaryColor(
  BuildContext context,
  int connected,
  int total,
) {
  final scheme = Theme.of(context).colorScheme;
  if (total == 0 || connected == 0) return scheme.outline;
  if (connected >= total) {
    return Theme.of(context).brightness == Brightness.dark
        ? Colors.greenAccent.shade400
        : Colors.green.shade600;
  }
  return scheme.tertiary;
}
