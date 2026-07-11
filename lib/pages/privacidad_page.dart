import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../theme/module_app_bar.dart';

class PrivacidadPage extends StatefulWidget {
  const PrivacidadPage({super.key});

  @override
  State<PrivacidadPage> createState() => _PrivacidadPageState();
}

class _PrivacidadPageState extends State<PrivacidadPage> {
  String _texto = 'Cargando…';

  @override
  void initState() {
    super.initState();
    _cargar();
  }

  Future<void> _cargar() async {
    try {
      final raw =
          await rootBundle.loadString('assets/docs/PRIVACY_POLICY.md');
      if (!mounted) return;
      setState(() => _texto = raw);
    } catch (_) {
      if (!mounted) return;
      setState(() => _texto = 'No se pudo cargar la política de privacidad.');
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: buildModuleAppBar(context, title: 'Privacidad'),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(16),
        child: SelectableText(
          _texto,
          style: const TextStyle(fontSize: 14, height: 1.35),
        ),
      ),
    );
  }
}
