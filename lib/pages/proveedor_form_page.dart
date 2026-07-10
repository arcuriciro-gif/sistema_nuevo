import 'package:flutter/material.dart';

import '../models/proveedor.dart';
import '../services/proveedor_service.dart';

class ProveedorFormPage extends StatefulWidget {
  final Proveedor? proveedor;

  const ProveedorFormPage({
    super.key,
    this.proveedor,
  });

  @override
  State<ProveedorFormPage> createState() => _ProveedorFormPageState();
}

class _ProveedorFormPageState extends State<ProveedorFormPage> {
  final ProveedorService service = ProveedorService();
  final GlobalKey<FormState> formKey = GlobalKey<FormState>();

  late TextEditingController nombreController;
  late TextEditingController contactoController;
  late TextEditingController telefonoController;
  late TextEditingController whatsappController;
  late TextEditingController emailController;
  late TextEditingController webController;
  late TextEditingController cuitController;
  late TextEditingController condicionesComercialesController;
  late TextEditingController tiempoEntregaController;
  late TextEditingController observacionesController;

  bool activo = true;
  bool guardando = false;

  @override
  void initState() {
    super.initState();

    nombreController = TextEditingController(
      text: widget.proveedor?.nombre ?? '',
    );
    contactoController = TextEditingController(
      text: widget.proveedor?.contacto ?? '',
    );
    telefonoController = TextEditingController(
      text: widget.proveedor?.telefono ?? '',
    );
    whatsappController = TextEditingController(
      text: widget.proveedor?.whatsapp ?? '',
    );
    emailController = TextEditingController(
      text: widget.proveedor?.email ?? '',
    );
    webController = TextEditingController(
      text: widget.proveedor?.web ?? '',
    );
    cuitController = TextEditingController(
      text: widget.proveedor?.cuit ?? '',
    );
    condicionesComercialesController = TextEditingController(
      text: widget.proveedor?.condicionesComerciales ?? '',
    );
    tiempoEntregaController = TextEditingController(
      text: widget.proveedor?.tiempoEntrega ?? '',
    );
    observacionesController = TextEditingController(
      text: widget.proveedor?.observaciones ?? '',
    );

    activo = widget.proveedor?.activo ?? true;
  }

  @override
  void dispose() {
    nombreController.dispose();
    contactoController.dispose();
    telefonoController.dispose();
    whatsappController.dispose();
    emailController.dispose();
    webController.dispose();
    cuitController.dispose();
    condicionesComercialesController.dispose();
    tiempoEntregaController.dispose();
    observacionesController.dispose();

    super.dispose();
  }

  Future<void> guardar() async {
    if (!formKey.currentState!.validate()) return;
    final messenger = ScaffoldMessenger.of(context);
    final navigator = Navigator.of(context);

    setState(() {
      guardando = true;
    });

    try {
      final proveedor = Proveedor(
        id: widget.proveedor?.id,
        nombre: nombreController.text,
        contacto: contactoController.text,
        telefono: telefonoController.text,
        whatsapp: whatsappController.text,
        email: emailController.text,
        web: webController.text,
        cuit: cuitController.text,
        condicionesComerciales: condicionesComercialesController.text,
        tiempoEntrega: tiempoEntregaController.text,
        observaciones: observacionesController.text,
        fechaCreacion: widget.proveedor?.fechaCreacion,
        activo: activo,
      );

      if (widget.proveedor == null) {
        await service.insertar(proveedor);
        if (!mounted) return;
        messenger.showSnackBar(
          const SnackBar(
            content: Text("Proveedor guardado exitosamente"),
            backgroundColor: Colors.green,
          ),
        );
      } else {
        await service.actualizar(proveedor);
        if (!mounted) return;
        messenger.showSnackBar(
          const SnackBar(
            content: Text("Proveedor actualizado exitosamente"),
            backgroundColor: Colors.green,
          ),
        );
      }

      if (!mounted) return;
      navigator.pop();
    } catch (e) {
      if (!mounted) return;
      messenger.showSnackBar(
        SnackBar(
          content: Text("Error: $e"),
          backgroundColor: Colors.red,
        ),
      );
    } finally {
      if (mounted) {
        setState(() {
          guardando = false;
        });
      }
    }
  }

  Widget _campo(
    String label,
    TextEditingController controller, {
    IconData? icon,
    TextInputType? keyboardType,
    int maxLines = 1,
    String? Function(String?)? validator,
  }) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 16),
      child: TextFormField(
        controller: controller,
        keyboardType: keyboardType,
        maxLines: maxLines,
        validator: validator,
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
      appBar: AppBar(
        title: Text(
          widget.proveedor == null ? "Nuevo Proveedor" : "Editar Proveedor",
        ),
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(16),
        child: Form(
          key: formKey,
          child: Column(
            children: [
              _campo(
                "Nombre del Proveedor",
                nombreController,
                icon: Icons.business,
                validator: (value) {
                  if (value == null || value.isEmpty) {
                    return "El nombre es requerido";
                  }
                  return null;
                },
              ),
              _campo("Persona de contacto", contactoController,
                  icon: Icons.person_outline),
              _campo(
                "Teléfono",
                telefonoController,
                icon: Icons.phone,
                keyboardType: TextInputType.phone,
                validator: (value) {
                  if (value == null || value.isEmpty) {
                    return "El teléfono es requerido";
                  }
                  return null;
                },
              ),
              _campo("WhatsApp", whatsappController,
                  icon: Icons.chat, keyboardType: TextInputType.phone),
              _campo(
                "Email",
                emailController,
                icon: Icons.email,
                keyboardType: TextInputType.emailAddress,
                validator: (value) {
                  if (value == null || value.isEmpty) {
                    return "El email es requerido";
                  }
                  if (!RegExp(r'^[^@]+@[^@]+\.[^@]+').hasMatch(value)) {
                    return "Ingrese un email válido";
                  }
                  return null;
                },
              ),
              _campo("Sitio web", webController, icon: Icons.language),
              _campo("CUIT", cuitController, icon: Icons.badge),
              _campo(
                "Condiciones comerciales",
                condicionesComercialesController,
                icon: Icons.handshake_outlined,
                maxLines: 2,
              ),
              _campo("Tiempo de entrega", tiempoEntregaController,
                  icon: Icons.local_shipping_outlined),
              _campo("Observaciones", observacionesController,
                  icon: Icons.note, maxLines: 3),
              const SizedBox(height: 16),
              CheckboxListTile(
                title: const Text("Proveedor Activo"),
                value: activo,
                onChanged: (value) {
                  setState(() {
                    activo = value ?? true;
                  });
                },
              ),
              const SizedBox(height: 24),
              SizedBox(
                width: double.infinity,
                height: 50,
                child: ElevatedButton(
                  onPressed: guardando ? null : guardar,
                  child: guardando
                      ? const SizedBox(
                          height: 24,
                          width: 24,
                          child: CircularProgressIndicator(
                            strokeWidth: 2,
                          ),
                        )
                      : const Text("Guardar Proveedor"),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
