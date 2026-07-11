import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';

import '../core/utils/media_path.dart';
import '../models/cliente.dart';
import '../services/branding_service.dart';
import '../services/cliente_service.dart';
import '../theme/module_app_bar.dart';
import '../widgets/comentarios_internos_sheet.dart';
import '../widgets/form_save_bar.dart';

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

  bool guardando = false;
  String foto = '';

  bool get esEdicion => widget.cliente != null;

  @override
  void initState() {
    super.initState();
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
    foto = widget.cliente?.foto ?? '';
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

  Future<void> _mostrarOpcionesFoto() async {
    final accion = await showModalBottomSheet<String>(
      context: context,
      builder: (ctx) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            ListTile(
              leading: const Icon(Icons.photo_library_outlined),
              title: const Text('Galería'),
              onTap: () => Navigator.pop(ctx, 'gallery'),
            ),
            ListTile(
              leading: const Icon(Icons.photo_camera_outlined),
              title: const Text('Cámara'),
              onTap: () => Navigator.pop(ctx, 'camera'),
            ),
            if (foto.trim().isNotEmpty)
              ListTile(
                leading: const Icon(Icons.delete_outline, color: Colors.red),
                title: const Text('Quitar foto'),
                onTap: () => Navigator.pop(ctx, 'remove'),
              ),
          ],
        ),
      ),
    );
    if (!mounted || accion == null) return;
    if (accion == 'remove') {
      setState(() => foto = '');
      return;
    }
    final picker = ImagePicker();
    final img = await picker.pickImage(
      source: accion == 'camera' ? ImageSource.camera : ImageSource.gallery,
      imageQuality: 80,
      maxWidth: 1024,
    );
    if (img == null || !mounted) return;
    final base = 'cliente_${widget.cliente?.id ?? DateTime.now().millisecondsSinceEpoch}';
    final path = await BrandingService.instance.persistirImagen(img.path, base);
    if (!mounted) return;
    setState(() => foto = path);
  }

  Future<void> guardar() async {
    if (!formKey.currentState!.validate()) return;

    setState(() => guardando = true);

    final descuento =
        _parseDbl(descuentoController.text).clamp(0.0, 100.0).toDouble();

    final cliente = Cliente(
      id: widget.cliente?.id,
      syncId: widget.cliente?.syncId ?? '',
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
      foto: foto,
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
    return Scaffold(
      appBar: buildModuleAppBar(
        context,
        title: esEdicion ? "Editar cliente" : "Nuevo cliente",
        actions: [
          if (esEdicion && widget.cliente?.id != null)
            ComentariosInternosButton(
              entidadTipo: 'cliente',
              entidadId: '${widget.cliente!.id}',
              titulo: '${widget.cliente!.nombre} ${widget.cliente!.apellido}'.trim(),
            ),
        ],
      ),
      bottomNavigationBar: FormSaveBar(
        onPressed: guardando ? null : guardar,
        loading: guardando,
        label: esEdicion ? 'ACTUALIZAR' : 'GUARDAR',
      ),
      body: SingleChildScrollView(
        padding: formScrollPadding(context),
        child: Form(
          key: formKey,
          child: Column(
            children: [
              Builder(
                builder: (context) {
                  final cs = Theme.of(context).colorScheme;
                  final provider = imageProviderDesdePath(foto);
                  final nombre = nombreController.text.trim();
                  final inicial = nombre.isEmpty ? '?' : nombre[0].toUpperCase();
                  return Padding(
                    padding: const EdgeInsets.only(bottom: 20),
                    child: Column(
                      children: [
                        CircleAvatar(
                          radius: 44,
                          backgroundColor: cs.primaryContainer,
                          backgroundImage: provider,
                          child: provider == null
                              ? Text(
                                  inicial,
                                  style: TextStyle(
                                    fontSize: 32,
                                    fontWeight: FontWeight.w700,
                                    color: cs.onPrimaryContainer,
                                  ),
                                )
                              : null,
                        ),
                        const SizedBox(height: 8),
                        TextButton.icon(
                          onPressed: guardando ? null : _mostrarOpcionesFoto,
                          icon: const Icon(Icons.photo_camera_outlined),
                          label: Text(
                            foto.trim().isEmpty ? 'Agregar foto' : 'Cambiar foto',
                          ),
                        ),
                      ],
                    ),
                  );
                },
              ),
              TextFormField(
                controller: nombreController,
                onChanged: (_) => setState(() {}),
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
              const SizedBox(height: 8),
            ],
          ),
        ),
      ),
    );
  }
}
