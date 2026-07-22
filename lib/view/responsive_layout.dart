abstract final class AppLayout {
  static const compactNavigationBreakpoint = 600.0;
  static const desktopChromeBreakpoint = 1200.0;

  static bool useCompactNavigation(double width) =>
      width < compactNavigationBreakpoint;

  static bool useStatusGlass(double width) => width < desktopChromeBreakpoint;
}
