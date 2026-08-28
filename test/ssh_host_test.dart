import 'package:flutter_test/flutter_test.dart';
import 'package:server_box/core/utils/ssh_host.dart';

void main() {
  group('SSH host helpers', () {
    test('normalizes bracketed IPv6 literals', () {
      expect(normalizeSshHost('[2001:db8::10]'), '2001:db8::10');
      expect(isValidSshHost('[2001:db8::10]'), isTrue);
      expect(formatSshHostPort('2001:db8::10', 22), '[2001:db8::10]:22');
    });

    test('accepts IPv4, IPv6 zone identifiers, and hostnames', () {
      expect(isValidSshHost('192.0.2.10'), isTrue);
      expect(isValidSshHost('2001:db8::10'), isTrue);
      expect(isValidSshHost('fe80::1%eth0'), isTrue);
      expect(isValidSshHost('bastion.example.com'), isTrue);
    });

    test('rejects malformed or shell-sensitive hosts', () {
      expect(isValidSshHost('2001:db8::10]'), isFalse);
      expect(isValidSshHost('bad host'), isFalse);
      expect(isValidSshHost('host;echo-pwned'), isFalse);
    });
  });
}
