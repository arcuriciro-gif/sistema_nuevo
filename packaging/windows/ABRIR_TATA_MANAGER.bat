@echo off
cd /d "%~dp0"
title Tata.Manager

echo Carpeta: %CD%
echo.

if not exist "sistema_nuevo.exe" (
  echo [ERROR] No esta sistema_nuevo.exe en esta carpeta.
  echo Copiá TODA la carpeta Instalador_Windows o Release, no solo el .exe.
  pause
  exit /b 1
)

if not exist "data\flutter_assets" (
  echo [ERROR] Falta la carpeta data\flutter_assets
  echo El .exe no puede arrancar solo. Tiene que estar junto a:
  echo   - data\
  echo   - flutter_windows.dll
  echo   - otros .dll
  pause
  exit /b 1
)

if not exist "flutter_windows.dll" (
  echo [ERROR] Falta flutter_windows.dll
  echo Copiá la carpeta completa del build, no solo el .exe.
  pause
  exit /b 1
)

echo Iniciando sistema_nuevo.exe ...
echo Si se cierra solo, anota el mensaje de error.
echo.

sistema_nuevo.exe
set ERR=%ERRORLEVEL%

echo.
if %ERR% neq 0 (
  echo [ERROR] La app salio con codigo %ERR%
  echo.
  echo Probá tambien:
  echo   1^) Instalar Visual C++ Redistributable x64
  echo   2^) Desactivar antivirus un momento
  echo   3^) Ejecutar desde:
  echo      build\windows\x64\runner\Release\
) else (
  echo App cerrada normalmente.
)
pause
