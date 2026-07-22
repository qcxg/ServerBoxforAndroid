import 'package:flutter_test/flutter_test.dart';
import 'package:server_box/view/page/storage/file_pane_controller.dart';

void main() {
  test('file pane controller ignores updates from a stale owner', () {
    final controller = FilePaneController(FilePaneSide.local);
    final owner = Object();
    controller.attach(
      owner: owner,
      path: '/initial',
      refresh: () async {},
      goHome: () async {},
      create: () async {},
      deleteSelected: () async {},
      transferSelected: (_) async {},
      toggleSelectionMode: () {},
      selectAll: () {},
      clearSelection: () {},
    );

    controller.update(
      owner: Object(),
      path: '/stale',
      selectedCount: 4,
      selectionMode: true,
    );

    expect(controller.path, '/initial');
    expect(controller.selectedCount, 0);
    expect(controller.selectionMode, isFalse);
  });

  test('file pane controller exposes current pane selection state', () {
    final controller = FilePaneController(FilePaneSide.remote);
    final owner = Object();
    controller.attach(
      owner: owner,
      path: '/remote',
      refresh: () async {},
      goHome: () async {},
      create: () async {},
      deleteSelected: () async {},
      transferSelected: (_) async {},
      toggleSelectionMode: () {},
      selectAll: () {},
      clearSelection: () {},
    );

    controller.update(
      owner: owner,
      path: '/remote/logs',
      selectedCount: 3,
      selectionMode: true,
    );

    expect(controller.isBound, isTrue);
    expect(controller.path, '/remote/logs');
    expect(controller.selectedCount, 3);
    expect(controller.selectionMode, isTrue);
    expect(controller.transferTarget?.path, '/remote/logs');
    expect(
      controller.isCurrentTarget(
        const FilePaneTarget(path: '/remote/logs'),
      ),
      isTrue,
    );
    expect(
      controller.isCurrentTarget(
        const FilePaneTarget(path: '/remote/other'),
      ),
      isFalse,
    );

    controller.detach(owner);
    expect(controller.transferTarget, isNull);
  });

  test('file pane controller only refreshes the matching live target', () async {
    final controller = FilePaneController(FilePaneSide.local);
    final owner = Object();
    var refreshCount = 0;
    controller.attach(
      owner: owner,
      path: '/storage/emulated/0/Download',
      refresh: () async {
        refreshCount++;
      },
      goHome: () async {},
      create: () async {},
      deleteSelected: () async {},
      transferSelected: (_) async {},
      toggleSelectionMode: () {},
      selectAll: () {},
      clearSelection: () {},
    );

    await controller.refreshIfCurrent(
      const FilePaneTarget(path: '/storage/emulated/0/Download'),
    );
    await controller.refreshIfCurrent(
      const FilePaneTarget(path: '/storage/emulated/0/Documents'),
    );

    expect(refreshCount, 1);
  });
}
