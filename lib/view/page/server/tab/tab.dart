// ignore_for_file: invalid_use_of_protected_member

import 'dart:async';
import 'dart:math' as math;
import 'dart:ui';

import 'package:fl_lib/fl_lib.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:icons_plus/icons_plus.dart';
import 'package:server_box/core/chan.dart';
import 'package:server_box/core/extension/context/locale.dart';
import 'package:server_box/core/extension/ssh_client.dart';
import 'package:server_box/core/route.dart';
import 'package:server_box/data/model/app/net_view.dart';
import 'package:server_box/data/model/app/scripts/cmd_types.dart';
import 'package:server_box/data/model/app/scripts/shell_func.dart';
import 'package:server_box/data/model/server/server.dart';
import 'package:server_box/data/model/server/server_private_info.dart';
import 'package:server_box/data/model/server/try_limiter.dart';
import 'package:server_box/data/provider/port_forward_provider.dart';
import 'package:server_box/data/provider/server/all.dart';
import 'package:server_box/data/provider/server/single.dart';
import 'package:server_box/data/provider/sftp.dart';
import 'package:server_box/data/res/build_data.dart';
import 'package:server_box/data/res/store.dart';
import 'package:server_box/data/ssh/session_manager.dart';
import 'package:server_box/view/page/server/connection_stats.dart';
import 'package:server_box/view/page/server/detail/view.dart';
import 'package:server_box/view/page/server/edit/edit.dart';
import 'package:server_box/view/page/setting/entry.dart';
import 'package:server_box/view/responsive_layout.dart';
import 'package:server_box/view/widget/percent_circle.dart';
import 'package:server_box/view/widget/server_func_btns.dart';
import 'package:wakelock_plus/wakelock_plus.dart';

part 'card_stat.dart';
part 'content.dart';
part 'landscape.dart';
part 'top_bar.dart';
part 'utils.dart';

class ServerPage extends ConsumerStatefulWidget {
  const ServerPage({super.key});

  @override
  ConsumerState<ServerPage> createState() => _ServerPageState();

  static const route = AppRouteNoArg(page: ServerPage.new, path: '/servers');
}

const _cardPad = 74.0;
const _cardPadSingle = 13.0;

class _ServerPageState extends ConsumerState<ServerPage>
    with AutomaticKeepAliveClientMixin, AfterLayoutMixin {
  late double _textFactorDouble;
  final ValueNotifier<double> _offsetNotifier = ValueNotifier(1);
  late TextScaler _textFactor;

  final _cardsStatus = <String, _CardNotifier>{};
  late final ValueNotifier<Set<String>> _tags;

  Timer? _timer;

  final _tag = ''.vn;

  final _scrollController = ScrollController();

  @override
  void dispose() {
    _timer?.cancel();
    _scrollController.dispose();
    _tag.dispose();
    _tags.dispose();
    _offsetNotifier.dispose();
    super.dispose();
  }

  @override
  void initState() {
    super.initState();
    _tags = ValueNotifier(ref.read(serversProvider).tags);
    _startAvoidJitterTimer();
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _updateOffset();
  }

  @override
  Widget build(BuildContext context) {
    super.build(context);
    // Listen to provider changes and update the ValueNotifier
    ref.listen(serversProvider, (previous, next) {
      _tags.value = next.tags;
    });
    return OrientationBuilder(
      builder: (_, orientation) {
        if (orientation == Orientation.landscape) {
          final useFullScreen = Stores.setting.fullScreen.fetch();
          // Only enter landscape mode when the screen is wide enough and the
          // full screen mode is enabled.
          if (useFullScreen) return _buildLandscape();
        }
        return _buildPortrait();
      },
    );
  }

  Widget _buildScaffold(Widget child) {
    final width = MediaQuery.sizeOf(context).width;
    final useStatusGlass = AppLayout.useStatusGlass(width);
    return Scaffold(
      extendBodyBehindAppBar: useStatusGlass,
      appBar: _TopBar(
        tags: _tags,
        onTagChanged: (p0) => _tag.value = p0,
        initTag: _tag.value,
        onAddServer: _onTapAddServer,
        useStatusGlass: useStatusGlass,
        expandedStatus: !AppLayout.useCompactNavigation(width),
      ),
      body: Stores.setting.textFactor.listenable().listenVal((val) {
        _updateTextScaler(val);
        return child;
      }),
    );
  }

  Widget _buildPortrait() {
    // Watch serverOrder, tags, and servers to ensure filtered view rebuilds
    // when individual server tags change without affecting the global tag set
    final serverOrder = ref.watch(serversProvider.select((s) => s.serverOrder));
    ref.watch(serversProvider.select((s) => s.tags));
    ref.watch(serversProvider.select((s) => s.servers));
    return _tag.listenVal((val) {
      final filtered = _filterServers(serverOrder);
      final child = _buildScaffold(_buildBodySmall(filtered: filtered));
      return child;
    });
  }

  Widget _buildBodySmall({required List<String> filtered}) {
    if (filtered.isEmpty) {
      return Padding(
        padding: EdgeInsets.only(
          top: AppLayout.useStatusGlass(MediaQuery.sizeOf(context).width)
              ? _TopBar.mobileHeightWithStatus(
                  context,
                  _tags.value.isNotEmpty,
                )
              : 0,
        ),
        child: Center(child: Text(libL10n.empty, textAlign: TextAlign.center)),
      );
    }

    return LayoutBuilder(
      builder: (_, cons) {
        // Calculate number of columns based on available width
        final columnsCount = math.max(
          1,
          (cons.maxWidth / UIs.columnWidth).floor(),
        );
        final useStatusGlass = AppLayout.useStatusGlass(cons.maxWidth);
        final firstCardTopInset = useStatusGlass
            ? _TopBar.mobileHeightWithStatus(
                context,
                _tags.value.isNotEmpty,
              )
            : 0.0;
        final padding = columnsCount > 1
            ? EdgeInsets.fromLTRB(0, firstCardTopInset, 5, 7)
            : EdgeInsets.fromLTRB(7, firstCardTopInset, 7, 7);

        return Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: List.generate(columnsCount, (colIndex) {
            // Calculate which servers belong in this column
            final serversInThisColumn = <String>[];
            for (int i = colIndex; i < filtered.length; i += columnsCount) {
              serversInThisColumn.add(filtered[i]);
            }
            final lens = serversInThisColumn.length;

            return Expanded(
              child: ListView.builder(
                controller: colIndex == 0 ? _scrollController : null,
                padding: padding,
                itemCount: lens + 1, // Add 1 for bottom spacing
                itemBuilder: (context, index) {
                  // Last item is just spacing
                  if (index == lens) return SizedBox(height: 77);

                  final individualState = ref.watch(
                    serverProvider(serversInThisColumn[index]),
                  );

                  return _buildEachServerCard(
                    individualState,
                  );
                },
              ),
            );
          }),
        );
      },
    );
  }

  Widget _buildEachServerCard(ServerState srv) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final failed = srv.conn == ServerConn.failed;
    final baseColor = scheme.surfaceContainerLow;
    final cardColor = Color.alphaBlend(
      failed
          ? Colors.orange.withAlpha(
              theme.brightness == Brightness.dark ? 18 : 10,
            )
          : scheme.primary.withAlpha(
              theme.brightness == Brightness.dark ? 16 : 9,
            ),
      baseColor,
    );
    final outlineColor = failed
        ? Color.lerp(scheme.outlineVariant, Colors.orange, 0.24)!.withAlpha(
            theme.brightness == Brightness.dark ? 92 : 76,
          )
        : scheme.outlineVariant.withAlpha(26);
    final shape = RoundedSuperellipseBorder(
      borderRadius: const BorderRadius.all(Radius.circular(28)),
      side: BorderSide(color: outlineColor, width: 0.7),
    );

    return Padding(
      key: Key(srv.spi.id + _tag.value),
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: AnimatedContainer(
        duration: Durations.medium2,
        curve: Curves.fastEaseInToSlowEaseOut,
        decoration: ShapeDecoration(
          color: cardColor,
          shape: shape,
          shadows: [
            BoxShadow(
              color: scheme.shadow.withAlpha(7),
              blurRadius: 12,
              offset: const Offset(0, 3),
            ),
          ],
        ),
        child: Material(
          type: MaterialType.transparency,
          shape: shape,
          clipBehavior: Clip.antiAlias,
          child: Stack(
            fit: StackFit.passthrough,
            children: [
              InkWell(
                customBorder: shape,
                onTap: () => _onTapCard(srv),
                onLongPress: () => _onLongPressCard(srv),
                child: Padding(
                  padding: EdgeInsets.only(
                    left: _cardPadSingle,
                    right: 3,
                    top: _cardPadSingle,
                    bottom: _cardPadSingle,
                  ),
                  child: _buildRealServerCard(srv),
                ),
              ),
              if (srv.conn == ServerConn.connecting ||
                  srv.conn == ServerConn.connected ||
                  srv.conn == ServerConn.loading)
                Positioned.fill(
                  child: IgnorePointer(child: _CardConnectionSweep(shape)),
                ),
            ],
          ),
        ),
      ),
    );
  }

  /// The child's width mat not equal to 1/4 of the screen width,
  /// so we need to wrap it with a SizedBox.
  Widget _wrapWithSizedbox(
    Widget child,
    double maxWidth, [
    bool circle = false,
  ]) {
    return LayoutBuilder(
      builder: (_, cons) {
        final width = (maxWidth - _cardPad) / 4;
        return SizedBox(width: width, child: child);
      },
    );
  }

  Widget _buildRealServerCard(ServerState srv) {
    final id = srv.spi.id;
    final cardStatus = _getCardNoti(id);
    final title = _buildServerCardTitle(srv);

    return cardStatus.listenVal((_) {
      final List<Widget> children = [title];
      if (srv.conn == ServerConn.finished) {
        if (cardStatus.value.flip) {
          children.add(_buildFlippedCard(srv));
        } else {
          children.add(_buildNormalCard(srv.status, srv.spi));
        }
      }

      final height = _calcCardHeight(srv.conn, cardStatus.value.flip);
      return AnimatedContainer(
        duration: const Duration(milliseconds: 377),
        curve: Curves.fastEaseInToSlowEaseOut,
        height: height,
        // Use [OverflowBox] to dismiss the warning of [Column] overflow.
        child: OverflowBox(
          // If `height == _kCardHeightMin`, the `maxHeight` will be ignored.
          //
          // You can comment the `maxHeight` then connect&disconnect the server
          // to see the difference.
          maxHeight: height != _kCardHeightMin ? height : null,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.center,
            children: children,
          ),
        ),
      );
    });
  }

  Widget _buildFlippedCard(ServerState srv) {
    const color = Colors.grey;
    const textStyle = TextStyle(fontSize: 13, color: color);
    final children = [
      Btn.column(
        onTap: () => _onTapSuspend(srv),
        icon: const Icon(Icons.stop, color: color),
        text: libL10n.suspend,
        textStyle: textStyle,
      ),
      Btn.column(
        onTap: () => _onTapShutdown(srv),
        icon: const Icon(Icons.power_off, color: color),
        text: libL10n.shutdown,
        textStyle: textStyle,
      ),
      Btn.column(
        onTap: () => _onTapReboot(srv),
        icon: const Icon(Icons.restart_alt, color: color),
        text: libL10n.reboot,
        textStyle: textStyle,
      ),
      Btn.column(
        onTap: () => ServerEditPage.route.go(context, args: SpiRequiredArgs(srv.spi)),
        icon: const Icon(Icons.edit, color: color),
        text: libL10n.edit,
        textStyle: textStyle,
      ),
    ];

    return Padding(
      padding: const EdgeInsets.only(top: 9),
      child: LayoutBuilder(
        builder: (_, cons) {
          final width = (cons.maxWidth - _cardPad) / children.length;
          return Row(
            mainAxisAlignment: MainAxisAlignment.spaceAround,
            children: children.map((e) {
              if (width == 0) return e;
              return SizedBox(width: width, child: e);
            }).toList(),
          );
        },
      ),
    );
  }

  Widget _buildNormalCard(ServerStatus ss, Spi spi) {
    return LayoutBuilder(
      builder: (_, cons) {
        final maxWidth = cons.maxWidth;
        return Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            UIs.height13,
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                _wrapWithSizedbox(
                  PercentCircle(percent: ss.cpu.usedPercent()),
                  maxWidth,
                  true,
                ),
                _wrapWithSizedbox(
                  PercentCircle(percent: ss.mem.usedPercent * 100),
                  maxWidth,
                  true,
                ),
                _wrapWithSizedbox(_buildNet(ss, spi.id), maxWidth),
                _wrapWithSizedbox(_buildDisk(ss, spi.id), maxWidth),
              ],
            ),
            UIs.height13,
            if (Stores.setting.moveServerFuncs.fetch())
              SizedBox(height: 27, child: ServerFuncBtns(spi: spi)),
          ],
        );
      },
    );
  }

  @override
  bool get wantKeepAlive => true;

  @override
  Future<void> afterFirstLayout(BuildContext context) async {
    ref.read(serversProvider.notifier).refresh();
    ref.read(serversProvider.notifier).startAutoRefresh();
  }

  static const _kCardHeightMin = 23.0;
  static const _kCardHeightFlip = 99.0;
  static const _kCardHeightNormal = 110.0;
  static const _kCardHeightMoveOutFuncs = 135.0;
}

final class _CardConnectionSweep extends StatefulWidget {
  final ShapeBorder shape;

  const _CardConnectionSweep(this.shape);

  @override
  State<_CardConnectionSweep> createState() => _CardConnectionSweepState();
}

final class _CardConnectionSweepState extends State<_CardConnectionSweep>
    with SingleTickerProviderStateMixin {
  late final AnimationController _controller = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 3600),
  )..repeat();

  late final Animation<double> _travel = CurvedAnimation(
    parent: _controller,
    curve: const Interval(0, 0.84, curve: Curves.easeInOutSine),
  );

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    return ClipPath(
      clipper: ShapeBorderClipper(shape: widget.shape),
      child: LayoutBuilder(
        builder: (context, constraints) {
          final bandWidth = math.min(168.0, constraints.maxWidth * 0.55);
          return AnimatedBuilder(
            animation: _travel,
            builder: (context, child) {
              final left =
                  -bandWidth +
                  (constraints.maxWidth + bandWidth * 2) * _travel.value;
              return Stack(
                children: [
                  Positioned(
                    left: left,
                    top: -24,
                    bottom: -24,
                    width: bandWidth,
                    child: Transform.rotate(
                      angle: -0.035,
                      child: ImageFiltered(
                        imageFilter: ImageFilter.blur(
                          sigmaX: 20,
                          sigmaY: 7,
                        ),
                        child: DecoratedBox(
                          decoration: BoxDecoration(
                            gradient: LinearGradient(
                              colors: [
                                Colors.transparent,
                                scheme.primary.withAlpha(3),
                                Colors.white.withAlpha(
                                  theme.brightness == Brightness.dark ? 22 : 58,
                                ),
                                scheme.primary.withAlpha(5),
                                Colors.transparent,
                              ],
                              stops: const [0, 0.2, 0.5, 0.8, 1],
                            ),
                          ),
                        ),
                      ),
                    ),
                  ),
                ],
              );
            },
          );
        },
      ),
    );
  }
}
