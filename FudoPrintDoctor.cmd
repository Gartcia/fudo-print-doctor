@echo off
REM ================================================================
REM  FUDO PRINT DOCTOR
REM  Doble clic. Diagnostica y repara el flujo de impresion.
REM  Se eleva a administrador solo. Deja resultado.json al lado.
REM ================================================================
setlocal
cd /d "%~dp0"
title Fudo Print Doctor

net session >/dev/null 2>&1
if %errorlevel% neq 0 (
  echo  Pidiendo permisos de administrador...
  powershell -NoProfile -Command "Start-Process -FilePath %~f0 -Verb RunAs"
  exit /b
)

echo.
echo  ================================================================
echo   FUDO PRINT DOCTOR
echo  ================================================================
echo   Va a revisar toda la cadena de impresion y reparar lo que pueda:
echo     - servicio de cola de impresion (spooler)
echo     - impresora en modo offline o pausada
echo     - App Nativa de Fudo en cuarentena del antivirus
echo     - puerto USB cambiado
echo     - driver e instalacion de la impresora, si falta
echo.
echo   Va a IMPRIMIR UN TICKET DE PRUEBA: avisale al cliente.
echo   Si hay comandas trabadas en la cola, primero te pregunta.
echo.
echo   Enter para empezar, o cerra esta ventana para cancelar.
echo  ================================================================
pause >nul
echo.

powershell -NoProfile -ExecutionPolicy Bypass -File "%~dp0FudoPrintDoctor.ps1" -JsonOut "%~dp0resultado.json"
set FPD_EXIT=%errorlevel%

echo.
echo  ----------------------------------------------------------------
if "%FPD_EXIT%"=="0" echo   RESUELTO. Probar imprimir una comanda desde Fudo.
if "%FPD_EXIT%"=="2" echo   Quedan cosas por hacer: mira QUE HACER AHORA aca arriba.
if "%FPD_EXIT%"=="3" echo   El motor tuvo una falla interna: escalar con resultado.json.
echo   Detalle completo: %~dp0resultado.json
echo  ----------------------------------------------------------------
echo.
pause
