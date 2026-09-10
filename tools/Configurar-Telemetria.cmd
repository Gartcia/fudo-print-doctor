@echo off
REM ================================================================
REM  Configurar-Telemetria
REM  Arma la copia INTERNA de FudoPrintDoctor.cmd, con la URL de
REM  telemetria adentro, para distribuir al equipo.
REM
REM  Por que existe: el .cmd del repositorio publico deja la URL vacia
REM  a proposito, y la URL no puede vivir en el repositorio. Este
REM  archivo la pega en una copia, sin escribirla en ningun otro lado.
REM  El resultado (FudoPrintDoctor-interno.cmd) NO se commitea.
REM
REM  Uso:
REM   - doble clic, y pega la URL cuando la pida; o
REM   - arrastrale encima un FudoPrintDoctor.cmd interno que ya tenga
REM     la URL, y la toma de ahi sin que tengas que tipearla.
REM
REM  La sustitucion la hace PowerShell y no batch: un .cmd copiado
REM  linea por linea con echo pierde los >nul 2>&1 y los %~dp0.
REM ================================================================
setlocal
cd /d "%~dp0"
title Configurar telemetria - FudoPrintDoctor

set "FPD_BASE=%~dp0..\FudoPrintDoctor.cmd"
if not exist "%FPD_BASE%" set "FPD_BASE=%~dp0FudoPrintDoctor.cmd"
if not exist "%FPD_BASE%" goto sin_base
set "FPD_OUT=%~dp0FudoPrintDoctor-interno.cmd"

echo.
echo  ================================================================
echo   CONFIGURAR TELEMETRIA
echo  ================================================================
echo   Base: %FPD_BASE%
echo.

set "FPD_URL="
set "FPD_SRC="

REM  1) De un .cmd interno arrastrado encima: no hay que tipear nada
REM     y la URL no aparece en pantalla.
if "%~1"=="" goto sin_arg
if not exist "%~1" goto sin_arg
set "FPD_FROM=%~1"
for /f "usebackq tokens=* delims=" %%u in (`powershell -NoProfile -ExecutionPolicy Bypass -Command "$t=[IO.File]::ReadAllText($env:FPD_FROM); $m=[regex]::Match($t, 'FUDO_TELEMETRY_URL=([^' + [char]34 + ']+)'); if ($m.Success) { $m.Groups[1].Value }"`) do set "FPD_URL=%%u"
if defined FPD_URL set "FPD_SRC=%~nx1"
goto tengo_url

:sin_arg
REM  2) De la variable de entorno de esta PC, si esta seteada.
if defined FUDO_TELEMETRY_URL set "FPD_URL=%FUDO_TELEMETRY_URL%"
if defined FPD_URL set "FPD_SRC=variable FUDO_TELEMETRY_URL"

:tengo_url
if not defined FPD_URL goto pedir_url
echo   URL tomada de: %FPD_SRC%
goto generar

:pedir_url
echo   Pega la URL del Apps Script (empieza con https:// y termina en /exec).
echo.
set /p FPD_URL=  URL:
if not defined FPD_URL goto sin_url

:generar
REM  Validacion y sustitucion en PowerShell: la URL viaja por variable
REM  de entorno para no pelear con las comillas de cmd.
powershell -NoProfile -ExecutionPolicy Bypass -Command "$u=$env:FPD_URL; if ($u -notmatch '^https://' -or $u -notmatch '/exec$') { exit 3 }; $q=[char]34; $base=[IO.File]::ReadAllText($env:FPD_BASE); $buscar='set ' + $q + 'FUDO_TELEMETRY_URL=' + $q; $poner='set ' + $q + 'FUDO_TELEMETRY_URL=' + $u + $q; if ($base -notlike ('*' + $buscar + '*')) { exit 4 }; $nuevo=$base.Replace($buscar, $poner); [IO.File]::WriteAllText($env:FPD_OUT, $nuevo); exit 0"
if errorlevel 4 goto sin_marcador
if errorlevel 3 goto url_invalida
if errorlevel 1 goto fallo
if not exist "%FPD_OUT%" goto fallo

REM  Verificar el efecto, no el codigo de retorno.
findstr /c:"FUDO_TELEMETRY_URL=http" "%FPD_OUT%" >nul
if errorlevel 1 goto fallo

echo.
echo  ----------------------------------------------------------------
echo   LISTO: %FPD_OUT%
echo.
echo   Ese es el archivo para distribuir al equipo. Renombralo a
echo   FudoPrintDoctor.cmd y mandalo junto con el .msi de la App
echo   Nativa firmada: el motor lo baja solo, el .msi no.
echo.
echo   NO lo commitees: la URL no va al repositorio.
echo  ----------------------------------------------------------------
echo.
pause
exit /b 0

:sin_base
echo.
echo  No encontre FudoPrintDoctor.cmd (lo busque en la carpeta de arriba
echo  y en esta). Este archivo va dentro del repositorio, en tools\.
echo.
pause
exit /b 1

:sin_url
echo.
echo  No se ingreso ninguna URL. No se genero nada.
echo.
pause
exit /b 1

:url_invalida
echo.
echo  Esa URL no parece la del Apps Script: tiene que empezar con
echo  https:// y terminar en /exec. No se genero nada.
echo.
pause
exit /b 1

:sin_marcador
echo.
echo  El .cmd base no tiene la linea que hay que reemplazar:
echo    set "FUDO_TELEMETRY_URL="
echo  Puede ser que ya tenga una URL puesta. No se genero nada.
echo.
pause
exit /b 1

:fallo
echo.
echo  No se pudo generar el archivo. No se genero nada usable.
echo.
del /q "%FPD_OUT%" >nul 2>&1
pause
exit /b 1
