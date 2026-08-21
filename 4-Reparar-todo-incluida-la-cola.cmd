@echo off
REM ============================================================
REM  FUDO PRINT DOCTOR - Reparacion completa
REM  Incluye limpiar la cola de impresion: los trabajos
REM  pendientes SE PIERDEN y hay que volver a mandarlos.
REM ============================================================
setlocal
cd /d "%~dp0"
title Fudo Print Doctor - reparacion completa
net session >/dev/null 2>&1
if %errorlevel% neq 0 (
  powershell -NoProfile -Command "Start-Process -FilePath %~f0 -Verb RunAs"
  exit /b
)
echo.
echo  ATENCION
echo  --------
echo  Ademas de todo lo del launcher 2, esto LIMPIA la cola de
echo  impresion. Las comandas que esten esperando en la cola se
echo  descartan y hay que volver a imprimirlas desde Fudo.
echo.
echo  Ctrl+C para cancelar, o
pause
echo.
powershell -NoProfile -ExecutionPolicy Bypass -File "%~dp0FudoPrintDoctor.ps1"
echo.
pause
