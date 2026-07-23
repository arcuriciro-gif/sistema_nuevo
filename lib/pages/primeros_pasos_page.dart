import 'package:flutter/material.dart';

import '../theme/module_app_bar.dart';

/// Guía corta en la app: primeros pasos para poner Tata a trabajar.
class PrimerosPasosPage extends StatelessWidget {
  const PrimerosPasosPage({super.key, this.onIrA});

  /// Navega a un módulo del menú (título exacto de MainShell).
  final void Function(String tituloModulo)? onIrA;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return Scaffold(
      appBar: buildModuleAppBar(context, title: 'Primeros pasos'),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(16, 12, 16, 32),
        children: [
          Text(
            'Empezá acá',
            style: Theme.of(context).textTheme.headlineSmall?.copyWith(
                  fontWeight: FontWeight.w700,
                ),
          ),
          const SizedBox(height: 6),
          Text(
            'Pasos cortos para dejar la PC y el celular alineados. '
            'Si Sync está activo, lo que cargues en un equipo aparece en el otro.',
            style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                  color: cs.onSurfaceVariant,
                ),
          ),
          const SizedBox(height: 16),
          _PasoCard(
            paso: 1,
            titulo: 'Activar la nube (Sync)',
            cuerpo:
                'En Configuración activá Sync / nube. Usá el mismo código de '
                'empresa en la PC y en el celular. Sin Sync cada equipo queda solo.',
            boton: 'Ir a Configuración',
            onPressed: onIrA == null ? null : () => onIrA!('Configuración'),
          ),
          _PasoCard(
            paso: 2,
            titulo: 'Crear un usuario',
            cuerpo:
                'En Usuarios → Nuevo: nombre de usuario, clave y rol '
                '(admin / encargado / empleado). Con ese usuario entrá en el celular.',
            boton: 'Ir a Usuarios',
            onPressed: onIrA == null ? null : () => onIrA!('Usuarios'),
          ),
          _PasoCard(
            paso: 3,
            titulo: 'Cargar un producto',
            cuerpo:
                'En Productos → Nuevo: código, descripción, costo, precio y stock. '
                'Ese producto se usa en venta rápida, remitos y facturas.',
            boton: 'Ir a Productos',
            onPressed: onIrA == null ? null : () => onIrA!('Productos'),
          ),
          _PasoCard(
            paso: 4,
            titulo: 'Hacer la primera venta',
            cuerpo:
                'Venta rápida (mostrador) o Remito / Factura B-C. Al emitir elegí '
                'Pendiente, Parcial o Cobrado. Si queda saldo, va a cuenta corriente.',
            boton: 'Ir a Venta Rápida',
            onPressed: onIrA == null ? null : () => onIrA!('Venta Rápida'),
          ),
          _PasoCard(
            paso: 5,
            titulo: 'Revisar en el otro equipo',
            cuerpo:
                'En Ventas totales (o Remitos / Facturas) del celular debería '
                'aparecer lo cargado en la PC (y al revés). Si tarda unos segundos, '
                'esperá: en la PC el sync es suave para no cerrar el programa.',
            boton: 'Ir a Ventas / Facturas',
            onPressed: onIrA == null ? null : () => onIrA!('Ventas / Facturas'),
          ),
          const SizedBox(height: 8),
          Card(
            child: ListTile(
              leading: Icon(Icons.menu_book_rounded, color: cs.primary),
              title: const Text('Manual completo'),
              subtitle: const Text('PDF con más detalle de cada módulo'),
              trailing: const Icon(Icons.chevron_right),
              onTap: onIrA == null ? null : () => onIrA!('Manual de usuario'),
            ),
          ),
        ],
      ),
    );
  }
}

class _PasoCard extends StatelessWidget {
  const _PasoCard({
    required this.paso,
    required this.titulo,
    required this.cuerpo,
    required this.boton,
    this.onPressed,
  });

  final int paso;
  final String titulo;
  final String cuerpo;
  final String boton;
  final VoidCallback? onPressed;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: Material(
        color: cs.surfaceContainerHighest.withValues(alpha: 0.45),
        borderRadius: BorderRadius.circular(12),
        child: Padding(
          padding: const EdgeInsets.all(14),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  CircleAvatar(
                    radius: 14,
                    backgroundColor: cs.primary,
                    foregroundColor: cs.onPrimary,
                    child: Text(
                      '$paso',
                      style: const TextStyle(
                        fontWeight: FontWeight.w700,
                        fontSize: 13,
                      ),
                    ),
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Text(
                      titulo,
                      style: const TextStyle(
                        fontWeight: FontWeight.w700,
                        fontSize: 16,
                      ),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 8),
              Text(cuerpo, style: Theme.of(context).textTheme.bodyMedium),
              if (onPressed != null) ...[
                const SizedBox(height: 10),
                Align(
                  alignment: Alignment.centerLeft,
                  child: FilledButton.tonal(
                    onPressed: onPressed,
                    child: Text(boton),
                  ),
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }
}
