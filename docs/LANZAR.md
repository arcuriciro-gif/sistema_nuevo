# Cómo generar APK y EXE (Tata.Manager)

Versión actual: **`1.1.10+20`**  
En la pantalla de **login** debe verse abajo: **`Tata.Manager v1.1.10 (20)`**.  
Si no aparece ese texto, estás usando una carpeta/EXE/APK **vieja**.

Package Android: `com.eltatamanager.app`  
Rama con todo lo nuevo: `cursor/sync-queue-offline-6144`

---

## Regla de oro (para no renegar)

1. **Siempre** `git pull` en esa rama antes de compilar.
2. **Borrá** el instalador/APK viejo antes de copiar el nuevo.
3. En login verificá **`v1.1.10 (20)`**. Si no está, no es este build.

---

## A) APK (Android)

En PowerShell / CMD, en la carpeta del proyecto:

```bat
cd A:\PROYECTOS\sistema_nuevo_git
git fetch origin
git checkout cursor/sync-queue-offline-6144
git pull origin cursor/sync-queue-offline-6144
flutter pub get
flutter build apk --release
```

**Archivo listo:**
```
build\app\outputs\flutter-apk\app-release.apk
```

### Instalar en el celular
1. Desinstalá la app anterior (si era `com.example…` o un build viejo).
2. Copiá **ese** `app-release.apk` al teléfono e instalá.
3. Login → debe decir **`Tata.Manager v1.1.10 (20)`**.

Con cable:
```bat
adb install -r build\app\outputs\flutter-apk\app-release.apk
```

---

## B) EXE (Windows)

**Solo se puede compilar en una PC Windows** (Flutter + Visual Studio C++).

```bat
cd A:\PROYECTOS\sistema_nuevo_git
git fetch origin
git checkout cursor/sync-queue-offline-6144
git pull origin cursor/sync-queue-offline-6144
flutter pub get
flutter config --enable-windows-desktop
flutter build windows --release
scripts\preparar_instalador_windows.bat
```

Eso deja lista la carpeta:
```
Instalador_Windows\
  sistema_nuevo.exe      ← programa real
  ABRIR_TATA_MANAGER.bat ← atajo cómodo
  data\
  *.dll
  ...
```

### Usar / actualizar en esta PC o en otra
1. Cerrá Tata.Manager si está abierto.
2. **Borrá** cualquier `Instalador_Windows` vieja (pendrive, Escritorio, etc.).
3. Copiá **toda** la carpeta nueva `Instalador_Windows` (no solo el `.exe`).
4. Abrí y verificá login: **`v1.1.10 (20)`**.

### Acceso directo en Windows
Creá el acceso directo sobre:

**`Instalador_Windows\sistema_nuevo.exe`**

Importante: el `.exe` debe quedarse dentro de esa carpeta (con las DLL y `data`).

---

## C) Borrar todo / sistema virgen

1. Login con usuario **Administrador** (por defecto suele ser `admin`).
2. Menú → **Configuración**.
3. Arriba del todo: tarjeta roja **BORRAR TODO**.
4. Ahí se ve tu usuario, rol y versión. Si el rol no es Administrador, no aparecen los botones.
5. Botón rojo: **Borrar todo (sistema virgen)** → pide tu contraseña.

---

## D) Checklist “¿tengo la versión nueva?”

| Check | OK si… |
|-------|--------|
| Login | `Tata.Manager v1.1.10 (20)` |
| Configuración | Arriba: tarjeta **BORRAR TODO** |
| Reportes | PDF/CSV/Excel abre **Guardar como…** en Windows |
| Menú | Inventario, Estadísticas, Cierre de caja (si no los ocultaste) |

---

## No hagas esto

- No copies solo `sistema_nuevo.exe`.
- No mezcles DLL de un build viejo con un exe nuevo.
- No uses un ZIP sin descomprimir.
- No instales un APK de otra carpeta/`build` viejo.

## Error STL1011 al compilar Windows (VS 18.6+)

Si ves `error STL1011` / `experimental/coroutine` en `permission_handler_windows`, necesitás el fix de `v1.1.8` (`git pull` de esta rama). Los warnings MSB8029 y CMake Deprecation Warning se pueden ignorar.
