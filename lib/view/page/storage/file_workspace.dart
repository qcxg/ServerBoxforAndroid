import 'dart:async';
import 'dart:math';

import 'package:dartssh2/dartssh2.dart';
import 'package:fl_lib/fl_lib.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:icons_plus/icons_plus.dart';
import 'package:responsive_framework/responsive_framework.dart';
import 'package:server_box/core/extension/context/locale.dart';
import 'package:server_box/data/model/server/server.dart';
import 'package:server_box/data/model/server/server_private_info.dart';
import 'package:server_box/data/provider/server/all.dart';
import 'package:server_box/data/provider/server/single.dart';
import 'package:server_box/data/res/store.dart';
import 'package:server_box/data/ssh/ssh_sftp_link.dart';
import 'package:server_box/view/page/storage/file_pane_controller.dart';
import 'package:server_box/view/page/storage/local.dart';
import 'package:server_box/view/page/storage/sftp.dart';
import 'package:server_box/view/widget/glass_surface.dart';
import 'package:server_box/view/widget/server_reachability_dot.dart';

class FileWorkspacePage extends ConsumerStatefulWidget {
  const FileWorkspacePage({super.key});

  @override
  ConsumerState<FileWorkspacePage> createState() => _FileWorkspacePageState();
}

class _FileWorkspacePageState extends ConsumerState<FileWorkspacePage>
    with AutomaticKeepAliveClientMixin {
  final List<String> _openedServerIds = [];
  final FilePaneController _localPaneController = FilePaneController(
    FilePaneSide.local,
  );
  final Map<String, FilePaneController> _remotePaneControllers = {};
  final Map<String, SSHClient> _remoteClients = {};
  String? _selectedServerId;
  FilePaneSide _activePane = FilePaneSide.local;
  int _handledLinkRevision = -1;

  @override
  void initState() {
    super.initState();
    sshSftpLink.addListener(_handleLinkedSshServer);
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _handleLinkedSshServer();
    });
  }

  @override
  void dispose() {
    sshSftpLink.removeListener(_handleLinkedSshServer);
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    super.build(context);
    final serverState = ref.watch(serversProvider);
    final removedIds = _openedServerIds
        .where((id) => !serverState.servers.containsKey(id))
        .toList(growable: false);
    _openedServerIds.removeWhere((id) => removedIds.contains(id));
    for (final id in removedIds) {
      _remotePaneControllers.remove(id);
      _remoteClients.remove(id);
    }
    if (_selectedServerId != null &&
        !serverState.servers.containsKey(_selectedServerId)) {
      _selectedServerId = null;
    }
    final remote = _buildRemotePane(serverState);
    final compact = MediaQuery.sizeOf(context).width < 720;
    final edge = compact ? 0.0 : 8.0;
    final remoteController = _selectedServerId == null
        ? null
        : _remotePaneControllers[_selectedServerId];

    return Scaffold(
      // Keep the shared glass toolbar anchored to the physical bottom. The
      // editable path bars live at the top, so lifting the whole workspace
      // above the IME only makes the toolbar jump over the file list.
      resizeToAvoidBottomInset: false,
      appBar: _FileServerTabBar(
        openedServerIds: _openedServerIds,
        selectedServerId: _selectedServerId,
        servers: serverState.servers,
        onShowSelector: _showServerSelector,
        onSelect: _selectOpenedServer,
        onClose: _closeServer,
      ),
      body: Stack(
        children: [
          Positioned.fill(
            child: Padding(
              padding: EdgeInsets.fromLTRB(
                edge,
                compact ? 3 : 8,
                edge,
                0,
              ),
              child: Row(
                children: [
                  Expanded(
                    child: Listener(
                      onPointerDown: (_) =>
                          _activatePane(FilePaneSide.local),
                      child: _FilePaneCard(
                        key: const ValueKey('local-file-pane'),
                        side: FilePaneSide.local,
                        active: _activePane == FilePaneSide.local,
                        child: LocalFilePage(
                          embedded: true,
                          paneController: _localPaneController,
                          transferTargetController: remoteController,
                        ),
                      ),
                    ),
                  ),
                  VerticalDivider(
                    width: 1,
                    thickness: 1,
                    color: Theme.of(
                      context,
                    ).colorScheme.outlineVariant.withAlpha(95),
                  ),
                  Expanded(
                    child: Listener(
                      onPointerDown: (_) =>
                          _activatePane(FilePaneSide.remote),
                      child: _FilePaneCard(
                        key: const ValueKey('remote-file-pane'),
                        side: FilePaneSide.remote,
                        active: _activePane == FilePaneSide.remote,
                        child: remote,
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
          Positioned(
            left: compact ? 9 : 18,
            right: compact ? 9 : 18,
            bottom: 0,
            child: Align(
              alignment: Alignment.bottomCenter,
              child: ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: 440),
                child: _SharedFileToolbar(
                  local: _localPaneController,
                  remote: remoteController,
                  activeSide: _activePane,
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildRemotePane(ServersState serverState) {
    final selectedId = _selectedServerId;
    final selectedIndex = selectedId == null
        ? -1
        : _openedServerIds.indexOf(selectedId);
    final selectorIndex = _openedServerIds.length;

    return IndexedStack(
      index: selectedIndex < 0 ? selectorIndex : selectedIndex,
      children: [
        ..._openedServerIds.map((id) {
          final spi = serverState.servers[id];
          if (spi == null) return const SizedBox.shrink();
          final providerClient = ref.watch(
            serverProvider(id).select((value) => value.client),
          );
          var client = _remoteClients[id];
          if ((client == null || client.isClosed) &&
              providerClient != null &&
              !providerClient.isClosed) {
            client = providerClient;
            _remoteClients[id] = providerClient;
          }
          if (client == null || client.isClosed) {
            return _DisconnectedRemotePane(
              spi: spi,
              onReconnect: () => _openServer(spi, forceReconnect: true),
            );
          }
          return SftpPage(
            key: ValueKey('sftp-pane-$id'),
            args: SftpPageArgs(spi: spi),
            client: client,
            embedded: true,
            paneController: _remotePaneControllers.putIfAbsent(
              id,
              () => FilePaneController(FilePaneSide.remote),
            ),
            transferTargetController: _localPaneController,
          );
        }),
        _FileServerSelector(onSelected: _openServer),
      ],
    );
  }

  void _showServerSelector() {
    setState(() {
      _selectedServerId = null;
      _activePane = FilePaneSide.remote;
    });
  }

  void _selectOpenedServer(String id) {
    setState(() {
      _selectedServerId = id;
      _activePane = FilePaneSide.remote;
    });
  }

  void _closeServer(String id) {
    final removedIndex = _openedServerIds.indexOf(id);
    if (removedIndex < 0) return;
    setState(() {
      _openedServerIds.removeAt(removedIndex);
      _remoteClients.remove(id);
      _remotePaneControllers.remove(id);
      if (_selectedServerId == id) {
        _selectedServerId = _openedServerIds.isEmpty
            ? null
            : _openedServerIds[min(removedIndex, _openedServerIds.length - 1)];
      }
    });
  }

  Future<void> _openServer(
    Spi spi, {
    bool forceReconnect = false,
  }) async {
    var serverState = ref.read(serverProvider(spi.id));
    if (!forceReconnect &&
        !await guardServerReachability(context, spi, serverState.conn)) {
      return;
    }
    if (forceReconnect || serverState.client == null) {
      final (_, error) = await context.showLoadingDialog(
        fn: () async {
          await ref.read(serverProvider(spi.id).notifier).refresh();
          return true;
        },
      );
      if (!mounted) return;
      serverState = ref.read(serverProvider(spi.id));
      if (error != null || serverState.client == null) {
        context.showSnackBar(l10n.waitConnection);
        return;
      }
    }

    setState(() {
      _remoteClients[spi.id] = serverState.client!;
      if (!_openedServerIds.contains(spi.id)) {
        _openedServerIds.add(spi.id);
      }
      _selectedServerId = spi.id;
      _activePane = FilePaneSide.remote;
    });
  }

  void _handleLinkedSshServer() {
    if (!mounted || !Stores.setting.sshSftpLink.fetch()) return;
    if (_handledLinkRevision == sshSftpLink.revision) return;
    _handledLinkRevision = sshSftpLink.revision;
    final serverId = sshSftpLink.serverId;
    if (serverId == null) return;
    final spi = ref.read(serversProvider).servers[serverId];
    if (spi == null) return;
    unawaited(_openLinkedServer(spi));
  }

  Future<void> _openLinkedServer(Spi spi) async {
    var serverState = ref.read(serverProvider(spi.id));
    if (serverState.client == null) {
      await ref.read(serverProvider(spi.id).notifier).refresh();
      if (!mounted) return;
      serverState = ref.read(serverProvider(spi.id));
    }
    setState(() {
      final client = serverState.client;
      if (client != null) _remoteClients[spi.id] = client;
      if (!_openedServerIds.contains(spi.id)) {
        _openedServerIds.add(spi.id);
      }
      _selectedServerId = spi.id;
      _activePane = FilePaneSide.remote;
    });
  }

  void _activatePane(FilePaneSide side) {
    if (_activePane == side) return;
    setState(() => _activePane = side);
  }

  @override
  bool get wantKeepAlive => true;
}

final class _FileServerTabBar extends ConsumerWidget
    implements PreferredSizeWidget {
  const _FileServerTabBar({
    required this.openedServerIds,
    required this.selectedServerId,
    required this.servers,
    required this.onShowSelector,
    required this.onSelect,
    required this.onClose,
  });

  final List<String> openedServerIds;
  final String? selectedServerId;
  final Map<String, Spi> servers;
  final VoidCallback onShowSelector;
  final ValueChanged<String> onSelect;
  final ValueChanged<String> onClose;

  @override
  Size get preferredSize => const Size.fromHeight(48);

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return Row(
      children: [
        _buildAddItem(context),
        _buildDivider(context),
        Expanded(
          child: ClipRect(
            child: ListView.separated(
              scrollDirection: Axis.horizontal,
              padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 5),
              itemCount: openedServerIds.length,
              itemBuilder: (context, index) => _buildItem(context, ref, index),
              separatorBuilder: (_, _) => _buildDivider(context),
            ),
          ),
        ),
        _buildDivider(context),
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 7),
          child: Stores.setting.sshSftpLink.listenable().listenVal((linked) {
            return IconButton(
              tooltip: l10n.sshSftpLinkTip,
              isSelected: linked,
              onPressed: () {
                final next = !linked;
                Stores.setting.sshSftpLink.put(next);
                if (next) sshSftpLink.replay();
              },
              icon: const Icon(Icons.link_off_rounded),
              selectedIcon: const Icon(Icons.link_rounded),
            );
          }),
        ),
      ],
    );
  }

  Widget _buildAddItem(BuildContext context) {
    final color = selectedServerId == null ? null : Colors.grey;
    return Material(
      color: Colors.transparent,
      borderRadius: BorderRadius.circular(13),
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        borderRadius: BorderRadius.circular(13),
        onTap: onShowSelector,
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
          child: Icon(MingCute.add_circle_fill, size: 17, color: color),
        ),
      ),
    );
  }

  Widget _buildItem(BuildContext context, WidgetRef ref, int index) {
    final isMobile = ResponsiveBreakpoints.of(context).isMobile;
    final wideWidth = isMobile ? 132.0 : 172.0;
    final narrowWidth = isMobile ? 78.0 : 108.0;
    final id = openedServerIds[index];
    final spi = servers[id];
    if (spi == null) return const SizedBox.shrink();
    final selected = id == selectedServerId;
    final color = selected ? null : Colors.grey;
    final conn = ref.watch(serverProvider(id).select((value) => value.conn));
    final title = _FileConnectionTitle(
      title: spi.name,
      conn: conn,
      showStatusText: selected,
      foregroundColor: color,
    );
    final Widget button;
    if (selected) {
      button = Row(
        mainAxisAlignment: MainAxisAlignment.spaceEvenly,
        children: [
          Btn.icon(
            icon: Icon(MingCute.close_circle_fill, color: color, size: 17),
            onTap: () => onClose(id),
            padding: null,
          ),
          const SizedBox(width: 4),
          Expanded(child: title),
        ],
      );
    } else {
      button = Center(child: title);
    }
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 7),
      child: Material(
        color: Colors.transparent,
        borderRadius: BorderRadius.circular(13),
        clipBehavior: Clip.antiAlias,
        child: InkWell(
          borderRadius: BorderRadius.circular(13),
          onTap: () => onSelect(id),
          child: AnimatedContainer(
            width: selected ? wideWidth : narrowWidth,
            duration: Durations.medium3,
            curve: Curves.fastEaseInToSlowEaseOut,
            child: button,
          ),
        ),
      ),
    );
  }

  Widget _buildDivider(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 17),
      child: Container(
        color: Theme.of(context).dividerColor.withAlpha(61),
        width: 3,
      ),
    );
  }
}

final class _FileServerSelector extends ConsumerWidget {
  const _FileServerSelector({required this.onSelected});

  final ValueChanged<Spi> onSelected;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final state = ref.watch(serversProvider);
    final order = state.serverOrder;
    if (order.isEmpty) return Center(child: Text(libL10n.empty));

    return LayoutBuilder(
      builder: (context, constraints) {
        final columns = max(1, (constraints.maxWidth / 300).floor());
        return CustomScrollView(
          slivers: [
            SliverToBoxAdapter(
              child: Padding(
                padding: const EdgeInsets.fromLTRB(18, 18, 18, 10),
                child: Row(
                  children: [
                    Icon(
                      Icons.cloud_sync_rounded,
                      color: Theme.of(context).colorScheme.primary,
                    ),
                    const SizedBox(width: 10),
                    Text(
                      libL10n.server,
                      style: Theme.of(context).textTheme.titleLarge?.copyWith(
                        fontWeight: FontWeight.w800,
                      ),
                    ),
                  ],
                ),
              ),
            ),
            SliverPadding(
              padding: const EdgeInsets.fromLTRB(10, 0, 10, 148),
              sliver: SliverGrid.builder(
                itemCount: order.length,
                gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
                  crossAxisCount: columns,
                  crossAxisSpacing: 8,
                  mainAxisSpacing: 8,
                  mainAxisExtent: 78,
                ),
                itemBuilder: (context, index) {
                  final spi = state.servers[order[index]];
                  if (spi == null) return const SizedBox.shrink();
                  return _FileServerCard(
                    spi: spi,
                    onTap: () => onSelected(spi),
                  );
                },
              ),
            ),
          ],
        );
      },
    );
  }
}

final class _FileServerCard extends ConsumerWidget {
  const _FileServerCard({required this.spi, required this.onTap});

  final Spi spi;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final scheme = Theme.of(context).colorScheme;
    final connection = ref.watch(
      serverProvider(spi.id).select((value) => value.conn),
    );
    const shape = RoundedSuperellipseBorder(
      borderRadius: BorderRadius.all(Radius.circular(22)),
    );
    return Card.filled(
      margin: EdgeInsets.zero,
      color: scheme.surfaceContainerLow,
      shape: shape,
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        customBorder: shape,
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 14),
          child: Row(
            children: [
              Container(
                width: 42,
                height: 42,
                decoration: ShapeDecoration(
                  color: scheme.secondaryContainer,
                  shape: const RoundedSuperellipseBorder(
                    borderRadius: BorderRadius.all(Radius.circular(15)),
                  ),
                ),
                child: Icon(
                  Icons.dns_rounded,
                  color: scheme.onSecondaryContainer,
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      spi.name,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(fontWeight: FontWeight.w700),
                    ),
                    Text(
                      spi.oldId,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: Theme.of(context).textTheme.bodySmall?.copyWith(
                        color: scheme.onSurfaceVariant,
                      ),
                    ),
                  ],
                ),
              ),
              ServerReachabilityDot(connection: connection),
            ],
          ),
        ),
      ),
    );
  }
}

final class _DisconnectedRemotePane extends StatelessWidget {
  const _DisconnectedRemotePane({required this.spi, required this.onReconnect});

  final Spi spi;
  final VoidCallback onReconnect;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.cloud_off_rounded, size: 48, color: scheme.outline),
            const SizedBox(height: 12),
            Text(
              spi.name,
              style: Theme.of(context).textTheme.titleMedium?.copyWith(
                fontWeight: FontWeight.w700,
              ),
            ),
            const SizedBox(height: 12),
            FilledButton.icon(
              onPressed: onReconnect,
              icon: const Icon(Icons.refresh_rounded),
              label: Text(libL10n.retry),
            ),
          ],
        ),
      ),
    );
  }
}

final class _FilePaneCard extends StatelessWidget {
  const _FilePaneCard({
    super.key,
    required this.side,
    required this.active,
    required this.child,
  });

  final FilePaneSide side;
  final bool active;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return LayoutBuilder(
      builder: (context, constraints) {
        final radius = constraints.maxWidth < 280 ? 15.0 : 24.0;
        final shape = RoundedSuperellipseBorder(
          borderRadius: side == FilePaneSide.local
              ? BorderRadius.only(
                  topLeft: Radius.circular(radius),
                  bottomLeft: Radius.circular(radius),
                )
              : BorderRadius.only(
                  topRight: Radius.circular(radius),
                  bottomRight: Radius.circular(radius),
                ),
        );
        return Material(
          color: scheme.surfaceContainerLowest,
          shape: shape.copyWith(
            side: BorderSide(
              color: active
                  ? scheme.primary.withAlpha(95)
                  : scheme.outlineVariant.withAlpha(60),
              width: active ? 1.2 : 0.8,
            ),
          ),
          clipBehavior: Clip.antiAlias,
          child: child,
        );
      },
    );
  }
}

final class _SharedFileToolbar extends StatelessWidget {
  const _SharedFileToolbar({
    required this.local,
    required this.remote,
    required this.activeSide,
  });

  final FilePaneController local;
  final FilePaneController? remote;
  final FilePaneSide activeSide;

  @override
  Widget build(BuildContext context) {
    final remoteController = remote;
    final listenables = <Listenable>[local, ?remoteController];
    return ListenableBuilder(
      listenable: Listenable.merge(listenables),
      builder: (context, _) {
        final source = activeSide == FilePaneSide.remote
            ? remoteController
            : local;
        final target = activeSide == FilePaneSide.remote
            ? local
            : remoteController;
        final bound = source?.isBound == true;
        final selecting = source?.selectionMode == true;
        final selectedCount = source?.selectedCount ?? 0;
        final transferTarget = target?.transferTarget;
        final canTransfer = selectedCount > 0 && transferTarget != null;
        return SafeArea(
          top: false,
          minimum: const EdgeInsets.fromLTRB(5, 4, 5, 3),
          child: GlassSurface(
            shape: const StadiumBorder(),
            shadow: true,
            child: SizedBox(
              height: 48,
              child: Row(
                children: [
                  _ToolbarButton(
                    tooltip: selecting ? libL10n.close : libL10n.path,
                    icon: selecting
                        ? Icons.close_rounded
                        : Icons.home_rounded,
                    onPressed: !bound
                        ? null
                        : selecting
                        ? source!.clearSelection
                        : source!.goHome,
                  ),
                  _ToolbarButton(
                    tooltip: selecting ? libL10n.all : libL10n.select,
                    icon: selecting
                        ? Icons.select_all_rounded
                        : Icons.checklist_rounded,
                    onPressed: !bound
                        ? null
                        : selecting
                        ? source!.selectAll
                        : source!.toggleSelectionMode,
                    badge: selectedCount,
                  ),
                  _ToolbarButton(
                    tooltip: activeSide == FilePaneSide.local
                        ? libL10n.upload
                        : libL10n.download,
                    icon: activeSide == FilePaneSide.local
                        ? Icons.arrow_forward_rounded
                        : Icons.arrow_back_rounded,
                    onPressed: canTransfer
                        ? () => source!.transferSelected(transferTarget)
                        : null,
                  ),
                  _ToolbarButton(
                    tooltip: libL10n.add,
                    icon: Icons.add_rounded,
                    onPressed: bound && !selecting ? source!.create : null,
                  ),
                  _ToolbarButton(
                    tooltip: libL10n.delete,
                    icon: Icons.delete_outline_rounded,
                    onPressed: selectedCount > 0
                        ? source!.deleteSelected
                        : null,
                  ),
                  _ToolbarButton(
                    tooltip: MaterialLocalizations.of(
                      context,
                    ).refreshIndicatorSemanticLabel,
                    icon: Icons.refresh_rounded,
                    onPressed: bound ? source!.refresh : null,
                  ),
                ],
              ),
            ),
          ),
        );
      },
    );
  }
}

final class _ToolbarButton extends StatelessWidget {
  const _ToolbarButton({
    required this.tooltip,
    required this.icon,
    required this.onPressed,
    this.badge = 0,
  });

  final String tooltip;
  final IconData icon;
  final VoidCallback? onPressed;
  final int badge;

  @override
  Widget build(BuildContext context) {
    final iconWidget = Icon(icon, size: 21);
    return Expanded(
      child: IconButton(
        tooltip: tooltip,
        visualDensity: VisualDensity.compact,
        onPressed: onPressed,
        icon: badge > 0
            ? Badge(label: Text('$badge'), child: iconWidget)
            : iconWidget,
      ),
    );
  }
}

final class _FileConnectionTitle extends StatelessWidget {
  const _FileConnectionTitle({
    required this.title,
    required this.conn,
    required this.showStatusText,
    this.foregroundColor,
  });

  final String title;
  final ServerConn conn;
  final bool showStatusText;
  final Color? foregroundColor;

  @override
  Widget build(BuildContext context) {
    final connected = switch (conn) {
      ServerConn.connected || ServerConn.loading || ServerConn.finished => true,
      _ => false,
    };
    final statusText = switch (conn) {
      ServerConn.connecting => l10n.sshConnecting,
      ServerConn.connected || ServerConn.loading || ServerConn.finished =>
        l10n.sshConnected,
      ServerConn.failed || ServerConn.disconnected => l10n.sshConnectionLost,
    };
    final titleWidget = Text(
      title,
      maxLines: 1,
      overflow: TextOverflow.ellipsis,
      style: TextStyle(
        color: foregroundColor,
        fontSize: 13,
        fontWeight: FontWeight.w600,
        height: 1.05,
      ),
    );
    final status = Semantics(
      label: statusText,
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          _ConnectionDot(conn: conn, size: 7, glow: connected),
          if (showStatusText) ...[
            const SizedBox(width: 5),
            Flexible(
              child: Text(
                statusText,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(
                  color: _connectionColor(context, conn),
                  fontSize: 10,
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
          status,
          const SizedBox(width: 6),
          Flexible(child: titleWidget),
        ],
      );
    }
    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [titleWidget, const SizedBox(height: 2), status],
    );
  }
}

Color _connectionColor(BuildContext context, ServerConn conn) {
  final theme = Theme.of(context);
  return switch (conn) {
    ServerConn.failed => theme.colorScheme.error,
    ServerConn.disconnected => theme.colorScheme.outline,
    ServerConn.connecting => Colors.orange,
    ServerConn.connected || ServerConn.loading || ServerConn.finished =>
      theme.brightness == Brightness.dark
          ? Colors.greenAccent.shade400
          : Colors.green.shade600,
  };
}

final class _ConnectionDot extends StatelessWidget {
  const _ConnectionDot({
    required this.conn,
    this.size = 9,
    this.glow = false,
  });

  final ServerConn conn;
  final double size;
  final bool glow;

  @override
  Widget build(BuildContext context) {
    final color = _connectionColor(context, conn);
    return Container(
      width: size,
      height: size,
      decoration: BoxDecoration(
        color: color,
        shape: BoxShape.circle,
        boxShadow: glow
            ? [
                BoxShadow(
                  color: color.withValues(alpha: 0.38),
                  blurRadius: 5,
                  spreadRadius: 1,
                ),
              ]
            : null,
      ),
    );
  }
}
