@echo off
cd /d "%~dp0"
if not exist "Tata.Manager.exe" (
  echo No esta Tata.Manager.exe en esta carpeta.
  pause
  exit /b 1
)
echo Abriendo Tata.Manager desde:
echo   %CD%
echo.
echo Primera vez: usuario admin / clave admin123
echo.
echo Si falla el login, mira tata_manager_error.log
echo (en esta carpeta o en Documentos).
echo.
start "" "Tata.Manager.exe"
