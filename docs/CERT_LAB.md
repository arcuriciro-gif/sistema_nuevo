# Laboratorio de Certificación ERP (CERT LAB)

| Campo | Valor |
|---|---|
| Estado ERP | **NO CERTIFICADO** |
| Módulo actual | **Productos** (orden 1) |
| Código | `lib/core/cert/lab/` |
| Tests | `test/cert/lab/` |
| CI | `.github/workflows/cert-lab.yml` |

## Regla de hierro

1. **Prohibido** modificar el Sync Engine sin evidencia del lab (causa raíz demostrada).
2. Rojo → corregís **UNO** → re-ejecutás **TODA** la batería.
3. **No merge** de sync con escenario rojo.
4. APK/EXE solo tras módulos certificados (20 verdes consecutivos por módulo).
5. Un rojo en un módulo certificado → estado **revocado**.

## Orden obligatorio

1. Productos  
2. Stock  
3. Ventas  
4. Compras  
5. Remitos  
6. Clientes  
7. Proveedores  
8. Cuenta Corriente  
9. Configuración  

No avanzar si el módulo actual tiene una sola diferencia.

## Qué usa el lab (honesto)

| Capa | Real / Lab |
|---|---|
| `ProductoService` / ledger / outbox SQLite | **REAL** |
| Oráculo Win ↔ Android ↔ proyección cloud | **REAL comparación** |
| Firestore SDK / `FirestoreSyncService` push-pull | **NO** (puente lab) |
| Triple-hop Firebase producción | **NO CERTIFICADO** (`CertLabEngineManifest`) |

El puente lab materializa lo que el outbox real encolaría. Eso certifica dominio + cola + apply peer. **No** sustituye el motor Windows inbound en producción.

## Informe de fallo

Entidad, dónde, primer evento, archivo/clase/método, SQL, Firestore path, stack.

## Comandos

```bash
# Protocolo P0 (sin contrato motor)
flutter test test/cert/lab/cert_lab_protocol_test.dart

# Productos (ProductoService real) — 1 + 3 consecutivas CI
flutter test test/cert/lab/cert_lab_productos_test.dart

# Batería completa (P0-99 ROJO hasta inbound Win certificado)
flutter test test/cert/lab/cert_lab_battery_test.dart

tool/run_cert_lab.sh
```

## Definición CERTIFICADO (módulo)

20 ejecuciones consecutivas verdes, sin diferencias, sin pendientes eternos, sin crashes, sin intervención manual.  
CI valida 3 consecutivas como gate mínimo; la certificación plena de release exige 20.
