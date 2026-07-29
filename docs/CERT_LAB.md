# Laboratorio de Certificación ERP (CERT LAB)

| Campo | Valor |
|---|---|
| Estado | **OBLIGATORIO** antes de tocar Sync Engine |
| Código | `lib/core/cert/lab/` |
| Tests | `test/cert/lab/` |
| CI | `.github/workflows/cert-lab.yml` |

## Regla de hierro

1. **Prohibido** modificar el Sync Engine si el Cert Lab no existe o su batería protocolo no corre.
2. Cuando el lab detecta un rojo: corregís **UNO**, ejecutás **TODA** la batería.
3. **No se mergea** ningún PR de sync con un escenario rojo.
4. APK/EXE de sync **solo** tras varias corridas consecutivas verdes (protocolo + contratos).

## Qué compara

Nodos lógicos:

- **Windows** (SQLite)
- **Android** (SQLite)
- **Firestore** (simulado en memoria: docs + `stock_ops`)

Entidades: productos, stock, precios, clientes, proveedores, compras, ventas,
remitos, cuenta corriente, movimientos, configuración (extensible).

## Informe de fallo

Cada rojo incluye:

- entidad
- dónde diverge
- primer evento distinto
- archivo / clase / método
- path Firestore
- SQL
- stacktrace

Artefactos: `/opt/cursor/artifacts/cert-lab/cert_lab_latest.md`

## Cómo correr

```bash
flutter test test/cert/lab/
# o solo protocolo (sin contratos de motor):
flutter test test/cert/lab/cert_lab_protocol_test.dart
# batería completa (incluye P0-99 RED hasta certificar inbound Win):
flutter test test/cert/lab/cert_lab_battery_test.dart
```

## Manifiesto de motor

`CertLabEngineManifest` declara capacidades **aún no certificadas**.
Poner un flag en `true` sin evidencia del lab es fraude de certificación.

## Relación con Sync Engine

El lab **no** llama a `FirestoreSyncService` en P0 protocolo: valida el
modelo de verdad (ledger + stock_ops + docs) y el oráculo triple.

El escenario `P0-99` falla a propósito hasta que exista evidencia de inbound
Windows automático. Eso **no** se “arregla” tocando el manifiesto: se arregla
el motor (cuando esté autorizado) y se demuestra con el lab.
