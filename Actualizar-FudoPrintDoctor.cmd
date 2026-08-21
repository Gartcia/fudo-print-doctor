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

echo.
echo  Buscando la ultima version publicada...
echo.

powershell -NoProfile -ExecutionPolicy Bypass -Command ^
  "try { [Net.ServicePointManager]::SecurityProtocol=[Net.SecurityProtocolType]::Tls12 } catch {}; ^
   $b='%BASE%'; ^
   $v=(Invoke-WebRequest -Uri ($b+'/VERSION') -UseBasicParsing -TimeoutSec 15).Content.Trim(); ^
   Write-Host ('  Version publicada: '+$v); ^
   Invoke-WebRequest -Uri ($b+'/FudoPrintDoctor.ps1') -UseBasicParsing -TimeoutSec 60 -OutFile 'FudoPrintDoctor.ps1.new'; ^
   Invoke-WebRequest -Uri ($b+'/FudoPrintDoctor.cmd') -UseBasicParsing -TimeoutSec 30 -OutFile 'FudoPrintDoctor.cmd.new'; ^
   Move-Item -Force 'FudoPrintDoctor.ps1.new' 'FudoPrintDoctor.ps1'; ^
   Move-Item -Force 'FudoPrintDoctor.cmd.new' 'FudoPrintDoctor.cmd'; ^
   Set-Content -Path 'version-descargada.txt' -Value $v; ^
   Write-Host ''; Write-Host ('  Listo: FudoPrintDoctor v'+$v+' descargado en esta carpeta.')"

if errorlevel 1 goto error

echo.
echo  ================================================================
echo   Para usarlo en la PC de un cliente, copiale estos dos archivos:
echo     FudoPrintDoctor.cmd
echo     FudoPrintDoctor.ps1
echo   y que haga doble clic en el .cmd
echo  ================================================================
echo.
pause
exit /b 0

:error
echo.
echo  No se pudo descargar. Revisar la conexion a internet o si el
echo  antivirus / proxy esta bloqueando github.com
echo  Alternativa: bajar el ZIP desde
echo    https://github.com/Gartcia/fudo-print-doctor
echo.
pause
exit /b 1
