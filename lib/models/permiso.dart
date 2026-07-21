class Permiso {
  int? id;
  String rol;
  String modulo;
  bool puedeVer;
  bool puedeCrear;
  bool puedeEditar;
  bool puedeEliminar;

  Permiso({
    this.id,
    required this.rol,
    required this.modulo,
    this.puedeVer = true,
    this.puedeCrear = false,
    this.puedeEditar = false,
    this.puedeEliminar = false,
  });

  factory Permiso.fromMap(Map<String, dynamic> map) {
    bool asBool(dynamic v, {bool def = false}) {
      if (v == null) return def;
      if (v is bool) return v;
      if (v is num) return v != 0;
      final t = v.toString().trim().toLowerCase();
      return t == '1' || t == 'true' || t == 'si' || t == 'yes';
    }

    return Permiso(
      id: map['id'],
      rol: map['rol'] ?? '',
      modulo: map['modulo'] ?? '',
      puedeVer: asBool(map['puede_ver'] ?? map['puedeVer'], def: true),
      puedeCrear: asBool(map['puede_crear'] ?? map['puedeCrear']),
      puedeEditar: asBool(map['puede_editar'] ?? map['puedeEditar']),
      puedeEliminar: asBool(map['puede_eliminar'] ?? map['puedeEliminar']),
    );
  }

  Map<String, dynamic> toFirestore() {
    return {
      'rol': rol,
      'modulo': modulo,
      'puedeVer': puedeVer,
      'puedeCrear': puedeCrear,
      'puedeEditar': puedeEditar,
      'puedeEliminar': puedeEliminar,
    };
  }

  Map<String, dynamic> toMap() {
    return {
      'id': id,
      'rol': rol,
      'modulo': modulo,
      'puede_ver': puedeVer ? 1 : 0,
      'puede_crear': puedeCrear ? 1 : 0,
      'puede_editar': puedeEditar ? 1 : 0,
      'puede_eliminar': puedeEliminar ? 1 : 0,
    };
  }
}
