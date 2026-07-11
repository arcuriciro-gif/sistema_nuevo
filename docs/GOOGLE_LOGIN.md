# Login con Google (Tata.Manager)

Versión con botón **Entrar con Google**: `1.2.0+`.

## Cómo funciona en la app

1. El **admin** crea el usuario y carga su **Gmail exacto**.
2. En el celular, la persona toca **Entrar con Google** y elige esa cuenta.
3. Si el Gmail coincide con un usuario activo → entra y sincroniza.
4. Si no está dado de alta → mensaje pidiendo al admin que lo cree con ese email.
5. En la PC el admin puede seguir entrando con `admin` / clave.

## Configuración obligatoria en Firebase (una vez)

Sin esto, Google Sign-In falla (tu `google-services.json` hoy tiene `oauth_client: []`).

### 1) Activar proveedor Google
Firebase Console → **Authentication** → **Sign-in method** → **Google** → Activar → Guardar.

### 2) SHA-1 de Android
En la PC de desarrollo:

```bat
cd A:\PROYECTOS\sistema_nuevo_git\android
gradlew signingReport
```

O con keytool (debug):

```bat
keytool -list -v -keystore %USERPROFILE%\.android\debug.keystore -alias androiddebugkey -storepass android -keypass android
```

Copiá el **SHA-1** (y SHA-256 si pide).

Firebase Console → Project settings → Tu app Android `com.eltatamanager.app` → **Add fingerprint** → pegá SHA-1.

Si firmás release con `android/key.properties`, también agregá el SHA-1 del keystore de release.

### 3) Descargar de nuevo `google-services.json`
Project settings → tu app Android → **Download google-services.json**  
Reemplazá `android/app/google-services.json`.

### 4) Web client ID
Authentication → Google → **Web client ID** (termina en `.apps.googleusercontent.com`).

Pegalo en `lib/firebase_options.dart`:

```dart
static const String googleWebClientId =
    'TU-ID.apps.googleusercontent.com';
```

### 5) Rebuild

```bat
flutter pub get
flutter build apk --release
flutter build windows --release
```

## Prueba rápida

1. Admin crea usuario `juan` con email `juan@gmail.com` y una clave cualquiera.
2. En el APK: **Entrar con Google** → cuenta `juan@gmail.com`.
3. Debe entrar al sistema con el rol que le asignaste.
