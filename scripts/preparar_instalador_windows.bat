@echo off
REM Copia el build Windows listo a la carpeta raiz Instalador_Windows
REM Uso (despues de compilar):
REM   scripts\preparar_instalador_windows.bat
REM o:
REM   flutter build windows --release
REM   scripts\preparar_instalador_windows.bat

setlocal
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

echo Copiando desde:
echo   %SRC%
echo Hacia:
echo   %DST%
echo.

if exist "%DST%" (
  echo Limpiando carpeta anterior...
  rmdir /s /q "%DST%"
)
mkdir "%DST%"

xcopy "%SRC%\*" "%DST%\" /E /I /Y /Q >nul
if errorlevel 1 (
  echo [ERROR] Fallo al copiar.
  pause
  exit /b 1
)

REM Asegurar PDF del manual
if exist "%ROOT%\assets\docs\MANUAL_DE_USO.pdf" (
  copy /Y "%ROOT%\assets\docs\MANUAL_DE_USO.pdf" "%DST%\MANUAL_DE_USO.pdf" >nul
)

REM Accesos faciles
copy /Y "%~dp0..\packaging\windows\ABRIR_TATA_MANAGER.bat" "%DST%\ABRIR_TATA_MANAGER.bat" >nul
copy /Y "%~dp0..\packaging\windows\LEEME.txt" "%DST%\LEEME.txt" >nul

echo.
echo Listo. Carpeta lista para copiar a otra PC:
echo   %DST%
echo.
echo Abrí ABRIR_TATA_MANAGER.bat o sistema_nuevo.exe
echo NO muevas solo el .exe: tiene que ir toda la carpeta.
echo.
explorer "%DST%"
endlocal
