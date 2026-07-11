# Política de privacidad — Tata.Manager (EL TATA Manager)

**Última actualización:** 11 de julio de 2026  
**Aplicación:** Tata.Manager (`com.eltatamanager.app`)  
**Contacto:** el administrador del negocio que opera la app / soporte del desarrollador.

Esta política describe qué datos trata la aplicación de gestión comercial **Tata.Manager** (stock, ventas, clientes, sync en la nube e impresión).

## 1. Quién es el responsable

La app es un sistema de gestión para un negocio. El **responsable del tratamiento** de los datos de clientes, ventas y stock es el **comercio/usuario administrador** que instala y configura la aplicación. El desarrollador provee el software; no vende publicidad ni perfiles de usuarios finales a terceros.

## 2. Datos que puede tratar la app

Según el uso que haga el negocio:

| Categoría | Ejemplos | Finalidad |
|-----------|----------|-----------|
| Cuenta de usuario | Usuario, nombre, rol, foto de perfil | Acceso y auditoría |
| Datos comerciales | Productos, precios, stock, clientes, proveedores, ventas, remitos, pagos | Operación del negocio |
| Archivos / medios | Fotos de productos o clientes, PDFs, logos | Catálogo, documentos, branding |
| Dispositivo | Preferencias locales del menú, impresora Bluetooth elegida | Funcionamiento offline y UX |
| Red / nube | Datos sincronizados vía Firebase (Auth, Firestore, Storage) cuando hay conexión | Multi-dispositivo y respaldo |

## 3. Permisos del dispositivo (Android)

- **Internet:** sync con Firebase y actualizaciones de datos.
- **Cámara:** escanear códigos de barras / QR e (opcional) tomar fotos.
- **Bluetooth (CONNECT / SCAN):** conectar a **impresoras térmicas**. **No se usa la ubicación** para Bluetooth.
- **Galería / archivos (vía selector del sistema):** elegir imágenes o exportar/compartir documentos.

La app **no solicita** el permiso de ubicación para imprimir. **No usa Advertising ID** con fines publicitarios.

## 4. Servicios de terceros

Si el negocio configura Firebase:

- **Firebase Authentication, Cloud Firestore, Firebase Storage** (Google).  
  Aplican las políticas de Google/Firebase. Los datos quedan en el proyecto Firebase del negocio.

## 5. Conservación y eliminación

- Los datos viven en la base local del dispositivo y, si hay sync, en Firebase del tenant.
- El administrador puede borrar productos, clientes o realizar un “sistema virgen” (conservando usuarios/permisos según la configuración).
- Desinstalar la app elimina los datos locales del dispositivo; no borra automáticamente la nube del proyecto Firebase (hay que limpiarla desde la consola o funciones de la app).

## 6. Seguridad

- Comunicación con Firebase por HTTPS (sin tráfico cleartext).
- Contraseñas y roles gestionados por el módulo de usuarios.
- Backup automático de Android excluye bases y preferencias sensibles cuando aplica.

## 7. Menores

La app está pensada para uso comercial / laboral. No está dirigida a menores de 13 años.

## 8. Cambios

Podemos actualizar esta política. La fecha de “última actualización” indica la versión vigente. En Play Console debe publicarse la URL pública de esta política (o una página web equivalente).

## 9. Contacto / derechos

Los clientes finales del comercio deben ejercer derechos (acceso, rectificación, baja) ante el **comercio**.  
Para temas técnicos de la app, contactar al administrador que la desplegó.

---

**Nota para Play Console (Data Safety):** declarar recolección de datos financieros/comerciales, fotos, identificadores de cuenta; cifrado en tránsito; no venta de datos; no publicidad personalizada; eliminación disponible vía administrador.
