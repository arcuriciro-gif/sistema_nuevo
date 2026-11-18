class Comparacion {
  int? id;

  String codigo;
  String descripcion;

  /// costoViejo y costoNuevo se almacenan en las columnas precioViejo/precioNuevo
  /// de la BD para mantener compatibilidad con versiones anteriores.
  double precioViejo;
  double precioNuevo;

  String estado;
  String marca;
  String proveedor;

  Comparacion({
    this.id,
    required this.codigo,
    required this.descripcion,
    required this.precioViejo,
    required this.precioNuevo,
    required this.estado,
    this.marca = '',
    this.proveedor = '',
  });

  Map<String, dynamic> toMap() {
    return {
      'id': id,
      'codigo': codigo,
      'descripcion': descripcion,
      'precioViejo': precioViejo,
      'precioNuevo': precioNuevo,
      'estado': estado,
      'marca': marca,
      'proveedor': proveedor,
    };
  }

  factory Comparacion.fromMap(Map<String, dynamic> map) {
    return Comparacion(
      id: map['id'],
      codigo: map['codigo'] ?? '',
      descripcion: map['descripcion'] ?? '',
      precioViejo: (map['precioViejo'] ?? 0).toDouble(),
      precioNuevo: (map['precioNuevo'] ?? 0).toDouble(),
      estado: map['estado'] ?? '',
      marca: map['marca'] ?? '',
      proveedor: map['proveedor'] ?? '',
    );
  }

  double get diferencia => precioNuevo - precioViejo;

  double get porcentaje {
    if (precioViejo == 0) {
      return 0;
    }

    return ((precioNuevo - precioViejo) / precioViejo) * 100;
  }

  bool get aumento => precioNuevo > precioViejo;

  bool get baja => precioNuevo < precioViejo;

  bool get igual => precioNuevo == precioViejo;
}