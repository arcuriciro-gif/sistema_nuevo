import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../models/lista_precio.dart';
import '../plugins/whatsapp/whatsapp_business_config.dart';
import '../plugins/whatsapp/whatsapp_business_service.dart';
import '../plugins/whatsapp/whatsapp_catalog_service.dart';
import '../plugins/whatsapp/whatsapp_message_log.dart';
import '../services/lista_precio_service.dart';
import '../services/producto_service.dart';
import '../services/whatsapp_plantillas_service.dart';
import '../theme/app_tokens.dart';
import '../theme/module_app_bar.dart';
import '../widgets/erp/erp_section_header.dart';

/// Configuración del plugin WhatsApp Business (Cloud API + deeplink + catálogo).
class WhatsappBusinessPage extends StatefulWidget {
  const WhatsappBusinessPage({super.key});

  @override
  State<WhatsappBusinessPage> createState() => _WhatsappBusinessPageState();
}

class _WhatsappBusinessPageState extends State<WhatsappBusinessPage> {
  final _cfg = WhatsappBusinessConfig.instance;
  final _svc = WhatsappBusinessService.instance;
  final _cat = WhatsappCatalogService.instance;
  final _tpl = WhatsappPlantillasService.instance;
  final _productos = ProductoService();
  final _listasSvc = ListaPrecioService();

  final _tokenCtrl = TextEditingController();
  final _phoneIdCtrl = TextEditingController();
  final _wabaCtrl = TextEditingController();
  final _versionCtrl = TextEditingController();
  final _countryCtrl = TextEditingController();
  final _catalogIdCtrl = TextEditingController();
  final _currencyCtrl = TextEditingController(text: 'ARS');
  final _urlTplCtrl = TextEditingController();
  final _testPhoneCtrl = TextEditingController();
  final _testMsgCtrl = TextEditingController();
  final _tplNameCtrl = TextEditingController();
  final _tplLangCtrl = TextEditingController(text: 'es_AR');

  List<WhatsappMessageLog> _log = [];
  List<Map<String, dynamic>> _catLog = [];
  List<ListaPrecio> _listas = [];
  bool _cargando = true;
  bool _syncingCatalog = false;
  String? _status;
  String? _catalogStatus;

  @override
  void initState() {
    super.initState();
    _cargar();
  }

  @override
  void dispose() {
    _tokenCtrl.dispose();
    _phoneIdCtrl.dispose();
    _wabaCtrl.dispose();
    _versionCtrl.dispose();
    _countryCtrl.dispose();
    _catalogIdCtrl.dispose();
    _currencyCtrl.dispose();
    _urlTplCtrl.dispose();
    _testPhoneCtrl.dispose();
    _testMsgCtrl.dispose();
    _tplNameCtrl.dispose();
    _tplLangCtrl.dispose();
    super.dispose();
  }

  Future<void> _cargar() async {
    await _cfg.cargar();
    await _tpl.cargar();
    final log = await _svc.listarLog();
    final catLog = await _cat.listarEstadoLocal();
    List<ListaPrecio> listas = [];
    try {
      listas = await _listasSvc.obtenerActivas();
    } catch (_) {}
    if (!mounted) return;
    setState(() {
      _tokenCtrl.text = _cfg.accessToken;
      _phoneIdCtrl.text = _cfg.phoneNumberId;
      _wabaCtrl.text = _cfg.wabaId;
      _versionCtrl.text = _cfg.apiVersion;
      _countryCtrl.text = _cfg.defaultCountryCode;
      _catalogIdCtrl.text = _cfg.catalogId;
      _currencyCtrl.text = _cfg.catalogCurrency;
      _urlTplCtrl.text = _cfg.catalogProductUrlTemplate;
      _testMsgCtrl.text = _tpl.render(
        _tpl.general,
        nombre: 'Cliente',
        empresa: 'Tu comercio',
      );
      _log = log;
      _catLog = catLog;
      _listas = listas;
      _cargando = false;
    });
  }

  List<DropdownMenuItem<String>> get _priceListItems {
    final items = <DropdownMenuItem<String>>[
      const DropdownMenuItem(value: '1', child: Text('Lista 1')),
      const DropdownMenuItem(value: '2', child: Text('Lista 2')),
      const DropdownMenuItem(value: '3', child: Text('Lista 3')),
    ];
    for (final l in _listas) {
      if (l.id == null) continue;
      final key = '${l.id}';
      if (key == '1' || key == '2' || key == '3') continue;
      items.add(
        DropdownMenuItem(
          value: key,
          child: Text(l.nombre.trim().isEmpty ? 'Lista $key' : l.nombre),
        ),
      );
    }
    return items;
  }

  String get _priceListKeySafe {
    final key = _cfg.catalogPriceListKey;
    final values = _priceListItems.map((e) => e.value).whereType<String>();
    if (values.contains(key)) return key;
    return '1';
  }

  Future<void> _guardar() async {
    await _cfg.guardar(
      accessToken: _tokenCtrl.text,
      phoneNumberId: _phoneIdCtrl.text,
      wabaId: _wabaCtrl.text,
      apiVersion: _versionCtrl.text,
      defaultCountryCode: _countryCtrl.text,
      catalogId: _catalogIdCtrl.text,
      catalogCurrency: _currencyCtrl.text,
      catalogProductUrlTemplate: _urlTplCtrl.text,
      catalogPriceMode: _cfg.catalogPriceMode,
      catalogPriceListKey: _cfg.catalogPriceListKey,
    );
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text('Configuración WhatsApp guardada')),
    );
    setState(() {});
  }

  Future<void> _probarConexion() async {
    await _guardar();
    if (!mounted) return;
    final r = await _svc.probarConexion();
    if (!mounted) return;
    setState(() => _status = r);
  }

  Future<void> _probarCatalogo() async {
    await _guardar();
    if (!mounted) return;
    final r = await _cat.probarCatalogo();
    if (!mounted) return;
    setState(() => _catalogStatus = r);
  }

  Future<void> _activarVisibilidad() async {
    await _guardar();
    if (!mounted) return;
    final r = await _cat.activarVisibilidadCatalogo(visible: true);
    if (!mounted) return;
    setState(() => _catalogStatus = r);
  }

  Future<void> _syncFavoritos() async {
    await _guardar();
    if (!mounted) return;
    setState(() => _syncingCatalog = true);
    try {
      final favs = await _productos.obtenerFavoritos();
      final r = await _cat.sincronizarLista(favs);
      if (!mounted) return;
      setState(() {
        _catalogStatus =
            'Favoritos · ok ${r.ok} · error ${r.error} · omitidos ${r.skipped}'
            '${r.lastError == null ? '' : '\n${r.lastError}'}';
      });
      await _cargar();
    } finally {
      if (mounted) setState(() => _syncingCatalog = false);
    }
  }

  Future<void> _syncTodos() async {
    await _guardar();
    if (!mounted) return;
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Sincronizar catálogo'),
        content: const Text(
          'Se subirán hasta 500 productos con foto en la nube y precio > 0. '
          'Meta puede demorar en mostrarlos en WhatsApp.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('Cancelar'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('Sincronizar'),
          ),
        ],
      ),
    );
    if (ok != true || !mounted) return;
    setState(() => _syncingCatalog = true);
    try {
      final todos = await _productos.obtenerTodos();
      final r = await _cat.sincronizarLista(todos, maxItems: 500);
      if (!mounted) return;
      setState(() {
        _catalogStatus =
            'Catálogo · ok ${r.ok} · error ${r.error} · omitidos ${r.skipped}'
            '${r.lastError == null ? '' : '\n${r.lastError}'}';
      });
      await _cargar();
    } finally {
      if (mounted) setState(() => _syncingCatalog = false);
    }
  }

  Future<void> _enviarPrueba({bool deeplink = false}) async {
    await _guardar();
    if (!mounted) return;
    final raw = _testPhoneCtrl.text.trim();
    if (raw.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Ingresá un teléfono de prueba')),
      );
      return;
    }
    final digits = _svc.normalizarTelefono(raw);
    final msg = _testMsgCtrl.text.trim();
    final r = await _svc.enviarOAbrir(
      telefonoDigits: digits,
      mensaje: msg,
      forzarDeeplink: deeplink,
    );
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(
          r.ok
              ? (r.modo == WhatsappSendMode.api
                  ? 'Enviado por API · ${r.waMessageId ?? ''}'
                  : 'WhatsApp abierto (deeplink)')
              : (r.error ?? 'Error al enviar'),
        ),
        backgroundColor: r.ok ? null : Theme.of(context).colorScheme.error,
      ),
    );
    await _cargar();
  }

  Future<void> _enviarTemplate() async {
    await _guardar();
    if (!mounted) return;
    final raw = _testPhoneCtrl.text.trim();
    final name = _tplNameCtrl.text.trim();
    if (raw.isEmpty || name.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Teléfono y nombre de plantilla requeridos')),
      );
      return;
    }
    final digits = _svc.normalizarTelefono(raw);
    final r = await _svc.enviarTemplateApi(
      telefonoDigits: digits,
      templateName: name,
      languageCode: _tplLangCtrl.text.trim().isEmpty
          ? 'es_AR'
          : _tplLangCtrl.text.trim(),
    );
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(
          r.ok ? 'Template enviado · ${r.waMessageId ?? ''}' : (r.error ?? 'Error'),
        ),
        backgroundColor: r.ok ? null : Theme.of(context).colorScheme.error,
      ),
    );
    await _cargar();
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return Scaffold(
      appBar: buildModuleAppBar(
        context,
        title: 'WhatsApp Business',
        actions: [
          IconButton(
            tooltip: 'Guardar',
            icon: const Icon(Icons.save_rounded),
            onPressed: _guardar,
          ),
        ],
      ),
      body: _cargando
          ? const Center(child: CircularProgressIndicator())
          : ListView(
              padding: const EdgeInsets.fromLTRB(16, 12, 16, 32),
              children: [
                const ErpSectionHeader(
                  title: 'Conexión Cloud API',
                  subtitle:
                      'Plugin opcional · Meta WhatsApp Business. Si no hay API, se usa wa.me',
                ),
                const SizedBox(height: 12),
                SwitchListTile(
                  contentPadding: EdgeInsets.zero,
                  title: const Text('Activar WhatsApp Business'),
                  value: _cfg.enabled,
                  onChanged: (v) async {
                    await _cfg.guardar(enabled: v);
                    setState(() {});
                  },
                ),
                SwitchListTile(
                  contentPadding: EdgeInsets.zero,
                  title: const Text('Preferir API (si está configurada)'),
                  subtitle: const Text(
                    'Si falla (p. ej. fuera de ventana 24h), abre WhatsApp',
                  ),
                  value: _cfg.preferApi,
                  onChanged: _cfg.enabled
                      ? (v) async {
                          await _cfg.guardar(preferApi: v);
                          setState(() {});
                        }
                      : null,
                ),
                const SizedBox(height: 8),
                TextField(
                  controller: _tokenCtrl,
                  obscureText: true,
                  decoration: const InputDecoration(
                    labelText: 'Access token',
                    border: OutlineInputBorder(),
                    helperText: 'Token de sistema / permanente de Meta',
                  ),
                ),
                const SizedBox(height: 8),
                TextField(
                  controller: _phoneIdCtrl,
                  decoration: const InputDecoration(
                    labelText: 'Phone Number ID',
                    border: OutlineInputBorder(),
                  ),
                  keyboardType: TextInputType.number,
                ),
                const SizedBox(height: 8),
                TextField(
                  controller: _wabaCtrl,
                  decoration: const InputDecoration(
                    labelText: 'WABA ID (opcional)',
                    border: OutlineInputBorder(),
                  ),
                ),
                const SizedBox(height: 8),
                Row(
                  children: [
                    Expanded(
                      child: TextField(
                        controller: _versionCtrl,
                        decoration: const InputDecoration(
                          labelText: 'API version',
                          border: OutlineInputBorder(),
                        ),
                      ),
                    ),
                    const SizedBox(width: 8),
                    Expanded(
                      child: TextField(
                        controller: _countryCtrl,
                        decoration: const InputDecoration(
                          labelText: 'Cód. país default',
                          border: OutlineInputBorder(),
                          helperText: 'ej. 54',
                        ),
                        keyboardType: TextInputType.number,
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 12),
                Wrap(
                  spacing: 8,
                  runSpacing: 8,
                  children: [
                    FilledButton.icon(
                      onPressed: _guardar,
                      icon: const Icon(Icons.save_rounded),
                      label: const Text('Guardar'),
                    ),
                    OutlinedButton.icon(
                      onPressed: _probarConexion,
                      icon: const Icon(Icons.cloud_done_rounded),
                      label: const Text('Probar conexión'),
                    ),
                  ],
                ),
                if (_status != null) ...[
                  const SizedBox(height: 8),
                  Text(
                    _status!,
                    style: TextStyle(
                      color: _status!.startsWith('OK')
                          ? AppTokens.success
                          : cs.error,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ],
                const SizedBox(height: 24),
                const ErpSectionHeader(
                  title: 'Catálogo de productos',
                  subtitle:
                      'Sube nombre, foto y (opcional) precio a Meta Commerce. '
                      'Límite práctico: 500 ítems por WABA.',
                ),
                const SizedBox(height: 10),
                TextField(
                  controller: _catalogIdCtrl,
                  decoration: const InputDecoration(
                    labelText: 'Catalog ID (Commerce Manager)',
                    border: OutlineInputBorder(),
                    helperText: 'Vinculá el catálogo al WABA en WhatsApp Manager',
                  ),
                  keyboardType: TextInputType.number,
                ),
                const SizedBox(height: 8),
                Row(
                  children: [
                    Expanded(
                      child: TextField(
                        controller: _currencyCtrl,
                        decoration: const InputDecoration(
                          labelText: 'Moneda',
                          border: OutlineInputBorder(),
                          helperText: 'ISO · ej. ARS',
                        ),
                      ),
                    ),
                    const SizedBox(width: 8),
                    Expanded(
                      child: SwitchListTile(
                        contentPadding: EdgeInsets.zero,
                        title: const Text('Auto al guardar'),
                        subtitle: Text(
                          _cfg.catalogSyncPrice
                              ? 'Nombre, foto y precio → Meta'
                              : 'Nombre y foto → Meta (precio congelado)',
                        ),
                        value: _cfg.catalogAutoSync,
                        onChanged: _cfg.enabled
                            ? (v) async {
                                await _cfg.guardar(catalogAutoSync: v);
                                setState(() {});
                              }
                            : null,
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 12),
                Text(
                  'Precio en WhatsApp',
                  style: Theme.of(context).textTheme.titleSmall?.copyWith(
                        fontWeight: FontWeight.w700,
                      ),
                ),
                const SizedBox(height: 6),
                SegmentedButton<String>(
                  segments: const [
                    ButtonSegment(
                      value: WhatsappBusinessConfig.priceModeSync,
                      label: Text('Actualizar'),
                      icon: Icon(Icons.sync_rounded, size: 18),
                    ),
                    ButtonSegment(
                      value: WhatsappBusinessConfig.priceModeHide,
                      label: Text('No actualizar'),
                      icon: Icon(Icons.visibility_off_outlined, size: 18),
                    ),
                  ],
                  selected: {_cfg.catalogPriceMode},
                  onSelectionChanged: (s) async {
                    if (!_cfg.enabled) return;
                    await _cfg.guardar(catalogPriceMode: s.first);
                    setState(() {});
                  },
                ),
                const SizedBox(height: 6),
                Text(
                  _cfg.catalogSyncPrice
                      ? 'Si cambiás el precio en la app (y Auto está on), '
                          'también se actualiza en WhatsApp.'
                      : 'Meta exige un precio técnico la primera vez; después '
                          'no lo pisamos. En la ficha dice “consultá por chat”.',
                  style: TextStyle(
                    color: cs.onSurfaceVariant,
                    fontSize: 12.5,
                  ),
                ),
                const SizedBox(height: 10),
                DropdownButtonFormField<String>(
                  initialValue: _priceListKeySafe,
                  decoration: const InputDecoration(
                    labelText: 'Lista de precios a publicar',
                    border: OutlineInputBorder(),
                    helperText:
                        'Solo aplica si elegiste “Actualizar”. Lista 1/2/3 o personalizada.',
                  ),
                  items: _priceListItems,
                  onChanged: _cfg.enabled && _cfg.catalogSyncPrice
                      ? (v) async {
                          if (v == null) return;
                          await _cfg.guardar(catalogPriceListKey: v);
                          setState(() {});
                        }
                      : null,
                ),
                const SizedBox(height: 8),
                TextField(
                  controller: _urlTplCtrl,
                  decoration: const InputDecoration(
                    labelText: 'URL producto (opcional)',
                    hintText: 'https://tuweb.com/p/{codigo}',
                    border: OutlineInputBorder(),
                    helperText:
                        'Si vacío: usa sitio web del branding o el catálogo Meta',
                  ),
                ),
                const SizedBox(height: 12),
                Wrap(
                  spacing: 8,
                  runSpacing: 8,
                  children: [
                    OutlinedButton.icon(
                      onPressed: _syncingCatalog ? null : _probarCatalogo,
                      icon: const Icon(Icons.storefront_rounded),
                      label: const Text('Probar catálogo'),
                    ),
                    OutlinedButton.icon(
                      onPressed: _syncingCatalog ? null : _activarVisibilidad,
                      icon: const Icon(Icons.visibility_rounded),
                      label: const Text('Mostrar en chat'),
                    ),
                    FilledButton.tonalIcon(
                      onPressed: _syncingCatalog ? null : _syncFavoritos,
                      icon: _syncingCatalog
                          ? const SizedBox(
                              width: 16,
                              height: 16,
                              child: CircularProgressIndicator(strokeWidth: 2),
                            )
                          : const Icon(Icons.star_rounded),
                      label: const Text('Sync favoritos'),
                    ),
                    FilledButton.icon(
                      onPressed: _syncingCatalog ? null : _syncTodos,
                      icon: const Icon(Icons.cloud_upload_rounded),
                      label: const Text('Sync catálogo (máx 500)'),
                    ),
                  ],
                ),
                if (_catalogStatus != null) ...[
                  const SizedBox(height: 8),
                  Text(
                    _catalogStatus!,
                    style: TextStyle(
                      color: _catalogStatus!.startsWith('OK') ||
                              _catalogStatus!.contains('ok ')
                          ? AppTokens.success
                          : cs.error,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ],
                if (_catLog.isNotEmpty) ...[
                  const SizedBox(height: 12),
                  Text(
                    'Últimos syncs locales',
                    style: Theme.of(context).textTheme.titleSmall?.copyWith(
                          fontWeight: FontWeight.w700,
                        ),
                  ),
                  const SizedBox(height: 6),
                  ..._catLog.take(12).map((e) {
                    final estado = '${e['estado'] ?? ''}';
                    final ok = estado == 'ok';
                    return ListTile(
                      dense: true,
                      contentPadding: EdgeInsets.zero,
                      leading: Icon(
                        ok ? Icons.check_circle_rounded : Icons.error_outline,
                        color: ok ? AppTokens.success : AppTokens.danger,
                        size: 20,
                      ),
                      title: Text(
                        '${e['codigo']} · ${e['titulo'] ?? ''}',
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(fontWeight: FontWeight.w600),
                      ),
                      subtitle: Text(
                        '${e['currency'] ?? ''} '
                        '${(e['precio'] as num?)?.toStringAsFixed(2) ?? ''} · '
                        '$estado'
                        '${'${e['error'] ?? ''}'.isEmpty ? '' : ' · ${e['error']}'}',
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                      ),
                    );
                  }),
                ],
                const SizedBox(height: 24),
                const ErpSectionHeader(
                  title: 'Prueba de envío',
                  subtitle: 'Texto libre (API o deeplink) y template Meta',
                ),
                const SizedBox(height: 10),
                TextField(
                  controller: _testPhoneCtrl,
                  decoration: const InputDecoration(
                    labelText: 'Teléfono destino',
                    hintText: '54911…',
                    border: OutlineInputBorder(),
                  ),
                  keyboardType: TextInputType.phone,
                ),
                const SizedBox(height: 8),
                TextField(
                  controller: _testMsgCtrl,
                  maxLines: 3,
                  decoration: const InputDecoration(
                    labelText: 'Mensaje de prueba',
                    border: OutlineInputBorder(),
                  ),
                ),
                const SizedBox(height: 8),
                Wrap(
                  spacing: 8,
                  runSpacing: 8,
                  children: [
                    FilledButton.tonalIcon(
                      onPressed: () => _enviarPrueba(deeplink: false),
                      icon: const Icon(Icons.send_rounded),
                      label: const Text('Enviar (API→fallback)'),
                    ),
                    OutlinedButton.icon(
                      onPressed: () => _enviarPrueba(deeplink: true),
                      icon: const Icon(Icons.open_in_new_rounded),
                      label: const Text('Solo wa.me'),
                    ),
                  ],
                ),
                const SizedBox(height: 16),
                TextField(
                  controller: _tplNameCtrl,
                  decoration: const InputDecoration(
                    labelText: 'Template name (Meta)',
                    border: OutlineInputBorder(),
                    helperText: 'Debe estar aprobado en Business Manager',
                  ),
                ),
                const SizedBox(height: 8),
                TextField(
                  controller: _tplLangCtrl,
                  decoration: const InputDecoration(
                    labelText: 'Idioma template',
                    border: OutlineInputBorder(),
                  ),
                ),
                const SizedBox(height: 8),
                OutlinedButton.icon(
                  onPressed: _enviarTemplate,
                  icon: const Icon(Icons.description_rounded),
                  label: const Text('Enviar template API'),
                ),
                const SizedBox(height: 24),
                ErpSectionHeader(
                  title: 'Últimos envíos',
                  trailing: IconButton(
                    tooltip: 'Actualizar',
                    onPressed: _cargar,
                    icon: const Icon(Icons.refresh_rounded),
                  ),
                ),
                const SizedBox(height: 8),
                if (_log.isEmpty)
                  Text(
                    'Sin envíos registrados',
                    style: TextStyle(color: cs.onSurfaceVariant),
                  )
                else
                  ..._log.take(30).map((e) {
                    final color = e.estado == 'ok' || e.estado == 'abierto'
                        ? AppTokens.success
                        : AppTokens.danger;
                    return Card(
                      margin: const EdgeInsets.only(bottom: 6),
                      child: ListTile(
                        dense: true,
                        leading: Icon(
                          e.modo == 'deeplink'
                              ? Icons.open_in_new_rounded
                              : Icons.cloud_upload_rounded,
                          color: color,
                        ),
                        title: Text(
                          '${e.telefono} · ${e.modo}',
                          style: const TextStyle(fontWeight: FontWeight.w700),
                        ),
                        subtitle: Text(
                          '${e.estado}${e.error.isEmpty ? '' : ' · ${e.error}'}\n'
                          '${e.cuerpo}',
                          maxLines: 3,
                          overflow: TextOverflow.ellipsis,
                        ),
                        isThreeLine: true,
                        trailing: e.waMessageId.isEmpty
                            ? null
                            : IconButton(
                                tooltip: 'Copiar ID',
                                icon: const Icon(Icons.copy_rounded, size: 18),
                                onPressed: () async {
                                  await Clipboard.setData(
                                    ClipboardData(text: e.waMessageId),
                                  );
                                },
                              ),
                      ),
                    );
                  }),
              ],
            ),
    );
  }
}
