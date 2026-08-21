@echo off
REM ============================================================
REM  FUDO PRINT DOCTOR - Diagnostico (NO cambia nada en la PC)
REM  Doble clic para correr. No necesita permisos de admin.
REM ============================================================
setlocal
cd /d "%~dp0"
title Fudo Print Doctor - diagnostico
echo.
echo  Corriendo diagnostico (modo seguro, sin aplicar cambios)...
echo.
powershell -NoProfile -ExecutionPolicy Bypass -File "%~dp0FudoPrintDoctor.ps1" -DryRun
echo.
echo  ------------------------------------------------------------
echo   Para que el motor ADEMAS repare, cerra esta ventana y usa:
echo   2-Diagnosticar-y-reparar.cmd
echo  ------------------------------------------------------------
echo.
pause
