import 'package:flutter_test/flutter_test.dart';
import 'package:server_box/view/widget/file_type_icon.dart';

void main() {
  test('recognizes common structured file formats', () {
    expect(
      fileVisualKind('compose.yml', isDirectory: false),
      FileVisualKind.yaml,
    );
    expect(
      fileVisualKind('AndroidManifest.xml', isDirectory: false),
      FileVisualKind.xml,
    );
    expect(
      fileVisualKind('settings.json', isDirectory: false),
      FileVisualKind.json,
    );
  });

  test('directory visual takes priority over its extension', () {
    expect(
      fileVisualKind('archive.json', isDirectory: true),
      FileVisualKind.folder,
    );
  });
}
