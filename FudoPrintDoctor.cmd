@echo off
REM ================================================================
REM  FUDO PRINT DOCTOR - launcher
REM  Doble clic. Diagnostica y repara el flujo de impresion.
REM  Se eleva a administrador solo. Deja resultado.json al lado.
REM ================================================================
REM  Este archivo hace cinco cosas antes y despues del motor, y las
REM  cinco salieron de casos reales:
REM   1. Verifica que la PC pueda correr el motor (PowerShell 5+ y
REM      Get-Printer). Una PC con PowerShell 2.0 hacia que el .ps1 no
REM      parseara, no corriera NADA, y el launcher dijera RESUELTO.
REM   2. Verifica que el .ps1 que tiene al lado sea la version
REM      publicada, y lo actualiza si no. Antes solo miraba si el
REM      archivo EXISTIA: una copia vieja olvidada en el escritorio de
REM      un cliente se seguia usando para siempre.
REM   3. No pregunta el ID del caso: lo pide el motor desde la 3.14.
REM      Preguntarlo aca lo pedia dos veces y le metia un espacio.
REM   4. No dice RESUELTO por el codigo de salida: verifica que el
REM      resultado.json se haya escrito en esta corrida. Un .ps1 que no
REM      parsea hace que powershell -File salga con codigo 0.
REM   5. Deja la PC del cliente limpia al terminar.
REM ================================================================
REM  LAUNCHER-VERSION: 2   <- subir esto cuando cambie este archivo. El
REM  updater no lo pisa (lleva la URL de telemetria), asi que hoy la copia
REM  interna se distribuye a mano. El marcador queda para que el updater
REM  pueda comparar y refrescarlo preservando la URL.
setlocal
cd /d "%~dp0"
title Fudo Print Doctor

REM ----------------------------------------------------------------
REM  TELEMETRIA (opcional): pegar entre las comillas la URL del Apps
REM  Script para que cada corrida reporte sola. Este es el archivo que
REM  SI se copia a la PC del cliente, asi que no hay ningun archivo
REM  extra que olvidarse. El repositorio publico lo deja vacio: para
REM  armar la copia interna, usar tools\Configurar-Telemetria.cmd.
REM ----------------------------------------------------------------
set "FUDO_TELEMETRY_URL="

set "FPD_MOTOR=%~dp0FudoPrintDoctor.ps1"
set "FPD_JSON=%~dp0resultado.json"
set "FPD_RAW=https://raw.githubusercontent.com/Gartcia/fudo-print-doctor/main"

net session >nul 2>&1
if errorlevel 1 goto elevar
goto admin_ok

:elevar
echo  Pidiendo permisos de administrador...
powershell -NoProfile -Command "Start-Process -FilePath '%~f0' -Verb RunAs"
exit /b

:admin_ok
REM ----------------------------------------------------------------
REM  1) Puede esta PC correr el motor?
REM  El sondeo se escribe con sintaxis de PowerShell 2.0 a proposito:
REM  tiene que poder correr justamente en las PCs que vamos a rechazar.
REM ----------------------------------------------------------------
powershell -NoProfile -ExecutionPolicy Bypass -Command "$m=0; try { $m=$PSVersionTable.PSVersion.Major } catch {}; if ($m -lt 5) { exit 10 }; if (-not (Get-Command Get-Printer -ErrorAction SilentlyContinue)) { exit 11 }; exit 0"
if errorlevel 12 goto sin_powershell
if errorlevel 11 goto windows_viejo
if errorlevel 10 goto ps_vieja

REM ----------------------------------------------------------------
REM  2) El motor tiene que ser la version publicada, no la que quedo.
REM ----------------------------------------------------------------
set "FPD_PUB="
del /q "%~dp0version.tmp" >nul 2>&1
powershell -NoProfile -ExecutionPolicy Bypass -Command "try { [Net.ServicePointManager]::SecurityProtocol=[Net.SecurityProtocolType]::Tls12 } catch {}; try { Invoke-WebRequest -Uri '%FPD_RAW%/VERSION' -UseBasicParsing -TimeoutSec 25 -OutFile '%~dp0version.tmp' } catch {}" >nul 2>&1
if exist "%~dp0version.tmp" for /f "usebackq tokens=* delims= " %%v in ("%~dp0version.tmp") do set "FPD_PUB=%%v"
del /q "%~dp0version.tmp" >nul 2>&1

if not defined FPD_PUB goto sin_internet
if not exist "%FPD_MOTOR%" goto bajar_motor

REM La version vive dentro del .ps1 como $script:SchemaVersion = 'X.Y'.
findstr /c:"SchemaVersion = '%FPD_PUB%'" "%FPD_MOTOR%" >nul 2>&1
if not errorlevel 1 goto motor_ok

echo.
echo  El motor que hay en esta carpeta no es la version publicada (%FPD_PUB%).
echo  Lo actualizo...
del /q "%FPD_MOTOR%" >nul 2>&1
goto bajar_motor

:sin_internet
if not exist "%FPD_MOTOR%" goto bajar_motor
echo.
echo  OJO: no se pudo consultar la version publicada (esta PC puede no
echo  tener internet). Se usa el motor que esta en la carpeta, que puede
echo  estar desactualizado.
echo.
goto motor_ok

:bajar_motor
echo  Descargando el motor...
echo.
powershell -NoProfile -ExecutionPolicy Bypass -Command "try { [Net.ServicePointManager]::SecurityProtocol=[Net.SecurityProtocolType]::Tls12 } catch {}; Invoke-WebRequest -Uri '%FPD_RAW%/FudoPrintDoctor.ps1' -UseBasicParsing -TimeoutSec 90 -OutFile '%FPD_MOTOR%'"
if not exist "%FPD_MOTOR%" goto sin_motor

:motor_ok
findstr /c:"FudoPrintDoctor" "%FPD_MOTOR%" >nul
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
echo   Despues te pide el ID de la conversacion de Intercom: son los
echo   15 numeros, y podes pegar la URL entera.
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

REM  El resultado anterior se borra ANTES de correr: es la unica forma
REM  de saber despues si el motor llego a escribir el de esta corrida.
del /q "%FPD_JSON%" >nul 2>&1

powershell -NoProfile -ExecutionPolicy Bypass -File "%FPD_MOTOR%" -JsonOut "%FPD_JSON%"
set FPD_EXIT=%errorlevel%

echo.
echo  ----------------------------------------------------------------
if not exist "%FPD_JSON%" goto sin_resultado

if "%FPD_EXIT%"=="0" echo   RESUELTO. Probar imprimir una comanda desde Fudo.
if "%FPD_EXIT%"=="2" echo   Quedan cosas por hacer: mira QUE HACER AHORA aca arriba.
if "%FPD_EXIT%"=="3" echo   El motor tuvo una falla interna: escalar con resultado.json.
if "%FPD_EXIT%"=="5" echo   El motor esta desactualizado y no diagnostico. Volve a abrir este archivo.
if "%FPD_EXIT%"=="6" echo   Falta el ID de la conversacion: sin eso no se puede seguir el caso.
if "%FPD_EXIT%"=="7" echo   Falta el instalador de la App Nativa. Copialo al lado de este archivo.
echo   Detalle completo: %FPD_JSON%
echo  ----------------------------------------------------------------
goto limpiar

:sin_resultado
echo   EL MOTOR NO LLEGO A DIAGNOSTICAR: no genero el resultado.
echo.
echo   NO tomar esto como resuelto. Si arriba hay un error en rojo,
echo   sacale una captura y escribi en #fudo-print-doctor: es un bug
echo   del motor, no del cliente.
echo  ----------------------------------------------------------------
set FPD_EXIT=3

:limpiar
REM  No dejar herramientas nuestras en la PC del cliente. El
REM  telemetria.txt se borra siempre: lleva la URL interna de reporte.
del /q "%~dp0telemetria.txt" >nul 2>&1
echo.
set "FPD_BORRAR="
set /p FPD_BORRAR=  Borrar el motor de esta PC al salir? (Enter = si / n = no):
if /i "%FPD_BORRAR%"=="n" goto fin
del /q "%FPD_MOTOR%" >nul 2>&1
echo.
echo  Listo. Quedo solo resultado.json: adjuntalo al caso y borralo.

:fin
echo.
pause
exit /b %FPD_EXIT%

:ps_vieja
echo.
echo  ================================================================
echo   ESTA PC NO PUEDE CORRER EL DIAGNOSTICO
echo  ================================================================
echo   Tiene una version de PowerShell anterior a la 5, que es de
echo   Windows 7 o anterior. El motor no puede funcionar ahi.
echo.
echo   No se ejecuto nada. NO es un problema del cliente ni de la
echo   impresora: es esta PC.
echo.
echo   Que hacer: resolver el caso a mano y dejar anotado en la
echo   conversacion que la PC tiene Windows viejo.
echo  ================================================================
echo.
pause
exit /b 8

:windows_viejo
echo.
echo  ================================================================
echo   ESTA PC NO PUEDE CORRER EL DIAGNOSTICO
echo  ================================================================
echo   Le falta la administracion de impresoras de Windows
echo   (Get-Printer), que existe desde Windows 8. El motor la necesita
echo   para ver las colas de impresion.
echo.
echo   No se ejecuto nada. Resolver el caso a mano y dejarlo anotado.
echo  ================================================================
echo.
pause
exit /b 8

:sin_powershell
echo.
echo  No se pudo ejecutar PowerShell en esta PC, asi que el diagnostico
echo  no puede correr. No se ejecuto nada.
echo.
pause
exit /b 8

:sin_motor
echo.
echo  No se pudo descargar y no esta en la carpeta. Esta PC puede no
echo  tener internet. Copiar tambien el archivo FudoPrintDoctor.ps1
echo  junto a este .cmd y volver a intentar.
echo.
pause
exit /b 1

:motor_invalido
del /q "%FPD_MOTOR%" >nul 2>&1
echo.
echo  Lo que se descargo no es el motor (el repositorio puede estar
echo  privado). Copiar el archivo FudoPrintDoctor.ps1 junto a este .cmd.
echo.
pause
exit /b 1
