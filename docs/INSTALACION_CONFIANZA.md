# Instalación confiable — Tata.Manager

## Por qué Android / Windows avisan “app desconocida”

| Plataforma | Qué ves | Qué hicimos en el repo | Qué falta (fuera del código) |
|---|---|---|---|
| **Android** | “Orígenes desconocidos” / Play Protect | CI genera APK siempre; LEEME indica `FIRMA: release` o `FIRMA: DEBUG`. Con secrets → firma release. | Cargar secrets del keystore; opcional Play Store |
| **Windows** | SmartScreen “publicador desconocido” | Publisher unificado (`Matias Arcuri`), LEEME con pasos “Más info → Ejecutar”, SHA256SUMS | Comprar certificado **Authenticode** (OV/EV) y firmar el `.exe` / instalador Inno |

Sin certificado de pago, Windows **siempre** puede mostrar el aviso la primera vez. Eso no se “arregla” solo con código.

## Checklist rápida de prueba (1.2.9+)

1. Instalar APK desde artifact de `main` (ideal: LEEME con `FIRMA: release`; si dice DEBUG, igual sirve para probar).
2. Permitir notificaciones cuando el teléfono lo pida.
3. Desde otra sesión/usuario: enviar un mensaje de chat → debe sonar **y** verse título + texto en la bandeja.
4. Abrir Notificaciones dentro de la app → filas con título y cuerpo (nunca vacías).
5. Modo avión: remito/venta con producto en stock 0 → debe guardar.
6. Configuración → “Permitir stock negativo” viene **ON** por defecto.
7. Windows: descomprimir ZIP completo, abrir con `ABRIR_TATA_MANAGER.bat`, si SmartScreen → Más información → Ejecutar.

## Secrets CI (Android)

- `ANDROID_KEYSTORE_BASE64`
- `ANDROID_KEY_PROPERTIES` (contenido de `key.properties`, `storeFile` relativo al JKS restaurado)

Sin esos secrets el CI **igual genera el APK** (firma debug) y lo marca en LEEME. Con secrets, sale `FIRMA: release`.
