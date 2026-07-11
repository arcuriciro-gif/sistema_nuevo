# Manual técnico — EL TATA Manager

Documento vivo de arquitectura e integración. Actualizar al cerrar cada módulo estable.

## Stack actual (no reemplazar)

| Capa | Tecnología |
|------|------------|
| UI | Flutter (Android + Windows) |
| Local | SQLite (`eltata.db`) vía `DatabaseHelper` |
| Remoto | Firebase Auth + Cloud Firestore + Storage |
| Sync inbound | `FirestoreSyncService` (snapshots en tiempo real) |
| Sync outbound | Métodos `subir*` / `eliminar*` + **`SyncQueueService`** (cola persistente) |

Tenant Firestore: `tenants/{tenantId}/…` (`BackendConfigService.tenantId`).

## Schema relevante

### v23 — cola de sincronización

- `sync_queue`: operaciones pendientes/fallidas (`dedupeKey` UNIQUE).
- `sync_history`: auditoría técnica de cada intento (success / retry / failed).

Migración en `DatabaseHelper._crearTablasSyncQueue`.

## Flujo de sincronización

```
Escritura local (SQLite)
        │
        ▼
pushOrEnqueue / DualProductoRepository
        │
        ├─ remoto OK → listo
        └─ sin red / error → sync_queue (pending)
                │
                ▼
        SyncQueueService (timer 8s)
                │
                ▼
        runOutboundStrict → subir*/eliminar*
                │
                ├─ OK → borrar de cola + sync_history(success)
                └─ fail → backoff + sync_history(retry|failed)
```

Inbound (otros dispositivos → este): listeners de `FirestoreSyncService` sin cambios.

## Estados UI (`SyncUiStatus`)

| Estado | Condición |
|--------|-----------|
| Sin conexión | Sin Auth Firebase / hint de red |
| Sincronizando… | Worker activo |
| Error | Ítems en `failed` |
| Pendiente | Ítems `pending`/`processing` |
| Sincronizado | Cola vacía y remoto disponible |

Widget: `lib/widgets/sync_status_chip.dart`  
Página: `lib/pages/sync_historial_page.dart`

## Navegación — botón Inicio

- `lib/core/navigation/app_navigation.dart`: `AppNavigation.irAlInicio` hace `popUntil(isFirst)` y selecciona el módulo `inicio` vía callback registrado por `MainShell`.
- `buildModuleAppBar` muestra el ícono casa por defecto (`showHome: true`); Inicio lo oculta.
- En móvil, la AppBar del shell también muestra Inicio cuando el módulo actual no es Inicio.

## Servicios que encolan

- `ClienteService`, `ProveedorService`
- `VentaService`, `CuentaCorrienteService`
- `RemitoService`, `CompraService`
- `DocumentoClienteService`
- `CategoriaService`, `ListaPrecioService`
- `ComentarioInternoService`
- `_DualProductoRepository` (productos)

### Colecciones Firestore adicionales (v1.1.2)

| Colección | Clave doc | Notas |
|-----------|-----------|--------|
| `categorias` | nombre normalizado | master de categorías |
| `listas_precios` | nombre normalizado | definiciones de listas |
| `remitos.pagos` | embebido | historial cobros remito |
| `comentarios` | hash tipo+entidad+usuario+fecha+texto | vía cola |

### Aún local-only (próximos)

- `movimientos_stock` / `historial_precios` (ledger)
- Branding / numeración de documentos (SharedPreferences)
- Roster completo de usuarios + permisos
- AFIP config

## Reglas de evolución

1. No cambiar arquitectura general ni reemplazar tecnologías.
2. No refactor masivo ni eliminar módulos.
3. Nueva funcionalidad sobre servicios/modelos/repos existentes.
4. Tras cada módulo estable: actualizar este manual + `CHANGELOG.md`.
5. Prioridad absoluta: confiabilidad de sync multi-dispositivo.

## Próximos módulos (orden)

1. ~~Cola sync + indicador + historial~~ ← actual
2. Dashboard (accesos rápidos + KPIs)
3. Planilla de pedidos a proveedores
4. Pedido sugerido inteligente
5. Administración de usuarios (solo admin + auditoría)
6. Reiniciar sistema (servicios, sin borrar datos)
7. Historial de producto ampliado
8. Estadísticas
9. Inventario (barcode / cámara)
10. Alertas automáticas
