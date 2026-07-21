import 'package:sqflite/sqflite.dart';

import '../core/utils/texto_producto.dart';
import '../database/database_helper.dart';
import '../models/comparacion.dart';
import '../models/producto.dart';
import 'auth_service.dart';
import 'producto_service.dart';

class ComparadorService {
  final ProductoService productoService = ProductoService();

  Future<void> limpiarComparaciones() async {
    final db = await DatabaseHelper.instance.database;
    await db.delete('comparacion');
  }

  Future<void> guardarComparacion(Comparacion comparacion) async {
    final db = await DatabaseHelper.instance.database;
    await db.insert(
      'comparacion',
      comparacion.toMap(),
      conflictAlgorithm: ConflictAlgorithm.replace,
    );
  }

  Future<List<Comparacion>> obtenerComparacion() async {
    final db = await DatabaseHelper.instance.database;
    final resultado = await db.query('comparacion', orderBy: 'descripcion');
    return resultado.map((e) => Comparacion.fromMap(e)).toList();
  }

  /// Compara la lista del proveedor contra la base por **descripción**
  /// (no por código interno), salvo [matchPrecisoPorCodigo].
  ///
  /// Modos:
  /// 1) **Rango de talles** (Febo): "papi blanco 39-42" → solo ese color y
  ///    talles 39..42.
  /// 2) **Precio único por modelo** (Leal, Profeta, etc.).
  /// 3) **Preciso** (PDF presupuesto/remito Cuero Sur): código local o
  ///    mismo artículo+color+talle. No cruza colores ni inventa hermanos.
  Future<void> compararProductos(
    List<Producto> productosImportados, {
    String proveedor = '',
    bool matchPrecisoPorCodigo = false,
  }) async {
    await limpiarComparaciones();
    final locales = await productoService.obtenerTodos();

    // Índice por artículo (descripcion / modelo) — sin color ni talle.
    final porArticulo = <String, List<Producto>>{};
    // Índice por artículo+color (sin talle) — para rangos tipo Febo.
    final porDescColor = <String, List<Producto>>{};
    // Índice por texto completo normalizado.
    final porDesc = <String, List<Producto>>{};

    for (final p in locales) {
      final art = TextoProducto.articuloBase(
        p.modelo.trim().isNotEmpty ? p.modelo : p.descripcion,
      );
      if (art.isNotEmpty) {
        porArticulo.putIfAbsent(art, () => []).add(p);
      }
      final artDesc = TextoProducto.articuloBase(p.descripcion);
      if (artDesc.isNotEmpty && artDesc != art) {
        porArticulo.putIfAbsent(artDesc, () => []).add(p);
      }

      final d = TextoProducto.normalizar(p.descripcion);
      if (d.isNotEmpty) {
        porDesc.putIfAbsent(d, () => []).add(p);
      }
      final dc = TextoProducto.textoLocalSinTalle(
        descripcion: p.descripcion,
        color: p.colorProducto,
      );
      if (dc.isNotEmpty) {
        porDescColor.putIfAbsent(dc, () => []).add(p);
      }
      if (p.talle.trim().isEmpty) {
        final sinTalle = TextoProducto.quitarTalleFinal(
          p.colorProducto.trim().isEmpty
              ? p.descripcion
              : '${p.descripcion} ${p.colorProducto}',
        );
        if (sinTalle.isNotEmpty && sinTalle != dc && sinTalle != d) {
          porDescColor.putIfAbsent(sinTalle, () => []).add(p);
        }
      }
      final full = TextoProducto.textoLocal(
        descripcion: p.descripcion,
        color: p.colorProducto,
        talle: p.talle,
      );
      if (full.isNotEmpty && full != d && full != dc) {
        porDesc.putIfAbsent(full, () => []).add(p);
      }
    }

    // Una fila del informe por código local (si el Excel repite el modelo,
    // gana la última línea válida — evita inflar el conteo).
    final porCodigoLocal = <String, Comparacion>{};
    final nuevos = <Comparacion>[];

    for (final importado in productosImportados) {
      final descProv = importado.descripcion.trim();
      if (descProv.isEmpty) continue;

      final matches = matchPrecisoPorCodigo
          ? _buscarLocalesPreciso(
              importado: importado,
              proveedorLista: proveedor,
              todos: locales,
            )
          : _buscarLocales(
              descripcionProveedor: descProv,
              proveedorLista: proveedor,
              porArticulo: porArticulo,
              porDesc: porDesc,
              porDescColor: porDescColor,
              todos: locales,
            );

      if (matches.isEmpty) {
        nuevos.add(
          Comparacion(
            codigo: importado.codigo.isNotEmpty
                ? importado.codigo
                : 'NUEVO-${TextoProducto.articuloBase(descProv).hashCode.abs()}',
            descripcion: descProv,
            precioViejo: 0,
            precioNuevo: importado.costo,
            estado: 'NUEVO',
            marca: importado.marca,
            proveedor: proveedor,
          ),
        );
        continue;
      }

      for (final local in matches) {
        var estado = 'IGUAL';
        if (importado.costo > local.costo) {
          estado = 'SUBIO';
        } else if (importado.costo < local.costo) {
          estado = 'BAJO';
        }
        final etiquetaLocal =
            '${local.descripcion}${local.colorProducto.isNotEmpty ? ' ${local.colorProducto}' : ''}${local.talle.isNotEmpty ? ' ${local.talle}' : ''}';
        porCodigoLocal[local.codigo] = Comparacion(
          codigo: local.codigo,
          descripcion: '$etiquetaLocal  ←  $descProv',
          precioViejo: local.costo,
          precioNuevo: importado.costo,
          estado: estado,
          marca: local.marca.isNotEmpty ? local.marca : importado.marca,
          proveedor: proveedor,
        );
      }
    }

    // NUEVO solo si ese artículo no quedó cubierto por ningún match local.
    final articulosMatcheados = <String>{};
    for (final c in porCodigoLocal.values) {
      final ladoProv = c.descripcion.contains('  ←  ')
          ? c.descripcion.split('  ←  ').last
          : c.descripcion;
      articulosMatcheados.add(TextoProducto.articuloBase(ladoProv));
    }
    final nuevosUnicos = <String, Comparacion>{};
    for (final n in nuevos) {
      final art = TextoProducto.articuloBase(n.descripcion);
      if (art.isNotEmpty && articulosMatcheados.contains(art)) continue;
      nuevosUnicos.putIfAbsent(art.isNotEmpty ? art : n.codigo, () => n);
    }

    for (final c in [...porCodigoLocal.values, ...nuevosUnicos.values]) {
      await guardarComparacion(c);
    }
  }

  /// Match conservador para PDF: código → mismo modelo+color+talle.
  List<Producto> _buscarLocalesPreciso({
    required Producto importado,
    required String proveedorLista,
    required List<Producto> todos,
  }) {
    final universo = todos
        .where(
          (p) => TextoProducto.proveedorCompatible(
            proveedorLista,
            p.proveedor,
          ),
        )
        .toList();

    final cod = importado.codigo.trim();
    if (cod.isNotEmpty) {
      final porCodigo = universo
          .where((p) => p.codigo.trim().toLowerCase() == cod.toLowerCase())
          .toList();
      if (porCodigo.isNotEmpty) return porCodigo;
    }

    final descProv = importado.descripcion.trim();
    final artProv = TextoProducto.articuloBase(descProv);
    final coloresProv = TextoProducto.coloresEnTexto(descProv);
    final talleProv = TextoProducto.parsearTalleAlFinal(descProv) ??
        TextoProducto.parsearRangoTalle(descProv).desde;

    final out = <Producto>[];
    for (final p in universo) {
      if (!TextoProducto.mismoArticulo(
        artProv,
        p.modelo.trim().isNotEmpty ? p.modelo : p.descripcion,
      )) {
        if (!TextoProducto.mismoArticulo(artProv, p.descripcion)) continue;
      }

      if (!TextoProducto.localCoincideColorProveedor(
        descripcionLocal: p.descripcion,
        colorLocal: p.colorProducto,
        textoProveedorSinTalle: TextoProducto.quitarTalleFinal(descProv),
      )) {
        continue;
      }
      // Si el proveedor trae color, exigimos color en el local (no genéricos).
      if (coloresProv.isNotEmpty) {
        final colsLoc =
            TextoProducto.coloresEnTexto('${p.descripcion} ${p.colorProducto}');
        if (colsLoc.intersection(coloresProv).isEmpty) continue;
      }

      if (talleProv != null) {
        final okTalle = TextoProducto.localEnRangoProveedor(
          descripcionLocal: p.descripcion,
          colorLocal: p.colorProducto,
          talleLocal: p.talle,
          desde: talleProv,
          hasta: talleProv,
        );
        // Pares tipo 34/35 en el PDF: aceptar si el local cae en ese par.
        final rangoProv = TextoProducto.parsearRangoTalle(descProv);
        final okPar = rangoProv.desde != null &&
            rangoProv.hasta != null &&
            TextoProducto.localEnRangoProveedor(
              descripcionLocal: p.descripcion,
              colorLocal: p.colorProducto,
              talleLocal: p.talle,
              desde: rangoProv.desde!,
              hasta: rangoProv.hasta!,
            );
        if (!okTalle && !okPar) continue;
      }

      out.add(p);
    }
    return out;
  }

  /// Sugiere talles hermanos (mismo artículo+color) no presentes en el PDF.
  /// Siempre para revisión manual: no aplica solo.
  Future<List<Comparacion>> sugerirHermanosTalle() async {
    final informe = await obtenerComparacion();
    final conCambio = informe
        .where((c) => c.estado == 'SUBIO' || c.estado == 'BAJO')
        .toList();
    if (conCambio.isEmpty) return const [];

    final locales = await productoService.obtenerTodos();
    final codigosEnInforme = informe.map((c) => c.codigo).toSet();
    final sugeridos = <String, Comparacion>{};

    for (final fila in conCambio) {
      final local = await productoService.buscarPorCodigo(fila.codigo);
      if (local == null) continue;
      final clave = TextoProducto.claveFamiliaHermanos(
        local.descripcion,
        color: local.colorProducto,
      );
      if (clave.isEmpty) continue;

      for (final p in locales) {
        if (codigosEnInforme.contains(p.codigo)) continue;
        if (sugeridos.containsKey(p.codigo)) continue;
        if (!TextoProducto.proveedorCompatible(fila.proveedor, p.proveedor)) {
          continue;
        }
        final claveP = TextoProducto.claveFamiliaHermanos(
          p.descripcion,
          color: p.colorProducto,
        );
        if (claveP != clave) continue;

        var estado = 'IGUAL';
        if (fila.precioNuevo > p.costo) {
          estado = 'SUBIO';
        } else if (fila.precioNuevo < p.costo) {
          estado = 'BAJO';
        }
        if (estado == 'IGUAL') continue;

        final etiqueta =
            '${p.descripcion}${p.colorProducto.isNotEmpty ? ' ${p.colorProducto}' : ''}${p.talle.isNotEmpty ? ' ${p.talle}' : ''}';
        sugeridos[p.codigo] = Comparacion(
          codigo: p.codigo,
          descripcion: '$etiqueta  ←  hermano de ${fila.descripcion}',
          precioViejo: p.costo,
          precioNuevo: fila.precioNuevo,
          estado: estado,
          marca: p.marca,
          proveedor: fila.proveedor,
        );
      }
    }
    return sugeridos.values.toList()
      ..sort((a, b) => a.descripcion.compareTo(b.descripcion));
  }

  Future<void> agregarComparaciones(List<Comparacion> filas) async {
    for (final c in filas) {
      await guardarComparacion(c);
    }
  }

  List<Producto> _buscarLocales({
    required String descripcionProveedor,
    required String proveedorLista,
    required Map<String, List<Producto>> porArticulo,
    required Map<String, List<Producto>> porDesc,
    required Map<String, List<Producto>> porDescColor,
    required List<Producto> todos,
  }) {
    final n = TextoProducto.normalizar(descripcionProveedor);
    final rango = TextoProducto.parsearRangoTalle(descripcionProveedor);
    final universo = todos
        .where(
          (p) => TextoProducto.proveedorCompatible(
            proveedorLista,
            p.proveedor,
          ),
        )
        .toList();

    // 1) Rango de talles (Febo): color + talles del rango.
    if (rango.desde != null && rango.hasta != null) {
      final base = rango.base;
      final bases = <String>{
        base,
        base
            .replaceAll(
              RegExp(r'\b(x par|por par|en eva|eva|pu|pve|tr|goma)\b'),
              ' ',
            )
            .replaceAll(RegExp(r'\s+'), ' ')
            .trim(),
      }..removeWhere((e) => e.isEmpty);

      final candidatos = <Producto>{};
      final artProv = TextoProducto.articuloBase(base);

      for (final p in universo) {
        final mismoModelo = artProv.isNotEmpty &&
            TextoProducto.localEsMismoModeloPrecioUnico(
              descripcionProveedor: artProv,
              descripcionLocal: p.descripcion,
              modeloLocal: p.modelo,
            );
        final dc = TextoProducto.textoLocalSinTalle(
          descripcion: p.descripcion,
          color: p.colorProducto,
        );
        final porTexto = bases.any(
          (b) =>
              b == dc ||
              (dc.isNotEmpty && TextoProducto.coincidePorTokens(b, dc)),
        );

        if (!mismoModelo && !porTexto) continue;

        if (!TextoProducto.localCoincideColorProveedor(
          descripcionLocal: p.descripcion,
          colorLocal: p.colorProducto,
          textoProveedorSinTalle: base,
        )) {
          continue;
        }

        candidatos.add(p);
      }

      final enRango = candidatos.where((p) {
        return TextoProducto.localEnRangoProveedor(
          descripcionLocal: p.descripcion,
          colorLocal: p.colorProducto,
          talleLocal: p.talle,
          desde: rango.desde!,
          hasta: rango.hasta!,
        );
      }).toList();

      if (enRango.isNotEmpty) return enRango;
      // Si el rango no pegó, seguimos con precio único por modelo.
    }

    // 2) Precio único por modelo (Leal, Profeta, …):
    //    un costo → todos los color×talle de ese artículo en tu stock.
    final artProv = TextoProducto.articuloBase(descripcionProveedor);
    final delModelo = <Producto>{};

    if (artProv.isNotEmpty) {
      final indexados = porArticulo[artProv];
      if (indexados != null) {
        delModelo.addAll(
          indexados.where(
            (p) => TextoProducto.proveedorCompatible(
              proveedorLista,
              p.proveedor,
            ),
          ),
        );
      }

      for (final p in universo) {
        if (TextoProducto.localEsMismoModeloPrecioUnico(
          descripcionProveedor: descripcionProveedor,
          descripcionLocal: p.descripcion,
          modeloLocal: p.modelo,
        )) {
          delModelo.add(p);
        }
      }
    }

    if (delModelo.isNotEmpty) {
      return delModelo.toList();
    }

    // 3) Match exacto del texto completo (último recurso).
    final exactos = porDesc[n];
    if (exactos != null && exactos.isNotEmpty) {
      return exactos
          .where(
            (p) => TextoProducto.proveedorCompatible(
              proveedorLista,
              p.proveedor,
            ),
          )
          .toList();
    }

    return const [];
  }

  /// Actualiza **únicamente el costo** de productos ya existentes en tu lista.
  /// Los NUEVO no se crean solos: hay que darlos de alta a mano (si te interesan).
  Future<void> actualizarProductos() async {
    final comparaciones = await obtenerComparacion();
    final db = await DatabaseHelper.instance.database;
    final usuario = AuthService.instance.currentUser?.usuario ?? 'sistema';
    final ahora = DateTime.now().toIso8601String();

    for (final comp in comparaciones) {
      if (comp.estado == 'NUEVO') continue;

      final producto = await productoService.buscarPorCodigo(comp.codigo);
      if (producto == null) continue;
      if (comp.precioNuevo == comp.precioViejo) continue;

      await db.update(
        'productos',
        {'costo': comp.precioNuevo},
        where: 'id = ?',
        whereArgs: [producto.id],
      );

      await db.insert('historial_precios', {
        'productoId': producto.id,
        'fecha': ahora,
        'usuario': usuario,
        'costoAnterior': comp.precioViejo,
        'costoNuevo': comp.precioNuevo,
        'precioAnterior': producto.precio,
        'precioNuevo': producto.precio,
        'porcentaje': comp.precioViejo > 0
            ? ((comp.precioNuevo - comp.precioViejo) / comp.precioViejo) * 100
            : 0.0,
        'listaModificada':
            comp.proveedor.isNotEmpty ? comp.proveedor : 'Lista proveedor',
        'motivo': 'Actualización de costo por lista (desc)',
      });
    }
  }

  /// Sugiere el próximo código numérico libre (máx+1), o un código corto.
  Future<String> sugerirCodigoNuevo() async {
    final todos = await productoService.obtenerTodos();
    var maxN = 0;
    for (final p in todos) {
      final n = int.tryParse(p.codigo.trim());
      if (n != null && n > maxN) maxN = n;
    }
    if (maxN > 0) return '${maxN + 1}';
    return 'A${DateTime.now().millisecondsSinceEpoch % 100000}';
  }

  Future<void> eliminarComparacionPorCodigo(String codigo) async {
    final db = await DatabaseHelper.instance.database;
    await db.delete('comparacion', where: 'codigo = ?', whereArgs: [codigo]);
  }

  /// Alta manual de un artículo NUEVO del informe.
  Future<String?> crearProductoDesdeNuevo({
    required Comparacion comp,
    required String codigo,
    required String descripcion,
    String color = '',
    String talle = '',
  }) async {
    final cod = codigo.trim();
    if (cod.isEmpty) return 'Ingresá un código.';
    if (cod.toUpperCase().startsWith('NUEVO-')) {
      return 'Elegí tu código (no uses el de referencia del informe).';
    }
    final existe = await productoService.buscarPorCodigo(cod);
    if (existe != null) return 'Ese código ya existe en tu lista.';

    await productoService.insertar(
      Producto(
        codigo: cod,
        descripcion: descripcion.trim().isEmpty
            ? comp.descripcion.split('  ←  ').first.trim()
            : descripcion.trim(),
        marca: comp.marca,
        categoria: '',
        proveedor: comp.proveedor,
        ubicacion: '',
        stock: 0,
        costo: comp.precioNuevo,
        precio: 0,
        observaciones: '',
        foto: '',
        colorProducto: color.trim(),
        talle: talle.trim(),
      ),
    );
    await eliminarComparacionPorCodigo(comp.codigo);
    return null;
  }

  Future<int> cantidadAumentos() async {
    final db = await DatabaseHelper.instance.database;
    final resultado = await db
        .rawQuery("SELECT COUNT(*) FROM comparacion WHERE estado='SUBIO'");
    return Sqflite.firstIntValue(resultado) ?? 0;
  }

  Future<int> cantidadBajas() async {
    final db = await DatabaseHelper.instance.database;
    final resultado = await db
        .rawQuery("SELECT COUNT(*) FROM comparacion WHERE estado='BAJO'");
    return Sqflite.firstIntValue(resultado) ?? 0;
  }

  Future<int> cantidadNuevos() async {
    final db = await DatabaseHelper.instance.database;
    final resultado = await db
        .rawQuery("SELECT COUNT(*) FROM comparacion WHERE estado='NUEVO'");
    return Sqflite.firstIntValue(resultado) ?? 0;
  }

  Future<int> cantidadIguales() async {
    final db = await DatabaseHelper.instance.database;
    final resultado = await db
        .rawQuery("SELECT COUNT(*) FROM comparacion WHERE estado='IGUAL'");
    return Sqflite.firstIntValue(resultado) ?? 0;
  }
}
