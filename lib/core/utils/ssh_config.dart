import 'dart:io';
import 'package:fl_lib/fl_lib.dart';
import 'package:meta/meta.dart';
import 'package:server_box/core/utils/ssh_host.dart';
import 'package:server_box/data/model/server/server_private_info.dart';

/// Utility class to parse SSH config files under `~/.ssh/config`
abstract final class SSHConfig {
  static const String _defaultPath = '~/.ssh/config';

  static String? get _homePath {
    final homePath = isWindows
        ? Platform.environment['USERPROFILE']
        : Platform.environment['HOME'];
    if (homePath == null || homePath.isEmpty) {
      return null;
    }
    return homePath;
  }

  /// Get possible SSH config file paths, with macOS-specific handling
  static List<String> get _possibleConfigPaths {
    final paths = <String>[];
    final homePath = _homePath;

    if (homePath != null) {
      // Standard path
      paths.add('$homePath/.ssh/config');

      // On macOS, also try the actual user home directory
      if (isMacOS) {
        // Try to get the real user home directory
        final username = Platform.environment['USER'];
        if (username != null) {
          paths.add('/Users/$username/.ssh/config');
        }
      }
    }

    return paths;
  }

  /// Parse SSH config file and return a list of Spi objects
  static Future<List<Spi>> parseConfig([String? configPath]) async {
    final (file, exists) = configExists(configPath);
    if (!exists || file == null) {
      Loggers.app.info(
        'SSH config file does not exist at path: ${configPath ?? _defaultPath}',
      );
      return [];
    }

    final content = await file.readAsString();
    return _parseSSHConfig(content);
  }

  /// Parse SSH config content
  static List<Spi> _parseSSHConfig(String content) {
    final servers = <Spi>[];
    final lines = content.split('\n');

    String? currentHost;
    String? hostname;
    String? user;
    int port = 22;
    String? identityFile;
    String? jumpHost;
    String? proxyCommand;

    void addServer() {
      if (currentHost != null && currentHost != '*' && hostname != null) {
        final normalizedProxyCommand = proxyCommand?.trim();
        final resolvedProxyCommand =
            normalizedProxyCommand == null || normalizedProxyCommand.isEmpty
            ? null
            : normalizedProxyCommand;
        final resolvedJumpHost = resolvedProxyCommand != null ? null : jumpHost;
        if (resolvedProxyCommand != null && jumpHost != null) {
          Loggers.app.info(
            'SSH config host $currentHost defines both ProxyJump and '
            'ProxyCommand; preferring ProxyCommand.',
          );
        }
        final spi = Spi(
          id: ShortId.generate(),
          name: currentHost,
          ip: normalizeSshHost(hostname),
          port: port,
          user: user ?? 'root', // Default user is 'root'
          keyId: identityFile,
          jumpId: resolvedJumpHost,
          proxyCommand: resolvedProxyCommand,
        );
        final validationError = spi.validate();
        if (validationError != null) {
          Loggers.app.warning(
            'Skipping invalid SSH config host $currentHost: $validationError',
          );
          return;
        }
        servers.add(spi);
      }
    }

    for (final line in lines) {
      final trimmed = line.trim();
      if (trimmed.isEmpty || trimmed.startsWith('#')) continue;

      // Handle inline comments
      final cleanLine = _stripInlineComment(trimmed);
      if (cleanLine.isEmpty) continue;

      final parts = cleanLine.split(RegExp(r'\s+'));
      if (parts.length < 2) continue;

      final key = parts[0].toLowerCase();
      var value = parts.sublist(1).join(' ');

      // Remove quotes from values
      if ((value.startsWith('"') && value.endsWith('"')) ||
          (value.startsWith("'") && value.endsWith("'"))) {
        value = value.substring(1, value.length - 1);
      }

      switch (key) {
        case 'host':
          // Save previous host config
          addServer();

          // Reset for new host
          final originalValue = parts.sublist(1).join(' ');
          final isQuoted =
              (originalValue.startsWith('"') && originalValue.endsWith('"')) ||
              (originalValue.startsWith("'") && originalValue.endsWith("'"));

          currentHost = value;
          // Skip hosts with multiple patterns (contains spaces but not quoted)
          if (currentHost.contains(' ') && !isQuoted) {
            currentHost = null; // Mark as invalid to skip
          }
          hostname = null;
          user = null;
          port = 22;
          identityFile = null;
          jumpHost = null;
          proxyCommand = null;
          break;

        case 'hostname':
          hostname = value;
          break;

        case 'user':
          user = value;
          break;

        case 'port':
          port = int.tryParse(value) ?? 22;
          break;

        case 'identityfile':
          identityFile = value; // Store the path directly
          break;

        case 'proxyjump':
          jumpHost = _extractJumpHost(value);
          break;
        case 'proxycommand':
          proxyCommand = value;
          break;
      }
    }

    // Add the last server
    addServer();

    // ProxyJump stores a Host alias, while Spi.jumpId stores the generated
    // server id. Resolve aliases after every Host block has been parsed.
    final byName = <String, Spi>{
      for (final server in servers) server.name: server,
    };
    final byHost = <String, Spi>{
      for (final server in servers) server.ip: server,
    };
    for (var i = 0; i < servers.length; i++) {
      final server = servers[i];
      final jumpAlias = server.jumpId;
      if (jumpAlias == null) continue;
      final jump = byName[jumpAlias] ?? byHost[jumpAlias];
      if (jump == null) {
        Loggers.app.warning(
          'SSH config jump host $jumpAlias was not found for ${server.name}',
        );
        servers[i] = server.copyWith(jumpId: null, jumpIds: null);
        continue;
      }
      servers[i] = server.copyWith(jumpId: jump.id, jumpIds: [jump.id]);
    }

    return servers;
  }

  /// Extract jump host from ProxyJump or ProxyCommand
  static String? _extractJumpHost(String value) {
    final first = value.split(',').first.trim();
    if (first.isEmpty || first.toLowerCase() == 'none') return null;

    final at = first.lastIndexOf('@');
    var hostPort = at == -1 ? first : first.substring(at + 1);
    hostPort = hostPort.trim();
    if (hostPort.startsWith('[')) {
      final close = hostPort.indexOf(']');
      if (close <= 1) return null;
      return normalizeSshHost(hostPort.substring(0, close + 1));
    }

    // An unbracketed IPv6 literal contains multiple colons and must not have
    // its final hextet mistaken for a port. Only strip :port from hostnames.
    final colon = hostPort.lastIndexOf(':');
    if (colon > 0 && hostPort.indexOf(':') == colon) {
      final port = int.tryParse(hostPort.substring(colon + 1));
      if (port != null) hostPort = hostPort.substring(0, colon);
    }
    return normalizeSshHost(hostPort);
  }

  static String _stripInlineComment(String line) {
    var inSingleQuotes = false;
    var inDoubleQuotes = false;
    var escaped = false;

    for (var i = 0; i < line.length; i++) {
      final char = line[i];
      if (escaped) {
        escaped = false;
        continue;
      }
      if (char == r'\') {
        escaped = true;
        continue;
      }
      if (char == "'" && !inDoubleQuotes) {
        inSingleQuotes = !inSingleQuotes;
        continue;
      }
      if (char == '"' && !inSingleQuotes) {
        inDoubleQuotes = !inDoubleQuotes;
        continue;
      }
      if (char == '#' &&
          !inSingleQuotes &&
          !inDoubleQuotes &&
          (i == 0 || line[i - 1].trim().isEmpty)) {
        return line.substring(0, i).trim();
      }
    }

    return line.trim();
  }

  @visibleForTesting
  static String stripInlineCommentForTest(String line) {
    return _stripInlineComment(line);
  }

  /// Check if SSH config file exists, trying multiple possible paths
  static (File?, bool) configExists([String? configPath]) {
    if (configPath != null) {
      // If specific path is provided, use it directly
      final homePath = _homePath;
      if (homePath == null) {
        Loggers.app.warning(
          'Cannot determine home directory for SSH config parsing.',
        );
        return (null, false);
      }
      final expandedPath = configPath.replaceFirst('~', homePath);
      dprint('Checking SSH config at path: $expandedPath');
      final file = File(expandedPath);
      return (file, file.existsSync());
    }

    // Try multiple possible paths
    for (final path in _possibleConfigPaths) {
      dprint('Checking SSH config at path: $path');
      final file = File(path);
      if (file.existsSync()) {
        dprint('Found SSH config at: $path');
        return (file, true);
      }
    }

    dprint('SSH config file not found in any of the expected locations');
    return (null, false);
  }
}
