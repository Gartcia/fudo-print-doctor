@echo off
REM ================================================================
REM  Actualizar Fudo Print Doctor
REM  Doble clic. Baja la ultima version publicada a esta carpeta.
REM  Guardalo una vez y usalo cada vez que quieras la version nueva.
REM ================================================================
setlocal
cd /d "%~dp0"
title Actualizar Fudo Print Doctor

set BASE=https://raw.githubusercontent.com/Gartcia/fudo-print-doctor/main
set REPO=https://github.com/Gartcia/fudo-print-doctor

REM curl viene con Windows 10 1803 y posteriores; si no esta, usamos PowerShell.
set DL=curl
where curl >nul 2>&1
if errorlevel 1 set DL=ps

del /q version.tmp motor.tmp launcher.tmp >nul 2>&1

echo.
echo  Buscando la ultima version publicada...
echo.

call :descargar VERSION version.tmp
if errorlevel 1 goto sin_red
findstr /r "^[0-9]" version.tmp >nul
if errorlevel 1 goto no_publico
set /p NUEVA=<version.tmp
echo   Version publicada: %NUEVA%
echo   Descargando...

call :descargar FudoPrintDoctor.ps1 motor.tmp
if errorlevel 1 goto sin_red
findstr /c:"FudoPrintDoctor" motor.tmp >nul
if errorlevel 1 goto no_publico

call :descargar FudoPrintDoctor.cmd launcher.tmp
if errorlevel 1 goto sin_red

move /y motor.tmp "FudoPrintDoctor.ps1" >nul
move /y launcher.tmp "FudoPrintDoctor.cmd" >nul
move /y version.tmp "version-descargada.txt" >nul

echo.
echo  ================================================================
echo   Listo: Fudo Print Doctor v%NUEVA% en esta carpeta.
echo.
echo   Para usarlo en la PC de un cliente, copiale estos dos archivos:
echo     FudoPrintDoctor.cmd
echo     FudoPrintDoctor.ps1
echo   y que haga doble clic en el .cmd
echo  ================================================================
echo.
pause
exit /b 0


REM ---------------------------------------------------------------
REM  :descargar <archivo-remoto> <archivo-local>
REM ---------------------------------------------------------------
:descargar
if "%DL%"=="ps" goto dl_ps
curl -fsSL --max-time 90 -o "%~2" "%BASE%/%~1"
exit /b %errorlevel%
:dl_ps
powershell -NoProfile -ExecutionPolicy Bypass -Command "$ErrorActionPreference='Stop'; try { [Net.ServicePointManager]::SecurityProtocol=[Net.SecurityProtocolType]::Tls12 } catch {}; Invoke-WebRequest -Uri '%BASE%/%~1' -UseBasicParsing -TimeoutSec 90 -OutFile '%~2'"
exit /b %errorlevel%


:no_publico
del /q version.tmp motor.tmp launcher.tmp >nul 2>&1
echo.
echo  ----------------------------------------------------------------
echo   Se pudo llegar a github, pero el archivo no esta disponible.
echo   Casi siempre es porque el repositorio todavia es PRIVADO.
echo.
echo   Para dejarlo publico:
echo     %REPO%/settings
echo     -^> General -^> abajo "Danger Zone" -^> Change visibility -^> Public
echo.
echo   Tambien puede pasar si todavia no se subio el archivo VERSION.
echo  ----------------------------------------------------------------
echo.
pause
exit /b 1


:sin_red
del /q version.tmp motor.tmp launcher.tmp >nul 2>&1
echo.
echo  ----------------------------------------------------------------
echo   No se pudo descargar.
echo.
echo   Revisar:
echo     - conexion a internet en esta PC
echo     - que el antivirus o el proxy no bloqueen github.com
echo.
echo   Alternativa: bajar el ZIP a mano desde
echo     %REPO%
echo  ----------------------------------------------------------------
echo.
pause
exit /b 1
