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
        SyncQueueService (timer 4s)
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

## Refresco de pantallas (`DataRefreshHub`)

- Al guardar local o al aplicar inbound de Firestore se llama `notifyTodo` / `notifyProductos` / etc.
- Debounce ~450 ms para no recargar N veces por un lote de sync.
- Inicio, Dashboard y listas principales escuchan el hub y recargan en silencio (sin spinner).
- No hay polling de 1 s: Firestore ya empuja cambios en tiempo real.

## Servicios que encolan

- `ClienteService`, `ProveedorService`
- `VentaService`, `CuentaCorrienteService`
- `RemitoService`, `CompraService`
- `DocumentoClienteService`
- `CategoriaService`, `ListaPrecioService`
- `ComentarioInternoService`
- `PedidoService`
- `_DualProductoRepository` (productos)

### Colecciones Firestore adicionales (v1.1.2)

| Colección | Clave doc | Notas |
|-----------|-----------|--------|
| `categorias` | nombre normalizado | master de categorías |
| `listas_precios` | nombre normalizado | definiciones de listas |
| `remitos.pagos` | embebido | historial cobros remito |
| `comentarios` | hash tipo+entidad+usuario+fecha+texto | vía cola |
| `pedidos` | `numero` (P-#####) | items embebidos; sin impacto en stock |

### Aún local-only (próximos)

- `movimientos_stock` / `historial_precios` (ledger)
- Branding / numeración de documentos (SharedPreferences)
- Roster completo de usuarios + permisos
- AFIP config

## Planilla de pedidos (v25)

- Tablas: `pedidos`, `pedido_items` (artículo, cantidad, color, observaciones).
- Servicio: `PedidoService` — CRUD + cola sync `entityType: pedido`.
- UI: `PedidosPage` (agrupado por proveedor) + `PedidoFormPage`.
- Proveedores iniciales de planilla: Varios, JK, Cuero Sur, Profeta, Parkegon (`asegurarProveedoresPlanilla`).
- Export: PDF / Excel / impresión (Printing).
- No modifica stock (a diferencia de Compras).

## Pedido sugerido inteligente

- Servicio: `PedidoSugeridoService` — ventas (remitos + ventas) entre fechas + stock.
- Fórmula: `sugerido = max(0, vendido + stockMinimo - stockActual)`.
- Filtros: proveedor, categoría, marca, modelo, color, talle.
- UI: `PedidoSugeridoPage` → envía selección a borradores de `Pedidos` por proveedor.
- Menú: `pedido_sugerido` (permiso módulo `pedidos`).

## Administración de usuarios (solo admin)

- UI + servicio: `UsuariosPage` / `UsuarioService` exigen `AuthService.esAdministrador()`.
- Acciones auditadas en `audit_log`: `CREAR_USUARIO`, `MODIFICAR_USUARIO`, `ACTIVAR_USUARIO`, `DESACTIVAR_USUARIO`, `RESTABLECER_PASSWORD`, `MODIFICAR_PERMISOS`.
- `PermisosPage` / `PermisosService.guardarLoteConAuditoria`: solo admin; el rol `admin` conserva módulos críticos.
- Menú: ítems `usuarios` y `permisos` visibles solo si `esAdministrador()`.
- Restablecer contraseña: hash local + `debeCambiarPassword`; si hay email real, intenta email de reset Firebase.

## Reiniciar sistema

- Servicio: `SystemRestartService.reiniciarServicios()` — solo admin.
- Secuencia: stop SyncQueue → FirestoreSync → Comunicaciones → AutoBackup → start en el mismo orden.
- UI: Configuración → Mantención → **Reiniciar sistema** (diálogo de confirmación).
- No toca SQLite, backups ni sesión. Auditoría: `REINICIAR_SISTEMA` / `REINICIAR_SISTEMA_ERROR`.

## Historial de producto

- `ProductoService.historialCambios`: une `historial_precios` + `movimientos_stock` + `audit_log`.
- UI: `HistorialPreciosPage` con tabs Todo / Precios / Stock / Cambios.
- Al editar stock en la ficha se registra movimiento de stock.

## Borrado / sistema virgen

- `AuthService.verificarPassword` + `confirmarConClave` (diálogo).
- `DataWipeService`: `vaciarProductos`, `vaciarClientes`, `sistemaVirgen` (solo admin).
- Conserva usuarios, permisos y branding. Limpia colecciones Firestore del tenant cuando hay nube.
- Eliminar definitivo de producto también borra en Firestore vía cola.

## Reglas de evolución

1. No cambiar arquitectura general ni reemplazar tecnologías.
2. No refactor masivo ni eliminar módulos.
3. Nueva funcionalidad sobre servicios/modelos/repos existentes.
4. Tras cada módulo estable: actualizar este manual + `CHANGELOG.md`.
5. Prioridad absoluta: confiabilidad de sync multi-dispositivo.

## Próximos módulos (orden)

1. ~~Cola sync + indicador + historial~~
2. ~~Dashboard (accesos rápidos + KPIs)~~
3. ~~Planilla de pedidos a proveedores~~
4. ~~Pedido sugerido inteligente~~
5. ~~Administración de usuarios (solo admin + auditoría)~~
6. ~~Reiniciar sistema (servicios, sin borrar datos)~~
7. ~~Historial de producto ampliado~~
8. ~~Estadísticas~~
9. ~~Inventario (barcode / cámara)~~
10. ~~Alertas automáticas~~

### Siguiente oleada
- ~~Personalizar menú (UX)~~
- ~~Escaneo remitos/compras~~
- ~~Cierre de caja~~
- ~~Alertas CC + etiquetas EAN~~ ← actual

## Clientes — lista y foto

- Lista: `Row` + `maxLines: 1` / ellipsis; avatar `imageProviderDesdePath(foto)` o inicial.
- Acciones (editar, CC, historial, notas, chat, eliminar) en bottom sheet para no comprimir el nombre en Android.
- Campo `clientes.foto` (migración v26). Formulario permite agregar/cambiar/quitar foto.

## Estadísticas

- Página `EstadisticasPage` (menú Análisis, permiso `reportes`).
- Reutiliza `AnalyticsService` (ventas, ganancia, top/bottom productos con filtro de fechas) + consultas de rentabilidad / sin movimiento / stock crítico.
- Gráficos de evolución ventas y compras por mes (`fl_chart`).

## Inventario (conteo)

- Página `InventarioPage` (menú Operaciones, permiso `stock`).
- Flujo: escanear (`ScannerPage` / `mobile_scanner`) o buscar → `ProductoService.buscarPorCodigoBarras` → ingresar stock contado → `StockService.registrarMovimiento` (entrada/salida por delta).
- Sesión local con historial de conteos de la pantalla.

## Alertas automáticas de stock

- `AlertasStockService`: digest diario + aviso por producto (dedupe SharedPreferences).
- Destinos: usuario actual + admins activos.
- Triggers: arranque de `MainShell` y tras `StockService.registrarMovimiento`.
- UI: campana de notificaciones; tap en `tipo: stock` abre Stock / ficha producto.
- Umbral: `stock_minimo` (editable en producto); si es 0, fallback ≤ 5.

## Personalizar menú lateral

- Configuración → Personalizar menú (`MenuLateralConfigPage`).
- Preferencias **locales por dispositivo** (Android ≠ Windows).
- Perfiles: móvil / operaciones / completo. Contador de módulos visibles.
- Nuevos ítems (`inventario`, `estadisticas`, `cierre_caja`, etc.) aparecen en el catálogo y se pueden ocultar.

## Cierre de caja

- `CierreCajaPage` (permiso `reportes`): ventas del día vs cobros del día, breakdown por `medioPago`, detalle de pagos.
- `CuentaCorrienteService.resumenCobrosPorMedio`.

## Etiquetas EAN

- `PdfService.generateEtiquetasPdf`: EAN-13 si `codigoBarras` válido; Code128 si hay barras no-EAN; QR del código interno como fallback.


## Impresión térmica

- `ThermalPrintService` + `ImpresoraTermicaPage` (Configuración).
- ESC/POS vía `esc_pos_utils_plus`; envío con `print_bluetooth_thermal` (sin ubicación).
- Ancho según `BrandingService.papelPdf` (`ticket_58` / `ticket_80`).
- Hooks: remito form (post-guardado), lista remitos, venta/factura.

## Reportes (exportación)

- Página `ReportesPage`: PDF / CSV / Excel por lista (productos, clientes, deudores, etc.).
- **Escritorio (Windows/Linux/macOS):** `FilePicker.saveFile` (“Guardar como…”) + SnackBar con ruta/Abrir. No usar solo `SharePlus` (falla en EXE unpackaged).
- **Android:** `SharePlus` con `mimeType` + `text`; manifest con queries `SEND`/`VIEW`.
- CSV: BOM UTF-8 (`CsvService.exportarCsv`) para Excel.
- Generación completa (consulta DB + archivo) dentro de `_ejecutar` (spinner + SnackBar de error).

## Google Play / Android

- `applicationId`: `com.eltatamanager.app`.
- Ver `docs/PLAY_STORE.md` y `docs/PRIVACY_POLICY.md`.
- Re-registrar la app Android en Firebase con el nuevo package antes de producción.
