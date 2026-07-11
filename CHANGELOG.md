## [1.2.2] — 2026-07-11

### Remitos
- Botón **Eliminar** (papelera) en cada remito: revierte stock, borra cobros asociados y lo saca de la lista (también sync a Firebase).
- Sigue existiendo **Anular** si solo querés dejarlo anulado sin borrarlo.

### Planilla de pedidos
- Exportar **PDF** y **Excel** visibles: ícono compartir en la barra, botones por proveedor y por pedido.
- En Windows usa “Guardar como…”.

### Cierre de caja
- Corregida la pantalla negra: si falla la carga muestra el error y **Reintentar**.
- Lectura de pagos más tolerante (filas con `ventaId` raro ya no rompen la pantalla).

## [1.2.1] — 2026-07-11

### Acceso tipo Cursor (solicitud + alta)
- Ellos entran con **Google** o **correo** y piden acceso.
- Quedan **PENDIENTE ALTA**; el admin aprueba y asigna rol en Usuarios.
- No hace falta crearles usuario/clave de antemano.
- Teléfono: próximamente.
- Guía: `docs/GOOGLE_LOGIN.md`.

## [1.2.0] — 2026-07-11

### Login con Google
- Botón **Entrar con Google** en el login (Android; Windows intenta provider).
- El admin da de alta el usuario con su **Gmail**; esa cuenta es la que autoriza el acceso.
- Sigue existiendo login con usuario/clave (admin / fallback).
- Guía de configuración Firebase (SHA-1, OAuth, Web client ID): `docs/GOOGLE_LOGIN.md`.

## [1.1.12] — 2026-07-11

### Login usuarios (definitivo)
- Firebase Auth usa siempre email sintético `usuario@tenant.tatastock.app` (el Gmail es solo contacto).
- Así el celular y la PC entran con el mismo usuario/clave.
- Al crear/restablecer se crea o reutiliza la cuenta Auth con esa clave.
- Email del formulario ahora es opcional.
- Si Auth quedó con otra clave vieja, el mensaje indica borrar esa cuenta en Firebase Console.

## [1.1.11] — 2026-07-11

### Usuarios
- Botón **Eliminar** (papelera) en Usuarios: borra de SQLite y Firestore.
- Pide contraseña del admin. No permite autoeliminarse ni borrar el único admin.

## [1.1.10] — 2026-07-11

### Login multi-dispositivo (crítico)
- Bug: usuarios traídos de Firestore se marcaban `activo=false` (`true == 1`) y el APK no dejaba entrar.
- El hash de contraseña ahora viaja en Firestore para validar la misma clave en Android y PC.
- Login local válido aunque Firebase Auth tenga una clave vieja; no bloquea la entrada.

## [1.1.9] — 2026-07-11

### Usuarios / login
- Al crear usuario **ya no se envía mail de reset** (eso cambiaba la clave de Firebase y no podías entrar).
- Restablecer contraseña (admin): solo clave temporal local; instrucciones claras.
- Login: mejores mensajes de error; busca también por email; alinea clave local/nube.

## [1.1.8] — 2026-07-11

### Windows build (VS 18.6+)
- Fix compilación: MSVC STL1011 / coroutines experimentales (`permission_handler_windows`).
- En `windows/CMakeLists.txt`: `_SILENCE_EXPERIMENTAL_COROUTINE_DEPRECATION_WARNINGS`.

## [1.1.7] — 2026-07-11

### Configuración — Borrar todo
- Tarjeta **BORRAR TODO** siempre arriba en Configuración (borde rojo).
- Muestra usuario, rol y versión de la app.
- Si no sos admin: explica que hay que entrar con usuario Administrador.
- Si sos admin: botón rojo **Borrar todo (sistema virgen)** + vaciar productos/clientes.

## [1.1.6] — 2026-07-11

### Reportes — exportación
- En Windows/Linux/macOS: diálogo **Guardar como…** (el share de archivos fallaba en silencio en el EXE).
- SnackBar con ruta del archivo y acción **Abrir**.
- En Android: share con `mimeType` + `text`; queries `SEND`/`VIEW` en el manifest.
- Carga de datos dentro del spinner (`_ejecutar`); errores de DB ya no quedan sin feedback.
- CSV con BOM UTF-8 para que Excel abra bien acentos.

## [1.1.5] — 2026-07-11

### Configuración / sistema virgen
- Bloque **MANTENIMIENTO Y DATOS** arriba en Configuración (admin), con vaciar productos/clientes y sistema virgen.
- Si no sos admin, se explica el rol. Admin siempre tiene acceso a módulos críticos.

## [1.1.4] — 2026-07-11

### Versión visible + sync
- Login muestra `Tata.Manager v1.1.4 (14)` para confirmar que no es un EXE/APK viejo.
- Indicador de sync con tooltip y labels más claros; appId Android actualizado.

# Changelog

Todos los cambios relevantes del proyecto se documentan aquí.

## [1.1.3] — 2026-07-11

### Impresión térmica + Google Play
- Impresión Bluetooth ESC/POS 58/80 mm (`print_bluetooth_thermal` + `esc_pos_utils_plus`), sin permiso de ubicación.
- Configuración → Impresora térmica; ticket de prueba; guardado de MAC.
- Remitos y ventas: acción **Térmica** además de PDF.
- Package Android `com.eltatamanager.app` (ya no `com.example.*`).
- Manifest endurecido: Bluetooth CONNECT/SCAN, cámara opcional, sin cleartext, backup rules, AD_ID removido.
- Release con R8 + `proguard-rules.pro`; firma via `android/key.properties` si existe.
- Política de privacidad (`docs/PRIVACY_POLICY.md`) + pantalla en Configuración.
- Checklist Play: `docs/PLAY_STORE.md`.

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
- **Planilla de pedidos a proveedores**: módulo Pedidos (Varios, JK, Cuero Sur, Profeta, Parkegon), editable todo el día, líneas con artículo/cantidad/color/obs, sync offline, export PDF/Excel/impresión.
- **Pedido sugerido inteligente**: analiza ventas entre fechas (remitos + facturas), filtros por proveedor/categoría/marca/modelo/color/talle; sugiere cantidad = vendido + stock mín − stock; envía a la planilla por proveedor.
- **Usuarios (solo admin)**: menú Usuarios/Permisos solo administrador; cambios de permisos auditados (`MODIFICAR_PERMISOS`); activar/desactivar y restablecer contraseña con registro en auditoría; protege al único admin.
- **Reiniciar sistema**: en Configuración (solo admin), reinicia sync/comunicaciones/auto-backup con confirmación; no borra datos ni cierra sesión; queda en auditoría.
- **Historial de producto**: precios + stock + auditoría (tabs), con usuario y fecha/hora; acceso desde lista de productos.
- **Borrado con clave**: eliminar cliente / producto definitivo y vaciar productos, vaciar clientes o **sistema virgen** (Configuración) exigen contraseña del admin; se conservan usuarios/permisos.
- **Clientes (APK)**: lista con nombre en una sola línea horizontal (sin wrap vertical), avatar con foto o inicial, y acciones en menú “⋯” para no apretar el título.
- Foto de cliente en alta/edición (galería/cámara); columna `clientes.foto` (DB v26).
- **Estadísticas**: módulo en Análisis con período (30/90 días, 6 meses, 1 año): ventas, ganancia real, margen, evolución ventas/compras, más/menos vendidos, rentabilidad, sin movimiento y stock crítico.
- **Inventario (barcode/cámara)**: módulo Operaciones → Inventario; escanea o busca por código/barras, carga stock contado y registra el ajuste en movimientos.
- **Stock mínimo** editable en ficha de producto (dispara alertas cuando stock ≤ mínimo).
- **Alertas automáticas de stock**: al abrir la app y tras movimientos, crea notificaciones internas (`tipo: stock`) para el usuario y admins (digest diario + por producto); al tocarlas abren Stock o la ficha del producto.
- **Personalizar menú**: título claro, contador de visibles, subtítulos oculto/visible, perfil **Operaciones** además de móvil/completo.
- **Escaneo en Remitos y Compras**: match exacto por código de barras agrega el ítem al instante.
- **Cierre de caja**: ventas del día, cobros por medio de pago, efectivo y ganancia (menú Análisis; se puede ocultar).
- **Alertas de cuenta corriente**: notificación diaria en la campana; al tocarla abre deudores.
- **Etiquetas**: si el producto tiene `codigoBarras`, imprime EAN-13 (o Code128); si no, QR del código interno.



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
