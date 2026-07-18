class Cliente {
  int? id;

  String syncId;
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
  String foto;
  double descuento;
  double saldo;
  double limiteCuenta;

  Cliente({
    this.id,
    this.syncId = '',
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
    this.foto = '',
    this.descuento = 0.0,
    this.saldo = 0.0,
    this.limiteCuenta = 0.0,
  });

  Map<String, dynamic> toMap() {
    return {
      "id": id,
      "syncId": syncId,
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
      "foto": foto,
      "descuento": descuento,
      "saldo": saldo,
      "limiteCuenta": limiteCuenta,
    };
  }

  Map<String, dynamic> toFirestore() {
    final data = Map<String, dynamic>.from(toMap()..remove('id'));
    // Solo URLs https en la nube. Si aún no subió, NO mandar foto vacía
    // (merge:true borraría la foto buena del otro dispositivo).
    final f = foto.trim();
    if (f.startsWith('http://') || f.startsWith('https://')) {
      data['foto'] = f;
    } else {
      data.remove('foto');
    }
    data['actualizadoEn'] = DateTime.now().toUtc().toIso8601String();
    return data;
  }

  factory Cliente.fromMap(Map<String, dynamic> map) {
    return Cliente(
      id: map["id"],
      syncId: map["syncId"]?.toString() ?? '',
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
      foto: map["foto"]?.toString() ?? "",
      descuento: (map["descuento"] ?? 0).toDouble(),
      saldo: (map["saldo"] ?? 0).toDouble(),
      limiteCuenta: (map["limiteCuenta"] ?? 0).toDouble(),
    );
  }

  String get nombreCompleto =>
      apellido.isEmpty ? nombre : '$nombre $apellido';

  Cliente copyWith({
    int? id,
    String? syncId,
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
    String? foto,
    double? descuento,
    double? saldo,
    double? limiteCuenta,
  }) {
    return Cliente(
      id: id ?? this.id,
      syncId: syncId ?? this.syncId,
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
      foto: foto ?? this.foto,
      descuento: descuento ?? this.descuento,
      saldo: saldo ?? this.saldo,
      limiteCuenta: limiteCuenta ?? this.limiteCuenta,
    );
  }
}
