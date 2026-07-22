import 'package:fl_lib/fl_lib.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_markdown_plus/flutter_markdown_plus.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:server_box/core/extension/context/locale.dart';
import 'package:server_box/data/model/server/snippet.dart';
import 'package:server_box/data/provider/server/all.dart';
import 'package:server_box/data/provider/snippet.dart';

final class SnippetEditPageArgs {
  final Snippet? snippet;
  final bool duplicate;

  const SnippetEditPageArgs({this.snippet, this.duplicate = false});
}

class SnippetEditPage extends ConsumerStatefulWidget {
  final SnippetEditPageArgs? args;

  const SnippetEditPage({super.key, this.args});

  @override
  ConsumerState<SnippetEditPage> createState() => _SnippetEditPageState();

  static const route = AppRoute(
    page: SnippetEditPage.new,
    path: '/snippets/edit',
  );
}

class _SnippetEditPageState extends ConsumerState<SnippetEditPage>
    with AfterLayoutMixin {
  final _nameController = TextEditingController();
  final _scriptController = TextEditingController();
  final _noteController = TextEditingController();
  final _scriptNode = FocusNode();
  final _autoRunOn = ValueNotifier(<String>[]);
  final _tags = <String>{}.vn;

  String? _nameError;
  bool _allowPop = false;

  Snippet? get _original => widget.args?.duplicate == true
      ? null
      : widget.args?.snippet;

  bool get _isNew => _original == null;

  void _update(VoidCallback callback) => setState(callback);

  @override
  void dispose() {
    _nameController.dispose();
    _scriptController.dispose();
    _noteController.dispose();
    _scriptNode.dispose();
    _autoRunOn.dispose();
    _tags.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final title = _isNew
        ? '${libL10n.add} ${libL10n.snippet}'
        : '${libL10n.edit} ${libL10n.snippet}';
    return PopScope(
      canPop: _allowPop,
      onPopInvokedWithResult: (didPop, _) {
        if (!didPop) _requestPop();
      },
      child: Scaffold(
        appBar: AppBar(
          backgroundColor: Colors.transparent,
          scrolledUnderElevation: 0,
          leading: IconButton(
            tooltip: MaterialLocalizations.of(context).backButtonTooltip,
            onPressed: _requestPop,
            icon: const Icon(Icons.arrow_back_rounded),
          ),
          title: Text(
            title,
            style: const TextStyle(fontWeight: FontWeight.w800),
          ),
          actions: _buildAppBarActions(),
        ),
        body: _buildBody(),
        floatingActionButton: FloatingActionButton.extended(
          heroTag: 'snippetSave',
          onPressed: _save,
          icon: const Icon(Icons.save_rounded),
          label: Text(libL10n.save),
        ),
      ),
    );
  }

  @override
  void afterFirstLayout(BuildContext context) {
    final snippet = widget.args?.snippet;
    if (snippet == null) return;
    _nameController.text = snippet.name;
    _scriptController.text = snippet.script;
    _noteController.text = snippet.note ?? '';
    _tags.value = snippet.tags?.toSet() ?? {};
    _autoRunOn.value = snippet.autoRunOn?.toList() ?? [];
    if (widget.args?.duplicate == true) {
      _nameController.selection = TextSelection(
        baseOffset: 0,
        extentOffset: _nameController.text.length,
      );
    }
  }
}

extension _SnippetEditView on _SnippetEditPageState {
  List<Widget>? _buildAppBarActions() {
    final snippet = _original;
    if (snippet == null) return null;
    return [
      IconButton.filledTonal(
        tooltip: libL10n.delete,
        onPressed: () => _delete(snippet),
        icon: const Icon(Icons.delete_rounded),
      ),
      const SizedBox(width: 8),
    ];
  }

  Widget _buildBody() {
    return Align(
      alignment: Alignment.topCenter,
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 920),
        child: ListView(
          keyboardDismissBehavior: ScrollViewKeyboardDismissBehavior.onDrag,
          padding: const EdgeInsets.fromLTRB(16, 8, 16, 112),
          children: [
            _buildIdentityCard(),
            const SizedBox(height: 14),
            _buildScriptCard(),
            const SizedBox(height: 14),
            _buildAutoRunCard(),
            const SizedBox(height: 14),
            _buildReferenceCard(),
          ],
        ),
      ),
    );
  }

  Widget _buildIdentityCard() {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    return _sectionCard(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(18, 18, 18, 10),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            _SectionTitle(
              icon: Icons.badge_rounded,
              title: libL10n.name,
              color: scheme.primaryContainer,
              foregroundColor: scheme.onPrimaryContainer,
            ),
            const SizedBox(height: 16),
            TextField(
              controller: _nameController,
              autofocus: true,
              textInputAction: TextInputAction.next,
              onChanged: (_) {
                if (_nameError != null) _update(() => _nameError = null);
              },
              onSubmitted: (_) => _scriptNode.requestFocus(),
              decoration: _inputDecoration(
                label: libL10n.name,
                icon: Icons.title_rounded,
                errorText: _nameError,
              ),
            ),
            const SizedBox(height: 12),
            TextField(
              controller: _noteController,
              minLines: 2,
              maxLines: 4,
              textCapitalization: TextCapitalization.sentences,
              decoration: _inputDecoration(
                label: libL10n.note,
                icon: Icons.notes_rounded,
              ),
            ),
            const SizedBox(height: 6),
            Consumer(
              builder: (_, ref, _) {
                final allTags = ref.watch(
                  snippetProvider.select((state) => state.tags),
                );
                return TagTile(tags: _tags, allTags: allTags);
              },
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildScriptCard() {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final tokens = [
      ...SnippetX.fmtArgs.keys,
      r'${enter}',
      r'${sleep 1}',
      r'${ctrl+c}',
    ];
    return _sectionCard(
      child: Padding(
        padding: const EdgeInsets.all(18),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            _SectionTitle(
              icon: Icons.terminal_rounded,
              title: libL10n.snippet,
              color: scheme.tertiaryContainer,
              foregroundColor: scheme.onTertiaryContainer,
            ),
            const SizedBox(height: 16),
            TextField(
              controller: _scriptController,
              focusNode: _scriptNode,
              minLines: 7,
              maxLines: 16,
              keyboardType: TextInputType.multiline,
              autocorrect: false,
              enableSuggestions: false,
              style: const TextStyle(fontFamily: 'monospace', height: 1.45),
              decoration: _inputDecoration(
                label: libL10n.snippet,
                icon: Icons.code_rounded,
                alignLabelWithHint: true,
              ),
            ),
            const SizedBox(height: 16),
            Text(
              context.l10n.snippetInsertVariable,
              style: theme.textTheme.labelLarge?.copyWith(
                color: scheme.onSurfaceVariant,
              ),
            ),
            const SizedBox(height: 8),
            Wrap(
              spacing: 7,
              runSpacing: 7,
              children: tokens
                  .map(
                    (token) => ActionChip(
                      avatar: const Icon(Icons.add_rounded, size: 17),
                      label: Text(
                        token,
                        style: const TextStyle(fontFamily: 'monospace'),
                      ),
                      onPressed: () => _insertToken(token),
                    ),
                  )
                  .toList(growable: false),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildAutoRunCard() {
    final scheme = Theme.of(context).colorScheme;
    return _sectionCard(
      child: ValBuilder(
        listenable: _autoRunOn,
        builder: (serverIds) {
          final servers = ref.read(serversProvider);
          final names = serverIds
              .map((id) => servers.servers[id]?.name ?? id)
              .join(', ');
          return ListTile(
            contentPadding: const EdgeInsets.symmetric(
              horizontal: 18,
              vertical: 8,
            ),
            leading: Container(
              width: 46,
              height: 46,
              decoration: ShapeDecoration(
                color: scheme.secondaryContainer,
                shape: const RoundedSuperellipseBorder(
                  borderRadius: BorderRadius.all(Radius.circular(16)),
                ),
              ),
              child: Icon(
                Icons.bolt_rounded,
                color: scheme.onSecondaryContainer,
              ),
            ),
            title: Text(
              l10n.autoRun,
              style: const TextStyle(fontWeight: FontWeight.w700),
            ),
            subtitle: Text(
              serverIds.isEmpty
                  ? context.l10n.snippetAutoRunDescription
                  : names,
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
            ),
            trailing: Badge(
              isLabelVisible: serverIds.isNotEmpty,
              label: Text('${serverIds.length}'),
              child: const Icon(Icons.chevron_right_rounded),
            ),
            onTap: _pickAutoRunServers,
          );
        },
      ),
    );
  }

  Widget _buildReferenceCard() {
    final scheme = Theme.of(context).colorScheme;
    return _sectionCard(
      child: ExpansionTile(
        leading: Container(
          width: 42,
          height: 42,
          decoration: ShapeDecoration(
            color: scheme.surfaceContainerHighest,
            shape: const RoundedSuperellipseBorder(
              borderRadius: BorderRadius.all(Radius.circular(15)),
            ),
          ),
          child: const Icon(Icons.menu_book_rounded, size: 21),
        ),
        title: Text(
          l10n.supportFmtArgs,
          style: const TextStyle(fontWeight: FontWeight.w700),
        ),
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(18, 0, 18, 18),
            child: SimpleMarkdown(
              data:
                  '''
${SnippetX.fmtArgs.keys.map((key) => '`$key`').join(', ')}

${SnippetX.fmtTermKeys.keys.map((key) => '`$key+?}`').join(', ')}

${libL10n.example}:
- `\${ctrl+c}` (Control + C)
- `\${ctrl+b}d` (Tmux Detach)
- `\${sleep 1}`
- `\${enter 2}`
''',
              styleSheet: MarkdownStyleSheet(
                codeblockDecoration: const BoxDecoration(
                  color: Colors.transparent,
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _sectionCard({required Widget child}) {
    return Card.filled(
      margin: EdgeInsets.zero,
      color: Theme.of(context).colorScheme.surfaceContainerLow,
      shape: const RoundedSuperellipseBorder(
        borderRadius: BorderRadius.all(Radius.circular(28)),
      ),
      clipBehavior: Clip.antiAlias,
      child: child,
    );
  }

  InputDecoration _inputDecoration({
    required String label,
    required IconData icon,
    String? errorText,
    bool alignLabelWithHint = false,
  }) {
    final scheme = Theme.of(context).colorScheme;
    const border = OutlineInputBorder(
      borderRadius: BorderRadius.all(Radius.circular(18)),
      borderSide: BorderSide.none,
    );
    return InputDecoration(
      labelText: label,
      prefixIcon: Icon(icon),
      errorText: errorText,
      alignLabelWithHint: alignLabelWithHint,
      filled: true,
      fillColor: scheme.surfaceContainerHighest.withAlpha(150),
      border: border,
      enabledBorder: border,
      focusedBorder: border.copyWith(
        borderSide: BorderSide(color: scheme.primary, width: 2),
      ),
      errorBorder: border.copyWith(
        borderSide: BorderSide(color: scheme.error, width: 1.5),
      ),
      focusedErrorBorder: border.copyWith(
        borderSide: BorderSide(color: scheme.error, width: 2),
      ),
    );
  }
}

extension _SnippetEditActions on _SnippetEditPageState {
  Future<void> _requestPop() async {
    if (_allowPop) return;
    if (!_hasUnsavedChanges()) {
      _exit();
      return;
    }
    final discard = await context.showRoundDialog<bool>(
      title: context.l10n.snippetUnsavedTitle,
      child: Text(context.l10n.snippetUnsavedDescription),
      actions: [
        TextButton(
          onPressed: () => context.pop(false),
          child: Text(libL10n.cancel),
        ),
        FilledButton(
          onPressed: () => context.pop(true),
          child: Text(context.l10n.snippetDiscard),
        ),
      ],
    );
    if (discard == true) _exit();
  }

  bool _hasUnsavedChanges() {
    final seed = widget.args?.snippet;
    if (seed == null) {
      return _nameController.text.isNotEmpty ||
          _scriptController.text.isNotEmpty ||
          _noteController.text.isNotEmpty ||
          _tags.value.isNotEmpty ||
          _autoRunOn.value.isNotEmpty;
    }
    if (widget.args?.duplicate == true) return true;
    return _nameController.text != seed.name ||
        _scriptController.text != seed.script ||
        _noteController.text != (seed.note ?? '') ||
        !setEquals(_tags.value, seed.tags?.toSet() ?? <String>{}) ||
        !listEquals(_autoRunOn.value, seed.autoRunOn ?? const <String>[]);
  }

  void _exit() {
    if (!mounted) return;
    _update(() => _allowPop = true);
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) context.pop();
    });
  }

  Future<void> _save() async {
    final name = _nameController.text.trim();
    final script = _scriptController.text;
    if (name.isEmpty || script.trim().isEmpty) {
      _update(() => _nameError = name.isEmpty ? libL10n.empty : null);
      context.showSnackBar(libL10n.empty);
      return;
    }
    final hasConflict = ref.read(snippetProvider).snippets.any(
      (snippet) => snippet.name == name && snippet.name != _original?.name,
    );
    if (hasConflict) {
      _update(() => _nameError = context.l10n.snippetNameExists);
      return;
    }

    final note = _noteController.text.trim();
    final snippet = Snippet(
      name: name,
      script: script,
      tags: _tags.value.isEmpty ? null : _tags.value.toList(),
      note: note.isEmpty ? null : note,
      autoRunOn: _autoRunOn.value.isEmpty ? null : _autoRunOn.value,
    );
    final notifier = ref.read(snippetProvider.notifier);
    if (_original == null) {
      notifier.add(snippet);
    } else {
      notifier.update(_original!, snippet);
    }
    _exit();
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
    if (confirmed != true) return;
    ref.read(snippetProvider.notifier).del(snippet);
    _exit();
  }

  Future<void> _pickAutoRunServers() async {
    final servers = ref.read(serversProvider);
    final validIds = _autoRunOn.value
        .where(servers.serverOrder.contains)
        .toList(growable: false);
    final selected = await context.showPickDialog<String>(
      title: l10n.autoRun,
      items: servers.serverOrder,
      display: (id) => servers.servers[id]?.name ?? id,
      initial: validIds,
      clearable: true,
    );
    if (selected != null) _autoRunOn.value = selected;
  }

  void _insertToken(String token) {
    final value = _scriptController.value;
    final selection = value.selection;
    final start = selection.isValid ? selection.start : value.text.length;
    final end = selection.isValid ? selection.end : value.text.length;
    final text = value.text.replaceRange(start, end, token);
    _scriptController.value = value.copyWith(
      text: text,
      selection: TextSelection.collapsed(offset: start + token.length),
      composing: TextRange.empty,
    );
    _scriptNode.requestFocus();
  }
}

final class _SectionTitle extends StatelessWidget {
  const _SectionTitle({
    required this.icon,
    required this.title,
    required this.color,
    required this.foregroundColor,
  });

  final IconData icon;
  final String title;
  final Color color;
  final Color foregroundColor;

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Container(
          width: 42,
          height: 42,
          decoration: ShapeDecoration(
            color: color,
            shape: const RoundedSuperellipseBorder(
              borderRadius: BorderRadius.all(Radius.circular(15)),
            ),
          ),
          child: Icon(icon, color: foregroundColor, size: 21),
        ),
        const SizedBox(width: 12),
        Text(
          title,
          style: Theme.of(context).textTheme.titleLarge?.copyWith(
            fontWeight: FontWeight.w700,
          ),
        ),
      ],
    );
  }
}
