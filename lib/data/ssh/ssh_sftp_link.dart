import 'package:flutter/foundation.dart';

/// In-memory hand-off from the SSH workspace to the SFTP workspace.
///
/// The last server is retained so a lazily built Files page can still consume
/// the most recent SSH selection.
final class SshSftpLink extends ChangeNotifier {
  String? _serverId;
  int _revision = 0;

  String? get serverId => _serverId;
  int get revision => _revision;

  void selectServer(String serverId) {
    _serverId = serverId;
    _notifySelection();
  }

  void replay() {
    if (_serverId == null) return;
    _notifySelection();
  }

  void _notifySelection() {
    _revision++;
    notifyListeners();
  }
}

final sshSftpLink = SshSftpLink();
