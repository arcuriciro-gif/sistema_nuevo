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
const List<ShellMenuEntry> kShellMenuCatalog = [
  ShellMenuEntry(id: 'dashboard|Inicio', title: 'Inicio', icon: Icons.home_rounded),
  ShellMenuEntry(id: 'remitos|Venta Rápida', title: 'Venta Rápida', icon: Icons.point_of_sale_rounded),
  ShellMenuEntry(id: 'productos|Productos', title: 'Productos', icon: Icons.inventory_2_rounded),
  ShellMenuEntry(id: 'comunicaciones|Comunicaciones', title: 'Comunicaciones', icon: Icons.forum_rounded),
  ShellMenuEntry(id: 'dashboard|Dashboard', title: 'Dashboard', icon: Icons.query_stats_rounded),
  ShellMenuEntry(id: 'productos|Papelera', title: 'Papelera', icon: Icons.delete_outline_rounded),
  ShellMenuEntry(id: 'productos|Categorías', title: 'Categorías', icon: Icons.category_rounded),
  ShellMenuEntry(id: 'remitos|Ventas / Facturas', title: 'Ventas / Facturas', icon: Icons.receipt_long_rounded),
  ShellMenuEntry(id: 'remitos|Presupuestos', title: 'Presupuestos', icon: Icons.request_quote_rounded),
  ShellMenuEntry(id: 'remitos|Notas de entrega', title: 'Notas de entrega', icon: Icons.local_shipping_outlined),
  ShellMenuEntry(id: 'remitos|Comprobantes internos', title: 'Comprobantes internos', icon: Icons.article_outlined),
  ShellMenuEntry(id: 'listas_precios|Comparador de listas', title: 'Comparador de listas', icon: Icons.compare_arrows_rounded),
  ShellMenuEntry(id: 'productos|Importaciones', title: 'Importaciones', icon: Icons.hub_rounded),
  ShellMenuEntry(id: 'productos|Importar Productos', title: 'Importar Productos', icon: Icons.upload_file_rounded),
  ShellMenuEntry(id: 'stock|Stock', title: 'Stock', icon: Icons.warehouse_rounded),
  ShellMenuEntry(id: 'compras|Compras', title: 'Compras', icon: Icons.shopping_cart_rounded),
  ShellMenuEntry(id: 'remitos|Remitos', title: 'Remitos', icon: Icons.description_rounded),
  ShellMenuEntry(id: 'clientes|Clientes', title: 'Clientes', icon: Icons.groups_rounded),
  ShellMenuEntry(id: 'clientes|Archivo PDF', title: 'Archivo PDF', icon: Icons.folder_shared_rounded),
  ShellMenuEntry(id: 'clientes|Cuenta corriente', title: 'Cuenta corriente', icon: Icons.account_balance_wallet_rounded),
  ShellMenuEntry(id: 'proveedores|Proveedores', title: 'Proveedores', icon: Icons.local_shipping_rounded),
  ShellMenuEntry(id: 'listas_precios|Listas de Precios', title: 'Listas de Precios', icon: Icons.sell_rounded),
  ShellMenuEntry(id: 'reportes|Reportes', title: 'Reportes', icon: Icons.bar_chart_rounded),
  ShellMenuEntry(id: 'reportes|Inteligencia Comercial', title: 'Inteligencia Comercial', icon: Icons.insights_rounded),
  ShellMenuEntry(id: 'etiquetas|Etiquetas', title: 'Etiquetas', icon: Icons.label_rounded),
  ShellMenuEntry(id: 'auditoria|Auditoría', title: 'Auditoría', icon: Icons.history_edu_rounded),
  ShellMenuEntry(id: 'dashboard|Mi perfil', title: 'Mi perfil', icon: Icons.manage_accounts_rounded),
  ShellMenuEntry(id: 'usuarios|Usuarios', title: 'Usuarios', icon: Icons.people_alt_rounded),
  ShellMenuEntry(id: 'usuarios|Permisos', title: 'Permisos', icon: Icons.admin_panel_settings_rounded),
  ShellMenuEntry(id: 'backup|Respaldo', title: 'Respaldo', icon: Icons.cloud_upload_rounded),
  ShellMenuEntry(id: 'dashboard|Manual de usuario', title: 'Manual de usuario', icon: Icons.menu_book_rounded),
  ShellMenuEntry(id: 'configuracion|Configuración', title: 'Configuración', icon: Icons.settings_rounded),
];
