import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:server_box/data/ssh/session_manager.dart';
import 'package:server_box/generated/l10n/l10n.dart';
import 'package:server_box/view/widget/ssh_connection_status.dart';

void main() {
  testWidgets('SSH title follows the live localized connection status', (
    tester,
  ) async {
    final status = ValueNotifier(TermSessionStatus.connecting);
    addTearDown(status.dispose);

    await tester.pumpWidget(
      MaterialApp(
        locale: const Locale('zh'),
        localizationsDelegates: AppLocalizations.localizationsDelegates,
        supportedLocales: AppLocalizations.supportedLocales,
        home: Scaffold(
          appBar: AppBar(
            title: SshConnectionTitle(
              title: 'Test server',
              statusListenable: status,
            ),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('Test server'), findsOneWidget);
    expect(find.text('正在连接'), findsOneWidget);

    status.value = TermSessionStatus.connected;
    await tester.pump();
    expect(find.text('已连接'), findsOneWidget);

    status.value = TermSessionStatus.disconnected;
    await tester.pump();
    expect(find.text('连接断开'), findsOneWidget);
  });
}
