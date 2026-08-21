@echo off
REM ============================================================
REM  FUDO PRINT DOCTOR - Diagnostico + reparacion automatica
REM  Se eleva a administrador solo (hace falta para el spooler,
REM  la cola de impresion y la instalacion de drivers).
REM ============================================================
setlocal
cd /d "%~dp0"
title Fudo Print Doctor - diagnostico y reparacion
net session >/dev/null 2>&1
if %errorlevel% neq 0 (
  echo  Pidiendo permisos de administrador...
  powershell -NoProfile -Command "Start-Process -FilePath %~f0 -Verb RunAs"
  exit /b
)
echo.
echo  Corriendo diagnostico + reparacion...
echo.
powershell -NoProfile -ExecutionPolicy Bypass -File "%~dp0FudoPrintDoctor.ps1"
echo.
pause
