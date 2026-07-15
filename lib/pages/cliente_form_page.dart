import 'dart:io';

import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';
import 'package:uuid/uuid.dart';

import '../core/sync/firestore_sync_service.dart';
import '../core/sync/media_sync_service.dart';
import '../core/utils/media_path.dart';
import '../models/cliente.dart';
import '../services/cliente_service.dart';
import '../theme/module_app_bar.dart';
import '../widgets/comentarios_internos_sheet.dart';

class ClienteFormPage extends StatefulWidget {
  final Cliente? cliente;

  const ClienteFormPage({super.key, this.cliente});

  @override
  State<ClienteFormPage> createState() => _ClienteFormPageState();
}

class _ClienteFormPageState extends State<ClienteFormPage> {
  final ClienteService service = ClienteService();
  final GlobalKey<FormState> formKey = GlobalKey<FormState>();

  late TextEditingController nombreController;
  late TextEditingController apellidoController;
  late TextEditingController telefonoController;
  late TextEditingController whatsappController;
  late TextEditingController emailController;
  late TextEditingController direccionController;
  late TextEditingController localidadController;
  late TextEditingController provinciaController;
  late TextEditingController cuitController;
  late TextEditingController condicionIvaController;
  late TextEditingController observacionesController;
  late TextEditingController descuentoController;
  late TextEditingController saldoController;
  late TextEditingController limiteCuentaController;

  String _foto = '';
  bool guardando = false;

  bool get esEdicion => widget.cliente != null;

  @override
  void initState() {
    super.initState();
    _foto = widget.cliente?.foto ?? '';
    nombreController = TextEditingController(text: widget.cliente?.nombre ?? '');
    apellidoController =
        TextEditingController(text: widget.cliente?.apellido ?? '');
    telefonoController =
        TextEditingController(text: widget.cliente?.telefono ?? '');
    whatsappController =
        TextEditingController(text: widget.cliente?.whatsapp ?? '');
    emailController = TextEditingController(text: widget.cliente?.email ?? '');
    direccionController =
        TextEditingController(text: widget.cliente?.direccion ?? '');
    localidadController =
        TextEditingController(text: widget.cliente?.localidad ?? '');
    provinciaController =
        TextEditingController(text: widget.cliente?.provincia ?? '');
    cuitController = TextEditingController(text: widget.cliente?.cuit ?? '');
    condicionIvaController =
        TextEditingController(text: widget.cliente?.condicionIva ?? '');
    observacionesController =
        TextEditingController(text: widget.cliente?.observaciones ?? '');
    descuentoController = TextEditingController(
      text: (widget.cliente?.descuento ?? 0).toStringAsFixed(1),
    );
    saldoController = TextEditingController(
      text: (widget.cliente?.saldo ?? 0).toStringAsFixed(2),
    );
    limiteCuentaController = TextEditingController(
      text: (widget.cliente?.limiteCuenta ?? 0).toStringAsFixed(2),
    );
  }

  @override
  void dispose() {
    nombreController.dispose();
    apellidoController.dispose();
    telefonoController.dispose();
    whatsappController.dispose();
    emailController.dispose();
    direccionController.dispose();
    localidadController.dispose();
    provinciaController.dispose();
    cuitController.dispose();
    condicionIvaController.dispose();
    observacionesController.dispose();
    descuentoController.dispose();
    saldoController.dispose();
    limiteCuentaController.dispose();
    super.dispose();
  }

  double _parseDbl(String text) =>
      double.tryParse(text.replaceAll(',', '.')) ?? 0;

  Future<void> _elegirFoto() async {
    final img = await ImagePicker().pickImage(
      source: ImageSource.gallery,
      imageQuality: 85,
      maxWidth: 1200,
    );
    if (img == null) return;
    try {
      final docs = await getApplicationDocumentsDirectory();
      final dir = Directory(p.join(docs.path, 'clientes_fotos'));
      if (!await dir.exists()) await dir.create(recursive: true);
      final ext = p.extension(img.path).isEmpty ? '.jpg' : p.extension(img.path);
      final dest = p.join(dir.path, 'cli_${const Uuid().v4()}$ext');
      await File(img.path).copy(dest);
      if (!mounted) return;
      setState(() => _foto = dest);
    } catch (_) {
      if (!mounted) return;
      setState(() => _foto = img.path);
    }
  }

  Future<String> _fotoParaGuardar(String syncKey) async {
    if (_foto.isEmpty) return '';
    if (esUrlRemota(_foto)) return _foto;
    final file = File(_foto);
    if (!file.existsSync()) return _foto;
    if (!MediaSyncService.instance.nubeDisponible) return _foto;
    final url = await MediaSyncService.instance.subirArchivo(
      storagePath:
          'tenants/${MediaSyncService.instance.tenantId}/clientes/$syncKey/foto_${const Uuid().v4()}.jpg',
      file: file,
      contentType: 'image/jpeg',
    );
    return url ?? _foto;
  }

  Future<void> guardar() async {
    if (!formKey.currentState!.validate()) return;

    setState(() => guardando = true);

    final descuento =
        _parseDbl(descuentoController.text).clamp(0.0, 100.0).toDouble();
    final syncId = widget.cliente?.syncId.isNotEmpty == true
        ? widget.cliente!.syncId
        : const Uuid().v4();

    final fotoFinal = await _fotoParaGuardar(syncId);

    final cliente = Cliente(
      id: widget.cliente?.id,
      syncId: syncId,
      nombre: nombreController.text.trim(),
      apellido: apellidoController.text.trim(),
      telefono: telefonoController.text.trim(),
      whatsapp: whatsappController.text.trim(),
      email: emailController.text.trim(),
      direccion: direccionController.text.trim(),
      localidad: localidadController.text.trim(),
      provincia: provinciaController.text.trim(),
      cuit: cuitController.text.trim(),
      condicionIva: condicionIvaController.text.trim(),
      observaciones: observacionesController.text.trim(),
      foto: fotoFinal,
      descuento: descuento,
      saldo: _parseDbl(saldoController.text),
      limiteCuenta: _parseDbl(limiteCuentaController.text),
    );

    if (esEdicion) {
      await service.actualizar(cliente);
    } else {
      await service.insertar(cliente);
    }

    if (!mounted) return;
    final detalle = FirestoreSyncService.instance.syncStatusDetail;
    if (detalle != null &&
        detalle.toLowerCase().contains('nube') &&
        context.mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(detalle), duration: const Duration(seconds: 5)),
      );
    }
    Navigator.pop(context);
  }

  Widget _campo(
    String label,
    TextEditingController controller, {
    IconData? icon,
    TextInputType? keyboardType,
    int maxLines = 1,
  }) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 16),
      child: TextFormField(
        controller: controller,
        keyboardType: keyboardType,
        maxLines: maxLines,
        decoration: InputDecoration(
          labelText: label,
          prefixIcon: icon != null ? Icon(icon) : null,
          border: const OutlineInputBorder(),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final provider = imageProviderDesdePath(_foto);

    return Scaffold(
      appBar: buildModuleAppBar(
        context,
        title: esEdicion ? "Editar cliente" : "Nuevo cliente",
        actions: [
          if (esEdicion && widget.cliente?.id != null)
            ComentariosInternosButton(
              entidadTipo: 'cliente',
              entidadId: '${widget.cliente!.id}',
              titulo:
                  '${widget.cliente!.nombre} ${widget.cliente!.apellido}'.trim(),
            ),
        ],
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(16),
        child: Form(
          key: formKey,
          child: Column(
            children: [
              GestureDetector(
                onTap: guardando ? null : _elegirFoto,
                child: CircleAvatar(
                  radius: 48,
                  backgroundColor: cs.primaryContainer,
                  backgroundImage: provider,
                  child: provider == null
                      ? Icon(Icons.add_a_photo_rounded,
                          size: 32, color: cs.onPrimaryContainer)
                      : null,
                ),
              ),
              const SizedBox(height: 6),
              Text(
                'Foto del cliente (opcional)',
                style: Theme.of(context).textTheme.bodySmall?.copyWith(
                      color: cs.onSurfaceVariant,
                    ),
              ),
              if (_foto.isNotEmpty)
                TextButton(
                  onPressed: () => setState(() => _foto = ''),
                  child: const Text('Quitar foto'),
                ),
              const SizedBox(height: 12),
              TextFormField(
                controller: nombreController,
                decoration: const InputDecoration(
                  labelText: "Nombre *",
                  prefixIcon: Icon(Icons.person),
                  border: OutlineInputBorder(),
                ),
                validator: (v) =>
                    v == null || v.trim().isEmpty ? "Ingresá el nombre" : null,
              ),
              const SizedBox(height: 16),
              _campo("Apellido", apellidoController, icon: Icons.badge_outlined),
              _campo("Teléfono", telefonoController,
                  icon: Icons.phone, keyboardType: TextInputType.phone),
              _campo("WhatsApp", whatsappController,
                  icon: Icons.chat, keyboardType: TextInputType.phone),
              _campo("Email", emailController,
                  icon: Icons.email_outlined,
                  keyboardType: TextInputType.emailAddress),
              _campo("Dirección", direccionController,
                  icon: Icons.location_on),
              _campo("Localidad", localidadController,
                  icon: Icons.location_city_outlined),
              _campo("Provincia", provinciaController, icon: Icons.map_outlined),
              _campo("CUIT", cuitController, icon: Icons.badge),
              _campo("Condición IVA", condicionIvaController,
                  icon: Icons.receipt_long_outlined),
              TextFormField(
                controller: descuentoController,
                decoration: const InputDecoration(
                  labelText: "Descuento (%)",
                  prefixIcon: Icon(Icons.percent),
                  border: OutlineInputBorder(),
                ),
                keyboardType:
                    const TextInputType.numberWithOptions(decimal: true),
                validator: (value) {
                  final texto = (value ?? '').trim();
                  if (texto.isEmpty) return null;
                  final descuento = double.tryParse(texto.replaceAll(',', '.'));
                  if (descuento == null) return 'Ingresá un número válido';
                  if (descuento < 0 || descuento > 100) {
                    return 'El descuento debe estar entre 0 y 100';
                  }
                  return null;
                },
              ),
              const SizedBox(height: 16),
              _campo("Saldo de cuenta corriente", saldoController,
                  icon: Icons.account_balance_wallet_outlined,
                  keyboardType: const TextInputType.numberWithOptions(
                      decimal: true, signed: true)),
              _campo("Límite de cuenta corriente", limiteCuentaController,
                  icon: Icons.credit_card,
                  keyboardType:
                      const TextInputType.numberWithOptions(decimal: true)),
              _campo("Observaciones", observacionesController,
                  icon: Icons.notes, maxLines: 3),
              const SizedBox(height: 24),
              SizedBox(
                width: double.infinity,
                height: 50,
                child: ElevatedButton.icon(
                  onPressed: guardando ? null : guardar,
                  icon: guardando
                      ? const SizedBox(
                          width: 20,
                          height: 20,
                          child: CircularProgressIndicator(strokeWidth: 2),
                        )
                      : const Icon(Icons.save),
                  label: Text(esEdicion ? "ACTUALIZAR" : "GUARDAR"),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
