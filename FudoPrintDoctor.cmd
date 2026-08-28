@echo off
REM ================================================================
REM  FUDO PRINT DOCTOR
REM  Doble clic. Diagnostica y repara el flujo de impresion.
REM  Se eleva a administrador solo. Deja resultado.json al lado.
REM ================================================================
setlocal
cd /d "%~dp0"
title Fudo Print Doctor

REM ----------------------------------------------------------------
REM  TELEMETRIA (opcional): pegar entre las comillas la URL del Apps
REM  Script para que cada corrida reporte sola. Este es el archivo que
REM  SI se copia a la PC del cliente, asi que no hay ningun archivo
REM  extra que olvidarse. El repositorio publico lo deja vacio.
REM ----------------------------------------------------------------
set "FUDO_TELEMETRY_URL="

net session >nul 2>&1
if errorlevel 1 goto elevar
goto admin_ok

:elevar
echo  Pidiendo permisos de administrador...
powershell -NoProfile -Command "Start-Process -FilePath '%~f0' -Verb RunAs"
exit /b

:admin_ok
if exist "%~dp0FudoPrintDoctor.ps1" goto motor_ok

echo  No encuentro FudoPrintDoctor.ps1 al lado de este archivo.
echo  Intento descargarlo...
echo.
powershell -NoProfile -ExecutionPolicy Bypass -Command "try { [Net.ServicePointManager]::SecurityProtocol=[Net.SecurityProtocolType]::Tls12 } catch {}; Invoke-WebRequest -Uri 'https://raw.githubusercontent.com/Gartcia/fudo-print-doctor/main/FudoPrintDoctor.ps1' -UseBasicParsing -TimeoutSec 60 -OutFile '%~dp0FudoPrintDoctor.ps1'"
if not exist "%~dp0FudoPrintDoctor.ps1" goto sin_motor

:motor_ok
findstr /c:"FudoPrintDoctor" "%~dp0FudoPrintDoctor.ps1" >nul
if errorlevel 1 goto motor_invalido

echo.
echo  ================================================================
echo   FUDO PRINT DOCTOR
echo  ================================================================
echo   Va a revisar la cadena de impresion y reparar lo que pueda:
echo     - servicio de cola de impresion (spooler)
echo     - impresora en modo offline o pausada
echo     - App Nativa de Fudo en cuarentena del antivirus
echo     - puerto USB cambiado
echo     - driver e instalacion de la impresora, si falta
echo.
echo   Primero te pregunta si la impresora es USB, de red, o las dos.
echo   Si no sabes, elegi las dos.
echo.
echo   Va a IMPRIMIR UN TICKET DE PRUEBA: avisale al cliente.
echo   Despues te pregunta si salio el papel: es la unica forma de
echo   saber si quedo resuelto, asi que conviene tener la impresora
echo   a la vista.
echo   Si hay comandas trabadas en la cola, primero te pregunta.
echo.
echo   Enter para empezar, o cerra esta ventana para cancelar.
echo  ================================================================
pause >nul
echo.

set "FPD_CASO="
set /p FPD_CASO=  ID del caso (Intercom/ClickUp), o Enter para omitir: 
echo.
powershell -NoProfile -ExecutionPolicy Bypass -File "%~dp0FudoPrintDoctor.ps1" -JsonOut "%~dp0resultado.json" -CaseId "%FPD_CASO%"
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
exit /b %FPD_EXIT%

:sin_motor
echo.
echo  No se pudo descargar y no esta en la carpeta. Esta PC puede no
echo  tener internet. Copiar tambien el archivo FudoPrintDoctor.ps1
echo  junto a este .cmd y volver a intentar.
echo.
pause
exit /b 1

:motor_invalido
del /q "%~dp0FudoPrintDoctor.ps1" >nul 2>&1
echo.
echo  Lo que se descargo no es el motor (el repositorio puede estar
echo  privado). Copiar el archivo FudoPrintDoctor.ps1 junto a este .cmd.
echo.
pause
exit /b 1
