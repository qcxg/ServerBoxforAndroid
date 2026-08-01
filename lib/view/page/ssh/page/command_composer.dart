part of 'page.dart';

enum _CommandSendMode { allAtOnce, lineByLine }

final class _SshKeyboardToolbar extends StatelessWidget {
  const _SshKeyboardToolbar({
    required this.panelBuilder,
    required this.viewInsetsListenable,
    this.applyBottomInset = true,
  });

  final WidgetBuilder panelBuilder;
  final ValueListenable<double> viewInsetsListenable;
  final bool applyBottomInset;

  @override
  Widget build(BuildContext context) {
    // Keep IME metric rebuilds inside this small subtree. The terminal view is
    // intentionally kept out of this dependency so keyboard animations do not
    // rebuild the whole SSH page on every metric tick.
    return ValueListenableBuilder<double>(
      valueListenable: viewInsetsListenable,
      builder: (context, viewInsetsBottom, _) {
        final keyboardVisible = viewInsetsBottom > 0;
        final child = keyboardVisible
            ? KeyedSubtree(
                key: const ValueKey('ssh-keyboard-toolbar-visible'),
                child: panelBuilder(context),
              )
            : const SizedBox(key: ValueKey('ssh-keyboard-toolbar-hidden'));

        return Padding(
          // Scaffold keeps bottomNavigationBar at the physical bottom while
          // the IME is visible. Move this small subtree above the IME without
          // making the terminal depend on the keyboard metrics.
          padding: EdgeInsets.only(
            bottom: applyBottomInset ? viewInsetsBottom : 0,
          ),
          child: AnimatedSize(
            duration: const Duration(milliseconds: 280),
            reverseDuration: const Duration(milliseconds: 180),
            curve: Curves.easeOutCubic,
            alignment: Alignment.bottomCenter,
            child: AnimatedSwitcher(
              duration: const Duration(milliseconds: 280),
              reverseDuration: const Duration(milliseconds: 180),
              switchInCurve: Curves.easeOutCubic,
              switchOutCurve: Curves.easeInCubic,
              layoutBuilder: (currentChild, previousChildren) {
                return Stack(
                  alignment: Alignment.bottomCenter,
                  children: <Widget>[...previousChildren, ?currentChild],
                );
              },
              transitionBuilder: (child, animation) {
                final curvedAnimation = CurvedAnimation(
                  parent: animation,
                  curve: Curves.easeOutCubic,
                  reverseCurve: Curves.easeInCubic,
                );
                final slideAnimation = Tween<Offset>(
                  begin: const Offset(0, 0.12),
                  end: Offset.zero,
                ).animate(curvedAnimation);
                return ClipRect(
                  child: FadeTransition(
                    opacity: curvedAnimation,
                    child: SlideTransition(
                      position: slideAnimation,
                      child: child,
                    ),
                  ),
                );
              },
              child: child,
            ),
          ),
        );
      },
    );
  }
}

extension _CommandComposer on SSHPageState {
  Widget _buildMobileInputPanel() {
    return ValueListenableBuilder<bool>(
      valueListenable: _isCommandComposerOpen,
      builder: (context, isOpen, child) {
        final scheme = Theme.of(context).colorScheme;
        return SafeArea(
          top: false,
          minimum: const EdgeInsets.only(bottom: 2),
          child: Padding(
            padding: const EdgeInsets.fromLTRB(8, 4, 8, 4),
            child: GlassSurface(
              shape: const RoundedSuperellipseBorder(
                borderRadius: BorderRadius.all(Radius.circular(24)),
              ),
              blur: 20,
              surfaceAlpha: 218,
              borderAlpha: 48,
              shadow: false,
              child: Material(
                type: MaterialType.transparency,
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    if (!_horizonVirtKeys || isOpen)
                      _buildCommandModeBar(scheme, isOpen),
                    AnimatedSize(
                      duration: const Duration(milliseconds: 220),
                      curve: Curves.easeOutCubic,
                      alignment: Alignment.bottomCenter,
                      child: isOpen
                          ? _buildCommandComposer(scheme)
                          : _buildVirtualKeyboardPanel(),
                    ),
                  ],
                ),
              ),
            ),
          ),
        );
      },
    );
  }

  Widget _buildCommandModeBar(
    ColorScheme scheme,
    bool isOpen, {
    bool inline = false,
  }) {
    return ValueListenableBuilder<TextEditingValue>(
      valueListenable: _commandBufferController,
      builder: (context, value, child) {
        final bufferedLines = splitCommandBufferLines(value.text).length;
        final label = isOpen ? l10n.sshDirectInput : l10n.sshCommandBuffer;
        final icon = isOpen
            ? Icons.keyboard_alt_outlined
            : Icons.edit_note_rounded;
        final modeBar = Material(
          color: scheme.surfaceContainerHighest.withValues(alpha: 0.72),
          shape: const StadiumBorder(),
          clipBehavior: Clip.antiAlias,
          child: InkWell(
            customBorder: const StadiumBorder(),
            onTap: _toggleCommandComposer,
            child: SizedBox(
              height: inline ? _sshToolbarKeyHeight : 40,
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: 8),
                child: Row(
                  children: [
                    AnimatedSwitcher(
                      duration: Durations.short4,
                      transitionBuilder: (child, animation) {
                        return FadeTransition(
                          opacity: animation,
                          child: ScaleTransition(
                            scale: animation,
                            child: child,
                          ),
                        );
                      },
                      child: DecoratedBox(
                        key: ValueKey(isOpen),
                        decoration: ShapeDecoration(
                          color: scheme.primaryContainer,
                          shape: const CircleBorder(),
                        ),
                        child: SizedBox.square(
                          dimension: 28,
                          child: Icon(
                            icon,
                            size: 17,
                            color: scheme.onPrimaryContainer,
                          ),
                        ),
                      ),
                    ),
                    const SizedBox(width: 8),
                    Expanded(
                      child: AnimatedSwitcher(
                        duration: Durations.short4,
                        layoutBuilder: (currentChild, previousChildren) {
                          return Stack(
                            alignment: Alignment.centerLeft,
                            children: <Widget>[
                              ...previousChildren,
                              ?currentChild,
                            ],
                          );
                        },
                        transitionBuilder: (child, animation) {
                          return FadeTransition(
                            opacity: animation,
                            child: child,
                          );
                        },
                        child: Text(
                          label,
                          key: ValueKey(label),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: Theme.of(context).textTheme.labelLarge
                              ?.copyWith(fontWeight: FontWeight.w700),
                        ),
                      ),
                    ),
                    if (!isOpen && bufferedLines > 0) ...[
                      const SizedBox(width: 6),
                      Container(
                        constraints: const BoxConstraints(minWidth: 24),
                        padding: const EdgeInsets.symmetric(
                          horizontal: 7,
                          vertical: 4,
                        ),
                        decoration: ShapeDecoration(
                          color: scheme.secondaryContainer,
                          shape: const StadiumBorder(),
                        ),
                        child: Text(
                          '$bufferedLines',
                          textAlign: TextAlign.center,
                          style: TextStyle(
                            color: scheme.onSecondaryContainer,
                            fontSize: 11,
                            fontWeight: FontWeight.w800,
                          ),
                        ),
                      ),
                    ],
                    const SizedBox(width: 4),
                    Icon(
                      isOpen
                          ? Icons.keyboard_arrow_up_rounded
                          : Icons.edit_rounded,
                      size: 19,
                      color: scheme.onSurfaceVariant,
                    ),
                  ],
                ),
              ),
            ),
          ),
        );

        if (inline) return modeBar;
        return Padding(
          padding: const EdgeInsets.fromLTRB(8, 6, 8, 6),
          child: Align(
            alignment: Alignment.centerLeft,
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 300),
              child: modeBar,
            ),
          ),
        );
      },
    );
  }

  Widget _buildVirtualKeyboardPanel() {
    if (_virtKeysHeight == 0) return const SizedBox.shrink();
    return SizedBox(
      height: _virtKeysHeight,
      child: Padding(
        padding: const EdgeInsets.fromLTRB(
          8,
          _sshToolbarKeyInset,
          8,
          _sshToolbarKeyInset,
        ),
        child: Consumer(
          builder: (context, ref, child) {
            final virtKeyState = ref.watch(virtKeyboardProvider);
            final virtKeyNotifier = ref.read(virtKeyboardProvider.notifier);
            _terminal.inputHandler = virtKeyNotifier;
            return _buildVirtualKey(virtKeyState, virtKeyNotifier);
          },
        ),
      ),
    );
  }

  Widget _buildCommandComposer(ColorScheme scheme) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(10, 0, 10, 10),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          TextField(
            controller: _commandBufferController,
            focusNode: _commandBufferFocusNode,
            minLines: 1,
            maxLines: 4,
            autocorrect: false,
            enableSuggestions: false,
            keyboardType: TextInputType.multiline,
            textInputAction: TextInputAction.newline,
            style: Theme.of(context).textTheme.bodyMedium?.copyWith(
              color: scheme.onSurface,
              fontFamily: 'monospace',
            ),
            decoration: InputDecoration(
              isDense: true,
              filled: true,
              fillColor: scheme.surfaceContainerHighest.withValues(alpha: 0.72),
              contentPadding: const EdgeInsets.symmetric(
                horizontal: 12,
                vertical: 10,
              ),
              prefixIcon: Icon(
                Icons.terminal_rounded,
                color: scheme.primary,
                size: 20,
              ),
              labelText: l10n.sshCommandBuffer,
              hintText: l10n.sshCommandBufferHint,
              labelStyle: TextStyle(color: scheme.onSurfaceVariant),
              hintStyle: TextStyle(
                color: scheme.onSurfaceVariant.withValues(alpha: 0.74),
              ),
              enabledBorder: OutlineInputBorder(
                borderRadius: const BorderRadius.all(Radius.circular(16)),
                borderSide: BorderSide(
                  color: scheme.outlineVariant.withValues(alpha: 0.64),
                ),
              ),
              focusedBorder: OutlineInputBorder(
                borderRadius: const BorderRadius.all(Radius.circular(16)),
                borderSide: BorderSide(color: scheme.primary, width: 1.4),
              ),
            ),
          ),
          const SizedBox(height: 8),
          ListenableBuilder(
            listenable: Listenable.merge([
              _commandBufferController,
              _commandSendMode,
              _isSendingCommandBuffer,
            ]),
            builder: (context, child) {
              final hasText = _commandBufferController.text.trim().isNotEmpty;
              final sendMode = _commandSendMode.value;
              final isSending = _isSendingCommandBuffer.value;
              return Row(
                children: [
                  Expanded(
                    child: _buildCommandSendModeButton(
                      scheme,
                      sendMode,
                      isSending,
                    ),
                  ),
                  const SizedBox(width: 6),
                  IconButton.filledTonal(
                    onPressed: hasText && !isSending
                        ? _commandBufferController.clear
                        : null,
                    tooltip: libL10n.clear,
                    icon: const Icon(Icons.clear_rounded),
                    style: IconButton.styleFrom(
                      minimumSize: const Size.square(40),
                      maximumSize: const Size.square(40),
                      padding: EdgeInsets.zero,
                    ),
                  ),
                  const SizedBox(width: 6),
                  IconButton.filled(
                    onPressed: hasText && !isSending
                        ? _sendCommandBuffer
                        : null,
                    tooltip: l10n.sshSend,
                    icon: isSending
                        ? const SizedBox.square(
                            dimension: 17,
                            child: CircularProgressIndicator(strokeWidth: 2),
                          )
                        : const Icon(Icons.send_rounded),
                    style: IconButton.styleFrom(
                      minimumSize: const Size.square(40),
                      maximumSize: const Size.square(40),
                      padding: EdgeInsets.zero,
                    ),
                  ),
                ],
              );
            },
          ),
        ],
      ),
    );
  }

  Widget _buildCommandSendModeButton(
    ColorScheme scheme,
    _CommandSendMode sendMode,
    bool isSending,
  ) {
    return SegmentedButton<_CommandSendMode>(
      showSelectedIcon: false,
      segments: [
        ButtonSegment(
          value: _CommandSendMode.allAtOnce,
          icon: const Icon(Icons.all_inclusive_rounded, size: 17),
          label: Text(
            l10n.sshSendAllAtOnce,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
          ),
        ),
        ButtonSegment(
          value: _CommandSendMode.lineByLine,
          icon: const Icon(Icons.format_list_numbered_rounded, size: 17),
          label: Text(
            l10n.sshSendLineByLine,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
          ),
        ),
      ],
      selected: {sendMode},
      onSelectionChanged: isSending
          ? null
          : (selection) {
              if (selection.isNotEmpty) {
                _commandSendMode.value = selection.first;
              }
            },
      style: ButtonStyle(
        visualDensity: VisualDensity.compact,
        tapTargetSize: MaterialTapTargetSize.shrinkWrap,
        minimumSize: const WidgetStatePropertyAll(Size(0, 40)),
        padding: const WidgetStatePropertyAll(
          EdgeInsets.symmetric(horizontal: 8),
        ),
        textStyle: WidgetStatePropertyAll(
          Theme.of(
            context,
          ).textTheme.labelMedium?.copyWith(fontWeight: FontWeight.w700),
        ),
        backgroundColor: WidgetStateProperty.resolveWith(
          (states) => states.contains(WidgetState.selected)
              ? scheme.secondaryContainer
              : scheme.surfaceContainerHighest.withValues(alpha: 0.72),
        ),
        foregroundColor: WidgetStateProperty.resolveWith(
          (states) => states.contains(WidgetState.selected)
              ? scheme.onSecondaryContainer
              : scheme.onSurfaceVariant,
        ),
        side: WidgetStatePropertyAll(
          BorderSide(color: scheme.outlineVariant.withValues(alpha: 0.64)),
        ),
        shape: const WidgetStatePropertyAll(
          RoundedSuperellipseBorder(
            borderRadius: BorderRadius.all(Radius.circular(16)),
          ),
        ),
      ),
    );
  }

  void _toggleCommandComposer() {
    final opening = !_isCommandComposerOpen.value;
    if (opening) {
      _isCommandComposerOpen.value = true;
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted && _isCommandComposerOpen.value) {
          _commandBufferFocusNode.requestFocus();
        }
      });
      return;
    }

    widget.args.focusNode?.requestFocus();
    _termKey.currentState?.requestKeyboard();
    _isCommandComposerOpen.value = false;
  }

  Future<void> _sendCommandBuffer() async {
    if (_isSendingCommandBuffer.value) return;
    final source = normalizeCommandBufferText(_commandBufferController.text);
    if (source.trim().isEmpty) return;
    if (_session == null || _client == null || _client!.isClosed) {
      context.showSnackBar(libL10n.disconnected);
      return;
    }

    _isSendingCommandBuffer.value = true;
    var sentEntireBuffer = false;
    try {
      switch (_commandSendMode.value) {
        case _CommandSendMode.allAtOnce:
          final payload = buildCommandBufferSendAllPayload(source);
          _session!.write(utf8.encode(payload));
          sentEntireBuffer = true;
          break;
        case _CommandSendMode.lineByLine:
          final payloads = buildCommandBufferLinePayloads(source);
          sentEntireBuffer = true;
          for (final payload in payloads) {
            final session = _session;
            if (!mounted ||
                session == null ||
                _client == null ||
                _client!.isClosed) {
              sentEntireBuffer = false;
              break;
            }
            session.write(utf8.encode(payload));
            await Future.delayed(const Duration(milliseconds: 300));
          }
          break;
      }
      if (sentEntireBuffer) {
        _commandBufferController.clear();
      } else if (mounted) {
        context.showSnackBar(libL10n.disconnected);
      }
    } catch (error, stackTrace) {
      Loggers.app.warning(
        'Failed to send SSH command buffer',
        error,
        stackTrace,
      );
      if (mounted) context.showSnackBar(error.toString());
    } finally {
      if (mounted) {
        _isSendingCommandBuffer.value = false;
        if (_isCommandComposerOpen.value) {
          _commandBufferFocusNode.requestFocus();
        }
      }
    }
  }
}
