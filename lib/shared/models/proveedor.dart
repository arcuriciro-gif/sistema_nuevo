class Proveedor {
  int? id;

  String syncId;
  String nombre;
  String contacto;
  String telefono;
  String whatsapp;
  String email;
  String web;
  String cuit;
  String condicionesComerciales;
  String tiempoEntrega;
  String observaciones;

  DateTime? fechaCreacion;
  bool activo;
  String? actualizadoEn;

  Proveedor({
    this.id,
    this.syncId = '',
    required this.nombre,
    this.contacto = '',
    required this.telefono,
    this.whatsapp = '',
    required this.email,
    this.web = '',
    this.cuit = '',
    this.condicionesComerciales = '',
    this.tiempoEntrega = '',
    required this.observaciones,
    this.fechaCreacion,
    this.activo = true,
    this.actualizadoEn,
  });

  Map<String, dynamic> toMap() {
    return {
      'id': id,
      'syncId': syncId,
      'nombre': nombre,
      'contacto': contacto,
      'telefono': telefono,
      'whatsapp': whatsapp,
      'email': email,
      'web': web,
      'cuit': cuit,
      'condicionesComerciales': condicionesComerciales,
      'tiempoEntrega': tiempoEntrega,
      'observaciones': observaciones,
      'fechaCreacion': fechaCreacion?.toIso8601String(),
      'activo': activo ? 1 : 0,
      'actualizadoEn': actualizadoEn ?? '',
    };
  }

  Map<String, dynamic> toFirestore() {
    final data = Map<String, dynamic>.from(toMap()..remove('id'));
    data['actualizadoEn'] =
        (actualizadoEn != null && actualizadoEn!.isNotEmpty)
            ? actualizadoEn
            : DateTime.now().toUtc().toIso8601String();
    return data;
  }

  factory Proveedor.fromMap(Map<String, dynamic> map) {
    return Proveedor(
      id: map['id'],
      syncId: map['syncId']?.toString() ?? '',
      nombre: map['nombre'] ?? '',
      contacto: map['contacto'] ?? '',
      telefono: map['telefono'] ?? '',
      whatsapp: map['whatsapp'] ?? '',
      email: map['email'] ?? '',
      web: map['web'] ?? '',
      cuit: map['cuit'] ?? '',
      condicionesComerciales: map['condicionesComerciales'] ?? '',
      tiempoEntrega: map['tiempoEntrega'] ?? '',
      observaciones: map['observaciones'] ?? '',
      fechaCreacion: map['fechaCreacion'] != null
          ? DateTime.tryParse(map['fechaCreacion'].toString())
          : null,
      activo: (map['activo'] ?? 1) == 1,
      actualizadoEn: map['actualizadoEn']?.toString(),
    );
  }

  Proveedor copyWith({
    int? id,
    String? syncId,
    String? nombre,
    String? contacto,
    String? telefono,
    String? whatsapp,
    String? email,
    String? web,
    String? cuit,
    String? condicionesComerciales,
    String? tiempoEntrega,
    String? observaciones,
    DateTime? fechaCreacion,
    bool? activo,
    String? actualizadoEn,
  }) {
    return Proveedor(
      id: id ?? this.id,
      syncId: syncId ?? this.syncId,
      nombre: nombre ?? this.nombre,
      contacto: contacto ?? this.contacto,
      telefono: telefono ?? this.telefono,
      whatsapp: whatsapp ?? this.whatsapp,
      email: email ?? this.email,
      web: web ?? this.web,
      cuit: cuit ?? this.cuit,
      condicionesComerciales:
          condicionesComerciales ?? this.condicionesComerciales,
      tiempoEntrega: tiempoEntrega ?? this.tiempoEntrega,
      observaciones: observaciones ?? this.observaciones,
      fechaCreacion: fechaCreacion ?? this.fechaCreacion,
      activo: activo ?? this.activo,
      actualizadoEn: actualizadoEn ?? this.actualizadoEn,
    );
  }
}
