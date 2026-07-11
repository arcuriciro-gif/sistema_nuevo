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
      version: 25,
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
  precios_bloqueados TEXT DEFAULT '[]',
  favorito INTEGER DEFAULT 0,
  deleted_at TEXT
)
''');

    await db.execute('''
CREATE TABLE proveedores(
  id INTEGER PRIMARY KEY AUTOINCREMENT,
  syncId TEXT DEFAULT '',
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
  syncId TEXT DEFAULT '',
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
  totalPagado REAL DEFAULT 0,
  saldoPendiente REAL DEFAULT 0,
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
  costoUnitario REAL DEFAULT 0,
  ganancia REAL DEFAULT 0,
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
    await _crearTablaPagos(db);
    await _crearTablasComunicaciones(db);
    await _crearTablaComentariosInternos(db);
    await _migrarSyncCompletoV21(db);
    await _crearTablasSyncQueue(db);
    await _crearTablasPedidos(db);
    await _crearIndices(db);
  }

  Future<void> _crearTablasPedidos(Database db) async {
    await db.execute('''
CREATE TABLE IF NOT EXISTS pedidos(
  id INTEGER PRIMARY KEY AUTOINCREMENT,
  proveedorId INTEGER,
  proveedorNombre TEXT NOT NULL,
  numero TEXT NOT NULL UNIQUE,
  fecha TEXT NOT NULL,
  observaciones TEXT DEFAULT '',
  estado TEXT DEFAULT 'borrador',
  fechaCreacion TEXT,
  fechaActualizacion TEXT,
  FOREIGN KEY (proveedorId) REFERENCES proveedores(id)
)
''');
    await db.execute('''
CREATE TABLE IF NOT EXISTS pedido_items(
  id INTEGER PRIMARY KEY AUTOINCREMENT,
  pedidoId INTEGER NOT NULL,
  productoId INTEGER,
  articulo TEXT NOT NULL,
  cantidad INTEGER NOT NULL DEFAULT 1,
  color TEXT DEFAULT '',
  observaciones TEXT DEFAULT '',
  orden INTEGER DEFAULT 0,
  FOREIGN KEY (pedidoId) REFERENCES pedidos(id) ON DELETE CASCADE
)
''');
    await db.execute(
      'CREATE INDEX IF NOT EXISTS idx_pedidos_proveedor ON pedidos(proveedorId)',
    );
    await db.execute(
      'CREATE INDEX IF NOT EXISTS idx_pedidos_fecha ON pedidos(fecha)',
    );
    await db.execute(
      'CREATE INDEX IF NOT EXISTS idx_pedido_items_pedido ON pedido_items(pedidoId)',
    );
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
  foto TEXT DEFAULT '',
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
        'password': '240be518fabd2724ddb6f04eeb1da5967448d7e831c08c8fa822809f74c720a9', // admin123
        'rol': 'admin',
        'activo': 1,
        'debe_cambiar_password': 1,
        'email': 'admin@tata-stock.tatastock.app',
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
      'comunicaciones',
      'pedidos',
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
            'pedidos',
            'clientes',
            'proveedores',
            'productos',
            'comunicaciones',
          ].contains(modulo)
              ? 1
              : 0;
          editarVal = [
            'remitos',
            'compras',
            'pedidos',
            'clientes',
            'proveedores',
            'productos',
            'stock',
            'listas_precios',
            'comunicaciones',
          ].contains(modulo)
              ? 1
              : 0;
          if (['auditoria', 'backup', 'configuracion', 'usuarios']
              .contains(modulo)) {
            verVal = 0;
          }
        } else if (rol == 'empleado') {
          crearVal = ['remitos', 'comunicaciones', 'pedidos'].contains(modulo)
              ? 1
              : 0;
          editarVal = ['comunicaciones', 'pedidos'].contains(modulo) ? 1 : 0;
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
  totalPagado REAL DEFAULT 0,
  saldoPendiente REAL DEFAULT 0,
  fechaVencimiento TEXT,
  estadoAfip TEXT DEFAULT 'no_aplica',
  cae TEXT DEFAULT '',
  caeVencimiento TEXT,
  puntoVenta INTEGER DEFAULT 0,
  observaciones TEXT,
  fechaCreacion TEXT,
  usuarioId INTEGER,
  FOREIGN KEY(clienteId) REFERENCES clientes(id)
)
''');
  }

  Future<void> _crearTablaPagos(Database db) async {
    await db.execute('''
CREATE TABLE IF NOT EXISTS pagos(
  id INTEGER PRIMARY KEY AUTOINCREMENT,
  ventaId INTEGER NOT NULL,
  clienteId INTEGER,
  fecha TEXT NOT NULL,
  monto REAL NOT NULL DEFAULT 0,
  medioPago TEXT DEFAULT 'efectivo',
  observaciones TEXT DEFAULT '',
  FOREIGN KEY(ventaId) REFERENCES ventas(id),
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
  costoUnitario REAL DEFAULT 0,
  ganancia REAL DEFAULT 0,
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

    if (oldVersion < 16) {
      await _agregarColumnas(db, 'ventas', {
        'totalPagado': 'REAL DEFAULT 0',
        'saldoPendiente': 'REAL DEFAULT 0',
      });
      await _crearTablaPagos(db);
      // Inicializar saldos de ventas existentes según estadoPago
      await db.execute('''
        UPDATE ventas SET
          totalPagado = CASE
            WHEN estadoPago = 'cobrado' THEN total
            WHEN estadoPago = 'parcial' THEN total * 0.5
            ELSE 0
          END,
          saldoPendiente = CASE
            WHEN estadoPago = 'cobrado' THEN 0
            WHEN estadoPago = 'parcial' THEN total * 0.5
            ELSE total
          END
        WHERE estado != 'anulada'
      ''');
      await db.execute('''
        UPDATE clientes SET saldo = COALESCE((
          SELECT SUM(v.saldoPendiente)
          FROM ventas v
          WHERE v.clienteId = clientes.id
            AND v.estado != 'anulada'
            AND v.saldoPendiente > 0
        ), 0)
      ''');
    }

    if (oldVersion < 17) {
      await _agregarColumnas(db, 'ventas', {
        'fechaVencimiento': 'TEXT',
        'estadoAfip': "TEXT DEFAULT 'no_aplica'",
        'cae': "TEXT DEFAULT ''",
        'caeVencimiento': 'TEXT',
        'puntoVenta': 'INTEGER DEFAULT 0',
      });
      // Vencimiento por defecto: fecha + 30 días para saldos abiertos
      await db.execute('''
        UPDATE ventas
        SET fechaVencimiento = datetime(fecha, '+30 days')
        WHERE fechaVencimiento IS NULL
          AND estado != 'anulada'
          AND saldoPendiente > 0
      ''');
    }

    if (oldVersion < 18) {
      await _agregarColumnas(db, 'productos', {
        'favorito': 'INTEGER DEFAULT 0',
        'deleted_at': 'TEXT',
      });
      await _agregarColumnas(db, 'ventas_items', {
        'costoUnitario': 'REAL DEFAULT 0',
        'ganancia': 'REAL DEFAULT 0',
      });
      await _agregarColumnas(db, 'remito_items', {
        'costoUnitario': 'REAL DEFAULT 0',
        'ganancia': 'REAL DEFAULT 0',
      });
      await db.execute(
        'CREATE INDEX IF NOT EXISTS idx_productos_favorito ON productos(favorito)',
      );
      await db.execute(
        'CREATE INDEX IF NOT EXISTS idx_productos_deleted_at ON productos(deleted_at)',
      );
      // Backfill ganancia con costo actual (aprox. para historial previo)
      await db.execute('''
        UPDATE ventas_items
        SET costoUnitario = COALESCE((
          SELECT costo FROM productos WHERE productos.id = ventas_items.productoId
        ), 0),
        ganancia = subtotal - (
          cantidad * COALESCE((
            SELECT costo FROM productos WHERE productos.id = ventas_items.productoId
          ), 0)
        )
        WHERE COALESCE(costoUnitario, 0) = 0
      ''');
      await db.execute('''
        UPDATE remito_items
        SET costoUnitario = COALESCE((
          SELECT costo FROM productos WHERE productos.id = remito_items.productoId
        ), 0),
        ganancia = subtotal - (
          cantidad * COALESCE((
            SELECT costo FROM productos WHERE productos.id = remito_items.productoId
          ), 0)
        )
        WHERE COALESCE(costoUnitario, 0) = 0
      ''');
    }

    if (oldVersion < 19) {
      await _crearTablasComunicaciones(db);
      final roles = ['admin', 'supervisor', 'empleado', 'solo_lectura'];
      for (final rol in roles) {
        int ver = 1;
        int crear = 0;
        int editar = 0;
        int eliminar = 0;
        if (rol == 'admin') {
          crear = 1;
          editar = 1;
          eliminar = 1;
        } else if (rol == 'supervisor' || rol == 'empleado') {
          crear = 1;
          editar = 1;
        }
        await db.insert(
          'permisos',
          {
            'rol': rol,
            'modulo': 'comunicaciones',
            'puede_ver': ver,
            'puede_crear': crear,
            'puede_editar': editar,
            'puede_eliminar': eliminar,
          },
          conflictAlgorithm: ConflictAlgorithm.ignore,
        );
      }
    }

    if (oldVersion < 20) {
      await _crearTablaComentariosInternos(db);
    }
    if (oldVersion < 21) {
      await _migrarSyncCompletoV21(db);
    }
    if (oldVersion < 22) {
      await _agregarColumnas(db, 'usuarios', {
        'foto': "TEXT DEFAULT ''",
      });
    }
    if (oldVersion < 23) {
      await _crearTablasSyncQueue(db);
    }
    if (oldVersion < 24) {
      await _migrarRemitosSaldoV24(db);
    }
    if (oldVersion < 25) {
      await _crearTablasPedidos(db);
      final roles = ['admin', 'supervisor', 'empleado', 'solo_lectura'];
      for (final rol in roles) {
        int ver = 1;
        int crear = 0;
        int editar = 0;
        int eliminar = 0;
        if (rol == 'admin') {
          crear = 1;
          editar = 1;
          eliminar = 1;
        } else if (rol == 'supervisor') {
          crear = 1;
          editar = 1;
          eliminar = 0;
        } else if (rol == 'empleado') {
          crear = 1;
          editar = 1;
        }
        await db.insert(
          'permisos',
          {
            'rol': rol,
            'modulo': 'pedidos',
            'puede_ver': ver,
            'puede_crear': crear,
            'puede_editar': editar,
            'puede_eliminar': eliminar,
          },
          conflictAlgorithm: ConflictAlgorithm.ignore,
        );
      }
    }
  }

  Future<void> _migrarRemitosSaldoV24(Database db) async {
    await _agregarColumnas(db, 'remitos', {
      'totalPagado': 'REAL DEFAULT 0',
      'saldoPendiente': 'REAL DEFAULT 0',
    });
    await db.execute('''
      UPDATE remitos SET
        totalPagado = CASE
          WHEN COALESCE(estadoPago, 'pendiente') = 'cobrado' THEN COALESCE(total, 0)
          WHEN COALESCE(estadoPago, 'pendiente') = 'parcial'
            THEN COALESCE(total, 0) * 0.5
          ELSE 0
        END,
        saldoPendiente = CASE
          WHEN COALESCE(estadoPago, 'pendiente') = 'cobrado' THEN 0
          WHEN COALESCE(estadoPago, 'pendiente') = 'parcial'
            THEN COALESCE(total, 0) * 0.5
          ELSE COALESCE(total, 0)
        END
    ''');
  }

  Future<void> _migrarSyncCompletoV21(Database db) async {
    await _agregarColumnas(db, 'clientes', {
      'syncId': "TEXT DEFAULT ''",
    });
    await _agregarColumnas(db, 'proveedores', {
      'syncId': "TEXT DEFAULT ''",
    });
    await db.execute('''
CREATE TABLE IF NOT EXISTS documentos_cliente(
  id TEXT PRIMARY KEY,
  clienteSyncId TEXT NOT NULL,
  clienteId INTEGER,
  clienteNombre TEXT DEFAULT '',
  tipo TEXT DEFAULT 'otro',
  numero TEXT DEFAULT '',
  nombreArchivo TEXT NOT NULL,
  url TEXT DEFAULT '',
  localPath TEXT DEFAULT '',
  creadoPor TEXT DEFAULT '',
  fecha TEXT NOT NULL
)
''');
    await db.execute(
      'CREATE INDEX IF NOT EXISTS idx_docs_cliente_sync '
      'ON documentos_cliente(clienteSyncId)',
    );
  }

  Future<void> _crearTablasComunicaciones(Database db) async {
    await db.execute('''
CREATE TABLE IF NOT EXISTS chat_conversaciones(
  id TEXT PRIMARY KEY,
  tipo TEXT DEFAULT 'dm',
  participantes TEXT NOT NULL,
  nombres TEXT DEFAULT '{}',
  titulo TEXT,
  ultimoMensaje TEXT DEFAULT '',
  ultimoMensajeAt TEXT,
  noLeidos TEXT DEFAULT '{}',
  creadaAt TEXT NOT NULL
)
''');
    await db.execute('''
CREATE TABLE IF NOT EXISTS chat_mensajes(
  id TEXT PRIMARY KEY,
  conversacionId TEXT NOT NULL,
  autorUsuario TEXT NOT NULL,
  autorNombre TEXT NOT NULL,
  tipo TEXT DEFAULT 'texto',
  texto TEXT DEFAULT '',
  archivoPath TEXT,
  archivoNombre TEXT,
  archivoMime TEXT,
  compartido TEXT,
  fecha TEXT NOT NULL,
  estados TEXT DEFAULT '{}'
)
''');
    await db.execute(
      'CREATE INDEX IF NOT EXISTS idx_chat_mensajes_conv ON chat_mensajes(conversacionId)',
    );
    await db.execute('''
CREATE TABLE IF NOT EXISTS notificaciones_internas(
  id TEXT PRIMARY KEY,
  usuarioDestino TEXT NOT NULL,
  tipo TEXT NOT NULL,
  titulo TEXT NOT NULL,
  cuerpo TEXT DEFAULT '',
  conversacionId TEXT,
  entidadTipo TEXT,
  entidadId TEXT,
  fecha TEXT NOT NULL,
  leida INTEGER DEFAULT 0
)
''');
    await db.execute(
      'CREATE INDEX IF NOT EXISTS idx_notif_destino ON notificaciones_internas(usuarioDestino)',
    );
  }

  Future<void> _crearTablaComentariosInternos(Database db) async {
    await db.execute('''
CREATE TABLE IF NOT EXISTS comentarios_internos(
  id INTEGER PRIMARY KEY AUTOINCREMENT,
  entidadTipo TEXT NOT NULL,
  entidadId TEXT NOT NULL,
  usuario TEXT NOT NULL,
  nombre TEXT NOT NULL,
  texto TEXT NOT NULL,
  fecha TEXT NOT NULL,
  activo INTEGER DEFAULT 1
)
''');
    await db.execute(
      'CREATE INDEX IF NOT EXISTS idx_comentarios_entidad '
      'ON comentarios_internos(entidadTipo, entidadId)',
    );
  }

  /// Cola persistente de sincronización outbound + historial técnico.
  Future<void> _crearTablasSyncQueue(Database db) async {
    await db.execute('''
CREATE TABLE IF NOT EXISTS sync_queue (
  id INTEGER PRIMARY KEY AUTOINCREMENT,
  entityType TEXT NOT NULL,
  operation TEXT NOT NULL,
  entityId TEXT NOT NULL,
  payloadJson TEXT DEFAULT '',
  dedupeKey TEXT NOT NULL UNIQUE,
  status TEXT NOT NULL DEFAULT 'pending',
  attempts INTEGER NOT NULL DEFAULT 0,
  lastError TEXT DEFAULT '',
  createdAt TEXT NOT NULL,
  updatedAt TEXT NOT NULL,
  nextRetryAt TEXT
)
''');
    await db.execute(
      'CREATE INDEX IF NOT EXISTS idx_sync_queue_status '
      'ON sync_queue(status, nextRetryAt)',
    );
    await db.execute('''
CREATE TABLE IF NOT EXISTS sync_history (
  id INTEGER PRIMARY KEY AUTOINCREMENT,
  queueId INTEGER,
  entityType TEXT NOT NULL,
  operation TEXT NOT NULL,
  entityId TEXT NOT NULL,
  status TEXT NOT NULL,
  error TEXT DEFAULT '',
  durationMs INTEGER DEFAULT 0,
  finishedAt TEXT NOT NULL
)
''');
    await db.execute(
      'CREATE INDEX IF NOT EXISTS idx_sync_history_finished '
      'ON sync_history(finishedAt)',
    );
  }

  Future<void> cerrar() async {
    final db = _database;
    if (db != null && db.isOpen) {
      await db.close();
    }
    _database = null;
  }
}
