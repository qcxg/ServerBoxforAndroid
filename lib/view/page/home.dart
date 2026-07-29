import 'dart:async';
import 'dart:io';
import 'dart:ui';

import 'package:fl_lib/fl_lib.dart';
import 'package:flutter/foundation.dart' show kReleaseMode;
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:server_box/core/chan.dart';
import 'package:server_box/core/sync.dart';
import 'package:server_box/data/model/app/tab.dart';
import 'package:server_box/data/provider/server/all.dart';
import 'package:server_box/data/res/store.dart';
import 'package:server_box/view/page/home_tab.dart';
import 'package:server_box/view/page/macos_menu_bar.dart';
import 'package:server_box/view/page/setting/entry.dart';
import 'package:server_box/view/responsive_layout.dart';
import 'package:wakelock_plus/wakelock_plus.dart';

class HomePage extends ConsumerStatefulWidget {
  const HomePage({super.key});

  @override
  ConsumerState<HomePage> createState() => _HomePageState();

  static const route = AppRouteNoArg(page: HomePage.new, path: '/');
}

class _HomePageState extends ConsumerState<HomePage>
    with
        AutomaticKeepAliveClientMixin,
        AfterLayoutMixin,
        WidgetsBindingObserver,
        GlobalRef,
        RestorationMixin {
  // Restorable state for current tab index
  final RestorableInt _restorableTabIndex = RestorableInt(0);

  @override
  String get restorationId => 'home_page';

  @override
  void restoreState(RestorationBucket? oldBucket, bool initialRestore) {
    registerForRestoration(_restorableTabIndex, 'tab_index');
  }

  late final PageController _pageController;

  final _selectIndex = ValueNotifier(0);

  bool _switchingPage = false;
  bool _shouldAuth = false;
  bool? _lastFullscreenMode;
  DateTime? _pausedTime;

  late final _notifier = ref.read(serversProvider.notifier);
  late List<AppTab> _tabs = Stores.setting.homeTabs.fetch();

  @override
  void dispose() {
    _restorableTabIndex.dispose();
    if (isMobile) {
      SystemUIs.switchStatusBar(hide: false);
    }
    WidgetsBinding.instance.removeObserver(this);
    Stores.setting.homeTabs.listenable().removeListener(_handleHomeTabsChanged);
    Stores.setting.serverStatusUpdateInterval.listenable().removeListener(
      _handleRefreshIntervalChanged,
    );
    // In release builds (real app exit), close connections.
    // In debug (hot reload), avoid forcing disconnects.
    if (kReleaseMode) {
      Future(() => _notifier.closeServer());
    }
    _pageController.dispose();
    WakelockPlus.disable();

    _selectIndex.dispose();
    super.dispose();
  }

  @override
  void initState() {
    super.initState();
    SystemUIs.switchStatusBar(hide: false);
    WidgetsBinding.instance.addObserver(this);
    // avoid index out of range
    if (_selectIndex.value >= _tabs.length || _selectIndex.value < 0) {
      _selectIndex.value = 0;
    }
    _pageController = PageController(initialPage: _selectIndex.value);
    if (Stores.setting.generalWakeLock.fetch()) {
      WakelockPlus.enable();
    }

    // Listen to homeTabs changes
    Stores.setting.homeTabs.listenable().addListener(_handleHomeTabsChanged);
    Stores.setting.serverStatusUpdateInterval.listenable().addListener(
      _handleRefreshIntervalChanged,
    );
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    super.didChangeAppLifecycleState(state);
    if (isDesktop) return;

    switch (state) {
      case AppLifecycleState.resumed:
        _lastFullscreenMode = null;
        if (_shouldAuth) {
          final delay = Stores.setting.delayBioAuthLock.fetch();
          if (delay > 0 && _pausedTime != null) {
            final now = DateTime.now();
            if (now.difference(_pausedTime ?? now).inSeconds > delay) {
              _goAuth();
            } else {
              _shouldAuth = false;
            }
            _pausedTime = null;
          } else {
            _goAuth();
          }
        }
        final serverNotifier = _notifier;
        unawaited(serverNotifier.startAutoRefresh());
        unawaited(serverNotifier.refresh());
        unawaited(MethodChans.updateHomeWidget());
        _syncFullscreenSystemUi();
        break;
      case AppLifecycleState.paused:
        _lastFullscreenMode = null;
        _pausedTime = DateTime.now();
        _shouldAuth = true;
        if (!(isAndroid && Stores.setting.bgRun.fetch())) {
          _notifier.stopAutoRefresh();
        }
        break;
      default:
        break;
    }
  }

  @override
  Widget build(BuildContext context) {
    super.build(context);
    final width = MediaQuery.sizeOf(context).width;
    final useBottomNavigation = AppLayout.useCompactNavigation(width);
    _syncFullscreenSystemUi();

    final Widget mainContent = ListenableBuilder(
      listenable: _selectIndex,
      builder: (context, _) {
        final selectedIndex = _selectIndex.value;
        final serverUsesStatusGlass =
            AppLayout.useStatusGlass(width) &&
            selectedIndex >= 0 &&
            selectedIndex < _tabs.length &&
            _tabs[selectedIndex] == AppTab.server;
        return Scaffold(
          // The home shell itself never owns a text field. Let nested pages
          // handle their keyboards without allowing a stale Android IME inset
          // to permanently shorten the tab viewport after a route is popped.
          resizeToAvoidBottomInset: false,
          extendBody: isMobile,
          extendBodyBehindAppBar: serverUsesStatusGlass,
          appBar: _AppBar(
            MediaQuery.paddingOf(context).top,
            paintGlass: !serverUsesStatusGlass,
          ),
          body: Row(
            children: [
              if (!useBottomNavigation) _buildRailBar(),
              Expanded(
                child: PageView.builder(
                  controller: _pageController,
                  itemCount: _tabs.length,
                  physics: const NeverScrollableScrollPhysics(),
                  itemBuilder: (_, index) => _tabs[index].page,
                  onPageChanged: (value) {
                    FocusScope.of(context).unfocus();
                    if (!_switchingPage) {
                      _selectIndex.value = value;
                      _restorableTabIndex.value = value;
                    }
                    _syncFullscreenSystemUi();
                  },
                ),
              ),
            ],
          ),
          bottomNavigationBar: useBottomNavigation ? _buildBottomBar() : null,
        );
      },
    );

    if (Platform.isMacOS) {
      return PlatformMenuBar(
        menus: MacOSMenuBarManager.buildMenuBar(
          context,
          _onDestinationSelected,
        ),
        child: mainContent,
      );
    }
    return mainContent;
  }

  Widget _buildBottomBar() {
    return ListenableBuilder(
      listenable: _selectIndex,
      builder: (context, child) {
        if (_isServerFullscreenMode) return UIs.placeholder;
        return _FloatingHomeNavigation(
          tabs: _tabs,
          selectedIndex: _selectIndex.value,
          onDestinationSelected: _onDestinationSelected,
        );
      },
    );
  }

  Widget _buildRailBar() {
    return ListenableBuilder(
      listenable: _selectIndex,
      builder: (context, _) {
        if (_isServerFullscreenMode) return UIs.placeholder;
        return _ExpressiveSideNavigation(
          tabs: _tabs,
          selectedIndex: _selectIndex.value,
          onDestinationSelected: _onDestinationSelected,
          onSettings: () => SettingsPage.route.go(context),
        );
      },
    );
  }

  @override
  bool get wantKeepAlive => true;

  @override
  Future<void> afterFirstLayout(BuildContext context) async {
    // Auth required for first launch
    // Restore tab index from restoration if available
    if (_restorableTabIndex.value >= 0 && _restorableTabIndex.value < _tabs.length) {
      _selectIndex.value = _restorableTabIndex.value;
      if (_pageController.hasClients) {
        _pageController.jumpToPage(_restorableTabIndex.value);
      }
    }
    _goAuth();

    unawaited(MethodChans.updateHomeWidget());
    await _notifier.refresh();

    bakSync.sync(milliDelay: 1000);
  }

  void _goAuth() {
    if (Stores.setting.useBioAuth.fetch()) {
      if (LocalAuthPage.route.alreadyIn) return;
      LocalAuthPage.route.go(
        context,
        args: LocalAuthPageArgs(onAuthSuccess: () => _shouldAuth = false),
      );
    }
  }

  void _onDestinationSelected(int index) {
    if (_selectIndex.value == index) return;
    if (index < 0 || index >= _tabs.length) return;
    _selectIndex.value = index;
    _restorableTabIndex.value = index;
    _switchingPage = true;
    _pageController.animateToPage(
      index,
      duration: const Duration(milliseconds: 677),
      curve: Curves.fastLinearToSlowEaseIn,
    );
    Future.delayed(const Duration(milliseconds: 677), () {
      _switchingPage = false;
    });
  }

  bool get _isServerFullscreenMode {
    if (!Stores.setting.fullScreen.fetch()) return false;
    if (_tabs.isEmpty) return false;
    final selectedIndex = _selectIndex.value;
    if (selectedIndex < 0 || selectedIndex >= _tabs.length) return false;
    final isLandscape =
        MediaQuery.orientationOf(context) == Orientation.landscape;
    return isLandscape && _tabs[selectedIndex] == AppTab.server;
  }

  void _syncFullscreenSystemUi({bool? forceHide}) {
    if (!isMobile) return;
    final hide = forceHide ?? _isServerFullscreenMode;
    if (_lastFullscreenMode == hide) return;
    _lastFullscreenMode = hide;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      SystemUIs.switchStatusBar(hide: hide);
    });
  }
}

final class _ExpressiveSideNavigation extends StatelessWidget {
  const _ExpressiveSideNavigation({
    required this.tabs,
    required this.selectedIndex,
    required this.onDestinationSelected,
    required this.onSettings,
  });

  final List<AppTab> tabs;
  final int selectedIndex;
  final ValueChanged<int> onDestinationSelected;
  final VoidCallback onSettings;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    if (tabs.isEmpty) return const SizedBox(width: 92);
    final selected = selectedIndex.clamp(0, tabs.length - 1);
    return Material(
      color: Color.alphaBlend(
        scheme.primary.withAlpha(5),
        scheme.surfaceContainerLow,
      ),
      child: SafeArea(
        right: false,
        child: SizedBox(
          width: 92,
          child: DecoratedBox(
            decoration: BoxDecoration(
              border: Border(
                right: BorderSide(
                  color: scheme.outlineVariant.withAlpha(70),
                  width: 0.8,
                ),
              ),
            ),
            child: Column(
              children: [
                const SizedBox(height: 12),
                Expanded(
                  child: ListView.builder(
                    padding: const EdgeInsets.symmetric(horizontal: 8),
                    itemCount: tabs.length,
                    itemBuilder: (context, index) {
                      final destination = tabs[index].navDestination;
                      return Padding(
                        padding: const EdgeInsets.only(bottom: 6),
                        child: _SideNavigationItem(
                          label: destination.label,
                          icon: destination.icon,
                          selectedIcon:
                              destination.selectedIcon ?? destination.icon,
                          selected: selected == index,
                          onTap: () => onDestinationSelected(index),
                        ),
                      );
                    },
                  ),
                ),
                Padding(
                  padding: const EdgeInsets.fromLTRB(8, 6, 8, 10),
                  child: _SideNavigationItem(
                    label: libL10n.setting,
                    icon: const Icon(Icons.settings_outlined),
                    selectedIcon: const Icon(Icons.settings_rounded),
                    selected: false,
                    onTap: onSettings,
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

final class _SideNavigationItem extends StatelessWidget {
  const _SideNavigationItem({
    required this.label,
    required this.icon,
    required this.selectedIcon,
    required this.selected,
    required this.onTap,
  });

  final String label;
  final Widget icon;
  final Widget selectedIcon;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final foreground = selected
        ? scheme.onSecondaryContainer
        : scheme.onSurfaceVariant;
    final shape = RoundedSuperellipseBorder(
      borderRadius: const BorderRadius.all(Radius.circular(18)),
      side: BorderSide(
        color: selected
            ? scheme.outlineVariant.withAlpha(75)
            : Colors.transparent,
        width: 0.7,
      ),
    );
    return Semantics(
      button: true,
      selected: selected,
      label: label,
      child: Material(
        color: Colors.transparent,
        shape: shape,
        clipBehavior: Clip.antiAlias,
        child: InkWell(
          customBorder: shape,
          splashFactory: NoSplash.splashFactory,
          overlayColor: const WidgetStatePropertyAll(Colors.transparent),
          onTap: onTap,
          child: AnimatedContainer(
            height: 66,
            duration: Durations.medium2,
            curve: Curves.fastEaseInToSlowEaseOut,
            decoration: ShapeDecoration(
              color: selected
                  ? scheme.secondaryContainer.withAlpha(205)
                  : Colors.transparent,
              shape: shape,
            ),
            child: Stack(
              children: [
                AnimatedPositionedDirectional(
                  duration: Durations.medium2,
                  curve: Curves.fastEaseInToSlowEaseOut,
                  start: selected ? 0 : -4,
                  top: 18,
                  bottom: 18,
                  child: AnimatedOpacity(
                    duration: Durations.short4,
                    opacity: selected ? 1 : 0,
                    child: Container(
                      width: 3,
                      decoration: BoxDecoration(
                        color: scheme.primary,
                        borderRadius: BorderRadius.circular(3),
                      ),
                    ),
                  ),
                ),
                Center(
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      IconTheme(
                        data: IconThemeData(color: foreground, size: 22),
                        child: selected ? selectedIcon : icon,
                      ),
                      const SizedBox(height: 4),
                      Text(
                        label,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: Theme.of(context).textTheme.labelSmall?.copyWith(
                          color: foreground,
                          fontWeight: selected
                              ? FontWeight.w700
                              : FontWeight.w600,
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

final class _AppBar extends StatelessWidget implements PreferredSizeWidget {
  final double paddingTop;
  final bool paintGlass;

  const _AppBar(this.paddingTop, {required this.paintGlass});

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final overlayStyle = Theme.of(context).brightness == Brightness.dark
        ? SystemUiOverlayStyle.light
        : SystemUiOverlayStyle.dark;
    return AnnotatedRegion<SystemUiOverlayStyle>(
      value: overlayStyle.copyWith(
        statusBarColor: Colors.transparent,
        systemStatusBarContrastEnforced: false,
      ),
      child: SizedBox(
        height: preferredSize.height,
        child: paintGlass
            ? ClipRect(
                child: BackdropFilter(
                  filter: ImageFilter.blur(sigmaX: 18, sigmaY: 18),
                  child: DecoratedBox(
                    decoration: BoxDecoration(
                      color: scheme.surface.withAlpha(148),
                      border: Border(
                        bottom: BorderSide(
                          color: scheme.outlineVariant.withAlpha(42),
                          width: 0.7,
                        ),
                      ),
                    ),
                  ),
                ),
              )
            : const ColoredBox(color: Colors.transparent),
      ),
    );
  }

  @override
  Size get preferredSize {
    return Size.fromHeight(paddingTop);
  }
}

final class _FloatingHomeNavigation extends StatelessWidget {
  const _FloatingHomeNavigation({
    required this.tabs,
    required this.selectedIndex,
    required this.onDestinationSelected,
  });

  final List<AppTab> tabs;
  final int selectedIndex;
  final ValueChanged<int> onDestinationSelected;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final foreground = scheme.onSurfaceVariant.withAlpha(224);
    const stadium = StadiumBorder();
    if (tabs.isEmpty) return const SizedBox.shrink();

    final indicatorIndex = selectedIndex.clamp(0, tabs.length - 1);
    final direction = Directionality.of(context);
    final textScaler = MediaQuery.textScalerOf(context);
    final baseStyle = theme.textTheme.labelMedium;
    final labelWidths = tabs.map((tab) {
      final destination = tab.navDestination;
      final regular = _measureLabel(
        destination.label,
        baseStyle?.copyWith(fontWeight: FontWeight.w600),
        direction,
        textScaler,
      );
      final selected = _measureLabel(
        destination.label,
        baseStyle?.copyWith(fontWeight: FontWeight.w700),
        direction,
        textScaler,
      );
      return regular > selected ? regular : selected;
    }).toList(growable: false);

    final maxNavWidth = (MediaQuery.sizeOf(context).width - 40).clamp(
      0.0,
      520.0,
    );
    final baseWidth = labelWidths.fold<double>(24, (sum, width) => sum + width);
    final horizontalSpace = ((maxNavWidth - 8 - baseWidth) / tabs.length)
        .clamp(12.0, 28.0);
    var itemWidths = List<double>.generate(
      tabs.length,
      (index) =>
          labelWidths[index] + horizontalSpace + (index == indicatorIndex ? 24 : 0),
      growable: false,
    );
    final desiredContentWidth = itemWidths.fold<double>(0, (a, b) => a + b);
    final maxContentWidth = maxNavWidth - 8;
    if (desiredContentWidth > maxContentWidth && desiredContentWidth > 0) {
      final scale = maxContentWidth / desiredContentWidth;
      itemWidths = itemWidths.map((width) => width * scale).toList(growable: false);
    }
    final navWidth = itemWidths.fold<double>(8, (sum, width) => sum + width);
    final indicatorStart = itemWidths
        .take(indicatorIndex)
        .fold<double>(4, (sum, width) => sum + width);

    return SafeArea(
      top: false,
      minimum: const EdgeInsets.fromLTRB(20, 0, 20, 8),
      child: Align(
        heightFactor: 1,
        child: AnimatedContainer(
          width: navWidth,
          height: 60,
          duration: Durations.medium2,
          curve: Curves.fastEaseInToSlowEaseOut,
          decoration: ShapeDecoration(
            color: Colors.transparent,
            shape: stadium,
            shadows: [
              BoxShadow(
                color: scheme.shadow.withAlpha(22),
                blurRadius: 18,
                offset: const Offset(0, 6),
              ),
            ],
          ),
          child: ClipPath(
            clipper: const ShapeBorderClipper(shape: stadium),
            child: BackdropFilter(
              filter: ImageFilter.blur(sigmaX: 18, sigmaY: 18),
              child: Stack(
                fit: StackFit.expand,
                children: [
                  DecoratedBox(
                    decoration: ShapeDecoration(
                      color: scheme.surface.withAlpha(148),
                      shape: StadiumBorder(
                        side: BorderSide(
                          color: scheme.outlineVariant.withAlpha(54),
                          width: 0.7,
                        ),
                      ),
                    ),
                  ),
                  AnimatedPositionedDirectional(
                    start: indicatorStart,
                    top: 9,
                    width: itemWidths[indicatorIndex] - 8,
                    height: 42,
                    duration: Durations.medium2,
                    curve: Curves.fastEaseInToSlowEaseOut,
                    child: IgnorePointer(
                      child: DecoratedBox(
                        decoration: ShapeDecoration(
                          color: scheme.surfaceContainerHighest.withAlpha(190),
                          shape: stadium,
                        ),
                      ),
                    ),
                  ),
                  Row(
                    mainAxisSize: MainAxisSize.min,
                    children: List.generate(tabs.length, (index) {
                      final destination = tabs[index].navDestination;
                      final selected = indicatorIndex == index;
                      return AnimatedContainer(
                        width: itemWidths[index],
                        duration: Durations.medium2,
                        curve: Curves.fastEaseInToSlowEaseOut,
                        child: Semantics(
                          button: true,
                          selected: selected,
                          label: destination.label,
                          child: Material(
                            type: MaterialType.transparency,
                            child: InkWell(
                              customBorder: stadium,
                              overlayColor: const WidgetStatePropertyAll(
                                Colors.transparent,
                              ),
                              splashFactory: NoSplash.splashFactory,
                              onTap: () => onDestinationSelected(index),
                              child: Center(
                                child: AnimatedSwitcher(
                                  duration: Durations.short4,
                                  child: IconTheme(
                                    data: IconThemeData(
                                      size: 20,
                                      color: foreground,
                                    ),
                                    child: selected
                                        ? Row(
                                            key: ValueKey('selected-$index'),
                                            mainAxisSize: MainAxisSize.min,
                                            children: [
                                              destination.selectedIcon ??
                                                  destination.icon,
                                              const SizedBox(width: 4),
                                              Text(
                                                destination.label,
                                                maxLines: 1,
                                                softWrap: false,
                                                style: baseStyle?.copyWith(
                                                  color: foreground,
                                                  fontWeight: FontWeight.w700,
                                                ),
                                              ),
                                            ],
                                          )
                                        : Text(
                                            destination.label,
                                            key: ValueKey(
                                              'unselected-$index',
                                            ),
                                            maxLines: 1,
                                            softWrap: false,
                                            style: baseStyle?.copyWith(
                                              color: foreground,
                                              fontWeight: FontWeight.w600,
                                            ),
                                          ),
                                  ),
                                ),
                              ),
                            ),
                          ),
                        ),
                      );
                    }),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }

  static double _measureLabel(
    String label,
    TextStyle? style,
    TextDirection direction,
    TextScaler textScaler,
  ) {
    final painter = TextPainter(
      text: TextSpan(text: label, style: style),
      textDirection: direction,
      textScaler: textScaler,
      maxLines: 1,
    )..layout();
    return painter.width;
  }
}

extension _HomePageStateActions on _HomePageState {
  void _handleHomeTabsChanged() {
    final newTabs = Stores.setting.homeTabs.fetch();
    if (!mounted || newTabs == _tabs) return;

    final previousIndex = _selectIndex.value;
    final clampedIndex = newTabs.isEmpty
        ? 0
        : previousIndex.clamp(0, newTabs.length - 1);

    // ignore: invalid_use_of_protected_member
    setState(() {
      _tabs = newTabs;
      _selectIndex.value = clampedIndex;
      _restorableTabIndex.value = clampedIndex;
    });

    if (clampedIndex != previousIndex && _pageController.hasClients) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (!_pageController.hasClients) return;
        _pageController.jumpToPage(clampedIndex);
      });
    }
  }

  void _handleRefreshIntervalChanged() {
    final lifecycle = WidgetsBinding.instance.lifecycleState;
    if (isDesktop ||
        lifecycle == null ||
        lifecycle == AppLifecycleState.resumed) {
      unawaited(_notifier.startAutoRefresh());
      unawaited(_notifier.refresh());
    }
  }
}
