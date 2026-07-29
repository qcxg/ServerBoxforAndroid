import 'dart:async';
import 'dart:io';

import 'package:dartssh2/dartssh2.dart';
import 'package:fl_lib/fl_lib.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:icons_plus/icons_plus.dart';
import 'package:server_box/core/chan.dart';
import 'package:server_box/core/extension/context/locale.dart';
import 'package:server_box/core/extension/sftpfile.dart';
import 'package:server_box/core/extension/ssh_client.dart';
import 'package:server_box/core/utils/comparator.dart';
import 'package:server_box/core/utils/host_key_helper.dart';
import 'package:server_box/core/utils/sftp_sudo.dart';
import 'package:server_box/core/utils/sftp_timeout.dart';
import 'package:server_box/core/utils/shell_quote.dart';
import 'package:server_box/data/model/server/server_private_info.dart';
import 'package:server_box/data/model/sftp/browser_status.dart';
import 'package:server_box/data/model/sftp/req.dart';
import 'package:server_box/data/provider/server/single.dart';
import 'package:server_box/data/provider/sftp.dart';
import 'package:server_box/data/res/misc.dart';
import 'package:server_box/data/res/store.dart';
import 'package:server_box/view/page/ssh/page/page.dart';
import 'package:server_box/view/page/storage/file_pane_controller.dart';
import 'package:server_box/view/page/storage/local.dart';
import 'package:server_box/view/page/storage/sftp_mission.dart';
import 'package:server_box/view/widget/expressive_loading_indicator.dart';
import 'package:server_box/view/widget/file_list_metadata.dart';
import 'package:server_box/view/widget/file_type_icon.dart';
import 'package:server_box/view/widget/glass_context_menu.dart';
import 'package:server_box/view/widget/glass_surface.dart';
import 'package:server_box/view/widget/unix_perm.dart';

part 'sftp_helpers.dart';

final _sftpPermissionDeniedReg = RegExp(
  r'permission denied',
  caseSensitive: false,
);

enum _EmbeddedSftpAction {
  mission,
  search,
  sortName,
  sortSize,
  sortTime,
  sudo,
}

final class SftpPageArgs {
  final Spi spi;
  final bool isSelect;
  final String? initPath;

  const SftpPageArgs({required this.spi, this.isSelect = false, this.initPath});
}

class SftpPage extends ConsumerStatefulWidget {
  final SftpPageArgs args;
  final SSHClient? client;
  final bool embedded;
  final FilePaneController? paneController;
  final FilePaneController? transferTargetController;

  const SftpPage({
    super.key,
    required this.args,
    this.client,
    this.embedded = false,
    this.paneController,
    this.transferTargetController,
  });

  @override
  ConsumerState<SftpPage> createState() => _SftpPageState();

  static const route = AppRouteArg<String, SftpPageArgs>(
    page: SftpPage.new,
    path: '/sftp',
  );
}

class _SftpPageState extends ConsumerState<SftpPage> with AfterLayoutMixin {
  late final SftpBrowserStatus _status;
  late SSHClient _client;
  late SftpSudoHelper _sudoHelper;
  final _sortOption = _SortOption().vn;
  final _sudoMode = false.vn;
  final _pathController = TextEditingController(text: '/');
  final _pathFocusNode = FocusNode();
  bool _isDirectoryLoading = true;
  int _filesVersion = 0;
  int _sortedFilesVersion = -1;
  _SortOption? _sortedFilesOption;
  bool? _sortedFilesShowFoldersFirst;
  List<SftpName>? _sortedFilesCache;
  Future<SftpClient>? _openingClientFuture;
  final Set<String> _selectedNames = {};
  final Set<String> _openingRemotePaths = {};
  bool _selectionMode = false;

  bool get _useSudo => _sudoHelper.enabled && _sudoMode.value;

  @override
  void initState() {
    super.initState();
    final serverState = ref.read(serverProvider(widget.args.spi.id));
    _client = widget.client ?? serverState.client!;
    _status = SftpBrowserStatus();
    _sudoHelper = _createSudoHelper(_client);
    widget.paneController?.attach(
      owner: this,
      path: _status.path.path,
      server: widget.args.spi,
      refresh: () async => _listDir(null, true),
      goHome: _goHome,
      create: _showAddDialog,
      deleteSelected: _deleteSelected,
      transferSelected: _transferSelected,
      toggleSelectionMode: _toggleSelectionMode,
      selectAll: _selectAll,
      clearSelection: _clearSelection,
    );
  }

  @override
  void dispose() {
    widget.paneController?.detach(this);
    _status.client?.close();
    _openingClientFuture = null;
    _sortOption.dispose();
    _sudoMode.dispose();
    _pathFocusNode.dispose();
    _pathController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final children = [
      Btn.icon(
        icon: const Icon(Icons.downloading),
        onTap: () => SftpMissionPage.route.go(context),
      ),
      _buildSortMenu(),
      _buildSearchBtn(),
      if (_sudoHelper.enabled) _buildSudoBtn(),
    ];
    if (isDesktop) children.add(_buildRefreshBtn());

    if (widget.embedded) {
      return _buildEmbeddedFilePane(children);
    }

    return Scaffold(
      appBar: CustomAppBar(
        title: Text(widget.args.spi.name),
        actions: children,
      ),
      body: _buildFileView(),
      bottomNavigationBar: _buildBottom(),
    );
  }

  SftpSudoHelper _createSudoHelper(SSHClient client) {
    return SftpSudoHelper(
      client: client,
      spi: widget.args.spi,
      contextProvider: () => mounted ? context : null,
    );
  }

  @override
  void didUpdateWidget(covariant SftpPage oldWidget) {
    super.didUpdateWidget(oldWidget);
    final replacement = widget.client;
    if (replacement == null ||
        identical(replacement, _client) ||
        !_client.isClosed) {
      return;
    }
    _status.client?.close();
    _status.client = null;
    _openingClientFuture = null;
    _client = replacement;
    _sudoHelper = _createSudoHelper(replacement);
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) unawaited(_listDir());
    });
  }

  Widget _buildEmbeddedFilePane(List<Widget> actions) {
    final scheme = Theme.of(context).colorScheme;
    return Column(
      children: [
        LayoutBuilder(
          builder: (context, constraints) {
            final compact = constraints.maxWidth < 280;
            return SizedBox(
              height: compact ? 44 : 52,
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
                      Icons.cloud_rounded,
                      size: compact ? 20 : 24,
                      color: scheme.primary,
                    ),
                    SizedBox(width: compact ? 5 : 10),
                    Expanded(
                      child: Text(
                        widget.args.spi.name,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: Theme.of(context).textTheme.titleMedium
                            ?.copyWith(fontWeight: FontWeight.w700),
                      ),
                    ),
                    if (compact)
                      _buildCompactActionsMenu()
                    else
                      ...actions,
                  ],
                ),
              ),
            );
          },
        ),
        Padding(
          padding: const EdgeInsets.fromLTRB(6, 0, 6, 3),
          child: _buildPathCard(),
        ),
        Expanded(child: _buildFileView()),
        if (widget.paneController == null) _buildBottom(showPath: false),
      ],
    );
  }

  @override
  FutureOr<void> afterFirstLayout(BuildContext context) async {
    String initPath;

    try {
      final homeResult = await _client.run(
        'getent passwd -- ${shellSingleQuote(widget.args.spi.user)}',
      );
      final passwdEntry = homeResult.string.trim();
      final homePath = passwdEntry.split(':').elementAtOrNull(5)?.trim() ?? '';
      if (homePath.isNotEmpty && homePath.startsWith('/')) {
        initPath = homePath;
      } else {
        final user = widget.args.spi.user;
        initPath = user != 'root' ? '/home/$user' : '/root';
      }
    } catch (_) {
      final user = widget.args.spi.user;
      initPath = user != 'root' ? '/home/$user' : '/root';
    }

    if (Stores.setting.sftpOpenLastPath.fetch()) {
      final history = Stores.history.sftpLastPath.fetch(widget.args.spi.id);
      if (history != null) {
        SftpClient? sftp;
        try {
          final normalizedHistory = _normalizeSftpPath(history);
          sftp = await withSftpSessionOpenTimeout(
            'open session for last path',
            _client.sftp(),
            _sftpOpTimeout,
          );
          await withSftpOpTimeout(
            'list last path',
            sftp.listdir(normalizedHistory),
            _sftpOpTimeout,
          );
          initPath = normalizedHistory;
        } catch (_) {
        } finally {
          sftp?.close();
        }
      }
    }

    _status.path.path = widget.args.initPath ?? initPath;
    _syncPathController();
    _syncPaneController();
    unawaited(_listDir(context));
  }
}

extension _UI on _SftpPageState {
  Widget _buildSortMenu() {
    final options = [
      (_SortType.name, libL10n.name),
      (_SortType.size, l10n.size),
      (_SortType.time, l10n.time),
    ];
    return _sortOption.listenVal((value) {
      return PopupMenuButton<_SortType>(
        icon: const Icon(Icons.sort),
        itemBuilder: (context) {
          return options.map((r) {
            final (type, name) = r;
            final selected = type == value.sortBy;
            final title = selected
                ? "$name (${value.reversed ? '-' : '+'})"
                : name;
            return PopupMenuItem(
              value: type,
              child: Text(
                title,
                style: TextStyle(
                  color: selected ? UIs.primaryColor : null,
                  fontWeight: selected ? FontWeight.bold : null,
                ),
              ),
            );
          }).toList();
        },
        onSelected: (sortBy) {
          final old = _sortOption.value;
          if (old.sortBy == sortBy) {
            _sortOption.value = old.copyWith(reversed: !old.reversed);
          } else {
            _sortOption.value = old.copyWith(sortBy: sortBy);
          }
        },
      );
    });
  }

  Widget _buildBottom({bool showPath = true}) {
    final children = widget.args.isSelect
        ? [
            IconButton(
              onPressed: () => context.pop(_status.path.path),
              icon: const Icon(Icons.done),
            ),
            _buildSearchBtn(),
          ]
        : [
            _buildBackBtn(),
            _buildHomeBtn(),
            _buildAddBtn(),
            _buildUploadBtn(),
          ];
    return SafeArea(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(11, 7, 11, 11),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            if (showPath) _buildPathCard(),
            if (showPath) const SizedBox(height: 4),
            Row(
              children: children
                  .map(
                    (child) => Expanded(
                      child: Center(child: child),
                    ),
                  )
                  .toList(growable: false),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildPathCard() {
    return _sudoMode.listenVal((enabled) {
      final scheme = Theme.of(context).colorScheme;
      return GlassSurface(
        shape: const RoundedRectangleBorder(
          borderRadius: BorderRadius.all(Radius.circular(11)),
        ),
        child: SizedBox(
          height: widget.embedded ? 40 : null,
          child: Padding(
            padding: EdgeInsets.only(
              left: widget.embedded ? 9 : 14,
              right: widget.embedded ? 2 : 5,
            ),
            child: Row(
              children: [
                Icon(
                  Icons.folder_open_rounded,
                  size: widget.embedded ? 18 : 21,
                  color: scheme.primary,
                ),
                SizedBox(width: widget.embedded ? 6 : 10),
                Expanded(
                  child: TextField(
                    controller: _pathController,
                    focusNode: _pathFocusNode,
                    enabled: !_isDirectoryLoading,
                    keyboardType: TextInputType.url,
                    textInputAction: TextInputAction.go,
                    autocorrect: false,
                    enableSuggestions: false,
                    style: widget.embedded
                        ? Theme.of(context).textTheme.bodySmall
                        : null,
                    decoration: InputDecoration(
                      labelText: widget.embedded ? null : libL10n.path,
                      border: InputBorder.none,
                      isDense: true,
                      contentPadding: widget.embedded ? EdgeInsets.zero : null,
                    ),
                    onTapOutside: (_) => _pathFocusNode.unfocus(),
                    onSubmitted: _openPathFromEditor,
                  ),
                ),
                if (enabled)
                  Icon(
                    Icons.security_rounded,
                    size: 15,
                    color: scheme.primary,
                  ),
                IconButton(
                  tooltip: l10n.goto,
                  visualDensity: widget.embedded
                      ? VisualDensity.compact
                      : null,
                  onPressed: _isDirectoryLoading
                      ? null
                      : () => _openPathFromEditor(_pathController.text),
                  icon: Icon(
                    Icons.arrow_forward_rounded,
                    size: widget.embedded ? 19 : 24,
                  ),
                ),
              ],
            ),
          ),
        ),
      );
    });
  }

  Widget _buildCompactActionsMenu() {
    return PopupMenuButton<_EmbeddedSftpAction>(
      tooltip: MaterialLocalizations.of(context).moreButtonTooltip,
      icon: const Icon(Icons.more_vert_rounded),
      onSelected: (action) {
        switch (action) {
          case _EmbeddedSftpAction.mission:
            SftpMissionPage.route.go(context);
          case _EmbeddedSftpAction.search:
            _showFileSearch();
          case _EmbeddedSftpAction.sortName:
            _selectSort(_SortType.name);
          case _EmbeddedSftpAction.sortSize:
            _selectSort(_SortType.size);
          case _EmbeddedSftpAction.sortTime:
            _selectSort(_SortType.time);
          case _EmbeddedSftpAction.sudo:
            _sudoMode.value = !_sudoMode.value;
        }
      },
      itemBuilder: (context) => [
        PopupMenuItem(
          value: _EmbeddedSftpAction.mission,
          child: ListTile(
            leading: const Icon(Icons.downloading_rounded),
            title: Text(libL10n.mission),
          ),
        ),
        PopupMenuItem(
          value: _EmbeddedSftpAction.search,
          child: ListTile(
            leading: const Icon(Icons.search_rounded),
            title: Text(libL10n.search),
          ),
        ),
        PopupMenuItem(
          value: _EmbeddedSftpAction.sortName,
          child: ListTile(
            leading: const Icon(Icons.sort_by_alpha_rounded),
            title: Text('${l10n.sort}: ${libL10n.name}'),
          ),
        ),
        PopupMenuItem(
          value: _EmbeddedSftpAction.sortSize,
          child: ListTile(
            leading: const Icon(Icons.data_usage_rounded),
            title: Text('${l10n.sort}: ${l10n.size}'),
          ),
        ),
        PopupMenuItem(
          value: _EmbeddedSftpAction.sortTime,
          child: ListTile(
            leading: const Icon(Icons.schedule_rounded),
            title: Text('${l10n.sort}: ${l10n.time}'),
          ),
        ),
        if (_sudoHelper.enabled)
          PopupMenuItem(
            value: _EmbeddedSftpAction.sudo,
            child: ListTile(
              leading: const Icon(Icons.security_rounded),
              title: Text(l10n.trySudo),
            ),
          ),
      ],
    );
  }

  void _selectSort(_SortType sortBy) {
    final old = _sortOption.value;
    _sortOption.value = old.sortBy == sortBy
        ? old.copyWith(reversed: !old.reversed)
        : old.copyWith(sortBy: sortBy);
  }

  void _syncPaneController() {
    widget.paneController?.update(
      owner: this,
      path: _status.path.path,
      selectedCount: _selectedNames.length,
      selectionMode: _selectionMode,
    );
  }

  void _toggleSelectionMode() {
    setStateSafe(() {
      _selectionMode = !_selectionMode;
      if (!_selectionMode) _selectedNames.clear();
    });
    _syncPaneController();
  }

  void _selectAll() {
    setStateSafe(() {
      _selectionMode = true;
      _selectedNames
        ..clear()
        ..addAll(
          _status.files
              .where((file) => file.filename != '.' && file.filename != '..')
              .map((file) => file.filename),
        );
    });
    _syncPaneController();
  }

  void _clearSelection() {
    if (!_selectionMode && _selectedNames.isEmpty) return;
    setStateSafe(() {
      _selectionMode = false;
      _selectedNames.clear();
    });
    _syncPaneController();
  }

  void _toggleSelected(String name) {
    setStateSafe(() {
      if (!_selectedNames.add(name)) _selectedNames.remove(name);
    });
    _syncPaneController();
  }

  Future<void> _goHome() async {
    _pathFocusNode.unfocus();
    final user = widget.args.spi.user;
    _status.path.path = user != 'root' ? '/home/$user' : '/root';
    _clearSelection();
    await _listDir();
  }

  Future<void> _showAddDialog() async {
    await context.showRoundDialog(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Btn.tile(
            icon: const Icon(Icons.folder),
            text: libL10n.folder,
            onTap: _mkdir,
          ),
          Btn.tile(
            icon: const Icon(Icons.insert_drive_file),
            text: libL10n.file,
            onTap: _newFile,
          ),
        ],
      ),
    );
  }

  Future<void> _deleteSelected() async {
    if (_selectedNames.isEmpty) return;
    final confirmed = await context.showRoundDialog<bool>(
      title: libL10n.delete,
      child: Text(libL10n.askContinue('${_selectedNames.length}')),
      actions: Btnx.cancelRedOk,
    );
    if (confirmed != true || !mounted) return;
    final selected = _status.files
        .where((file) => _selectedNames.contains(file.filename))
        .toList(growable: false);
    final (_, error) = await context.showLoadingDialog(
      fn: () async {
        String? sudoPassword;
        if (_useSudo) {
          sudoPassword = await _sudoHelper.ensurePassword();
          if (sudoPassword == null) throw Exception(libL10n.cancel);
        }
        for (final file in selected) {
          final remotePath = _getRemotePath(file);
          final isDir = file.attr.isDirectory;
          if (sudoPassword != null) {
            await _sudoHelper.delete(
              remotePath,
              isDir: isDir,
              recursive: isDir,
              password: sudoPassword,
            );
          } else if (isDir && Stores.setting.sftpRmrDir.fetch()) {
            await _runShellCommand('rm -r ${shellSingleQuote(remotePath)}');
          } else if (isDir) {
            await _status.client!.rmdir(remotePath);
          } else {
            await _status.client!.remove(remotePath);
          }
        }
        return true;
      },
    );
    if (error != null) return;
    _clearSelection();
    await _listDir();
  }

  Future<void> _transferSelected(FilePaneTarget target) async {
    if (_selectedNames.isEmpty) return;
    final files = _status.files.where(
      (file) =>
          _selectedNames.contains(file.filename) && !file.attr.isDirectory,
    ).toList(growable: false);
    if (files.isEmpty) {
      context.showSnackBar(libL10n.empty);
      return;
    }
    await _downloadFilesToTarget(files, target, clearSelectionAfter: true);
  }

  Future<void> _downloadFilesToTarget(
    Iterable<SftpName> files,
    FilePaneTarget target, {
    bool clearSelectionAfter = false,
  }) async {
    if (!await ensureHostKeyAcceptedForSftp(context, widget.args.spi)) return;
    await Directory(target.path).create(recursive: true);
    final completions = <Future<bool>>[];
    for (final file in files) {
      final completer = Completer<bool>();
      ref
          .read(sftpProvider.notifier)
          .add(
            SftpReq(
              widget.args.spi,
              _getRemotePath(file),
              target.path.joinPath(file.filename),
              SftpReqType.download,
            ),
            completer: completer,
          );
      completions.add(completer.future);
    }
    if (clearSelectionAfter) _clearSelection();
    context.showSnackBar(l10n.added2List);
    unawaited(_refreshLocalTargetAfter(completions, target));
  }

  Future<void> _refreshLocalTargetAfter(
    List<Future<bool>> completions,
    FilePaneTarget target,
  ) async {
    if (completions.isEmpty) return;
    await Future.wait(completions);
    await widget.transferTargetController?.refreshIfCurrent(target);
  }

  Widget _buildSudoBtn() {
    return _sudoMode.listenVal((enabled) {
      return IconButton(
        tooltip: l10n.trySudo,
        onPressed: () => _sudoMode.value = !enabled,
        icon: Icon(Icons.security, color: enabled ? UIs.primaryColor : null),
      );
    });
  }

  Widget _buildFileView() {
    if (_isDirectoryLoading) {
      return const Center(child: ExpressiveLoadingIndicator());
    }
    if (_status.files.isEmpty) return Center(child: Text(libL10n.empty));

    return RefreshIndicator(
      onRefresh: _listDir,
      child: FadeIn(
        key: Key(widget.args.spi.name + _status.path.path),
        child: ValBuilder(
          listenable: _sortOption,
          builder: (sortOption) {
            final files = _getSortedFiles(sortOption);
            return ListView.builder(
              itemCount: files.length,
              padding: EdgeInsets.fromLTRB(
                widget.embedded ? 3 : 7,
                3,
                widget.embedded ? 3 : 7,
                widget.embedded ? 148 : 3,
              ),
              itemBuilder: (_, index) => _buildItem(files[index]),
            );
          },
        ),
      ),
    );
  }

  Widget _buildItem(SftpName file, {VoidCallback? beforeTap}) {
    final isDir = file.attr.isDirectory;
    return LayoutBuilder(
      builder: (context, constraints) {
        final compact = constraints.maxWidth < 390;
        final modified = _getTime(file.attr.modifyTime);
        final mode = file.attr.mode?.str ?? '';
        final size = formatFileListSize(file.attr.size ?? 0);
        final embeddedMetadata = file.filename == '..'
            ? null
            : isDir
            ? modified
            : '$modified  $size';
        final selected = _selectedNames.contains(file.filename);
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
                    onChanged: (_) => _toggleSelected(file.filename),
                  )
                : FileTypeIcon(
                    name: file.filename,
                    isDirectory: isDir,
                    size: widget.embedded ? 20 : 24,
                  ),
            title: Text(
              file.filename,
              maxLines: widget.embedded ? 2 : 1,
              overflow: TextOverflow.ellipsis,
              style: widget.embedded
                  ? Theme.of(context).textTheme.bodyMedium
                  : null,
            ),
            trailing: compact || widget.embedded
                ? null
                : Text(
                    '$modified\n$mode',
                    style: UIs.textGrey,
                    textAlign: TextAlign.right,
                  ),
            subtitle: widget.embedded
                ? embeddedMetadata == null
                      ? null
                      : FileListMetadata(text: embeddedMetadata)
                : compact
                ? Text(
                    [if (!isDir) size, modified, mode]
                        .where((value) => value.isNotEmpty)
                        .join('\n'),
                    style: UIs.textGrey,
                  )
                : isDir
                ? null
                : Text(size, style: UIs.textGrey),
            onTap: () {
              beforeTap?.call();
              if (_selectionMode && file.filename != '..') {
                _toggleSelected(file.filename);
                return;
              }
              if (isDir) {
                unawaited(_openRemoteDirectory(file));
              } else {
                unawaited(_edit(file, popMenu: false));
              }
            },
          );
        final child = widget.embedded
            ? DecoratedBox(
                decoration: BoxDecoration(
                  border: Border(
                    bottom: BorderSide(
                      color: Theme.of(
                        context,
                      ).colorScheme.outlineVariant.withAlpha(55),
                    ),
                  ),
                ),
                child: tile,
              )
            : CardX(child: tile);
        return GestureDetector(
          behavior: HitTestBehavior.translucent,
          onLongPressStart: (details) {
            beforeTap?.call();
            _onItemPress(file, !isDir, details.globalPosition);
          },
          child: child,
        );
      },
    );
  }

  List<SftpName> _getSortedFiles(_SortOption sortOption) {
    final showFoldersFirst = Stores.setting.sftpShowFoldersFirst.fetch();
    final cachedFiles = _sortedFilesCache;
    if (cachedFiles != null &&
        _sortedFilesVersion == _filesVersion &&
        _sortedFilesOption == sortOption &&
        _sortedFilesShowFoldersFirst == showFoldersFirst) {
      return cachedFiles;
    }

    final sortedFiles = sortOption.sortBy.sort(
      _status.files,
      reversed: sortOption.reversed,
    );
    _sortedFilesVersion = _filesVersion;
    _sortedFilesOption = sortOption;
    _sortedFilesShowFoldersFirst = showFoldersFirst;
    _sortedFilesCache = sortedFiles;
    return sortedFiles;
  }
}

extension _Actions on _SftpPageState {
  bool _isPermissionDeniedErr(Object? err) {
    final msg = '$err'.toLowerCase();
    return msg.contains('permission denied') ||
        msg.contains('access denied') ||
        msg.contains('code 3') ||
        msg.contains('failure');
  }

  Future<bool> _askRetryWithSudo() async {
    if (_useSudo || !_sudoHelper.enabled) return false;

    final retry = await context.showRoundDialog<bool>(
      title: l10n.trySudo,
      child: Text('Permission denied.\n${libL10n.askContinue(l10n.trySudo)}'),
      actions: Btnx.cancelRedOk,
    );
    return retry == true;
  }

  Future<void> _runShellCommand(String command) async {
    final (code, output) = await _client.execWithPwd(
      command,
      context: context,
      id: '${widget.args.spi.id}_sftp_cmd',
    );
    if (code != 0) {
      throw Exception(output.trim().isEmpty ? 'Command failed' : output.trim());
    }
  }

  Future<bool> _runWithSudoRetry({
    required Future<void> Function() normal,
    required Future<void> Function(String pwd) sudo,
  }) async {
    if (_useSudo) {
      final pwd = await _sudoHelper.ensurePassword();
      if (pwd == null) return false;
      final (suc, err) = await context.showLoadingDialog(
        fn: () async {
          await sudo(pwd);
          return true;
        },
      );
      return suc != null && err == null;
    }

    final (suc, err) = await context.showLoadingDialog(
      fn: () async {
        await normal();
        return true;
      },
    );
    if (suc != null && err == null) return true;
    if (!_isPermissionDeniedErr(err)) return false;

    final shouldRetry = await _askRetryWithSudo();
    if (!shouldRetry) return false;

    final pwd = await _sudoHelper.ensurePassword();
    if (pwd == null) return false;
    final (sudoSuc, sudoErr) = await context.showLoadingDialog(
      fn: () async {
        await sudo(pwd);
        return true;
      },
    );
    if (sudoSuc != null && sudoErr == null) {
      _sudoMode.value = true;
    }
    return sudoSuc != null && sudoErr == null;
  }

  Future<bool> _canWriteRemotePath(String remoteDir) async {
    final (code, _) = await _client.execWithPwd(
      'test -w ${shellSingleQuote(remoteDir)}',
      context: context,
      id: '${widget.args.spi.id}_sftp_write_probe',
    );
    return code == 0;
  }

  Future<bool> _uploadViaSudo({
    required String localPath,
    required String remotePath,
    required String fileName,
  }) async {
    final pwd = await _sudoHelper.ensurePassword();
    if (pwd == null) return false;

    final tmpPath =
        '/tmp/serverbox-upload-${DateTime.now().microsecondsSinceEpoch}-$fileName';
    final completer = Completer<bool>();
    final req = SftpReq(
      widget.args.spi,
      tmpPath,
      localPath,
      SftpReqType.upload,
    );
    final reqId = ref
        .read(sftpProvider.notifier)
        .add(req, completer: completer, announceUpload: false);

    final (uploaded, uploadErr) = await context.showLoadingDialog(
      fn: () async {
        final success = await completer.future;
        if (!success) {
          final status = ref.read(sftpProvider.notifier).get(reqId);
          throw status?.error ?? Exception(libL10n.fail);
        }
        final status = ref.read(sftpProvider.notifier).get(reqId);
        if (status?.error != null) {
          throw status!.error!;
        }
        await _sudoHelper.rename(tmpPath, remotePath, password: pwd);
        return true;
      },
    );

    if (uploaded != null && uploadErr == null) {
      _sudoMode.value = true;
      return true;
    }

    try {
      await _sudoHelper.delete(
        tmpPath,
        isDir: false,
        recursive: false,
        password: pwd,
      );
    } catch (_) {}
    return false;
  }

  void _onItemPress(SftpName file, bool notDir, Offset anchor) {
    final transferTarget = widget.transferTargetController?.transferTarget;
    showGlassContextMenu(
      context,
      anchor: anchor,
      actions: [
        if (notDir)
          GlassContextMenuAction(
            icon: Icons.edit_rounded,
            label: libL10n.edit,
            onPressed: () => _edit(file, popMenu: false),
          ),
        if (notDir && (transferTarget != null || !widget.embedded))
          GlassContextMenuAction(
            icon: Icons.download_rounded,
            label: libL10n.download,
            onPressed: transferTarget != null
                ? () => _downloadFilesToTarget([file], transferTarget)
                : () => _download(file, popMenu: false),
          ),
        if (notDir && _canDecompress(file.filename))
          GlassContextMenuAction(
            icon: Icons.folder_zip_rounded,
            label: libL10n.decompress,
            onPressed: () => _decompress(file, popMenu: false),
          ),
        GlassContextMenuAction(
          icon: Icons.drive_file_rename_outline_rounded,
          label: libL10n.rename,
          onPressed: () => _rename(file, popMenu: false),
        ),
        GlassContextMenuAction(
          icon: MingCute.copy_line,
          label: l10n.copyPath,
          onPressed: () {
            Pfs.copy(_getRemotePath(file));
            context.showSnackBar(libL10n.success);
          },
        ),
        GlassContextMenuAction(
          icon: Icons.security_rounded,
          label: l10n.permission,
          onPressed: () => _changePermissions(file),
        ),
        GlassContextMenuAction(
          icon: Icons.delete_outline_rounded,
          label: libL10n.delete,
          destructive: true,
          onPressed: () => _delete(file, popMenu: false),
        ),
      ],
    );
  }

  Future<void> _changePermissions(SftpName file) async {
    final perm = file.attr.mode?.toUnixPerm() ?? UnixPerm.empty;
    var newPerm = perm.copyWith();
    final ok = await context.showRoundDialog(
      child: UnixPermEditor(perm: perm, onChanged: (p) => newPerm = p),
      actions: Btnx.okReds,
    );
    final permStr = newPerm.perm;
    if (ok != true || permStr == perm.perm) return;
    final remotePath = _getRemotePath(file);
    final suc = await _runWithSudoRetry(
      normal: () => _runShellCommand(
        'chmod ${shellSingleQuote(permStr)} ${shellSingleQuote(remotePath)}',
      ),
      sudo: (pwd) => _sudoHelper.chmod(permStr, remotePath, password: pwd),
    );
    if (!suc) return;
    await _listDir();
  }

  Future<void> _edit(SftpName name, {bool popMenu = true}) async {
    if (popMenu) context.pop();

    final remotePath = _getRemotePath(name);
    if (!_openingRemotePaths.add(remotePath)) return;
    try {
    final useSudoForEdit = _useSudo;

    // #489
    final editor = Stores.setting.sftpEditor.fetch();
    if (editor.isNotEmpty) {
      final sudoPrefix = useSudoForEdit ? 'sudo ' : '';
      final cmd =
          '$sudoPrefix$editor ${shellSingleQuote(remotePath)}';
      final args = SshPageArgs(spi: widget.args.spi, initCmd: cmd);
      await SSHPage.route.go(context, args);
      await _listDir();
      return;
    }

    int? size = name.attr.size;
    String? sudoPassword;
    if (useSudoForEdit) {
      sudoPassword = await _sudoHelper.ensurePassword();
      if (sudoPassword == null) return;
      final (ret, err) = await context.showLoadingDialog(
        fn: () => _sudoHelper.getFileSize(
          remotePath,
          password: sudoPassword,
        ),
      );
      if (ret == null || err != null) return;
      size = ret;
    } else {
      if (!await ensureHostKeyAcceptedForSftp(context, widget.args.spi)) {
        return;
      }
      final (attrs, err) = await context.showLoadingDialog(
        fn: () => _statRemoteFileWithRetry(remotePath),
      );
      if (attrs == null || err != null || attrs.isDirectory) {
        unawaited(_listDir(null, true));
        return;
      }
      size = attrs.size;
    }

    if (size == null || size > Miscs.editorMaxSize) {
      context.showSnackBar(
        l10n.fileTooLarge(name.filename, size ?? 0, Miscs.editorMaxSize),
      );
      return;
    }

    final localPath = _getLocalPath(remotePath);
    if (size == 0) {
      final localFile = File(localPath);
      await localFile.parent.create(recursive: true);
      await localFile.writeAsBytes(const <int>[]);
    } else if (useSudoForEdit) {
      final (suc, err) = await context.showLoadingDialog(
        fn: () async {
          await _sudoHelper.downloadTextFile(
            remotePath,
            localPath,
            password: sudoPassword,
          );
          return true;
        },
      );
      if (suc == null || err != null) return;
    } else {
      final (suc, err) = await context.showLoadingDialog(
        fn: () => _downloadEditorCopyWithRetry(
          remotePath: remotePath,
          localPath: localPath,
          expectedSize: size!,
        ),
      );
      if (suc != true || err != null) return;
    }

    final remoteDir = _status.path.path;
    var preserveTemporaryCopy = false;
    var backgroundUploadPending = false;
    try {
      await EditorPage.route.go(
        context,
        args: EditorPageArgs(
          path: localPath,
          onSave: (_) async {
            if (useSudoForEdit) {
              final pwd = sudoPassword;
              if (pwd == null) {
                preserveTemporaryCopy = true;
                return;
              }
              backgroundUploadPending = true;
              unawaited(
                _finishBackgroundSudoEditUpload(
                  localPath: localPath,
                  remotePath: remotePath,
                  remoteDir: remoteDir,
                  password: pwd,
                ),
              );
              return;
            }

            final uploadCompleter = Completer<bool>();
            ref
                .read(sftpProvider.notifier)
                .add(
                  SftpReq(
                    widget.args.spi,
                    remotePath,
                    localPath,
                    SftpReqType.upload,
                  ),
                  completer: uploadCompleter,
                );
            backgroundUploadPending = true;
            if (context.mounted) context.showSnackBar(l10n.added2List);
            unawaited(
              _finishBackgroundQueuedEditUpload(
                completion: uploadCompleter.future,
                localPath: localPath,
                remotePath: remotePath,
                remoteDir: remoteDir,
              ),
            );
          },
          closeAfterSave: true,
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
    } catch (_) {
      preserveTemporaryCopy = true;
      rethrow;
    } finally {
      if (!preserveTemporaryCopy && !backgroundUploadPending) {
        await _deleteTemporaryEditFile(localPath);
      }
    }
    } catch (error, stackTrace) {
      if (mounted) context.showErrDialog(error, stackTrace);
    } finally {
      _openingRemotePaths.remove(remotePath);
    }
  }

  void _download(SftpName name, {bool popMenu = true}) {
    if (popMenu) context.pop();
    context.showRoundDialog(
      title: libL10n.attention,
      child: Text('${l10n.dl2Local(name.filename)}\n${l10n.keepForeground}'),
      actions: [
        TextButton(onPressed: () => context.pop(), child: Text(libL10n.cancel)),
        TextButton(
          onPressed: () async {
            context.pop();
            final remotePath = _getRemotePath(name);

            if (!await ensureHostKeyAcceptedForSftp(context, widget.args.spi)) {
              return;
            }

            ref
                .read(sftpProvider.notifier)
                .add(
                  SftpReq(
                    widget.args.spi,
                    remotePath,
                    _getLocalPath(remotePath),
                    SftpReqType.download,
                  ),
                );

          },
          child: Text(libL10n.download),
        ),
      ],
    );
  }

  void _delete(SftpName file, {bool popMenu = true}) {
    if (popMenu) context.pop();
    final isDir = file.attr.isDirectory;
    var useRmr = Stores.setting.sftpRmrDir.fetch();

    // Most users don't know that SFTP can't delete a directory which is not
    // empty, so we provide a checkbox to let user choose to use `rm -r` or not
    context.showRoundDialog(
      title: libL10n.attention,
      child: StatefulBuilder(
        builder: (_, setState) {
          final text = libL10n.askContinue(
            '${libL10n.delete} ${file.filename}'
            '${isDir && useRmr ? '\n${l10n.sftpRmrDirSummary}' : ''}',
          );
          return Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              ListTile(title: Text(text)),
              if (isDir && !Stores.setting.sftpRmrDir.fetch())
                CheckboxListTile(
                  title: Text(l10n.sftpRmrDirSummary),
                  value: useRmr,
                  onChanged: (val) {
                    setState(() {
                      useRmr = val ?? false;
                    });
                  },
                ),
            ],
          );
        },
      ),
      actions: [
        TextButton(onPressed: () => context.pop(), child: Text(libL10n.cancel)),
        TextButton(
          onPressed: () async {
            context.pop();
            final remotePath = _getRemotePath(file);
            final suc = await _runWithSudoRetry(
              normal: () async {
                if (useRmr) {
                  await _runShellCommand('rm -r ${shellSingleQuote(remotePath)}');
                } else if (isDir) {
                  await _status.client!.rmdir(remotePath);
                } else {
                  await _status.client!.remove(remotePath);
                }
              },
              sudo: (pwd) => _sudoHelper.delete(
                remotePath,
                isDir: isDir,
                recursive: useRmr,
                password: pwd,
              ),
            );
            if (!suc) return;

            _listDir();
          },
          child: Text(libL10n.delete, style: UIs.textRed),
        ),
      ],
    );
  }

  Future<void> _showSftpInputDialog({
    required String title,
    required IconData icon,
    String? initialValue,
    required Future<bool> Function(String text) onConfirm,
    bool popMenu = true,
  }) async {
    if (popMenu) context.pop();
    final textController = TextEditingController(text: initialValue);

    void onSubmitted() async {
      final text = textController.text.trim();
      if (text.isEmpty) {
        context.showRoundDialog(
          title: libL10n.attention,
          child: Text(libL10n.empty),
          actions: Btnx.oks,
        );
        return;
      }
      context.pop();
      final suc = await onConfirm(text);
      if (!suc) return;
      _listDir();
    }

    await context.showRoundDialog(
      title: title,
      child: Input(
        autoFocus: true,
        icon: icon,
        controller: textController,
        label: libL10n.name,
        suggestion: true,
        onSubmitted: (_) => onSubmitted(),
      ),
      actions: [
        Btn.cancel(),
        Btn.ok(onTap: onSubmitted, red: true),
      ],
    );
    textController.dispose();
  }

  void _mkdir() {
    _showSftpInputDialog(
      title: libL10n.folder,
      icon: Icons.folder,
      onConfirm: (text) async {
        final dir = '${_status.path.path}/$text';
        return await _runWithSudoRetry(
          normal: () => _status.client!.mkdir(dir),
          sudo: (pwd) => _sudoHelper.mkdir(dir, password: pwd),
        );
      },
    );
  }

  void _newFile() {
    _showSftpInputDialog(
      title: libL10n.file,
      icon: Icons.insert_drive_file,
      onConfirm: (text) async {
        final path = '${_status.path.path}/$text';
        return await _runWithSudoRetry(
          normal: () => _runShellCommand('touch ${shellSingleQuote(path)}'),
          sudo: (pwd) => _sudoHelper.touch(path, password: pwd),
        );
      },
    );
  }

  void _rename(SftpName file, {bool popMenu = true}) {
    _showSftpInputDialog(
      title: libL10n.rename,
      icon: Icons.abc,
      initialValue: file.filename,
      popMenu: popMenu,
      onConfirm: (newName) async {
        return await _runWithSudoRetry(
          normal: () => _status.client!.rename(
            _getRemotePath(file),
            _status.path.path.joinPath(newName, separator: '/'),
          ),
          sudo: (pwd) => _sudoHelper.rename(
            _getRemotePath(file),
            _status.path.path.joinPath(newName, separator: '/'),
            password: pwd,
          ),
        );
      },
    );
  }

  Future<void> _decompress(SftpName name, {bool popMenu = true}) async {
    if (popMenu) context.pop();
    final absPath = _getRemotePath(name);
    final cmd = _getDecompressCmd(absPath);
    if (cmd == null) {
      context.showRoundDialog(
        title: libL10n.error,
        child: Text('Unsupport file: ${name.filename}'),
        actions: [Btn.ok()],
      );
      return;
    }

    final confirm = await context.showRoundDialog(
      title: libL10n.attention,
      child: SimpleMarkdown(data: '```sh\n$cmd\n```'),
      actions: Btnx.cancelRedOk,
    );
    if (confirm != true) return;

    final args = SshPageArgs(spi: widget.args.spi, initCmd: cmd);
    await SSHPage.route.go(context, args);
    _listDir();
  }

  String _getRemotePath(SftpName name) {
    final prePath = _status.path.path;
    // Only support Linux as remote now, so the seperator is '/'
    return prePath.joinPath(name.filename, separator: '/');
  }

  /// Local file dir + server id + remote path
  String _getLocalPath(String remotePath) {
    final pathParts = remotePath.split('/').where((part) => part.isNotEmpty);
    return pathParts.fold(
      Paths.file.joinPath(widget.args.spi.id),
      (path, part) => path.joinPath(_safeLocalPathPart(part)),
    );
  }

  Future<SftpClient> _ensureBrowserClient() async {
    final current = _status.client;
    if (current != null) return current;

    final opening = _openingClientFuture ??=
        withSftpSessionOpenTimeout(
          'open browser session',
          _client.sftp(),
          _sftpOpTimeout,
        );
    try {
      final opened = await opening;
      return _status.client ??= opened;
    } finally {
      if (identical(_openingClientFuture, opening)) {
        _openingClientFuture = null;
      }
    }
  }

  void _resetBrowserClient() {
    _status.client?.close();
    _status.client = null;
    _openingClientFuture = null;
  }

  bool _isTransientSftpError(Object error) {
    if (error is FileSystemException || error is FormatException) return false;
    if (error is SftpStatusError) {
      // 2 = no such file, 3 = permission denied. Retrying those would only
      // duplicate work; channel/failure/connection statuses may recover.
      return error.code != 2 && error.code != 3;
    }
    return true;
  }

  Future<SftpFileAttrs> _statRemoteFileWithRetry(String remotePath) async {
    Object? lastError;
    StackTrace? lastStackTrace;
    for (var attempt = 0; attempt < 2; attempt++) {
      try {
        final sftp = await _ensureBrowserClient();
        return await withSftpOpTimeout(
          'stat edit file',
          sftp.stat(remotePath),
          _sftpOpTimeout,
        );
      } catch (error, stackTrace) {
        lastError = error;
        lastStackTrace = stackTrace;
        if (attempt > 0 || !_isTransientSftpError(error)) {
          Error.throwWithStackTrace(error, stackTrace);
        }
        _resetBrowserClient();
        await Future<void>.delayed(const Duration(milliseconds: 180));
      }
    }
    Error.throwWithStackTrace(lastError!, lastStackTrace!);
  }

  Future<bool> _downloadEditorCopyWithRetry({
    required String remotePath,
    required String localPath,
    required int expectedSize,
  }) async {
    Object? lastError;
    StackTrace? lastStackTrace;
    for (var attempt = 0; attempt < 2; attempt++) {
      SftpFile? remoteFile;
      try {
        final sftp = await _ensureBrowserClient();
        final openedRemoteFile = await withSftpOpTimeout(
          'open edit file',
          sftp.open(remotePath),
          _sftpOpTimeout,
        );
        remoteFile = openedRemoteFile;
        final bytes = await withSftpOpTimeout(
          'read edit file',
          openedRemoteFile.readBytes(length: expectedSize),
          _sftpOpTimeout,
        );
        if (bytes.length != expectedSize) {
          throw SftpError(
            'Incomplete editor download: '
            '${bytes.length} of $expectedSize bytes',
          );
        }

        final localFile = File(localPath);
        await localFile.parent.create(recursive: true);
        await localFile.writeAsBytes(bytes, flush: true);
        if (!await localFile.exists() ||
            await localFile.length() != expectedSize) {
          throw FileSystemException(
            'Downloaded editor copy failed validation',
            localPath,
          );
        }
        return true;
      } catch (error, stackTrace) {
        lastError = error;
        lastStackTrace = stackTrace;
        if (attempt > 0 || !_isTransientSftpError(error)) {
          Error.throwWithStackTrace(error, stackTrace);
        }
        _resetBrowserClient();
        await Future<void>.delayed(const Duration(milliseconds: 180));
      } finally {
        await remoteFile?.close();
      }
    }
    Error.throwWithStackTrace(lastError!, lastStackTrace!);
  }

  Future<void> _deleteTemporaryEditFile(String localPath) async {
    try {
      final file = File(localPath);
      if (await file.exists()) await file.delete();

      final cacheRoot = Directory(Paths.file).absolute.path;
      var parent = file.parent.absolute;
      while (parent.path != cacheRoot &&
          parent.path.startsWith('$cacheRoot${Pfs.seperator}')) {
        if (!await parent.list().isEmpty) break;
        final next = parent.parent;
        await parent.delete();
        parent = next;
      }
    } catch (e, s) {
      Loggers.app.warning('Failed to clean temporary SFTP edit file', e, s);
    }
  }

  Future<void> _finishBackgroundQueuedEditUpload({
    required Future<bool> completion,
    required String localPath,
    required String remotePath,
    required String remoteDir,
  }) async {
    try {
      final uploaded = await completion;
      if (!uploaded) {
        Loggers.app.warning(
          'Background editor upload failed for $remotePath; '
          'preserving $localPath',
        );
        return;
      }
      await _deleteTemporaryEditFile(localPath);
      if (!mounted || _status.path.path != remoteDir) return;
      await _listDir(null, true);
    } catch (e, s) {
      Loggers.app.warning(
        'Background editor upload failed for $remotePath; '
        'preserving $localPath',
        e,
        s,
      );
    }
  }

  Future<void> _finishBackgroundSudoEditUpload({
    required String localPath,
    required String remotePath,
    required String remoteDir,
    required String password,
  }) async {
    try {
      await _sudoHelper.uploadTextFile(
        localPath,
        remotePath,
        password: password,
      );
      await _deleteTemporaryEditFile(localPath);
      await MethodChans.showToast(
        '${libL10n.upload} ${libL10n.success} (1)',
      );
      if (!mounted || _status.path.path != remoteDir) return;
      await _listDir(null, true);
    } catch (e, s) {
      Loggers.app.warning(
        'Background sudo editor upload failed for $remotePath; '
        'preserving $localPath',
        e,
        s,
      );
      await MethodChans.showToast(
        '${libL10n.upload} ${libL10n.fail} (1/1)',
      );
    }
  }

  String _safeLocalPathPart(String part) {
    if (part == '.' || part == '..') return '_';
    var safe = part.replaceAll(RegExp(r'[<>:"/\\|?*\x00-\x1F]'), '_');
    safe = safe.replaceAll(RegExp(r'[ .]+$'), '');
    if (safe.isEmpty) return '_';

    final baseName = safe.split('.').first.toUpperCase();
    final isReservedDeviceName = RegExp(
      r'^(CON|PRN|AUX|NUL|COM[1-9]|LPT[1-9])$',
    ).hasMatch(baseName);
    return isReservedDeviceName ? '_$safe' : safe;
  }

  /// Only return true if the path is changed
  Duration get _sftpOpTimeout {
    final seconds = Stores.setting.timeout.fetch();
    return sftpOperationTimeout(seconds);
  }

  Future<bool?> _listDir([
    BuildContext? dialogContext,
    bool silent = false,
  ]) async {
    if (dialogContext == null && !mounted) return false;
    final context = dialogContext ?? this.context;
    if (!context.mounted) return false;
    _syncPathController();

    Future<bool> loadDirectory() async {
      final listPath = _status.path.path;
      final fs = await _listDirWithFallback(listPath);
      if (fs == null) {
        return false;
      }
      fs.sort((a, b) => a.filename.compareTo(b.filename));

      /// Issue #97
      /// In order to compatible with the Synology NAS
      /// which not has '.' and '..' in listdir
      if (fs.firstOrNull?.filename == '.') {
        fs.removeAt(0);
      }

      if (fs.isNotEmpty &&
          fs.firstOrNull?.filename == '..' &&
          _status.path.path == '/') {
        fs.removeAt(0);
      }
      if (_status.path.path != listPath) return false;
      if (mounted) {
        // ignore: invalid_use_of_protected_member
        setState(() {
          _status.files
            ..clear()
            ..addAll(fs);
          _selectedNames.removeWhere(
            (name) => !fs.any((file) => file.filename == name),
          );
          _filesVersion++;
          _sortedFilesCache = null;
          _sortedFilesShowFoldersFirst = null;
        });
        _syncPaneController();

        // Only update history when success
        if (Stores.setting.sftpOpenLastPath.fetch()) {
          final normalizedPath = _normalizeSftpPath(listPath);
          Stores.history.sftpLastPath.put(widget.args.spi.id, normalizedPath);
        }

        return true;
      }
      return false;
    }

    if (silent) {
      try {
        return await loadDirectory();
      } catch (e, s) {
        Loggers.app.warning('Failed to refresh SFTP directory', e, s);
        return false;
      }
    }

    if (mounted && !_isDirectoryLoading) {
      // ignore: invalid_use_of_protected_member
      setState(() => _isDirectoryLoading = true);
    }
    try {
      return await loadDirectory();
    } catch (e, s) {
      if (context.mounted) context.showErrDialog(e, s);
      return false;
    } finally {
      if (mounted) {
        // ignore: invalid_use_of_protected_member
        setState(() => _isDirectoryLoading = false);
      }
    }
  }

  Future<List<SftpName>?> _listDirWithFallback(String listPath) async {
    Object? lastError;
    StackTrace? lastStackTrace;
    for (var attempt = 0; attempt < 2; attempt++) {
      try {
        return await _listDirWithFallbackOnce(listPath);
      } catch (error, stackTrace) {
        lastError = error;
        lastStackTrace = stackTrace;
        if (attempt > 0 || !_isTransientSftpError(error)) {
          Error.throwWithStackTrace(error, stackTrace);
        }
        _resetBrowserClient();
        await Future<void>.delayed(const Duration(milliseconds: 180));
      }
    }
    Error.throwWithStackTrace(lastError!, lastStackTrace!);
  }

  Future<List<SftpName>?> _listDirWithFallbackOnce(String listPath) async {
    if (_useSudo) {
      final pwd = await _sudoHelper.ensurePassword();
      if (pwd == null) return null;
      final items = await _sudoHelper.listDir(listPath, password: pwd);
      _sudoMode.value = true;
      return items;
    }

    try {
      final browserClient = await _ensureBrowserClient();
      if (!mounted) return null;
      return await withSftpOpTimeout(
        'list directory',
        browserClient.listdir(listPath),
        _sftpOpTimeout,
      );
    } on SftpStatusError catch (e) {
      _openingClientFuture = null;
      final canFallback =
          _sudoHelper.enabled &&
          (e.code == 3 || _sftpPermissionDeniedReg.hasMatch(e.message));
      if (!canFallback) rethrow;

      final pwd = await _sudoHelper.ensurePassword();
      if (pwd == null) return null;
      final items = await _sudoHelper.listDir(listPath, password: pwd);
      _sudoMode.value = true;
      return items;
    } catch (e) {
      if (e is! SftpStatusError) _resetBrowserClient();
      _openingClientFuture = null;
      rethrow;
    }
  }

  Future<void> _backward() async {
    _pathFocusNode.unfocus();
    if (_status.path.undo()) {
      _clearSelection();
      await _listDir();
    }
  }

  Widget _buildBackBtn() {
    return Btn.icon(onTap: _backward, icon: const Icon(Icons.arrow_back));
  }

  Widget _buildSearchBtn() {
    return Btn.icon(
      onTap: _showFileSearch,
      icon: const Icon(Icons.search),
    );
  }

  void _showFileSearch() {
    Stream<SftpName> find(String query) async* {
      final fs = _status.files;
      for (final f in fs) {
        if (f.filename.contains(query)) yield f;
      }
    }

    showSearch(
      context: context,
      delegate: SearchPage(
        padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 3),
        future: (q) => find(q).toList(),
        builder: (ctx, e) => _buildItem(e, beforeTap: ctx.pop),
      ),
    );
  }

  Widget _buildUploadBtn() {
    return Btn.icon(
      onTap: () async {
        final idx = await context.showRoundDialog(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Btn.tile(
                icon: const Icon(Icons.open_in_new),
                text: l10n.system,
                onTap: () => context.pop(1),
              ),
              Btn.tile(
                icon: const Icon(Icons.folder),
                text: libL10n.inner,
                onTap: () => context.pop(0),
              ),
            ],
          ),
        );
        final path = switch (idx) {
          0 => await LocalFilePage.route.go(
            context,
            args: const LocalFilePageArgs(isPickFile: true),
          ),
          1 => await Pfs.pickFilePath(),
          _ => null,
        };
        if (path == null) return;

        final remoteDir = _status.path.path;
        final fileName = path.split(Platform.pathSeparator).lastOrNull;
        if (fileName == null || fileName.isEmpty) return;
        final remotePath = '$remoteDir/$fileName';
        Loggers.app.info('SFTP upload local: $path, remote: $remotePath');
        if (!await ensureHostKeyAcceptedForSftp(context, widget.args.spi)) {
          return;
        }

        if (_useSudo) {
          await _uploadViaSudo(
            localPath: path,
            remotePath: remotePath,
            fileName: fileName,
          );
          await _listDir();
          return;
        }

        final writable = await _canWriteRemotePath(remoteDir);
        if (!writable) {
          final shouldRetry = await _askRetryWithSudo();
          if (shouldRetry) {
            final suc = await _uploadViaSudo(
              localPath: path,
              remotePath: remotePath,
              fileName: fileName,
            );
            if (suc) {
              await _listDir();
            }
          }
          return;
        }

        final completer = Completer<bool>();
        ref
            .read(sftpProvider.notifier)
            .add(
              SftpReq(widget.args.spi, remotePath, path, SftpReqType.upload),
              completer: completer,
            );
        unawaited(_refreshCurrentDirectoryAfter(completer.future, remoteDir));
      },
      icon: const Icon(Icons.upload_file),
    );
  }

  Future<void> _refreshCurrentDirectoryAfter(
    Future<bool> completion,
    String remoteDir,
  ) async {
    await completion;
    if (!mounted || _status.path.path != remoteDir) return;
    await _listDir(null, true);
  }

  Widget _buildAddBtn() {
    return Btn.icon(
      onTap: _showAddDialog,
      icon: const Icon(Icons.add),
    );
  }

  Widget _buildRefreshBtn() {
    return Btn.icon(onTap: _listDir, icon: const Icon(Icons.refresh));
  }

  Widget _buildHomeBtn() {
    return IconButton(
      onPressed: _goHome,
      icon: const Icon(Icons.home),
    );
  }

  void _syncPathController() {
    final path = _status.path.path;
    if (_pathController.text == path) return;
    _pathController.value = TextEditingValue(
      text: path,
      selection: TextSelection.collapsed(offset: path.length),
    );
  }

  Future<void> _openPathFromEditor(String rawPath) async {
    _pathFocusNode.unfocus();
    final path = _normalizeSftpPath(rawPath.trim());
    if (path.isEmpty) {
      _syncPathController();
      return;
    }

    final oldPath = _status.path.path;
    if (path != oldPath) {
      _clearSelection();
      _status.path.path = path;
      _syncPathController();
    }

    final success = await _listDir() ?? false;
    if (!success && path != oldPath) {
      _status.path.undo();
      _syncPathController();
      if (mounted) {
        // ignore: invalid_use_of_protected_member
        setState(() {});
      }
      return;
    }

    if (success && Stores.setting.recordHistory.fetch()) {
      Stores.history.sftpGoPath.add(_status.path.path);
    }
  }

  Future<void> _openRemoteDirectory(SftpName directory) async {
    _pathFocusNode.unfocus();
    _clearSelection();
    _status.path.path = directory.filename;
    final opened = await _listDir();
    if (opened == true || !mounted) return;

    // The row may be stale or the SFTP channel may have dropped. Restore the
    // last valid directory so one failed tap cannot strand the remote pane.
    _status.path.undo();
    _syncPathController();
    await _listDir(null, true);
  }
}
