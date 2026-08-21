@echo off
REM  Corrida para el agente: resumen en pantalla + JSON en resultado.json
setlocal
cd /d "%~dp0"
powershell -NoProfile -ExecutionPolicy Bypass -File "%~dp0FudoPrintDoctor.ps1" -JsonOut "%~dp0resultado.json" -CaseId "%~1"
echo.
echo  JSON: %~dp0resultado.json   (exit code %errorlevel%)
pause
