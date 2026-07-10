@echo off
cd /d "%~dp0"
if not exist "sistema_nuevo.exe" (
  echo No esta sistema_nuevo.exe en esta carpeta.
  pause
  exit /b 1
)
start "" "sistema_nuevo.exe"
