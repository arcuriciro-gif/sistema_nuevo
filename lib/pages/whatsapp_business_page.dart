import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../plugins/whatsapp/whatsapp_business_config.dart';
import '../plugins/whatsapp/whatsapp_business_service.dart';
import '../plugins/whatsapp/whatsapp_message_log.dart';
import '../services/whatsapp_plantillas_service.dart';
import '../theme/app_tokens.dart';
import '../theme/module_app_bar.dart';
import '../widgets/erp/erp_section_header.dart';

/// Configuración del plugin WhatsApp Business (Cloud API + deeplink).
class WhatsappBusinessPage extends StatefulWidget {
  const WhatsappBusinessPage({super.key});

  @override
  State<WhatsappBusinessPage> createState() => _WhatsappBusinessPageState();
}

class _WhatsappBusinessPageState extends State<WhatsappBusinessPage> {
  final _cfg = WhatsappBusinessConfig.instance;
  final _svc = WhatsappBusinessService.instance;
  final _tpl = WhatsappPlantillasService.instance;

  final _tokenCtrl = TextEditingController();
  final _phoneIdCtrl = TextEditingController();
  final _wabaCtrl = TextEditingController();
  final _versionCtrl = TextEditingController();
  final _countryCtrl = TextEditingController();
  final _testPhoneCtrl = TextEditingController();
  final _testMsgCtrl = TextEditingController();
  final _tplNameCtrl = TextEditingController();
  final _tplLangCtrl = TextEditingController(text: 'es_AR');

  List<WhatsappMessageLog> _log = [];
  bool _cargando = true;
  String? _status;

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
    if (!mounted) return;
    setState(() {
      _tokenCtrl.text = _cfg.accessToken;
      _phoneIdCtrl.text = _cfg.phoneNumberId;
      _wabaCtrl.text = _cfg.wabaId;
      _versionCtrl.text = _cfg.apiVersion;
      _countryCtrl.text = _cfg.defaultCountryCode;
      _testMsgCtrl.text = _tpl.render(
        _tpl.general,
        nombre: 'Cliente',
        empresa: 'Tu comercio',
      );
      _log = log;
      _cargando = false;
    });
  }

  Future<void> _guardar() async {
    await _cfg.guardar(
      accessToken: _tokenCtrl.text,
      phoneNumberId: _phoneIdCtrl.text,
      wabaId: _wabaCtrl.text,
      apiVersion: _versionCtrl.text,
      defaultCountryCode: _countryCtrl.text,
    );
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text('Configuración WhatsApp guardada')),
    );
    setState(() {});
  }

  Future<void> _probarConexion() async {
    await _guardar();
    final r = await _svc.probarConexion();
    if (!mounted) return;
    setState(() => _status = r);
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
