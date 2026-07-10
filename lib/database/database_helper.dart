import 'package:flutter/foundation.dart';
import 'package:path/path.dart';
import 'package:sqflite/sqflite.dart';

class DatabaseHelper {
  DatabaseHelper._();

  static final DatabaseHelper instance = DatabaseHelper._();

  Database? _database;

  Future<Database> get database async {
    _database ??= await _initDatabase();
    return _database!;
  }

  Future<Database> _initDatabase() async {
    final dbPath = await getDatabasesPath();
    final path = join(dbPath, 'eltata.db');

    debugPrint('Base de datos: $path');

    return openDatabase(
      path,
      version: 15,
      onCreate: _onCreate,
      onUpgrade: _onUpgrade,
    );
  }

  Future<void> _onCreate(Database db, int version) async {
    await db.execute('''
CREATE TABLE productos(
  id INTEGER PRIMARY KEY AUTOINCREMENT,
  codigo TEXT NOT NULL,
  codigo_barras TEXT DEFAULT '',
  descripcion TEXT NOT NULL,
  marca TEXT,
  categoria TEXT,
  subcategoria TEXT DEFAULT '',
  modelo TEXT DEFAULT '',
  color_producto TEXT DEFAULT '',
  talle TEXT DEFAULT '',
  unidad_venta TEXT DEFAULT 'UN',
  proveedor TEXT,
  ubicacion TEXT,
  stock INTEGER DEFAULT 0,
  stock_minimo INTEGER DEFAULT 0,
  costo REAL DEFAULT 0,
  precio REAL DEFAULT 0,
  precio2 REAL DEFAULT 0,
  precio3 REAL DEFAULT 0,
  porcentaje_ganancia REAL DEFAULT 0,
  observaciones TEXT,
  notas_internas TEXT DEFAULT '',
  foto TEXT,
  fotos TEXT DEFAULT '[]',
  precios_listas TEXT DEFAULT '{}',
  precios_bloqueados TEXT DEFAULT '[]'
)
''');

    await db.execute('''
CREATE TABLE proveedores(
  id INTEGER PRIMARY KEY AUTOINCREMENT,
  nombre TEXT NOT NULL,
  telefono TEXT,
  email TEXT,
  observaciones TEXT,
  fechaCreacion TEXT,
  activo INTEGER DEFAULT 1,
  contacto TEXT DEFAULT '',
  cuit TEXT DEFAULT '',
  whatsapp TEXT DEFAULT '',
  web TEXT DEFAULT '',
  condicionesComerciales TEXT DEFAULT '',
  tiempoEntrega TEXT DEFAULT ''
)
''');

    await db.execute('''
CREATE TABLE clientes(
  id INTEGER PRIMARY KEY AUTOINCREMENT,
  nombre TEXT NOT NULL,
  telefono TEXT,
  email TEXT,
  direccion TEXT,
  observaciones TEXT,
  fechaCreacion TEXT,
  descuento REAL DEFAULT 0,
  activo INTEGER DEFAULT 1,
  apellido TEXT DEFAULT '',
  cuit TEXT DEFAULT '',
  condicionIva TEXT DEFAULT '',
  localidad TEXT DEFAULT '',
  provincia TEXT DEFAULT '',
  whatsapp TEXT DEFAULT '',
  saldo REAL DEFAULT 0,
  limiteCuenta REAL DEFAULT 0
)
''');

    await db.execute('''
CREATE TABLE remitos(
  id INTEGER PRIMARY KEY AUTOINCREMENT,
  numero TEXT NOT NULL,
  clienteId INTEGER,
  fecha TEXT,
  total REAL DEFAULT 0,
  descuento REAL DEFAULT 0,
  estado TEXT,
  estadoPago TEXT DEFAULT 'pendiente',
  observaciones TEXT,
  fechaCreacion TEXT,
  FOREIGN KEY(clienteId) REFERENCES clientes(id)
)
''');

    await db.execute('''
CREATE TABLE remito_items(
  id INTEGER PRIMARY KEY AUTOINCREMENT,
  remitoId INTEGER,
  productoId INTEGER,
  cantidad INTEGER,
  precio REAL,
  subtotal REAL,
  FOREIGN KEY(remitoId) REFERENCES remitos(id),
  FOREIGN KEY(productoId) REFERENCES productos(id)
)
''');

    await db.execute('''
CREATE TABLE comparacion(
  id INTEGER PRIMARY KEY AUTOINCREMENT,
  codigo TEXT,
  descripcion TEXT,
  precioViejo REAL,
  precioNuevo REAL,
  estado TEXT,
  marca TEXT,
  proveedor TEXT DEFAULT ''
)
''');

    await _crearTablaMovimientosStock(db);
    await _crearTablaUsuarios(db);
    await _crearTablaAuditLog(db);
    await _crearTablasCompras(db);
    await _crearTablaListasPrecios(db);
    await _crearTablaHistorialPrecios(db);
    await _crearTablaPermisos(db);
    await _crearTablaVentas(db);
    await _crearTablaCategorias(db);
    await _crearTablaVentasItems(db);
    await _crearIndices(db);
  }

  Future<void> _crearTablasCompras(Database db) async {
    await db.execute('''
CREATE TABLE IF NOT EXISTS compras(
  id INTEGER PRIMARY KEY AUTOINCREMENT,
  proveedorId INTEGER,
  proveedorNombre TEXT,
  numero TEXT,
  factura TEXT DEFAULT '',
  fecha TEXT,
  total REAL DEFAULT 0,
  descuento REAL DEFAULT 0,
  iva REAL DEFAULT 0,
  observaciones TEXT,
  fechaCreacion TEXT,
  estado TEXT DEFAULT 'confirmada',
  FOREIGN KEY(proveedorId) REFERENCES proveedores(id)
)
''');

    await db.execute('''
CREATE TABLE IF NOT EXISTS compra_items(
  id INTEGER PRIMARY KEY AUTOINCREMENT,
  compraId INTEGER NOT NULL,
  productoId INTEGER NOT NULL,
  productoDescripcion TEXT,
  cantidad INTEGER DEFAULT 0,
  costo REAL DEFAULT 0,
  subtotal REAL DEFAULT 0,
  FOREIGN KEY(compraId) REFERENCES compras(id),
  FOREIGN KEY(productoId) REFERENCES productos(id)
)
''');
  }

  Future<void> _crearTablaListasPrecios(Database db) async {
    await db.execute('''
CREATE TABLE IF NOT EXISTS listas_precios(
  id INTEGER PRIMARY KEY AUTOINCREMENT,
  nombre TEXT NOT NULL,
  porcentaje REAL DEFAULT 0,
  activa INTEGER DEFAULT 1,
  orden INTEGER DEFAULT 0,
  color TEXT DEFAULT '',
  prioridad INTEGER DEFAULT 0
)
''');

    final count = Sqflite.firstIntValue(
      await db.rawQuery('SELECT COUNT(*) FROM listas_precios'),
    )!;
    if (count == 0) {
      await db.insert('listas_precios', {
        'nombre': 'Mayorista',
        'porcentaje': 30.0,
        'activa': 1,
        'orden': 0,
        'color': '',
        'prioridad': 0,
      });
      await db.insert('listas_precios', {
        'nombre': 'Minorista',
        'porcentaje': 50.0,
        'activa': 1,
        'orden': 1,
        'color': '',
        'prioridad': 1,
      });
      await db.insert('listas_precios', {
        'nombre': 'Taller',
        'porcentaje': 40.0,
        'activa': 1,
        'orden': 2,
        'color': '',
        'prioridad': 2,
      });
    }
  }

  Future<void> _crearTablaHistorialPrecios(Database db) async {
    await db.execute('''
CREATE TABLE IF NOT EXISTS historial_precios(
  id INTEGER PRIMARY KEY AUTOINCREMENT,
  productoId INTEGER NOT NULL,
  fecha TEXT NOT NULL,
  usuario TEXT,
  costoAnterior REAL DEFAULT 0,
  costoNuevo REAL DEFAULT 0,
  precioAnterior REAL DEFAULT 0,
  precioNuevo REAL DEFAULT 0,
  porcentaje REAL DEFAULT 0,
  listaModificada TEXT,
  motivo TEXT,
  FOREIGN KEY(productoId) REFERENCES productos(id)
)
''');
  }

  Future<void> _agregarColumnasClienteExtendido(Database db) async {
    await _agregarColumnas(db, 'clientes', {
      'apellido': "TEXT DEFAULT ''",
      'cuit': "TEXT DEFAULT ''",
      'condicionIva': "TEXT DEFAULT ''",
      'localidad': "TEXT DEFAULT ''",
      'provincia': "TEXT DEFAULT ''",
      'whatsapp': "TEXT DEFAULT ''",
      'saldo': 'REAL DEFAULT 0',
      'limiteCuenta': 'REAL DEFAULT 0',
    });
  }

  Future<void> _agregarColumnasProveedorExtendido(Database db) async {
    await _agregarColumnas(db, 'proveedores', {
      'contacto': "TEXT DEFAULT ''",
      'cuit': "TEXT DEFAULT ''",
      'whatsapp': "TEXT DEFAULT ''",
      'web': "TEXT DEFAULT ''",
      'condicionesComerciales': "TEXT DEFAULT ''",
      'tiempoEntrega': "TEXT DEFAULT ''",
    });
  }

  Future<void> _crearTablaUsuarios(Database db) async {
    await db.execute('''
CREATE TABLE IF NOT EXISTS usuarios(
  id INTEGER PRIMARY KEY AUTOINCREMENT,
  firebase_uid TEXT,
  nombre TEXT NOT NULL,
  usuario TEXT NOT NULL UNIQUE,
  password TEXT NOT NULL,
  rol TEXT DEFAULT 'empleado',
  activo INTEGER DEFAULT 1,
  debe_cambiar_password INTEGER DEFAULT 0,
  email TEXT DEFAULT '',
  fechaCreacion TEXT,
  ultimoAcceso TEXT
)
''');

    final count = Sqflite.firstIntValue(
      await db.rawQuery('SELECT COUNT(*) FROM usuarios'),
    )!;
    if (count == 0) {
      final ahora = DateTime.now().toIso8601String();
      await db.insert('usuarios', {
        'nombre': 'Administrador',
        'usuario': 'admin',
        'password': '8c6976e5b5410415bde908bd4dee15dfb167a9c873fc4bb8a81f6f2ab448a918',
        'rol': 'admin',
        'activo': 1,
        'debe_cambiar_password': 1,
        'email': 'admin@tatastock.app',
        'fechaCreacion': ahora,
        'ultimoAcceso': ahora,
      });
    }
  }

  Future<void> _crearTablaAuditLog(Database db) async {
    await db.execute('''
CREATE TABLE IF NOT EXISTS audit_log(
  id INTEGER PRIMARY KEY AUTOINCREMENT,
  usuario TEXT NOT NULL,
  accion TEXT NOT NULL,
  detalle TEXT,
  tablaAfectada TEXT,
  valorAnterior TEXT,
  valorNuevo TEXT,
  fecha TEXT NOT NULL
)
''');
  }

  Future<void> _crearTablaMovimientosStock(Database db) async {
    await db.execute('''
CREATE TABLE IF NOT EXISTS movimientos_stock(
  id INTEGER PRIMARY KEY AUTOINCREMENT,
  productoId INTEGER NOT NULL,
  tipo TEXT NOT NULL,
  cantidad INTEGER NOT NULL,
  fecha TEXT NOT NULL,
  remitoId TEXT,
  motivo TEXT,
  usuario TEXT,
  stockAnterior INTEGER DEFAULT 0,
  stockNuevo INTEGER DEFAULT 0,
  FOREIGN KEY(productoId) REFERENCES productos(id)
)
''');
  }

  Future<void> _crearTablaPermisos(Database db) async {
    await db.execute('''
CREATE TABLE IF NOT EXISTS permisos(
  id INTEGER PRIMARY KEY AUTOINCREMENT,
  rol TEXT NOT NULL,
  modulo TEXT NOT NULL,
  puede_ver INTEGER DEFAULT 1,
  puede_crear INTEGER DEFAULT 0,
  puede_editar INTEGER DEFAULT 0,
  puede_eliminar INTEGER DEFAULT 0,
  UNIQUE(rol, modulo)
)
''');

    final roles = ['admin', 'supervisor', 'empleado', 'solo_lectura'];
    final modulos = [
      'dashboard',
      'productos',
      'clientes',
      'proveedores',
      'remitos',
      'compras',
      'listas_precios',
      'reportes',
      'etiquetas',
      'stock',
      'auditoria',
      'backup',
      'configuracion',
      'usuarios',
    ];

    for (final rol in roles) {
      for (final modulo in modulos) {
        int verVal = 1;
        int crearVal = 0;
        int editarVal = 0;
        int eliminarVal = 0;

        if (rol == 'admin') {
          crearVal = 1;
          editarVal = 1;
          eliminarVal = 1;
        } else if (rol == 'supervisor') {
          crearVal = [
            'remitos',
            'compras',
            'clientes',
            'proveedores',
            'productos',
          ].contains(modulo)
              ? 1
              : 0;
          editarVal = [
            'remitos',
            'compras',
            'clientes',
            'proveedores',
            'productos',
            'stock',
            'listas_precios',
          ].contains(modulo)
              ? 1
              : 0;
          if (['auditoria', 'backup', 'configuracion', 'usuarios']
              .contains(modulo)) {
            verVal = 0;
          }
        } else if (rol == 'empleado') {
          crearVal = ['remitos'].contains(modulo) ? 1 : 0;
          if ([
            'auditoria',
            'backup',
            'configuracion',
            'usuarios',
            'compras',
            'listas_precios',
          ].contains(modulo)) {
            verVal = 0;
          }
        } else {
          if (['auditoria', 'backup', 'configuracion', 'usuarios']
              .contains(modulo)) {
            verVal = 0;
          }
        }

        try {
          await db.insert('permisos', {
            'rol': rol,
            'modulo': modulo,
            'puede_ver': verVal,
            'puede_crear': crearVal,
            'puede_editar': editarVal,
            'puede_eliminar': eliminarVal,
          });
        } catch (_) {}
      }
    }
  }

  Future<void> _crearTablaVentas(Database db) async {
    await db.execute('''
CREATE TABLE IF NOT EXISTS ventas(
  id INTEGER PRIMARY KEY AUTOINCREMENT,
  tipo TEXT NOT NULL DEFAULT 'remito',
  numero TEXT NOT NULL,
  clienteId INTEGER,
  fecha TEXT,
  total REAL DEFAULT 0,
  descuento REAL DEFAULT 0,
  iva REAL DEFAULT 0,
  estado TEXT DEFAULT 'confirmada',
  estadoPago TEXT DEFAULT 'pendiente',
  observaciones TEXT,
  fechaCreacion TEXT,
  usuarioId INTEGER,
  FOREIGN KEY(clienteId) REFERENCES clientes(id)
)
''');
  }

  Future<void> _crearTablaCategorias(Database db) async {
    await db.execute('''
CREATE TABLE IF NOT EXISTS categorias(
  id INTEGER PRIMARY KEY AUTOINCREMENT,
  nombre TEXT NOT NULL UNIQUE,
  descripcion TEXT DEFAULT '',
  activa INTEGER DEFAULT 1
)
''');
  }

  Future<void> _crearTablaVentasItems(Database db) async {
    await db.execute('''
CREATE TABLE IF NOT EXISTS ventas_items(
  id INTEGER PRIMARY KEY AUTOINCREMENT,
  ventaId INTEGER NOT NULL,
  productoId INTEGER NOT NULL,
  productoDescripcion TEXT,
  cantidad INTEGER DEFAULT 0,
  precio REAL DEFAULT 0,
  subtotal REAL DEFAULT 0,
  FOREIGN KEY(ventaId) REFERENCES ventas(id),
  FOREIGN KEY(productoId) REFERENCES productos(id)
)
''');
  }

  Future<void> _crearIndices(Database db) async {
    const indices = [
      'CREATE INDEX IF NOT EXISTS idx_productos_codigo ON productos(codigo)',
      'CREATE INDEX IF NOT EXISTS idx_productos_descripcion ON productos(descripcion)',
      'CREATE INDEX IF NOT EXISTS idx_productos_marca ON productos(marca)',
      'CREATE INDEX IF NOT EXISTS idx_productos_categoria ON productos(categoria)',
      'CREATE INDEX IF NOT EXISTS idx_clientes_nombre ON clientes(nombre)',
      'CREATE INDEX IF NOT EXISTS idx_clientes_cuit ON clientes(cuit)',
      'CREATE INDEX IF NOT EXISTS idx_proveedores_nombre ON proveedores(nombre)',
      'CREATE INDEX IF NOT EXISTS idx_remitos_numero ON remitos(numero)',
      'CREATE INDEX IF NOT EXISTS idx_remitos_clienteId ON remitos(clienteId)',
      'CREATE INDEX IF NOT EXISTS idx_remitos_fecha ON remitos(fecha)',
      'CREATE INDEX IF NOT EXISTS idx_compras_fecha ON compras(fecha)',
      'CREATE INDEX IF NOT EXISTS idx_movimientos_productoId ON movimientos_stock(productoId)',
      'CREATE INDEX IF NOT EXISTS idx_movimientos_fecha ON movimientos_stock(fecha)',
      'CREATE INDEX IF NOT EXISTS idx_audit_log_fecha ON audit_log(fecha)',
      'CREATE INDEX IF NOT EXISTS idx_audit_log_usuario ON audit_log(usuario)',
      'CREATE INDEX IF NOT EXISTS idx_historial_precios_productoId ON historial_precios(productoId)',
      'CREATE INDEX IF NOT EXISTS idx_ventas_fecha ON ventas(fecha)',
      'CREATE INDEX IF NOT EXISTS idx_ventas_clienteId ON ventas(clienteId)',
      'CREATE INDEX IF NOT EXISTS idx_ventas_tipo ON ventas(tipo)',
    ];

    for (final sql in indices) {
      await db.execute(sql);
    }
  }

  Future<void> _agregarColumnas(
    Database db,
    String tabla,
    Map<String, String> columnas,
  ) async {
    for (final entry in columnas.entries) {
      try {
        await db.execute(
          'ALTER TABLE $tabla ADD COLUMN ${entry.key} ${entry.value}',
        );
      } catch (_) {
        // column already exists
      }
    }
  }

  Future<void> _onUpgrade(Database db, int oldVersion, int newVersion) async {
    if (oldVersion < 2) {
      await db.execute(
        "ALTER TABLE comparacion ADD COLUMN marca TEXT DEFAULT ''",
      );
    }

    if (oldVersion < 3) {
      await _crearTablaMovimientosStock(db);
    }

    if (oldVersion < 4) {
      await db.execute(
        'ALTER TABLE remitos ADD COLUMN descuento REAL DEFAULT 0',
      );
      await db.execute(
        "ALTER TABLE remitos ADD COLUMN estadoPago TEXT DEFAULT 'pendiente'",
      );
    }

    if (oldVersion < 5) {
      await db.execute(
        'ALTER TABLE productos ADD COLUMN precio2 REAL DEFAULT 0',
      );
      await db.execute(
        'ALTER TABLE productos ADD COLUMN precio3 REAL DEFAULT 0',
      );
      await db.execute(
        'ALTER TABLE clientes ADD COLUMN descuento REAL DEFAULT 0',
      );
    }

    if (oldVersion < 6) {
      await _crearTablaUsuarios(db);
      await _crearTablaAuditLog(db);
    }

    if (oldVersion < 7) {
      await _crearTablasCompras(db);
    }

    if (oldVersion < 8) {
      await _crearTablaListasPrecios(db);
    }

    if (oldVersion < 9) {
      await _crearTablaHistorialPrecios(db);
    }

    if (oldVersion < 10) {
      await _agregarColumnasClienteExtendido(db);
      await _agregarColumnasProveedorExtendido(db);
    }

    if (oldVersion < 11) {
      await _agregarColumnas(db, 'usuarios', {
        'fechaCreacion': 'TEXT',
        'ultimoAcceso': 'TEXT',
      });
      await _agregarColumnas(db, 'audit_log', {
        'tablaAfectada': 'TEXT',
        'valorAnterior': 'TEXT',
        'valorNuevo': 'TEXT',
      });
      await _agregarColumnas(db, 'movimientos_stock', {
        'usuario': 'TEXT',
        'stockAnterior': 'INTEGER DEFAULT 0',
        'stockNuevo': 'INTEGER DEFAULT 0',
      });
      await _agregarColumnas(db, 'historial_precios', {
        'precioAnterior': 'REAL DEFAULT 0',
        'precioNuevo': 'REAL DEFAULT 0',
        'porcentaje': 'REAL DEFAULT 0',
        'listaModificada': 'TEXT',
      });
      await _agregarColumnas(db, 'listas_precios', {
        'color': "TEXT DEFAULT ''",
        'prioridad': 'INTEGER DEFAULT 0',
      });
      await _agregarColumnas(db, 'compras', {
        'factura': "TEXT DEFAULT ''",
        'descuento': 'REAL DEFAULT 0',
        'iva': 'REAL DEFAULT 0',
      });
      await _crearTablaPermisos(db);
      await _crearTablaVentas(db);
      await _crearIndices(db);
    }

    if (oldVersion < 12) {
      await _agregarColumnas(db, 'comparacion', {
        'proveedor': "TEXT DEFAULT ''",
      });
    }

    if (oldVersion < 13) {
      await _crearTablaCategorias(db);
      await _crearTablaVentasItems(db);
    }

    if (oldVersion < 14) {
      await _agregarColumnas(db, 'productos', {
        'codigo_barras': "TEXT DEFAULT ''",
        'subcategoria': "TEXT DEFAULT ''",
        'modelo': "TEXT DEFAULT ''",
        'color_producto': "TEXT DEFAULT ''",
        'talle': "TEXT DEFAULT ''",
        'unidad_venta': "TEXT DEFAULT 'UN'",
        'stock_minimo': 'INTEGER DEFAULT 0',
        'porcentaje_ganancia': 'REAL DEFAULT 0',
        'notas_internas': "TEXT DEFAULT ''",
        'fotos': "TEXT DEFAULT '[]'",
        'precios_listas': "TEXT DEFAULT '{}'",
        'precios_bloqueados': "TEXT DEFAULT '[]'",
      });
      await db.execute(
        "CREATE INDEX IF NOT EXISTS idx_productos_codigo_barras ON productos(codigo_barras)",
      );
    }

    if (oldVersion < 15) {
      await _agregarColumnas(db, 'usuarios', {
        'firebase_uid': 'TEXT',
        'debe_cambiar_password': 'INTEGER DEFAULT 0',
        'email': "TEXT DEFAULT ''",
      });
      await db.update(
        'usuarios',
        {'debe_cambiar_password': 1},
        where: "usuario = 'admin' AND debe_cambiar_password = 0",
      );

      final permisosEncargado = await db.query(
        'permisos',
        where: 'rol = ?',
        whereArgs: ['supervisor'],
      );
      for (final row in permisosEncargado) {
        try {
          await db.insert('permisos', {
            'rol': 'encargado',
            'modulo': row['modulo'],
            'puede_ver': row['puede_ver'],
            'puede_crear': row['puede_crear'],
            'puede_editar': row['puede_editar'],
            'puede_eliminar': row['puede_eliminar'],
          });
        } catch (_) {}
      }
    }
  }

  Future<void> cerrar() async {
    final db = _database;
    if (db != null && db.isOpen) {
      await db.close();
    }
    _database = null;
  }
}
