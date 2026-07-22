import 'package:fl_lib/fl_lib.dart' as fl;
import 'package:flutter_test/flutter_test.dart';
import 'package:server_box/data/model/app/path_with_prefix.dart';

void main() {
  group('LocalPath editable absolute path', () {
    final root = fl.isWindows ? r'C:\app\files' : '/app/files';
    final nested =
        '$root${fl.Pfs.seperator}server${fl.Pfs.seperator}logs';
    final outside = fl.isWindows ? r'C:\other' : '/other';

    test('accepts root and descendants', () {
      final path = LocalPath(root);
      expect(path.setAbsolute(nested), isTrue);
      expect(path.path, nested);
      expect(path.setAbsolute(root), isTrue);
      expect(path.path, '$root${fl.Pfs.seperator}');
    });

    test('rejects paths outside the managed root', () {
      final path = LocalPath(root);
      expect(path.setAbsolute(outside), isFalse);
      expect(path.path, '$root${fl.Pfs.seperator}');
    });
  });
}
