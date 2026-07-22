import 'package:flutter_test/flutter_test.dart';
import 'package:server_box/view/responsive_layout.dart';

void main() {
  group('responsive layout', () {
    test('uses compact navigation only below tablet width', () {
      expect(AppLayout.useCompactNavigation(599), isTrue);
      expect(AppLayout.useCompactNavigation(600), isFalse);
    });

    test('keeps status glass across phone and tablet widths', () {
      expect(AppLayout.useStatusGlass(430), isTrue);
      expect(AppLayout.useStatusGlass(900), isTrue);
      expect(AppLayout.useStatusGlass(1200), isFalse);
    });
  });
}
