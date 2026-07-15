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
import '../core/config/backend_config_service.dart';
import '../core/firebase/firebase_auth_usuario_service.dart';
import '../core/sync/firestore_sync_service.dart';
import '../theme/layout_constants.dart';
import '../theme/module_app_bar.dart';
import '../widgets/media_avatar.dart';
import 'archivo_pdfs_page.dart';
import 'auditoria_page.dart';
import 'backup_page.dart';
import 'busqueda_global_page.dart';
import 'categorias_page.dart';
import 'centro_importaciones_page.dart';
import 'clientes_page.dart';
import 'clientes_deudores_page.dart';
import 'comparacion_page.dart';
import 'compras_page.dart';
import 'comunicaciones_page.dart';
import 'configuracion_page.dart';
import 'dashboard_page.dart';
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

// ── Barra lateral oscura; el acento seleccionado sigue el color de Config ─────
const Color _kSidebarBg = Color(0xFF000000);
const Color _kSidebarBorder = Color(0xFF1A1A1A);
const Color _kSidebarHeaderBorder = Color(0xFF2A2A2A);
const Color _kSidebarInactiveIcon = Color(0xFF9CA3AF);
const Color _kSidebarInactiveText = Color(0xFFD1D5DB);
const Color _kSidebarUserBg = Color(0xFF141414);
const Color _kSidebarSubtext = Color(0xFF6B7280);

class _ShellItem {
  final IconData icon;
  final String title;
  final String modulo;
  final Widget Function() builder;
  final bool quickAccess;

  const _ShellItem({
    required this.icon,
    required this.title,
    required this.modulo,
    required this.builder,
    this.quickAccess = false,
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
      if (mounted) _mostrarRecordatorioCc();
    });
  }

  void _onSidebarPrefs() {
    if (!mounted) return;
    setState(() {
      _selectedIndex = _resolverIndiceSeleccionado(_visibleItems);
    });
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
    super.dispose();
  }

  List<_ShellItem> get _items => [
        _ShellItem(
          icon: Icons.home_rounded,
          title: 'Inicio',
          modulo: 'dashboard',
          builder: () => const InicioPage(),
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
          builder: () => const DashboardPage(),
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
          title: 'Notas de entrega',
          modulo: 'remitos',
          builder: () => const VentasPage(
            titulo: 'Notas de entrega',
            tipos: {'nota_entrega': 'Nota de entrega'},
          ),
        ),
        _ShellItem(
          icon: Icons.article_outlined,
          title: 'Comprobantes internos',
          modulo: 'remitos',
          builder: () => const VentasPage(
            titulo: 'Comprobantes internos',
            tipos: {'comprobante_interno': 'Comprobante interno'},
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
    return _items
        .where((item) => PermisosService.instance.puedeVer(rol, item.modulo))
        .where((item) => prefs.estaVisible(item.preferenciaId))
        .toList();
  }

  /// Mantiene la misma pantalla al ocultar/mostrar ítems del menú.
  int _resolverIndiceSeleccionado(List<_ShellItem> items) {
    if (items.isEmpty) return 0;
    final id = _selectedPreferenciaId;
    if (id != null) {
      final i = items.indexWhere((e) => e.preferenciaId == id);
      if (i >= 0) return i;
    }
    // La página actual se ocultó: quedarse en Configuración si está, si no Inicio.
    final cfg = items.indexWhere(
      (e) => e.preferenciaId == 'configuracion|Configuración',
    );
    if (cfg >= 0) {
      _selectedPreferenciaId = items[cfg].preferenciaId;
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
    return _resolverIndiceSeleccionado(items);
  }

  void _select(int index) {
    final items = _visibleItems;
    if (index < 0 || index >= items.length) return;
    if (_selectedIndex == index &&
        _selectedPreferenciaId == items[index].preferenciaId) {
      return;
    }
    setState(() {
      _selectedIndex = index;
      _selectedPreferenciaId = items[index].preferenciaId;
    });
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

  Future<void> _abrirBusqueda({required bool desktop}) async {
    if (desktop) {
      await showDialog<void>(
        context: context,
        builder: (ctx) => Dialog.fullscreen(
          backgroundColor: Theme.of(ctx).colorScheme.surface,
          child: const BusquedaGlobalPage(),
        ),
      );
    } else {
      await Navigator.push(
        context,
        MaterialPageRoute(builder: (_) => const BusquedaGlobalPage()),
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
        child: BusquedaGlobalPage(consultaInicial: codigo.trim()),
      ),
    );
  }

  void _irAModulo(String title) {
    final items = _visibleItems;
    final idx = items.indexWhere((e) => e.title == title);
    if (idx >= 0) _select(idx);
  }

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
                onSettings: () {
                  Navigator.of(context).push(
                    MaterialPageRoute(
                      builder: (_) => const ConfiguracionPage(),
                    ),
                  );
                },
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
                              onAbrirConfig: () {
                                Navigator.of(context).push(
                                  MaterialPageRoute(
                                    builder: (_) => const ConfiguracionPage(),
                                  ),
                                );
                              },
                            )
                          : IndexedStack(
                              index: index,
                              children: [
                                for (final item in items)
                                  KeyedSubtree(
                                    key: ValueKey(item.preferenciaId),
                                    child: item.builder(),
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
    final quickItems = items.where((item) => item.quickAccess).take(4).toList();
    final cs = Theme.of(context).colorScheme;

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
          appBar: AppBar(
            leading: IconButton(
              tooltip: 'Inicio',
              icon: const Icon(Icons.home_rounded),
              onPressed: _irAInicio,
            ),
            title: Text(
              current?.title ?? 'EL TATA Manager',
              style: TextStyle(
                color: cs.onSurface,
                fontWeight: FontWeight.w700,
              ),
            ),
            centerTitle: true,
            actions: [
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
                        child: item.builder(),
                      ),
                  ],
                ),
          bottomNavigationBar: quickItems.isEmpty
              ? null
              : SafeArea(
                  top: false,
                  child: BottomNavigationBar(
                    backgroundColor: cs.surfaceContainerLow,
                    selectedItemColor: cs.primary,
                    unselectedItemColor: cs.onSurfaceVariant,
                    type: BottomNavigationBarType.fixed,
                    currentIndex: quickItems.contains(current)
                        ? quickItems.indexOf(current!)
                        : 0,
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
      width: 230,
      decoration: const BoxDecoration(
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

class _SidebarContent extends StatelessWidget {
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
  Widget build(BuildContext context) {
    final branding = BrandingService.instance;
    final logoPath = branding.imagenUiPath;
    final cs = Theme.of(context).colorScheme;
    final selectedBg = cs.primary;
    final selectedFg = cs.onPrimary;

    return SafeArea(
      child: Column(
        children: [
          // ── Encabezado (logo + nombre del negocio) ────────────────────────────
          Container(
            width: double.infinity,
            padding: const EdgeInsets.fromLTRB(16, 20, 16, 16),
            decoration: const BoxDecoration(
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
                  radius: 30,
                  fallbackLetter:
                      branding.nombre.isNotEmpty ? branding.nombre[0] : 'T',
                  backgroundColor: const Color(0xFF1A1A1A),
                  foregroundColor: Colors.white70,
                ),
                const SizedBox(height: 8),
                Text(
                  branding.nombre,
                  style: const TextStyle(
                    color: Colors.white,
                    fontWeight: FontWeight.bold,
                    fontSize: 14,
                  ),
                  textAlign: TextAlign.center,
                  overflow: TextOverflow.ellipsis,
                ),
                if (branding.slogan.isNotEmpty)
                  Text(
                    branding.slogan,
                    style:
                        const TextStyle(color: _kSidebarSubtext, fontSize: 11),
                    textAlign: TextAlign.center,
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                  ),
              ],
            ),
          ),
          // ── Ítems de navegación ───────────────────────────────────────────────
          Expanded(
            child: ListView.builder(
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 8),
              itemCount: items.length,
              itemBuilder: (context, index) {
                final item = items[index];
                final selected = selectedIndex == index;
                return Padding(
                  padding: const EdgeInsets.symmetric(vertical: 2),
                  child: Material(
                    color: selected ? selectedBg : Colors.transparent,
                    borderRadius: BorderRadius.circular(8),
                    child: ListTile(
                      dense: true,
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(8),
                      ),
                      leading: Icon(
                        item.icon,
                        color: selected
                            ? selectedFg
                            : _kSidebarInactiveIcon,
                        size: 20,
                      ),
                      title: Text(
                        item.title,
                        style: TextStyle(
                          color: selected
                              ? selectedFg
                              : _kSidebarInactiveText,
                          fontWeight:
                              selected ? FontWeight.w700 : FontWeight.normal,
                          fontSize: 14,
                        ),
                      ),
                      onTap: () => onTap(index),
                    ),
                  ),
                );
              },
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
                          style: const TextStyle(
                            color: _kSidebarSubtext,
                            fontSize: 11,
                          ),
                          overflow: TextOverflow.ellipsis,
                        ),
                      ],
                    ),
                  ),
                  IconButton(
                    icon: const Icon(
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
      height: 56,
      padding: const EdgeInsets.symmetric(horizontal: 16),
      decoration: const BoxDecoration(
        color: _kSidebarBg,
        border: Border(
          bottom: BorderSide(color: _kSidebarBorder),
        ),
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
            backgroundColor: const Color(0xFF2A2A2A),
            foregroundColor: Colors.white70,
          ),
          const SizedBox(width: 10),
          Text(
            branding.nombre,
            style: const TextStyle(
              color: Colors.white,
              fontWeight: FontWeight.bold,
              fontSize: 15,
            ),
          ),
          const Spacer(),
          // Estado de sync real (nube = Firebase + sesión Auth).
          Builder(
            builder: (context) {
              final nubeOn = BackendConfigService.instance.firebaseEnabled;
              final conAuth =
                  FirebaseAuthUsuarioService.instance.uidActual != null;
              final label = !nubeOn
                  ? 'Solo local'
                  : (conAuth
                      ? FirestoreSyncService.instance.syncStatusLabel
                      : 'Sin sesión nube');
              final ok = nubeOn && conAuth;
              return Container(
                padding:
                    const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                decoration: BoxDecoration(
                  color: const Color(0xFF1A1A1A),
                  borderRadius: BorderRadius.circular(999),
                  border: Border.all(color: _kSidebarHeaderBorder),
                ),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(
                      ok
                          ? Icons.cloud_done_outlined
                          : Icons.cloud_off_outlined,
                      size: 14,
                      color: ok
                          ? const Color(0xFF4ADE80)
                          : _kSidebarSubtext,
                    ),
                    const SizedBox(width: 6),
                    Text(
                      label,
                      style: const TextStyle(
                        color: _kSidebarInactiveText,
                        fontSize: 11,
                      ),
                    ),
                  ],
                ),
              );
            },
          ),
          IconButton(
            tooltip: 'Configuración',
            onPressed: onSettings,
            icon: const Icon(Icons.settings_rounded, color: _kSidebarInactiveIcon),
          ),
          const SizedBox(width: 4),
          GestureDetector(
            onTap: onSearch,
            child: Container(
              height: 34,
              width: 220,
              decoration: BoxDecoration(
                color: const Color(0xFF1A1A1A),
                borderRadius: BorderRadius.circular(8),
                border: Border.all(color: _kSidebarHeaderBorder),
              ),
              child: const Row(
                children: [
                  SizedBox(width: 10),
                  Icon(Icons.search_rounded,
                      color: _kSidebarInactiveIcon, size: 17),
                  SizedBox(width: 8),
                  Text(
                    'Buscar productos...',
                    style: TextStyle(color: _kSidebarSubtext, fontSize: 13),
                  ),
                ],
              ),
            ),
          ),
          const SizedBox(width: 12),
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
          const SizedBox(width: 4),
          InkWell(
            onTap: () {
              Navigator.of(context).push(
                MaterialPageRoute(builder: (_) => const PerfilUsuarioPage()),
              );
            },
            borderRadius: BorderRadius.circular(20),
            child: CircleAvatar(
              radius: 16,
              backgroundColor: const Color(0xFF2A2A2A),
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
          const SizedBox(width: 4),
          IconButton(
            tooltip: 'Cerrar sesión',
            onPressed: onLogout,
            icon: const Icon(Icons.logout_rounded, color: _kSidebarInactiveIcon),
          ),
        ],
      ),
    );
  }
}

