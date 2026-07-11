import 'package:flutter/material.dart';

import '../services/menu_preferencias_service.dart';
import '../theme/module_app_bar.dart';

class MenuLateralConfigPage extends StatefulWidget {
  const MenuLateralConfigPage({super.key});

  @override
  State<MenuLateralConfigPage> createState() => _MenuLateralConfigPageState();
}

class _MenuLateralConfigPageState extends State<MenuLateralConfigPage> {
  final _svc = MenuPreferenciasService.instance;

  @override
  void initState() {
    super.initState();
    _svc.addListener(_onChange);
    if (!_svc.cargado) {
      _svc.cargar();
    }
  }

  void _onChange() {
    if (mounted) setState(() {});
  }

  @override
  void dispose() {
    _svc.removeListener(_onChange);
    super.dispose();
  }

  int get _visibles {
    return MenuPreferenciasService.catalogo
        .where((i) => _svc.estaVisible(i.id))
        .length;
  }

  Future<void> _snack(String msg) async {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(msg)));
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final total = MenuPreferenciasService.catalogo.length;
    final porGrupo = <String, List<({String id, String titulo, String grupo})>>{};
    for (final item in MenuPreferenciasService.catalogo) {
      porGrupo.putIfAbsent(item.grupo, () => []).add(item);
    }

    return Scaffold(
      appBar: buildModuleAppBar(
        context,
        title: 'Personalizar menú',
        actions: [
          TextButton(
            onPressed: () async {
              await _svc.mostrarTodos();
              await _snack('Se mostraron todos los módulos ($_visibles/$total)');
            },
            child: const Text('Todos'),
          ),
        ],
      ),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(12, 12, 12, 24),
        children: [
          Card(
            child: Padding(
              padding: const EdgeInsets.all(12),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    'Menú de ${_svc.plataformaLabel}',
                    style: const TextStyle(fontWeight: FontWeight.bold),
                  ),
                  const SizedBox(height: 6),
                  Text(
                    'Activá solo lo que usás en este dispositivo. '
                    'Lo que desactivás no aparece en la barra lateral. '
                    'Inicio y Configuración siempre quedan visibles.',
                    style: TextStyle(
                      fontSize: 13,
                      color: cs.onSurfaceVariant,
                    ),
                  ),
                  const SizedBox(height: 10),
                  Text(
                    'Visibles ahora: $_visibles de $total',
                    style: TextStyle(
                      fontWeight: FontWeight.w700,
                      color: cs.primary,
                    ),
                  ),
                  const SizedBox(height: 10),
                  Wrap(
                    spacing: 8,
                    runSpacing: 8,
                    children: [
                      OutlinedButton.icon(
                        onPressed: () async {
                          await _svc.aplicarPerfilMovil();
                          await _snack(
                            'Perfil móvil: $_visibles módulos esenciales',
                          );
                        },
                        icon: const Icon(Icons.phone_android_rounded, size: 18),
                        label: const Text('Perfil móvil'),
                      ),
                      OutlinedButton.icon(
                        onPressed: () async {
                          await _svc.aplicarPerfilOperaciones();
                          await _snack(
                            'Perfil operaciones: $_visibles módulos de venta/stock',
                          );
                        },
                        icon: const Icon(Icons.storefront_rounded, size: 18),
                        label: const Text('Perfil operaciones'),
                      ),
                      OutlinedButton.icon(
                        onPressed: () async {
                          await _svc.mostrarTodos();
                          await _snack('Perfil completo: todos visibles');
                        },
                        icon: const Icon(Icons.desktop_windows_rounded, size: 18),
                        label: const Text('Perfil completo'),
                      ),
                    ],
                  ),
                ],
              ),
            ),
          ),
          const SizedBox(height: 8),
          for (final grupo in porGrupo.keys) ...[
            Padding(
              padding: const EdgeInsets.fromLTRB(4, 12, 4, 4),
              child: Text(
                grupo,
                style: TextStyle(
                  fontWeight: FontWeight.w700,
                  color: cs.primary,
                  fontSize: 13,
                ),
              ),
            ),
            Card(
              margin: const EdgeInsets.only(bottom: 4),
              child: Column(
                children: [
                  for (final item in porGrupo[grupo]!)
                    SwitchListTile(
                      dense: true,
                      title: Text(item.titulo),
                      subtitle: MenuPreferenciasService.idsObligatorios
                              .contains(item.id)
                          ? const Text('Siempre visible')
                          : Text(
                              _svc.estaVisible(item.id)
                                  ? 'Se muestra en el menú'
                                  : 'Oculto en este dispositivo',
                              style: TextStyle(
                                fontSize: 12,
                                color: _svc.estaVisible(item.id)
                                    ? cs.onSurfaceVariant
                                    : cs.error,
                              ),
                            ),
                      value: _svc.estaVisible(item.id),
                      onChanged: MenuPreferenciasService.idsObligatorios
                              .contains(item.id)
                          ? null
                          : (v) => _svc.setVisible(item.id, v),
                    ),
                ],
              ),
            ),
          ],
        ],
      ),
    );
  }
}
