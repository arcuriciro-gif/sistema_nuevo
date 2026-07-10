@echo off
cd /d "%~dp0"
if not exist "sistema_nuevo.exe" (
  echo No esta sistema_nuevo.exe en esta carpeta.
  pause
  exit /b 1
)
echo Abriendo Tata.Manager desde:
echo   %CD%
echo.
echo Si la app se cierra al iniciar sesion:
echo  - No muevas solo el .exe; usa TODA esta carpeta
echo  - Instala "Microsoft Visual C++ Redistributable" x64
echo  - Mira el archivo tata_manager_error.log en Documentos
echo.
start "" "sistema_nuevo.exe"
