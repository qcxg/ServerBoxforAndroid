import 'package:flutter/foundation.dart';
import 'package:server_box/data/model/server/server_private_info.dart';

enum FilePaneSide { local, remote }

final class FilePaneTarget {
  const FilePaneTarget({required this.path, this.server});

  final String path;
  final Spi? server;
}

final class FilePaneController extends ChangeNotifier {
  FilePaneController(this.side);

  final FilePaneSide side;

  Object? _owner;
  String path = '';
  Spi? server;
  int selectedCount = 0;
  bool selectionMode = false;

  Future<void> Function()? _refresh;
  Future<void> Function()? _goHome;
  Future<void> Function()? _create;
  Future<void> Function()? _deleteSelected;
  Future<void> Function(FilePaneTarget target)? _transferSelected;
  VoidCallback? _toggleSelectionMode;
  VoidCallback? _selectAll;
  VoidCallback? _clearSelection;

  bool get isBound => _owner != null;
  FilePaneTarget? get transferTarget => isBound
      ? FilePaneTarget(path: path, server: server)
      : null;

  bool isCurrentTarget(FilePaneTarget target) {
    if (!isBound || path != target.path) return false;
    return server?.id == target.server?.id;
  }

  void attach({
    required Object owner,
    required String path,
    Spi? server,
    required Future<void> Function() refresh,
    required Future<void> Function() goHome,
    required Future<void> Function() create,
    required Future<void> Function() deleteSelected,
    required Future<void> Function(FilePaneTarget target) transferSelected,
    required VoidCallback toggleSelectionMode,
    required VoidCallback selectAll,
    required VoidCallback clearSelection,
  }) {
    _owner = owner;
    this.path = path;
    this.server = server;
    _refresh = refresh;
    _goHome = goHome;
    _create = create;
    _deleteSelected = deleteSelected;
    _transferSelected = transferSelected;
    _toggleSelectionMode = toggleSelectionMode;
    _selectAll = selectAll;
    _clearSelection = clearSelection;
    notifyListeners();
  }

  void update({
    required Object owner,
    required String path,
    required int selectedCount,
    required bool selectionMode,
  }) {
    if (!identical(owner, _owner)) return;
    this.path = path;
    this.selectedCount = selectedCount;
    this.selectionMode = selectionMode;
    notifyListeners();
  }

  void detach(Object owner) {
    if (!identical(owner, _owner)) return;
    _owner = null;
    server = null;
    selectedCount = 0;
    selectionMode = false;
    _refresh = null;
    _goHome = null;
    _create = null;
    _deleteSelected = null;
    _transferSelected = null;
    _toggleSelectionMode = null;
    _selectAll = null;
    _clearSelection = null;
    notifyListeners();
  }

  Future<void> refresh() async => _refresh?.call();
  Future<void> refreshIfCurrent(FilePaneTarget target) async {
    if (!isCurrentTarget(target)) return;
    await refresh();
  }
  Future<void> goHome() async => _goHome?.call();
  Future<void> create() async => _create?.call();
  Future<void> deleteSelected() async => _deleteSelected?.call();
  Future<void> transferSelected(FilePaneTarget target) async =>
      _transferSelected?.call(target);
  void toggleSelectionMode() => _toggleSelectionMode?.call();
  void selectAll() => _selectAll?.call();
  void clearSelection() => _clearSelection?.call();
}
