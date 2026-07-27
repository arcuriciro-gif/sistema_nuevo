# HARDENING CHECKLIST — Tata.Manager 1.4.11+79

**Rama:** `cursor/hardening-cert-checklist-e44b`  
**Objetivo:** etapa exclusiva de endurecimiento (no certificación completa aún).

| # | Ítem | Estado | Evidencia |
|---|------|--------|-----------|
| 1 | Identidad global única entidades/tombstones | **HECHO** | `stable_document_id.dart`; ledger `documentId=numero`; tombstone reverse por numero+fallback local |
| 2 | Eliminar escritura absoluta `productos.stock` | **HECHO** | SQLite/Firestore insert strip; `actualizar`→sin stock; rules productos; upload siempre sin absoluto |
| 3 | Convergencia nodos con IDs distintos | **DEMOSTRADO** | `test/cert/hardening_convergencia_nodos_test.dart` |
| 4 | Watermark nunca avanza dejando eventos sin procesar | **HECHO** | park malformed + blockers; tests hardening |
| 5 | auth default `admin123` | **HECHO** | recovery default **OFF**; migrate; no repair sin recovery ON |
| 6 | Crashes mounted/navegación | **HECHO** | venta_factura, dashboard, remitos, compras |
| 7 | Catch-up unbounded limitado | **HECHO** | clientes/proveedores ausentes paginados (80×40, budget 50/ciclo) |

## Detalle

### 1. Identidad global
- `stableCommercialDocumentId(numero, localId)`
- Remito/venta/compra inventory events usan `numero`
- `_reversoLocalAntesDeTombstone(localId, stableDocumentId)` busca net por candidates

### 2. Stock absoluto
- Rules: create sin stock (o 0); update stock solo si keys ⊆ `{stock, actualizadoEn, ultimaStockOp, codigo}` (increment path)
- Repos strip stock

### 5. admin123
- `isDefaultRecoveryEnabled() ?? false`
- Bootstrap llama `enableDefaultRecoveryForBootstrap`
- Migrate: si admin ya cambió clave → recovery OFF

## Tests

```bash
flutter test test/cert/hardening_checklist_test.dart
flutter test test/cert/hardening_convergencia_nodos_test.dart
```

## Residual consciente
- Money ledger aún usa local id en algunos paths (no stock G6).
- Increment de stock en cloud sigue siendo client-side (rules permiten keys acotadas).
