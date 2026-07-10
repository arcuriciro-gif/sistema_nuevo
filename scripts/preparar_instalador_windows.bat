@echo off
REM Copia el build Windows listo a la carpeta raiz Instalador_Windows
REM Uso (despues de compilar):
REM   scripts\preparar_instalador_windows.bat

setlocal EnableExtensions
set "ROOT=%~dp0.."
set "SRC=%ROOT%\build\windows\x64\runner\Release"
set "DST=%ROOT%\Instalador_Windows"

if not exist "%SRC%\sistema_nuevo.exe" (
  echo.
  echo [ERROR] No encontre el .exe.
  echo Primero compilá con:
  echo   flutter build windows --release
  echo.
  pause
  exit /b 1
)

echo Cerrando Tata.Manager si esta abierto...
taskkill /F /IM sistema_nuevo.exe >nul 2>&1
taskkill /F /IM ABRIR_TATA_MANAGER.bat >nul 2>&1
timeout /t 2 /nobreak >nul

echo Copiando desde:
echo   %SRC%
echo Hacia:
echo   %DST%
echo.

if exist "%DST%" (
  echo Liberando carpeta anterior...
  rmdir /s /q "%DST%" 2>nul
)

if exist "%DST%" (
  echo No se pudo borrar. Renombrando carpeta bloqueada...
  set "STAMP=%DATE:~-4%%DATE:~3,2%%DATE:~0,2%_%TIME:~0,2%%TIME:~3,2%%TIME:~6,2%"
  set "STAMP=%STAMP: =0%"
  set "STAMP=%STAMP:/=-%"
  set "STAMP=%STAMP::=-%"
  ren "%DST%" "Instalador_Windows_viejo_%RANDOM%"
)

if exist "%DST%" (
  echo.
  echo [ERROR] Instalador_Windows sigue bloqueada.
  echo 1^) Cerra TODAS las ventanas del Explorador
  echo 2^) Cerra la app si esta abierta
  echo 3^) Ejecuta:
  echo    taskkill /F /IM sistema_nuevo.exe
  echo    taskkill /F /IM explorer.exe
  echo    start explorer.exe
  echo 4^) Volve a correr este script
  echo.
  echo Mientras tanto podes usar directo:
  echo   %SRC%
  echo.
  pause
  exit /b 1
)

mkdir "%DST%"
xcopy "%SRC%\*" "%DST%\" /E /I /Y /Q >nul
if errorlevel 1 (
  echo [ERROR] Fallo al copiar.
  pause
  exit /b 1
)

if exist "%ROOT%\assets\docs\MANUAL_DE_USO.pdf" (
  copy /Y "%ROOT%\assets\docs\MANUAL_DE_USO.pdf" "%DST%\MANUAL_DE_USO.pdf" >nul
)

if exist "%ROOT%\assets\templates" (
  mkdir "%DST%\plantillas" 2>nul
  xcopy "%ROOT%\assets\templates\*" "%DST%\plantillas\" /E /I /Y /Q >nul
)

copy /Y "%~dp0..\packaging\windows\ABRIR_TATA_MANAGER.bat" "%DST%\ABRIR_TATA_MANAGER.bat" >nul
copy /Y "%~dp0..\packaging\windows\LEEME.txt" "%DST%\LEEME.txt" >nul

echo.
echo Listo. Carpeta para copiar a otra PC:
echo   %DST%
echo.
echo Abrí ABRIR_TATA_MANAGER.bat
echo NO muevas solo el .exe.
echo.
explorer "%DST%"
endlocal
