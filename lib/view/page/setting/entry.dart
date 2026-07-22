import 'dart:convert';
import 'dart:io';

import 'package:dynamic_color/dynamic_color.dart';
import 'package:file_picker/file_picker.dart';
import 'package:fl_lib/fl_lib.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_highlight/theme_map.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:icons_plus/icons_plus.dart';
import 'package:server_box/core/extension/context/locale.dart';
import 'package:server_box/core/utils/server_dedup.dart';
import 'package:server_box/core/utils/ssh_config.dart';
import 'package:server_box/data/model/app/net_view.dart';
import 'package:server_box/data/model/server/discovery_result.dart';
import 'package:server_box/data/model/server/server_private_info.dart';
import 'package:server_box/data/provider/server/all.dart';
import 'package:server_box/data/res/build_data.dart';
import 'package:server_box/data/res/github_id.dart';
import 'package:server_box/data/res/store.dart';
import 'package:server_box/data/res/url.dart';
import 'package:server_box/data/store/setting.dart';
import 'package:server_box/generated/l10n/l10n.dart';
import 'package:server_box/view/page/backup.dart';
import 'package:server_box/view/page/private_key/list.dart';
import 'package:server_box/view/page/server/connection_stats.dart';
import 'package:server_box/view/page/server/discovery/discovery.dart';
import 'package:server_box/view/page/setting/entries/home_tabs.dart';
import 'package:server_box/view/page/setting/platform/ios.dart';
import 'package:server_box/view/page/setting/platform/platform_pub.dart';
import 'package:server_box/view/page/setting/seq/srv_detail_seq.dart';
import 'package:server_box/view/page/setting/seq/srv_func_seq.dart';
import 'package:server_box/view/page/setting/seq/srv_seq.dart';
import 'package:server_box/view/page/setting/seq/virt_key.dart';

part 'about.dart';
part 'entries/ai.dart';
part 'entries/app.dart';
part 'entries/container.dart';
part 'entries/editor.dart';
part 'entries/full_screen.dart';
part 'entries/server.dart';
part 'entries/sftp.dart';
part 'entries/ssh.dart';

const _kIconSize = 23.0;

class SettingsPage extends ConsumerStatefulWidget {
  const SettingsPage({super.key});

  static const route = AppRouteNoArg(page: SettingsPage.new, path: '/settings');

  @override
  ConsumerState<SettingsPage> createState() => _SettingsPageState();
}

class _SettingsPageState extends ConsumerState<SettingsPage>
    with SingleTickerProviderStateMixin {
  late final _tabCtrl = TabController(
    length: SettingsTabs.values.length,
    vsync: this,
  );

  void _clearAllSettings() {
    final keys = SettingStore.instance.box.keys;
    SettingStore.instance.box.deleteAll(keys);
    context.showSnackBar(libL10n.success);
  }

  @override
  void dispose() {
    _tabCtrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Scaffold(
      appBar: CustomAppBar(
        centerTitle: false,
        title: Text(
          libL10n.setting,
          style: Theme.of(context).textTheme.titleLarge?.copyWith(
            fontWeight: FontWeight.w800,
            letterSpacing: -0.25,
          ),
        ),
        bottom: PreferredSize(
          preferredSize: const Size.fromHeight(54),
          child: Padding(
            padding: const EdgeInsets.fromLTRB(12, 2, 12, 8),
            child: DecoratedBox(
              decoration: ShapeDecoration(
                color: scheme.surfaceContainerHigh,
                shape: const StadiumBorder(),
              ),
              child: TabBar(
                controller: _tabCtrl,
                dividerHeight: 0,
                tabAlignment: TabAlignment.center,
                isScrollable: true,
                splashFactory: NoSplash.splashFactory,
                overlayColor: const WidgetStatePropertyAll(
                  Colors.transparent,
                ),
                labelColor: scheme.onSecondaryContainer,
                unselectedLabelColor: scheme.onSurfaceVariant,
                indicatorSize: TabBarIndicatorSize.tab,
                indicator: ShapeDecoration(
                  color: scheme.secondaryContainer,
                  shape: const StadiumBorder(),
                ),
                tabs: SettingsTabs.values
                    .map(
                      (e) => SizedBox(
                        height: 40,
                        child: Center(child: Text(e.i18n)),
                      ),
                    )
                    .toList(growable: false),
              ),
            ),
          ),
        ),
        actions: [
          PopupMenuButton<_SettingsMenuAction>(
            tooltip: MaterialLocalizations.of(context).moreButtonTooltip,
            icon: const Icon(Icons.more_vert_rounded),
            onSelected: _onMenuAction,
            itemBuilder: (context) => [
              PopupMenuItem(
                value: _SettingsMenuAction.logs,
                child: ListTile(
                  leading: const Icon(Icons.receipt_long_rounded),
                  title: Text(context.libL10n.logs),
                ),
              ),
              PopupMenuItem(
                value: _SettingsMenuAction.reset,
                child: ListTile(
                  leading: Icon(
                    Icons.delete_sweep_rounded,
                    color: scheme.error,
                  ),
                  title: Text(
                    '${libL10n.delete} ${libL10n.all}',
                    style: TextStyle(color: scheme.error),
                  ),
                ),
              ),
            ],
          ),
        ],
      ),
      body: SafeArea(
        child: TabBarView(controller: _tabCtrl, children: SettingsTabs.pages),
      ),
    );
  }

  void _onMenuAction(_SettingsMenuAction action) {
    switch (action) {
      case _SettingsMenuAction.logs:
        DebugPage.route.go(
          context,
          args: DebugPageArgs(
            title: '${context.libL10n.logs}(${BuildData.build})',
          ),
        );
      case _SettingsMenuAction.reset:
        context.showRoundDialog(
          title: libL10n.attention,
          child: SimpleMarkdown(
            data: libL10n.askContinue(
              '${libL10n.delete} **${libL10n.all}** ${libL10n.setting}',
            ),
          ),
          actions: [
            CountDownBtn(
              onTap: () {
                context.pop();
                _clearAllSettings();
              },
              afterColor: Colors.red,
            ),
          ],
        );
    }
  }
}

enum _SettingsMenuAction { logs, reset }

final class AppSettingsPage extends ConsumerStatefulWidget {
  const AppSettingsPage({super.key});

  @override
  ConsumerState<AppSettingsPage> createState() => _AppSettingsPageState();
}

final class _AppSettingsPageState extends ConsumerState<AppSettingsPage> {
  final _setting = Stores.setting;

  late final _sshOpacityCtrl = TextEditingController(
    text: _setting.sshBgOpacity.fetch().toString(),
  );
  late final _sshBlurCtrl = TextEditingController(
    text: _setting.sshBlurRadius.fetch().toString(),
  );
  late final _textScalerCtrl = TextEditingController(
    text: _setting.textFactor.toString(),
  );
  late final _serverLogoCtrl = TextEditingController(
    text: _setting.serverLogoUrl.fetch(),
  );

  @override
  void dispose() {
    _sshOpacityCtrl.dispose();
    _sshBlurCtrl.dispose();
    _textScalerCtrl.dispose();
    _serverLogoCtrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final sections = <_SettingsSectionSpec>[
      _SettingsSectionSpec(
        title: libL10n.app,
        icon: Icons.tune_rounded,
        bodyBuilder: (_) => _buildApp(),
        initiallyExpanded: true,
      ),
      _SettingsSectionSpec(
        title: l10n.ai,
        icon: Icons.auto_awesome_rounded,
        bodyBuilder: (_) => _buildAskAiConfig(),
      ),
      _SettingsSectionSpec(
        title: libL10n.server,
        icon: Icons.dns_rounded,
        bodyBuilder: (_) => _buildServer(),
      ),
      _SettingsSectionSpec(
        title: l10n.ssh,
        icon: Icons.terminal_rounded,
        bodyBuilder: (_) => _buildSSH(),
      ),
      _SettingsSectionSpec(
        title: l10n.sftp,
        icon: Icons.folder_open_rounded,
        bodyBuilder: (_) => _buildSFTP(),
      ),
      _SettingsSectionSpec(
        title: libL10n.editor,
        icon: Icons.edit_note_rounded,
        bodyBuilder: (_) => _buildEditor(),
      ),
      _SettingsSectionSpec(
        title: libL10n.container,
        icon: Icons.inventory_2_rounded,
        bodyBuilder: (_) => _buildContainer(),
      ),
      if (isMobile)
        _SettingsSectionSpec(
          title: l10n.fullScreen,
          icon: Icons.fullscreen_rounded,
          bodyBuilder: (_) => _buildFullScreen(),
        ),
    ];

    return ListView.builder(
      padding: const EdgeInsets.fromLTRB(12, 12, 12, 28),
      scrollCacheExtent: const ScrollCacheExtent.pixels(240),
      keyboardDismissBehavior: ScrollViewKeyboardDismissBehavior.onDrag,
      itemCount: sections.length,
      itemBuilder: (context, index) => Padding(
        padding: const EdgeInsets.only(bottom: 10),
        child: _SettingsSection(
          spec: sections[index],
          toneIndex: index,
        ),
      ),
    );
  }

  Future<void> showTextSettingDialog({
    required String title,
    required String initialValue,
    required String label,
    required String hint,
    required IconData icon,
    required ValueChanged<String> onSave,
    bool suggestion = false,
  }) {
    return Future<void>.sync(
      () => withTextFieldController((ctrl) async {
        ctrl.text = initialValue;

        void save() {
          onSave(ctrl.text.trim());
          context.pop();
        }

        await context.showRoundDialog<bool>(
          title: title,
          child: Input(
            controller: ctrl,
            autoFocus: true,
            label: label,
            hint: hint,
            icon: icon,
            suggestion: suggestion,
            onSubmitted: (_) => save(),
          ),
          actions: Btn.ok(onTap: save).toList,
        );
      }),
    );
  }
}

final class _SettingsSectionSpec {
  const _SettingsSectionSpec({
    required this.title,
    required this.icon,
    required this.bodyBuilder,
    this.initiallyExpanded = false,
  });

  final String title;
  final IconData icon;
  final WidgetBuilder bodyBuilder;
  final bool initiallyExpanded;
}

final class _SettingsSection extends StatelessWidget {
  const _SettingsSection({required this.spec, required this.toneIndex});

  final _SettingsSectionSpec spec;
  final int toneIndex;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final accent = switch (toneIndex % 3) {
      1 => scheme.tertiary,
      2 => scheme.secondary,
      _ => scheme.primary,
    };
    final shape = RoundedSuperellipseBorder(
      borderRadius: const BorderRadius.all(Radius.circular(26)),
      side: BorderSide(color: scheme.outlineVariant.withAlpha(46)),
    );

    return DecoratedBox(
      decoration: ShapeDecoration(
        color: Color.alphaBlend(
          accent.withAlpha(theme.brightness == Brightness.dark ? 12 : 7),
          scheme.surfaceContainerLow,
        ),
        shape: shape,
        shadows: [
          BoxShadow(
            color: scheme.shadow.withAlpha(6),
            blurRadius: 12,
            offset: const Offset(0, 3),
          ),
        ],
      ),
      child: Material(
        type: MaterialType.transparency,
        shape: shape,
        clipBehavior: Clip.antiAlias,
        child: ExpansionTile(
          initiallyExpanded: spec.initiallyExpanded,
          maintainState: false,
          tilePadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 3),
          childrenPadding: const EdgeInsets.fromLTRB(5, 0, 5, 8),
          backgroundColor: Colors.transparent,
          collapsedBackgroundColor: Colors.transparent,
          shape: const Border(),
          collapsedShape: const Border(),
          leading: DecoratedBox(
            decoration: ShapeDecoration(
              color: accent.withAlpha(
                theme.brightness == Brightness.dark ? 34 : 22,
              ),
              shape: const RoundedSuperellipseBorder(
                borderRadius: BorderRadius.all(Radius.circular(15)),
              ),
            ),
            child: SizedBox.square(
              dimension: 42,
              child: Icon(spec.icon, color: accent, size: 22),
            ),
          ),
          title: Text(
            spec.title,
            style: theme.textTheme.titleMedium?.copyWith(
              fontWeight: FontWeight.w700,
            ),
          ),
          children: [
            Divider(
              height: 1,
              indent: 12,
              endIndent: 12,
              color: scheme.outlineVariant.withAlpha(55),
            ),
            RepaintBoundary(
              child: Builder(builder: spec.bodyBuilder),
            ),
          ],
        ),
      ),
    );
  }
}

enum SettingsTabs {
  app,
  privateKey,
  backup,
  about;

  String get i18n => switch (this) {
    SettingsTabs.app => libL10n.app,
    SettingsTabs.privateKey => l10n.privateKey,
    SettingsTabs.backup => libL10n.backup,
    SettingsTabs.about => libL10n.about,
  };

  Widget get page => switch (this) {
    SettingsTabs.app => const AppSettingsPage(),
    SettingsTabs.privateKey => const PrivateKeysListPage(),
    SettingsTabs.backup => const BackupPage(),
    SettingsTabs.about => const _AppAboutPage(),
  };

  static final List<Widget> pages = SettingsTabs.values
      .map((e) => e.page)
      .toList();
}
