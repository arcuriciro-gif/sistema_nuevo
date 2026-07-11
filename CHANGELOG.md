# Changelog

Todos los cambios relevantes del proyecto se documentan aquí.

## [1.1.2] — 2026-07-11

### Dashboard / Inicio (Windows EXE)
- KPIs más compactos: iconos chicos, más columnas en pantallas anchas, menos scroll.
- Sidebar más densa (logo y filas más chicas) para menos movimiento de mouse.
- **Valor del stock a costo** además del valor a precio de venta (Inicio, Dashboard y Productos).
- **Todos los KPIs son clickeables** y abren la página correspondiente (APK y EXE).
- Productos sin barra KPI: layout tipo Clientes (buscador + actualizar + volver).
- En la lista de productos: foto del artículo y solo precios de listas activas (con su nombre).
- Listas de precios: renombrar + editar % (más claro en la UI).
- Botón Guardar fijo arriba de la barra de sistema Android (no se pisa con gestos).
- Badge de Notificaciones solo cuenta notificaciones reales (no mensajes de chat).
- **Menú lateral personalizable** por dispositivo (Android/Windows): Configuración → Personalizar menú. Perfiles “móvil” y “completo”.
- Notas internas: input con SafeArea (no se pisa con Android); sin duplicados al sincronizar.
- Fotos de producto: se persisten y suben a la nube; la lista muestra la foto (o inicial si no hay).
- **Botón Inicio** en todas las pantallas (ícono casa en el AppBar): un toque cierra el stack y vuelve al inicio.
- **Actualización automática** de Inicio y listas al llegar cambios (sync/local), sin timer de 1s ni parpadeo de loading. Cola de subida cada 4s.

### Sync — cobertura ampliada
- Categorías y listas de precios: sync bidireccional + cola offline.
- Comentarios internos: ahora pasan por `SyncQueueService` (no se pierden offline).
- Pagos de remito (`ventaId=0`): viajan embebidos en el documento remito.
- Al recibir ventas remotas se recalcula el saldo del cliente.

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
