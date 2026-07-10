class Cliente {
  int? id;

  String nombre;
  String apellido;
  String telefono;
  String whatsapp;
  String email;
  String direccion;
  String localidad;
  String provincia;
  String cuit;
  String condicionIva;
  String observaciones;
  double descuento;
  double saldo;
  double limiteCuenta;

  Cliente({
    this.id,
    required this.nombre,
    this.apellido = '',
    required this.telefono,
    this.whatsapp = '',
    this.email = '',
    required this.direccion,
    this.localidad = '',
    this.provincia = '',
    this.cuit = '',
    this.condicionIva = '',
    required this.observaciones,
    this.descuento = 0.0,
    this.saldo = 0.0,
    this.limiteCuenta = 0.0,
  });

  Map<String, dynamic> toMap() {
    return {
      "id": id,
      "nombre": nombre,
      "apellido": apellido,
      "telefono": telefono,
      "whatsapp": whatsapp,
      "email": email,
      "direccion": direccion,
      "localidad": localidad,
      "provincia": provincia,
      "cuit": cuit,
      "condicionIva": condicionIva,
      "observaciones": observaciones,
      "descuento": descuento,
      "saldo": saldo,
      "limiteCuenta": limiteCuenta,
    };
  }

  factory Cliente.fromMap(Map<String, dynamic> map) {
    return Cliente(
      id: map["id"],
      nombre: map["nombre"] ?? "",
      apellido: map["apellido"] ?? "",
      telefono: map["telefono"] ?? "",
      whatsapp: map["whatsapp"] ?? "",
      email: map["email"] ?? "",
      direccion: map["direccion"] ?? "",
      localidad: map["localidad"] ?? "",
      provincia: map["provincia"] ?? "",
      cuit: map["cuit"] ?? "",
      condicionIva: map["condicionIva"] ?? "",
      observaciones: map["observaciones"] ?? "",
      descuento: (map["descuento"] ?? 0).toDouble(),
      saldo: (map["saldo"] ?? 0).toDouble(),
      limiteCuenta: (map["limiteCuenta"] ?? 0).toDouble(),
    );
  }

  String get nombreCompleto =>
      apellido.isEmpty ? nombre : '$nombre $apellido';

  Cliente copyWith({
    int? id,
    String? nombre,
    String? apellido,
    String? telefono,
    String? whatsapp,
    String? email,
    String? direccion,
    String? localidad,
    String? provincia,
    String? cuit,
    String? condicionIva,
    String? observaciones,
    double? descuento,
    double? saldo,
    double? limiteCuenta,
  }) {
    return Cliente(
      id: id ?? this.id,
      nombre: nombre ?? this.nombre,
      apellido: apellido ?? this.apellido,
      telefono: telefono ?? this.telefono,
      whatsapp: whatsapp ?? this.whatsapp,
      email: email ?? this.email,
      direccion: direccion ?? this.direccion,
      localidad: localidad ?? this.localidad,
      provincia: provincia ?? this.provincia,
      cuit: cuit ?? this.cuit,
      condicionIva: condicionIva ?? this.condicionIva,
      observaciones: observaciones ?? this.observaciones,
      descuento: descuento ?? this.descuento,
      saldo: saldo ?? this.saldo,
      limiteCuenta: limiteCuenta ?? this.limiteCuenta,
    );
  }
}
