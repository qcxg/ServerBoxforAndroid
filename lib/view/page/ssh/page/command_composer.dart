part of 'page.dart';

enum _CommandSendMode { allAtOnce, lineByLine }

extension _CommandComposer on SSHPageState {
  Widget _buildMobileInputPanel() {
    final foreground = _isDark ? Colors.white : Colors.black;
    return ValueListenableBuilder<bool>(
      valueListenable: _isCommandComposerOpen,
      builder: (context, isOpen, child) {
        return SafeArea(
          top: false,
          child: AnimatedPadding(
            padding: _media.viewInsets,
            duration: const Duration(milliseconds: 23),
            curve: Curves.fastOutSlowIn,
            child: Material(
              color: _terminalTheme.background,
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Divider(
                    height: 1,
                    color: foreground.withValues(alpha: 0.18),
                  ),
                  _buildCommandModeBar(foreground, isOpen),
                  AnimatedSize(
                    duration: const Duration(milliseconds: 180),
                    curve: Curves.easeOutCubic,
                    alignment: Alignment.bottomCenter,
                    child: isOpen
                        ? _buildCommandComposer(foreground)
                        : _buildVirtualKeyboardPanel(),
                  ),
                ],
              ),
            ),
          ),
        );
      },
    );
  }

  Widget _buildCommandModeBar(Color foreground, bool isOpen) {
    return ValueListenableBuilder<TextEditingValue>(
      valueListenable: _commandBufferController,
      builder: (context, value, child) {
        final bufferedLines = splitCommandBufferLines(value.text).length;
        return Material(
          color: foreground.withValues(alpha: 0.035),
          child: InkWell(
            onTap: _toggleCommandComposer,
            child: SizedBox(
              height: 46,
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: 12),
                child: Row(
                  children: [
                    Container(
                      width: 30,
                      height: 30,
                      decoration: BoxDecoration(
                        color: foreground.withValues(alpha: 0.09),
                        borderRadius: BorderRadius.circular(9),
                      ),
                      child: Icon(
                        isOpen
                            ? Icons.keyboard_alt_outlined
                            : Icons.edit_note_rounded,
                        size: 18,
                        color: foreground,
                      ),
                    ),
                    const SizedBox(width: 9),
                    Text(
                      isOpen
                          ? l10n.sshDirectInput
                          : l10n.sshCommandBuffer,
                      style: TextStyle(
                        color: foreground,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                    const Spacer(),
                    if (bufferedLines > 0)
                      Container(
                        margin: const EdgeInsets.only(right: 8),
                        padding: const EdgeInsets.symmetric(
                          horizontal: 8,
                          vertical: 3,
                        ),
                        decoration: BoxDecoration(
                          color: foreground.withValues(alpha: 0.1),
                          borderRadius: BorderRadius.circular(99),
                        ),
                        child: Text(
                          '$bufferedLines',
                          style: TextStyle(
                            color: foreground.withValues(alpha: 0.78),
                            fontSize: 11,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                      ),
                    Icon(
                      isOpen
                          ? Icons.expand_more
                          : Icons.expand_less,
                      color: foreground.withValues(alpha: 0.66),
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

  Widget _buildVirtualKeyboardPanel() {
    if (_virtKeysHeight == 0) return const SizedBox.shrink();
    return SizedBox(
      height: _virtKeysHeight,
      child: Consumer(
        builder: (context, ref, child) {
          final virtKeyState = ref.watch(virtKeyboardProvider);
          final virtKeyNotifier = ref.read(virtKeyboardProvider.notifier);
          _terminal.inputHandler = virtKeyNotifier;
          return _buildVirtualKey(virtKeyState, virtKeyNotifier);
        },
      ),
    );
  }

  Widget _buildCommandComposer(Color foreground) {
    return DecoratedBox(
      decoration: BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
          colors: [
            foreground.withValues(alpha: 0.055),
            foreground.withValues(alpha: 0.015),
          ],
        ),
      ),
      child: Padding(
        padding: const EdgeInsets.fromLTRB(10, 8, 10, 10),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            TextField(
            controller: _commandBufferController,
            focusNode: _commandBufferFocusNode,
            minLines: 2,
            maxLines: 5,
            autocorrect: false,
            enableSuggestions: false,
            keyboardType: TextInputType.multiline,
            textInputAction: TextInputAction.newline,
            style: TextStyle(color: foreground, fontFamily: 'monospace'),
            decoration: InputDecoration(
              isDense: true,
              filled: true,
              fillColor: foreground.withValues(alpha: 0.07),
              prefixIcon: Icon(
                Icons.terminal_rounded,
                color: foreground.withValues(alpha: 0.58),
              ),
              labelText: l10n.sshCommandBuffer,
              hintText: l10n.sshCommandBufferHint,
              labelStyle: TextStyle(
                color: foreground.withValues(alpha: 0.72),
              ),
              hintStyle: TextStyle(
                color: foreground.withValues(alpha: 0.48),
              ),
              enabledBorder: OutlineInputBorder(
                borderRadius: BorderRadius.circular(14),
                borderSide: BorderSide(
                  color: foreground.withValues(alpha: 0.16),
                ),
              ),
              focusedBorder: OutlineInputBorder(
                borderRadius: BorderRadius.circular(14),
                borderSide: BorderSide(
                  color: foreground.withValues(alpha: 0.52),
                  width: 1.4,
                ),
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
              return Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  SizedBox(
                    width: double.infinity,
                    child: SegmentedButton<_CommandSendMode>(
                      showSelectedIcon: false,
                      segments: [
                        ButtonSegment(
                          value: _CommandSendMode.allAtOnce,
                          icon: const Icon(Icons.all_inclusive, size: 17),
                          label: Text(l10n.sshSendAllAtOnce),
                        ),
                        ButtonSegment(
                          value: _CommandSendMode.lineByLine,
                          icon: const Icon(Icons.format_list_numbered, size: 17),
                          label: Text(l10n.sshSendLineByLine),
                        ),
                      ],
                      selected: {sendMode},
                      style: ButtonStyle(
                        visualDensity: VisualDensity.compact,
                        shape: WidgetStatePropertyAll(
                          RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(12),
                          ),
                        ),
                      ),
                      onSelectionChanged: isSending
                          ? null
                          : (selection) =>
                                _commandSendMode.value = selection.first,
                    ),
                  ),
                  const SizedBox(height: 5),
                  Align(
                    alignment: Alignment.centerLeft,
                    child: Text(
                      sendMode == _CommandSendMode.allAtOnce
                          ? l10n.sshSendAllHelp
                          : l10n.sshSendLineByLineHelp,
                      style: TextStyle(
                        color: foreground.withValues(alpha: 0.58),
                        fontSize: 11,
                        height: 1.25,
                      ),
                    ),
                  ),
                  const SizedBox(height: 3),
                  Row(
                    mainAxisAlignment: MainAxisAlignment.end,
                    children: [
                      IconButton(
                        onPressed: hasText && !isSending
                            ? _commandBufferController.clear
                            : null,
                        tooltip: libL10n.clear,
                        icon: const Icon(Icons.clear),
                      ),
                      const SizedBox(width: 4),
                      FilledButton.icon(
                        onPressed: hasText && !isSending
                            ? _sendCommandBuffer
                            : null,
                        icon: isSending
                            ? const SizedBox.square(
                                dimension: 16,
                                child: CircularProgressIndicator(
                                  strokeWidth: 2,
                                ),
                              )
                            : const Icon(Icons.send, size: 17),
                        label: Text(l10n.sshSend),
                        style: FilledButton.styleFrom(
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(12),
                          ),
                        ),
                      ),
                    ],
                  ),
                ],
              );
            },
            ),
          ],
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
      Loggers.app.warning('Failed to send SSH command buffer', error, stackTrace);
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
