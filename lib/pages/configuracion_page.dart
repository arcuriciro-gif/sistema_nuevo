import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../core/config/backend_config_service.dart';
import '../core/firebase/firebase_auth_usuario_service.dart';
import '../core/firebase/firebase_safe_mode.dart';
import '../core/sync/firestore_sync_service.dart';
import '../core/utils/media_path.dart';
import '../navigation/shell_menu_catalog.dart';
import '../services/app_log.dart';
import '../services/auth_service.dart';
import '../services/branding_service.dart';
import '../services/permisos_service.dart';
import '../services/producto_service.dart';
import '../services/sidebar_preferencias_service.dart';
import '../theme/app_theme.dart';
import '../theme/theme_provider.dart';
import 'listas_precio_page.dart';
import 'plantilla_impresion_page.dart';
import 'documentos_config_page.dart';
import '../theme/module_app_bar.dart';

class ConfiguracionPage extends StatefulWidget {
  const ConfiguracionPage({super.key});

  @override
  State<ConfiguracionPage> createState() => _ConfiguracionPageState();
}

class _ConfiguracionPageState extends State<ConfiguracionPage> {
  bool _mostrarImagenes = true;
  bool _nubeActiva = false;
  bool _conectandoNube = false;
  bool _modoSeguro = false;

  // Branding
  final _nombreCtrl = TextEditingController();
  final _sloganCtrl = TextEditingController();
  final _telefonoCtrl = TextEditingController();
  final _direccionCtrl = TextEditingController();
  final _emailCtrl = TextEditingController();
  final _sitioWebCtrl = TextEditingController();
  final _whatsappCtrl = TextEditingController();
  final _instagramCtrl = TextEditingController();
  final _facebookCtrl = TextEditingController();
  final _monedaCtrl = TextEditingController();
  final _formatoFechaCtrl = TextEditingController();
  final _cuitCtrl = TextEditingController();
  final _ingresosBrutosCtrl = TextEditingController();
  final _condicionIvaCtrl = TextEditingController();
  final _direccionFiscalCtrl = TextEditingController();
  String _logoPath = '';
  String _iconoPath = '';
  bool _guardandoBranding = false;

  void _onThemeChanged() {
    if (mounted) {
      setState(() {});
    }
  }

  @override
  void initState() {
    super.initState();
    themeProvider.addListener(_onThemeChanged);
    BrandingService.instance.addListener(_onThemeChanged);
    _cargarPreferencias();
    _cargarBranding();
    _cargarEstadoNube();
  }

  void _cargarEstadoNube() {
    setState(() {
      _nubeActiva = BackendConfigService.instance.firebaseEnabled &&
          FirebaseAuthUsuarioService.instance.uidActual != null;
      _modoSeguro = FirebaseSafeMode.enabled;
    });
  }

  Future<void> _activarNube() async {
    setState(() => _conectandoNube = true);
    await appendAppLog('UI activar nube');
    final r = await AuthService.instance.activarNube();
    var extra = '';
    if (r.ok) {
      try {
        final n = await ProductoService().sincronizarFotosLocalesPendientes();
        if (n > 0) {
          extra = ' Se subieron fotos de $n productos.';
        }
      } catch (_) {}
      try {
        await FirestoreSyncService.instance.subirBranding();
      } catch (_) {}
      try {
        final u = AuthService.instance.currentUser;
        if (u != null) {
          await FirestoreSyncService.instance.subirUsuario(u);
        }
      } catch (_) {}
      try {
        await FirestoreSyncService.instance.subirPermisos();
      } catch (_) {}
    }
    if (!mounted) return;
    setState(() {
      _conectandoNube = false;
      _nubeActiva = r.ok;
      _modoSeguro = FirebaseSafeMode.enabled;
    });
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text('${r.mensaje}$extra')),
    );
  }

  Future<void> _desactivarNube() async {
    await AuthService.instance.desactivarNube();
    if (!mounted) return;
    setState(() {
      _nubeActiva = false;
    });
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text('Sincronización desactivada (modo local).')),
    );
  }

  Future<void> _salirModoSeguro() async {
    await FirebaseSafeMode.desactivar();
    if (!mounted) return;
    setState(() => _modoSeguro = false);
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(
        content: Text('Modo seguro desactivado. Ahora podés activar la nube.'),
      ),
    );
  }

  @override
  void dispose() {
    themeProvider.removeListener(_onThemeChanged);
    BrandingService.instance.removeListener(_onThemeChanged);
    _nombreCtrl.dispose();
    _sloganCtrl.dispose();
    _telefonoCtrl.dispose();
    _direccionCtrl.dispose();
    _emailCtrl.dispose();
    _sitioWebCtrl.dispose();
    _whatsappCtrl.dispose();
    _instagramCtrl.dispose();
    _facebookCtrl.dispose();
    _monedaCtrl.dispose();
    _formatoFechaCtrl.dispose();
    _cuitCtrl.dispose();
    _ingresosBrutosCtrl.dispose();
    _condicionIvaCtrl.dispose();
    _direccionFiscalCtrl.dispose();
    super.dispose();
  }

  void _cargarBranding() {
    final b = BrandingService.instance;
    _nombreCtrl.text = b.nombre;
    _sloganCtrl.text = b.slogan;
    _telefonoCtrl.text = b.telefono;
    _direccionCtrl.text = b.direccion;
    _emailCtrl.text = b.email;
    _sitioWebCtrl.text = b.sitioWeb;
    _whatsappCtrl.text = b.whatsapp;
    _instagramCtrl.text = b.instagram;
    _facebookCtrl.text = b.facebook;
    _monedaCtrl.text = b.moneda;
    _formatoFechaCtrl.text = b.formatoFecha;
    _cuitCtrl.text = b.cuit;
    _ingresosBrutosCtrl.text = b.ingresosBrutos;
    _condicionIvaCtrl.text = b.condicionIva;
    _direccionFiscalCtrl.text = b.direccionFiscal;
    setState(() {
      _logoPath = b.logoPath;
      _iconoPath = b.iconoPath;
    });
  }

  bool get _puedeEditarNegocio {
    final u = AuthService.instance.currentUser;
    if (u == null) return false;
    if (AuthService.instance.esAdministrador()) return true;
    return PermisosService.instance.puedeEditar(u.rol, 'configuracion');
  }

  void _avisarSinPermisoNegocio() {
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(
        content: Text(
          'Solo el administrador (o quien tenga permiso de Configuración) '
          'puede cambiar logo y datos del negocio.',
        ),
      ),
    );
  }

  Future<void> _elegirLogo() async {
    if (!_puedeEditarNegocio) {
      _avisarSinPermisoNegocio();
      return;
    }
    final picker = ImagePicker();
    final img =
        await picker.pickImage(source: ImageSource.gallery, imageQuality: 85);
    if (img == null) return;
    final path =
        await BrandingService.instance.persistirImagen(img.path, 'logo');
    setState(() => _logoPath = path);
  }

  Future<void> _elegirIcono() async {
    if (!_puedeEditarNegocio) {
      _avisarSinPermisoNegocio();
      return;
    }
    final picker = ImagePicker();
    final img =
        await picker.pickImage(source: ImageSource.gallery, imageQuality: 90);
    if (img == null) return;
    final path =
        await BrandingService.instance.persistirImagen(img.path, 'icono_app');
    setState(() => _iconoPath = path);
  }

  Future<void> _guardarBranding() async {
    if (!_puedeEditarNegocio) {
      _avisarSinPermisoNegocio();
      return;
    }
    setState(() => _guardandoBranding = true);
    try {
      await BrandingService.instance.guardar(
        nombre: _nombreCtrl.text.trim(),
        slogan: _sloganCtrl.text.trim(),
        telefono: _telefonoCtrl.text.trim(),
        direccion: _direccionCtrl.text.trim(),
        logoPath: _logoPath,
        iconoPath: _iconoPath,
        email: _emailCtrl.text.trim(),
        sitioWeb: _sitioWebCtrl.text.trim(),
        whatsapp: _whatsappCtrl.text.trim(),
        instagram: _instagramCtrl.text.trim(),
        facebook: _facebookCtrl.text.trim(),
        moneda: _monedaCtrl.text.trim().isEmpty ? r'$' : _monedaCtrl.text.trim(),
        formatoFecha: _formatoFechaCtrl.text.trim().isEmpty
            ? 'dd/MM/yyyy'
            : _formatoFechaCtrl.text.trim(),
        cuit: _cuitCtrl.text.trim(),
        ingresosBrutos: _ingresosBrutosCtrl.text.trim(),
        condicionIva: _condicionIvaCtrl.text.trim(),
        direccionFiscal: _direccionFiscalCtrl.text.trim(),
      );
      String mensaje =
          'Datos del negocio guardados (login y menú actualizados)';
      if (BackendConfigService.instance.firebaseEnabled) {
        try {
          await FirestoreSyncService.instance.subirBranding();
          mensaje =
              'Negocio sincronizado en la nube. Logo y descripción llegan a todos los equipos.';
        } catch (e) {
          mensaje =
              'Guardado local. No se pudo sincronizar: ${AuthService.mensajeUsuario(e)}';
        }
      }
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(mensaje)),
      );
      setState(() {});
    } finally {
      if (mounted) setState(() => _guardandoBranding = false);
    }
  }

  Future<void> _cargarPreferencias() async {
    final prefs = await SharedPreferences.getInstance();
    if (!mounted) return;
    setState(() {
      _mostrarImagenes = prefs.getBool('mostrarImagenes') ?? true;
    });
  }

  Future<void> _setMostrarImagenes(bool value) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool('mostrarImagenes', value);
    if (!mounted) return;
    setState(() {
      _mostrarImagenes = value;
    });
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;

    return Scaffold(
      appBar: buildModuleAppBar(context, title: 'Configuración'),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(16),
        child: Column(
          children: [
            // ── Sincronización / nube ─────────────────
            Card(
              elevation: 3,
              child: Padding(
                padding: const EdgeInsets.all(20),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Icon(Icons.cloud_sync_rounded, color: colorScheme.primary),
                        const SizedBox(width: 10),
                        Text(
                          'SINCRONIZACIÓN EN LA NUBE',
                          style: theme.textTheme.titleMedium?.copyWith(
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 12),
                    Text(
                      _nubeActiva
                          ? 'Estado: CONECTADO. Lo que cargues acá se refleja en el celular (y al revés).'
                          : 'Estado: SOLO LOCAL. Para usarlo online con el celular, activá la sincronización.',
                      style: theme.textTheme.bodyMedium,
                    ),
                    if (_modoSeguro) ...[
                      const SizedBox(height: 8),
                      Container(
                        width: double.infinity,
                        padding: const EdgeInsets.all(12),
                        decoration: BoxDecoration(
                          color: const Color(0xFFFFF4E5),
                          borderRadius: BorderRadius.circular(8),
                          border: Border.all(color: const Color(0xFFF0B429)),
                        ),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              'Modo seguro activo (hubo un cierre al conectar Firebase). '
                              'Desactivalo para volver a sincronizar.',
                              style: theme.textTheme.bodySmall?.copyWith(
                                color: const Color(0xFF8A5A00),
                              ),
                            ),
                            Align(
                              alignment: Alignment.centerLeft,
                              child: TextButton(
                                onPressed: _salirModoSeguro,
                                child: const Text('Desactivar modo seguro'),
                              ),
                            ),
                          ],
                        ),
                      ),
                    ],
                    const SizedBox(height: 12),
                    if (_nubeActiva)
                      OutlinedButton.icon(
                        onPressed: _conectandoNube ? null : _desactivarNube,
                        icon: const Icon(Icons.cloud_off_outlined),
                        label: const Text('Desactivar nube'),
                      )
                    else
                      FilledButton.icon(
                        onPressed: _conectandoNube ? null : _activarNube,
                        icon: _conectandoNube
                            ? const SizedBox(
                                width: 18,
                                height: 18,
                                child: CircularProgressIndicator(strokeWidth: 2),
                              )
                            : const Icon(Icons.cloud_done_outlined),
                        label: Text(
                          _conectandoNube
                              ? 'Conectando...'
                              : 'Activar sincronización online',
                        ),
                      ),
                    const SizedBox(height: 8),
                    Text(
                      'Requisito: internet. Usá el mismo usuario/clave en el celular.',
                      style: theme.textTheme.bodySmall?.copyWith(
                        color: colorScheme.onSurfaceVariant,
                      ),
                    ),
                  ],
                ),
              ),
            ),
            const SizedBox(height: 16),
            // ── Branding ──────────────────────────────
            Card(
              elevation: 3,
              child: Padding(
                padding: const EdgeInsets.all(20),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Icon(Icons.storefront, color: colorScheme.primary),
                        const SizedBox(width: 10),
                        Expanded(
                          child: Text(
                            'MI NEGOCIO',
                            style: theme.textTheme.titleMedium?.copyWith(
                              fontWeight: FontWeight.bold,
                            ),
                          ),
                        ),
                        if (!_puedeEditarNegocio)
                          Chip(
                            avatar: const Icon(Icons.lock_outline, size: 16),
                            label: const Text('Solo lectura'),
                            visualDensity: VisualDensity.compact,
                          ),
                      ],
                    ),
                    if (!_puedeEditarNegocio) ...[
                      const SizedBox(height: 8),
                      Text(
                        'El logo y la descripción los define el administrador '
                        'y se sincronizan online. Pedí permiso de Configuración '
                        'si necesitás editarlos.',
                        style: theme.textTheme.bodySmall?.copyWith(
                          color: colorScheme.onSurfaceVariant,
                        ),
                      ),
                    ],
                    const SizedBox(height: 16),
                    Row(
                      mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                      children: [
                        Column(
                          children: [
                            GestureDetector(
                              onTap: _puedeEditarNegocio ? _elegirLogo : _avisarSinPermisoNegocio,
                              child: Stack(
                                children: [
                                  CircleAvatar(
                                    radius: 44,
                                    backgroundColor: colorScheme.primaryContainer,
                                    backgroundImage:
                                        imageProviderDesdePath(_logoPath),
                                    child: imageProviderDesdePath(_logoPath) ==
                                            null
                                        ? Icon(Icons.store,
                                            size: 36,
                                            color: colorScheme.primary)
                                        : null,
                                  ),
                                  if (_puedeEditarNegocio)
                                    Positioned(
                                      right: 0,
                                      bottom: 0,
                                      child: CircleAvatar(
                                        radius: 12,
                                        backgroundColor: colorScheme.primary,
                                        child: const Icon(Icons.edit,
                                            size: 14, color: Colors.white),
                                      ),
                                    ),
                                ],
                              ),
                            ),
                            const SizedBox(height: 6),
                            Text(
                              'Logo',
                              style: theme.textTheme.bodySmall
                                  ?.copyWith(color: Colors.grey),
                            ),
                          ],
                        ),
                        Column(
                          children: [
                            GestureDetector(
                              onTap: _puedeEditarNegocio ? _elegirIcono : _avisarSinPermisoNegocio,
                              child: Stack(
                                children: [
                                  CircleAvatar(
                                    radius: 44,
                                    backgroundColor:
                                        colorScheme.secondaryContainer,
                                    backgroundImage:
                                        imageProviderDesdePath(_iconoPath),
                                    child: imageProviderDesdePath(_iconoPath) ==
                                            null
                                        ? Icon(Icons.apps_rounded,
                                            size: 36,
                                            color: colorScheme.secondary)
                                        : null,
                                  ),
                                  if (_puedeEditarNegocio)
                                    Positioned(
                                      right: 0,
                                      bottom: 0,
                                      child: CircleAvatar(
                                        radius: 12,
                                        backgroundColor: colorScheme.secondary,
                                        child: const Icon(Icons.edit,
                                            size: 14, color: Colors.white),
                                      ),
                                    ),
                                ],
                              ),
                            ),
                            const SizedBox(height: 6),
                            Text(
                              'Icono de la app',
                              style: theme.textTheme.bodySmall
                                  ?.copyWith(color: Colors.grey),
                            ),
                          ],
                        ),
                      ],
                    ),
                    const SizedBox(height: 8),
                    Text(
                      'El icono y el logo se ven al instante en el login y el menú. '
                      'Al guardar con la nube activa, se sincronizan a todos los equipos.',
                      style: theme.textTheme.bodySmall
                          ?.copyWith(color: colorScheme.onSurfaceVariant),
                      textAlign: TextAlign.center,
                    ),
                    if (_puedeEditarNegocio && _iconoPath.isNotEmpty)
                      TextButton(
                        onPressed: () => setState(() => _iconoPath = ''),
                        child: const Text('Quitar icono personalizado'),
                      ),
                    const SizedBox(height: 16),
                    TextField(
                      controller: _nombreCtrl,
                      readOnly: !_puedeEditarNegocio,
                      decoration: const InputDecoration(
                        labelText: 'Nombre del negocio',
                        border: OutlineInputBorder(),
                        prefixIcon: Icon(Icons.business),
                      ),
                    ),
                    const SizedBox(height: 12),
                    TextField(
                      controller: _sloganCtrl,
                      readOnly: !_puedeEditarNegocio,
                      decoration: const InputDecoration(
                        labelText: 'Slogan / descripción',
                        border: OutlineInputBorder(),
                        prefixIcon: Icon(Icons.short_text),
                      ),
                    ),
                    const SizedBox(height: 12),
                    TextField(
                      controller: _telefonoCtrl,
                      readOnly: !_puedeEditarNegocio,
                      keyboardType: TextInputType.phone,
                      decoration: const InputDecoration(
                        labelText: 'Teléfono',
                        border: OutlineInputBorder(),
                        prefixIcon: Icon(Icons.phone),
                      ),
                    ),
                    const SizedBox(height: 12),
                    TextField(
                      controller: _direccionCtrl,
                      readOnly: !_puedeEditarNegocio,
                      decoration: const InputDecoration(
                        labelText: 'Dirección',
                        border: OutlineInputBorder(),
                        prefixIcon: Icon(Icons.location_on),
                      ),
                    ),
                    const SizedBox(height: 12),
                    TextField(
                      controller: _emailCtrl,
                      readOnly: !_puedeEditarNegocio,
                      keyboardType: TextInputType.emailAddress,
                      decoration: const InputDecoration(
                        labelText: 'Correo electrónico',
                        border: OutlineInputBorder(),
                        prefixIcon: Icon(Icons.email_outlined),
                      ),
                    ),
                    const SizedBox(height: 12),
                    TextField(
                      controller: _whatsappCtrl,
                      readOnly: !_puedeEditarNegocio,
                      keyboardType: TextInputType.phone,
                      decoration: const InputDecoration(
                        labelText: 'WhatsApp',
                        border: OutlineInputBorder(),
                        prefixIcon: Icon(Icons.chat),
                      ),
                    ),
                    const SizedBox(height: 12),
                    TextField(
                      controller: _sitioWebCtrl,
                      readOnly: !_puedeEditarNegocio,
                      keyboardType: TextInputType.url,
                      decoration: const InputDecoration(
                        labelText: 'Sitio web',
                        border: OutlineInputBorder(),
                        prefixIcon: Icon(Icons.language),
                      ),
                    ),
                    const SizedBox(height: 12),
                    TextField(
                      controller: _instagramCtrl,
                      readOnly: !_puedeEditarNegocio,
                      decoration: const InputDecoration(
                        labelText: 'Instagram (opcional)',
                        border: OutlineInputBorder(),
                        prefixIcon: Icon(Icons.camera_alt_outlined),
                      ),
                    ),
                    const SizedBox(height: 12),
                    TextField(
                      controller: _facebookCtrl,
                      readOnly: !_puedeEditarNegocio,
                      decoration: const InputDecoration(
                        labelText: 'Facebook (opcional)',
                        border: OutlineInputBorder(),
                        prefixIcon: Icon(Icons.public),
                      ),
                    ),
                    const SizedBox(height: 16),
                    const Divider(),
                    const SizedBox(height: 8),
                    Text(
                      'Preferencias generales',
                      style: theme.textTheme.titleSmall
                          ?.copyWith(fontWeight: FontWeight.w600),
                    ),
                    const SizedBox(height: 12),
                    Row(
                      children: [
                        Expanded(
                          child: TextField(
                            controller: _monedaCtrl,
                            decoration: const InputDecoration(
                              labelText: 'Moneda',
                              border: OutlineInputBorder(),
                              prefixIcon: Icon(Icons.attach_money),
                            ),
                          ),
                        ),
                        const SizedBox(width: 12),
                        Expanded(
                          flex: 2,
                          child: TextField(
                            controller: _formatoFechaCtrl,
                            decoration: const InputDecoration(
                              labelText: 'Formato de fecha',
                              border: OutlineInputBorder(),
                              prefixIcon: Icon(Icons.calendar_today),
                            ),
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 16),
                    Text(
                      'Datos fiscales',
                      style: theme.textTheme.titleSmall
                          ?.copyWith(fontWeight: FontWeight.w600),
                    ),
                    const SizedBox(height: 12),
                    TextField(
                      controller: _cuitCtrl,
                      readOnly: !_puedeEditarNegocio,
                      decoration: const InputDecoration(
                        labelText: 'CUIT del negocio',
                        border: OutlineInputBorder(),
                        prefixIcon: Icon(Icons.badge),
                      ),
                    ),
                    const SizedBox(height: 12),
                    TextField(
                      controller: _ingresosBrutosCtrl,
                      readOnly: !_puedeEditarNegocio,
                      decoration: const InputDecoration(
                        labelText: 'Ingresos Brutos',
                        border: OutlineInputBorder(),
                        prefixIcon: Icon(Icons.account_balance),
                      ),
                    ),
                    const SizedBox(height: 12),
                    TextField(
                      controller: _condicionIvaCtrl,
                      readOnly: !_puedeEditarNegocio,
                      decoration: const InputDecoration(
                        labelText: 'Condición frente al IVA',
                        border: OutlineInputBorder(),
                        prefixIcon: Icon(Icons.receipt_long),
                      ),
                    ),
                    const SizedBox(height: 12),
                    TextField(
                      controller: _direccionFiscalCtrl,
                      readOnly: !_puedeEditarNegocio,
                      decoration: const InputDecoration(
                        labelText: 'Dirección fiscal',
                        border: OutlineInputBorder(),
                        prefixIcon: Icon(Icons.home_work_outlined),
                      ),
                    ),
                    const SizedBox(height: 16),
                    Text(
                      'Plantillas de impresión / PDF',
                      style: theme.textTheme.titleSmall
                          ?.copyWith(fontWeight: FontWeight.w600),
                    ),
                    const SizedBox(height: 8),
                    const Text(
                      'Editá encabezado, pie, papel, márgenes, firma y sello '
                      'una sola vez. Queda guardado y se usa en todos los documentos.',
                    ),
                    const SizedBox(height: 12),
                    SizedBox(
                      width: double.infinity,
                      child: OutlinedButton.icon(
                        onPressed: () async {
                          await Navigator.push<void>(
                            context,
                            MaterialPageRoute(
                              builder: (_) => const PlantillaImpresionPage(),
                            ),
                          );
                          _cargarBranding();
                        },
                        icon: const Icon(Icons.print_rounded),
                        label: const Text('Editar plantilla de impresión'),
                      ),
                    ),
                    const SizedBox(height: 8),
                    SizedBox(
                      width: double.infinity,
                      child: OutlinedButton.icon(
                        onPressed: () async {
                          await Navigator.push<void>(
                            context,
                            MaterialPageRoute(
                              builder: (_) => const DocumentosConfigPage(),
                            ),
                          );
                        },
                        icon: const Icon(Icons.numbers_rounded),
                        label: const Text('Numeración y AFIP/ARCA'),
                      ),
                    ),
                    const SizedBox(height: 16),
                    SizedBox(
                      width: double.infinity,
                      child: ElevatedButton.icon(
                        onPressed: (!_puedeEditarNegocio || _guardandoBranding)
                            ? null
                            : _guardarBranding,
                        icon: _guardandoBranding
                            ? const SizedBox(
                                width: 18,
                                height: 18,
                                child:
                                    CircularProgressIndicator(strokeWidth: 2),
                              )
                            : const Icon(Icons.save),
                        label: Text(
                          _puedeEditarNegocio
                              ? 'GUARDAR DATOS DEL NEGOCIO'
                              : 'SIN PERMISO PARA EDITAR',
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ),
            const SizedBox(height: 16),
            // ── Barra lateral personalizable ───────────
            Card(
              elevation: 3,
              child: Padding(
                padding: const EdgeInsets.all(20),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Icon(Icons.view_sidebar_rounded,
                            color: colorScheme.primary),
                        const SizedBox(width: 10),
                        Expanded(
                          child: Text(
                            'BARRA LATERAL',
                            style: theme.textTheme.titleMedium?.copyWith(
                              fontWeight: FontWeight.bold,
                            ),
                          ),
                        ),
                        TextButton(
                          onPressed: () async {
                            await SidebarPreferenciasService.instance
                                .mostrarTodos();
                            if (!mounted) return;
                            setState(() {});
                          },
                          child: const Text('Mostrar todos'),
                        ),
                      ],
                    ),
                    const SizedBox(height: 8),
                    Text(
                      'Elegí qué módulos ver en el menú. Podés dejarla llena o vacía; '
                      'ningún ítem es obligatorio. Si queda vacía, usá el engranaje '
                      'de la barra superior para volver a Configuración.',
                      style: theme.textTheme.bodySmall?.copyWith(
                        color: colorScheme.onSurfaceVariant,
                      ),
                    ),
                    const SizedBox(height: 12),
                    ...kShellMenuCatalog.map((entry) {
                      final visible = SidebarPreferenciasService.instance
                          .estaVisible(entry.id);
                      return CheckboxListTile(
                        dense: true,
                        contentPadding: EdgeInsets.zero,
                        secondary: Icon(entry.icon, size: 22),
                        title: Text(entry.title),
                        value: visible,
                        onChanged: (v) async {
                          await SidebarPreferenciasService.instance
                              .setVisible(entry.id, v ?? true);
                          if (!mounted) return;
                          setState(() {});
                        },
                      );
                    }),
                  ],
                ),
              ),
            ),
            const SizedBox(height: 16),
            // ── Listas de precios ──────────────────────
            Card(
              elevation: 3,
              child: Padding(
                padding: const EdgeInsets.all(20),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Icon(Icons.sell_rounded, color: colorScheme.primary),
                        const SizedBox(width: 10),
                        Text(
                          'PORCENTAJES DE LISTAS',
                          style: theme.textTheme.titleMedium?.copyWith(
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 8),
                    const Text(
                      'Creá, editá o desactivá las listas de precios usadas para calcular automáticamente el precio de venta según el costo.',
                    ),
                    const SizedBox(height: 16),
                    SizedBox(
                      width: double.infinity,
                      child: ElevatedButton.icon(
                        onPressed: () {
                          Navigator.push(
                            context,
                            MaterialPageRoute(
                              builder: (_) => const ListasPrecioPage(),
                            ),
                          );
                        },
                        icon: const Icon(Icons.arrow_forward_rounded),
                        label: const Text('ADMINISTRAR LISTAS DE PRECIOS'),
                      ),
                    ),
                  ],
                ),
              ),
            ),
            const SizedBox(height: 16),
            // ── Tema ──────────────────────────────────
            Card(
              elevation: 3,
              child: Padding(
                padding: const EdgeInsets.all(20),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Icon(Icons.palette, color: colorScheme.primary),
                        const SizedBox(width: 10),
                        Expanded(
                          child: Text(
                            'PERSONALIZÁ TU EXPERIENCIA',
                            style: theme.textTheme.titleMedium?.copyWith(
                              fontWeight: FontWeight.bold,
                            ),
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 24),
                    Text(
                      'Colores del tema',
                      style: theme.textTheme.titleSmall?.copyWith(
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                    const SizedBox(height: 12),
                    Wrap(
                      spacing: 12,
                      runSpacing: 12,
                      children: AppTheme.coloresDisponibles.map((color) {
                        final selected = themeProvider.color == color;
                        return InkWell(
                          onTap: () => themeProvider.setColor(color),
                          borderRadius: BorderRadius.circular(24),
                          child: CircleAvatar(
                            radius: 22,
                            backgroundColor: color,
                            child: selected
                                ? const Icon(Icons.check, color: Colors.white)
                                : null,
                          ),
                        );
                      }).toList(),
                    ),
                    const SizedBox(height: 24),
                    Text(
                      'Fuente',
                      style: theme.textTheme.titleSmall?.copyWith(
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                    const SizedBox(height: 12),
                    DropdownButtonFormField<String>(
                      initialValue: themeProvider.fuente,
                      decoration: const InputDecoration(
                        border: OutlineInputBorder(),
                      ),
                      items: AppTheme.fuentesDisponibles
                          .map(
                            (fuente) => DropdownMenuItem(
                              value: fuente,
                              child: Text(fuente),
                            ),
                          )
                          .toList(),
                      onChanged: (value) {
                        if (value != null) {
                          themeProvider.setFuente(value);
                        }
                      },
                    ),
                    const SizedBox(height: 24),
                    Text(
                      'Modo',
                      style: theme.textTheme.titleSmall?.copyWith(
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                    const SizedBox(height: 12),
                    LayoutBuilder(
                      builder: (context, constraints) {
                        final isNarrow = constraints.maxWidth < 360;
                        return ToggleButtons(
                          isSelected: [
                            themeProvider.mode == ThemeMode.light,
                            themeProvider.mode == ThemeMode.dark,
                            themeProvider.mode == ThemeMode.system,
                          ],
                          onPressed: (index) {
                            final mode = [
                              ThemeMode.light,
                              ThemeMode.dark,
                              ThemeMode.system,
                            ][index];
                            themeProvider.setMode(mode);
                          },
                          direction:
                              isNarrow ? Axis.vertical : Axis.horizontal,
                          children: const [
                            Padding(
                              padding: EdgeInsets.symmetric(horizontal: 16),
                              child: Text('Claro'),
                            ),
                            Padding(
                              padding: EdgeInsets.symmetric(horizontal: 16),
                              child: Text('Oscuro'),
                            ),
                            Padding(
                              padding: EdgeInsets.symmetric(horizontal: 16),
                              child: Text('Sistema'),
                            ),
                          ],
                        );
                      },
                    ),
                    const SizedBox(height: 24),
                    const Divider(),
                    const SizedBox(height: 8),
                    Text(
                      'Configuración avanzada',
                      style: theme.textTheme.titleSmall?.copyWith(
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                    const SizedBox(height: 12),
                    SwitchListTile(
                      contentPadding: EdgeInsets.zero,
                      value: _mostrarImagenes,
                      onChanged: _setMostrarImagenes,
                      title: const Text('Mostrar imágenes'),
                      subtitle:
                          const Text('Guardado localmente en el dispositivo'),
                    ),
                    const ListTile(
                      contentPadding: EdgeInsets.zero,
                      leading: Icon(Icons.info_outline),
                      title: Text('3 listas de precios'),
                      subtitle: Text(
                        'Lista 1, Lista 2 y Lista 3 ya están disponibles para cada producto.',
                      ),
                    ),
                    const ListTile(
                      contentPadding: EdgeInsets.zero,
                      leading: Icon(Icons.place_outlined),
                      title: Text('Ubicaciones'),
                      subtitle: Text(
                        'Podés seguir usando ubicaciones para ordenar mejor el stock.',
                      ),
                    ),
                  ],
                ),
              ),
            ),
            const SizedBox(height: 16),
          ],
        ),
      ),
    );
  }
}
