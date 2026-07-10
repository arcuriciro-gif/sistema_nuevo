# Manual de uso — Tata.Manager

Guía práctica para usar el sistema en **PC (Windows)** y **celular (Android)**.

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
1. Copiá **toda** la carpeta `Release` (no solo el `.exe`).
2. Ejecutá `sistema_nuevo.exe` desde esa carpeta.
3. No borres los `.dll` ni las carpetas que van junto al ejecutable.
4. En esa misma carpeta vas a encontrar **`MANUAL_DE_USO.pdf`** (manual en PDF).

### Manual dentro de la app
Menú **Manual de usuario**: se lee en pantalla, y también podés abrir/compartir el PDF.

### Primera vez
- Usuario por defecto suele ser `admin` (la contraseña la define quien instaló el sistema).
- Si pide cambiar contraseña, usá al menos **6 caracteres**.

---

## 3. Inicio de sesión

1. Abrí la app.  
2. Ingresá **usuario** y **contraseña**.  
3. Si Firebase está activo, el login también conecta la sincronización en la nube.

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

*Manual correspondiente a Tata.Manager (sistema_nuevo). Actualizado con sync multi-dispositivo, Archivo PDF, Mi perfil, alerta sin stock y plantilla de impresión.*
