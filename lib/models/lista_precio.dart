class ListaPrecio {
  int? id;
  String nombre;
  double porcentaje;
  bool activa;
  int orden;
  String color;
  int prioridad;

  ListaPrecio({
    this.id,
    required this.nombre,
    required this.porcentaje,
    this.activa = true,
    this.orden = 0,
    this.color = '',
    this.prioridad = 0,
  });

  double calcularPrecio(double costo) => costo * (1 + porcentaje / 100);

  Map<String, dynamic> toMap() {
    return {
      'id': id,
      'nombre': nombre,
      'porcentaje': porcentaje,
      'activa': activa ? 1 : 0,
      'orden': orden,
      'color': color,
      'prioridad': prioridad,
    };
  }

  factory ListaPrecio.fromMap(Map<String, dynamic> map) {
    return ListaPrecio(
      id: map['id'],
      nombre: map['nombre'] ?? '',
      porcentaje: (map['porcentaje'] ?? 0).toDouble(),
      activa: (map['activa'] ?? 1) == 1,
      orden: map['orden'] ?? 0,
      color: map['color'] ?? '',
      prioridad: map['prioridad'] ?? 0,
    );
  }

  ListaPrecio copyWith({
    int? id,
    String? nombre,
    double? porcentaje,
    bool? activa,
    int? orden,
    String? color,
    int? prioridad,
  }) {
    return ListaPrecio(
      id: id ?? this.id,
      nombre: nombre ?? this.nombre,
      porcentaje: porcentaje ?? this.porcentaje,
      activa: activa ?? this.activa,
      orden: orden ?? this.orden,
      color: color ?? this.color,
      prioridad: prioridad ?? this.prioridad,
    );
  }
}
