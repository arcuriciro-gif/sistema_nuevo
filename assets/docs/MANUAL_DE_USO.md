# Manual de uso — Tata.Manager

Guía práctica para usar el sistema en **PC (Windows)** y **celular (Android)**.

Este manual se puede abrir **antes de iniciar sesión** (botón en la pantalla de login) o desde el menú **Manual de usuario** una vez dentro.

---

## Primeros pasos: registro y correo

Leé esto si es la primera vez que usás el sistema o si te crearon un usuario nuevo.

### Quién crea las cuentas
No hay auto-registro público. El **administrador** da de alta a cada persona en **Usuarios → Nuevo**.

### Pasos para el usuario nuevo
1. El admin te crea con: nombre, **usuario**, **email real**, rol y una contraseña temporal.  
2. Te llega un **correo de confirmación / bienvenida** (revisá también spam).  
3. Abrí la app e iniciá sesión con el **usuario** y la **contraseña temporal**.  
4. Si la app pide cambiar la clave, elegí una de **al menos 6 caracteres**.  
5. Entrá a **Mi perfil**: completá foto, nombre y, si hace falta, el email.  
6. Para sincronizar con otros dispositivos (PC + celular), tenés que estar logueado con Firebase en **cada** equipo.

### Sobre el correo
- Tiene que ser un **email real** (Gmail, Outlook, etc.), no inventado.  
- Si no llega: spam, email mal escrito, o Firebase Auth/Templates sin configurar (ver sección 17).  
- El correo sirve para recuperación de clave y para vincular la cuenta en la nube.

### Primera vez en una PC nueva (admin)
- Usuario por defecto suele ser `admin` (la contraseña la define quien instaló).  
- Después creá el resto de usuarios con email real.

---

## 1. Qué es Tata.Manager

Sistema de gestión para:

- Productos, precios y stock  
- Ventas / remitos  
- Clientes y cuenta corriente  
- Compras y proveedores  
- PDFs, reportes y comunicaciones internas  

Varios usuarios pueden trabajar a la vez (admin, encargado, empleado). Si están **logueados con Firebase**, lo que hace uno se refleja en los demás dispositivos.

---

## 2. Instalación

### Android
1. Instalá el archivo `app-release.apk`.
2. Si el teléfono bloquea la instalación, permití “orígenes desconocidos” para ese archivo.

### Windows
1. En la PC de desarrollo, después de compilar, usá la carpeta de la **raíz del proyecto**:
   - `Instalador_Windows\`
2. Ahí está el `.exe`, el PDF del manual y `ABRIR_TATA_MANAGER.bat`.
3. Copiá **toda** esa carpeta a la otra PC (pendrive, red, zip).
4. En la otra PC: doble clic en `ABRIR_TATA_MANAGER.bat` o en `sistema_nuevo.exe`.

**No muevas solo el `.exe`** a otra carpeta: se rompe. Tiene que ir con los `.dll` y la carpeta `data`.

Cómo regenerar `Instalador_Windows` en la PC de desarrollo:
```bat
flutter build windows --release
scripts\preparar_instalador_windows.bat
```
(El build también puede dejarla armada sola al compilar.)

### Manual dentro de la app
- **Antes de iniciar sesión:** en la pantalla de login tocá **Ver instrucciones (PDF / manual)**.  
- **Ya logueado:** menú **Manual de usuario**.  
Se lee en pantalla y también podés abrir/compartir el PDF. En Windows el PDF también está junto al `.exe`.

### Primera vez
Ver la sección **Primeros pasos: registro y correo** al inicio de este manual.

---

## 3. Inicio de sesión

1. Abrí la app.  
2. Si necesitás ayuda, abrí el **manual/PDF** desde el botón debajo del login (no hace falta entrar).  
3. Ingresá **usuario** y **contraseña**.  
4. Si Firebase está activo, el login también conecta la sincronización en la nube.

**Importante:** sin login Firebase en un dispositivo, ese equipo trabaja solo con su base local y **no** se entera de lo que pasa en los otros.

---

## 4. Pantalla de Inicio

Resumen rápido:

- Cantidad de productos, stock, valor de stock  
- **Sin stock** (tocá la tarjeta → lista de productos sin stock)  
- Clientes, remitos, ventas/compras del mes  
- Cuentas por cobrar → **Ver detalle**

Usá el ícono de **actualizar** (flecha circular) para refrescar.

---

## 5. Productos

### Alta / edición
1. Menú **Productos** → **Nuevo**.  
2. Completá código, descripción, marca, stock, costo y precios.  
3. Podés cargar **foto** del producto (se sincroniza a la nube).  
4. Guardá.

### Buscar
- Por código, barras, nombre, marca o proveedor.  
- Filtros de marca / proveedor.  
- Escáner de código de barras (ícono QR).

### Alerta sin stock
- Tocá la tarjeta **Sin stock**.  
- Se abre la lista solo con esos productos.  
- **Ver todos** quita el filtro.

### Papelera
- Al eliminar, el producto va a **Papelera** (se puede recuperar).

### Categorías y listas de precios
- **Categorías**: organizar el catálogo.  
- **Listas de precios**: precios por lista (mayorista, etc.).

### Importar productos desde Excel
1. Menú **Centro de importaciones** → **Plantillas Excel**.  
2. Descargá **plantilla_productos.xlsx**.  
3. Completá las columnas **en este orden** (no renombres la primera fila):

| # | Columna | Notas |
|---|---------|--------|
| 1 | Codigo | Obligatorio. Si ya existe, se actualiza |
| 2 | Descripcion | Nombre / detalle del producto |
| 3 | Marca | |
| 4 | Categoria | |
| 5 | Proveedor | |
| 6 | Stock | Cantidad |
| 7 | Costo | Precio de costo |
| 8 | Precio1 | Precio de venta principal |
| 9 | Precio2 | Segunda lista |
| 10 | Precio3 | Tercera lista |
| 11 | CodigoBarras | Opcional |

4. Borrá la fila de ejemplo y guardá.  
5. **Importar Productos** → seleccioná el archivo.

También hay CSV de referencia en `Instalador_Windows/plantillas` y en `assets/templates`.

---

## 6. Vender (lo más usado)

### Venta rápida
1. **Venta Rápida**.  
2. Agregá productos (búsqueda o escáner).  
3. Confirmá → se genera un **remito** (cliente MOSTRADOR) y baja el stock.  
4. El PDF queda en **Archivo PDF** para enviarlo después.

### Remitos
1. **Remitos** → nuevo remito.  
2. Elegí cliente y productos.  
3. Guardá.  
4. Podés imprimir o compartir.  
5. El PDF se archiva por cliente automáticamente.

### Ventas / Facturas / Presupuestos / Notas
Desde el menú correspondiente según el tipo de documento.  
Misma lógica: cliente + ítems → guardar → PDF / impresión.

---

## 7. Clientes y cuenta corriente

### Clientes
- Alta con nombre, teléfono, dirección, CUIT, etc.  
- Historial de operaciones del cliente.

### Importar clientes desde Excel
**Centro de importaciones** → **Plantillas Excel** → plantilla de clientes.

Orden: Nombre, Apellido, Telefono, WhatsApp, Email, Direccion, Localidad, Provincia, CUIT, CondicionIVA, Descuento, LimiteCuenta, Observaciones.

Si el **CUIT** coincide (o Nombre+Apellido), se actualiza; si no, se crea.

### Cuenta corriente
- Lista de deudores (incluye **ventas** y **remitos sin cobrar**).  
- Desde ahí podés ver quién debe y cuánto.

---

## 8. Archivo PDF (enviar desde el celular)

1. Generás el remito/factura en la **PC**.  
2. El PDF se guarda en la nube, **por cliente**.  
3. En el celular abrís **Archivo PDF**.  
4. Entrás a la carpeta del cliente.  
5. Tocá **compartir** → WhatsApp, mail, etc.

Así no hace falta regenerar el PDF en el teléfono.

---

## 9. Stock y compras

### Stock
- Movimientos (entradas / salidas / ajustes).  
- Pestaña **Alertas**: productos con stock bajo.

### Compras
- Registrá compra a proveedor.  
- Sube stock y actualiza costo.  
- Se sincroniza con los otros dispositivos (si hay Firebase).

### Proveedores
- Alta y edición de proveedores.

### Importar proveedores desde Excel
**Centro de importaciones** → plantilla de proveedores.

Orden: Nombre, Contacto, Telefono, WhatsApp, Email, Web, CUIT, CondicionesComerciales, TiempoEntrega, Observaciones.

### Comparar costos con rangos de talle
Si tenés cada talle como producto aparte (`PAPI FEBO BLANCA 41`) y el proveedor manda rangos (`PAPI FEBO BLANCA 39 AL 42 $10000`):

1. **Centro de importaciones** → **Plantillas Excel** → *Lista proveedor (rangos de talle)*.  
2. Completá: `Articulo` + `Costo` (ej. `PAPI FEBO BLANCA 39 AL 42` / `10000`).  
3. **Comparar Costos** → cargá el archivo.  
4. El sistema busca productos cuyo nombre base coincida y cuyo talle esté en el rango, y propone actualizar el **costo**.  
5. Revisá y tocá **ACTUALIZAR COSTOS**.

Formatos de rango: `39 AL 42`, `39 A 42`, `39-42`.

---

## 10. Sincronización multi-dispositivo

Para que PC y celulares vean lo mismo:

| Requisito | Detalle |
|-----------|---------|
| Mismo negocio | Mismo tenant Firebase (por defecto `tata_stock`) |
| Login | Cada persona con su usuario, en cada dispositivo |
| Internet | Necesaria para subir/bajar cambios |

Se sincroniza, entre otras cosas:

- Productos, precios, stock, fotos  
- Clientes y proveedores  
- Remitos, ventas, compras  
- Archivo PDF  
- Comunicaciones  

Si un equipo nunca se logueó a Firebase, solo tiene su base local.  
Para clonar datos sin nube: usá **Respaldo** (exportar/importar `.db`).

---

## 11. Usuarios y permisos

### Mi perfil (cada usuario)
Menú **Mi perfil** o tocando tu avatar:

- Foto  
- Nombre para mostrar  
- Usuario de login  
- Contraseña  
- Email  

### Alta de usuario (solo admin)
1. **Usuarios** → **Nuevo**.  
2. Nombre, usuario, **email real**, rol, contraseña temporal.  
3. Guardar → llega mail de confirmación (si Firebase Auth está bien configurado).  
4. El nuevo usuario entra y cambia su contraseña / foto en **Mi perfil**.

### Roles típicos
- **Admin**: todo (usuarios, permisos, configuración).  
- **Encargado / Empleado**: según lo definido en **Permisos**.

### Permisos
Matriz por rol y módulo (ver, crear, editar, eliminar).

---

## 12. Comunicaciones

- Chats internos entre usuarios.  
- Compartir fichas (producto, remito, etc.).  
- Campanita de **notificaciones** en la barra superior.

---

## 13. Reportes e inteligencia

- **Reportes**: listados exportables a PDF.  
- **Inteligencia comercial**: rankings, márgenes, etc.  
- **Etiquetas**: impresión de etiquetas con código.

---

## 14. Configuración e impresión

### Configuración
Datos del negocio: nombre, logo, teléfono, email de la empresa, etc.

### Plantilla de impresión
- Encabezado, pie, logo, firma, sello.  
- **Paleta de colores** del encabezado.  
- Opción **Transparente**.  
- Switch **Impresión en blanco y negro** (encabezado sin color, ideal para impresoras B/N).  
- Vista previa PDF antes de guardar.

---

## 15. Respaldo

1. Menú **Respaldo**.  
2. **Exportar** la base (archivo `.db`) y guardalo en un lugar seguro.  
3. En otra PC/celular: **Importar** ese archivo para clonar los datos.

Recomendación: hacer respaldo periódico aunque uses Firebase.

---

## 16. Auditoría

Registro de cambios importantes (altas, bajas, precios, usuarios, etc.) para saber quién hizo qué.

---

## 17. Configurar el mail en Firebase (admin técnico)

Para que al crear un usuario llegue el email:

1. [Firebase Console](https://console.firebase.google.com) → proyecto **tata-stock-8631e**.  
2. **Authentication** → **Sign-in method** → activar **Correo/Contraseña**.  
3. **Templates**: dejar activos *Password reset* y *Email verification*.  
4. Al dar de alta un usuario, usar un **email real** (Gmail, etc.).  

Si no llega: revisar spam y que el email esté bien escrito.

---

## 18. Generar APK y EXE (para quien compila)

```bash
# Android
flutter build apk --release
# → build/app/outputs/flutter-apk/app-release.apk

# Windows
flutter build windows --release
# → copiar TODA la carpeta build/windows/x64/runner/Release/
```

Instalá la misma versión (misma rama/merge) en todos los equipos para que las funciones nuevas coincidan.

---

## 19. Flujo diario sugerido

1. Abrir app y loguearse.  
2. Revisar **Inicio** / alertas de sin stock.  
3. Vender con **Venta rápida** o **Remitos**.  
4. Si hace falta, cobrar en **Cuenta corriente**.  
5. Enviar PDF desde **Archivo PDF** (celular).  
6. Cargar compras cuando llegue mercadería.  
7. De vez en cuando: **Respaldo**.

---

## 20. Problemas frecuentes

| Problema | Qué revisar |
|----------|-------------|
| El celular no ve lo de la PC | Login Firebase en ambos; misma versión de app; internet |
| No llega el mail de alta | Email real; Authentication + Templates en Firebase; spam |
| No abre el .exe en otra PC | Copiar carpeta Release completa |
| Productos sin foto en el otro equipo | Subir foto estando logueado (para que vaya a la nube) |
| “Hay X sin stock” y no los encuentro | Tocar la tarjeta **Sin stock** |

---

## 21. Contacto interno

Para dudas del negocio (precios, roles, quién puede vender a cuenta): consultá al **administrador** del sistema.

Para temas técnicos de Firebase / instalación: quien mantenga el proyecto en GitHub / la PC de desarrollo.

---

*Manual correspondiente a Tata.Manager (sistema_nuevo). Actualizado con sync multi-dispositivo, Archivo PDF, Mi perfil, alerta sin stock, plantilla de impresión, plantillas Excel de importación, rangos de talle y manual accesible antes del login.*
