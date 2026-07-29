import 'package:flutter_test/flutter_test.dart';
import 'package:server_box/data/model/server/server.dart';
import 'package:server_box/data/ssh/server_reachability.dart';

void main() {
  test('reachability follows the home server connection state', () {
    expect(
      reachabilityFromServerConnection(ServerConn.disconnected),
      ServerReachability.checking,
    );
    expect(
      reachabilityFromServerConnection(ServerConn.connecting),
      ServerReachability.checking,
    );
    expect(
      reachabilityFromServerConnection(ServerConn.connected),
      ServerReachability.checking,
    );
    expect(
      reachabilityFromServerConnection(ServerConn.loading),
      ServerReachability.checking,
    );
    expect(
      reachabilityFromServerConnection(ServerConn.finished),
      ServerReachability.online,
    );
    expect(
      reachabilityFromServerConnection(ServerConn.failed),
      ServerReachability.offline,
    );
  });

  test('offline force connection requires a second tap', () {
    final gate = OfflineConnectionGate();
    final now = DateTime(2026, 7, 23, 12);

    expect(gate.consumeConfirmation('server', now: now), isFalse);
    expect(
      gate.consumeConfirmation(
        'server',
        now: now.add(const Duration(seconds: 1)),
      ),
      isTrue,
    );
    expect(
      gate.consumeConfirmation(
        'server',
        now: now.add(const Duration(seconds: 2)),
      ),
      isFalse,
    );
  });
}
