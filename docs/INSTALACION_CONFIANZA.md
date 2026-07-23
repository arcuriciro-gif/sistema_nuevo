# Instalación confiable — Tata.Manager

## Por qué Android / Windows avisan “app desconocida”

| Plataforma | Qué ves | Qué hicimos en el repo | Qué falta (fuera del código) |
|---|---|---|---|
| **Android** | “Orígenes desconocidos” / Play Protect | CI de `main` **exige** keystore release (secrets). LEEME aclara firma y checksum. | Subir a Play Store (opcional) y rotar keystore si alguna vez se publicó en git |
| **Windows** | SmartScreen “publicador desconocido” | Publisher unificado (`Matias Arcuri`), LEEME con pasos “Más info → Ejecutar”, SHA256SUMS | Comprar certificado **Authenticode** (OV/EV) y firmar el `.exe` / instalador Inno |

Sin certificado de pago, Windows **siempre** puede mostrar el aviso la primera vez. Eso no se “arregla” solo con código.

## Checklist rápida de prueba (1.2.9+)

1. Instalar APK firmado desde artifact de `main` (LEEME debe decir FIRMA: release).
2. Permitir notificaciones cuando el teléfono lo pida.
3. Desde otra sesión/usuario: enviar un mensaje de chat → debe sonar **y** verse título + texto en la bandeja.
4. Abrir Notificaciones dentro de la app → filas con título y cuerpo (nunca vacías).
5. Modo avión: remito/venta con producto en stock 0 → debe guardar.
6. Configuración → “Permitir stock negativo” viene **ON** por defecto.
7. Windows: descomprimir ZIP completo, abrir con `ABRIR_TATA_MANAGER.bat`, si SmartScreen → Más información → Ejecutar.

## Secrets CI (Android)

- `ANDROID_KEYSTORE_BASE64`
- `ANDROID_KEY_PROPERTIES` (contenido de `key.properties`, `storeFile` relativo al JKS restaurado)

Sin esos secrets, el build de `main` **falla a propósito** para no repartir APKs firmados en debug.
