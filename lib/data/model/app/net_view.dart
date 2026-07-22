import 'package:fl_lib/fl_lib.dart';
import 'package:server_box/data/model/server/server.dart';

enum NetViewType {
  conn,
  speed,
  traffic;

  NetViewType get next => switch (this) {
    conn => speed,
    speed => traffic,
    traffic => conn,
  };

  String get toStr => switch (this) {
    NetViewType.conn => libL10n.conn,
    NetViewType.traffic => libL10n.traffic,
    NetViewType.speed => libL10n.speed,
  };

  /// If no device is specified, return the cached value (only real devices,
  /// such as ethX, wlanX...).
  (String, String) buildValues(ServerStatus ss, {String? dev}) {
    final notSpecifyDev = dev == null || dev.isEmpty;
    try {
      switch (this) {
        case NetViewType.conn:
          return ('${ss.tcp.maxConn}', '${ss.tcp.fail}');
        case NetViewType.speed:
          if (notSpecifyDev) {
            return (
              ss.netSpeed.cachedVals.speedIn,
              ss.netSpeed.cachedVals.speedOut,
            );
          }
          return (
            ss.netSpeed.speedIn(device: dev),
            ss.netSpeed.speedOut(device: dev),
          );
        case NetViewType.traffic:
          if (notSpecifyDev) {
            return (
              ss.netSpeed.cachedVals.sizeIn,
              ss.netSpeed.cachedVals.sizeOut,
            );
          }
          return (
            ss.netSpeed.sizeIn(device: dev),
            ss.netSpeed.sizeOut(device: dev),
          );
      }
    } catch (e, s) {
      Loggers.app.warning('NetViewType.build', e, s);
      return ('N/A', 'N/A');
    }
  }

  (String, String) build(ServerStatus ss, {String? dev}) {
    final (first, second) = buildValues(ss, dev: dev);
    return switch (this) {
      NetViewType.conn => (
        '${libL10n.conn}:\n$first',
        '${libL10n.fail}:\n$second',
      ),
      NetViewType.speed || NetViewType.traffic => (
        '↓:\n$first',
        '↑:\n$second',
      ),
    };
  }

  int toJson() => switch (this) {
    NetViewType.conn => 0,
    NetViewType.speed => 1,
    NetViewType.traffic => 2,
  };

  static NetViewType fromJson(int json) => switch (json) {
    0 => NetViewType.conn,
    1 => NetViewType.speed,
    _ => NetViewType.traffic,
  };
}
