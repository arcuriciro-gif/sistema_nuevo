# Google Play — checklist Tata.Manager

Package ID: **`com.eltatamanager.app`**  
Versión en `pubspec.yaml` (versionName / versionCode).

## Antes de subir el AAB

1. **Firebase Console**
   - Agregar app Android con package `com.eltatamanager.app`.
   - Descargar el nuevo `google-services.json` y reemplazar `android/app/google-services.json`.
   - (El archivo del repo ya apunta a ese package; si el proyecto Firebase no tiene esa app, Auth/Firestore fallarán hasta registrarla.)

2. **Firma de release**
   - Generar keystore de upload.
   - Copiar `android/key.properties.example` → `android/key.properties` y completar.
   - No commitear `key.properties` ni el `.jks`.

3. **Build**
   ```bash
   flutter build appbundle --release
   ```
   Salida: `build/app/outputs/bundle/release/app-release.aab`

4. **Play Console**
   - Política de privacidad: publicar `docs/PRIVACY_POLICY.md` en una URL HTTPS pública y pegarla en la ficha.
   - Completar **Data safety** (ver sección abajo).
   - Content rating, público objetivo, países.
   - Declarar que **no** se usa Advertising ID.
   - Permisos: Cámara (escáner/fotos), Bluetooth (impresora térmica, sin ubicación).

## Data Safety (resumen)

| Dato | Recolecta | Comparte | Finalidad |
|------|-----------|----------|-----------|
| Info de cuenta (usuario/rol) | Sí (local + Firebase Auth) | No (salvo sync propio) | Funcionalidad app |
| Datos financieros/comerciales | Sí | Sync Firebase del negocio | Gestión |
| Fotos / archivos | Sí (opcionales) | Storage del tenant | Catálogo / docs |
| Advertising ID | **No** | — | — |
| Ubicación | **No** | — | — |

Cifrado en tránsito: sí (HTTPS/Firebase).  
Eliminación: vía administrador de la app / desinstalación (local).

## Cambios técnicos ya hechos en el repo

- `applicationId` / `namespace` → `com.eltatamanager.app` (ya no `com.example.*`).
- Manifest: Bluetooth sin ubicación, cámara opcional, sin cleartext, backup rules, AD_ID remove.
- R8/minify release + `proguard-rules.pro`.
- Firma release si existe `android/key.properties`.
- Política en `docs/PRIVACY_POLICY.md` + pantalla en Configuración.

## Impresión térmica

- Configuración → **Impresora térmica Bluetooth**.
- Emparejar la impresora en Ajustes del celular, luego elegirla en la app.
- Remitos / ventas: acción **Térmica** (además de PDF).
- Ancho 58/80 mm según plantilla de impresión (`papelPdf`).
