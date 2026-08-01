import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:ui';

import 'package:dartssh2/dartssh2.dart';
import 'package:fl_lib/fl_lib.dart';
import 'package:flutter/foundation.dart'
    show Listenable, ValueListenable, ValueNotifier;
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:server_box/core/extension/context/locale.dart';
import 'package:server_box/core/utils/server.dart';
import 'package:server_box/core/utils/ssh_auth.dart';
import 'package:server_box/core/utils/sudo_password.dart';
import 'package:server_box/data/model/ai/ask_ai_models.dart';
import 'package:server_box/data/model/server/server_private_info.dart';
import 'package:server_box/data/model/server/snippet.dart';
import 'package:server_box/data/model/ssh/virtual_key.dart';
import 'package:server_box/data/provider/ai/ask_ai.dart';
import 'package:server_box/data/provider/server/single.dart';
import 'package:server_box/data/provider/snippet.dart';
import 'package:server_box/data/provider/virtual_keyboard.dart';
import 'package:server_box/data/res/store.dart';
import 'package:server_box/data/res/terminal.dart';
import 'package:server_box/data/ssh/command_buffer.dart';
import 'package:server_box/data/ssh/persistent_shell.dart';
import 'package:server_box/data/ssh/session_manager.dart';
import 'package:server_box/data/ssh/ssh_terminal_environment.dart';
import 'package:server_box/data/ssh/terminal_output_buffer.dart';
import 'package:server_box/data/ssh/tmux/tmux_export.dart';
import 'package:server_box/view/page/storage/sftp.dart';
import 'package:server_box/view/widget/glass_surface.dart';
import 'package:server_box/view/widget/ssh_connection_status.dart';
import 'package:server_box/view/widget/tmux_session_selector.dart';
import 'package:wakelock_plus/wakelock_plus.dart';
import 'package:xterm/core.dart';
import 'package:xterm/ui.dart' hide TerminalThemes;

part 'ask_ai.dart';
part 'command_composer.dart';
part 'init.dart';
part 'keyboard.dart';
part 'virt_key.dart';

final class SshPageArgs {
  final Spi spi;
  final String? initCmd;
  final Snippet? initSnippet;
  final bool notFromTab;
  final bool autoShowKeyboard;
  final Function()? onSessionEnd;
  final GlobalKey<TerminalViewState>? terminalKey;
  final FocusNode? focusNode;
  final ValueListenable<bool>? visibleListenable;
  final String? tmuxSession;
  final int? tmuxWindow;
  final VoidCallback? onTmuxStateChanged;
  final ValueNotifier<TermSessionStatus>? connectionStatus;

  const SshPageArgs({
    required this.spi,
    this.initCmd,
    this.initSnippet,
    this.notFromTab = true,
    this.autoShowKeyboard = false,
    this.onSessionEnd,
    this.terminalKey,
    this.focusNode,
    this.visibleListenable,
    this.tmuxSession,
    this.tmuxWindow,
    this.onTmuxStateChanged,
    this.connectionStatus,
  }) : assert(
         notFromTab || visibleListenable != null,
         'visibleListenable is required when notFromTab is false',
       );
}

class _EmptyRoute extends StatefulWidget {
  const _EmptyRoute();

  @override
  State<_EmptyRoute> createState() => _EmptyRouteState();
}

class _EmptyRouteState extends State<_EmptyRoute> {
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) Navigator.of(context).pop();
    });
  }

  @override
  Widget build(BuildContext context) => const SizedBox.shrink();
}

class SSHPage extends ConsumerStatefulWidget {
  final SshPageArgs args;

  const SSHPage({super.key, required this.args});

  @override
  ConsumerState<SSHPage> createState() => SSHPageState();

  static const route = AppRouteArg<void, SshPageArgs>(
    page: SSHPage.new,
    path: '/ssh/page',
  );

  /// Restorable route builder for navigation from server list.
  /// Takes a server ID as argument and looks up the Spi from the store.
  /// Note: tmux state restoration is handled at SSHTabPage level for tab-based navigation.
  static Route<void> restorableRouteBuilder(
    BuildContext context,
    Object? arguments,
  ) {
    if (arguments is! String) {
      return MaterialPageRoute(builder: (_) => const _EmptyRoute());
    }
    final serverId = arguments;
    final servers = Stores.server.fetch();
    final spi = servers.where((s) => s.id == serverId).firstOrNull;
    if (spi == null) {
      return MaterialPageRoute(builder: (_) => const _EmptyRoute());
    }
    return MaterialPageRoute(
      builder: (_) => VirtualWindowFrame(
        child: SSHPage(args: SshPageArgs(spi: spi, autoShowKeyboard: true)),
      ),
    );
  }
}

const _horizonPadding = 7.0;
const _sshToolbarKeyHeight = 38.0;
const _sshToolbarKeyGap = 4.0;
const _sshToolbarKeyInset = 6.0;
const _sshToolbarDirectionKeys = [
  VirtKey.up,
  VirtKey.left,
  VirtKey.down,
  VirtKey.right,
];

class SSHPageState extends ConsumerState<SSHPage>
    with
        AutomaticKeepAliveClientMixin,
        AfterLayoutMixin,
        TickerProviderStateMixin,
        WidgetsBindingObserver,
        RestorationMixin {
  // Restorable state for this SSH page
  final RestorableString _restorableServerId = RestorableString('');
  final RestorableStringN _restorableTmuxSession = RestorableStringN(null);
  final RestorableIntN _restorableTmuxWindow = RestorableIntN(null);

  @override
  String get restorationId => 'ssh_page_${widget.args.spi.id}';

  @override
  void restoreState(RestorationBucket? oldBucket, bool initialRestore) {
    registerForRestoration(_restorableServerId, 'server_id');
    registerForRestoration(_restorableTmuxSession, 'tmux_session');
    registerForRestoration(_restorableTmuxWindow, 'tmux_window');
  }

  late final _terminal = Terminal();
  late final TerminalController _terminalController = TerminalController(
    vsync: this,
  );
  final List<List<VirtKey>> _virtKeysList = [];
  late final _termKey =
      widget.args.terminalKey ?? GlobalKey<TerminalViewState>();

  late TerminalStyle _terminalStyle;
  late TerminalTheme _terminalTheme;
  double _virtKeysHeight = 0;
  bool _horizonVirtKeys = false;

  bool _isDark = false;
  Timer? _virtKeyRepeatTimer;
  final TextEditingController _commandBufferController =
      TextEditingController();
  final FocusNode _commandBufferFocusNode = FocusNode();
  final ValueNotifier<_CommandSendMode> _commandSendMode = ValueNotifier(
    _CommandSendMode.allAtOnce,
  );
  final ValueNotifier<bool> _isCommandComposerOpen = ValueNotifier(false);
  final ValueNotifier<bool> _isSendingCommandBuffer = ValueNotifier(false);
  final ValueNotifier<double> _keyboardInset = ValueNotifier(0);
  SSHClient? _client;
  SSHSession? _session;
  Timer? _discontinuityTimer;
  Timer? _terminalFlushTimer;
  final _terminalOutputBuffer = TerminalOutputBuffer();
  String _sshOutputTail = '';
  final List<StreamSubscription<String>> _terminalOutputSubscriptions = [];
  static const _connectionCheckInterval = Duration(seconds: 60);
  static const _connectionCheckTimeout = Duration(seconds: 10);
  static const _terminalFlushInterval = Duration(milliseconds: 16);
  static const _terminalFlushCharLimit = 32768;
  static const _sshOutputTailCharLimit = 8192;
  static const _maxKeepAliveFailures = 3;
  int _missedKeepAliveCount = 0;
  bool _isCheckingConnection = false;
  bool _hasPendingImmediateCheck = false;
  bool _reconnectCancelled = false;
  bool _disconnectDialogOpen = false;
  bool _reportedDisconnected = false;
  late final ValueNotifier<TermSessionStatus> _connectionStatus;
  late final bool _ownsConnectionStatus;
  VoidCallback? _visibilityListener;
  bool _isPickingSnippet = false;
  String? _tmuxCurrentSession;
  int? _tmuxCurrentWindow;

  /// Current tmux session name (for state restoration)
  String? get tmuxCurrentSession => _tmuxCurrentSession;

  /// Current tmux window index (for state restoration)
  int? get tmuxCurrentWindow => _tmuxCurrentWindow;

  /// Used for (de)activate the wake lock and forground service
  static var _sshConnCount = 0;
  late final String _sessionId = ShortId.generate();
  late final int _sessionStartMs = DateTime.now().millisecondsSinceEpoch;

  Future<void> pickSnippetFromToolbar() => _pickSnippet();

  void requestTerminalKeyboard() {
    if (!mounted) return;
    widget.args.focusNode?.requestFocus();
    _termKey.currentState?.requestKeyboard();
  }

  void _setConnectionStatus(TermSessionStatus status) {
    if (_connectionStatus.value != status) {
      _connectionStatus.value = status;
    }
    TermSessionManager.updateStatus(_sessionId, status);
  }

  @override
  void dispose() {
    _restorableServerId.dispose();
    _restorableTmuxSession.dispose();
    _restorableTmuxWindow.dispose();
    WidgetsBinding.instance.removeObserver(this);
    _stopVirtKeyRepeat();
    _commandBufferController.dispose();
    _commandBufferFocusNode.dispose();
    _commandSendMode.dispose();
    _isCommandComposerOpen.dispose();
    _isSendingCommandBuffer.dispose();
    _keyboardInset.dispose();
    _terminalController.dispose();
    _discontinuityTimer?.cancel();
    _terminalFlushTimer?.cancel();
    for (final subscription in _terminalOutputSubscriptions) {
      subscription.cancel();
    }
    _removeVisibilityListener();
    Stores.setting.horizonVirtKey.listenable().removeListener(
      _handleVirtKeySettingsChanged,
    );
    Stores.setting.sshVirtKeys.listenable().removeListener(
      _handleVirtKeySettingsChanged,
    );
    Stores.setting.sshVirtKeysDisabled.listenable().removeListener(
      _handleVirtKeySettingsChanged,
    );

    HardwareKeyboard.instance.removeHandler(_handleKeyEvent);

    if (--_sshConnCount <= 0) {
      WakelockPlus.disable();
    }

    // Remove session entry
    TermSessionManager.remove(_sessionId);
    if (_ownsConnectionStatus) {
      _connectionStatus.dispose();
    }

    super.dispose();
  }

  @override
  void initState() {
    super.initState();
    _ownsConnectionStatus = widget.args.connectionStatus == null;
    _connectionStatus =
        widget.args.connectionStatus ??
        ValueNotifier(TermSessionStatus.connecting);
    _connectionStatus.value = TermSessionStatus.connecting;
    WidgetsBinding.instance.addObserver(this);
    _initStoredCfg();
    _reloadVirtKeys();
    Stores.setting.horizonVirtKey.listenable().addListener(
      _handleVirtKeySettingsChanged,
    );
    Stores.setting.sshVirtKeys.listenable().addListener(
      _handleVirtKeySettingsChanged,
    );
    Stores.setting.sshVirtKeysDisabled.listenable().addListener(
      _handleVirtKeySettingsChanged,
    );
    _bindVisibilityListener();
    _setupDiscontinuityTimer();

    // Initialize client from provider
    final serverState = ref.read(serverProvider(widget.args.spi.id));
    _client = serverState.client;

    if (++_sshConnCount == 1) {
      WakelockPlus.enable();
    }

    // Add session entry (for Android notifications & iOS Live Activities)
    TermSessionManager.add(
      id: _sessionId,
      spi: widget.args.spi,
      startTimeMs: _sessionStartMs,
      disconnect: _disconnectFromNotification,
      status: TermSessionStatus.connecting,
      setAsActive: _shouldActivateSessionOnInit,
    );
    if (_shouldActivateSessionOnInit) {
      TermSessionManager.setActive(_sessionId, hasTerminal: true);
    }
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    super.didChangeAppLifecycleState(state);
    if (!mounted) return;

    switch (state) {
      case AppLifecycleState.resumed:
        if (!_isVisibleSessionPage) return;
        TermSessionManager.setActive(_sessionId, hasTerminal: true);
        if (!_shouldShowKeyboardOnEntry) break;
        WidgetsBinding.instance.addPostFrameCallback((_) {
          if (!mounted || !_isVisibleSessionPage) return;
          requestTerminalKeyboard();
        });
        unawaited(_checkConnectionHealth(immediate: true));
        if (_discontinuityTimer == null || !_discontinuityTimer!.isActive) {
          _setupDiscontinuityTimer();
        }
        break;
      case AppLifecycleState.paused:
        _stopVirtKeyRepeat();
        if (!_isVisibleSessionPage) return;
        TermSessionManager.setActive(_sessionId, hasTerminal: false);
        break;
      case AppLifecycleState.inactive:
      case AppLifecycleState.hidden:
      case AppLifecycleState.detached:
        _stopVirtKeyRepeat();
        break;
    }
  }

  @override
  void didChangeMetrics() {
    super.didChangeMetrics();
    _updateKeyboardInset();
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _isDark = switch (Stores.setting.termTheme.fetch()) {
      1 => false,
      2 => true,
      _ => switch (Stores.setting.themeMode.fetch()) {
        1 => false,
        2 || 3 => true,
        _ => context.isDark,
      },
    };
    _terminalTheme = _isDark ? TerminalThemes.dark : TerminalThemes.light;
    _terminalTheme = _terminalTheme.copyWith(selectionCursor: UIs.primaryColor);

    // Because the virtual keyboard only displayed on mobile devices
    _updateVirtKeysHeight();
    _updateKeyboardInset();
  }

  @override
  Widget build(BuildContext context) {
    super.build(context);
    Widget child = PopScope(
      canPop: false,
      onPopInvokedWithResult: (didPop, _) {
        if (didPop) return;
        _handleEscKeyOrBackButton();
      },
      child: Scaffold(
        appBar: widget.args.notFromTab
            ? CustomAppBar(
                leading: BackButton(
                  onPressed: () {
                    _closeTerminalKeyboard();
                    context.pop();
                  },
                ),
                title: SshConnectionTitle(
                  title: widget.args.spi.name,
                  statusListenable: _connectionStatus,
                ),
                centerTitle: false,
                actions: _buildAppBarActions(),
              )
            : null,
        body: _buildBody(),
        bottomNavigationBar: isDesktop ? null : _buildBottom(),
      ),
    );

    if (isIOS) {
      child = AnnotatedRegion(
        value: _isDark ? SystemUiOverlayStyle.light : SystemUiOverlayStyle.dark,
        child: child,
      );
    }
    return child;
  }

  Widget _buildBody() {
    final letterCache = Stores.setting.letterCache.fetch();
    final bgImage = Stores.setting.sshBgImage.fetch();
    final opacity = Stores.setting.sshBgOpacity.fetch();
    final blur = Stores.setting.sshBlurRadius.fetch();
    final file = File(bgImage);
    final hasBg = bgImage.isNotEmpty && file.existsSync();
    final theme = hasBg
        ? _terminalTheme.copyWith(background: Colors.transparent)
        : _terminalTheme;
    final children = <Widget>[];
    if (hasBg) {
      children.add(
        Positioned.fill(
          child: Image.file(
            file,
            fit: BoxFit.cover,
            errorBuilder: (_, _, _) => const SizedBox(),
          ),
        ),
      );
      if (blur > 0) {
        children.add(
          Positioned.fill(
            child: BackdropFilter(
              filter: ImageFilter.blur(sigmaX: blur, sigmaY: blur),
              child: const SizedBox(),
            ),
          ),
        );
      }
      children.add(
        Positioned.fill(
          child: ColoredBox(
            color: _terminalTheme.background.withValues(alpha: opacity),
          ),
        ),
      );
    }
    children.add(
      Padding(
        padding: EdgeInsets.only(left: _horizonPadding, right: _horizonPadding),
        child: TerminalView(
          _terminal,
          key: _termKey,
          controller: _terminalController,
          keyboardType: TextInputType.text,
          enableSuggestions: letterCache,
          enableIMEPersonalizedLearning: true,
          textStyle: _terminalStyle,
          backgroundOpacity: 0,
          theme: theme,
          deleteDetection: isMobile,
          autofocus: false,
          keyboardAppearance: _isDark ? Brightness.dark : Brightness.light,
          showToolbar: true,
          viewOffset: Offset(
            2 * _horizonPadding,
            CustomAppBar.sysStatusBarHeight,
          ),
          hideScrollBar: false,
          focusNode: widget.args.focusNode,
          toolbarBuilder: _buildTerminalToolbar,
          onCopied: _onTerminalCopied,
          onSelectAll: _onTerminalSelectAll,
          onPaste: _onTerminalPaste,
        ),
      ),
    );

    return SizedBox(
      height: double.infinity,
      child: Stack(children: children),
    );
  }

  Widget _buildBottom() => _SshKeyboardToolbar(
    panelBuilder: (context) => _buildMobileInputPanel(),
    viewInsetsListenable: _keyboardInset,
    applyBottomInset: widget.args.notFromTab,
  );

  void _updateKeyboardInset() {
    if (!mounted) return;
    final view = View.of(context);
    final windowInset = view.viewInsets.bottom / view.devicePixelRatio;
    final mediaInset = MediaQuery.maybeViewInsetsOf(context)?.bottom ?? 0;
    final nextInset = mediaInset > windowInset ? mediaInset : windowInset;
    if ((_keyboardInset.value - nextInset).abs() < 0.5) return;
    _keyboardInset.value = nextInset;
  }

  void _closeTerminalKeyboard() {
    _termKey.currentState?.closeKeyboard();
    _commandBufferFocusNode.unfocus();
    widget.args.focusNode?.unfocus();
    FocusManager.instance.primaryFocus?.unfocus();
  }

  List<Widget> _buildAppBarActions() {
    final actions = <Widget>[
      IconButton(
        onPressed: _pickSnippet,
        tooltip: libL10n.snippet,
        icon: const Icon(Icons.code),
      ),
    ];
    if (!widget.args.spi.isRoot) {
      actions.add(
        IconButton(
          onPressed: _insertSudoPassword,
          tooltip: l10n.trySudo,
          icon: const Icon(Icons.password),
        ),
      );
    }
    return actions;
  }

  Future<void> _pickSnippet() async {
    if (_isPickingSnippet) return;
    _isPickingSnippet = true;

    try {
      final snippets = ref.read(snippetProvider.select((p) => p.snippets));
      if (snippets.isEmpty) {
        if (!mounted) return;
        context.showSnackBar(libL10n.empty);
        return;
      }

      final selected = await context.showPickSingleDialog<Snippet>(
        title: libL10n.snippet,
        items: snippets,
        display: (snippet) => snippet.name,
      );
      if (selected == null) return;

      try {
        await selected.runInTerm(_terminal, widget.args.spi);
      } catch (e, s) {
        if (!mounted) return;
        context.showErrDialog(e, s, '${libL10n.snippet}: ${selected.name}');
        return;
      }
      if (!mounted) return;
      widget.args.focusNode?.requestFocus();
      _termKey.currentState?.requestKeyboard();
    } finally {
      _isPickingSnippet = false;
    }
  }

  Widget _buildVirtualKey(
    VirtKeyState virtKeyState,
    VirtKeyboard virtKeyNotifier,
  ) {
    if (_horizonVirtKeys) {
      return _buildSingleLineVirtualKey(virtKeyState, virtKeyNotifier);
    }
    return _buildMultiLineVirtualKey(virtKeyState, virtKeyNotifier);
  }

  Widget _buildMultiLineVirtualKey(
    VirtKeyState virtKeyState,
    VirtKeyboard virtKeyNotifier,
  ) {
    if (_virtKeysList.isEmpty) return UIs.placeholder;

    return LayoutBuilder(
      builder: (_, cons) {
        final maxKeyCount = _virtKeysList.fold<int>(
          0,
          (max, row) => row.length > max ? row.length : max,
        );
        final availableWidth =
            cons.maxWidth - _sshToolbarKeyGap * (maxKeyCount - 1);
        final virtKeyWidth = availableWidth > 0
            ? availableWidth / maxKeyCount
            : _sshToolbarKeyHeight;

        Widget buildRow(List<VirtKey> rowKeys) {
          final children = <Widget>[];
          for (var index = 0; index < rowKeys.length; index++) {
            if (index > 0) {
              children.add(const SizedBox(width: _sshToolbarKeyGap));
            }
            children.add(
              _buildVirtKeyItem(
                rowKeys[index],
                virtKeyWidth,
                virtKeyState,
                virtKeyNotifier,
              ),
            );
          }
          return SizedBox(
            width: double.infinity,
            height: _sshToolbarKeyHeight,
            child: Row(children: children),
          );
        }

        final rows = <Widget>[];
        for (var index = 0; index < _virtKeysList.length; index++) {
          if (index > 0) {
            rows.add(const SizedBox(height: _sshToolbarKeyGap));
          }
          rows.add(buildRow(_virtKeysList[index]));
        }
        return Column(mainAxisSize: MainAxisSize.min, children: rows);
      },
    );
  }

  Widget _buildSingleLineVirtualKey(
    VirtKeyState virtKeyState,
    VirtKeyboard virtKeyNotifier,
  ) {
    final allKeys = _virtKeysList.expand((keys) => keys).toList();
    if (allKeys.isEmpty) return UIs.placeholder;
    final otherKeys = allKeys
        .where((key) => !_sshToolbarDirectionKeys.contains(key))
        .toList();
    final hasUp = allKeys.contains(VirtKey.up);
    final trailingDirectionKeys = [
      VirtKey.left,
      VirtKey.down,
      VirtKey.right,
    ].where(allKeys.contains).toList();

    return LayoutBuilder(
      builder: (_, cons) {
        final trailingWidth =
            trailingDirectionKeys.length * _sshToolbarKeyHeight +
            _sshToolbarKeyGap * (trailingDirectionKeys.length - 1);
        final otherAreaWidth =
            cons.maxWidth -
            (trailingDirectionKeys.isEmpty
                ? 0
                : _sshToolbarKeyGap + trailingWidth);
        final keyCount = otherKeys.length < 7 ? otherKeys.length : 7;
        final otherKeyWidth = otherKeys.isEmpty
            ? _sshToolbarKeyHeight
            : (otherAreaWidth - _sshToolbarKeyGap * (keyCount - 1)) > 0
            ? (otherAreaWidth - _sshToolbarKeyGap * (keyCount - 1)) / keyCount
            : _sshToolbarKeyHeight;

        List<Widget> buildOtherKeys() {
          final children = <Widget>[];
          for (var index = 0; index < otherKeys.length; index++) {
            if (index > 0) {
              children.add(const SizedBox(width: _sshToolbarKeyGap));
            }
            children.add(
              _buildVirtKeyItem(
                otherKeys[index],
                otherKeyWidth,
                virtKeyState,
                virtKeyNotifier,
              ),
            );
          }
          return children;
        }

        Widget buildTrailingDirectionKeys() {
          final children = <Widget>[];
          for (var index = 0; index < trailingDirectionKeys.length; index++) {
            if (index > 0) {
              children.add(const SizedBox(width: _sshToolbarKeyGap));
            }
            children.add(
              _buildVirtKeyItem(
                trailingDirectionKeys[index],
                _sshToolbarKeyHeight,
                virtKeyState,
                virtKeyNotifier,
              ),
            );
          }
          return Row(mainAxisSize: MainAxisSize.min, children: children);
        }

        return Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            SizedBox(
              height: _sshToolbarKeyHeight,
              child: Row(
                children: [
                  Expanded(
                    child: _buildCommandModeBar(
                      Theme.of(context).colorScheme,
                      false,
                      inline: true,
                    ),
                  ),
                  if (hasUp) ...[
                    const SizedBox(width: _sshToolbarKeyGap),
                    _buildVirtKeyItem(
                      VirtKey.up,
                      _sshToolbarKeyHeight,
                      virtKeyState,
                      virtKeyNotifier,
                    ),
                  ],
                ],
              ),
            ),
            const SizedBox(height: _sshToolbarKeyGap),
            SizedBox(
              height: _sshToolbarKeyHeight,
              child: Row(
                children: [
                  Expanded(
                    child: otherKeys.isEmpty
                        ? const SizedBox.shrink()
                        : SingleChildScrollView(
                            scrollDirection: Axis.horizontal,
                            child: SizedBox(
                              height: _sshToolbarKeyHeight,
                              child: Row(children: buildOtherKeys()),
                            ),
                          ),
                  ),
                  if (trailingDirectionKeys.isNotEmpty) ...[
                    const SizedBox(width: _sshToolbarKeyGap),
                    buildTrailingDirectionKeys(),
                  ],
                ],
              ),
            ),
          ],
        );
      },
    );
  }

  Widget _buildVirtKeyItem(
    VirtKey item,
    double virtKeyWidth,
    VirtKeyState virtKeyState,
    VirtKeyboard virtKeyNotifier,
  ) {
    var selected = false;
    switch (item.key) {
      case TerminalKey.control:
        selected = virtKeyState.ctrl;
        break;
      case TerminalKey.alt:
        selected = virtKeyState.alt;
        break;
      case TerminalKey.shift:
        selected = virtKeyState.shift;
        break;
      default:
        break;
    }

    final scheme = Theme.of(context).colorScheme;
    final foreground = selected
        ? scheme.onSecondaryContainer
        : scheme.onSurfaceVariant;
    final child = item.icon != null
        ? Icon(item.icon, size: 17, color: foreground)
        : Text(
            item.text,
            style: TextStyle(
              color: foreground,
              fontSize: 14,
              fontWeight: selected ? FontWeight.w800 : FontWeight.w600,
            ),
          );

    const shape = RoundedSuperellipseBorder(
      borderRadius: BorderRadius.all(Radius.circular(13)),
    );
    return Semantics(
      button: true,
      label: item.help ?? item.text,
      toggled: item.toggleable ? selected : null,
      child: SizedBox(
        width: virtKeyWidth,
        height: _sshToolbarKeyHeight,
        child: Material(
          color: selected
              ? scheme.secondaryContainer
              : scheme.surfaceContainerHighest.withValues(alpha: 0.68),
          shape: shape,
          clipBehavior: Clip.antiAlias,
          child: InkWell(
            customBorder: shape,
            onTap: () => _doVirtualKey(item, virtKeyNotifier),
            onTapDown: (_) {
              if (item.canLongPress) {
                _startVirtKeyRepeat(item, virtKeyNotifier);
              }
            },
            onTapCancel: _stopVirtKeyRepeat,
            onTapUp: (_) => _stopVirtKeyRepeat(),
            child: Center(child: child),
          ),
        ),
      ),
    );
  }

  void _startVirtKeyRepeat(VirtKey item, VirtKeyboard virtKeyNotifier) {
    _stopVirtKeyRepeat();
    final deadline = DateTime.now().add(const Duration(seconds: 4));
    _virtKeyRepeatTimer = Timer(const Duration(milliseconds: 450), () {
      if (!mounted) return;
      _doVirtualKey(item, virtKeyNotifier);
      _virtKeyRepeatTimer = Timer.periodic(const Duration(milliseconds: 90), (
        timer,
      ) {
        if (!mounted || DateTime.now().isAfter(deadline)) {
          timer.cancel();
          return;
        }
        _doVirtualKey(item, virtKeyNotifier);
      });
    });
  }

  void _stopVirtKeyRepeat() {
    _virtKeyRepeatTimer?.cancel();
    _virtKeyRepeatTimer = null;
  }

  void _onTerminalCopied() {
    _showClipboardSuccess();
    _terminalController.clearSelection();
  }

  void _onTerminalSelectAll() {
    if (!mounted) return;
    _termKey.currentState?.renderTerminal.selectAll();
  }

  Future<void> _onTerminalPaste() async {
    final value = await Clipboard.getData(Clipboard.kTextPlain);
    if (!mounted) return;
    final text = value?.text;
    if (text == null) return;
    _terminal.textInput(text);
    _terminalController.clearSelection();
  }

  Future<void> _onClipboardAction() async {
    if (_terminalController.selection != null) {
      final selectedText = _termKey.currentState?.renderTerminal.selectedText;
      if (selectedText != null && selectedText.isNotEmpty) {
        await Clipboard.setData(ClipboardData(text: selectedText));
        _showClipboardSuccess();
        _terminalController.clearSelection();
        return;
      }
      return;
    }
    await _onTerminalPaste();
  }

  @override
  bool get wantKeepAlive => true;

  bool get _shouldActivateSessionOnInit {
    if (widget.args.notFromTab) return true;
    return widget.args.visibleListenable?.value ?? false;
  }

  bool get _shouldShowKeyboardOnEntry {
    if (widget.args.notFromTab) return widget.args.autoShowKeyboard;
    return _shouldActivateSessionOnInit;
  }

  bool get _isVisibleSessionPage {
    if (widget.args.notFromTab) {
      final route = ModalRoute.of(context);
      return route?.isCurrent ?? true;
    }
    return widget.args.visibleListenable?.value ?? false;
  }

  void _bindVisibilityListener() {
    final visibleListenable = widget.args.visibleListenable;
    if (widget.args.notFromTab ||
        visibleListenable == null ||
        _visibilityListener != null) {
      return;
    }
    void listener() {
      if (!mounted) return;
      if (visibleListenable.value) {
        TermSessionManager.setActive(_sessionId, hasTerminal: true);
        unawaited(_checkConnectionHealth(immediate: true));
      } else {
        TermSessionManager.hideTerminal(_sessionId);
      }
    }

    _visibilityListener = listener;
    visibleListenable.addListener(listener);
  }

  void _removeVisibilityListener() {
    final visibleListenable = widget.args.visibleListenable;
    final listener = _visibilityListener;
    if (visibleListenable != null && listener != null) {
      visibleListenable.removeListener(listener);
    }
    _visibilityListener = null;
  }

  void _handleVirtKeySettingsChanged() {
    if (!mounted) return;
    setState(_reloadVirtKeys);
  }

  void _showClipboardSuccess() {
    if (!mounted) return;
    context.showSnackBar(libL10n.success);
  }

  Future<void> _insertSudoPassword() async {
    final authed = await SudoPassword.authenticateIfNeeded();
    if (!authed) {
      if (!mounted) return;
      context.showSnackBar(libL10n.fail);
      return;
    }

    final password = await SudoPassword.resolveForTerminal(widget.args.spi);
    if (password == null || password.isEmpty) {
      if (!mounted) return;
      context.showSnackBar(libL10n.empty);
      return;
    }

    bool detected = false;
    const delays = [0, 100, 200, 400, 800, 1600];
    for (int i = 0; i < delays.length; i++) {
      final delayMs = delays[i];
      if (delayMs > 0) {
        await Future.delayed(Duration(milliseconds: delayMs));
        if (!mounted) return;
      }

      _drainPendingTerminalOutput();

      if (_hasPendingSudoPrompt()) {
        detected = true;
        break;
      }
    }

    if (!detected) {
      if (!mounted) return;
      context.showSnackBar(l10n.sudoPromptNotFound);
      return;
    }

    _terminal.textInput(password);
    _terminal.keyInput(TerminalKey.enter);
    _sshOutputTail = '';

    if (!mounted) return;
    widget.args.focusNode?.requestFocus();
    _termKey.currentState?.requestKeyboard();
    context.showSnackBar(libL10n.success);
  }

  bool _hasPendingSudoPrompt() {
    return _hasPendingSudoPromptInTerminalBuffer() ||
        _hasPendingSudoPromptInOutputTail();
  }

  bool _hasPendingSudoPromptInTerminalBuffer() {
    final raw = _terminal.buffer.currentLine.toString().trim();
    if (raw.isEmpty) return false;
    return SudoPassword.isPromptText(raw);
  }

  bool _hasPendingSudoPromptInOutputTail() {
    final raw = _latestSshOutputLine();
    if (raw.isEmpty) return false;
    return SudoPassword.isPromptText(raw);
  }

  String _latestSshOutputLine() {
    final normalized = SudoPassword.normalizeOutput(_sshOutputTail);
    return normalized
        .split('\n')
        .reversed
        .map((line) => line.trim())
        .firstWhere((line) => line.isNotEmpty, orElse: () => '');
  }

  void _updateVirtKeysHeight() {
    if (!isMobile) {
      _virtKeysHeight = 0;
      return;
    }

    if (_virtKeysList.isEmpty) {
      _virtKeysHeight = 0;
    } else {
      final rowCount = _horizonVirtKeys ? 2 : _virtKeysList.length;
      _virtKeysHeight =
          _sshToolbarKeyHeight * rowCount +
          _sshToolbarKeyGap * (rowCount - 1) +
          _sshToolbarKeyInset * 2;
    }
  }

  @override
  FutureOr<void> afterFirstLayout(BuildContext context) async {
    await _showHelp();
    try {
      await _initTerminal();
    } catch (_) {
      _setConnectionStatus(TermSessionStatus.disconnected);
      rethrow;
    }

    if (Stores.setting.sshWakeLock.fetch()) WakelockPlus.enable();

    HardwareKeyboard.instance.addHandler(_handleKeyEvent);
  }
}
