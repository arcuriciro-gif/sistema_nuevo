import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:sistema_nuevo/navigation/shell_menu_catalog.dart';
import 'package:sistema_nuevo/services/sidebar_preferencias_service.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() async {
    SharedPreferences.setMockInitialValues({});
    await SidebarPreferenciasService.instance.cargar();
  });

  test('modo básico deja ventas/productos y oculta el resto', () async {
    await SidebarPreferenciasService.instance.aplicarModo(UiModoMenu.basico);
    expect(SidebarPreferenciasService.instance.modo, UiModoMenu.basico);
    expect(
      SidebarPreferenciasService.instance.estaVisible('productos|Productos'),
      isTrue,
    );
    expect(
      SidebarPreferenciasService.instance
          .estaVisible('remitos|Venta Rápida'),
      isTrue,
    );
    expect(
      SidebarPreferenciasService.instance.estaVisible('remitos|Comprobantes'),
      isTrue,
    );
    expect(
      SidebarPreferenciasService.instance.estaVisible('compras|Compras'),
      isTrue,
    );
    expect(
      SidebarPreferenciasService.instance.estaVisible('reportes|Reportes'),
      isFalse,
    );
    expect(
      SidebarPreferenciasService.instance.estaVisible('usuarios|Usuarios'),
      isFalse,
    );
    expect(
      kShellMenuCatalog.any((e) => e.title == 'Panel técnico'),
      isFalse,
    );
  });

  test('modo completo muestra todo el catálogo', () async {
    await SidebarPreferenciasService.instance.aplicarModo(UiModoMenu.basico);
    await SidebarPreferenciasService.instance.aplicarModo(UiModoMenu.completo);
    expect(SidebarPreferenciasService.instance.modo, UiModoMenu.completo);
    for (final e in kShellMenuCatalog) {
      expect(
        SidebarPreferenciasService.instance.estaVisible(e.id),
        isTrue,
        reason: e.id,
      );
    }
  });
}
