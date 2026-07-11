class Usuario {
  int? id;
  String? firebaseUid;
  String nombre;
  String usuario;
  String password;
  String rol;
  bool activo;
  bool debeCambiarPassword;
  /// Solicitud de acceso: el usuario se registró solo y espera el alta del admin.
  bool pendienteAlta;
  String email;
  String foto;
  /// admin | google | email | telefono
  String origenAlta;
  DateTime? fechaCreacion;
  DateTime? ultimoAcceso;

  Usuario({
    this.id,
    this.firebaseUid,
    required this.nombre,
    required this.usuario,
    required this.password,
    this.rol = 'empleado',
    this.activo = true,
    this.debeCambiarPassword = false,
    this.pendienteAlta = false,
    this.email = '',
    this.foto = '',
    this.origenAlta = 'admin',
    DateTime? fechaCreacion,
    this.ultimoAcceso,
  }) : fechaCreacion = fechaCreacion;

  static bool _asBool(dynamic value, {required bool defaultValue}) {
    if (value == null) return defaultValue;
    if (value is bool) return value;
    if (value is num) return value != 0;
    final s = value.toString().trim().toLowerCase();
    if (s == '1' || s == 'true' || s == 'si' || s == 'sí') return true;
    if (s == '0' || s == 'false' || s == 'no') return false;
    return defaultValue;
  }

  factory Usuario.fromMap(Map<String, dynamic> map) {
    return Usuario(
      id: map['id'],
      firebaseUid: map['firebase_uid'] ?? map['firebaseUid'],
      nombre: map['nombre'] ?? '',
      usuario: map['usuario'] ?? '',
      password: map['password']?.toString() ?? '',
      rol: map['rol'] ?? 'empleado',
      activo: _asBool(map['activo'], defaultValue: true),
      debeCambiarPassword: _asBool(
        map['debe_cambiar_password'] ?? map['debeCambiarPassword'],
        defaultValue: false,
      ),
      pendienteAlta: _asBool(
        map['pendiente_alta'] ?? map['pendienteAlta'],
        defaultValue: false,
      ),
      email: map['email'] ?? '',
      foto: map['foto']?.toString() ?? '',
      origenAlta: (map['origen_alta'] ?? map['origenAlta'] ?? 'admin')
          .toString(),
      fechaCreacion: map['fechaCreacion'] != null
          ? DateTime.tryParse(map['fechaCreacion'].toString())
          : null,
      ultimoAcceso: map['ultimoAcceso'] != null
          ? DateTime.tryParse(map['ultimoAcceso'].toString())
          : null,
    );
  }

  Map<String, dynamic> toMap() {
    return {
      'id': id,
      'firebase_uid': firebaseUid,
      'nombre': nombre,
      'usuario': usuario,
      'password': password,
      'rol': rol,
      'activo': activo ? 1 : 0,
      'debe_cambiar_password': debeCambiarPassword ? 1 : 0,
      'pendiente_alta': pendienteAlta ? 1 : 0,
      'email': email,
      'foto': foto,
      'origen_alta': origenAlta,
      'fechaCreacion': fechaCreacion?.toIso8601String(),
      'ultimoAcceso': ultimoAcceso?.toIso8601String(),
    };
  }

  Map<String, dynamic> toFirestore() {
    return {
      'firebaseUid': firebaseUid,
      'nombre': nombre,
      'usuario': usuario,
      'usuarioLower': usuario.trim().toLowerCase(),
      'password': password,
      'rol': rol,
      'activo': activo,
      'debeCambiarPassword': debeCambiarPassword,
      'pendienteAlta': pendienteAlta,
      'email': email,
      'foto': foto,
      'origenAlta': origenAlta,
      'fechaCreacion': fechaCreacion?.toIso8601String(),
      'ultimoAcceso': ultimoAcceso?.toIso8601String(),
      'actualizadoEn': DateTime.now().toUtc().toIso8601String(),
    };
  }

  factory Usuario.fromFirestore(Map<String, dynamic> data, {String? docId}) {
    final map = Map<String, dynamic>.from(data);
    if (docId != null) map['firebase_uid'] = docId;
    return Usuario.fromMap(map);
  }

  Usuario copyWith({
    int? id,
    String? firebaseUid,
    String? nombre,
    String? usuario,
    String? password,
    String? rol,
    bool? activo,
    bool? debeCambiarPassword,
    bool? pendienteAlta,
    String? email,
    String? foto,
    String? origenAlta,
    DateTime? fechaCreacion,
    DateTime? ultimoAcceso,
  }) {
    return Usuario(
      id: id ?? this.id,
      firebaseUid: firebaseUid ?? this.firebaseUid,
      nombre: nombre ?? this.nombre,
      usuario: usuario ?? this.usuario,
      password: password ?? this.password,
      rol: rol ?? this.rol,
      activo: activo ?? this.activo,
      debeCambiarPassword: debeCambiarPassword ?? this.debeCambiarPassword,
      pendienteAlta: pendienteAlta ?? this.pendienteAlta,
      email: email ?? this.email,
      foto: foto ?? this.foto,
      origenAlta: origenAlta ?? this.origenAlta,
      fechaCreacion: fechaCreacion ?? this.fechaCreacion,
      ultimoAcceso: ultimoAcceso ?? this.ultimoAcceso,
    );
  }
}
