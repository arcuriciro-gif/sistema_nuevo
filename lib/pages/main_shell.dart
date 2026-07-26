import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../services/auth_service.dart';
import '../services/auto_backup_service.dart';
import '../services/branding_service.dart';
import '../services/comunicaciones_service.dart';
import '../services/cuenta_corriente_service.dart';
import '../services/permisos_service.dart';
import '../services/sidebar_preferencias_service.dart';
import '../core/events/data_refresh_hub.dart';
import '../core/comms/local_notification_service.dart';
import '../core/config/backend_config_service.dart';
import '../core/config/platform_capabilities.dart';
import '../core/sync/sync_background.dart';
import '../theme/app_tokens.dart';
import '../theme/layout_constants.dart';
import '../theme/module_app_bar.dart';
import '../widgets/media_avatar.dart';
import '../widgets/empresa_onboarding_dialog.dart';
import '../widgets/shell/shell_sync_badge.dart';
import 'archivo_pdfs_page.dart';
import 'auditoria_page.dart';
import 'backup_page.dart';
import 'busqueda_global_page.dart';
import 'categorias_page.dart';
import 'centro_importaciones_page.dart';
import 'chat_page.dart';
import 'clientes_page.dart';
import '../models/chat_conversacion.dart';
import 'clientes_deudores_page.dart';
import 'comparacion_page.dart';
import 'compras_page.dart';
import 'comunicaciones_page.dart';
import 'configuracion_page.dart';
import 'dashboard_page.dart';
import 'panel_tecnico_page.dart';
import 'etiquetas_page.dart';
import 'inicio_page.dart';
import 'importacion_page.dart';
import 'inteligencia_comercial_page.dart';
import 'listas_precio_page.dart';
import 'login_page.dart';
import 'manual_usuario_page.dart';
import 'notificaciones_page.dart';
import 'papelera_productos_page.dart';
import 'perfil_usuario_page.dart';
import 'permisos_page.dart';
import 'primeros_pasos_page.dart';
import 'productos_page.dart';
import 'proveedores_page.dart';
import 'remitos_page.dart';
import 'reportes_page.dart';
import 'scanner_page.dart';
import 'stock_page.dart';
import 'usuarios_page.dart';
import 'ventas_page.dart';
import 'venta_rapida_page.dart';
import '../core/utils/media_path.dart';

// Shell chrome (naranja/blanco/negro). El acento seleccionado sigue Config.
Color get _kSidebarBg => AppTokens.ink;
Color get _kSidebarBorder => AppTokens.line;
Color get _kSidebarHeaderBorder => AppTokens.line;
Color get _kSidebarInactiveIcon => AppTokens.mute;
Color get _kSidebarInactiveText => const Color(0xFFE5E7EB);
Color get _kSidebarUserBg => AppTokens.inkSoft;
Color get _kSidebarSubtext => AppTokens.muteSoft;

/// Agrupa módulos solo visualmente (mismos preferenciaId).
String _seccionDeTitulo(String title) {
  switch (title) {
    case 'Inicio':
      return 'Inicio';
    case 'Venta Rápida':
    case 'Ventas / Facturas':
    case 'Presupuestos':
    case 'Entregas (sin factura)':
    case 'Tickets internos':
    case 'Remitos':
    case 'Compras':
      return 'Operaciones';
    case 'Productos':
    case 'Papelera':
    case 'Categorías':
    case 'Stock':
    case 'Importaciones':
    case 'Importar Productos':
    case 'Etiquetas':
    case 'Listas de Precios':
    case 'Comparador de listas':
      return 'Inventario';
    case 'Clientes':
    case 'Archivo PDF':
    case 'Cuenta corriente':
    case 'Proveedores':
    case 'Comunicaciones':
      return 'Clientes';
    case 'Dashboard':
    case 'Reportes':
    case 'Inteligencia Comercial':
      return 'Análisis';
    default:
      return 'Administración';
  }
}

const _kOrdenSecciones = [
  'Inicio',
  'Operaciones',
  'Inventario',
  'Clientes',
  'Análisis',
  'Administración',
];

IconData _iconoSeccion(String sec) {
  switch (sec) {
    case 'Inicio':
      return Icons.home_rounded;
    case 'Operaciones':
      return Icons.point_of_sale_rounded;
    case 'Inventario':
      return Icons.inventory_2_rounded;
    case 'Clientes':
      return Icons.groups_rounded;
    case 'Análisis':
      return Icons.insights_rounded;
    default:
      return Icons.settings_rounded;
  }
}

class _ShellItem {
  final IconData icon;
  final String title;
  final String modulo;
  final Widget Function() builder;
  final bool quickAccess;
  final bool soloAdmin;

  const _ShellItem({
    required this.icon,
    required this.title,
    required this.modulo,
    required this.builder,
    this.quickAccess = false,
    this.soloAdmin = false,
  });

  /// Id estable para preferencias de barra lateral.
  String get preferenciaId => '$modulo|$title';
}

class MainShell extends StatefulWidget {
  const MainShell({super.key});

  @override
  State<MainShell> createState() => _MainShellState();
}

class _MainShellState extends State<MainShell> {
  int _selectedIndex = 0;
  /// Id estable del módulo visible (`preferenciaId`) para no saltar a Inicio
  /// cuando se oculta otro ítem del menú.
  String? _selectedPreferenciaId;
  bool _recordatorioMostrado = false;
  final GlobalKey<ScaffoldState> _mobileScaffoldKey = GlobalKey<ScaffoldState>();

  void _onBrandingChanged() {
    if (mounted) setState(() {});
  }

  void _onDatosRemotos() {
    if (mounted) setState(() {});
  }

  @override
  void initState() {
    super.initState();
    BrandingService.instance.addListener(_onBrandingChanged);
    ComunicacionesService.instance.addListener(_onCommsChanged);
    DataRefreshHub.instance.addListener(_onDatosRemotos);
    SidebarPreferenciasService.instance.addListener(_onSidebarPrefs);
    LocalNotificationService.instance.onTap = _onNotificationTap;
    WidgetsBinding.instance.addPostFrameCallback((_) async {
      try {
        await SidebarPreferenciasService.instance.cargar();
      } catch (e) {
        debugPrint('Sidebar prefs: $e');
      }
      try {
        await AutoBackupService.instance.iniciar();
      } catch (e) {
        debugPrint('AutoBackup init: $e');
      }
      try {
        await ComunicacionesService.instance.iniciar();
      } catch (e) {
        debugPrint('Comunicaciones init: $e');
      }
      if (mounted) await EmpresaOnboardingDialog.mostrarSiHaceFalta(context);
      if (mounted) await _ofrecerActivarNubeSiHaceFalta();
      // Recordatorio CC: no modal al abrir; solo badge/flujo manual.
    });
  }

  Future<void> _onNotificationTap(String payload) async {
    if (!mounted) return;
    final p = payload.trim();
    if (p == 'notif' || p.startsWith('notif:')) {
      await Navigator.of(context).push(
        MaterialPageRoute(builder: (_) => const NotificacionesPage()),
      );
      return;
    }
    if (p == 'chat' || p.startsWith('chat:')) {
      final id = p.startsWith('chat:') ? p.substring(5).trim() : '';
      _irAModulo('Comunicaciones');
      if (id.isEmpty) return;
      await ComunicacionesService.instance.refrescar();
      ChatConversacion? conv;
      for (final c in ComunicacionesService.instance.conversaciones) {
        if (c.id == id) {
          conv = c;
          break;
        }
      }
      if (conv != null && mounted) {
        await Navigator.of(context).push(
          MaterialPageRoute(builder: (_) => ChatPage(conversacion: conv!)),
        );
      }
    }
  }

  /// Sin nube PC y celular se desalinean. En Windows se activa sola al entrar.
  Future<void> _ofrecerActivarNubeSiHaceFalta() async {
    // No conectar a una empresa automática vacía: primero elegir código.
    if (!BackendConfigService.instance.empresaConfirmada) {
      return;
    }
    if (BackendConfigService.instance.firebaseEnabled) {
      // Ya activa: forzar un reconnect por si quedó a medias.
      // Windows: no bloquear el arranque de la UI con el catch-up de sync.
      if (PlatformCapabilities.isWindowsDesktop) {
        syncInBackground(
          AuthService.instance.conectarFirebaseDespuesDelLogin().then((_) {}),
          tag: 'reconnectNubeWindows',
        );
        return;
      }
      try {
        await AuthService.instance.conectarFirebaseDespuesDelLogin();
      } catch (_) {}
      return;
    }
    if (!mounted) return;
    // Activación automática: el sistema tiene que funcionar online sin pasos
    // fáciles de omitir. Si Firebase falla, queda Solo local y se avisa.
    // Windows: dar tiempo a que la UI pinte antes de conectar (evita crash).
    if (PlatformCapabilities.isWindowsDesktop) {
      await Future<void>.delayed(const Duration(milliseconds: 1200));
      if (!mounted) return;
    }
    final r = await AuthService.instance.activarNube();
    if (!mounted) return;
    final detalle = r.mensaje.replaceFirst('CUENTA_NUBE_EXISTE: ', '');
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(
          r.ok
              ? (PlatformCapabilities.isWindowsDesktop
                  ? 'Nube activada. Sync en segundo plano…'
                  : 'Nube activada.')
              : (detalle.isNotEmpty
                  ? 'No se pudo activar la nube: $detalle'
                  : 'No se pudo activar la nube. Reintentá en Configuración.'),
        ),
        duration: const Duration(seconds: 4),
      ),
    );
    if (mounted) setState(() {});
  }

  void _onSidebarPrefs() {
    if (!mounted) return;
    // No forzar Configuración: solo recalcular índice y limpiar caché.
    // El scroll del menú se preserva con PageStorageKey en el ListView.
    setState(() {
      final items = _visibleItems;
      _selectedIndex = _resolverIndiceSeleccionado(items);
      final ids = items.map((e) => e.preferenciaId).toSet();
      _pageCache.removeWhere((k, _) => !ids.contains(k));
    });
  }

  final Map<String, Widget> _pageCache = {};

  Widget _cachedPage(_ShellItem item) {
    return _pageCache.putIfAbsent(
      item.preferenciaId,
      () => item.builder(),
    );
  }

  void _onCommsChanged() {
    if (mounted) setState(() {});
  }

  @override
  void dispose() {
    BrandingService.instance.removeListener(_onBrandingChanged);
    ComunicacionesService.instance.removeListener(_onCommsChanged);
    DataRefreshHub.instance.removeListener(_onDatosRemotos);
    SidebarPreferenciasService.instance.removeListener(_onSidebarPrefs);
    LocalNotificationService.instance.onTap = null;
    super.dispose();
  }

  List<_ShellItem> get _items => [
        _ShellItem(
          icon: Icons.home_rounded,
          title: 'Inicio',
          modulo: 'dashboard',
          builder: () => InicioPage(
            onIrA: _irAModulo,
            onBuscar: () => _abrirBusqueda(
              desktop: MediaQuery.sizeOf(context).width >= kDesktopBreakpoint,
            ),
            onEscanear: _abrirScanner,
          ),
          quickAccess: true,
        ),
        _ShellItem(
          icon: Icons.point_of_sale_rounded,
          title: 'Venta Rápida',
          modulo: 'remitos',
          builder: () => const VentaRapidaPage(),
          quickAccess: true,
        ),
        _ShellItem(
          icon: Icons.inventory_2_rounded,
          title: 'Productos',
          modulo: 'productos',
          builder: () => const ProductosPage(),
          quickAccess: true,
        ),
        _ShellItem(
          icon: Icons.forum_rounded,
          title: 'Comunicaciones',
          modulo: 'comunicaciones',
          builder: () => const ComunicacionesPage(),
          quickAccess: true,
        ),
        _ShellItem(
          icon: Icons.query_stats_rounded,
          title: 'Dashboard',
          modulo: 'dashboard',
          builder: () => DashboardPage(onIrA: _irAModulo),
        ),
        _ShellItem(
          icon: Icons.delete_outline_rounded,
          title: 'Papelera',
          modulo: 'productos',
          builder: () => const PapeleraProductosPage(),
        ),
        _ShellItem(
          icon: Icons.category_rounded,
          title: 'Categorías',
          modulo: 'productos',
          builder: () => const CategoriasPage(),
        ),
        _ShellItem(
          icon: Icons.receipt_long_rounded,
          title: 'Ventas / Facturas',
          modulo: 'remitos',
          builder: () => const VentasPage(),
          quickAccess: true,
        ),
        _ShellItem(
          icon: Icons.request_quote_rounded,
          title: 'Presupuestos',
          modulo: 'remitos',
          builder: () => const VentasPage(
            titulo: 'Presupuestos',
            tipos: {'presupuesto': 'Presupuesto'},
          ),
        ),
        _ShellItem(
          icon: Icons.local_shipping_outlined,
          title: 'Entregas (sin factura)',
          modulo: 'remitos',
          builder: () => const VentasPage(
            titulo: 'Entregas (sin factura)',
            tipos: {'nota_entrega': 'Entrega sin factura'},
          ),
        ),
        _ShellItem(
          icon: Icons.article_outlined,
          title: 'Tickets internos',
          modulo: 'remitos',
          builder: () => const VentasPage(
            titulo: 'Tickets internos',
            tipos: {'comprobante_interno': 'Ticket interno'},
          ),
        ),
        _ShellItem(
          icon: Icons.compare_arrows_rounded,
          title: 'Comparador de listas',
          modulo: 'listas_precios',
          builder: () => const ComparacionPage(),
        ),
        _ShellItem(
          icon: Icons.hub_rounded,
          title: 'Importaciones',
          modulo: 'productos',
          builder: () => const CentroImportacionesPage(),
        ),
        _ShellItem(
          icon: Icons.upload_file_rounded,
          title: 'Importar Productos',
          modulo: 'productos',
          builder: () => const ImportacionPage(),
        ),
        _ShellItem(
          icon: Icons.warehouse_rounded,
          title: 'Stock',
          modulo: 'stock',
          builder: () => const StockPage(),
        ),
        _ShellItem(
          icon: Icons.shopping_cart_rounded,
          title: 'Compras',
          modulo: 'compras',
          builder: () => const ComprasPage(),
        ),
        _ShellItem(
          icon: Icons.description_rounded,
          title: 'Remitos',
          modulo: 'remitos',
          builder: () => const RemitosPage(),
        ),
        _ShellItem(
          icon: Icons.groups_rounded,
          title: 'Clientes',
          modulo: 'clientes',
          builder: () => const ClientesPage(),
        ),
        _ShellItem(
          icon: Icons.folder_shared_rounded,
          title: 'Archivo PDF',
          modulo: 'clientes',
          builder: () => const ArchivoPdfsPage(),
        ),
        _ShellItem(
          icon: Icons.account_balance_wallet_rounded,
          title: 'Cuenta corriente',
          modulo: 'clientes',
          builder: () => const ClientesDeudoresPage(),
        ),
        _ShellItem(
          icon: Icons.local_shipping_rounded,
          title: 'Proveedores',
          modulo: 'proveedores',
          builder: () => const ProveedoresPage(),
        ),
        _ShellItem(
          icon: Icons.sell_rounded,
          title: 'Listas de Precios',
          modulo: 'listas_precios',
          builder: () => const ListasPrecioPage(),
        ),
        _ShellItem(
          icon: Icons.bar_chart_rounded,
          title: 'Reportes',
          modulo: 'reportes',
          builder: () => const ReportesPage(),
        ),
        _ShellItem(
          icon: Icons.insights_rounded,
          title: 'Inteligencia Comercial',
          modulo: 'reportes',
          builder: () => const InteligenciaComercialPage(),
        ),
        _ShellItem(
          icon: Icons.label_rounded,
          title: 'Etiquetas',
          modulo: 'etiquetas',
          builder: () => const EtiquetasPage(),
        ),
        _ShellItem(
          icon: Icons.history_edu_rounded,
          title: 'Auditoría',
          modulo: 'auditoria',
          builder: () => const AuditoriaPage(),
        ),
        _ShellItem(
          icon: Icons.manage_accounts_rounded,
          title: 'Mi perfil',
          modulo: 'dashboard',
          builder: () => const PerfilUsuarioPage(),
        ),
        _ShellItem(
          icon: Icons.people_alt_rounded,
          title: 'Usuarios',
          modulo: 'usuarios',
          builder: () => const UsuariosPage(),
        ),
        _ShellItem(
          icon: Icons.admin_panel_settings_rounded,
          title: 'Permisos',
          modulo: 'usuarios',
          builder: () => const PermisosPage(),
        ),
        _ShellItem(
          icon: Icons.cloud_upload_rounded,
          title: 'Respaldo',
          modulo: 'backup',
          builder: () => const BackupPage(),
        ),
        _ShellItem(
          icon: Icons.monitor_heart_rounded,
          title: 'Panel técnico',
          modulo: 'auditoria',
          builder: () => const PanelTecnicoPage(),
          soloAdmin: true,
        ),
        _ShellItem(
          icon: Icons.route_rounded,
          title: 'Primeros pasos',
          modulo: 'dashboard',
          builder: () => PrimerosPasosPage(onIrA: _irAModulo),
        ),
        _ShellItem(
          icon: Icons.menu_book_rounded,
          title: 'Manual de usuario',
          modulo: 'dashboard',
          builder: () => const ManualUsuarioPage(),
        ),
        _ShellItem(
          icon: Icons.settings_rounded,
          title: 'Configuración',
          modulo: 'configuracion',
          builder: () => const ConfiguracionPage(),
        ),
      ];

  List<_ShellItem> get _visibleItems {
    final rol = AuthService.instance.currentUser?.rol ?? 'empleado';
    final prefs = SidebarPreferenciasService.instance;
    final isAdmin = AuthService.instance.esAdministrador();
    return _items
        .where((item) => !item.soloAdmin || isAdmin)
        .where((item) => PermisosService.instance.puedeVer(rol, item.modulo))
        .where((item) => prefs.estaVisible(item.preferenciaId))
        .toList();
  }

  /// Mantiene la misma pantalla al ocultar/mostrar ítems del menú.
  /// Nunca reutiliza un índice “viejo”: al crecer/achicar la lista el mismo
  /// número apunta a otro módulo (ej. Manual en lugar de Configuración).
  int _resolverIndiceSeleccionado(List<_ShellItem> items) {
    if (items.isEmpty) return 0;

    final id = _selectedPreferenciaId;
    if (id != null) {
      final i = items.indexWhere((e) => e.preferenciaId == id);
      if (i >= 0) return i;
    }

    // La página actual se ocultó (o aún no hay id): Configuración → Inicio.
    const cfgId = 'configuracion|Configuración';
    final cfg = items.indexWhere((e) => e.preferenciaId == cfgId);
    if (cfg >= 0) {
      _selectedPreferenciaId = cfgId;
      return cfg;
    }
    final ini = items.indexWhere((e) => e.title == 'Inicio');
    if (ini >= 0) {
      _selectedPreferenciaId = items[ini].preferenciaId;
      return ini;
    }
    _selectedPreferenciaId = items.first.preferenciaId;
    return 0;
  }

  int _safeIndex(List<_ShellItem> items) {
    final i = _resolverIndiceSeleccionado(items);
    if (_selectedIndex != i) {
      // Mantener el campo en sync sin setState extra (estamos en build).
      _selectedIndex = i;
    }
    return i;
  }

  void _select(int index) {
    final items = _visibleItems;
    if (index < 0 || index >= items.length) return;
    final id = items[index].preferenciaId;
    if (_selectedIndex == index && _selectedPreferenciaId == id) return;
    setState(() {
      _selectedIndex = index;
      _selectedPreferenciaId = id;
    });
  }

  void _irAConfiguracion() {
    final items = _visibleItems;
    final idx = items.indexWhere(
      (e) => e.preferenciaId == 'configuracion|Configuración',
    );
    if (idx >= 0) {
      _select(idx);
      return;
    }
    // Si Config está oculta en el menú, abrirla igual (push).
    Navigator.of(context).push(
      MaterialPageRoute(builder: (_) => const ConfiguracionPage()),
    );
  }

  Future<void> _logout() async {
    final olvidar = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Cerrar sesión'),
        content: const Text(
          '¿También querés desactivar el desbloqueo biométrico en este dispositivo?',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('Solo salir'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('Salir y olvidar'),
          ),
        ],
      ),
    );
    if (olvidar == null) return;
    await ComunicacionesService.instance.detener();
    await AuthService.instance.logout(olvidarHuella: olvidar);
    if (!mounted) return;
    Navigator.of(context).pushAndRemoveUntil(
      MaterialPageRoute(builder: (_) => const LoginPage()),
      (_) => false,
    );
  }

  void _irAInicio() {
    final items = _visibleItems;
    final idx = items.indexWhere((e) => e.title == 'Inicio');
    if (idx >= 0) _select(idx);
  }

  Widget _paginaBusqueda({String? consultaInicial}) {
    return BusquedaGlobalPage(
      consultaInicial: consultaInicial,
      onIrAModulo: _irAModulo,
    );
  }

  Future<void> _abrirBusqueda({required bool desktop}) async {
    if (desktop) {
      await showDialog<void>(
        context: context,
        builder: (ctx) => Dialog.fullscreen(
          backgroundColor: Theme.of(ctx).colorScheme.surface,
          child: _paginaBusqueda(),
        ),
      );
    } else {
      await Navigator.push(
        context,
        MaterialPageRoute(builder: (_) => _paginaBusqueda()),
      );
    }
  }

  Future<void> _abrirScanner() async {
    final codigo = await Navigator.push<String>(
      context,
      MaterialPageRoute(builder: (_) => const ScannerPage()),
    );
    if (codigo == null || codigo.trim().isEmpty || !mounted) return;
    // Abrir búsqueda con el código escaneado
    await showDialog<void>(
      context: context,
      builder: (ctx) => Dialog.fullscreen(
        backgroundColor: Theme.of(ctx).colorScheme.surface,
        child: _paginaBusqueda(consultaInicial: codigo.trim()),
      ),
    );
  }

  void _irAModulo(String title) {
    final items = _visibleItems;
    final idx = items.indexWhere((e) => e.title == title);
    if (idx >= 0) _select(idx);
  }

  // ignore: unused_element
  Future<void> _mostrarRecordatorioCc() async {
    if (_recordatorioMostrado || !mounted) return;
    _recordatorioMostrado = true;
    try {
      final resumen = await CuentaCorrienteService().resumenDashboard();
      if (!mounted || resumen.alertas.isEmpty) return;
      final vencidas = resumen.alertas
          .where((a) => a.toLowerCase().contains('vencid'))
          .toList();
      final relevantes = vencidas.isNotEmpty ? vencidas : resumen.alertas.take(3).toList();
      if (relevantes.isEmpty) return;

      await showDialog<void>(
        context: context,
        builder: (ctx) => AlertDialog(
          title: const Row(
            children: [
              Icon(Icons.notifications_active_rounded),
              SizedBox(width: 8),
              Expanded(child: Text('Cuentas por cobrar')),
            ],
          ),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                'Pendiente: \$${resumen.montoTotalPendiente.toStringAsFixed(2)}',
                style: const TextStyle(fontWeight: FontWeight.bold),
              ),
              const SizedBox(height: 8),
              ...relevantes.map((a) => Padding(
                    padding: const EdgeInsets.only(bottom: 4),
                    child: Text('• $a'),
                  )),
            ],
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(ctx),
              child: const Text('Después'),
            ),
            FilledButton(
              onPressed: () {
                Navigator.pop(ctx);
                _irAModulo('Cuenta corriente');
              },
              child: const Text('Ver cuentas'),
            ),
          ],
        ),
      );
    } catch (_) {}
  }

  @override
  Widget build(BuildContext context) {
    final desktop = MediaQuery.sizeOf(context).width >= kDesktopBreakpoint;
    return CallbackShortcuts(
      bindings: <ShortcutActivator, VoidCallback>{
        const SingleActivator(LogicalKeyboardKey.keyK, control: true): () =>
            _abrirBusqueda(desktop: desktop),
        const SingleActivator(LogicalKeyboardKey.keyF, control: true): () =>
            _abrirBusqueda(desktop: desktop),
        const SingleActivator(LogicalKeyboardKey.keyB, control: true): _abrirScanner,
        const SingleActivator(LogicalKeyboardKey.digit1, control: true): () =>
            _irAModulo('Inicio'),
        const SingleActivator(LogicalKeyboardKey.digit2, control: true): () =>
            _irAModulo('Venta Rápida'),
        const SingleActivator(LogicalKeyboardKey.digit3, control: true): () =>
            _irAModulo('Productos'),
        const SingleActivator(LogicalKeyboardKey.digit4, control: true): () =>
            _irAModulo('Comunicaciones'),
        const SingleActivator(LogicalKeyboardKey.digit5, control: true): () =>
            _irAModulo('Ventas / Facturas'),
        const SingleActivator(LogicalKeyboardKey.keyH, control: true): () {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content: Text(
                'Atajos: Ctrl+K buscar · Ctrl+B escanear · Ctrl+1..5 módulos',
              ),
              duration: Duration(seconds: 4),
            ),
          );
        },
      },
      child: Focus(
        autofocus: true,
        child: LayoutBuilder(
          builder: (context, constraints) {
            final isDesktop = constraints.maxWidth >= kDesktopBreakpoint;
            if (isDesktop) {
              return _buildDesktopLayout();
            }
            return _buildMobileLayout();
          },
        ),
      ),
    );
  }

  Widget _buildDesktopLayout() {
    final items = _visibleItems;
    final index = _safeIndex(items);
    return PopScope(
      canPop: false,
      onPopInvokedWithResult: (didPop, _) {
        if (didPop) return;
        if (Navigator.of(context).canPop()) {
          Navigator.of(context).pop();
          return;
        }
        _irAInicio();
      },
      child: ShellHost(
        embedded: true,
        goHome: _irAInicio,
        child: Scaffold(
          body: Column(
            children: [
              _TopBar(
                onSearch: () => _abrirBusqueda(desktop: true),
                onLogout: _logout,
                onHome: _irAInicio,
                onSettings: _irAConfiguracion,
              ),
              Expanded(
                child: Row(
                  children: [
                    _Sidebar(
                      selectedIndex: index,
                      items: items,
                      onTap: _select,
                      onLogout: _logout,
                    ),
                    Expanded(
                      child: items.isEmpty
                          ? _SidebarVacia(
                              onAbrirConfig: _irAConfiguracion,
                            )
                          : IndexedStack(
                              index: index,
                              children: [
                                for (final item in items)
                                  KeyedSubtree(
                                    key: ValueKey(item.preferenciaId),
                                    child: _cachedPage(item),
                                  ),
                              ],
                            ),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildMobileLayout() {
    final items = _visibleItems;
    final index = _safeIndex(items);
    final current = items.isNotEmpty ? items[index] : null;
    final quickItems = items.where((item) => item.quickAccess).take(5).toList();
    final cs = Theme.of(context).colorScheme;
    final bottomIndex = quickItems.indexWhere(
      (e) => e.preferenciaId == current?.preferenciaId,
    );

    return PopScope(
      canPop: false,
      onPopInvokedWithResult: (didPop, _) {
        if (didPop) return;
        if (Navigator.of(context).canPop()) {
          Navigator.of(context).pop();
          return;
        }
        if (current?.title != 'Inicio') {
          _irAInicio();
          return;
        }
      },
      child: ShellHost(
        embedded: true,
        goHome: _irAInicio,
        child: Scaffold(
          key: _mobileScaffoldKey,
          appBar: AppBar(
            leading: IconButton(
              tooltip: 'Menú',
              icon: const Icon(Icons.menu_rounded),
              onPressed: () => _mobileScaffoldKey.currentState?.openDrawer(),
            ),
            title: Text(
              current?.title ?? 'Manager',
              style: TextStyle(
                color: cs.onSurface,
                fontWeight: FontWeight.w700,
              ),
            ),
            centerTitle: true,
            actions: [
              IconButton(
                tooltip: 'Inicio',
                icon: const Icon(Icons.home_rounded),
                onPressed: _irAInicio,
              ),
              const Padding(
                padding: EdgeInsets.only(right: 4),
                child: Center(child: ShellSyncBadge(compact: true)),
              ),
              IconButton(
                onPressed: () => _abrirBusqueda(desktop: false),
                icon: const Icon(Icons.search_rounded),
                tooltip: 'Búsqueda global',
              ),
              IconButton(
                onPressed: () {
                  Navigator.push(
                    context,
                    MaterialPageRoute(
                      builder: (_) => const NotificacionesPage(),
                    ),
                  );
                },
                icon: Badge(
                  isLabelVisible:
                      ComunicacionesService.instance.badgeTotal > 0,
                  label:
                      Text('${ComunicacionesService.instance.badgeTotal}'),
                  child: const Icon(Icons.notifications_rounded),
                ),
                tooltip: 'Notificaciones',
              ),
              Padding(
                padding: const EdgeInsets.only(right: 8),
                child: InkWell(
                  onTap: () {
                    Navigator.of(context).push(
                      MaterialPageRoute(
                        builder: (_) => const PerfilUsuarioPage(),
                      ),
                    );
                  },
                  borderRadius: BorderRadius.circular(20),
                  child: CircleAvatar(
                    radius: 16,
                    backgroundColor: cs.primaryContainer,
                    backgroundImage: imageProviderDesdePath(
                      AuthService.instance.currentUser?.foto,
                    ),
                    child:
                        (AuthService.instance.currentUser?.foto ?? '').isEmpty
                            ? Text(
                                (AuthService.instance.currentUser?.nombre ??
                                        'A')
                                    .substring(0, 1)
                                    .toUpperCase(),
                                style: TextStyle(
                                  color: cs.onPrimaryContainer,
                                  fontWeight: FontWeight.bold,
                                  fontSize: 14,
                                ),
                              )
                            : null,
                  ),
                ),
              ),
            ],
          ),
          drawer: Drawer(
            backgroundColor: _kSidebarBg,
            width: 260,
            child: _SidebarContent(
              selectedIndex: index,
              items: items,
              onTap: (i) {
                Navigator.of(context).pop();
                _select(i);
              },
              onLogout: _logout,
            ),
          ),
          body: items.isEmpty
              ? const Center(child: Text('Sin módulos disponibles'))
              : IndexedStack(
                  index: index,
                  children: [
                    for (final item in items)
                      KeyedSubtree(
                        key: ValueKey(item.preferenciaId),
                        child: _cachedPage(item),
                      ),
                  ],
                ),
          bottomNavigationBar: quickItems.isEmpty
              ? null
              : SafeArea(
                  top: false,
                  child: BottomNavigationBar(
                    backgroundColor: cs.surfaceContainerLow,
                    selectedItemColor:
                        bottomIndex < 0 ? cs.onSurfaceVariant : cs.primary,
                    unselectedItemColor: cs.onSurfaceVariant,
                    type: BottomNavigationBarType.fixed,
                    currentIndex: bottomIndex < 0 ? 0 : bottomIndex,
                    onTap: (i) => _select(items.indexOf(quickItems[i])),
                    items: quickItems
                        .map(
                          (item) => BottomNavigationBarItem(
                            icon: Icon(item.icon),
                            label: item.title,
                          ),
                        )
                        .toList(),
                  ),
                ),
        ),
      ),
    );
  }
}

class _Sidebar extends StatelessWidget {
  final int selectedIndex;
  final List<_ShellItem> items;
  final ValueChanged<int> onTap;
  final VoidCallback onLogout;

  const _Sidebar({
    required this.selectedIndex,
    required this.items,
    required this.onTap,
    required this.onLogout,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      width: AppTokens.sidebarWidth,
      decoration: BoxDecoration(
        color: _kSidebarBg,
        border: Border(right: BorderSide(color: _kSidebarBorder)),
      ),
      child: _SidebarContent(
        selectedIndex: selectedIndex,
        items: items,
        onTap: onTap,
        onLogout: onLogout,
      ),
    );
  }
}

class _SidebarContent extends StatefulWidget {
  final int selectedIndex;
  final List<_ShellItem> items;
  final ValueChanged<int> onTap;
  final VoidCallback onLogout;

  const _SidebarContent({
    required this.selectedIndex,
    required this.items,
    required this.onTap,
    required this.onLogout,
  });

  @override
  State<_SidebarContent> createState() => _SidebarContentState();
}

class _SidebarContentState extends State<_SidebarContent> {
  final Set<String> _colapsadas = {};

  @override
  Widget build(BuildContext context) {
    final items = widget.items;
    final selectedIndex = widget.selectedIndex;
    final onTap = widget.onTap;
    final onLogout = widget.onLogout;
    final branding = BrandingService.instance;
    final logoPath = branding.imagenUiPath;
    final cs = Theme.of(context).colorScheme;
    final selectedBg = cs.primary;
    final selectedFg = cs.onPrimary;

    final agrupado = <String, List<({_ShellItem item, int index})>>{};
    for (var i = 0; i < items.length; i++) {
      final sec = _seccionDeTitulo(items[i].title);
      agrupado.putIfAbsent(sec, () => []).add((item: items[i], index: i));
    }

    return SafeArea(
      child: Column(
        children: [
          Container(
            width: double.infinity,
            padding: const EdgeInsets.fromLTRB(16, 18, 16, 14),
            decoration: BoxDecoration(
              border: Border(bottom: BorderSide(color: _kSidebarHeaderBorder)),
            ),
            child: Column(
              children: [
                MediaAvatar(
                  key: ValueKey(
                    'sidebar-logo-${branding.logoUiPath.isNotEmpty ? branding.logoUiPath : logoPath}',
                  ),
                  path: branding.logoUiPath.isNotEmpty
                      ? branding.logoUiPath
                      : logoPath,
                  radius: 28,
                  fallbackLetter:
                      branding.nombre.isNotEmpty ? branding.nombre[0] : 'T',
                  backgroundColor: AppTokens.inkSoft,
                  foregroundColor: Colors.white70,
                ),
                const SizedBox(height: 8),
                Text(
                  branding.nombre,
                  style: const TextStyle(
                    color: Colors.white,
                    fontWeight: FontWeight.w700,
                    fontSize: 14,
                  ),
                  textAlign: TextAlign.center,
                  overflow: TextOverflow.ellipsis,
                ),
                if (branding.slogan.isNotEmpty)
                  Text(
                    branding.slogan,
                    style: TextStyle(color: _kSidebarSubtext, fontSize: 11),
                    textAlign: TextAlign.center,
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                  ),
                const SizedBox(height: 10),
                const Align(
                  alignment: Alignment.centerLeft,
                  child: ShellSyncBadge(compact: true),
                ),
              ],
            ),
          ),
          Expanded(
            child: ListView(
              key: const PageStorageKey<String>('shell_sidebar_nav'),
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 8),
              children: [
                for (final sec in _kOrdenSecciones)
                  if (agrupado.containsKey(sec)) ...[
                    if (sec == 'Inicio')
                      ...agrupado[sec]!.map((e) {
                        final selected = selectedIndex == e.index;
                        return _navTile(
                          item: e.item,
                          selected: selected,
                          selectedBg: selectedBg,
                          selectedFg: selectedFg,
                          onTap: () => onTap(e.index),
                        );
                      })
                    else ...[
                      InkWell(
                        onTap: () {
                          setState(() {
                            if (_colapsadas.contains(sec)) {
                              _colapsadas.remove(sec);
                            } else {
                              _colapsadas.add(sec);
                            }
                          });
                        },
                        borderRadius: BorderRadius.circular(6),
                        child: Padding(
                          padding: const EdgeInsets.fromLTRB(10, 12, 8, 4),
                          child: Row(
                            children: [
                              Icon(
                                _iconoSeccion(sec),
                                size: 14,
                                color: _kSidebarSubtext,
                              ),
                              const SizedBox(width: 6),
                              Expanded(
                                child: Text(
                                  sec.toUpperCase(),
                                  style: TextStyle(
                                    color: _kSidebarSubtext,
                                    fontSize: 10,
                                    fontWeight: FontWeight.w700,
                                    letterSpacing: 0.8,
                                  ),
                                ),
                              ),
                              Icon(
                                _colapsadas.contains(sec)
                                    ? Icons.chevron_right_rounded
                                    : Icons.expand_more_rounded,
                                size: 16,
                                color: _kSidebarSubtext,
                              ),
                            ],
                          ),
                        ),
                      ),
                      if (!_colapsadas.contains(sec))
                        ...agrupado[sec]!.map((e) {
                          final selected = selectedIndex == e.index;
                          return _navTile(
                            item: e.item,
                            selected: selected,
                            selectedBg: selectedBg,
                            selectedFg: selectedFg,
                            onTap: () => onTap(e.index),
                          );
                        }),
                    ],
                  ],
              ],
            ),
          ),
          // ── Usuario logueado ──────────────────────────────────────────────────
          Container(
            margin: const EdgeInsets.fromLTRB(10, 0, 10, 10),
            padding: const EdgeInsets.all(10),
            decoration: BoxDecoration(
              color: _kSidebarUserBg,
              borderRadius: BorderRadius.circular(10),
            ),
            child: InkWell(
              onTap: () {
                Navigator.of(context).push(
                  MaterialPageRoute(
                    builder: (_) => const PerfilUsuarioPage(),
                  ),
                );
              },
              borderRadius: BorderRadius.circular(10),
              child: Row(
                children: [
                  CircleAvatar(
                    radius: 16,
                    backgroundColor: const Color(0xFF2A2A2A),
                    backgroundImage: imageProviderDesdePath(
                      AuthService.instance.currentUser?.foto,
                    ),
                    child:
                        (AuthService.instance.currentUser?.foto ?? '').isEmpty
                            ? Text(
                                (AuthService.instance.currentUser?.nombre ??
                                        'A')
                                    .substring(0, 1)
                                    .toUpperCase(),
                                style: const TextStyle(
                                  color: Colors.white70,
                                  fontWeight: FontWeight.bold,
                                  fontSize: 14,
                                ),
                              )
                            : null,
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Text(
                          AuthService.instance.currentUser?.nombre ??
                              'Usuario',
                          style: const TextStyle(
                            color: Colors.white,
                            fontSize: 12,
                            fontWeight: FontWeight.w600,
                          ),
                          overflow: TextOverflow.ellipsis,
                        ),
                        Text(
                          AuthService.instance.currentUser?.rol ??
                              'Editar perfil',
                          style: TextStyle(
                            color: _kSidebarSubtext,
                            fontSize: 11,
                          ),
                          overflow: TextOverflow.ellipsis,
                        ),
                      ],
                    ),
                  ),
                  IconButton(
                    icon: Icon(
                      Icons.logout_rounded,
                      color: _kSidebarInactiveIcon,
                      size: 20,
                    ),
                    tooltip: 'Cerrar sesión',
                    onPressed: onLogout,
                    padding: EdgeInsets.zero,
                    constraints: const BoxConstraints(),
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _navTile({
    required _ShellItem item,
    required bool selected,
    required Color selectedBg,
    required Color selectedFg,
    required VoidCallback onTap,
  }) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 1),
      child: Material(
        color: selected ? selectedBg : Colors.transparent,
        borderRadius: BorderRadius.circular(AppTokens.radiusSm),
        child: ListTile(
          dense: true,
          visualDensity: VisualDensity.compact,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(AppTokens.radiusSm),
          ),
          leading: Icon(
            item.icon,
            color: selected ? selectedFg : _kSidebarInactiveIcon,
            size: 20,
          ),
          title: Text(
            item.title,
            style: TextStyle(
              color: selected ? selectedFg : _kSidebarInactiveText,
              fontWeight: selected ? FontWeight.w700 : FontWeight.w500,
              fontSize: 13,
            ),
          ),
          onTap: onTap,
        ),
      ),
    );
  }
}

class _SidebarVacia extends StatelessWidget {
  final VoidCallback onAbrirConfig;
  const _SidebarVacia({required this.onAbrirConfig});

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(Icons.view_sidebar_outlined, size: 48),
            const SizedBox(height: 12),
            const Text(
              'La barra lateral está vacía.\n'
              'Podés elegir qué mostrar en Configuración.',
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 16),
            FilledButton.icon(
              onPressed: onAbrirConfig,
              icon: const Icon(Icons.settings_rounded),
              label: const Text('Abrir configuración'),
            ),
          ],
        ),
      ),
    );
  }
}

// ── Barra superior de escritorio ─────────────────────────────────────────────
class _TopBar extends StatelessWidget {
  final VoidCallback onSearch;
  final VoidCallback onLogout;
  final VoidCallback onHome;
  final VoidCallback onSettings;

  const _TopBar({
    required this.onSearch,
    required this.onLogout,
    required this.onHome,
    required this.onSettings,
  });

  @override
  Widget build(BuildContext context) {
    final branding = BrandingService.instance;
    final logoPath = branding.logoUiPath.isNotEmpty
        ? branding.logoUiPath
        : branding.imagenUiPath;
    final userName = AuthService.instance.currentUser?.nombre ?? 'Usuario';
    final userInitial = userName.substring(0, 1).toUpperCase();

    return Container(
      height: AppTokens.topBarHeight,
      padding: const EdgeInsets.symmetric(horizontal: 14),
      decoration: BoxDecoration(
        color: _kSidebarBg,
        border: Border(bottom: BorderSide(color: _kSidebarBorder)),
      ),
      child: Row(
        children: [
          IconButton(
            tooltip: 'Inicio',
            onPressed: onHome,
            icon: const Icon(Icons.home_rounded, color: Colors.white),
          ),
          MediaAvatar(
            key: ValueKey('topbar-logo-$logoPath'),
            path: logoPath,
            radius: 16,
            fallbackLetter:
                branding.nombre.isNotEmpty ? branding.nombre[0] : 'T',
            backgroundColor: AppTokens.inkSoft,
            foregroundColor: Colors.white70,
          ),
          const SizedBox(width: 10),
          Flexible(
            child: Text(
              branding.nombre,
              style: const TextStyle(
                color: Colors.white,
                fontWeight: FontWeight.w700,
                fontSize: 15,
              ),
              overflow: TextOverflow.ellipsis,
            ),
          ),
          const SizedBox(width: 12),
          const ShellSyncBadge(),
          const Spacer(),
          IconButton(
            tooltip: 'Configuración',
            onPressed: onSettings,
            icon: Icon(Icons.settings_rounded, color: _kSidebarInactiveIcon),
          ),
          GestureDetector(
            onTap: onSearch,
            child: Container(
              height: 36,
              width: 260,
              decoration: BoxDecoration(
                color: AppTokens.inkSoft,
                borderRadius: BorderRadius.circular(AppTokens.radiusMd),
                border: Border.all(
                  color: AppTokens.brandOrange.withValues(alpha: 0.45),
                ),
              ),
              child: Row(
                children: [
                  const SizedBox(width: 10),
                  Icon(Icons.search_rounded,
                      color: AppTokens.brandOrange, size: 17),
                  const SizedBox(width: 8),
                  Text(
                    'Buscar en todo…  Ctrl+K',
                    style: TextStyle(color: _kSidebarSubtext, fontSize: 12),
                  ),
                ],
              ),
            ),
          ),
          const SizedBox(width: 10),
          IconButton(
            icon: Badge(
              isLabelVisible: ComunicacionesService.instance.badgeTotal > 0,
              label: Text('${ComunicacionesService.instance.badgeTotal}'),
              child: const Icon(Icons.notifications_rounded),
            ),
            color: _kSidebarInactiveIcon,
            tooltip: 'Notificaciones',
            onPressed: () {
              Navigator.push(
                context,
                MaterialPageRoute(builder: (_) => const NotificacionesPage()),
              );
            },
          ),
          InkWell(
            onTap: () {
              Navigator.of(context).push(
                MaterialPageRoute(builder: (_) => const PerfilUsuarioPage()),
              );
            },
            borderRadius: BorderRadius.circular(20),
            child: CircleAvatar(
              radius: 16,
              backgroundColor: AppTokens.inkSoft,
              backgroundImage: imageProviderDesdePath(
                AuthService.instance.currentUser?.foto,
              ),
              child: (AuthService.instance.currentUser?.foto ?? '').isEmpty
                  ? Text(
                      userInitial,
                      style: const TextStyle(
                        color: Colors.white,
                        fontWeight: FontWeight.bold,
                        fontSize: 13,
                      ),
                    )
                  : null,
            ),
          ),
          IconButton(
            tooltip: 'Cerrar sesión',
            onPressed: onLogout,
            icon: Icon(Icons.logout_rounded, color: _kSidebarInactiveIcon),
          ),
        ],
      ),
    );
  }
}

