# Google Play y confianza — Tata.Manager

Package ID: **`com.eltatamanager.app`**  
Versión: la de `pubspec.yaml` (hoy `1.2.4+27`).

---

## 1. Por qué Android dice “app no segura”

Eso aparece cuando instalás el **APK a mano** (WhatsApp, Drive, cable).  
Play Protect no conoce esa instalación → aviso de “origen desconocido / puede ser dañina”.

| Forma de instalar | Confianza |
|-------------------|-----------|
| APK por fuera (ahora) | Aviso casi siempre |
| APK firmado release (keystore propio) | Un poco mejor, **sigue el aviso** |
| **Google Play** (o pista interna de Play) | De confianza: sin ese cartel |

**Conclusión:** para que sea “de confianza” de verdad, hay que publicarla en **Play Console** (aunque sea solo para tu equipo al principio).

---

## 2. Firma de release (obligatoria para Play)

En tu PC (una sola vez; **guardá el keystore en un lugar seguro**):

```bat
cd A:\PROYECTOS\sistema_nuevo_git\android
mkdir keystore
keytool -genkey -v -keystore keystore\upload-keystore.jks -keyalg RSA -keysize 2048 -validity 10000 -alias upload
```

Copiá y completá:

```bat
copy key.properties.example key.properties
```

Ejemplo `android/key.properties`:

```
storePassword=TU_CLAVE
keyPassword=TU_CLAVE
keyAlias=upload
storeFile=../keystore/upload-keystore.jks
```

**No subas** `key.properties` ni el `.jks` a Git.

Build para Play:

```bat
flutter build appbundle --release
```

Archivo: `build\app\outputs\bundle\release\app-release.aab`

---

## 3. Subir a Play Store (pasos)

1. Creá cuenta en [Google Play Console](https://play.google.com/console) (pago único de registro).
2. Crear app → nombre **Tata.Manager** → app de negocios / productividad.
3. Completá ficha: ícono, capturas, descripción corta/larga.
4. **Política de privacidad:** publicá `docs/PRIVACY_POLICY.md` en una URL HTTPS (GitHub Pages, tu web, Notion público, etc.) y pegá el link.
5. **Data safety:** usar la tabla de abajo.
6. Content rating, público (18+ / empresas), países.
7. Subí el **AAB** a:
   - **Prueba interna** (hasta 100 emails) → sin revisión larga; ideal para vos y empleados.
   - Luego **cerrada / abierta / producción**.
8. En Firebase Console → app Android → agregá el **SHA-1** de la firma de Play (App signing key certificate) además del de upload.

### Data Safety (resumen)

| Dato | Recolecta | Comparte | Finalidad |
|------|-----------|----------|-----------|
| Cuenta (usuario/rol) | Sí | Sync propio (Firebase) | Login |
| Datos comerciales | Sí | Firebase del negocio | Gestión |
| Fotos / archivos | Opcional | Storage del tenant | Catálogo |
| Advertising ID | **No** | — | — |
| Ubicación | **No** | — | — |

---

## 4. Muy importante: “cualquier usuario” sin usar TUS datos

Hoy la app apunta a **tu proyecto Firebase** y al tenant por defecto `tata_stock`.

Si publicás el mismo APK en Play **tal cual**:

- Cualquiera que la instale podría terminar en **tu misma nube** → **ve/mezcla tus datos**.  
  **No hagas producción pública así.**

### Opciones reales

#### A) Solo tu negocio (recomendado ahora)
- Play en **prueba interna / cerrada** (emails de tu equipo).
- O APK firmado solo para tus celulares.
- Un solo Firebase = tus datos. Correcto.

#### B) Varios comercios / “cualquiera” en Play (SaaS)
Hay que separar negocios:

1. **Alta de negocio** al primer uso (nombre del local).
2. Se crea un **`tenantId` único** (ej. `negocio_abc123`).
3. Todos los datos van a `tenants/{tenantId}/…` — **nunca** al tenant de otro.
4. Idealmente: cada cliente con su propio proyecto Firebase, **o** un backend multi-tenant con reglas que solo lean su tenant.

Eso es un desarrollo aparte (onboarding + reglas Firestore + posiblemente billing).  
Hasta que exista, **no publiques en producción abierta**.

#### C) Venta “caja cerrada”
- Les instalás vos el APK/EXE y configurás **su** Firebase / su tenant.
- No hace falta Play pública.

---

## 5. Checklist corto

- [ ] Keystore de upload creado y respaldado  
- [ ] `key.properties` local (no en Git)  
- [ ] `flutter build appbundle --release`  
- [ ] Política de privacidad en URL pública  
- [ ] Play Console → prueba interna primero  
- [ ] SHA-1 de Play en Firebase  
- [ ] **No** producción abierta mientras el tenant sea el tuyo fijo  

---

## 6. Cambios técnicos ya en el repo

- `applicationId` = `com.eltatamanager.app`
- Manifest endurecido (sin cleartext, sin AD_ID, Bluetooth sin ubicación)
- R8/minify en release
- Firma release si existe `android/key.properties`
- Política: `docs/PRIVACY_POLICY.md`
