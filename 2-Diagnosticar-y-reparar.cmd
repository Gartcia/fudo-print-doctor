@echo off
REM ============================================================
REM  FUDO PRINT DOCTOR - Diagnostico + reparacion segura
REM  Repara todo MENOS lo que no se puede deshacer.
REM  Se eleva a administrador solo.
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
echo  ============================================================
echo   Esto va a:
echo     - reiniciar el servicio de cola de impresion si esta caido
echo     - sacar la impresora de modo offline / pausada
echo     - restaurar la App Nativa de Fudo si Defender la puso en cuarentena
echo     - reasignar el puerto USB si la impresora se cambio de puerto
echo     - instalar el driver y una cola de prueba si hace falta
echo     - IMPRIMIR UN TICKET DE PRUEBA (avisale al cliente)
echo.
echo   NO va a borrar los trabajos de la cola de impresion.
echo   Si hay comandas trabadas y las queres limpiar, usa
echo   4-Reparar-todo-incluida-la-cola.cmd
echo  ============================================================
echo.
pause
echo.
powershell -NoProfile -ExecutionPolicy Bypass -File "%~dp0FudoPrintDoctor.ps1" -SkipIrreversible
echo.
pause
