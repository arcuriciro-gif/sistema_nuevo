# Changelog

Todos los cambios relevantes del proyecto se documentan aquí.

## [1.1.1] — 2026-07-11

### Cobro parcial de remitos
- Remitos ahora tienen `totalPagado` / `saldoPendiente`.
- En cuenta corriente → Remitos → **Cobrar** permite pagar una parte o el total.
- La lista de deudores usa el saldo real del remito (no siempre el total).

### Fotos y notas entre dispositivos
- Al subir productos / catálogo, las fotos locales se suben a Firebase Storage (URL).
- Comentarios internos de productos se sincronizan por Firestore (clave = código de producto).
- Notas internas del producto viajan con el documento del producto en la nube.

### Sync
- Sin tope artificial de 2000 productos.
- Botón **Subir catálogo** para igualar dispositivos.

## [1.1.0] — 2026-07-10

### Prioridad: sincronización confiable (offline → online)

#### Agregado
- Cola persistente SQLite `sync_queue` + historial técnico `sync_history` (schema v23).
- `SyncQueueService`: encolado con deduplicación, reintentos con backoff, confirmación de envío y recuperación ante fallos.
- Indicador visible de estado en la barra principal (desktop y móvil):
  - Sincronizado / Pendiente / Sin conexión / Error / Sincronizando…
- Pantalla **Sincronización** (tap en el indicador): cola pendiente + historial de auditoría técnica.
- Long-press en el indicador: reintento inmediato de ítems fallidos.

#### Integrado (sin cambiar arquitectura)
- Encolado outbound en: clientes, proveedores, ventas, remitos, compras, documentos PDF, productos (dual-write).
- Arranque/parada de la cola junto al login/logout (`AuthService`).
- `FirestoreSyncService.runOutboundStrict` para que la cola detecte fallos reales.

#### Comportamiento
- Con Internet y sesión Firebase: cambios se reflejan en tiempo real (listeners existentes) y el outbound se confirma o encola.
- Sin Internet / sin Auth remoto: la app sigue operando en SQLite; nada se pierde; al reconectar la cola vacía automáticamente.
- Deduplicación por `entityType:entityId:operation` evita duplicados al reintentar.

### Notas
- No se reemplazó Firebase ni SQLite; la cola se apoya sobre los `subir*` / `eliminar*` existentes.
- Los módulos siguientes (dashboard, pedidos, etc.) quedan pendientes hasta validar estabilidad de sync.
