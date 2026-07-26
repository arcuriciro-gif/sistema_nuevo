import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;

import '../../core/utils/media_path.dart';
import '../../database/database_helper.dart';
import '../../models/producto.dart';
import '../../services/branding_service.dart';
import 'whatsapp_business_config.dart';

class WhatsappCatalogSyncResult {
  final bool ok;
  final String? metaProductId;
  final String? error;
  final bool skipped;

  const WhatsappCatalogSyncResult({
    required this.ok,
    this.metaProductId,
    this.error,
    this.skipped = false,
  });
}

class WhatsappCatalogBulkResult {
  final int ok;
  final int error;
  final int skipped;
  final String? lastError;

  const WhatsappCatalogBulkResult({
    required this.ok,
    required this.error,
    required this.skipped,
    this.lastError,
  });
}

/// Sync de productos ERP → Meta Commerce Catalog (WhatsApp).
/// Plugin: local only, sin Firestore/outbox.
class WhatsappCatalogService {
  WhatsappCatalogService._();
  static final WhatsappCatalogService instance = WhatsappCatalogService._();

  final config = WhatsappBusinessConfig.instance;

  Future<void> cargar() => config.cargar();

  bool get listo => config.listoParaCatalogo;

  /// Hook de [ProductoSideEffects]: upsert o baja según [op].
  Future<void> onProductoSideEffect(
    Producto producto, {
    required String op,
  }) async {
    await config.cargar();
    if (!config.listoParaCatalogo || !config.catalogAutoSync) return;
    if (op == 'delete') {
      await marcarFueraDeStock(producto);
      return;
    }
    await sincronizarProducto(producto);
  }

  String _titulo(Producto p) {
    final t = p.descripcion.trim();
    if (t.isEmpty) return p.codigo;
    return t.length > 200 ? t.substring(0, 200) : t;
  }

  String _descripcion(Producto p, {required bool ocultarPrecio}) {
    final parts = <String>[
      if (ocultarPrecio) 'Precio: consultá el valor actual por chat.',
      if (p.observaciones.trim().isNotEmpty) p.observaciones.trim(),
      if (p.marca.trim().isNotEmpty) 'Marca: ${p.marca.trim()}',
      if (p.categoria.trim().isNotEmpty) 'Categoría: ${p.categoria.trim()}',
      if (p.modelo.trim().isNotEmpty) 'Modelo: ${p.modelo.trim()}',
    ];
    final d = parts.join('\n');
    if (d.isEmpty) return _titulo(p);
    return d.length > 5000 ? d.substring(0, 5000) : d;
  }

  String _brand(Producto p) {
    final m = p.marca.trim();
    if (m.isNotEmpty) return m;
    final b = BrandingService.instance.nombre.trim();
    if (b.isNotEmpty) return b;
    return 'Catalogo';
  }

  /// Precio según lista configurada (`1`/`2`/`3` o id de lista).
  double precioDeLista(Producto p) {
    final key = config.catalogPriceListKey.trim();
    if (key == '2') return p.precio2;
    if (key == '3') return p.precio3;
    if (key == '1' || key.isEmpty) return p.precio;
    final fromMap = p.preciosListas[key];
    if (fromMap != null && fromMap > 0) return fromMap;
    // Fallback razonable a Lista 1.
    return p.precio;
  }

  /// Precio Meta: enteros en centavos (599 = 5.99).
  int _precioCents(double precio) {
    if (precio <= 0) return 0;
    return (precio * 100).round();
  }

  String _availability(Producto p) {
    if (p.estaEliminado) return 'out of stock';
    if (p.stock <= 0) return 'out of stock';
    return 'in stock';
  }

  String _productUrl(Producto p) {
    final tpl = config.catalogProductUrlTemplate.trim();
    if (tpl.isNotEmpty) {
      return tpl
          .replaceAll('{codigo}', Uri.encodeComponent(p.codigo))
          .replaceAll('{id}', '${p.id ?? ''}');
    }
    final web = BrandingService.instance.sitioWeb.trim();
    if (web.isNotEmpty) {
      final base = web.endsWith('/') ? web.substring(0, web.length - 1) : web;
      final hasScheme =
          base.startsWith('http://') || base.startsWith('https://');
      final url = hasScheme ? base : 'https://$base';
      return '$url?sku=${Uri.encodeComponent(p.codigo)}';
    }
    // Meta exige URL; fallback al catálogo Commerce Manager.
    final cat = config.catalogId.trim();
    if (cat.isNotEmpty) {
      return 'https://www.facebook.com/commerce/catalogs/$cat';
    }
    return 'https://www.facebook.com/';
  }

  String? _imageUrl(Producto p) {
    final foto = p.fotoPrincipal.trim();
    if (foto.isEmpty) return null;
    if (!esUrlRemota(foto)) return null;
    return foto;
  }

  Future<Map<String, dynamic>?> _localRow(String codigo) async {
    final db = await DatabaseHelper.instance.database;
    final rows = await db.query(
      'wa_catalog_items',
      where: 'codigo = ?',
      whereArgs: [codigo],
      limit: 1,
    );
    return rows.isEmpty ? null : rows.first;
  }

  Future<WhatsappCatalogSyncResult> sincronizarProducto(Producto producto) async {
    await config.cargar();
    if (!config.listoParaCatalogo) {
      return const WhatsappCatalogSyncResult(
        ok: false,
        skipped: true,
        error: 'Catálogo WhatsApp no configurado',
      );
    }
    final image = _imageUrl(producto);
    if (image == null) {
      final err = producto.fotoPrincipal.trim().isEmpty
          ? 'Sin foto'
          : 'La foto debe estar en la nube (URL https) para Meta';
      await _upsertLocal(producto, estado: 'error', error: err);
      return WhatsappCatalogSyncResult(ok: false, error: err);
    }

    final ocultar = !config.catalogSyncPrice;
    final precioLista = precioDeLista(producto);
    final local = await _localRow(producto.codigo);
    final yaEnMeta = local != null &&
        (local['estado'] == 'ok' ||
            (local['metaProductId']?.toString().isNotEmpty ?? false));

    // Modo ocultar: no pisa el precio en Meta; solo nombre/foto/stock.
    if (ocultar && yaEnMeta) {
      return _updateSinPrecio(producto, imageUrl: image);
    }

    final cents = _precioCents(precioLista);
    if (cents <= 0) {
      const err = 'Precio de la lista elegida debe ser mayor a 0';
      await _upsertLocal(producto, estado: 'error', error: err);
      return const WhatsappCatalogSyncResult(ok: false, error: err);
    }

    return _upsertConPrecio(
      producto,
      imageUrl: image,
      precio: precioLista,
      cents: cents,
      ocultarPrecio: ocultar,
    );
  }

  Future<WhatsappCatalogSyncResult> _upsertConPrecio(
    Producto producto, {
    required String imageUrl,
    required double precio,
    required int cents,
    required bool ocultarPrecio,
  }) async {
    final url = Uri.parse(
      'https://graph.facebook.com/${config.apiVersion}/'
      '${config.catalogId}/products',
    );
    final body = <String, dynamic>{
      'access_token': config.accessToken,
      'retailer_id': producto.codigo,
      'name': _titulo(producto),
      'description': _descripcion(producto, ocultarPrecio: ocultarPrecio),
      'availability': _availability(producto),
      'condition': 'new',
      'price': cents,
      'currency': config.catalogCurrency,
      'image_url': imageUrl,
      'url': _productUrl(producto),
      'brand': _brand(producto),
      'allow_upsert': true,
      if (producto.categoria.trim().isNotEmpty)
        'product_type': producto.categoria.trim(),
      if (producto.codigoBarras.trim().isNotEmpty)
        'gtin': producto.codigoBarras.trim(),
      'inventory': producto.stock < 0 ? 0 : producto.stock,
    };

    try {
      final res = await http.post(url, body: body);
      Map<String, dynamic> json = {};
      try {
        final decoded = jsonDecode(res.body);
        if (decoded is Map<String, dynamic>) json = decoded;
      } catch (_) {}
      if (res.statusCode >= 200 && res.statusCode < 300) {
        final metaId = json['id']?.toString();
        await _upsertLocal(
          producto,
          estado: 'ok',
          metaProductId: metaId,
          error: '',
          precioSync: precio,
        );
        return WhatsappCatalogSyncResult(ok: true, metaProductId: metaId);
      }
      final err = (json['error'] is Map)
          ? (json['error']['message']?.toString() ?? 'Error Meta')
          : 'HTTP ${res.statusCode}: ${res.body}';
      await _upsertLocal(producto, estado: 'error', error: err);
      return WhatsappCatalogSyncResult(ok: false, error: err);
    } catch (e) {
      debugPrint('WA catalog sync: $e');
      await _upsertLocal(producto, estado: 'error', error: '$e');
      return WhatsappCatalogSyncResult(ok: false, error: '$e');
    }
  }

  /// Actualiza ficha sin tocar el precio (modo “no mostrar / congelar”).
  Future<WhatsappCatalogSyncResult> _updateSinPrecio(
    Producto producto, {
    required String imageUrl,
  }) async {
    final url = Uri.parse(
      'https://graph.facebook.com/${config.apiVersion}/'
      '${config.catalogId}/items_batch',
    );
    try {
      final res = await http.post(
        url,
        headers: {
          'Authorization': 'Bearer ${config.accessToken}',
          'Content-Type': 'application/json',
        },
        body: jsonEncode({
          'item_type': 'PRODUCT_ITEM',
          'requests': [
            {
              'method': 'UPDATE',
              'data': {
                'id': producto.codigo,
                'title': _titulo(producto),
                'description':
                    _descripcion(producto, ocultarPrecio: true),
                'availability': _availability(producto),
                'condition': 'new',
                'image_link': imageUrl,
                'link': _productUrl(producto),
                'brand': _brand(producto),
                if (producto.categoria.trim().isNotEmpty)
                  'product_type': producto.categoria.trim(),
              },
            },
          ],
        }),
      );
      if (res.statusCode >= 200 && res.statusCode < 300) {
        await _upsertLocal(
          producto,
          estado: 'ok',
          error: '',
          keepPrecio: true,
        );
        return const WhatsappCatalogSyncResult(ok: true);
      }
      final err = 'HTTP ${res.statusCode}: ${res.body}';
      await _upsertLocal(producto, estado: 'error', error: err, keepPrecio: true);
      return WhatsappCatalogSyncResult(ok: false, error: err);
    } catch (e) {
      await _upsertLocal(producto, estado: 'error', error: '$e', keepPrecio: true);
      return WhatsappCatalogSyncResult(ok: false, error: '$e');
    }
  }

  /// Baja lógica en Meta (out of stock). No borra el ítem del catálogo.
  Future<WhatsappCatalogSyncResult> marcarFueraDeStock(Producto producto) async {
    await config.cargar();
    if (!config.listoParaCatalogo) {
      return const WhatsappCatalogSyncResult(
        ok: false,
        skipped: true,
        error: 'Catálogo no configurado',
      );
    }
    final image = _imageUrl(producto);
    // Sin imagen no podemos upsert; intentamos items_batch DELETE.
    if (image == null) {
      return _deleteByRetailerId(producto);
    }
    final soft = producto.copyWith(stock: 0);
    // Forzar out of stock vía availability.
    final r = await sincronizarProducto(
      soft.copyWith(
        deletedAt: producto.deletedAt ?? DateTime.now().toIso8601String(),
      ),
    );
    return r;
  }

  Future<WhatsappCatalogSyncResult> _deleteByRetailerId(Producto producto) async {
    final url = Uri.parse(
      'https://graph.facebook.com/${config.apiVersion}/'
      '${config.catalogId}/items_batch',
    );
    try {
      final res = await http.post(
        url,
        headers: {
          'Authorization': 'Bearer ${config.accessToken}',
          'Content-Type': 'application/json',
        },
        body: jsonEncode({
          'item_type': 'PRODUCT_ITEM',
          'requests': [
            {
              'method': 'DELETE',
              'data': {'id': producto.codigo},
            },
          ],
        }),
      );
      if (res.statusCode >= 200 && res.statusCode < 300) {
        await _upsertLocal(producto, estado: 'deleted', error: '');
        return const WhatsappCatalogSyncResult(ok: true);
      }
      final err = 'HTTP ${res.statusCode}: ${res.body}';
      await _upsertLocal(producto, estado: 'error', error: err);
      return WhatsappCatalogSyncResult(ok: false, error: err);
    } catch (e) {
      await _upsertLocal(producto, estado: 'error', error: '$e');
      return WhatsappCatalogSyncResult(ok: false, error: '$e');
    }
  }

  Future<String?> probarCatalogo() async {
    await config.cargar();
    if (!config.listoParaCatalogo) {
      return 'Falta token o Catalog ID';
    }
    final url = Uri.parse(
      'https://graph.facebook.com/${config.apiVersion}/'
      '${config.catalogId}'
      '?fields=name,product_count,vertical',
    );
    try {
      final res = await http.get(
        url,
        headers: {'Authorization': 'Bearer ${config.accessToken}'},
      );
      if (res.statusCode >= 200 && res.statusCode < 300) {
        final json = jsonDecode(res.body) as Map<String, dynamic>;
        final name = json['name'] ?? config.catalogId;
        final count = json['product_count'];
        return 'OK · $name'
            '${count == null ? '' : ' · $count productos'}';
      }
      try {
        final json = jsonDecode(res.body);
        if (json is Map) {
          final err = json['error'];
          if (err is Map && err['message'] != null) {
            return err['message'].toString();
          }
        }
      } catch (_) {}
      return 'HTTP ${res.statusCode}';
    } catch (e) {
      return '$e';
    }
  }

  /// Muestra el ícono de catálogo en el chat (por número Business).
  Future<String?> activarVisibilidadCatalogo({bool visible = true}) async {
    await config.cargar();
    if (!config.listoParaApi) {
      return 'Falta Phone Number ID / token';
    }
    final url = Uri.parse(
      'https://graph.facebook.com/${config.apiVersion}/'
      '${config.phoneNumberId}/whatsapp_commerce_settings'
      '?is_catalog_visible=$visible',
    );
    try {
      final res = await http.post(
        url,
        headers: {'Authorization': 'Bearer ${config.accessToken}'},
      );
      if (res.statusCode >= 200 && res.statusCode < 300) {
        return visible ? 'Catálogo visible en WhatsApp' : 'Catálogo oculto';
      }
      return 'HTTP ${res.statusCode}: ${res.body}';
    } catch (e) {
      return '$e';
    }
  }

  Future<WhatsappCatalogBulkResult> sincronizarLista(
    List<Producto> productos, {
    int maxItems = 500,
  }) async {
    var ok = 0;
    var error = 0;
    var skipped = 0;
    String? lastError;
    final slice = productos.take(maxItems);
    for (final p in slice) {
      if (p.estaEliminado) {
        skipped++;
        continue;
      }
      final r = await sincronizarProducto(p);
      if (r.skipped) {
        skipped++;
      } else if (r.ok) {
        ok++;
      } else {
        error++;
        lastError = r.error;
      }
    }
    return WhatsappCatalogBulkResult(
      ok: ok,
      error: error,
      skipped: skipped,
      lastError: lastError,
    );
  }

  Future<void> _upsertLocal(
    Producto producto, {
    required String estado,
    String? metaProductId,
    String error = '',
    double? precioSync,
    bool keepPrecio = false,
  }) async {
    try {
      final db = await DatabaseHelper.instance.database;
      final now = DateTime.now().toIso8601String();
      final existing = await db.query(
        'wa_catalog_items',
        where: 'codigo = ?',
        whereArgs: [producto.codigo],
        limit: 1,
      );
      final prevPrecio = existing.isNotEmpty
          ? (existing.first['precio'] as num?)?.toDouble()
          : null;
      final precio = keepPrecio
          ? (prevPrecio ?? precioDeLista(producto))
          : (precioSync ?? precioDeLista(producto));
      final row = <String, dynamic>{
        'productoId': producto.id,
        'codigo': producto.codigo,
        'retailerId': producto.codigo,
        'metaProductId': metaProductId ??
            (existing.isNotEmpty
                ? (existing.first['metaProductId'] ?? '')
                : ''),
        'titulo': _titulo(producto),
        'precio': precio,
        'currency': config.catalogCurrency,
        'imageUrl': _imageUrl(producto) ?? '',
        'estado': estado,
        'error': error,
        'actualizadoEn': now,
      };
      if (existing.isEmpty) {
        row['creadoEn'] = now;
        await db.insert('wa_catalog_items', row);
      } else {
        await db.update(
          'wa_catalog_items',
          row,
          where: 'codigo = ?',
          whereArgs: [producto.codigo],
        );
      }
    } catch (e) {
      debugPrint('wa_catalog_items: $e');
    }
  }

  Future<List<Map<String, dynamic>>> listarEstadoLocal({int limite = 40}) async {
    final db = await DatabaseHelper.instance.database;
    return db.query(
      'wa_catalog_items',
      orderBy: 'datetime(actualizadoEn) DESC',
      limit: limite,
    );
  }
}
