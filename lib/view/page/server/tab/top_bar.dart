part of 'tab.dart';

final class _TopBar extends ConsumerWidget implements PreferredSizeWidget {
  final ValueNotifier<Set<String>> tags;
  final void Function(String) onTagChanged;
  final String initTag;
  final VoidCallback onAddServer;

  const _TopBar({
    required this.initTag,
    required this.onTagChanged,
    required this.tags,
    required this.onAddServer,
  });

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final useStatusGlass = AppLayout.useStatusGlass(
      MediaQuery.sizeOf(context).width,
    );
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
                      height: _mobileTitleHeight,
                      child: Row(
                        children: [
                          Expanded(
                            child: Text(
                              BuildData.name,
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: Theme.of(context).textTheme.headlineSmall
                                  ?.copyWith(
                                    fontWeight: FontWeight.w800,
                                    letterSpacing: -0.5,
                                  ),
                            ),
                          ),
                          IconButton.filled(
                            tooltip: libL10n.add,
                            style: IconButton.styleFrom(
                              foregroundColor: scheme.onSurfaceVariant,
                              backgroundColor: scheme.surfaceContainerHighest,
                            ),
                            onPressed: onAddServer,
                            icon: const Icon(Icons.add_rounded),
                          ),
                          const SizedBox(width: 4),
                          IconButton.filledTonal(
                            tooltip: libL10n.setting,
                            onPressed: () => SettingsPage.route.go(context),
                            icon: const Icon(Icons.settings_rounded),
                          ),
                          const SizedBox(width: 4),
                          IconButton.filledTonal(
                            tooltip: libL10n.exit,
                            style: IconButton.styleFrom(
                              foregroundColor: scheme.onErrorContainer,
                              backgroundColor: scheme.errorContainer,
                            ),
                            onPressed: () => _confirmExit(context, ref),
                            icon: const Icon(Icons.power_settings_new_rounded),
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
    final connectionText = '$connected/$total ${context.libL10n.conn}';
    final leading = MouseRegion(
      cursor: SystemMouseCursors.click,
      child: Tooltip(
        message: context.l10n.connectionStats,
        child: InkWell(
          onTap: () => ConnectionStatsPage.route.go(context),
          child: Text(
            connectionText,
            style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w600),
          ),
        ),
      ),
    );

    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          leading,
          const SizedBox(width: 16),
          TagSwitcher(
            tags: tags,
            onTagChanged: onTagChanged,
            initTag: initTag,
            singleLine: true,
            reversed: true,
          ).expanded(),
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

  static double mobileHeight(bool hasTags) {
    return _mobileTitleHeight +
        4 +
        (hasTags ? TagSwitcher.kTagBtnHeight : 0);
  }

  static double mobileHeightWithStatus(BuildContext context, bool hasTags) {
    return MediaQuery.paddingOf(context).top + mobileHeight(hasTags);
  }

  @override
  Size get preferredSize => Size.fromHeight(
    mobileHeight(tags.value.isNotEmpty),
  );
}
