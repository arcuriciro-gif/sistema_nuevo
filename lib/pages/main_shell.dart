import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/scheduler.dart';
import 'package:flutter/services.dart';

import '../core/navigation/app_navigation.dart';
import '../core/sync/sync_queue_service.dart';
import '../core/utils/media_path.dart';
import '../services/auth_service.dart';
import '../services/auto_backup_service.dart';
import '../services/branding_service.dart';
import '../services/comunicaciones_service.dart';
import '../services/cuenta_corriente_service.dart';
import '../services/menu_preferencias_service.dart';
import '../services/permisos_service.dart';
import '../theme/layout_constants.dart';
import '../widgets/sync_status_chip.dart';
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

// ── Paleta fija para la barra lateral oscura ──────────────────────────────────
const Color _kSidebarBg = Color(0xFF111827);
const Color _kSidebarBorder = Color(0xFF1F2937);
const Color _kSidebarHeaderBorder = Color(0xFF374151);
const Color _kSidebarSelectedBg = Color(0xFFFF7A00);
const Color _kSidebarSelectedIcon = Colors.white;
const Color _kSidebarSelectedText = Colors.white;
const Color _kSidebarInactiveIcon = Color(0xFF9CA3AF);
const Color _kSidebarInactiveText = Color(0xFFD1D5DB);
const Color _kSidebarUserBg = Color(0xFF1F2937);
const Color _kSidebarSubtext = Color(0xFF6B7280);

class _ShellItem {
  final String id;
  final IconData icon;
  final String title;
  final String modulo;
  final Widget Function() builder;
  final bool quickAccess;

  const _ShellItem({
    required this.id,
    required this.icon,
    required this.title,
    required this.modulo,
    required this.builder,
    this.quickAccess = false,
  });
}

class MainShell extends StatefulWidget {
  const MainShell({super.key});

  @override
  State<MainShell> createState() => _MainShellState();
}

class _MainShellState extends State<MainShell> {
  int _selectedIndex = 0;
  bool _recordatorioMostrado = false;
  final Map<String, Widget> _pageCache = {};

  void _onBrandingChanged() {
    if (!mounted) return;
    SchedulerBinding.instance.addPostFrameCallback((_) {
      if (mounted) setState(() {});
    });
  }

  @override
  void initState() {
    super.initState();
    // Start automatic backup timer if configured
    AutoBackupService.instance.iniciar();
    BrandingService.instance.addListener(_onBrandingChanged);
    ComunicacionesService.instance.addListener(_onCommsChanged);
    SyncQueueService.instance.addListener(_onSyncChanged);
    MenuPreferenciasService.instance.addListener(_onMenuPrefsChanged);
    ComunicacionesService.instance.iniciar();
    MenuPreferenciasService.instance.cargar();
    AppNavigation.irAModuloInicio = _irAInicio;
    WidgetsBinding.instance.addPostFrameCallback((_) => _mostrarRecordatorioCc());
  }

  void _irAInicio() {
    if (!mounted) return;
    final items = _visibleItems;
    final idx = items.indexWhere((i) => i.id == 'inicio');
    if (idx >= 0) {
      _select(idx);
    } else if (items.isNotEmpty) {
      _select(0);
    }
  }

  void _onMenuPrefsChanged() {
    if (!mounted) return;
    SchedulerBinding.instance.addPostFrameCallback((_) {
      if (mounted) setState(() {});
    });
  }

  void _onCommsChanged() {
    if (!mounted) return;
    SchedulerBinding.instance.addPostFrameCallback((_) {
      if (mounted) setState(() {});
    });
  }

  void _onSyncChanged() {
    if (!mounted) return;
    SchedulerBinding.instance.addPostFrameCallback((_) {
      if (mounted) setState(() {});
    });
  }

  @override
  void dispose() {
    if (AppNavigation.irAModuloInicio == _irAInicio) {
      AppNavigation.irAModuloInicio = null;
    }
    BrandingService.instance.removeListener(_onBrandingChanged);
    ComunicacionesService.instance.removeListener(_onCommsChanged);
    SyncQueueService.instance.removeListener(_onSyncChanged);
    MenuPreferenciasService.instance.removeListener(_onMenuPrefsChanged);
    super.dispose();
  }

  String _pageKey(_ShellItem item) => '${item.modulo}::${item.title}';

  Widget _pageFor(_ShellItem item) {
    // Cachear páginas: recrearlas en cada setState (sync/branding) rompía
    // IndexedStack con el assert _dependents.isEmpty.
    return _pageCache.putIfAbsent(_pageKey(item), item.builder);
  }

  List<Widget> _pagesFor(List<_ShellItem> items) {
    final keys = items.map(_pageKey).toSet();
    _pageCache.removeWhere((key, _) => !keys.contains(key));
    return [for (final item in items) _pageFor(item)];
  }

  List<_ShellItem> get _items => [
        _ShellItem(
          id: 'inicio',
          icon: Icons.home_rounded,
          title: 'Inicio',
          modulo: 'dashboard',
          builder: () => const InicioPage(),
          quickAccess: true,
        ),
        _ShellItem(
          id: 'dashboard',
          icon: Icons.query_stats_rounded,
          title: 'Dashboard',
          modulo: 'dashboard',
          builder: () => const DashboardPage(),
          quickAccess: true,
        ),
        _ShellItem(
          id: 'comunicaciones',
          icon: Icons.forum_rounded,
          title: 'Comunicaciones',
          modulo: 'comunicaciones',
          builder: () => const ComunicacionesPage(),
          quickAccess: true,
        ),
        _ShellItem(
          id: 'productos',
          icon: Icons.inventory_2_rounded,
          title: 'Productos',
          modulo: 'productos',
          builder: () => const ProductosPage(),
          quickAccess: true,
        ),
        _ShellItem(
          id: 'papelera',
          icon: Icons.delete_outline_rounded,
          title: 'Papelera',
          modulo: 'productos',
          builder: () => const PapeleraProductosPage(),
        ),
        _ShellItem(
          id: 'categorias',
          icon: Icons.category_rounded,
          title: 'Categorías',
          modulo: 'productos',
          builder: () => const CategoriasPage(),
        ),
        _ShellItem(
          id: 'venta_rapida',
          icon: Icons.point_of_sale_rounded,
          title: 'Venta Rápida',
          modulo: 'remitos',
          builder: () => const VentaRapidaPage(),
          quickAccess: true,
        ),
        _ShellItem(
          id: 'ventas_facturas',
          icon: Icons.receipt_long_rounded,
          title: 'Ventas / Facturas',
          modulo: 'remitos',
          builder: () => const VentasPage(),
          quickAccess: true,
        ),
        _ShellItem(
          id: 'presupuestos',
          icon: Icons.request_quote_rounded,
          title: 'Presupuestos',
          modulo: 'remitos',
          builder: () => const VentasPage(
            titulo: 'Presupuestos',
            tipos: {'presupuesto': 'Presupuesto'},
          ),
          quickAccess: true,
        ),
        _ShellItem(
          id: 'notas_entrega',
          icon: Icons.local_shipping_outlined,
          title: 'Notas de entrega',
          modulo: 'remitos',
          builder: () => const VentasPage(
            titulo: 'Notas de entrega',
            tipos: {'nota_entrega': 'Nota de entrega'},
          ),
        ),
        _ShellItem(
          id: 'comprobantes_internos',
          icon: Icons.article_outlined,
          title: 'Comprobantes internos',
          modulo: 'remitos',
          builder: () => const VentasPage(
            titulo: 'Comprobantes internos',
            tipos: {'comprobante_interno': 'Comprobante interno'},
          ),
        ),
        _ShellItem(
          id: 'comparador',
          icon: Icons.compare_arrows_rounded,
          title: 'Comparador de listas',
          modulo: 'listas_precios',
          builder: () => const ComparacionPage(),
        ),
        _ShellItem(
          id: 'importaciones',
          icon: Icons.hub_rounded,
          title: 'Importaciones',
          modulo: 'productos',
          builder: () => const CentroImportacionesPage(),
        ),
        _ShellItem(
          id: 'importar_productos',
          icon: Icons.upload_file_rounded,
          title: 'Importar Productos',
          modulo: 'productos',
          builder: () => const ImportacionPage(),
        ),
        _ShellItem(
          id: 'stock',
          icon: Icons.warehouse_rounded,
          title: 'Stock',
          modulo: 'stock',
          builder: () => const StockPage(),
        ),
        _ShellItem(
          id: 'compras',
          icon: Icons.shopping_cart_rounded,
          title: 'Compras',
          modulo: 'compras',
          builder: () => const ComprasPage(),
        ),
        _ShellItem(
          id: 'remitos',
          icon: Icons.description_rounded,
          title: 'Remitos',
          modulo: 'remitos',
          builder: () => const RemitosPage(),
          quickAccess: true,
        ),
        _ShellItem(
          id: 'clientes',
          icon: Icons.groups_rounded,
          title: 'Clientes',
          modulo: 'clientes',
          builder: () => const ClientesPage(),
          quickAccess: true,
        ),
        _ShellItem(
          id: 'archivo_pdf',
          icon: Icons.folder_shared_rounded,
          title: 'Archivo PDF',
          modulo: 'clientes',
          builder: () => const ArchivoPdfsPage(),
          quickAccess: true,
        ),
        _ShellItem(
          id: 'cuenta_corriente',
          icon: Icons.account_balance_wallet_rounded,
          title: 'Cuenta corriente',
          modulo: 'clientes',
          builder: () => const ClientesDeudoresPage(),
          quickAccess: true,
        ),
        _ShellItem(
          id: 'proveedores',
          icon: Icons.local_shipping_rounded,
          title: 'Proveedores',
          modulo: 'proveedores',
          builder: () => const ProveedoresPage(),
        ),
        _ShellItem(
          id: 'listas_precios',
          icon: Icons.sell_rounded,
          title: 'Listas de Precios',
          modulo: 'listas_precios',
          builder: () => const ListasPrecioPage(),
        ),
        _ShellItem(
          id: 'reportes',
          icon: Icons.bar_chart_rounded,
          title: 'Reportes',
          modulo: 'reportes',
          builder: () => const ReportesPage(),
        ),
        _ShellItem(
          id: 'inteligencia',
          icon: Icons.insights_rounded,
          title: 'Inteligencia Comercial',
          modulo: 'reportes',
          builder: () => const InteligenciaComercialPage(),
        ),
        _ShellItem(
          id: 'etiquetas',
          icon: Icons.label_rounded,
          title: 'Etiquetas',
          modulo: 'etiquetas',
          builder: () => const EtiquetasPage(),
        ),
        _ShellItem(
          id: 'auditoria',
          icon: Icons.history_edu_rounded,
          title: 'Auditoría',
          modulo: 'auditoria',
          builder: () => const AuditoriaPage(),
        ),
        _ShellItem(
          id: 'mi_perfil',
          icon: Icons.manage_accounts_rounded,
          title: 'Mi perfil',
          modulo: 'dashboard',
          builder: () => const PerfilUsuarioPage(),
          quickAccess: true,
        ),
        _ShellItem(
          id: 'usuarios',
          icon: Icons.people_alt_rounded,
          title: 'Usuarios',
          modulo: 'usuarios',
          builder: () => const UsuariosPage(),
        ),
        _ShellItem(
          id: 'permisos',
          icon: Icons.admin_panel_settings_rounded,
          title: 'Permisos',
          modulo: 'usuarios',
          builder: () => const PermisosPage(),
        ),
        _ShellItem(
          id: 'respaldo',
          icon: Icons.cloud_upload_rounded,
          title: 'Respaldo',
          modulo: 'backup',
          builder: () => const BackupPage(),
        ),
        _ShellItem(
          id: 'manual',
          icon: Icons.menu_book_rounded,
          title: 'Manual de usuario',
          modulo: 'dashboard',
          builder: () => const ManualUsuarioPage(),
        ),
        _ShellItem(
          id: 'configuracion',
          icon: Icons.settings_rounded,
          title: 'Configuración',
          modulo: 'configuracion',
          builder: () => const ConfiguracionPage(),
        ),
      ];

  List<_ShellItem> get _visibleItems {
    final rol = AuthService.instance.currentUser?.rol ?? 'empleado';
    final menu = MenuPreferenciasService.instance;
    return _items
        .where((item) => PermisosService.instance.puedeVer(rol, item.modulo))
        .where((item) => menu.estaVisible(item.id))
        .toList();
  }

  int _safeIndex(List<_ShellItem> items) {
    if (items.isEmpty) return 0;
    if (_selectedIndex >= items.length) return 0;
    return _selectedIndex;
  }

  void _select(int index) {
    if (_selectedIndex != index) setState(() => _selectedIndex = index);
  }

  Future<void> _logout() async {
    await ComunicacionesService.instance.detener();
    await AuthService.instance.logout();
    if (!mounted) return;
    Navigator.of(context).pushAndRemoveUntil(
      MaterialPageRoute(builder: (_) => const LoginPage()),
      (_) => false,
    );
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
            _irAModulo('Dashboard'),
        const SingleActivator(LogicalKeyboardKey.digit3, control: true): () =>
            _irAModulo('Productos'),
        const SingleActivator(LogicalKeyboardKey.digit4, control: true): () =>
            _irAModulo('Venta Rápida'),
        const SingleActivator(LogicalKeyboardKey.digit5, control: true): () =>
            _irAModulo('Remitos'),
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
    return Scaffold(
      body: Column(
        children: [
          _TopBar(
            onSearch: () => _abrirBusqueda(desktop: true),
            onLogout: _logout,
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
                      ? const Center(child: Text('Sin módulos disponibles'))
                      : IndexedStack(
                          index: index,
                          children: _pagesFor(items),
                        ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildMobileLayout() {
    final items = _visibleItems;
    final index = _safeIndex(items);
    final current = items.isNotEmpty ? items[index] : null;
    final quickItems = items.where((item) => item.quickAccess).take(4).toList();
    final cs = Theme.of(context).colorScheme;

    return Scaffold(
      appBar: AppBar(
        title: Text(
          current?.title ?? 'EL TATA Manager',
          style: TextStyle(
            color: cs.onSurface,
            fontWeight: FontWeight.w700,
          ),
        ),
        centerTitle: true,
        actions: [
          if (current?.id != 'inicio')
            IconButton(
              tooltip: 'Inicio',
              icon: const Icon(Icons.home_rounded),
              onPressed: _irAInicio,
            ),
          const Padding(
            padding: EdgeInsets.only(right: 4),
            child: SyncStatusChip(dense: true),
          ),
          IconButton(
            onPressed: () {
              Navigator.push(
                context,
                MaterialPageRoute(builder: (_) => const NotificacionesPage()),
              );
            },
            icon: Badge(
              isLabelVisible: ComunicacionesService.instance.notifSinLeer > 0,
              label: Text('${ComunicacionesService.instance.notifSinLeer}'),
              child: const Icon(Icons.notifications_rounded),
            ),
            tooltip: 'Notificaciones',
          ),
          IconButton(
            onPressed: () => _abrirBusqueda(desktop: false),
            icon: const Icon(Icons.search_rounded),
            tooltip: 'Búsqueda global',
          ),
          Padding(
            padding: const EdgeInsets.only(right: 8),
            child: InkWell(
              onTap: () {
                Navigator.of(context).push(
                  MaterialPageRoute(builder: (_) => const PerfilUsuarioPage()),
                );
              },
              borderRadius: BorderRadius.circular(20),
              child: CircleAvatar(
                radius: 16,
                backgroundColor: cs.primaryContainer,
                backgroundImage: imageProviderDesdePath(
                  AuthService.instance.currentUser?.foto,
                ),
                child: (AuthService.instance.currentUser?.foto ?? '').isEmpty
                    ? Text(
                        (AuthService.instance.currentUser?.nombre ?? 'A')
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
              children: _pagesFor(items),
            ),
      bottomNavigationBar: quickItems.isEmpty
          ? null
          : BottomNavigationBar(
              backgroundColor: cs.surfaceContainerLow,
              selectedItemColor: cs.primary,
              unselectedItemColor: cs.onSurfaceVariant,
              type: BottomNavigationBarType.fixed,
              currentIndex: quickItems.contains(current) ? quickItems.indexOf(current!) : 0,
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

    return Column(
      children: [
        // ── Encabezado (logo + nombre del negocio) ────────────────────────────
        Container(
          width: double.infinity,
          padding: const EdgeInsets.fromLTRB(12, 12, 12, 10),
          decoration: const BoxDecoration(
            border: Border(bottom: BorderSide(color: _kSidebarHeaderBorder)),
          ),
          child: Column(
            children: [
              if (logoPath.isNotEmpty)
                CircleAvatar(
                  radius: 22,
                  backgroundImage: FileImage(File(logoPath)),
                )
              else
                Container(
                  width: 44,
                  height: 44,
                  decoration: BoxDecoration(
                    borderRadius: BorderRadius.circular(10),
                    border: Border.all(
                      color: const Color(0xFF3B82F6),
                      width: 1.5,
                    ),
                    color: const Color(0xFF1E3A5F),
                  ),
                  child: const Icon(
                    Icons.store_rounded,
                    color: Color(0xFF93C5FD),
                    size: 22,
                  ),
                ),
              const SizedBox(height: 6),
              Text(
                branding.nombre,
                style: const TextStyle(
                  color: Colors.white,
                  fontWeight: FontWeight.bold,
                  fontSize: 13,
                ),
                textAlign: TextAlign.center,
                overflow: TextOverflow.ellipsis,
              ),
              if (branding.slogan.isNotEmpty)
                Text(
                  branding.slogan,
                  style: const TextStyle(color: _kSidebarSubtext, fontSize: 10),
                  textAlign: TextAlign.center,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
            ],
          ),
        ),
        // ── Ítems de navegación ───────────────────────────────────────────────
        Expanded(
              child: ListView.builder(
            padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 4),
            itemCount: items.length,
            itemBuilder: (context, index) {
              final item = items[index];
              final selected = selectedIndex == index;
              return Padding(
                padding: const EdgeInsets.symmetric(vertical: 1),
                child: Material(
                  color: selected ? _kSidebarSelectedBg : Colors.transparent,
                  borderRadius: BorderRadius.circular(8),
                  child: ListTile(
                    dense: true,
                    visualDensity: const VisualDensity(horizontal: 0, vertical: -2),
                    minLeadingWidth: 24,
                    contentPadding: const EdgeInsets.symmetric(horizontal: 10),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(8),
                    ),
                  leading: Icon(
                    item.icon,
                    color: selected ? _kSidebarSelectedIcon : _kSidebarInactiveIcon,
                    size: 18,
                  ),
                  title: Text(
                    item.title,
                    style: TextStyle(
                      color: selected ? _kSidebarSelectedText : _kSidebarInactiveText,
                      fontWeight: selected ? FontWeight.w700 : FontWeight.normal,
                      fontSize: 13,
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
          margin: const EdgeInsets.all(10),
          padding: const EdgeInsets.all(10),
          decoration: BoxDecoration(
            color: _kSidebarUserBg,
            borderRadius: BorderRadius.circular(10),
          ),
          child: InkWell(
            onTap: () {
              Navigator.of(context).push(
                MaterialPageRoute(builder: (_) => const PerfilUsuarioPage()),
              );
            },
            borderRadius: BorderRadius.circular(10),
            child: Row(
              children: [
                CircleAvatar(
                  radius: 16,
                  backgroundColor: const Color(0xFF1E3A5F),
                  backgroundImage: imageProviderDesdePath(
                    AuthService.instance.currentUser?.foto,
                  ),
                  child: (AuthService.instance.currentUser?.foto ?? '').isEmpty
                      ? Text(
                          (AuthService.instance.currentUser?.nombre ?? 'A')
                              .substring(0, 1)
                              .toUpperCase(),
                          style: const TextStyle(
                            color: Color(0xFF93C5FD),
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
                        AuthService.instance.currentUser?.nombre ?? 'Usuario',
                        style: const TextStyle(
                          color: Colors.white,
                          fontSize: 12,
                          fontWeight: FontWeight.w600,
                        ),
                        overflow: TextOverflow.ellipsis,
                      ),
                      const Text(
                        'Editar perfil',
                        style: TextStyle(color: _kSidebarSubtext, fontSize: 11),
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
    );
  }
}

// ── Barra superior de escritorio ─────────────────────────────────────────────
class _TopBar extends StatelessWidget {
  final VoidCallback onSearch;
  final VoidCallback onLogout;

  const _TopBar({required this.onSearch, required this.onLogout});

  @override
  Widget build(BuildContext context) {
    final branding = BrandingService.instance;
    final logoPath = branding.imagenUiPath;
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
          // Logo / nombre del negocio
          if (logoPath.isNotEmpty)
            CircleAvatar(
              radius: 16,
              backgroundImage: FileImage(File(logoPath)),
            )
          else
            const Icon(Icons.store_rounded, color: Color(0xFF93C5FD), size: 22),
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
          // Buscador global
          GestureDetector(
            onTap: onSearch,
            child: Container(
              height: 34,
              width: 220,
              decoration: BoxDecoration(
                color: const Color(0xFF1F2937),
                borderRadius: BorderRadius.circular(8),
                border: Border.all(color: _kSidebarHeaderBorder),
              ),
              child: const Row(
                children: [
                  SizedBox(width: 10),
                  Icon(Icons.search_rounded, color: _kSidebarInactiveIcon, size: 17),
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
          const SyncStatusChip(dense: true, dark: true),
          const SizedBox(width: 8),
          // Notificaciones
          IconButton(
            icon: Badge(
              isLabelVisible: ComunicacionesService.instance.notifSinLeer > 0,
              label: Text('${ComunicacionesService.instance.notifSinLeer}'),
              child: const Icon(Icons.notifications_rounded),
            ),
            color: _kSidebarInactiveIcon,
            tooltip: 'Notificaciones',
            onPressed: () {
              Navigator.of(context).push(
                MaterialPageRoute(builder: (_) => const NotificacionesPage()),
              );
            },
          ),
          const SizedBox(width: 4),
          // Usuario
          InkWell(
            onTap: () {
              Navigator.of(context).push(
                MaterialPageRoute(builder: (_) => const PerfilUsuarioPage()),
              );
            },
            borderRadius: BorderRadius.circular(20),
            child: Row(
              children: [
                CircleAvatar(
                  radius: 15,
                  backgroundColor: const Color(0xFF1E3A5F),
                  backgroundImage: imageProviderDesdePath(
                    AuthService.instance.currentUser?.foto,
                  ),
                  child: (AuthService.instance.currentUser?.foto ?? '').isEmpty
                      ? Text(
                          userInitial,
                          style: const TextStyle(
                            color: Color(0xFF93C5FD),
                            fontWeight: FontWeight.bold,
                            fontSize: 12,
                          ),
                        )
                      : null,
                ),
                const SizedBox(width: 8),
                Text(
                  userName,
                  style: const TextStyle(
                    color: _kSidebarInactiveText,
                    fontSize: 13,
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(width: 8),
          // Cerrar sesión
          IconButton(
            icon: const Icon(Icons.logout_rounded),
            color: _kSidebarInactiveIcon,
            tooltip: 'Cerrar sesión',
            onPressed: onLogout,
          ),
        ],
      ),
    );
  }
}
