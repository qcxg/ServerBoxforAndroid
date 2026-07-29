import 'package:flutter_test/flutter_test.dart';
import 'package:server_box/view/widget/file_list_metadata.dart';

void main() {
  test('file list time uses the compact MT-style minute precision', () {
    expect(
      formatFileListModified(DateTime(2026, 7, 27, 3, 6, 45)),
      '26-07-27 03:06',
    );
  });

  test('file list size omits the gap before its unit', () {
    expect(formatFileListSize(2048), '2KB');
  });
}
