import 'dart:io';

import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../services/branding_service.dart';
import '../theme/app_theme.dart';
import '../theme/theme_provider.dart';
import 'listas_precio_page.dart';

class ConfiguracionPage extends StatefulWidget {
  const ConfiguracionPage({super.key});

  @override
  State<ConfiguracionPage> createState() => _ConfiguracionPageState();
}

class _ConfiguracionPageState extends State<ConfiguracionPage> {
  bool _mostrarImagenes = true;

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
  final _encabezadoPdfCtrl = TextEditingController();
  final _piePdfCtrl = TextEditingController();
  final _colorPdfCtrl = TextEditingController();
  String _logoPath = '';
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
    _cargarPreferencias();
    _cargarBranding();
  }

  @override
  void dispose() {
    themeProvider.removeListener(_onThemeChanged);
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
    _encabezadoPdfCtrl.dispose();
    _piePdfCtrl.dispose();
    _colorPdfCtrl.dispose();
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
    _encabezadoPdfCtrl.text = b.encabezadoPdf;
    _piePdfCtrl.text = b.piePdf;
    _colorPdfCtrl.text = b.colorPdf;
    setState(() => _logoPath = b.logoPath);
  }

  Future<void> _elegirLogo() async {
    final picker = ImagePicker();
    final img = await picker.pickImage(source: ImageSource.gallery, imageQuality: 80);
    if (img != null) setState(() => _logoPath = img.path);
  }

  Future<void> _guardarBranding() async {
    setState(() => _guardandoBranding = true);
    await BrandingService.instance.guardar(
      nombre: _nombreCtrl.text.trim(),
      slogan: _sloganCtrl.text.trim(),
      telefono: _telefonoCtrl.text.trim(),
      direccion: _direccionCtrl.text.trim(),
      logoPath: _logoPath,
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
      encabezadoPdf: _encabezadoPdfCtrl.text.trim(),
      piePdf: _piePdfCtrl.text.trim(),
      colorPdf: _colorPdfCtrl.text.trim().replaceAll('#', '').isEmpty
          ? 'FF7A00'
          : _colorPdfCtrl.text.trim().replaceAll('#', ''),
    );
    if (!mounted) return;
    setState(() => _guardandoBranding = false);
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text('Datos del negocio guardados')),
    );
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
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(16),
        child: Column(
          children: [
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
                        Text(
                          'MI NEGOCIO',
                          style: theme.textTheme.titleMedium?.copyWith(
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 16),
                    Center(
                      child: GestureDetector(
                        onTap: _elegirLogo,
                        child: Stack(
                          children: [
                            CircleAvatar(
                              radius: 48,
                              backgroundColor: colorScheme.primaryContainer,
                              backgroundImage: _logoPath.isNotEmpty
                                  ? FileImage(File(_logoPath))
                                  : null,
                              child: _logoPath.isEmpty
                                  ? Icon(Icons.store,
                                      size: 40, color: colorScheme.primary)
                                  : null,
                            ),
                            Positioned(
                              right: 0,
                              bottom: 0,
                              child: CircleAvatar(
                                radius: 14,
                                backgroundColor: colorScheme.primary,
                                child: const Icon(Icons.edit,
                                    size: 16, color: Colors.white),
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                    const SizedBox(height: 4),
                    Center(
                      child: Text(
                        'Tocá para cambiar el logo',
                        style: theme.textTheme.bodySmall
                            ?.copyWith(color: Colors.grey),
                      ),
                    ),
                    const SizedBox(height: 16),
                    TextField(
                      controller: _nombreCtrl,
                      decoration: const InputDecoration(
                        labelText: 'Nombre del negocio',
                        border: OutlineInputBorder(),
                        prefixIcon: Icon(Icons.business),
                      ),
                    ),
                    const SizedBox(height: 12),
                    TextField(
                      controller: _sloganCtrl,
                      decoration: const InputDecoration(
                        labelText: 'Slogan / descripción',
                        border: OutlineInputBorder(),
                        prefixIcon: Icon(Icons.short_text),
                      ),
                    ),
                    const SizedBox(height: 12),
                    TextField(
                      controller: _telefonoCtrl,
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
                      decoration: const InputDecoration(
                        labelText: 'Dirección',
                        border: OutlineInputBorder(),
                        prefixIcon: Icon(Icons.location_on),
                      ),
                    ),
                    const SizedBox(height: 12),
                    TextField(
                      controller: _emailCtrl,
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
                      decoration: const InputDecoration(
                        labelText: 'Instagram (opcional)',
                        border: OutlineInputBorder(),
                        prefixIcon: Icon(Icons.camera_alt_outlined),
                      ),
                    ),
                    const SizedBox(height: 12),
                    TextField(
                      controller: _facebookCtrl,
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
                      decoration: const InputDecoration(
                        labelText: 'CUIT del negocio',
                        border: OutlineInputBorder(),
                        prefixIcon: Icon(Icons.badge),
                      ),
                    ),
                    const SizedBox(height: 12),
                    TextField(
                      controller: _ingresosBrutosCtrl,
                      decoration: const InputDecoration(
                        labelText: 'Ingresos Brutos',
                        border: OutlineInputBorder(),
                        prefixIcon: Icon(Icons.account_balance),
                      ),
                    ),
                    const SizedBox(height: 12),
                    TextField(
                      controller: _condicionIvaCtrl,
                      decoration: const InputDecoration(
                        labelText: 'Condición frente al IVA',
                        border: OutlineInputBorder(),
                        prefixIcon: Icon(Icons.receipt_long),
                      ),
                    ),
                    const SizedBox(height: 12),
                    TextField(
                      controller: _direccionFiscalCtrl,
                      decoration: const InputDecoration(
                        labelText: 'Dirección fiscal',
                        border: OutlineInputBorder(),
                        prefixIcon: Icon(Icons.home_work_outlined),
                      ),
                    ),
                    const SizedBox(height: 16),
                    Text(
                      'Documentos PDF',
                      style: theme.textTheme.titleSmall
                          ?.copyWith(fontWeight: FontWeight.w600),
                    ),
                    const SizedBox(height: 12),
                    TextField(
                      controller: _encabezadoPdfCtrl,
                      decoration: const InputDecoration(
                        labelText: 'Encabezado / leyenda de PDF',
                        border: OutlineInputBorder(),
                        prefixIcon: Icon(Icons.description_outlined),
                      ),
                      maxLines: 2,
                    ),
                    const SizedBox(height: 12),
                    TextField(
                      controller: _piePdfCtrl,
                      decoration: const InputDecoration(
                        labelText: 'Pie de página / observaciones PDF',
                        border: OutlineInputBorder(),
                        prefixIcon: Icon(Icons.notes),
                      ),
                      maxLines: 2,
                    ),
                    const SizedBox(height: 12),
                    TextField(
                      controller: _colorPdfCtrl,
                      decoration: const InputDecoration(
                        labelText: 'Color encabezado PDF (hex, ej. FF6D00)',
                        border: OutlineInputBorder(),
                        prefixIcon: Icon(Icons.palette_outlined),
                      ),
                    ),
                    const SizedBox(height: 16),
                    SizedBox(
                      width: double.infinity,
                      child: ElevatedButton.icon(
                        onPressed: _guardandoBranding ? null : _guardarBranding,
                        icon: _guardandoBranding
                            ? const SizedBox(
                                width: 18,
                                height: 18,
                                child:
                                    CircularProgressIndicator(strokeWidth: 2),
                              )
                            : const Icon(Icons.save),
                        label: const Text('GUARDAR DATOS DEL NEGOCIO'),
                      ),
                    ),
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
