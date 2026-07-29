/// Orden obligatorio de certificación (misión P0).
enum CertLabModule {
  productos(1, 'Productos'),
  stock(2, 'Stock'),
  ventas(3, 'Ventas'),
  compras(4, 'Compras'),
  remitos(5, 'Remitos'),
  clientes(6, 'Clientes'),
  proveedores(7, 'Proveedores'),
  cuentaCorriente(8, 'Cuenta Corriente'),
  configuracion(9, 'Configuración');

  const CertLabModule(this.order, this.title);
  final int order;
  final String title;
}

enum CertLabModuleStatus {
  notStarted,
  inProgress,
  certified,
  revoked,
}

/// Registro de certificación por módulo.
///
/// Un módulo solo es [CertLabModuleStatus.certified] tras N corridas
/// consecutivas verdes (default 20). Un rojo revoca automáticamente.
class CertLabRegistry {
  CertLabRegistry({this.requiredConsecutive = 20});

  final int requiredConsecutive;
  final Map<CertLabModule, CertLabModuleStatus> status = {
    for (final m in CertLabModule.values) m: CertLabModuleStatus.notStarted,
  };
  final Map<CertLabModule, int> consecutiveGreen = {
    for (final m in CertLabModule.values) m: 0,
  };
  final Map<CertLabModule, String?> lastFailure = {};

  /// Módulo activo: el primero no certificado en orden.
  CertLabModule get current {
    final sorted = CertLabModule.values.toList()
      ..sort((a, b) => a.order.compareTo(b.order));
    for (final m in sorted) {
      if (status[m] != CertLabModuleStatus.certified) return m;
    }
    return CertLabModule.configuracion;
  }

  bool get allCertified =>
      CertLabModule.values.every((m) => status[m] == CertLabModuleStatus.certified);

  void recordRun(CertLabModule module, {required bool ok, String? failure}) {
    if (ok) {
      consecutiveGreen[module] = (consecutiveGreen[module] ?? 0) + 1;
      status[module] = CertLabModuleStatus.inProgress;
      lastFailure[module] = null;
      if ((consecutiveGreen[module] ?? 0) >= requiredConsecutive) {
        status[module] = CertLabModuleStatus.certified;
      }
    } else {
      consecutiveGreen[module] = 0;
      status[module] = CertLabModuleStatus.revoked;
      lastFailure[module] = failure;
    }
  }

  Map<String, dynamic> toJson() => {
        'requiredConsecutive': requiredConsecutive,
        'allCertified': allCertified,
        'current': current.name,
        'modules': {
          for (final m in CertLabModule.values)
            m.name: {
              'order': m.order,
              'title': m.title,
              'status': status[m]!.name,
              'consecutiveGreen': consecutiveGreen[m] ?? 0,
              'lastFailure': lastFailure[m],
            },
        },
        'verdict': allCertified
            ? 'ERP_CERTIFICADO'
            : 'ERP_NO_CERTIFICADO — módulo actual: ${current.title}',
      };
}
