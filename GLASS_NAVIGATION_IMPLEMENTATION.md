# Floating Glass Navigation Bar — Flutter Implementation Guide

This document specifies how to reproduce the floating glass bottom navigation bar used by the customized ServerBox Android application. It is written as a self-contained implementation handoff for another engineer or coding model.

The component is inspired by the compact/short navigation treatment used by recent Material 3 Expressive applications. It is not Flutter's standard `NavigationBar`: the required shape, adaptive width, label behavior, glass rendering, and single moving selection capsule are composed from standard Flutter primitives.

## 1. Target behavior

The finished component must have these properties:

- It floats above page content instead of occupying an opaque full-width strip.
- The outer bar is one compact `StadiumBorder` glass capsule.
- Its width follows the actual localized label widths rather than dividing the screen into equal destinations.
- It supports approximately two to five destinations. Four is the reference layout.
- The selected destination contains its selected icon and label.
- Unselected destinations show labels only in the reference design.
- There is exactly one selection indicator in the entire bar.
- The selection indicator is a filled capsule behind the selected destination and moves horizontally when selection changes.
- Destination widths animate together with the indicator because the selected destination needs extra width for its icon.
- Tapping must not create a Material ripple, press halo, extra circle, or second shadow.
- Content remains visible through the glass and may scroll behind it.
- The final scrollable item must still be able to stop above the navigation overlay.
- The foreground icon and label remain readable; do not apply opacity to the complete widget tree.
- The geometry must work in both left-to-right and right-to-left layouts.
- Label measurement must honor the current text scale factor.

## 2. Reference visual constants

The proven ServerBox implementation uses the following values. Treat them as a coherent preset rather than independent arbitrary numbers.

| Property | Value | Purpose |
| --- | ---: | --- |
| Outer height | `60 dp` | Compact floating bar height |
| Outer shape | `StadiumBorder` | True capsule with straight middle edges |
| Maximum width | `520 dp` | Prevents an excessively wide bar on tablets |
| Screen side margin | `20 dp` | Leaves the bar visibly floating |
| Bottom minimum inset | `8 dp` | Additional visual separation from the bottom safe area |
| Outer internal horizontal inset | `4 dp` per side | Positions items and indicator inside the border |
| Indicator top | `9 dp` | Vertically centers a 42 dp indicator inside 60 dp |
| Indicator height | `42 dp` | Compact selected capsule |
| Indicator horizontal inset | `4 dp` per selected item side | Prevents the indicator touching neighboring item bounds |
| Selected item extra width | `24 dp` | Space for selected icon plus icon/label gap |
| Icon size | `20 dp` | Reference icon scale |
| Icon/label gap | `4 dp` | Selected content spacing |
| Blur sigma | `18` | Clearly visible glass blur without looking frosted-white |
| Outer tint | `colorScheme.surface`, alpha `148/255` | About 58% opaque, 42% transparent |
| Indicator tint | `surfaceContainerHighest`, alpha `190/255` | About 75% opaque |
| Foreground | `onSurfaceVariant`, alpha `224/255` | Slightly gray rather than solid black/white |
| Border | `outlineVariant`, alpha `54/255`, width `0.7` | Thin edge separation |
| Shadow | `shadow`, alpha `22/255`, blur `18`, offset `(0, 6)` | Low-contrast floating depth |
| Width/position duration | `Durations.medium2` | Material motion timing |
| Width/position curve | `Curves.fastEaseInToSlowEaseOut` | Smooth acceleration and settling |
| Content switch duration | `Durations.short4` | Fast label/icon state change |

Do not replace `StadiumBorder` with a superellipse. A superellipse produces visible curvature along the nominally straight top and bottom edges, which changes the character of the bar.

## 3. Rendering hierarchy

The order of widgets is important:

```text
SafeArea
└── Align(heightFactor: 1)
    └── AnimatedContainer                // width, height, unclipped shadow
        └── ClipPath(StadiumBorder)      // clips blur and all painted layers
            └── BackdropFilter           // blurs page content behind the bar
                └── Stack
                    ├── DecoratedBox     // translucent glass tint + thin border
                    ├── AnimatedPositionedDirectional
                    │   └── IgnorePointer
                    │       └── DecoratedBox // the only selection indicator
                    └── Row
                        └── AnimatedContainer per destination
                            └── Semantics
                                └── transparent Material
                                    └── InkWell with no splash/overlay
                                        └── selected or unselected content
```

Three rules are essential:

1. Clip before applying `BackdropFilter`. Otherwise the blur may be evaluated across a much larger screen region and can bleed outside the capsule.
2. Paint the outer shadow outside the clip. A shadow placed inside `ClipPath` is cut off.
3. Keep the moving indicator separate from every destination. Per-item selected backgrounds create two overlapping selection circles during animation.

Use `BackdropFilter`, not `ImageFiltered`. `BackdropFilter` blurs already-painted content behind the widget. `ImageFiltered` blurs the navigation widget's own children and makes icons/text soft.

## 4. Width algorithm

The navigation bar is content-sized, but its geometry must be deterministic so the selection indicator can be positioned exactly.

### 4.1 Measure labels

For every label, measure both the unselected and selected font weights with `TextPainter`. Keep the larger result:

```text
labelWidth[i] = max(
  width(label, FontWeight.w600),
  width(label, FontWeight.w700)
)
```

Measuring both weights prevents the layout from jumping because bold glyphs can be slightly wider. Pass both `Directionality.of(context)` and `MediaQuery.textScalerOf(context)` to `TextPainter`.

### 4.2 Determine the maximum bar width

```text
maxNavWidth = min(screenWidth - 40, 520)
```

The `40` is the combined 20 dp left and right floating margin.

### 4.3 Allocate destination widths

Reserve the following first:

- all measured label widths;
- 24 dp for the selected icon and gap;
- 8 dp for the bar's 4 dp left and right internal inset.

Distribute the remaining width evenly as horizontal breathing room, clamped to 12–28 dp per destination:

```text
horizontalSpace = clamp(
  (maxNavWidth - 8 - 24 - sum(labelWidths)) / destinationCount,
  12,
  28
)

itemWidth[i] = labelWidth[i]
             + horizontalSpace
             + (i == selectedIndex ? 24 : 0)
```

If the resulting content is still wider than the available width, scale all destination widths by the same factor. This preserves relative geometry and keeps the indicator aligned. For extremely large accessibility text, prefer switching the app to a navigation rail or another accessible layout rather than making the capsule unreadably small.

### 4.4 Compute the bar and indicator geometry

```text
barWidth = 8 + sum(itemWidths)

indicatorStart = 4 + sum(itemWidths before selectedIndex)
indicatorWidth = itemWidths[selectedIndex] - 8
```

Use `AnimatedPositionedDirectional(start: ...)`, not `AnimatedPositioned(left: ...)`, so RTL positioning works automatically.

The outer `AnimatedContainer`, every destination `AnimatedContainer`, and the indicator must use the same duration and curve. They then appear to be one deforming/panning object rather than unrelated animations.

## 5. Complete reusable Flutter implementation

The following implementation has no third-party package dependency.

```dart
import 'dart:math' as math;
import 'dart:ui';

import 'package:flutter/material.dart';

@immutable
final class GlassNavigationItem {
  const GlassNavigationItem({
    required this.label,
    required this.icon,
    this.selectedIcon,
    this.semanticLabel,
  });

  final String label;
  final Widget icon;
  final Widget? selectedIcon;
  final String? semanticLabel;
}

final class FloatingGlassNavigationBar extends StatelessWidget {
  const FloatingGlassNavigationBar({
    super.key,
    required this.items,
    required this.selectedIndex,
    required this.onDestinationSelected,
    this.maxWidth = 520,
  });

  final List<GlassNavigationItem> items;
  final int selectedIndex;
  final ValueChanged<int> onDestinationSelected;
  final double maxWidth;

  static const _barHeight = 60.0;
  static const _sideMargin = 20.0;
  static const _bottomMinimum = 8.0;
  static const _outerInset = 4.0;
  static const _indicatorTop = 9.0;
  static const _indicatorHeight = 42.0;
  static const _indicatorItemInset = 4.0;
  static const _selectedExtraWidth = 24.0;
  static const _minItemSpace = 12.0;
  static const _maxItemSpace = 28.0;
  static const _blurSigma = 18.0;

  @override
  Widget build(BuildContext context) {
    if (items.isEmpty) return const SizedBox.shrink();

    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final direction = Directionality.of(context);
    final textScaler = MediaQuery.textScalerOf(context);
    final screenWidth = MediaQuery.sizeOf(context).width;
    final baseStyle = theme.textTheme.labelMedium;
    final foreground = scheme.onSurfaceVariant.withAlpha(224);
    const stadium = StadiumBorder();

    final safeIndex = selectedIndex.clamp(0, items.length - 1);

    final labelWidths = items.map((item) {
      final regularWidth = _measureLabel(
        item.label,
        baseStyle?.copyWith(fontWeight: FontWeight.w600),
        direction,
        textScaler,
      );
      final selectedWidth = _measureLabel(
        item.label,
        baseStyle?.copyWith(fontWeight: FontWeight.w700),
        direction,
        textScaler,
      );
      return math.max(regularWidth, selectedWidth);
    }).toList(growable: false);

    final availableWidth = math.max(
      0.0,
      math.min(maxWidth, screenWidth - (_sideMargin * 2)),
    );
    if (availableWidth <= _outerInset * 2) {
      return const SizedBox.shrink();
    }

    final fixedWidth = labelWidths.fold<double>(
      _selectedExtraWidth,
      (sum, width) => sum + width,
    );
    final horizontalSpace =
        ((availableWidth - (_outerInset * 2) - fixedWidth) / items.length)
            .clamp(_minItemSpace, _maxItemSpace);

    var itemWidths = List<double>.generate(
      items.length,
      (index) =>
          labelWidths[index] +
          horizontalSpace +
          (index == safeIndex ? _selectedExtraWidth : 0),
      growable: false,
    );

    final maximumContentWidth = availableWidth - (_outerInset * 2);
    final desiredContentWidth = itemWidths.fold<double>(
      0,
      (sum, width) => sum + width,
    );
    if (desiredContentWidth > maximumContentWidth &&
        desiredContentWidth > 0) {
      final scale = maximumContentWidth / desiredContentWidth;
      itemWidths = itemWidths
          .map((width) => width * scale)
          .toList(growable: false);
    }

    final barWidth = itemWidths.fold<double>(
      _outerInset * 2,
      (sum, width) => sum + width,
    );
    final indicatorStart = itemWidths
        .take(safeIndex)
        .fold<double>(_outerInset, (sum, width) => sum + width);
    final indicatorWidth = math.max(
      0.0,
      itemWidths[safeIndex] - (_indicatorItemInset * 2),
    );

    return SafeArea(
      top: false,
      minimum: const EdgeInsets.fromLTRB(
        _sideMargin,
        0,
        _sideMargin,
        _bottomMinimum,
      ),
      child: Align(
        heightFactor: 1,
        child: AnimatedContainer(
          width: barWidth,
          height: _barHeight,
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
              filter: ImageFilter.blur(
                sigmaX: _blurSigma,
                sigmaY: _blurSigma,
              ),
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
                    key: const ValueKey('glass-nav-indicator'),
                    start: indicatorStart,
                    top: _indicatorTop,
                    width: indicatorWidth,
                    height: _indicatorHeight,
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
                    children: List.generate(items.length, (index) {
                      final item = items[index];
                      final selected = index == safeIndex;

                      return AnimatedContainer(
                        key: ValueKey('glass-nav-item-$index'),
                        width: itemWidths[index],
                        duration: Durations.medium2,
                        curve: Curves.fastEaseInToSlowEaseOut,
                        child: Semantics(
                          container: true,
                          button: true,
                          selected: selected,
                          label: item.semanticLabel ?? item.label,
                          child: Material(
                            type: MaterialType.transparency,
                            child: InkWell(
                              customBorder: stadium,
                              overlayColor:
                                  const WidgetStatePropertyAll(
                                    Colors.transparent,
                                  ),
                              splashFactory: NoSplash.splashFactory,
                              onTap: () => onDestinationSelected(index),
                              child: Center(
                                child: FittedBox(
                                  fit: BoxFit.scaleDown,
                                  child: IconTheme(
                                    data: IconThemeData(
                                      size: 20,
                                      color: foreground,
                                    ),
                                    child: selected
                                        ? Row(
                                            mainAxisSize: MainAxisSize.min,
                                            children: [
                                              item.selectedIcon ?? item.icon,
                                              const SizedBox(width: 4),
                                              Text(
                                                item.label,
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
                                            item.label,
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
```

## 6. Host page integration

Use `Scaffold.extendBody: true`. This lets page content paint behind the transparent bottom-navigation region, which is required for real backdrop blur.

```dart
final class MainShell extends StatefulWidget {
  const MainShell({super.key});

  @override
  State<MainShell> createState() => _MainShellState();
}

final class _MainShellState extends State<MainShell> {
  final _controller = PageController();
  int _selectedIndex = 0;

  static const _items = [
    GlassNavigationItem(
      label: 'Servers',
      icon: Icon(Icons.dns_outlined),
      selectedIcon: Icon(Icons.dns_rounded),
    ),
    GlassNavigationItem(
      label: 'SSH',
      icon: Icon(Icons.terminal_outlined),
      selectedIcon: Icon(Icons.terminal_rounded),
    ),
    GlassNavigationItem(
      label: 'Files',
      icon: Icon(Icons.folder_open_outlined),
      selectedIcon: Icon(Icons.folder_rounded),
    ),
    GlassNavigationItem(
      label: 'Snippets',
      icon: Icon(Icons.code_outlined),
      selectedIcon: Icon(Icons.code_rounded),
    ),
  ];

  void _selectPage(int index) {
    if (index == _selectedIndex) return;
    if (index < 0 || index >= _items.length) return;

    setState(() => _selectedIndex = index);
    _controller.animateToPage(
      index,
      duration: const Duration(milliseconds: 677),
      curve: Curves.fastLinearToSlowEaseIn,
    );
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      extendBody: true,
      body: PageView(
        controller: _controller,
        physics: const NeverScrollableScrollPhysics(),
        children: const [
          ServersPage(),
          SshPage(),
          FilesPage(),
          SnippetsPage(),
        ],
      ),
      bottomNavigationBar: FloatingGlassNavigationBar(
        items: _items,
        selectedIndex: _selectedIndex,
        onDestinationSelected: _selectPage,
      ),
    );
  }
}
```

If horizontal page swiping is enabled, update `selectedIndex` in `PageView.onPageChanged`; otherwise the page and navigation state can diverge. The reference app disables page swiping and owns all changes through one selection method.

## 7. Scroll content and obstruction handling

`extendBody: true` intentionally allows rows, cards, images, and other content to pass underneath the glass. It also means the last item can be hidden when scrolling stops unless the scrollable has sufficient tail padding.

For a normal `ListView`, use a bottom padding derived from the bar height and device safe area:

```dart
final bottomTail = MediaQuery.paddingOf(context).bottom + 88;

ListView.builder(
  padding: EdgeInsets.only(bottom: bottomTail),
  itemCount: items.length,
  itemBuilder: buildItem,
);
```

For a sliver page:

```dart
CustomScrollView(
  slivers: [
    SliverList.builder(
      itemCount: items.length,
      itemBuilder: buildItem,
    ),
    SliverToBoxAdapter(
      child: SizedBox(
        height: MediaQuery.paddingOf(context).bottom + 88,
      ),
    ),
  ],
);
```

This is scroll tail padding, not an opaque fixed footer. Content should be able to travel below the glass while scrolling, but the final item must be able to settle above it.

Any page-local floating action button must also avoid the navigation overlay. Either move the action into a top app bar or add a bottom offset approximately equal to:

```text
system bottom safe area + 60 dp bar + 8–20 dp visual gap
```

## 8. Why the duplicate-circle bug occurs

A common broken implementation produces a small press circle and a larger selected capsule at the same time. After the press animation ends, only one remains. This usually happens because both of these are active:

- the custom moving selection indicator; and
- `InkWell`/`InkResponse`/`NavigationBar`'s default splash or overlay.

The fix is not to tune the splash radius. Remove the second visual system completely:

```dart
InkWell(
  overlayColor: const WidgetStatePropertyAll(Colors.transparent),
  splashFactory: NoSplash.splashFactory,
  onTap: onTap,
  child: child,
)
```

Also check for these hidden sources of a second selected background:

- a per-item `AnimatedContainer` with `color` when selected;
- a `NavigationBar` indicator behind the custom indicator;
- an `Ink` decoration on the destination;
- a `MaterialStateProperty` supplied by the app theme;
- a shadow attached to both the indicator and the destination;
- two indicators cross-fading in an `AnimatedSwitcher`.

The reference design has one indicator widget in one `Stack`, and that indicator is repositioned. It does not create a new selected indicator per destination.

## 9. Glass quality and color behavior

The glass effect is produced by three independent signals:

1. Backdrop blur: gives the surface optical depth.
2. Translucent neutral tint: keeps content behind the bar from reducing legibility.
3. Very light border and shadow: separates the glass edge from similar backgrounds.

Do not wrap the full bar in `Opacity`. That would also fade the icon and text. Apply transparency only to the surface colors.

Prefer dynamic `ColorScheme` colors over hard-coded white:

- light theme glass derives from `surface`;
- dark theme glass also derives from `surface`;
- the selection indicator derives from `surfaceContainerHighest`;
- the foreground derives from `onSurfaceVariant`.

This keeps the bar neutral while still following Material You/dynamic color. If stronger wallpaper color sampling is desired, blend a very small amount of `primary` into `surface`; do not tint icons independently.

When the glass looks too thin, increase edge/shadow definition before making the tint opaque. When it looks cloudy, reduce tint alpha slightly; do not reduce text opacity.

## 10. Motion specification

Selection changes involve three synchronized geometric animations:

- the outer bar width;
- every destination width;
- the selection indicator's directional start and width.

All three use:

```dart
duration: Durations.medium2,
curve: Curves.fastEaseInToSlowEaseOut,
```

The page transition may be slightly longer than the navigation morph. The reference page transition is 677 ms with `Curves.fastLinearToSlowEaseIn`.

Do not animate the blur sigma. Rebuilding a changing blur kernel is expensive and usually looks like focus breathing rather than physical motion.

Respect reduced-motion preferences in a production app. If `MediaQuery.disableAnimationsOf(context)` is true, use `Duration.zero` for geometry and page motion while preserving the final layout.

## 11. Accessibility and localization

- Wrap each destination in `Semantics(button: true, selected: ...)`.
- Supply a meaningful localized semantic label.
- Keep at least a 42–48 dp effective vertical hit target. The reference destination occupies the complete 60 dp bar height.
- Use `TextPainter` with the active `TextScaler`.
- Use `AnimatedPositionedDirectional`, `EdgeInsetsDirectional` where applicable, and the current `TextDirection`.
- Do not hard-code widths from English screenshots. Chinese, German, Arabic, and accessibility text sizes can be much wider.
- Keep labels to one line. For impossible widths, use a navigation rail or a reduced destination set rather than ellipsizing every label.
- If the same component is used on desktop, add a custom focus outline because the mobile reference intentionally disables the default Material overlay.

## 12. Performance notes

The main cost is `BackdropFilter`. Keep it inexpensive with these rules:

- Clip the filter to the exact capsule before applying it.
- Use only one backdrop filter for the entire bar.
- Never create one filter per destination.
- Keep blur sigma fixed.
- Avoid `IntrinsicWidth`; label geometry is already known from `TextPainter`.
- Rebuild the navigation only when selected index, labels, theme, text scale, direction, or screen width changes.
- Do not rebuild the entire page body when selection indicator animation advances; Flutter animation widgets repaint their own subtree.
- Keep the destination list small.
- Profile glass performance in a profile/release Android build. Debug-mode raster timing is not representative.

The blur must repaint when moving page content is visible behind it; that is the intended optical effect. A `RepaintBoundary` cannot eliminate this dependency, though it can still isolate unrelated neighboring widgets.

## 13. Responsive behavior

The compact glass bar is primarily for phone-width layouts. Recommended shell behavior:

```text
compact width: floating glass bottom navigation
medium/expanded width: NavigationRail or another side navigation pattern
```

Even when shown on a tablet, cap its width at 520 dp. Do not stretch it edge-to-edge.

The reference app determines compact versus rail navigation outside the component. The glass component should remain focused on rendering and hit testing, not own the application's breakpoint policy.

## 14. Validation checklist

Visual checks:

- [ ] The outer surface is one true capsule.
- [ ] Page content is visibly blurred, not merely covered by transparency.
- [ ] Icons and text are not blurred or globally faded.
- [ ] There is exactly one selected capsule before, during, and after a tap.
- [ ] No press ripple or circular halo appears.
- [ ] The indicator moves instead of cross-fading between two indicators.
- [ ] The bar width changes smoothly when labels have different lengths.
- [ ] A four-character CJK label does not become an ellipsis at normal text scale.
- [ ] The final list item can scroll completely above the bar.
- [ ] A floating action button is not covered.

Behavior checks:

- [ ] Tapping the selected destination is a no-op at the state-owner level.
- [ ] Invalid selected indices are clamped or rejected safely.
- [ ] Page controller and selected index never diverge.
- [ ] Back navigation/restoration restores the correct selected destination.
- [ ] RTL moves the indicator in the correct direction.
- [ ] Light, dark, and dynamic-color themes remain legible.
- [ ] Text scale 1.0, 1.3, and 2.0 are tested.
- [ ] Gesture-navigation and three-button-navigation safe areas are tested.
- [ ] Profile-mode scrolling remains smooth on a real Android device.

Suggested widget-test assertions:

- exactly one widget has key `glass-nav-indicator`;
- every item has a stable `glass-nav-item-N` key;
- tapping calls `onDestinationSelected` once;
- the `InkWell` uses `NoSplash.splashFactory`;
- the `InkWell.overlayColor` resolves to transparent;
- changing selection changes indicator start and width after animation;
- long localized labels keep the bar within the screen margin;
- RTL selection uses directional positioning correctly.

## 15. Non-negotiable implementation contract for a coding model

The following block can be copied directly into another model's task description:

```text
Implement a reusable Flutter floating glass bottom navigation bar using only
Flutter framework widgets.

Requirements:
1. Use a 60 dp StadiumBorder outer capsule with a single clipped
   BackdropFilter at sigma 18.
2. Use a translucent Material ColorScheme.surface tint, a low-alpha outline,
   and one low-alpha outer shadow. Do not apply Opacity to text or icons.
3. Use exactly one 42 dp high StadiumBorder selection indicator in a Stack.
   Move it with AnimatedPositionedDirectional. Never create per-item selected
   backgrounds or shadows.
4. Disable all InkWell ripple/overlay effects with NoSplash and transparent
   overlayColor so tapping never creates a second circle or halo.
5. Measure every localized label with TextPainter at regular and selected font
   weights, respecting TextScaler and TextDirection. Use the larger width.
6. Give the selected destination 24 dp extra width for its selected icon and
   4 dp icon/label gap. Animate all item widths, outer width, indicator start,
   and indicator width with the same duration and curve.
7. Keep 20 dp screen side margins, cap bar width at 520 dp, and honor SafeArea.
8. Selected content is icon + label; unselected content is label only.
9. Wrap destinations in Semantics with button and selected states.
10. Integrate it through Scaffold(extendBody: true). Add scroll tail padding
    so final content can stop above the overlay while still scrolling behind it.
11. Support RTL with directional positioning.
12. Do not use Flutter NavigationBar, a platform view, one BackdropFilter per
    item, IntrinsicWidth, an animated blur sigma, or a superellipse outer shape.
```

## 16. Reference source in this repository

The production implementation from which this document was derived is located in:

- `lib/view/page/home.dart`, class `_FloatingHomeNavigation`
- `lib/view/page/home_tab.dart`, extension `AppTabViewX`

Those classes include ServerBox-specific state and localization. The reusable implementation in this document removes those dependencies while preserving the geometry, rendering order, motion, and interaction rules.
