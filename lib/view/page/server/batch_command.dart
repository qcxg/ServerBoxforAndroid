import 'dart:convert';
import 'dart:typed_data';

import 'package:fl_lib/fl_lib.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:server_box/core/extension/context/locale.dart';
import 'package:server_box/core/extension/ssh_client.dart';
import 'package:server_box/data/model/server/server.dart';
import 'package:server_box/data/model/server/server_private_info.dart';
import 'package:server_box/data/model/server/snippet.dart';
import 'package:server_box/data/model/server/try_limiter.dart';
import 'package:server_box/data/provider/server/all.dart';
import 'package:server_box/data/provider/server/single.dart';
import 'package:server_box/data/provider/snippet.dart';

class BatchCommandPage extends ConsumerStatefulWidget {
  const BatchCommandPage({super.key});

  static const route = AppRouteNoArg(
    page: BatchCommandPage.new,
    path: '/batch-command',
  );

  @override
  ConsumerState<BatchCommandPage> createState() => _BatchCommandPageState();
}

class _BatchCommandPageState extends ConsumerState<BatchCommandPage> {
  static const _maxVisibleOutput = 200000;

  final _commandController = TextEditingController();
  final _selectedIds = <String>{};
  final _results = <String, _BatchCommandResult>{};
  bool _running = false;

  @override
  void dispose() {
    _commandController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final serverState = ref.watch(serversProvider);
    final servers = serverState.serverOrder
        .map((id) => serverState.servers[id])
        .whereType<Spi>()
        .toList(growable: false);
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;

    return Scaffold(
      appBar: CustomAppBar(title: Text(context.l10n.batchCommand)),
      body: Align(
        alignment: Alignment.topCenter,
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 980),
          child: ListView(
            padding: EdgeInsets.fromLTRB(
              16,
              12,
              16,
              MediaQuery.paddingOf(context).bottom + 24,
            ),
            children: [
              Text(
                context.l10n.batchCommandDescription,
                style: theme.textTheme.bodyMedium?.copyWith(
                  color: scheme.onSurfaceVariant,
                ),
              ),
              const SizedBox(height: 16),
              TextField(
                controller: _commandController,
                enabled: !_running,
                minLines: 3,
                maxLines: 8,
                keyboardType: TextInputType.multiline,
                autocorrect: false,
                enableSuggestions: false,
                decoration: InputDecoration(
                  labelText: context.l10n.batchCommandInput,
                  hintText: context.l10n.batchCommandHint,
                  alignLabelWithHint: true,
                  filled: true,
                ),
              ),
              const SizedBox(height: 10),
              Align(
                alignment: AlignmentDirectional.centerStart,
                child: FilledButton.tonalIcon(
                  onPressed: _running ? null : _pickSnippet,
                  icon: const Icon(Icons.data_object_rounded),
                  label: Text(context.l10n.batchCommandUseSnippet),
                ),
              ),
              const SizedBox(height: 20),
              Row(
                children: [
                  Expanded(
                    child: Text(
                      context.l10n.batchCommandChooseServers,
                      style: theme.textTheme.titleMedium?.copyWith(
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                  ),
                  TextButton(
                    onPressed: _running || servers.isEmpty
                        ? null
                        : () => setState(
                            () => _selectedIds.addAll(
                              servers.map((server) => server.id),
                            ),
                          ),
                    child: Text(context.l10n.batchCommandSelectAll),
                  ),
                  TextButton(
                    onPressed: _running || _selectedIds.isEmpty
                        ? null
                        : () => setState(_selectedIds.clear),
                    child: Text(context.l10n.batchCommandClearSelection),
                  ),
                ],
              ),
              const SizedBox(height: 6),
              if (servers.isEmpty)
                Padding(
                  padding: const EdgeInsets.symmetric(vertical: 20),
                  child: Text(libL10n.empty, textAlign: TextAlign.center),
                )
              else
                Wrap(
                  spacing: 8,
                  runSpacing: 8,
                  children: servers.map((server) {
                    final selected = _selectedIds.contains(server.id);
                    final connection = ref.watch(
                      serverProvider(server.id).select((state) => state.conn),
                    );
                    final connected =
                        connection.index >= ServerConn.connected.index;
                    return FilterChip(
                      selected: selected,
                      showCheckmark: true,
                      avatar: Icon(
                        connected
                            ? Icons.cloud_done_rounded
                            : Icons.cloud_off_rounded,
                        size: 18,
                        color: connected ? scheme.primary : scheme.outline,
                      ),
                      label: Text(server.name),
                      onSelected: _running
                          ? null
                          : (value) => setState(() {
                              if (value) {
                                _selectedIds.add(server.id);
                              } else {
                                _selectedIds.remove(server.id);
                              }
                            }),
                    );
                  }).toList(growable: false),
                ),
              const SizedBox(height: 18),
              FilledButton.icon(
                onPressed: _running ? null : _runSelected,
                icon: _running
                    ? const SizedBox.square(
                        dimension: 18,
                        child: CircularProgressIndicator(strokeWidth: 2),
                      )
                    : const Icon(Icons.play_arrow_rounded),
                label: Text(
                  _running
                      ? context.l10n.batchCommandRunning
                      : context.l10n.batchCommandRun,
                ),
              ),
              if (_results.isNotEmpty) ...[
                const SizedBox(height: 24),
                Text(
                  context.l10n.batchCommandResults,
                  style: theme.textTheme.titleMedium?.copyWith(
                    fontWeight: FontWeight.w700,
                  ),
                ),
                const SizedBox(height: 8),
                ...servers
                    .where((server) => _results.containsKey(server.id))
                    .map(
                      (server) => Padding(
                        padding: const EdgeInsets.only(bottom: 10),
                        child: _ResultCard(
                          server: server,
                          result: _results[server.id]!,
                        ),
                      ),
                    ),
              ],
            ],
          ),
        ),
      ),
    );
  }

  Future<void> _pickSnippet() async {
    final snippets = ref.read(snippetProvider).snippets;
    if (snippets.isEmpty) {
      context.showSnackBar(libL10n.empty);
      return;
    }
    final selected = await context.showPickSingleDialog<Snippet>(
      title: libL10n.snippet,
      items: snippets,
      display: (snippet) => snippet.name,
    );
    if (selected == null || !mounted) return;
    _commandController.text = selected.script;
  }

  Future<void> _runSelected() async {
    final command = _commandController.text.trim();
    if (command.isEmpty) {
      context.showSnackBar(context.l10n.batchCommandInputRequired);
      return;
    }
    if (_selectedIds.isEmpty) {
      context.showSnackBar(context.l10n.batchCommandServerRequired);
      return;
    }

    FocusManager.instance.primaryFocus?.unfocus();
    final ids = _selectedIds.toList(growable: false);
    setState(() {
      _running = true;
      _results
        ..clear()
        ..addEntries(
          ids.map(
            (id) => MapEntry(id, const _BatchCommandResult.pending()),
          ),
        );
    });

    await Future.wait(ids.map((id) => _runOne(id, command)));
    if (mounted) setState(() => _running = false);
  }

  Future<void> _runOne(String serverId, String command) async {
    final spi = ref.read(serversProvider).servers[serverId];
    if (spi == null) return;
    final stopwatch = Stopwatch()..start();

    _updateResult(
      serverId,
      const _BatchCommandResult(status: _BatchCommandStatus.connecting),
    );

    try {
      var serverState = ref.read(serverProvider(serverId));
      var client = serverState.client;
      if (client == null || client.isClosed) {
        TryLimiter.reset(serverId);
        await ref.read(serverProvider(serverId).notifier).refresh();
        serverState = ref.read(serverProvider(serverId));
        client = serverState.client;
      }
      if (client == null || client.isClosed) {
        throw StateError(context.l10n.batchCommandConnectionUnavailable);
      }

      _updateResult(
        serverId,
        const _BatchCommandResult(status: _BatchCommandStatus.running),
      );
      final formatted = Snippet(name: '', script: command).fmtWithSpi(spi);
      final (session, _) = await client.exec(
        (session) {
          session.stdin.add(Uint8List.fromList(utf8.encode('$formatted\n')));
          session.stdin.close();
        },
        systemType: serverState.status.system,
        stdout: false,
        stderr: false,
        onStdout: (data, _) => _appendOutput(serverId, data),
        onStderr: (data, _) => _appendOutput(serverId, data, isError: true),
      );
      stopwatch.stop();
      final current = _results[serverId] ?? const _BatchCommandResult.pending();
      _updateResult(
        serverId,
        current.copyWith(
          status: session.exitCode == 0
              ? _BatchCommandStatus.succeeded
              : _BatchCommandStatus.failed,
          exitCode: session.exitCode,
          elapsed: stopwatch.elapsed,
        ),
      );
    } catch (error) {
      stopwatch.stop();
      final current = _results[serverId] ?? const _BatchCommandResult.pending();
      _updateResult(
        serverId,
        current.copyWith(
          status: _BatchCommandStatus.failed,
          output: current.output.isEmpty
              ? error.toString()
              : '${current.output}\n${error.toString()}',
          elapsed: stopwatch.elapsed,
        ),
      );
    }
  }

  void _appendOutput(String serverId, String data, {bool isError = false}) {
    if (data.isEmpty || !mounted) return;
    final current = _results[serverId];
    if (current == null) return;
    var output = current.output + data;
    if (output.length > _maxVisibleOutput) {
      output = output.substring(output.length - _maxVisibleOutput);
    }
    _updateResult(
      serverId,
      current.copyWith(output: output, hasStderr: current.hasStderr || isError),
    );
  }

  void _updateResult(String id, _BatchCommandResult result) {
    if (!mounted) return;
    setState(() => _results[id] = result);
  }
}

enum _BatchCommandStatus { pending, connecting, running, succeeded, failed }

class _BatchCommandResult {
  const _BatchCommandResult({
    required this.status,
    this.output = '',
    this.exitCode,
    this.elapsed,
    this.hasStderr = false,
  });

  const _BatchCommandResult.pending()
    : status = _BatchCommandStatus.pending,
      output = '',
      exitCode = null,
      elapsed = null,
      hasStderr = false;

  final _BatchCommandStatus status;
  final String output;
  final int? exitCode;
  final Duration? elapsed;
  final bool hasStderr;

  _BatchCommandResult copyWith({
    _BatchCommandStatus? status,
    String? output,
    int? exitCode,
    Duration? elapsed,
    bool? hasStderr,
  }) {
    return _BatchCommandResult(
      status: status ?? this.status,
      output: output ?? this.output,
      exitCode: exitCode ?? this.exitCode,
      elapsed: elapsed ?? this.elapsed,
      hasStderr: hasStderr ?? this.hasStderr,
    );
  }
}

class _ResultCard extends StatelessWidget {
  const _ResultCard({required this.server, required this.result});

  final Spi server;
  final _BatchCommandResult result;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final (icon, color, label) = switch (result.status) {
      _BatchCommandStatus.pending => (
        Icons.schedule_rounded,
        scheme.outline,
        context.l10n.batchCommandPending,
      ),
      _BatchCommandStatus.connecting => (
        Icons.cloud_sync_rounded,
        scheme.tertiary,
        context.l10n.batchCommandConnecting,
      ),
      _BatchCommandStatus.running => (
        Icons.sync_rounded,
        scheme.primary,
        context.l10n.batchCommandRunning,
      ),
      _BatchCommandStatus.succeeded => (
        Icons.check_circle_rounded,
        Colors.green.shade600,
        context.l10n.batchCommandSuccess,
      ),
      _BatchCommandStatus.failed => (
        Icons.error_rounded,
        scheme.error,
        context.l10n.batchCommandFailed,
      ),
    };
    final finished = result.status == _BatchCommandStatus.succeeded ||
        result.status == _BatchCommandStatus.failed;
    final detailParts = <String>[
      label,
      if (result.exitCode != null)
        context.l10n.batchCommandExitCode(result.exitCode!),
      if (result.elapsed != null)
        '${(result.elapsed!.inMilliseconds / 1000).toStringAsFixed(1)}s',
    ];

    return Card(
      clipBehavior: Clip.antiAlias,
      child: Padding(
        padding: const EdgeInsets.all(14),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Row(
              children: [
                Icon(icon, color: color),
                const SizedBox(width: 10),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        server.name,
                        style: Theme.of(context).textTheme.titleSmall?.copyWith(
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                      Text(
                        detailParts.join(' · '),
                        style: Theme.of(context).textTheme.bodySmall?.copyWith(
                          color: color,
                        ),
                      ),
                    ],
                  ),
                ),
                if (!finished)
                  SizedBox.square(
                    dimension: 18,
                    child: CircularProgressIndicator(
                      strokeWidth: 2,
                      color: color,
                    ),
                  ),
              ],
            ),
            const SizedBox(height: 10),
            Container(
              constraints: const BoxConstraints(minHeight: 72, maxHeight: 260),
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: scheme.surfaceContainerHighest.withAlpha(150),
                borderRadius: BorderRadius.circular(14),
                border: Border.all(color: scheme.outlineVariant.withAlpha(80)),
              ),
              child: SingleChildScrollView(
                child: SelectionArea(
                  child: Text(
                    result.output.isEmpty
                        ? (finished
                              ? context.l10n.batchCommandNoOutput
                              : context.l10n.batchCommandWaitingOutput)
                        : result.output,
                    style: Theme.of(context).textTheme.bodySmall?.copyWith(
                      fontFamily: 'monospace',
                      color: result.output.isEmpty
                          ? scheme.onSurfaceVariant
                          : scheme.onSurface,
                    ),
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
