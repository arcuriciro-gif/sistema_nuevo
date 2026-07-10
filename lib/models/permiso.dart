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
    return Permiso(
      id: map['id'],
      rol: map['rol'] ?? '',
      modulo: map['modulo'] ?? '',
      puedeVer: (map['puede_ver'] ?? 0) == 1,
      puedeCrear: (map['puede_crear'] ?? 0) == 1,
      puedeEditar: (map['puede_editar'] ?? 0) == 1,
      puedeEliminar: (map['puede_eliminar'] ?? 0) == 1,
    );
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
