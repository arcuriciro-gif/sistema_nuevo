@echo off
REM Copia el build Windows listo a la carpeta raiz Instalador_Windows
REM Uso (despues de compilar):
REM   flutter build windows --release
REM   scripts\preparar_instalador_windows.bat

setlocal
set "ROOT=%~dp0.."
set "SRC=%ROOT%\build\windows\x64\runner\Release"
set "DST=%ROOT%\Instalador_Windows"
set "EXE=Tata.Manager.exe"

if not exist "%SRC%\%EXE%" (
  echo.
  echo [ERROR] No encontre %EXE% en:
  echo   %SRC%
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

if exist "%ROOT%\packaging\windows\ABRIR_TATA_MANAGER.bat" (
  copy /Y "%ROOT%\packaging\windows\ABRIR_TATA_MANAGER.bat" "%DST%\" >nul
)
if exist "%ROOT%\packaging\windows\LEEME.txt" (
  copy /Y "%ROOT%\packaging\windows\LEEME.txt" "%DST%\" >nul
)
if exist "%ROOT%\assets\docs\MANUAL_DE_USO.pdf" (
  copy /Y "%ROOT%\assets\docs\MANUAL_DE_USO.pdf" "%DST%\" >nul
)

echo Generando SHA256SUMS.txt ...
powershell -NoProfile -Command ^
  "Get-ChildItem -File '%DST%' | ForEach-Object { $h=(Get-FileHash $_.FullName -Algorithm SHA256).Hash.ToLower(); '{0}  {1}' -f $h, $_.Name } | Set-Content -Encoding ascii '%DST%\SHA256SUMS.txt'"

echo.
echo Listo: %DST%\%EXE%
dir /b "%DST%"
echo.
pause
endlocal
