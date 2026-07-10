class Proveedor {
  int? id;

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

  Proveedor({
    this.id,
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
  });

  Map<String, dynamic> toMap() {
    return {
      'id': id,
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
    };
  }

  factory Proveedor.fromMap(Map<String, dynamic> map) {
    return Proveedor(
      id: map['id'],
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
          ? DateTime.parse(map['fechaCreacion'])
          : null,
      activo: (map['activo'] ?? 1) == 1,
    );
  }

  Proveedor copyWith({
    int? id,
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
  }) {
    return Proveedor(
      id: id ?? this.id,
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
    );
  }
}
