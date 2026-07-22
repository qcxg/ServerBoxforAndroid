import 'dart:async';
import 'dart:io';

import 'package:fl_lib/fl_lib.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:server_box/core/chan.dart';
import 'package:server_box/core/extension/context/locale.dart';
import 'package:server_box/core/utils/host_key_helper.dart';
import 'package:server_box/data/model/app/path_with_prefix.dart';
import 'package:server_box/data/model/server/server_private_info.dart';
import 'package:server_box/data/model/sftp/req.dart';
import 'package:server_box/data/provider/server/all.dart';
import 'package:server_box/data/provider/sftp.dart';
import 'package:server_box/data/res/misc.dart';
import 'package:server_box/data/res/store.dart';
import 'package:server_box/view/page/storage/file_pane_controller.dart';
import 'package:server_box/view/page/storage/sftp.dart';
import 'package:server_box/view/page/storage/sftp_mission.dart';
import 'package:server_box/view/widget/file_type_icon.dart';
import 'package:server_box/view/widget/glass_context_menu.dart';
import 'package:server_box/view/widget/glass_surface.dart';

enum _EmbeddedLocalAction { mission, sortName, sortSize, sortTime }

final class LocalFilePageArgs {
  final bool? isPickFile;
  final String? initDir;
  const LocalFilePageArgs({this.isPickFile, this.initDir});
}

class LocalFilePage extends ConsumerStatefulWidget {
  final LocalFilePageArgs? args;
  final bool embedded;
  final FilePaneController? paneController;
  final FilePaneController? transferTargetController;

  const LocalFilePage({
    super.key,
    this.args,
    this.embedded = false,
    this.paneController,
    this.transferTargetController,
  });

  static const route = AppRoute<String, LocalFilePageArgs>(
    page: LocalFilePage.new,
    path: '/files/local',
  );

  @override
  ConsumerState<LocalFilePage> createState() => _LocalFilePageState();
}

class _LocalFilePageState extends ConsumerState<LocalFilePage>
    with AutomaticKeepAliveClientMixin, WidgetsBindingObserver {
  static const _localHistoryKey = 'device';
  static const _androidStorageRoot = '/storage/emulated/0';

  late final _path = _createInitialPath();
  late final _pathController = TextEditingController(text: _path.path);
  final _pathFocusNode = FocusNode();
  final _sortType = _SortType.name.vn;
  late Future<List<(FileSystemEntity, FileStat)>> _entitiesFuture =
      _getEntities();
  List<(FileSystemEntity, FileStat)> _visibleEntities = [];
  final Set<String> _selectedPaths = {};
  bool _selectionMode = false;
  bool get isPickFile => widget.args?.isPickFile ?? false;
  bool _awaitingStorageAccess = false;

  @override
  void initState() {
    super.initState();
    widget.paneController?.attach(
      owner: this,
      path: _path.path,
      refresh: _refresh,
      goHome: _goHome,
      create: _showCreateMenu,
      deleteSelected: _deleteSelected,
      transferSelected: _transferSelected,
      toggleSelectionMode: _toggleSelectionMode,
      selectAll: _selectAll,
      clearSelection: _clearSelection,
    );
    WidgetsBinding.instance.addObserver(this);
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _ensureAndroidStorageAccess();
    });
  }

  Future<void> _ensureAndroidStorageAccess() async {
    if (!isAndroid || await MethodChans.hasStorageAccess()) return;
    _awaitingStorageAccess = true;
    await MethodChans.requestStorageAccess();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state != AppLifecycleState.resumed || !_awaitingStorageAccess) return;
    MethodChans.hasStorageAccess().then((granted) {
      if (!mounted || !granted) return;
      _awaitingStorageAccess = false;
      final saved = Stores.history.localLastPath.fetch(_localHistoryKey);
      final target = saved != null &&
              saved != Pfs.seperator &&
              Directory(saved).existsSync()
          ? saved
          : _androidStorageRoot;
      _path.setAbsolute(target);
      _pathFocusNode.unfocus();
      _syncPathController();
      _refresh();
    });
  }

  LocalPath _createInitialPath() {
    final requested = widget.args?.initDir;
    final saved = Stores.history.localLastPath.fetch(_localHistoryKey);
    final candidate = requested ?? saved;
    final path = LocalPath(isAndroid ? _androidStorageRoot : Pfs.seperator);
    if (candidate != null &&
        (!isAndroid || candidate != Pfs.seperator) &&
        Directory(candidate).existsSync()) {
      path.setAbsolute(Directory(candidate).absolute.path);
    }
    return path;
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    widget.paneController?.detach(this);
    _pathFocusNode.dispose();
    _pathController.dispose();
    super.dispose();
    _sortType.dispose();
  }

  Future<void> _refresh() async {
    setStateSafe(() {
      _entitiesFuture = _getEntities();
    });
    await _entitiesFuture;
    Stores.history.localLastPath.put(_localHistoryKey, _path.path);
    _syncPaneController();
  }

  void _syncPaneController() {
    widget.paneController?.update(
      owner: this,
      path: _path.path,
      selectedCount: _selectedPaths.length,
      selectionMode: _selectionMode,
    );
  }

  void _syncPathController() {
    final path = _path.path;
    if (_pathController.text == path) return;
    _pathController.value = TextEditingValue(
      text: path,
      selection: TextSelection.collapsed(offset: path.length),
    );
  }

  void _changePath(String value) {
    _pathFocusNode.unfocus();
    _path.update(value);
    _clearSelection();
    _syncPathController();
    _refresh();
  }

  Future<void> _goHome() async {
    _pathFocusNode.unfocus();
    final target = isAndroid ? _androidStorageRoot : Pfs.seperator;
    if (_path.setAbsolute(target)) {
      _clearSelection();
      _syncPathController();
      await _refresh();
    }
  }

  void _toggleSelectionMode() {
    setState(() {
      _selectionMode = !_selectionMode;
      if (!_selectionMode) _selectedPaths.clear();
    });
    _syncPaneController();
  }

  void _selectAll() {
    setState(() {
      _selectionMode = true;
      _selectedPaths
        ..clear()
        ..addAll(_visibleEntities.map((entry) => entry.$1.path));
    });
    _syncPaneController();
  }

  void _clearSelection() {
    if (!_selectionMode && _selectedPaths.isEmpty) return;
    setStateSafe(() {
      _selectionMode = false;
      _selectedPaths.clear();
    });
    _syncPaneController();
  }

  void _toggleSelected(String path) {
    setState(() {
      if (!_selectedPaths.add(path)) _selectedPaths.remove(path);
    });
    _syncPaneController();
  }

  Future<void> _deleteSelected() async {
    if (_selectedPaths.isEmpty) return;
    final confirmed = await context.showRoundDialog<bool>(
      title: libL10n.delete,
      child: Text(libL10n.askContinue('${_selectedPaths.length}')),
      actions: Btnx.cancelRedOk,
    );
    if (confirmed != true || !mounted) return;
    final targets = List<String>.from(_selectedPaths);
    final (_, error) = await context.showLoadingDialog(
      fn: () async {
        for (final path in targets) {
          if (await FileSystemEntity.type(path) ==
              FileSystemEntityType.directory) {
            await Directory(path).delete(recursive: true);
          } else {
            await File(path).delete();
          }
        }
        return true;
      },
    );
    if (error != null) return;
    _clearSelection();
    await _refresh();
  }

  Future<void> _transferSelected(FilePaneTarget target) async {
    final files = _visibleEntities.where(
      (entry) =>
          _selectedPaths.contains(entry.$1.path) &&
          entry.$2.type == FileSystemEntityType.file,
    ).map((entry) => entry.$1).toList(growable: false);
    if (files.isEmpty) {
      context.showSnackBar(libL10n.empty);
      return;
    }
    await _uploadFilesToTarget(files, target, clearSelectionAfter: true);
  }

  Future<void> _uploadFilesToTarget(
    Iterable<FileSystemEntity> files,
    FilePaneTarget target, {
    bool clearSelectionAfter = false,
  }) async {
    final spi = target.server;
    if (spi == null) return;
    if (!await ensureHostKeyAcceptedForSftp(context, spi)) return;
    final completions = <Future<bool>>[];
    for (final file in files) {
      final name = file.path.split(Pfs.seperator).last;
      final remotePath = target.path == '/'
          ? '/$name'
          : '${target.path}/$name';
      final completer = Completer<bool>();
      ref
          .read(sftpProvider.notifier)
          .add(
            SftpReq(spi, remotePath, file.path, SftpReqType.upload),
            completer: completer,
          );
      completions.add(completer.future);
    }
    if (clearSelectionAfter) _clearSelection();
    context.showSnackBar(l10n.added2List);
    unawaited(_refreshRemoteTargetAfter(completions, target));
  }

  Future<void> _refreshRemoteTargetAfter(
    List<Future<bool>> completions,
    FilePaneTarget target,
  ) async {
    if (completions.isEmpty) return;
    await Future.wait(completions);
    await widget.transferTargetController?.refreshIfCurrent(target);
  }

  Future<void> _showCreateMenu() async {
    await context.showRoundDialog(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Btn.tile(
            icon: const Icon(Icons.create_new_folder_rounded),
            text: libL10n.folder,
            onTap: () => _showCreateEntryDialog(directory: true),
          ),
          Btn.tile(
            icon: const Icon(Icons.note_add_rounded),
            text: libL10n.file,
            onTap: () => _showCreateEntryDialog(directory: false),
          ),
        ],
      ),
    );
  }

  void _showCreateEntryDialog({required bool directory}) {
    context.pop();
    final controller = TextEditingController();
    void submit() async {
      final name = controller.text.trim();
      if (name.isEmpty) return;
      context.pop();
      final path = _path.path.joinPath(name);
      final (_, error) = await context.showLoadingDialog(
        fn: () async {
          if (directory) {
            await Directory(path).create();
          } else {
            await File(path).create();
          }
          return true;
        },
      );
      if (error == null) await _refresh();
    }

    context.showRoundDialog(
      title: directory ? libL10n.folder : libL10n.file,
      child: Input(
        autoFocus: true,
        controller: controller,
        label: libL10n.name,
        onSubmitted: (_) => submit(),
      ),
      actions: Btn.ok(onTap: submit).toList,
    );
  }

  Future<void> _openPathFromEditor(String rawPath) async {
    _pathFocusNode.unfocus();
    final value = rawPath.trim();
    if (value.isEmpty) {
      _syncPathController();
      return;
    }

    final directory = Directory(value).absolute;
    if (!await directory.exists() || !_path.setAbsolute(directory.path)) {
      _syncPathController();
      if (mounted) context.showSnackBar(libL10n.error);
      return;
    }

    _syncPathController();
    await _refresh();
  }

  @override
  Widget build(BuildContext context) {
    super.build(context);
    final title = _path.path.fileNameGetter ?? libL10n.file;
    if (widget.embedded) {
      return _buildEmbeddedFilePane();
    }
    return Scaffold(
      appBar: CustomAppBar(
        title: AnimatedSwitcher(
          duration: Durations.short3,
          child: Text(title, key: ValueKey(title)),
        ),
        actions: [
          if (!isPickFile)
            IconButton(
              onPressed: () async {
                final path = await Pfs.pickFilePath();
                if (path == null) return;
                final name = path.getFileName() ?? 'imported';
                final destinationDir = Directory(_path.path);
                if (!await destinationDir.exists()) {
                  await destinationDir.create(recursive: true);
                }
                await File(path).copy(_path.path.joinPath(name));
                _refresh();
              },
              icon: const Icon(Icons.add),
            ),
          if (!isMobile)
            IconButton(
              icon: const Icon(Icons.refresh),
              tooltip: MaterialLocalizations.of(
                context,
              ).refreshIndicatorSemanticLabel,
              onPressed: _refresh,
            ),
          if (!isPickFile) _buildMissionBtn(),
          _buildSortBtn(),
        ],
      ),
      body: isMobile
          ? RefreshIndicator(
              onRefresh: _refresh,
              child: _sortType.listen(_buildBody),
            )
          : _sortType.listen(_buildBody),
    );
  }

  Widget _buildEmbeddedFilePane() {
    final scheme = Theme.of(context).colorScheme;
    return Column(
      children: [
        LayoutBuilder(
          builder: (context, constraints) {
            final compact = constraints.maxWidth < 280;
            final actionSize = compact ? 36.0 : 48.0;
            return SizedBox(
              height: compact ? 44 : 52,
              child: IconButtonTheme(
                data: IconButtonThemeData(
                  style: IconButton.styleFrom(
                    minimumSize: Size.square(actionSize),
                    maximumSize: Size.square(actionSize),
                    padding: EdgeInsets.all(compact ? 7 : 8),
                    iconSize: compact ? 20 : 24,
                  ),
                ),
                child: Padding(
                  padding: EdgeInsets.fromLTRB(
                    compact ? 7 : 14,
                    4,
                    compact ? 2 : 6,
                    0,
                  ),
                  child: Row(
                    children: [
                      Icon(
                        Icons.devices_rounded,
                        size: compact ? 20 : 24,
                        color: scheme.primary,
                      ),
                      SizedBox(width: compact ? 5 : 10),
                      Expanded(
                        child: Text(
                          libL10n.device,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: Theme.of(context).textTheme.titleMedium
                              ?.copyWith(fontWeight: FontWeight.w700),
                        ),
                      ),
                      IconButton(
                        tooltip: MaterialLocalizations.of(
                          context,
                        ).refreshIndicatorSemanticLabel,
                        onPressed: _refresh,
                        icon: const Icon(Icons.refresh_rounded),
                      ),
                      if (compact)
                        _buildCompactActionsMenu()
                      else ...[
                        if (!isPickFile) _buildMissionBtn(),
                        _buildSortBtn(),
                      ],
                    ],
                  ),
                ),
              ),
            );
          },
        ),
        Padding(
          padding: const EdgeInsets.fromLTRB(6, 0, 6, 3),
          child: GlassSurface(
            shape: const RoundedRectangleBorder(
              borderRadius: BorderRadius.all(Radius.circular(11)),
            ),
            child: SizedBox(
              height: 40,
              child: Padding(
                padding: const EdgeInsets.only(left: 9, right: 2),
                child: Row(
                  children: [
                    Icon(
                      Icons.folder_open_rounded,
                      size: 18,
                      color: scheme.primary,
                    ),
                    const SizedBox(width: 6),
                    Expanded(
                      child: TextField(
                        controller: _pathController,
                        focusNode: _pathFocusNode,
                        keyboardType: TextInputType.url,
                        textInputAction: TextInputAction.go,
                        autocorrect: false,
                        enableSuggestions: false,
                        style: Theme.of(context).textTheme.bodySmall,
                        decoration: const InputDecoration(
                          border: InputBorder.none,
                          isDense: true,
                          contentPadding: EdgeInsets.zero,
                        ),
                        onTapOutside: (_) => _pathFocusNode.unfocus(),
                        onSubmitted: _openPathFromEditor,
                      ),
                    ),
                    IconButton(
                      tooltip: l10n.goto,
                      visualDensity: VisualDensity.compact,
                      onPressed: () =>
                          _openPathFromEditor(_pathController.text),
                      icon: const Icon(Icons.arrow_forward_rounded, size: 19),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ),
        Expanded(
          child: RefreshIndicator(
            onRefresh: _refresh,
            child: _sortType.listen(_buildBody),
          ),
        ),
      ],
    );
  }

  Widget _buildBody() {
    return FutureWidget(
      future: _entitiesFuture,
      loading: UIs.placeholder,
      success: (items) {
        items ??= [];
        final len = _path.canBack ? items.length + 1 : items.length;
        return ListView.builder(
          itemCount: len,
          padding: EdgeInsets.fromLTRB(
            widget.embedded ? 3 : 13,
            widget.embedded ? 3 : 10,
            widget.embedded ? 3 : 13,
            widget.embedded ? 148 : 10,
          ),
          itemBuilder: (context, index) {
            if (index == 0 && _path.canBack) {
              final tile = ListTile(
                dense: widget.embedded,
                visualDensity: widget.embedded
                    ? const VisualDensity(vertical: -4)
                    : null,
                contentPadding: widget.embedded
                    ? const EdgeInsets.symmetric(horizontal: 8)
                    : null,
                minLeadingWidth: widget.embedded ? 24 : null,
                leading: const Icon(Icons.arrow_back, size: 20),
                title: const Text('..'),
                onTap: () {
                  _changePath('..');
                },
              );
              return widget.embedded ? tile : tile.cardx;
            }

            if (_path.canBack) index--;

            final item = items![index];
            final file = item.$1;
            final fileName = file.path.split(Pfs.seperator).last;
            final stat = item.$2;
            final isDir = stat.type == FileSystemEntityType.directory;

            return _buildItem(
              file: file,
              fileName: fileName,
              stat: stat,
              isDir: isDir,
            );
          },
        );
      },
    );
  }

  Widget _buildItem({
    required FileSystemEntity file,
    required String fileName,
    required FileStat stat,
    required bool isDir,
  }) {
    final isServerFolder = isDir && file.parent.path == Paths.file;
    String? serverName;
    if (isServerFolder) {
      final servers = ref.read(serversProvider).servers;
      final server = servers[fileName];
      if (server != null) {
        serverName = server.name;
      }
    }

    return LayoutBuilder(
      builder: (context, constraints) {
        Offset? pressPosition;
        final compact = constraints.maxWidth < 420;
        final modified = stat.modified.ymdhms();
        final subtitleParts = <String>[
          if (serverName != null) fileName,
          if (!isDir) stat.size.bytes2Str,
          if (compact) modified,
        ];
        final selected = _selectedPaths.contains(file.path);
        final tile = ListTile(
            dense: widget.embedded,
            visualDensity: widget.embedded
                ? const VisualDensity(vertical: -4)
                : null,
            contentPadding: widget.embedded
                ? const EdgeInsets.symmetric(horizontal: 8)
                : null,
            minLeadingWidth: widget.embedded ? 24 : null,
            selected: selected,
            selectedTileColor: Theme.of(
              context,
            ).colorScheme.secondaryContainer.withAlpha(120),
            leading: _selectionMode
                ? Checkbox(
                    value: selected,
                    visualDensity: VisualDensity.compact,
                    onChanged: (_) => _toggleSelected(file.path),
                  )
                : FileTypeIcon(
                    name: fileName,
                    isDirectory: isDir,
                    size: widget.embedded ? 20 : 24,
                  ),
            title: Text(
              serverName ?? fileName,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: widget.embedded
                  ? Theme.of(context).textTheme.bodyMedium
                  : null,
            ),
            subtitle: widget.embedded || subtitleParts.isEmpty
                ? null
                : Text(subtitleParts.join('\n'), style: UIs.textGrey),
            trailing: compact || widget.embedded
                ? null
                : Text(modified, style: UIs.textGrey),
            onLongPress: () => _showLocalItemMenu(
              file,
              isDir: isDir,
              anchor: pressPosition ?? Offset.zero,
            ),
            onTap: () {
              if (_selectionMode) {
                _toggleSelected(file.path);
                return;
              }
              if (!isDir) {
                if (isPickFile) {
                  _showPickFileDialog(file);
                } else {
                  _onTapEdit(file, fileName, popMenu: false);
                }
                return;
              }
              _changePath(fileName);
            },
          );
        final child = widget.embedded
            ? DecoratedBox(
          decoration: BoxDecoration(
            border: Border(
              bottom: BorderSide(
                color: Theme.of(context).colorScheme.outlineVariant.withAlpha(55),
              ),
            ),
          ),
          child: tile,
              )
            : CardX(child: tile);
        return Listener(
          onPointerDown: (event) => pressPosition = event.position,
          child: child,
        );
      },
    );
  }

  Widget _buildMissionBtn() {
    return IconButton(
      icon: const Icon(Icons.downloading),
      onPressed: () => SftpMissionPage.route.go(context),
    );
  }

  Widget _buildCompactActionsMenu() {
    return PopupMenuButton<_EmbeddedLocalAction>(
      tooltip: MaterialLocalizations.of(context).moreButtonTooltip,
      icon: const Icon(Icons.more_vert_rounded),
      onSelected: (action) {
        switch (action) {
          case _EmbeddedLocalAction.mission:
            SftpMissionPage.route.go(context);
          case _EmbeddedLocalAction.sortName:
            _sortType.value = _SortType.name;
          case _EmbeddedLocalAction.sortSize:
            _sortType.value = _SortType.size;
          case _EmbeddedLocalAction.sortTime:
            _sortType.value = _SortType.time;
        }
      },
      itemBuilder: (context) => [
        if (!isPickFile)
          PopupMenuItem(
            value: _EmbeddedLocalAction.mission,
            child: ListTile(
              leading: const Icon(Icons.downloading_rounded),
              title: Text(libL10n.mission),
            ),
          ),
        ..._SortType.values.map(
          (sort) => PopupMenuItem(
            value: switch (sort) {
              _SortType.name => _EmbeddedLocalAction.sortName,
              _SortType.size => _EmbeddedLocalAction.sortSize,
              _SortType.time => _EmbeddedLocalAction.sortTime,
            },
            child: ListTile(
              leading: Icon(sort.icon),
              title: Text('${l10n.sort}: ${sort.i18n}'),
            ),
          ),
        ),
      ],
    );
  }

  Future<List<(FileSystemEntity, FileStat)>> _getEntities() async {
    final files = await Directory(_path.path).list().toList();
    final stats = await Future.wait(
      files.map((e) async => (e, await e.stat())),
    );
    stats.sort(_sortType.value.compareTuple);
    _visibleEntities = stats;
    return stats;
  }

  Widget _buildSortBtn() {
    return _sortType.listenVal((value) {
      return PopupMenuButton<_SortType>(
        icon: const Icon(Icons.sort),
        itemBuilder: (_) => _SortType.values.map((e) => e.menuItem).toList(),
        onSelected: (value) {
          _sortType.value = value;
        },
      );
    });
  }

  @override
  bool get wantKeepAlive => true;
}

extension _Actions on _LocalFilePageState {
  void _showLocalItemMenu(
    FileSystemEntity file, {
    required bool isDir,
    required Offset anchor,
  }) {
    final fileName = file.path.split(Pfs.seperator).lastOrNull ?? '';
    final transferTarget = widget.transferTargetController?.transferTarget;
    showGlassContextMenu(
      context,
      anchor: anchor,
      actions: [
        if (!isDir && isMobile)
          GlassContextMenuAction(
            icon: Icons.edit_rounded,
            label: libL10n.edit,
            onPressed: () => _onTapEdit(file, fileName, popMenu: false),
          ),
        GlassContextMenuAction(
          icon: Icons.drive_file_rename_outline_rounded,
          label: libL10n.rename,
          onPressed: () => _showRenameDialog(file),
        ),
        if (!isDir && (transferTarget != null || !widget.embedded))
          GlassContextMenuAction(
            icon: Icons.upload_rounded,
            label: libL10n.upload,
            onPressed: transferTarget != null
                ? () => _uploadFilesToTarget([file], transferTarget)
                : () => _onTapUpload(file, fileName, popMenu: false),
          ),
        if (!isDir)
          GlassContextMenuAction(
            icon: Icons.open_in_new_rounded,
            label: libL10n.open,
            onPressed: () => Pfs.sharePaths(paths: [file.absolute.path]),
          ),
        GlassContextMenuAction(
          icon: Icons.delete_outline_rounded,
          label: libL10n.delete,
          destructive: true,
          onPressed: () => _showDeleteDialog(file),
        ),
      ],
    );
  }

  Future<void> _showPickFileDialog(FileSystemEntity file) async {
    final fileName = file.path.split(Pfs.seperator).lastOrNull ?? '';
    context.showRoundDialog(
      title: libL10n.file,
      child: Text(fileName),
      actions: [
        Btn.ok(
            onTap: () {
              context.pop();
              context.pop(file.path);
            },
          ),
      ],
    );
  }

  void _showRenameDialog(FileSystemEntity file) {
    final fileName = file.path.split(Pfs.seperator).last;
    final ctrl = TextEditingController(text: fileName);
    void onSubmit() async {
      final newName = ctrl.text;
      if (newName.isEmpty) {
        context.showSnackBar(libL10n.empty);
        return;
      }

      context.pop();
      final newPath = '${file.parent.path}${Pfs.seperator}$newName';
      await context.showLoadingDialog(fn: () => file.rename(newPath));

      setStateSafe(() {});
    }

    context.showRoundDialog(
      title: libL10n.rename,
      child: Input(
        autoFocus: true,
        icon: Icons.abc,
        label: libL10n.name,
        controller: ctrl,
        suggestion: true,
        maxLines: 3,
        onSubmitted: (p0) => onSubmit(),
      ),
      actions: Btn.ok(onTap: onSubmit).toList,
    );
  }

  void _showDeleteDialog(FileSystemEntity file) {
    final fileName = file.path.split(Pfs.seperator).last;
    context.showRoundDialog(
      title: libL10n.delete,
      child: Text(libL10n.askContinue('${libL10n.delete} $fileName')),
      actions: Btn.ok(
        onTap: () async {
          context.pop();
          try {
            await file.delete(recursive: true);
          } catch (e) {
            context.showSnackBar('${libL10n.fail}:\n$e');
            return;
          }
          setStateSafe(() {});
        },
      ).toList,
    );
  }
}

extension _OnTapFile on _LocalFilePageState {
  void _onTapEdit(
    FileSystemEntity file,
    String fileName, {
    bool popMenu = true,
  }) async {
    if (popMenu) context.pop();
    final stat = await file.stat();
    if (stat.size > Miscs.editorMaxSize) {
      context.showRoundDialog(
        title: libL10n.attention,
        child: Text(l10n.fileTooLarge(fileName, stat.size, '1m')),
      );
      return;
    }

    await EditorPage.route.go(
      context,
      args: EditorPageArgs(
        path: file.absolute.path,
        onSave: (_) {
          context.showSnackBar(libL10n.saved);
          setStateSafe(() {});
        },
        closeAfterSave: Stores.setting.closeAfterSave.fetch(),
        softWrap: Stores.setting.editorSoftWrap.fetch(),
        enableHighlight: Stores.setting.editorHighlight.fetch(),
        softWrapLabel: l10n.softWrap,
        highlightLabel: l10n.highlight,
        externalFileOpener: MethodChans.openFileExternally,
        lightTheme: HighlightTheme.fromThemeMapKey(
          Stores.setting.editorTheme.fetch(),
        ),
        darkTheme: HighlightTheme.fromThemeMapKey(
          Stores.setting.editorDarkTheme.fetch(),
        ),
        fontFamily: () {
          final font = Stores.setting.editorFontFamily.fetch();
          return font.isEmpty ? null : font;
        }(),
        fontSize: Stores.setting.editorFontSize.fetch(),
      ),
    );
  }

  void _onTapUpload(
    FileSystemEntity file,
    String fileName, {
    bool popMenu = true,
  }) async {
    if (popMenu) context.pop();

    final spi = await context.showPickSingleDialog<Spi>(
      title: libL10n.select,
      items: ref.read(serversProvider).servers.values.toList(),
      display: (e) => e.name,
    );
    if (spi == null) return;

    final args = SftpPageArgs(spi: spi, isSelect: true);
    final remotePath = await SftpPage.route.go(context, args);
    if (remotePath == null) {
      return;
    }

    if (!await ensureHostKeyAcceptedForSftp(context, spi)) {
      return;
    }

    ref
        .read(sftpProvider.notifier)
        .add(
          SftpReq(
            spi,
            '$remotePath/$fileName',
            file.absolute.path,
            SftpReqType.upload,
          ),
        );
    context.showSnackBar(l10n.added2List);
  }
}

enum _SortType {
  name,
  size,
  time;

  int compareTuple(
    (FileSystemEntity, FileStat) a,
    (FileSystemEntity, FileStat) b,
  ) {
    return switch (this) {
      _SortType.name => a.$1.path.compareTo(b.$1.path),
      _SortType.size => a.$2.size.compareTo(b.$2.size),
      _SortType.time => a.$2.modified.compareTo(b.$2.modified),
    };
  }

  String get i18n => switch (this) {
    name => libL10n.name,
    size => l10n.size,
    time => l10n.time,
  };

  IconData get icon => switch (this) {
    name => Icons.sort_by_alpha,
    size => Icons.sort,
    time => Icons.access_time,
  };

  PopupMenuItem<_SortType> get menuItem {
    return PopupMenuItem(
      value: this,
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceAround,
        children: [Icon(icon), Text(i18n)],
      ),
    );
  }
}
