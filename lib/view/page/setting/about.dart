part of 'entry.dart';

const _sponsorUrl = 'https://cdn.lpkt.cn/donate';

final class _AppAboutPage extends StatefulWidget {
  const _AppAboutPage();

  @override
  State<_AppAboutPage> createState() => _AppAboutPageState();
}

final class _AppAboutPageState extends State<_AppAboutPage>
    with AutomaticKeepAliveClientMixin {
  @override
  Widget build(BuildContext context) {
    super.build(context);
    return SafeArea(
      child: ListView(
        padding: const EdgeInsets.fromLTRB(14, 18, 14, 28),
        children: [
          const _AboutNoticeCard(),
          const SizedBox(height: 14),
          const _AboutIdentityCard(),
          const SizedBox(height: 14),
          _AboutActionsCard(
            onLicense: () => showLicensePage(context: context),
          ),
          const SizedBox(height: 14),
          _AboutSurface(
            child: SimpleMarkdown(
              data:
                  '''
#### Contributors
${GithubIds.contributors.map((e) => e.markdownLink).join(' ')}

#### Participants
${GithubIds.participants.map((e) => e.markdownLink).join(' ')}

#### My other apps
[GPT Box](https://github.com/lollipopkit/flutter_gpt_box)

${l10n.madeWithLove('[lollipopkit](${Urls.myGithub})')}
''',
            ),
          ),
        ],
      ),
    );
  }

  @override
  bool get wantKeepAlive => true;
}

final class _AboutNoticeCard extends StatelessWidget {
  const _AboutNoticeCard();

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    return _AboutSurface(
      color: Color.alphaBlend(
        scheme.tertiary.withAlpha(theme.brightness == Brightness.dark ? 38 : 24),
        scheme.surfaceContainer,
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          DecoratedBox(
            decoration: ShapeDecoration(
              color: scheme.tertiaryContainer,
              shape: const RoundedSuperellipseBorder(
                borderRadius: BorderRadius.all(Radius.circular(18)),
              ),
            ),
            child: SizedBox.square(
              dimension: 48,
              child: Icon(
                Icons.info_outline_rounded,
                color: scheme.onTertiaryContainer,
              ),
            ),
          ),
          const SizedBox(width: 13),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  l10n.unofficialForkNoticeTitle,
                  style: theme.textTheme.titleMedium?.copyWith(
                    fontWeight: FontWeight.w800,
                  ),
                ),
                const SizedBox(height: 5),
                Text(
                  l10n.unofficialForkNoticeBody,
                  style: theme.textTheme.bodyMedium?.copyWith(
                    color: scheme.onSurfaceVariant,
                    height: 1.35,
                  ),
                ),
                const SizedBox(height: 9),
                Row(
                  children: [
                    Icon(
                      Icons.auto_awesome_rounded,
                      size: 17,
                      color: scheme.tertiary,
                    ),
                    const SizedBox(width: 6),
                    Expanded(
                      child: Text(
                        l10n.codexCustomizationNotice,
                        style: theme.textTheme.labelLarge?.copyWith(
                          color: scheme.tertiary,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

final class _AboutIdentityCard extends StatelessWidget {
  const _AboutIdentityCard();

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    return _AboutSurface(
      color: scheme.surfaceContainerLow,
      child: Row(
        children: [
          SizedBox.square(
            dimension: 64,
            child: UIs.appIcon,
          ),
          const SizedBox(width: 16),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  BuildData.name,
                  style: theme.textTheme.headlineSmall?.copyWith(
                    fontWeight: FontWeight.w800,
                    letterSpacing: -0.5,
                  ),
                ),
                const SizedBox(height: 3),
                Text(
                  'v1.0.${BuildData.build}',
                  style: theme.textTheme.bodyLarge?.copyWith(
                    color: scheme.onSurfaceVariant,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ],
            ),
          ),
          Icon(
            Icons.android_rounded,
            color: scheme.primary,
            size: 28,
          ),
        ],
      ),
    );
  }
}

final class _AboutActionsCard extends StatelessWidget {
  const _AboutActionsCard({required this.onLicense});

  final VoidCallback onLicense;

  @override
  Widget build(BuildContext context) {
    return _AboutSurface(
      color: Theme.of(context).colorScheme.surfaceContainerLow,
      padding: const EdgeInsets.all(8),
      child: LayoutBuilder(
        builder: (context, constraints) {
          const gap = 8.0;
          final itemWidth = constraints.maxWidth >= 520
              ? (constraints.maxWidth - gap * 3) / 4
              : (constraints.maxWidth - gap) / 2;
          return Wrap(
            spacing: gap,
            runSpacing: gap,
            children: [
              _AboutAction(
                width: itemWidth,
                icon: Icons.edit_document,
                label: l10n.wiki,
                onTap: Urls.appWiki.launchUrl,
              ),
              _AboutAction(
                width: itemWidth,
                icon: Icons.feedback_rounded,
                label: libL10n.feedback,
                onTap: Urls.appHelp.launchUrl,
              ),
              _AboutAction(
                width: itemWidth,
                icon: MingCute.question_fill,
                label: libL10n.license,
                onTap: onLicense,
              ),
              _AboutAction(
                width: itemWidth,
                icon: MingCute.heart_fill,
                label: l10n.sponsor,
                onTap: () => _sponsorUrl.launchUrl(),
              ),
            ],
          );
        },
      ),
    );
  }
}

final class _AboutAction extends StatelessWidget {
  const _AboutAction({
    required this.width,
    required this.icon,
    required this.label,
    required this.onTap,
  });

  final double width;
  final IconData icon;
  final String label;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final shape = RoundedSuperellipseBorder(
      borderRadius: const BorderRadius.all(Radius.circular(18)),
      side: BorderSide(color: scheme.outlineVariant.withAlpha(48)),
    );
    return SizedBox(
      width: width,
      height: 58,
      child: Material(
        color: scheme.surfaceContainerHigh.withAlpha(190),
        shape: shape,
        clipBehavior: Clip.antiAlias,
        child: InkWell(
          customBorder: shape,
          onTap: onTap,
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 13),
            child: Row(
              children: [
                Icon(icon, size: 21, color: scheme.primary),
                const SizedBox(width: 9),
                Expanded(
                  child: Text(
                    label,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: theme.textTheme.labelLarge?.copyWith(
                      fontWeight: FontWeight.w700,
                    ),
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

final class _AboutSurface extends StatelessWidget {
  const _AboutSurface({
    required this.child,
    this.color,
    this.padding = const EdgeInsets.all(16),
  });

  final Widget child;
  final Color? color;
  final EdgeInsetsGeometry padding;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return DecoratedBox(
      decoration: ShapeDecoration(
        color: color ?? scheme.surfaceContainerLow,
        shape: RoundedSuperellipseBorder(
          borderRadius: const BorderRadius.all(Radius.circular(26)),
          side: BorderSide(color: scheme.outlineVariant.withAlpha(45)),
        ),
      ),
      child: Padding(
        padding: padding,
        child: child,
      ),
    );
  }
}
