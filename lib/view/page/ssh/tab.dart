import 'dart:convert';
import 'dart:math';

import 'package:fl_lib/fl_lib.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:icons_plus/icons_plus.dart';
import 'package:responsive_framework/responsive_framework.dart';
import 'package:server_box/core/extension/context/locale.dart';
import 'package:server_box/core/route.dart';
import 'package:server_box/data/model/server/server.dart';
import 'package:server_box/data/model/server/server_private_info.dart';
import 'package:server_box/data/provider/server/all.dart';
import 'package:server_box/data/provider/server/single.dart';
import 'package:server_box/data/res/store.dart';
import 'package:server_box/data/ssh/session_manager.dart';
import 'package:server_box/data/ssh/ssh_sftp_link.dart';
import 'package:server_box/view/page/server/edit/edit.dart';
import 'package:server_box/view/page/ssh/page/page.dart';
import 'package:server_box/view/widget/ssh_connection_status.dart';

class SSHTabPage extends ConsumerStatefulWidget {
  const SSHTabPage({super.key});

  @override
  ConsumerState<SSHTabPage> createState() => _SSHTabPageState();

  static const route = AppRouteNoArg(page: SSHTabPage.new, path: '/ssh');
}

typedef _TabMap =
    Map<
      String,
      ({
        Widget page,
        FocusNode? focus,
        ValueNotifier<bool>? visible,
        ValueNotifier<TermSessionStatus>? status,
        GlobalKey<SSHPageState>? sshPageKey,
      })
    >;

class _SSHTabPageState extends ConsumerState<SSHTabPage>
    with TickerProviderStateMixin, AutomaticKeepAliveClientMixin, RestorationMixin {
  // Restorable state for tab restoration
  final RestorableString _restorableTabsState = RestorableString('');

  @override
  String get restorationId => 'ssh_tab_page';

  @override
  void restoreState(RestorationBucket? oldBucket, bool initialRestore) {
    registerForRestoration(_restorableTabsState, 'tabs_state');

    // Restore tabs after the first frame
    if (initialRestore && _restorableTabsState.value.isNotEmpty) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        _restoreTabs();
      });
    }
  }

  void _saveTabsState() {
    final tabsData = <Map<String, dynamic>>[];
    for (final entry in _tabMap.entries) {
      if (entry.key == libL10n.add) continue; // Skip the add button

      final sshPageState = entry.value.sshPageKey?.currentState;
      final sshPage = entry.value.page as SSHPage;
      final serverId = sshPageState?.widget.args.spi.id ?? sshPage.args.spi.id;
      final tmuxSession =
          sshPageState?.tmuxCurrentSession ?? sshPage.args.tmuxSession;
      final tmuxWindow =
          sshPageState?.tmuxCurrentWindow ?? sshPage.args.tmuxWindow;

      tabsData.add({
        'serverId': serverId,
        'tmuxSession': tmuxSession,
        'tmuxWindow': tmuxWindow,
      });
    }
    _restorableTabsState.value = jsonEncode(tabsData);
  }

  void _restoreTabs() {
    try {
      final tabsData = jsonDecode(_restorableTabsState.value) as List;
      for (final tabData in tabsData) {
        final serverId = tabData['serverId'] as String;
        final tmuxSession = tabData['tmuxSession'] as String?;
        final tmuxWindow = tabData['tmuxWindow'] as int?;

        // Find the server
        final servers = Stores.server.fetch();
        final spi = servers.where((s) => s.id == serverId).firstOrNull;
        if (spi == null) {
          continue;
        }

        // Add the tab with tmux state
        _addTab(spi, tmuxSession: tmuxSession, tmuxWindow: tmuxWindow);
      }
    } catch (e, st) {
      Loggers.app.warning('Failed to restore SSH tabs', e, st);
    }
  }

  late final _TabMap _tabMap = {
    libL10n.add: (
      page: _AddPage(
        sortVersionVN: _sortVersionVN,
        onTapInitCard: _onTapInitCard,
        onLongPressInitCard: _onLongPressInitCard,
      ),
      focus: null,
      visible: null,
      status: null,
      sshPageKey: null,
    ),
  };
  final _pageCtrl = PageController();
  final _fabVN = 0.vn;
  final _tabRN = RNode();
  final _sortVersionVN = 0.vn;

  @override
  void dispose() {
    _restorableTabsState.dispose();
    final entries = _tabMap.values.toList(growable: false);
    _tabMap.clear();
    for (final entry in entries) {
      _disposeTabEntry(entry);
    }
    _pageCtrl.dispose();
    _tabRN.dispose();
    _fabVN.dispose();
    _sortVersionVN.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    super.build(context);
    final isMobile = ResponsiveBreakpoints.of(context).isMobile;
    return Scaffold(
      appBar: PreferredSizeListenBuilder(
        listenable: _tabRN,
        builder: () {
          return _TabBar(
            idxVN: _fabVN,
            map: _tabMap,
            onTap: _onTapTab,
            onClose: _onTapClose,
            snippetBtn: buildSnippetBtn(context),
            sortBtn: buildSortBtn(context),
            searchBtn: buildSearchBtn(context),
            historyBtn: buildHistoryBtn(context),
          );
        },
      ),
      body: _buildBody(),
      floatingActionButton: Padding(
        padding: EdgeInsets.only(bottom: isMobile ? 80 : 0),
        child: ValBuilder(
          listenable: _fabVN,
          builder: (idx) {
            if (idx != 0) return const SizedBox();
            return FloatingActionButton.extended(
              heroTag: 'sshAddServer',
              onPressed: () => ServerEditPage.route.go(context),
              tooltip: libL10n.add,
              icon: const Icon(Icons.add_rounded),
              label: Text(libL10n.add),
            );
          },
        ),
      ),
    );
  }

  Widget _buildBody() {
    return ListenBuilder(
      listenable: _tabRN,
      builder: () {
        final entries = _tabMap.entries.toList(growable: false);
        return PageView.builder(
          physics: const NeverScrollableScrollPhysics(),
          controller: _pageCtrl,
          itemCount: entries.length,
          itemBuilder: (_, idx) {
            return entries[idx].value.page;
          },
          onPageChanged: (value) {
            _fabVN.value = value;
            _syncVisibleTabs(value);
          },
        );
      },
    );
  }

  @override
  bool get wantKeepAlive => true;
}

extension on _SSHTabPageState {
  void _applySort({required int sortBy, required bool sortAsc}) {
    Stores.setting.sshPageSortBy.put(sortBy);
    Stores.setting.sshPageSortAsc.put(sortAsc);
    _tabRN.notify();
    _sortVersionVN.notify();
  }

  void _disposeTabEntry(
    ({
      Widget page,
      FocusNode? focus,
      ValueNotifier<bool>? visible,
      ValueNotifier<TermSessionStatus>? status,
      GlobalKey<SSHPageState>? sshPageKey,
    })
    entry,
  ) {
    entry.focus?.dispose();
    entry.visible?.dispose();
    entry.status?.dispose();
  }

  ({
    Widget page,
    FocusNode? focus,
    ValueNotifier<bool>? visible,
    ValueNotifier<TermSessionStatus>? status,
    GlobalKey<SSHPageState>? sshPageKey,
  })?
  _detachTabEntry(String name) {
    return _tabMap.remove(name);
  }

  void _disposeTabEntryAfterFrame(
    ({
      Widget page,
      FocusNode? focus,
      ValueNotifier<bool>? visible,
      ValueNotifier<TermSessionStatus>? status,
      GlobalKey<SSHPageState>? sshPageKey,
    })?
    entry,
  ) {
    if (entry == null) return;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _disposeTabEntry(entry);
    });
  }

  Future<void> _handleTabRemoved(
    String name, {
    Duration duration = Durations.medium1,
    Curve curve = Curves.fastEaseInToSlowEaseOut,
  }) async {
    final removedIndex = _tabMap.keys.toList().indexOf(name);
    final currentIndex = _fabVN.value;
    final removed = _detachTabEntry(name);
    if (!mounted) {
      if (removed != null) {
        _disposeTabEntry(removed);
      }
      return;
    }

    _tabRN.notify();
    _disposeTabEntryAfterFrame(removed);
    _saveTabsState();
    if (_tabMap.isEmpty) {
      _fabVN.value = 0;
      return;
    }

    final maxIndex = _tabMap.length - 1;
    final nextIndex = () {
      if (removedIndex == -1) {
        return currentIndex.clamp(0, maxIndex);
      }
      if (currentIndex > removedIndex) {
        return (currentIndex - 1).clamp(0, maxIndex);
      }
      return currentIndex.clamp(0, maxIndex);
    }();

    WidgetsBinding.instance.addPostFrameCallback((_) async {
      if (!mounted || !_pageCtrl.hasClients) return;
      await _toPage(nextIndex, duration: duration, curve: curve);
    });
  }

  void _syncVisibleTabs(int activeIndex) {
    final entries = _tabMap.entries.toList(growable: false);
    for (var i = 0; i < entries.length; i++) {
      entries[i].value.visible?.value = i == activeIndex;
    }
  }

  Future<void> _addTab(Spi spi, {String? tmuxSession, int? tmuxWindow}) async {
    final name = _generateTabName(spi);
    final key = GlobalKey<SSHPageState>(debugLabel: name);
    final focusNode = FocusNode();
    final visibleVN = ValueNotifier(false);
    final statusVN = ValueNotifier(TermSessionStatus.connecting);
    final args = SshPageArgs(
      spi: spi,
      notFromTab: false,
      onSessionEnd: () {
        _handleTabRemoved(name).ignore();
      },
      focusNode: focusNode,
      visibleListenable: visibleVN,
      connectionStatus: statusVN,
      tmuxSession: tmuxSession,
      tmuxWindow: tmuxWindow,
      onTmuxStateChanged: _saveTabsState,
    );
    _tabMap[name] = (
      page: SSHPage(
        key: key,
        args: args,
      ),
      focus: focusNode,
      visible: visibleVN,
      status: statusVN,
      sshPageKey: key,
    );
    _tabRN.notify();
    Stores.history.sshServerHistory.add(spi.id);
    _saveTabsState();
    // Wait for the page to be built
    await Future.delayed(Durations.short3);
    final idx = _tabMap.keys.toList().indexOf(name);
    await _toPage(idx);
  }

  String _generateTabName(Spi spi) {
      final reg = RegExp('${spi.name}\\((\\d+)\\)');
      final idxs = _tabMap.keys
          .map((e) => reg.firstMatch(e))
          .map((e) => e?.group(1))
          .whereType<String>();
      if (idxs.isEmpty) {
      return _tabMap.keys.contains(spi.name) ? '${spi.name}(1)' : spi.name;
      }
      final biggest = idxs.reduce((a, b) => a.length > b.length ? a : b);
      final biggestInt = int.tryParse(biggest);
      if (biggestInt != null && biggestInt > 0) {
      return '${spi.name}(${biggestInt + 1})';
      }
      return spi.name;
  }

  void _onTapInitCard(Spi spi) async {
    await _addTab(spi);
  }

  void _onLongPressInitCard(Spi spi) {
    ServerEditPage.route.go(context, args: SpiRequiredArgs(spi));
  }

  Future<void> _toPage(
    int idx, {
    Duration duration = Durations.short3,
    Curve curve = Curves.fastEaseInToSlowEaseOut,
  }) async {
    _fabVN.value = idx;
    await _pageCtrl.animateToPage(idx, duration: duration, curve: curve);
    _syncVisibleTabs(idx);
    final focus = _tabMap.values.elementAt(idx).focus;
    if (focus != null) {
      FocusScope.of(context).requestFocus(focus);
    }
    if (idx > 0) {
      final page = _tabMap.values.elementAt(idx).page;
      if (page is SSHPage) {
        sshSftpLink.selectServer(page.args.spi.id);
      }
    }
  }

  void _onTapTab(int idx) async {
    await _toPage(idx);
  }

  void _onTapClose(String name) async {
    final confirm = await contextSafe?.showRoundDialog(
      title: libL10n.attention,
      child: Text('${libL10n.close} SSH ${libL10n.conn}($name) ?'),
      actions: Btnx.okReds,
    );
    Future.delayed(Durations.short1, FocusScope.of(context).unfocus);
    if (confirm != true) return;
    await _handleTabRemoved(name);
  }

  Widget buildSortBtn(BuildContext context) {
    final sortBy = Stores.setting.sshPageSortBy.fetch();
    final sortAsc = Stores.setting.sshPageSortAsc.fetch();
    final sortIcon = sortBy == 0
        ? (sortAsc ? Icons.sort_by_alpha : Icons.sort)
        : (sortAsc ? Icons.arrow_upward : Icons.arrow_downward);

    return Btn.icon(
      icon: Icon(sortIcon, size: 18),
      onTap: () => showSortMenu(context),
    );
  }

  void showSortMenu(BuildContext context) {
    final sortBy = Stores.setting.sshPageSortBy.fetch();
    final sortAsc = Stores.setting.sshPageSortAsc.fetch();

    context.showRoundDialog(
      title: l10n.sort,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          _SortOption(
            icon: Icons.sort_by_alpha,
            label: '${l10n.sortByName} (A-Z)',
            selected: sortBy == 0 && sortAsc,
            onTap: () {
              _applySort(sortBy: 0, sortAsc: true);
              context.pop();
            },
          ),
          _SortOption(
            icon: Icons.sort,
            label: '${l10n.sortByName} (Z-A)',
            selected: sortBy == 0 && !sortAsc,
            onTap: () {
              _applySort(sortBy: 0, sortAsc: false);
              context.pop();
            },
          ),
          _SortOption(
            icon: Icons.arrow_upward,
            label: '${l10n.sortByJoinTime} (${l10n.ascending})',
            selected: sortBy == 1 && sortAsc,
            onTap: () {
              _applySort(sortBy: 1, sortAsc: true);
              context.pop();
            },
          ),
          _SortOption(
            icon: Icons.arrow_downward,
            label: '${l10n.sortByJoinTime} (${l10n.descending})',
            selected: sortBy == 1 && !sortAsc,
            onTap: () {
              _applySort(sortBy: 1, sortAsc: false);
              context.pop();
            },
          ),
        ],
      ),
    );
  }

  Widget buildSearchBtn(BuildContext context) {
    return Btn.icon(
      icon: const Icon(Icons.search, size: 18),
      onTap: () => showSearchDialog(context),
    );
  }

  void showSearchDialog(BuildContext context) {
    final serverState = ref.read(serversProvider);
    final allServers = serverState.serverOrder
        .map((id) => serverState.servers[id])
        .whereType<Spi>()
        .toList();

    showSearch(
      context: context,
      delegate: SearchPage<Spi>(
        padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 3),
        future: (q) async {
          if (q.isEmpty) return [];
          return allServers
              .where(
                (spi) =>
                    spi.name.toLowerCase().contains(q.toLowerCase()) ||
                    spi.user.toLowerCase().contains(q.toLowerCase()) ||
                    spi.ip.contains(q),
              )
              .toList();
        },
        builder: (ctx, spi) => ListTile(
          title: Text(spi.name),
          subtitle: Text('${spi.user}@${spi.ip}:${spi.port}'),
          trailing: const Icon(Icons.chevron_right),
          onTap: () {
            ctx.pop();
            _onTapInitCard(spi);
          },
        ),
      ),
    );
  }

  Widget buildHistoryBtn(BuildContext context) {
    return Btn.icon(
      icon: const Icon(Icons.history, size: 18),
      onTap: () => showHistoryDialog(context),
    );
  }

  Widget buildSnippetBtn(BuildContext context) {
    return Btn.icon(
      icon: const Icon(Icons.code, size: 18),
      onTap: () {
        final idx = _fabVN.value;
        if (idx == 0) return;
        final entry = _tabMap.values.elementAtOrNull(idx);
        entry?.sshPageKey?.currentState?.pickSnippetFromToolbar();
      },
    );
  }

  void showHistoryDialog(BuildContext context) {
    final history = Stores.history.sshServerHistory.all.cast<String>();
    if (history.isEmpty) {
      context.showRoundDialog(
        title: l10n.serverHistory,
        child: Text(libL10n.empty),
        actions: [Btn.ok(onTap: context.pop)],
      );
      return;
    }

    final serverState = ref.read(serversProvider);
    context.showRoundDialog(
      title: l10n.serverHistory,
      child: SizedBox(
        width: 420,
        height: 300,
        child: ListView.builder(
          itemCount: history.length,
          itemBuilder: (_, idx) {
            final id = history[idx];
            final spi = serverState.servers[id];
            return ListTile(
              contentPadding: EdgeInsets.zero,
              title: Text(spi?.name ?? id),
              subtitle: spi != null
                  ? Text('${spi.user}@${spi.ip}:${spi.port}')
                  : null,
              trailing: const Icon(Icons.chevron_right),
              onTap: () {
                context.pop();
                if (spi != null) {
                  _onTapInitCard(spi);
                } else {
                  context.showSnackBar(libL10n.error);
                }
              },
            );
          },
        ),
      ),
      actions: [
        TextButton(
          onPressed: () {
            Stores.history.sshServerHistory.clear();
            context.pop();
          },
          child: Text(l10n.clearHistory),
        ),
        Btn.ok(onTap: context.pop),
      ],
    );
  }
}

final class _TabBar extends StatelessWidget implements PreferredSizeWidget {
  const _TabBar({
    required this.idxVN,
    required this.map,
    required this.onTap,
    required this.onClose,
    required this.snippetBtn,
    required this.sortBtn,
    required this.searchBtn,
    required this.historyBtn,
  });

  final ValueListenable<int> idxVN;
  final _TabMap map;
  final void Function(int idx) onTap;
  final void Function(String name) onClose;
  final Widget snippetBtn;
  final Widget sortBtn;
  final Widget searchBtn;
  final Widget historyBtn;

  List<String> get names => map.keys.toList();
  List<String> get connectionNames => names.skip(1).toList();

  @override
  Size get preferredSize => const Size.fromHeight(48);

  @override
  Widget build(BuildContext context) {
    return ListenBuilder(
      listenable: idxVN,
      builder: () {
        final showHomeActions = idxVN.value == 0;
        final showSnippetAction = idxVN.value != 0;
        return Row(
          children: [
            _buildAddItem(context),
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 17),
              child: Container(
                color: Theme.of(context).dividerColor.withAlpha(61),
                width: 3,
              ),
            ),
            Expanded(
              child: ClipRect(
                child: ListView.separated(
                  scrollDirection: Axis.horizontal,
                  padding: const EdgeInsets.symmetric(
                    horizontal: 7,
                    vertical: 5,
                  ),
                  itemCount: connectionNames.length,
                  itemBuilder: (_, idx) => _buildItem(context, idx + 1),
                  separatorBuilder: (_, _) => Padding(
                    padding: const EdgeInsets.symmetric(vertical: 17),
                    child: Container(
                      color: Theme.of(context).dividerColor.withAlpha(61),
                      width: 3,
                    ),
                  ),
                ),
              ),
            ),
            if (showSnippetAction) ...[
              Padding(
                padding: const EdgeInsets.symmetric(vertical: 17),
                child: Container(
                  color: Theme.of(context).dividerColor.withAlpha(61),
                  width: 3,
                ),
              ),
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 7),
                child: snippetBtn,
              ),
            ],
            if (showHomeActions) ...[
              Padding(
                padding: const EdgeInsets.symmetric(vertical: 17),
                child: Container(
                  color: Theme.of(context).dividerColor.withAlpha(61),
                  width: 3,
                ),
              ),
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 7),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    sortBtn,
                    const SizedBox(width: 7),
                    searchBtn,
                    const SizedBox(width: 7),
                    historyBtn,
                  ],
                ),
              ),
            ],
          ],
        );
      },
    );
  }

  Widget _buildAddItem(BuildContext context) {
    final color = idxVN.value == 0 ? null : Colors.grey;
    return Material(
      color: Colors.transparent,
      borderRadius: BorderRadius.circular(13),
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        borderRadius: BorderRadius.circular(13),
        onTap: () => onTap(0),
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
          child: Icon(MingCute.add_circle_fill, size: 17, color: color),
        ),
      ),
    );
  }

  Widget _buildItem(BuildContext context, int idx) {
    final isMobile = ResponsiveBreakpoints.of(context).isMobile;
    final wideWidth = isMobile ? 132.0 : 172.0;
    final narrowWidth = isMobile ? 78.0 : 108.0;
    final name = names[idx];
    final selected = idxVN.value == idx;
    final color = selected ? null : Colors.grey;
    final status = map[name]!.status!;

    final title = SshConnectionTitle(
      title: name,
      statusListenable: status,
      showStatusText: selected,
      compact: true,
      foregroundColor: color,
    );
    final Widget btn;
    if (selected) {
      btn = Row(
        mainAxisAlignment: MainAxisAlignment.spaceEvenly,
        children: [
          Btn.icon(
            icon: Icon(MingCute.close_circle_fill, color: color, size: 17),
            onTap: () => onClose(name),
            padding: null,
          ),
          const SizedBox(width: 4),
          Expanded(child: title),
        ],
      );
    } else {
      btn = Center(child: title);
    }
    final child = AnimatedContainer(
      width: selected ? wideWidth : narrowWidth,
      duration: Durations.medium3,
      curve: Curves.fastEaseInToSlowEaseOut,
      child: btn,
    );

    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 7),
      child: Material(
        color: Colors.transparent,
        borderRadius: BorderRadius.circular(13),
        clipBehavior: Clip.antiAlias,
        child: InkWell(
          borderRadius: BorderRadius.circular(13),
          onTap: () => onTap(idx),
          child: child,
        ),
      ),
    );
  }
}

class _AddPage extends ConsumerStatefulWidget {
  const _AddPage({
    required this.sortVersionVN,
    required this.onTapInitCard,
    required this.onLongPressInitCard,
  });

  final ValueListenable<int> sortVersionVN;
  final void Function(Spi spi) onTapInitCard;
  final void Function(Spi spi) onLongPressInitCard;

  @override
  ConsumerState<_AddPage> createState() => _AddPageState();
}

class _AddPageState extends ConsumerState<_AddPage> {
  // Cache for sorted server order
  List<String>? _cachedOrder;
  int _cachedSortBy = -1;
  bool _cachedSortAsc = true;
  List<String>? _cachedServerOrder;
  Map<String, String>? _cachedServerNames;

  @override
  void initState() {
    super.initState();
    widget.sortVersionVN.addListener(_onSortVersionChanged);
  }

  @override
  void dispose() {
    widget.sortVersionVN.removeListener(_onSortVersionChanged);
    super.dispose();
  }

  void _onSortVersionChanged() {
    // Invalidate cache when sort version changes
    _cachedOrder = null;
    if (mounted) setState(() {});
  }

  List<String> _getSortedOrder(ServersState serverState, int sortBy, bool sortAsc) {
    // Check if cache is valid
    final serverOrder = serverState.serverOrder;
    final serverNames = <String, String>{};
    for (final id in serverOrder) {
      final name = serverState.servers[id]?.name;
      if (name != null) serverNames[id] = name;
    }

    if (_cachedOrder != null &&
        _cachedSortBy == sortBy &&
        _cachedSortAsc == sortAsc &&
        listEquals(_cachedServerOrder, serverOrder) &&
        mapEquals(_cachedServerNames, serverNames)) {
      return _cachedOrder!;
    }

    // Rebuild cache
    final order = serverOrder.toList();
    if (sortBy == 0) {
      order.sort((a, b) {
        final nameA = serverNames[a] ?? '';
        final nameB = serverNames[b] ?? '';
        return sortAsc ? nameA.compareTo(nameB) : nameB.compareTo(nameA);
      });
    } else if (sortBy == 1) {
      final indexMap = <String, int>{};
      for (var i = 0; i < serverOrder.length; i++) {
        indexMap[serverOrder[i]] = i;
      }
      order.sort((a, b) {
        final idxA = indexMap[a] ?? -1;
        final idxB = indexMap[b] ?? -1;
        return sortAsc ? idxA.compareTo(idxB) : idxB.compareTo(idxA);
      });
    }

    _cachedOrder = order;
    _cachedSortBy = sortBy;
    _cachedSortAsc = sortAsc;
    _cachedServerOrder = serverOrder;
    _cachedServerNames = serverNames;

    return order;
  }

  @override
  Widget build(BuildContext context) {
    final isMobile = ResponsiveBreakpoints.of(context).isMobile;
    final serverState = ref.watch(serversProvider);
    final sortBy = Stores.setting.sshPageSortBy.fetch();
    final sortAsc = Stores.setting.sshPageSortAsc.fetch();
    final order = _getSortedOrder(serverState, sortBy, sortAsc);

    return LayoutBuilder(
      builder: (_, cons) {
        final crossCount = isMobile
            ? 1
            : max(1, (cons.maxWidth / 360).floor());
        return CustomScrollView(
          slivers: [
            SliverToBoxAdapter(
              child: _SshSelectorHeader(serverCount: order.length),
            ),
            if (order.isEmpty)
              SliverFillRemaining(
                hasScrollBody: false,
                child: _SshEmptyState(
                  onAdd: () => ServerEditPage.route.go(context),
                ),
              )
            else
              SliverPadding(
                padding: const EdgeInsets.fromLTRB(16, 4, 16, 96),
                sliver: SliverGrid.builder(
                  itemCount: order.length,
                  gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
                    crossAxisCount: crossCount,
                    crossAxisSpacing: 12,
                    mainAxisSpacing: 12,
                    mainAxisExtent: 112,
                  ),
                  itemBuilder: (_, index) {
                    final spi = serverState.servers[order[index]];
                    if (spi == null) return UIs.placeholder;
                    return _SshServerCard(
                      spi: spi,
                      onTap: () => widget.onTapInitCard(spi),
                      onLongPress: () => widget.onLongPressInitCard(spi),
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

final class _SshSelectorHeader extends StatelessWidget {
  const _SshSelectorHeader({required this.serverCount});

  final int serverCount;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 22, 20, 14),
      child: Row(
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  l10n.ssh,
                  style: theme.textTheme.headlineMedium?.copyWith(
                    fontWeight: FontWeight.w800,
                    letterSpacing: -0.7,
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  '$serverCount ${serverCount == 1 ? libL10n.server : libL10n.servers}',
                  style: theme.textTheme.bodyMedium?.copyWith(
                    color: scheme.onSurfaceVariant,
                  ),
                ),
              ],
            ),
          ),
          Container(
            width: 58,
            height: 58,
            decoration: ShapeDecoration(
              color: scheme.tertiaryContainer,
              shape: const RoundedSuperellipseBorder(
                borderRadius: BorderRadius.all(Radius.circular(20)),
              ),
            ),
            child: Icon(
              Icons.terminal_rounded,
              color: scheme.onTertiaryContainer,
              size: 29,
            ),
          ),
        ],
      ),
    );
  }
}

final class _SshServerCard extends ConsumerWidget {
  const _SshServerCard({
    required this.spi,
    required this.onTap,
    required this.onLongPress,
  });

  final Spi spi;
  final VoidCallback onTap;
  final VoidCallback onLongPress;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final conn = ref.watch(
      serverProvider(spi.id).select((value) => value.conn),
    );
    final statusColor = switch (conn) {
      ServerConn.failed => scheme.error,
      ServerConn.disconnected => scheme.outline,
      ServerConn.connecting => Colors.orange,
      ServerConn.connected || ServerConn.loading || ServerConn.finished =>
        theme.brightness == Brightness.dark
            ? Colors.greenAccent.shade400
            : Colors.green.shade600,
    };
    const shape = RoundedSuperellipseBorder(
      borderRadius: BorderRadius.all(Radius.circular(26)),
    );

    return Card.filled(
      margin: EdgeInsets.zero,
      color: scheme.surfaceContainerLow,
      shape: shape,
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        customBorder: shape,
        onTap: onTap,
        onLongPress: onLongPress,
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
          child: Row(
            children: [
              Stack(
                clipBehavior: Clip.none,
                children: [
                  Container(
                    width: 54,
                    height: 54,
                    decoration: ShapeDecoration(
                      color: scheme.secondaryContainer,
                      shape: const RoundedSuperellipseBorder(
                        borderRadius: BorderRadius.all(Radius.circular(18)),
                      ),
                    ),
                    child: Icon(
                      Icons.dns_rounded,
                      color: scheme.onSecondaryContainer,
                    ),
                  ),
                  Positioned(
                    right: -2,
                    bottom: -2,
                    child: Container(
                      width: 15,
                      height: 15,
                      decoration: BoxDecoration(
                        color: statusColor,
                        shape: BoxShape.circle,
                        border: Border.all(
                          color: scheme.surfaceContainerLow,
                          width: 3,
                        ),
                      ),
                    ),
                  ),
                ],
              ),
              const SizedBox(width: 14),
              Expanded(
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      spi.name,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: theme.textTheme.titleMedium?.copyWith(
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                    const SizedBox(height: 5),
                    Text(
                      spi.oldId,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: theme.textTheme.bodySmall?.copyWith(
                        color: scheme.onSurfaceVariant,
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(width: 8),
              Container(
                width: 34,
                height: 34,
                decoration: BoxDecoration(
                  color: scheme.primaryContainer,
                  shape: BoxShape.circle,
                ),
                child: Icon(
                  Icons.arrow_forward_rounded,
                  color: scheme.onPrimaryContainer,
                  size: 19,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

final class _SshEmptyState extends StatelessWidget {
  const _SshEmptyState({required this.onAdd});

  final VoidCallback onAdd;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.dns_outlined, size: 52, color: scheme.primary),
            const SizedBox(height: 12),
            Text(libL10n.empty, textAlign: TextAlign.center),
            const SizedBox(height: 16),
            FilledButton.tonalIcon(
              onPressed: onAdd,
              icon: const Icon(Icons.add_rounded),
              label: Text(libL10n.add),
            ),
          ],
        ),
      ),
    );
  }
}

class _SortOption extends StatelessWidget {
  final IconData icon;
  final String label;
  final bool selected;
  final VoidCallback onTap;

  const _SortOption({
    required this.icon,
    required this.label,
    required this.selected,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final primaryColor = Theme.of(context).colorScheme.primary;
    return ListTile(
      leading: Icon(icon, color: selected ? primaryColor : null),
      title: Text(
        label,
        style: TextStyle(color: selected ? primaryColor : null),
      ),
      onTap: onTap,
    );
  }
}
