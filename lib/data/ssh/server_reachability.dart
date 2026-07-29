import 'package:server_box/data/model/server/server.dart';

enum ServerReachability { checking, online, offline }

ServerReachability reachabilityFromServerConnection(ServerConn connection) {
  return switch (connection) {
    ServerConn.finished => ServerReachability.online,
    ServerConn.failed => ServerReachability.offline,
    ServerConn.disconnected ||
    ServerConn.connecting ||
    ServerConn.connected ||
    ServerConn.loading => ServerReachability.checking,
  };
}

class OfflineConnectionGate {
  OfflineConnectionGate({
    this.forceConfirmationDuration = const Duration(seconds: 5),
  });

  final Duration forceConfirmationDuration;
  final Map<String, DateTime> _armedUntil = {};

  bool consumeConfirmation(String serverId, {DateTime? now}) {
    final currentTime = now ?? DateTime.now();
    final armedUntil = _armedUntil[serverId];
    if (armedUntil != null && currentTime.isBefore(armedUntil)) {
      _armedUntil.remove(serverId);
      return true;
    }
    _armedUntil[serverId] = currentTime.add(forceConfirmationDuration);
    return false;
  }

  void clear(String serverId) {
    _armedUntil.remove(serverId);
  }
}

final offlineConnectionGate = OfflineConnectionGate();
