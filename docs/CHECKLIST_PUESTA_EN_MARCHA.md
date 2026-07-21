# Checklist operativa — Firebase / puesta en marcha

Proyecto: **tata-stock-8631e** · App Android actual: **`com.example.sistema_nuevo`**

Completar en este orden. No saltear pasos.

## 1. Authentication
- [ ] Provider **Email/Password** habilitado
- [ ] Provider **Google** habilitado (si usan “Continuar con Google”)

## 2. Android SHA (Google Login)
En Firebase → Project settings → app **`com.example.sistema_nuevo`** (no `com.eltatamanager.app`):

- [ ] SHA-1 release: `A8:E0:3B:99:65:68:4C:7D:21:AC:DC:2A:EA:FF:BD:C8:5F:B4:E4:EF`
- [ ] (Opcional) SHA-1 debug CI: ver `docs/FIREBASE_GOOGLE_LOGIN.md`
- [ ] Esperar 2–5 minutos tras guardar

## 3. Firestore
- [ ] Firestore Database creado (modo production)
- [ ] **Antes de publicar rules:** al menos un dispositivo con la app nueva conectado a la nube (crea `members/{uid}`)
- [ ] Publicar reglas de **`firestore.rules`** de este repo  
  `firebase deploy --only firestore:rules`
  (Fase 3 agrega colección `stock_ops` — hay que republicar si ya tenías rules viejas)
- [ ] Indexes: crear los que Console solicite al usar queries

## 4. Storage (fotos / PDF)
- [ ] Storage habilitado
- [ ] Publicar **`storage.rules`** (después de membership)  
  `firebase deploy --only storage`
- Detalle: `docs/FIREBASE_STORAGE.md`

## 5. Instalación en dispositivos
- [ ] Windows: ZIP `Instalador_Windows` → `ABRIR_TATA_MANAGER.bat`
- [ ] Android: `TataManager.apk` del artifact `Instalador_Android`
- [ ] Primero ingreso: `admin` / `admin123` → **cambiar contraseña** (obligatorio)
- [ ] Guardar el **código de recuperación** que muestra la app (Configuración / primer cambio)
- [ ] Chip **En la nube** en PC y celular

## 6. Prueba de sync (5 minutos)
- [ ] Crear/editar un cliente en PC → aparece en celular
- [ ] Editar precio de producto en celular → aparece en PC
- [ ] Subir foto de producto → se ve en el otro dispositivo

## 7. Seguridad post-setup
- [ ] Confirmar que ya no entra con `admin123` tras cambiar la clave (recovery default desactivado)
- [ ] Código de recuperación guardado fuera del local
- [ ] Usuarios empleados creados con email real si usan Google

## Notas
- El package `com.eltatamanager.app` en Console **no** es el del APK actual.
- Windows: preferir usuario/contraseña (Google en Windows es frágil).
- Si el chip dice “Solo local” / “Sin sesión nube”: Configuración → Activar sincronización y volver a entrar.
