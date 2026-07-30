import 'package:flutter/material.dart';

/// Entradas del menú lateral (ids alineados con MainShell: `$modulo|$title`).
class ShellMenuEntry {
  final String id;
  final String title;
  final IconData icon;

  const ShellMenuEntry({
    required this.id,
    required this.title,
    required this.icon,
  });
}

/// Debe mantenerse en sync con `_items` de `main_shell.dart`.
/// Menú pyme: vender, stock, precios, compras — sin factura/AFIP/WA/CRM.
const List<ShellMenuEntry> kShellMenuCatalog = [
  ShellMenuEntry(id: 'dashboard|Inicio', title: 'Inicio', icon: Icons.home_rounded),
  ShellMenuEntry(id: 'remitos|Venta Rápida', title: 'Venta Rápida', icon: Icons.point_of_sale_rounded),
  ShellMenuEntry(id: 'productos|Productos', title: 'Productos', icon: Icons.inventory_2_rounded),
  ShellMenuEntry(id: 'productos|Papelera', title: 'Papelera', icon: Icons.delete_outline_rounded),
  ShellMenuEntry(id: 'productos|Categorías', title: 'Categorías', icon: Icons.category_rounded),
  ShellMenuEntry(id: 'remitos|Comprobantes', title: 'Comprobantes', icon: Icons.description_rounded),
  ShellMenuEntry(id: 'compras|Compras', title: 'Compras', icon: Icons.shopping_cart_rounded),
  ShellMenuEntry(id: 'stock|Stock', title: 'Stock', icon: Icons.warehouse_rounded),
  ShellMenuEntry(id: 'productos|Importar Productos', title: 'Importar Productos', icon: Icons.upload_file_rounded),
  ShellMenuEntry(id: 'listas_precios|Listas de Precios', title: 'Listas de Precios', icon: Icons.sell_rounded),
  ShellMenuEntry(id: 'listas_precios|Comparador de listas', title: 'Comparador de listas', icon: Icons.compare_arrows_rounded),
  ShellMenuEntry(id: 'clientes|Clientes', title: 'Clientes', icon: Icons.groups_rounded),
  ShellMenuEntry(id: 'clientes|Cuenta corriente', title: 'Cuenta corriente', icon: Icons.account_balance_wallet_rounded),
  ShellMenuEntry(id: 'proveedores|Proveedores', title: 'Proveedores', icon: Icons.local_shipping_rounded),
  ShellMenuEntry(id: 'reportes|Reportes', title: 'Reportes', icon: Icons.bar_chart_rounded),
  ShellMenuEntry(id: 'dashboard|Mi perfil', title: 'Mi perfil', icon: Icons.manage_accounts_rounded),
  ShellMenuEntry(id: 'usuarios|Usuarios', title: 'Usuarios', icon: Icons.people_alt_rounded),
  ShellMenuEntry(id: 'usuarios|Permisos', title: 'Permisos', icon: Icons.admin_panel_settings_rounded),
  ShellMenuEntry(id: 'backup|Respaldo', title: 'Respaldo', icon: Icons.cloud_upload_rounded),
  ShellMenuEntry(id: 'auditoria|Panel técnico', title: 'Panel técnico', icon: Icons.monitor_heart_rounded),
  ShellMenuEntry(id: 'configuracion|Configuración', title: 'Configuración', icon: Icons.settings_rounded),
];
