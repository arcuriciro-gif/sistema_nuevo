# Cómo generar APK y EXE (Tata.Manager)

Versión actual: **`1.1.5+15`**  
En la pantalla de **login** debe verse abajo: **`Tata.Manager v1.1.5 (15)`**.  
Si no aparece ese texto, estás usando una carpeta/EXE/APK **vieja**.

Package Android: `com.eltatamanager.app`

---

## A) APK (Android)

### En la PC de desarrollo

```bash
cd carpeta_del_proyecto
git checkout cursor/sync-queue-offline-6144
git pull
flutter pub get
flutter build apk --release
```

**Archivo:**
```
build/app/outputs/flutter-apk/app-release.apk
```

### Instalar en el celular
1. Copiá el APK al teléfono (Drive, WhatsApp, USB).
2. Desinstalá la app vieja si era `com.example…`.
3. Abrí el APK → permitir instalar → Instalar.
4. En login verificá: `Tata.Manager v1.1.5 (15)`.

### Con cable USB
```bash
adb install -r build/app/outputs/flutter-apk/app-release.apk
```

---

## B) EXE + carpeta para pendrive (varias PCs)

**Obligatorio: compilar en una PC con Windows** (Visual Studio C++ + Flutter desktop).

### 1. Compilar

```bat
cd carpeta_del_proyecto
git checkout cursor/sync-queue-offline-6144
git pull
flutter pub get
flutter config --enable-windows-desktop
flutter build windows --release
```

Salida interna:
```
build\windows\x64\runner\Release\
```

### 2. Armar carpeta para el pendrive

```bat
scripts\preparar_instalador_windows.bat
```

Crea / actualiza:
```
Instalador_Windows\
  ABRIR_TATA_MANAGER.bat   ← abrir con doble clic
  LEEME.txt
  sistema_nuevo.exe
  data\
  *.dll
  ...
```

### 3. Pendrive / otras PCs
1. **Borrá** del pendrive cualquier `Instalador_Windows` vieja.
2. Copiá **toda** la carpeta nueva `Instalador_Windows`.
3. En cada PC: pegá la carpeta y abrí **`ABRIR_TATA_MANAGER.bat`**.
4. En login verificá: `Tata.Manager v1.1.5 (15)`.

### No hagas esto
- No copies solo el `.exe`.
- No uses un ZIP sin descomprimir.
- No mezcles DLLs de un build viejo con un exe nuevo.

---

## C) Sistema virgen (borrar datos de negocio)

1. Login con usuario **Administrador** (rol `admin`).
2. Menú → **Configuración**.
3. Arriba del todo (tarjeta rojiza): **MANTENIMIENTO Y DATOS**.
4. **Dejar sistema virgen** → ingresá tu contraseña.

Conserva: usuarios, permisos, branding.  
Borra: productos, clientes, ventas, remitos, etc.

Si ves “Solo visible para Administrador”, tu usuario no es admin.

---

## D) Checklist “¿tengo la versión nueva?”

| Check | OK si… |
|-------|--------|
| Login | Dice `v1.1.5 (15)` |
| Configuración (admin) | Arriba: MANTENIMIENTO Y DATOS / sistema virgen |
| Menú | Inventario, Estadísticas, Cierre de caja (si no los ocultaste) |
| Sync | Chip de nube arriba (Sincronizado / Sin sesión / etc.) |

---

## Problemas frecuentes

**EXE sin sync / sin menús nuevos** → carpeta vieja. Recompilá y reemplazá toda `Instalador_Windows`.

**No veo sistema virgen** → no sos admin, o no bajaste lo suficiente (en builds viejos estaba al final). En `v1.1.5+` está **arriba**.

**Firebase / sync** → Authentication → Correo/contraseña activado; proyecto Blaze; JSON con `com.eltatamanager.app`.
