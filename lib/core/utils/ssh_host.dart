import 'dart:io';

/// Normalizes an SSH host entered as a bare IPv6 address or as an endpoint
/// host. Brackets are host:port notation and must not be sent to Socket.connect
/// or in an SSH direct-tcpip request.
String normalizeSshHost(String value) {
  final host = value.trim();
  if (host.length >= 2 && host.codeUnitAt(0) == 0x5b && host.endsWith(']')) {
    return host.substring(1, host.length - 1);
  }
  return host;
}

/// Returns whether [value] is a safe SSH hostname or numeric IP address.
///
/// Zone identifiers are accepted for link-local IPv6 addresses. They are
/// interpreted on the machine that creates the socket (the jump host for a
/// forwarded connection).
bool isValidSshHost(String value) {
  final host = normalizeSshHost(value);
  if (host.isEmpty || host.contains('[') || host.contains(']')) return false;
  if (host.codeUnits.any((unit) => unit <= 0x20 || unit == 0x7f)) return false;

  final zoneIndex = host.indexOf('%');
  final address = zoneIndex == -1 ? host : host.substring(0, zoneIndex);
  final zone = zoneIndex == -1 ? null : host.substring(zoneIndex + 1);
  if (zone != null &&
      (zone.isEmpty || !RegExp(r'^[a-zA-Z0-9._-]+$').hasMatch(zone))) {
    return false;
  }

  final parsed = InternetAddress.tryParse(address);
  if (parsed != null) return zone == null || parsed.type == InternetAddressType.IPv6;

  // Do not allow shell metacharacters because ProxyCommand is executed by a
  // shell on desktop platforms.
  return RegExp(r'^[a-zA-Z0-9](?:[a-zA-Z0-9._-]*[a-zA-Z0-9])?\.?$')
      .hasMatch(host);
}

/// Formats an SSH endpoint without making IPv6 ambiguous with the port.
String formatSshHostPort(String host, int port) {
  final normalized = normalizeSshHost(host);
  final address = normalized.contains(':') ? '[$normalized]' : normalized;
  return '$address:$port';
}
