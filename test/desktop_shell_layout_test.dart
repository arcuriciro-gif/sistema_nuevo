import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sistema_nuevo/theme/layout_constants.dart';

void main() {
  group('isDesktopShellLayout', () {
    test('celular portrait → móvil', () {
      expect(isDesktopShellLayout(const Size(390, 844)), isFalse);
    });

    test('celular landscape ancho >800 → sigue móvil (anti-crash rotación)', () {
      expect(isDesktopShellLayout(const Size(844, 390)), isFalse);
      expect(isDesktopShellLayout(const Size(915, 412)), isFalse);
    });

    test('tablet landscape → desktop', () {
      expect(isDesktopShellLayout(const Size(1024, 768)), isTrue);
    });

    test('PC típico → desktop', () {
      expect(isDesktopShellLayout(const Size(1366, 768)), isTrue);
    });
  });
}
