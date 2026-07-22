import 'dart:math';

import 'package:fl_lib/fl_lib.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:server_box/core/extension/context/locale.dart';
import 'package:server_box/data/model/server/snippet.dart';
import 'package:server_box/data/provider/server/all.dart';
import 'package:server_box/data/provider/snippet.dart';
import 'package:server_box/view/page/snippet/edit.dart';
import 'package:server_box/view/page/ssh/page/page.dart';
import 'package:server_box/view/widget/glass_surface.dart';

class SnippetListPage extends ConsumerStatefulWidget {
  const SnippetListPage({super.key});

  @override
  ConsumerState<SnippetListPage> createState() => _SnippetListPageState();

  static const route = AppRouteNoArg(
    page: SnippetListPage.new,
    path: '/snippets',
  );
}

enum _SnippetAction { edit, duplicate, delete }

class _SnippetListPageState extends ConsumerState<SnippetListPage>
    with AutomaticKeepAliveClientMixin {
  final _searchController = TextEditingController();
  final _searchFocus = FocusNode();
  String _query = '';
  String _tag = '';

  @override
  void dispose() {
    _searchController.dispose();
    _searchFocus.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    super.build(context);
    final snippetState = ref.watch(snippetProvider);
    final tags = snippetState.tags.toList()..sort();
    if (_tag.isNotEmpty && !snippetState.tags.contains(_tag)) {
      _tag = '';
    }
    final filtered = _filter(snippetState.snippets);

    return Scaffold(
      body: LayoutBuilder(
        builder: (_, constraints) {
          final columns = max(1, (constraints.maxWidth / 420).floor());
          return CustomScrollView(
            keyboardDismissBehavior: ScrollViewKeyboardDismissBehavior.onDrag,
            slivers: [
              SliverToBoxAdapter(
                child: _SnippetHeader(
                  visibleCount: filtered.length,
                  totalCount: snippetState.snippets.length,
                ),
              ),
              SliverPersistentHeader(
                pinned: true,
                delegate: _SnippetSearchHeaderDelegate(
                  controller: _searchController,
                  focusNode: _searchFocus,
                  onChanged: (value) => setState(() => _query = value),
                  onClear: _clearSearch,
                ),
              ),
              if (tags.isNotEmpty)
                SliverToBoxAdapter(child: _buildTagFilters(tags)),
              if (filtered.isEmpty)
                SliverFillRemaining(
                  hasScrollBody: false,
                  child: _SnippetEmptyState(
                    hasSnippets: snippetState.snippets.isNotEmpty,
                    onReset: _resetFilters,
                    onAdd: _openAdd,
                  ),
                )
              else
                SliverPadding(
                  padding: const EdgeInsets.fromLTRB(16, 10, 16, 104),
                  sliver: SliverGrid.builder(
                    itemCount: filtered.length,
                    gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
                      crossAxisCount: columns,
                      crossAxisSpacing: 12,
                      mainAxisSpacing: 12,
                      mainAxisExtent: 194,
                    ),
                    itemBuilder: (_, index) {
                      final snippet = filtered[index];
                      return _SnippetCard(
                        snippet: snippet,
                        onOpen: () => _openEdit(snippet),
                        onCopy: () => _copy(snippet),
                        onRun: () => _run(snippet),
                        onAction: (action) => _handleAction(snippet, action),
                      );
                    },
                  ),
                ),
            ],
          );
        },
      ),
      floatingActionButton: Padding(
        padding: EdgeInsets.only(bottom: isMobile ? 80 : 0),
        child: FloatingActionButton.extended(
          heroTag: 'snippetAdd',
          onPressed: _openAdd,
          icon: const Icon(Icons.add_rounded),
          label: Text(libL10n.add),
        ),
      ),
    );
  }

  List<Snippet> _filter(List<Snippet> snippets) {
    final query = _query.trim().toLowerCase();
    return snippets.where((snippet) {
      if (_tag.isNotEmpty && !(snippet.tags?.contains(_tag) ?? false)) {
        return false;
      }
      if (query.isEmpty) return true;
      return snippet.name.toLowerCase().contains(query) ||
          (snippet.note?.toLowerCase().contains(query) ?? false) ||
          snippet.script.toLowerCase().contains(query) ||
          (snippet.tags?.any((tag) => tag.toLowerCase().contains(query)) ??
              false);
    }).toList(growable: false);
  }

  Widget _buildTagFilters(List<String> tags) {
    return SizedBox(
      height: 52,
      child: ListView.separated(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 5),
        scrollDirection: Axis.horizontal,
        itemCount: tags.length + 1,
        separatorBuilder: (_, _) => const SizedBox(width: 8),
        itemBuilder: (_, index) {
          final tag = index == 0 ? '' : tags[index - 1];
          return FilterChip(
            selected: _tag == tag,
            showCheckmark: true,
            avatar: index == 0 ? const Icon(Icons.apps_rounded, size: 18) : null,
            label: Text(index == 0 ? libL10n.all : tag),
            onSelected: (_) => setState(() => _tag = tag),
          );
        },
      ),
    );
  }

  void _clearSearch() {
    _searchController.clear();
    setState(() => _query = '');
    _searchFocus.requestFocus();
  }

  void _resetFilters() {
    _searchController.clear();
    setState(() {
      _query = '';
      _tag = '';
    });
  }

  void _openAdd() => SnippetEditPage.route.go(context);

  void _openEdit(Snippet snippet) {
    SnippetEditPage.route.go(
      context,
      args: SnippetEditPageArgs(snippet: snippet),
    );
  }

  Future<void> _copy(Snippet snippet) async {
    await Clipboard.setData(ClipboardData(text: snippet.script));
    if (!mounted) return;
    context.showSnackBar('${libL10n.copy} ${libL10n.success}');
  }

  Future<void> _run(Snippet snippet) async {
    final servers = ref.read(serversProvider);
    if (servers.serverOrder.isEmpty) {
      context.showSnackBar(libL10n.empty);
      return;
    }
    final serverId = await context.showPickSingleDialog<String>(
      title: libL10n.server,
      items: servers.serverOrder,
      display: (id) => servers.servers[id]?.name ?? id,
    );
    if (!mounted || serverId == null) return;
    final spi = servers.servers[serverId];
    if (spi == null) return;

    final formatted = snippet.fmtWithSpi(spi);
    final confirmed = await context.showRoundDialog<bool>(
      title: '${libL10n.run} · ${snippet.name}',
      child: Container(
        width: double.maxFinite,
        constraints: const BoxConstraints(maxHeight: 360),
        padding: const EdgeInsets.all(14),
        decoration: BoxDecoration(
          color: Theme.of(context).colorScheme.surfaceContainerHighest,
          borderRadius: BorderRadius.circular(18),
        ),
        child: SingleChildScrollView(
          child: SelectionArea(
            child: Text(
              formatted,
              style: const TextStyle(fontFamily: 'monospace', height: 1.4),
            ),
          ),
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => context.pop(false),
          child: Text(libL10n.cancel),
        ),
        FilledButton.icon(
          onPressed: () => context.pop(true),
          icon: const Icon(Icons.play_arrow_rounded),
          label: Text(libL10n.run),
        ),
      ],
    );
    if (!mounted || confirmed != true) return;
    SSHPage.route.go(
      context,
      SshPageArgs(spi: spi, initSnippet: snippet),
    );
  }

  void _handleAction(Snippet snippet, _SnippetAction action) {
    switch (action) {
      case _SnippetAction.edit:
        _openEdit(snippet);
      case _SnippetAction.duplicate:
        _duplicate(snippet);
      case _SnippetAction.delete:
        _delete(snippet);
    }
  }

  void _duplicate(Snippet snippet) {
    final names = ref
        .read(snippetProvider)
        .snippets
        .map((item) => item.name)
        .toSet();
    var name = '${snippet.name} (${context.l10n.snippetCopySuffix})';
    var suffix = 2;
    while (names.contains(name)) {
      name = '${snippet.name} (${context.l10n.snippetCopySuffix} $suffix)';
      suffix++;
    }
    SnippetEditPage.route.go(
      context,
      args: SnippetEditPageArgs(
        snippet: snippet.copyWith(name: name),
        duplicate: true,
      ),
    );
  }

  Future<void> _delete(Snippet snippet) async {
    final confirmed = await context.showRoundDialog<bool>(
      title: libL10n.attention,
      child: Text(
        libL10n.askContinue(
          '${libL10n.delete} ${libL10n.snippet} (${snippet.name})',
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => context.pop(false),
          child: Text(libL10n.cancel),
        ),
        FilledButton(
          style: FilledButton.styleFrom(
            backgroundColor: Theme.of(context).colorScheme.error,
            foregroundColor: Theme.of(context).colorScheme.onError,
          ),
          onPressed: () => context.pop(true),
          child: Text(libL10n.delete),
        ),
      ],
    );
    if (confirmed == true) {
      ref.read(snippetProvider.notifier).del(snippet);
    }
  }

  @override
  bool get wantKeepAlive => true;
}

final class _SnippetHeader extends StatelessWidget {
  const _SnippetHeader({
    required this.visibleCount,
    required this.totalCount,
  });

  final int visibleCount;
  final int totalCount;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 22, 20, 8),
      child: Row(
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  libL10n.snippet,
                  style: theme.textTheme.headlineMedium?.copyWith(
                    fontWeight: FontWeight.w800,
                    letterSpacing: -0.7,
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  '$visibleCount / $totalCount · ${context.l10n.snippetLibraryDescription}',
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: theme.textTheme.bodyMedium?.copyWith(
                    color: scheme.onSurfaceVariant,
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(width: 16),
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
              Icons.code_rounded,
              color: scheme.onTertiaryContainer,
              size: 29,
            ),
          ),
        ],
      ),
    );
  }
}

final class _SnippetSearchHeaderDelegate
    extends SliverPersistentHeaderDelegate {
  _SnippetSearchHeaderDelegate({
    required this.controller,
    required this.focusNode,
    required this.onChanged,
    required this.onClear,
  });

  final TextEditingController controller;
  final FocusNode focusNode;
  final ValueChanged<String> onChanged;
  final VoidCallback onClear;

  @override
  double get minExtent => 76;

  @override
  double get maxExtent => 76;

  @override
  Widget build(
    BuildContext context,
    double shrinkOffset,
    bool overlapsContent,
  ) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 7, 20, 9),
      child: GlassSurface(
        shape: const StadiumBorder(),
        child: SearchBar(
          controller: controller,
          focusNode: focusNode,
          hintText: libL10n.search,
          leading: const Icon(Icons.search_rounded),
          trailing: [
            if (controller.text.isNotEmpty)
              IconButton(
                tooltip: libL10n.clear,
                onPressed: onClear,
                icon: const Icon(Icons.close_rounded),
              ),
          ],
          elevation: const WidgetStatePropertyAll(0),
          shadowColor: const WidgetStatePropertyAll(Colors.transparent),
          surfaceTintColor: const WidgetStatePropertyAll(Colors.transparent),
          backgroundColor: const WidgetStatePropertyAll(Colors.transparent),
          onChanged: onChanged,
        ),
      ),
    );
  }

  @override
  bool shouldRebuild(covariant _SnippetSearchHeaderDelegate oldDelegate) {
    return true;
  }
}

final class _SnippetCard extends StatelessWidget {
  const _SnippetCard({
    required this.snippet,
    required this.onOpen,
    required this.onCopy,
    required this.onRun,
    required this.onAction,
  });

  final Snippet snippet;
  final VoidCallback onOpen;
  final VoidCallback onCopy;
  final VoidCallback onRun;
  final ValueChanged<_SnippetAction> onAction;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    const shape = RoundedSuperellipseBorder(
      borderRadius: BorderRadius.all(Radius.circular(28)),
    );
    final tags = snippet.tags ?? const <String>[];

    return Card.filled(
      margin: EdgeInsets.zero,
      color: scheme.surfaceContainerLow,
      shape: shape,
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        customBorder: shape,
        onTap: onOpen,
        child: Padding(
          padding: const EdgeInsets.fromLTRB(16, 14, 10, 12),
          child: Column(
            children: [
              Row(
                children: [
                  Container(
                    width: 44,
                    height: 44,
                    decoration: ShapeDecoration(
                      color: scheme.secondaryContainer,
                      shape: const RoundedSuperellipseBorder(
                        borderRadius: BorderRadius.all(Radius.circular(15)),
                      ),
                    ),
                    child: Icon(
                      Icons.terminal_rounded,
                      color: scheme.onSecondaryContainer,
                      size: 22,
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          snippet.name,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: theme.textTheme.titleMedium?.copyWith(
                            fontWeight: FontWeight.w700,
                          ),
                        ),
                        if (snippet.note?.isNotEmpty == true)
                          Text(
                            snippet.note!,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: theme.textTheme.bodySmall?.copyWith(
                              color: scheme.onSurfaceVariant,
                            ),
                          ),
                      ],
                    ),
                  ),
                  PopupMenuButton<_SnippetAction>(
                    tooltip: libL10n.more,
                    onSelected: onAction,
                    itemBuilder: (_) => [
                      PopupMenuItem(
                        value: _SnippetAction.edit,
                        child: ListTile(
                          contentPadding: EdgeInsets.zero,
                          leading: const Icon(Icons.edit_rounded),
                          title: Text(libL10n.edit),
                        ),
                      ),
                      PopupMenuItem(
                        value: _SnippetAction.duplicate,
                        child: ListTile(
                          contentPadding: EdgeInsets.zero,
                          leading: const Icon(Icons.content_copy_rounded),
                          title: Text(context.l10n.snippetDuplicate),
                        ),
                      ),
                      PopupMenuItem(
                        value: _SnippetAction.delete,
                        child: ListTile(
                          contentPadding: EdgeInsets.zero,
                          leading: Icon(Icons.delete_rounded, color: scheme.error),
                          title: Text(
                            libL10n.delete,
                            style: TextStyle(color: scheme.error),
                          ),
                        ),
                      ),
                    ],
                    icon: const Icon(Icons.more_vert_rounded),
                  ),
                ],
              ),
              const SizedBox(height: 10),
              Container(
                width: double.infinity,
                height: 54,
                padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                decoration: ShapeDecoration(
                  color: scheme.surfaceContainerHighest.withAlpha(180),
                  shape: const RoundedSuperellipseBorder(
                    borderRadius: BorderRadius.all(Radius.circular(16)),
                  ),
                ),
                child: Text(
                  snippet.script,
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: theme.textTheme.bodySmall?.copyWith(
                    fontFamily: 'monospace',
                    height: 1.35,
                    color: scheme.onSurfaceVariant,
                  ),
                ),
              ),
              const Spacer(),
              Row(
                children: [
                  if (tags.isNotEmpty)
                    Expanded(
                      child: Text(
                        tags.take(3).map((tag) => '#$tag').join('  '),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: theme.textTheme.labelMedium?.copyWith(
                          color: scheme.primary,
                        ),
                      ),
                    )
                  else
                    const Spacer(),
                  IconButton.filledTonal(
                    tooltip: libL10n.copy,
                    onPressed: onCopy,
                    icon: const Icon(Icons.content_copy_rounded, size: 19),
                  ),
                  const SizedBox(width: 6),
                  FilledButton.tonalIcon(
                    onPressed: onRun,
                    icon: const Icon(Icons.play_arrow_rounded, size: 20),
                    label: Text(libL10n.run),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }
}

final class _SnippetEmptyState extends StatelessWidget {
  const _SnippetEmptyState({
    required this.hasSnippets,
    required this.onReset,
    required this.onAdd,
  });

  final bool hasSnippets;
  final VoidCallback onReset;
  final VoidCallback onAdd;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(28),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              width: 74,
              height: 74,
              decoration: ShapeDecoration(
                color: scheme.secondaryContainer,
                shape: const RoundedSuperellipseBorder(
                  borderRadius: BorderRadius.all(Radius.circular(26)),
                ),
              ),
              child: Icon(
                hasSnippets ? Icons.search_off_rounded : Icons.code_rounded,
                size: 34,
                color: scheme.onSecondaryContainer,
              ),
            ),
            const SizedBox(height: 18),
            Text(
              hasSnippets ? context.l10n.snippetNoMatch : libL10n.empty,
              textAlign: TextAlign.center,
              style: Theme.of(context).textTheme.titleMedium,
            ),
            const SizedBox(height: 16),
            FilledButton.tonalIcon(
              onPressed: hasSnippets ? onReset : onAdd,
              icon: Icon(hasSnippets ? Icons.filter_alt_off_rounded : Icons.add_rounded),
              label: Text(hasSnippets ? libL10n.clear : libL10n.add),
            ),
          ],
        ),
      ),
    );
  }
}
