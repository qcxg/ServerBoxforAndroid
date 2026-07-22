import 'package:server_box/data/ssh/command_buffer.dart';
import 'package:test/test.dart';

void main() {
  group('command buffer', () {
    test('normalizes platform line endings', () {
      expect(normalizeCommandBufferText('one\r\ntwo\rthree'), 'one\ntwo\nthree');
    });

    test('splits non-empty commands while preserving command whitespace', () {
      expect(
        splitCommandBufferLines('  echo one  \n\n  \nwhoami\r\n'),
        ['  echo one  ', 'whoami'],
      );
    });

    test('returns no commands for a blank buffer', () {
      expect(splitCommandBufferLines(' \r\n\t\n'), isEmpty);
    });

    test('prepares single-line input for exactly one caller-owned Enter', () {
      expect(prepareCommandBufferForSendAll('uptime'), 'uptime');
      expect(prepareCommandBufferForSendAll('uptime\r\n'), 'uptime');
    });

    test('preserves internal line breaks in multiline shell constructs', () {
      expect(
        prepareCommandBufferForSendAll(
          'for i in 1 2; do\r\n  echo \$i\r\ndone\r\n',
        ),
        'for i in 1 2; do\n  echo \$i\ndone',
      );
    });

    test('builds one atomic PTY payload with a final Enter', () {
      expect(
        buildCommandBufferSendAllPayload('echo one\nwhoami\n'),
        'echo one\rwhoami\r',
      );
      expect(buildCommandBufferSendAllPayload('  \n'), isEmpty);
    });

    test('builds separate executable PTY writes for line-by-line mode', () {
      expect(
        buildCommandBufferLinePayloads('echo one\n\nwhoami\n'),
        ['echo one\r', 'whoami\r'],
      );
    });
  });
}
