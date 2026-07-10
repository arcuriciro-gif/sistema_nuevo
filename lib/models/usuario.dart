class Usuario {
  int? id;
  String? firebaseUid;
  String nombre;
  String usuario;
  String password;
  String rol;
  bool activo;
  bool debeCambiarPassword;
  String email;
  String foto;
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
    this.email = '',
    this.foto = '',
    DateTime? fechaCreacion,
    this.ultimoAcceso,
  }) : fechaCreacion = fechaCreacion;

  factory Usuario.fromMap(Map<String, dynamic> map) {
    return Usuario(
      id: map['id'],
      firebaseUid: map['firebase_uid'] ?? map['firebaseUid'],
      nombre: map['nombre'] ?? '',
      usuario: map['usuario'] ?? '',
      password: map['password'] ?? '',
      rol: map['rol'] ?? 'empleado',
      activo: (map['activo'] ?? 1) == 1,
      debeCambiarPassword:
          (map['debe_cambiar_password'] ?? map['debeCambiarPassword'] ?? 0) ==
              1,
      email: map['email'] ?? '',
      foto: map['foto']?.toString() ?? '',
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
      'email': email,
      'foto': foto,
      'fechaCreacion': fechaCreacion?.toIso8601String(),
      'ultimoAcceso': ultimoAcceso?.toIso8601String(),
    };
  }

  Map<String, dynamic> toFirestore() {
    return {
      'firebaseUid': firebaseUid,
      'nombre': nombre,
      'usuario': usuario,
      'rol': rol,
      'activo': activo,
      'debeCambiarPassword': debeCambiarPassword,
      'email': email,
      'foto': foto,
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
    String? email,
    String? foto,
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
      email: email ?? this.email,
      foto: foto ?? this.foto,
      fechaCreacion: fechaCreacion ?? this.fechaCreacion,
      ultimoAcceso: ultimoAcceso ?? this.ultimoAcceso,
    );
  }
}
