import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter/scheduler.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// Preferencias del menú lateral / drawer, **por dispositivo y plataforma**.
///
/// En Android podés ocultar módulos que en Windows sí querés ver.
/// No se sincroniza a la nube (es local del equipo).
class MenuPreferenciasService extends ChangeNotifier {
  MenuPreferenciasService._();
  static final MenuPreferenciasService instance = MenuPreferenciasService._();

  static const _kHiddenPrefix = 'menu_hidden_';

  /// Ítems que nunca se pueden ocultar.
  static const idsObligatorios = {'inicio', 'configuracion'};

  /// Catálogo para la UI de configuración (id estable → título).
  static const catalogo = <({String id, String titulo, String grupo})>[
    (id: 'inicio', titulo: 'Inicio', grupo: 'Principal'),
    (id: 'dashboard', titulo: 'Dashboard', grupo: 'Principal'),
    (id: 'comunicaciones', titulo: 'Comunicaciones', grupo: 'Principal'),
    (id: 'productos', titulo: 'Productos', grupo: 'Catálogo'),
    (id: 'papelera', titulo: 'Papelera', grupo: 'Catálogo'),
    (id: 'categorias', titulo: 'Categorías', grupo: 'Catálogo'),
    (id: 'venta_rapida', titulo: 'Venta Rápida', grupo: 'Ventas'),
    (id: 'ventas_facturas', titulo: 'Ventas / Facturas', grupo: 'Ventas'),
    (id: 'presupuestos', titulo: 'Presupuestos', grupo: 'Ventas'),
    (id: 'notas_entrega', titulo: 'Notas de entrega', grupo: 'Ventas'),
    (id: 'comprobantes_internos', titulo: 'Comprobantes internos', grupo: 'Ventas'),
    (id: 'comparador', titulo: 'Comparador de listas', grupo: 'Importación'),
    (id: 'importaciones', titulo: 'Importaciones', grupo: 'Importación'),
    (id: 'importar_productos', titulo: 'Importar Productos', grupo: 'Importación'),
    (id: 'stock', titulo: 'Stock', grupo: 'Operaciones'),
    (id: 'compras', titulo: 'Compras', grupo: 'Operaciones'),
    (id: 'pedidos', titulo: 'Pedidos', grupo: 'Operaciones'),
    (id: 'pedido_sugerido', titulo: 'Pedido sugerido', grupo: 'Operaciones'),
    (id: 'remitos', titulo: 'Remitos', grupo: 'Operaciones'),
    (id: 'clientes', titulo: 'Clientes', grupo: 'Clientes'),
    (id: 'archivo_pdf', titulo: 'Archivo PDF', grupo: 'Clientes'),
    (id: 'cuenta_corriente', titulo: 'Cuenta corriente', grupo: 'Clientes'),
    (id: 'proveedores', titulo: 'Proveedores', grupo: 'Compras'),
    (id: 'listas_precios', titulo: 'Listas de Precios', grupo: 'Precios'),
    (id: 'reportes', titulo: 'Reportes', grupo: 'Análisis'),
    (id: 'inteligencia', titulo: 'Inteligencia Comercial', grupo: 'Análisis'),
    (id: 'etiquetas', titulo: 'Etiquetas', grupo: 'Utilidades'),
    (id: 'auditoria', titulo: 'Auditoría', grupo: 'Admin'),
    (id: 'mi_perfil', titulo: 'Mi perfil', grupo: 'Admin'),
    (id: 'usuarios', titulo: 'Usuarios', grupo: 'Admin'),
    (id: 'permisos', titulo: 'Permisos', grupo: 'Admin'),
    (id: 'respaldo', titulo: 'Respaldo', grupo: 'Admin'),
    (id: 'manual', titulo: 'Manual de usuario', grupo: 'Admin'),
    (id: 'configuracion', titulo: 'Configuración', grupo: 'Admin'),
  ];

  /// Perfil compacto sugerido para celular.
  static const idsEsencialesMovil = {
    'inicio',
    'dashboard',
    'comunicaciones',
    'productos',
    'venta_rapida',
    'ventas_facturas',
    'remitos',
    'clientes',
    'cuenta_corriente',
    'stock',
    'compras',
    'pedidos',
    'mi_perfil',
    'configuracion',
  };

  Set<String> _ocultos = {};
  bool _cargado = false;

  bool get cargado => _cargado;

  String get plataformaActual {
    if (kIsWeb) return 'web';
    if (Platform.isAndroid) return 'android';
    if (Platform.isIOS) return 'ios';
    if (Platform.isWindows) return 'windows';
    if (Platform.isLinux) return 'linux';
    if (Platform.isMacOS) return 'macos';
    return 'other';
  }

  String get plataformaLabel {
    switch (plataformaActual) {
      case 'android':
        return 'Android (este celular)';
      case 'windows':
        return 'Windows (este PC)';
      case 'ios':
        return 'iOS';
      default:
        return plataformaActual;
    }
  }

  String get _prefsKey => '$_kHiddenPrefix$plataformaActual';

  Future<void> cargar() async {
    final prefs = await SharedPreferences.getInstance();
    final list = prefs.getStringList(_prefsKey) ?? const <String>[];
    _ocultos = list.toSet()..removeAll(idsObligatorios);
    _cargado = true;
    _notify();
  }

  bool estaVisible(String id) {
    if (idsObligatorios.contains(id)) return true;
    return !_ocultos.contains(id);
  }

  Future<void> setVisible(String id, bool visible) async {
    if (idsObligatorios.contains(id)) return;
    if (visible) {
      _ocultos.remove(id);
    } else {
      _ocultos.add(id);
    }
    await _persistir();
    _notify();
  }

  Future<void> mostrarTodos() async {
    _ocultos.clear();
    await _persistir();
    _notify();
  }

  Future<void> aplicarPerfilMovil() async {
    final todos = catalogo.map((e) => e.id).toSet();
    _ocultos = todos.difference(idsEsencialesMovil)..removeAll(idsObligatorios);
    await _persistir();
    _notify();
  }

  Future<void> _persistir() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setStringList(_prefsKey, _ocultos.toList()..sort());
  }

  void _notify() {
    SchedulerBinding.instance.addPostFrameCallback((_) {
      notifyListeners();
    });
  }
}
