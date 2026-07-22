part of 'tab.dart';

extension on _ServerPageState {
  Widget _buildServerCardTitle(ServerState s) {
    final scheme = Theme.of(context).colorScheme;
    final failed = s.conn == ServerConn.failed;
    final failureColor = Color.lerp(
      scheme.onSurfaceVariant,
      Colors.orange,
      0.34,
    )!.withAlpha(184);
    return Padding(
      padding: const EdgeInsets.only(left: 5, right: 13),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          if (failed) ...[
            DecoratedBox(
              decoration: BoxDecoration(
                color: failureColor,
                shape: BoxShape.circle,
              ),
              child: const SizedBox.square(dimension: 7),
            ),
            const SizedBox(width: 8),
          ],
          Flexible(
            child: Text(
              s.spi.name,
              style: Theme.of(context).textTheme.titleSmall?.copyWith(
                color: scheme.onSurface,
                fontWeight: FontWeight.w700,
                letterSpacing: 0.1,
              ),
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
            ),
          ),
          Icon(
            Icons.keyboard_arrow_right_rounded,
            size: 18,
            color: scheme.onSurfaceVariant.withAlpha(150),
          ),
          const Spacer(),
          _buildTopRightText(s),
          _buildTopRightWidget(s),
        ],
      ),
    );
  }

  Widget _buildTopRightWidget(ServerState s) {
    final scheme = Theme.of(context).colorScheme;
    final failureColor = Color.lerp(
      scheme.onSurfaceVariant,
      Colors.orange,
      0.34,
    )!.withAlpha(184);
    final (child, onTap) = switch (s.conn) {
      ServerConn.connecting || ServerConn.loading || ServerConn.connected => (
        const SizedBox(
          width: 27,
          height: _ServerPageState._kCardHeightMin,
        ),
        null,
      ),
      ServerConn.failed => (
        Icon(Icons.refresh_rounded, size: 21, color: failureColor),
        () {
          TryLimiter.reset(s.spi.id);
          ref.read(serversProvider.notifier).refresh(spi: s.spi);
        },
      ),
      ServerConn.disconnected => (
        Icon(
          MingCute.link_3_line,
          size: 19,
          color: scheme.onSurfaceVariant.withAlpha(150),
        ),
        () => ref.read(serversProvider.notifier).refresh(spi: s.spi),
      ),
      ServerConn.finished => (
        Icon(
          MingCute.unlink_2_line,
          size: 17,
          color: scheme.onSurfaceVariant.withAlpha(150),
        ),
        () => ref.read(serversProvider.notifier).closeServer(id: s.spi.id),
      ),
    };

    // Or the loading icon will be rescaled.
    final wrapped = child is SizedBox
        ? child
        : SizedBox(
            height: _ServerPageState._kCardHeightMin,
            width: 27,
            child: child,
          );
    if (onTap == null) return wrapped.paddingOnly(left: 10);
    return InkWell(
      borderRadius: BorderRadius.circular(7),
      onTap: onTap,
      child: wrapped,
    ).paddingOnly(left: 5);
  }

  Widget _buildTopRightText(ServerState s) {
    final hasErr = s.status.err != null;
    final str = s._getTopRightStr(s.spi);
    if (str == null) return UIs.placeholder;
    final scheme = Theme.of(context).colorScheme;
    final color = s.conn == ServerConn.failed
        ? Color.lerp(
            scheme.onSurfaceVariant,
            Colors.orange,
            0.34,
          )!.withAlpha(184)
        : scheme.onSurfaceVariant.withAlpha(156);
    return GestureDetector(
      onTap: () {
        if (!hasErr) return;
        _showFailReason(s.status);
      },
      child: Text(
        str,
        style: Theme.of(context).textTheme.bodySmall?.copyWith(color: color),
      ),
    );
  }

  void _showFailReason(ServerStatus ss) {
    final md =
        '''
${ss.err?.solution ?? l10n.unknown}

```sh
${ss.err?.message ?? 'null'}
''';
    context.showRoundDialog(
      title: libL10n.error,
      child: SingleChildScrollView(child: SimpleMarkdown(data: md)),
      actions: [
        TextButton(onPressed: () => Pfs.copy(md), child: Text(libL10n.copy)),
      ],
    );
  }

  Widget _buildDisk(ServerStatus ss, String id) {
    final cardNoti = _getCardNoti(id);
    return cardNoti.listenVal((v) {
      final isSpeed =
          v.diskIO ?? !Stores.setting.serverTabPreferDiskAmount.fetch();
      final diskUsage = ss.diskUsage;
      final total = diskUsage == null
          ? BigInt.zero.kb2Str
          : diskUsage.size.kb2Str;
      final used = diskUsage == null
          ? BigInt.zero.kb2Str
          : diskUsage.used.kb2Str;

      final (r, w) = ss.diskIO.cachedAllSpeed;

      return AnimatedSwitcher(
        duration: const Duration(milliseconds: 377),
        transitionBuilder: (child, animation) {
          return FadeTransition(opacity: animation, child: child);
        },
        child: _buildIOData(
          title: isSpeed ? 'I/O' : libL10n.disk,
          categoryIcon: isSpeed
              ? Icons.sync_alt_rounded
              : Icons.storage_rounded,
          first: (
            icon: isSpeed
                ? Icons.arrow_downward_rounded
                : Icons.storage_rounded,
            value: isSpeed ? r ?? 'N/A' : total,
            label: isSpeed ? l10n.read : 'Total',
          ),
          second: (
            icon: isSpeed
                ? Icons.arrow_upward_rounded
                : Icons.pie_chart_outline_rounded,
            value: isSpeed ? w ?? 'N/A' : used,
            label: isSpeed ? l10n.write : libL10n.used,
          ),
          onTap: () {
            cardNoti.value = v.copyWith(diskIO: !isSpeed);
          },
          key: ValueKey(isSpeed),
        ),
      );
    });
  }

  Widget _buildNet(ServerStatus ss, String id) {
    final cardNoti = _getCardNoti(id);
    final type = cardNoti.value.net ?? Stores.setting.netViewType.fetch();
    final device = ref.watch(serversProvider).servers[id]?.custom?.netDev;
    final (a, b) = type.buildValues(ss, dev: device);
    final isConnection = type == NetViewType.conn;
    return AnimatedSwitcher(
      duration: const Duration(milliseconds: 377),
      transitionBuilder: (c, anim) => FadeTransition(opacity: anim, child: c),
      child: _buildIOData(
        title: type.toStr,
        categoryIcon: isConnection
            ? Icons.link_rounded
            : Icons.swap_vert_rounded,
        first: (
          icon: isConnection
              ? Icons.link_rounded
              : Icons.arrow_downward_rounded,
          value: a,
          label: isConnection ? libL10n.conn : '↓',
        ),
        second: (
          icon: isConnection
              ? Icons.link_off_rounded
              : Icons.arrow_upward_rounded,
          value: b,
          label: isConnection ? libL10n.fail : '↑',
        ),
        onTap: () => cardNoti.value = cardNoti.value.copyWith(net: type.next),
        key: ValueKey(type),
      ),
    );
  }

  Widget _buildIOData(
    {
    required String title,
    required IconData categoryIcon,
    required ({IconData icon, String value, String label}) first,
    required ({IconData icon, String value, String label}) second,
    void Function()? onTap,
    Key? key,
  }) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    String cleanValue(String value) {
      if (value == 'N/A' || value.contains('NaN')) return '—';
      return value;
    }

    final firstValue = cleanValue(first.value);
    final secondValue = cleanValue(second.value);
    final shape = RoundedSuperellipseBorder(
      borderRadius: const BorderRadius.all(Radius.circular(15)),
      side: BorderSide(
        color: scheme.outlineVariant.withAlpha(24),
        width: 0.6,
      ),
    );
    final foreground = scheme.onSurfaceVariant.withAlpha(190);
    final titleStyle = theme.textTheme.labelSmall?.copyWith(
      color: foreground.withAlpha(158),
      fontSize: 8.5,
      fontWeight: FontWeight.w700,
      height: 1,
      letterSpacing: 0.25,
    );
    final valueStyle = theme.textTheme.labelSmall?.copyWith(
      color: foreground,
      fontSize: 9.5,
      fontWeight: FontWeight.w600,
      height: 1,
      letterSpacing: -0.1,
    );

    Widget metricRow(({IconData icon, String value, String label}) metric) {
      return SizedBox(
        height: 14,
        child: Row(
          children: [
            Icon(metric.icon, size: 11, color: foreground.withAlpha(164)),
            const SizedBox(width: 3),
            Expanded(
              child: Align(
                alignment: Alignment.centerLeft,
                child: FittedBox(
                  fit: BoxFit.scaleDown,
                  child: Text(
                    cleanValue(metric.value),
                    style: valueStyle,
                    textScaler: _textFactor,
                    maxLines: 1,
                  ),
                ),
              ),
            ),
          ],
        ),
      );
    }

    final child = Padding(
      padding: const EdgeInsets.fromLTRB(5, 4, 4, 4),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          SizedBox(
            height: 12,
            child: Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Icon(
                  categoryIcon,
                  size: 10,
                  color: foreground.withAlpha(142),
                ),
                const SizedBox(width: 2),
                Flexible(
                  child: Text(
                    title,
                    style: titleStyle,
                    textScaler: _textFactor,
                    maxLines: 1,
                    overflow: TextOverflow.fade,
                    softWrap: false,
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 2),
          metricRow(first),
          metricRow(second),
        ],
      ),
    );

    return Semantics(
      key: key,
      button: onTap != null,
      label:
          '$title, ${first.label} $firstValue, ${second.label} $secondValue',
      child: Material(
        color: scheme.surfaceContainerHighest.withAlpha(
          theme.brightness == Brightness.dark ? 82 : 68,
        ),
        shape: shape,
        clipBehavior: Clip.antiAlias,
        child: InkWell(customBorder: shape, onTap: onTap, child: child),
      ),
    );
  }
}
