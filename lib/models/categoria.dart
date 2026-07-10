class Categoria {
  int? id;
  String nombre;
  String descripcion;
  int activa;

  Categoria({
    this.id,
    required this.nombre,
    this.descripcion = '',
    this.activa = 1,
  });

  Map<String, dynamic> toMap() {
    return {
      'id': id,
      'nombre': nombre,
      'descripcion': descripcion,
      'activa': activa,
    };
  }

  factory Categoria.fromMap(Map<String, dynamic> map) {
    return Categoria(
      id: map['id'],
      nombre: map['nombre'] ?? '',
      descripcion: map['descripcion'] ?? '',
      activa: map['activa'] ?? 1,
    );
  }

  Categoria copyWith({
    int? id,
    String? nombre,
    String? descripcion,
    int? activa,
  }) {
    return Categoria(
      id: id ?? this.id,
      nombre: nombre ?? this.nombre,
      descripcion: descripcion ?? this.descripcion,
      activa: activa ?? this.activa,
    );
  }
}
