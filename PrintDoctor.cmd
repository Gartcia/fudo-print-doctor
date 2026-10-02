@echo off
REM ================================================================
REM  PRINT DOCTOR - launcher de Deli (Brasil)
REM  GENERADO por tools\Generar-LauncherDeli.ps1 desde FudoPrintDoctor.cmd:
REM  los cambios van alla, no aca. Mismo motor, con -Idioma pt-BR.
REM  Doble clic. Diagnostica y repara el flujo de impresion.
REM  Se eleva a administrador solo. Deja resultado.json al lado.
REM ================================================================
REM  Este archivo hace seis cosas antes y despues del motor, y todas
REM  salieron de casos reales:
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
REM   6. Abre el diagnostico en el navegador (-Ui web). Esta ventana
REM      sigue siendo la que manda y sigue mostrando todo: si el
REM      navegador no abre, o el puerto local esta bloqueado, el motor
REM      avisa y sigue por consola. La interfaz no puede ser condicion
REM      para diagnosticar en la PC de un cliente que ya tiene un
REM      problema.
REM ================================================================
REM  LAUNCHER-VERSION: 7   <- subir esto cuando cambie este archivo. El
REM  updater no lo pisa (lleva la URL de telemetria), asi que hoy la copia
REM  interna se distribuye a mano. El marcador queda para que el updater
REM  pueda comparar y refrescarlo preservando la URL.
setlocal
cd /d "%~dp0"
title Print Doctor

REM ----------------------------------------------------------------
REM  TELEMETRIA (opcional): pegar entre las comillas la URL del Apps
REM  Script para que cada corrida reporte sola. Este es el archivo que
REM  SI se copia a la PC del cliente, asi que no hay ningun archivo
REM  extra que olvidarse. El repositorio publico lo deja vacio: para
REM  armar la copia interna, usar tools\Configurar-Telemetria.cmd.
REM ----------------------------------------------------------------
set "FUDO_TELEMETRY_URL="

set "FPD_MOTOR=%~dp0PrintDoctor.ps1"
set "FPD_JSON=%~dp0resultado.json"
set "FPD_RAW=https://raw.githubusercontent.com/Gartcia/fudo-print-doctor/main"

REM ----------------------------------------------------------------
REM  1) Puede esta PC correr el motor?
REM  El sondeo se escribe con sintaxis de PowerShell 2.0 a proposito:
REM  tiene que poder correr justamente en las PCs que vamos a rechazar.
REM ----------------------------------------------------------------
powershell -NoProfile -ExecutionPolicy Bypass -Command "$m=0; try { $m=$PSVersionTable.PSVersion.Major } catch {}; if ($m -lt 5) { exit 10 }; if (-not (Get-Command Get-Printer -ErrorAction SilentlyContinue)) { exit 11 }; exit 0"
if errorlevel 12 goto sin_powershell
if errorlevel 11 goto windows_viejo
if errorlevel 10 goto ps_vieja
REM  Launcher 6 (29/09/2026): este sondeo va ANTES de pedir permisos de
REM  administrador. Antes iba despues, y en una PC con Windows 7 el asesor
REM  pasaba por el pedido de permisos -que por TeamViewer deja la pantalla
REM  en negro hasta que el cliente acepta- para terminar leyendo que el
REM  motor no puede correr ahi. El sondeo no necesita ser administrador.

REM  Launcher 6: si este archivo o el motor llegaron con la marca de Windows
REM  de "descargado de internet" (el ZIP que se comparte por Slack o Drive la
REM  arrastra), se les saca aca, y solo a esos dos. La primera vez Windows
REM  pregunta igual -un archivo no puede desmarcarse antes de que lo abran-,
REM  pero las corridas siguientes en esta PC ya no. Lo mismo que tildar
REM  "Desbloquear" en Propiedades.
set "FPD_SELF=%~f0"
powershell -NoProfile -ExecutionPolicy Bypass -Command "foreach ($f in @($env:FPD_SELF, $env:FPD_MOTOR)) { try { if ($f -and (Test-Path -LiteralPath $f)) { Unblock-File -LiteralPath $f -ErrorAction Stop } } catch {} }" >nul 2>&1

net session >nul 2>&1
if errorlevel 1 goto elevar
goto admin_ok

:elevar
echo  Pedindo permissao de administrador...
powershell -NoProfile -Command "Start-Process -FilePath '%~f0' -Verb RunAs"
exit /b

:admin_ok
REM  Launcher 7 (01/10/2026): apagar la "edicion rapida" de ESTA ventana. Con ella activada,
REM  un clic adentro (por TeamViewer pasa sin querer, al traer la ventana al frente) pone la
REM  ventana en modo "Seleccionar" y congela lo que esta corriendo hasta que alguien aprieta
REM  una tecla. Dos asesores lo mandaron con captura: trabado en "Descargando el motor...".
REM  El motor ya lo hacia desde la 3.36, pero arranca despues de las descargas de aca abajo.
REM  OJO: no alcanza con apagarla una vez desde aca. cmd vuelve a poner su configuracion de la
REM  ventana cada vez que termina un programa que lanzo (probado: dentro del powershell queda
REM  apagada; al volver a cmd, prendida otra vez). Por eso se apaga ADENTRO de cada paso que
REM  tarda: las dos descargas de aca abajo la ejecutan primero. FPD_QE es ese codigo en base64
REM  (UTF-16), para no pelear con las comillas del batch; el legible esta en el CHANGELOG 3.37.
REM  Es un ajuste de esta ventana, que se cierra al terminar.
set "FPD_QE=dAByAHkAIAB7ACAAQQBkAGQALQBUAHkAcABlACAALQBUAHkAcABlAEQAZQBmAGkAbgBpAHQAaQBvAG4AIAAnAHUAcwBpAG4AZwAgAFMAeQBzAHQAZQBtADsAIAB1AHMAaQBuAGcAIABTAHkAcwB0AGUAbQAuAFIAdQBuAHQAaQBtAGUALgBJAG4AdABlAHIAbwBwAFMAZQByAHYAaQBjAGUAcwA7ACAAcAB1AGIAbABpAGMAIABzAHQAYQB0AGkAYwAgAGMAbABhAHMAcwAgAEYAcABkAFEAZQAgAHsAIABbAEQAbABsAEkAbQBwAG8AcgB0ACgAIgBrAGUAcgBuAGUAbAAzADIALgBkAGwAbAAiACkAXQAgAHAAdQBiAGwAaQBjACAAcwB0AGEAdABpAGMAIABlAHgAdABlAHIAbgAgAEkAbgB0AFAAdAByACAARwBlAHQAUwB0AGQASABhAG4AZABsAGUAKABpAG4AdAAgAG4AKQA7ACAAWwBEAGwAbABJAG0AcABvAHIAdAAoACIAawBlAHIAbgBlAGwAMwAyAC4AZABsAGwAIgApAF0AIABwAHUAYgBsAGkAYwAgAHMAdABhAHQAaQBjACAAZQB4AHQAZQByAG4AIABiAG8AbwBsACAARwBlAHQAQwBvAG4AcwBvAGwAZQBNAG8AZABlACgASQBuAHQAUAB0AHIAIABoACwAIABvAHUAdAAgAHUAaQBuAHQAIABtACkAOwAgAFsARABsAGwASQBtAHAAbwByAHQAKAAiAGsAZQByAG4AZQBsADMAMgAuAGQAbABsACIAKQBdACAAcAB1AGIAbABpAGMAIABzAHQAYQB0AGkAYwAgAGUAeAB0AGUAcgBuACAAYgBvAG8AbAAgAFMAZQB0AEMAbwBuAHMAbwBsAGUATQBvAGQAZQAoAEkAbgB0AFAAdAByACAAaAAsACAAdQBpAG4AdAAgAG0AKQA7ACAAfQAnADsAIAAkAGgAIAA9ACAAWwBGAHAAZABRAGUAXQA6ADoARwBlAHQAUwB0AGQASABhAG4AZABsAGUAKAAtADEAMAApADsAIAAkAG0AIAA9ACAAWwB1AGkAbgB0ADMAMgBdADAAOwAgAGkAZgAgACgAWwBGAHAAZABRAGUAXQA6ADoARwBlAHQAQwBvAG4AcwBvAGwAZQBNAG8AZABlACgAJABoACwAIABbAHIAZQBmAF0AJABtACkAKQAgAHsAIABbAHYAbwBpAGQAXQBbAEYAcABkAFEAZQBdADoAOgBTAGUAdABDAG8AbgBzAG8AbABlAE0AbwBkAGUAKAAkAGgALAAgAFsAdQBpAG4AdAAzADIAXQAoACgAWwBpAG4AdAA2ADQAXQAkAG0AIAAtAGIAbwByACAAMAB4ADgAMAApACAALQBiAGEAbgBkACAANAAyADkANAA5ADYANwAyADMAMQApACkAIAB9ACAAfQAgAGMAYQB0AGMAaAAgAHsAfQA="

REM ----------------------------------------------------------------
REM  2) El motor tiene que ser la version publicada, no la que quedo.
REM ----------------------------------------------------------------
echo  Procurando a versao publicada do motor...
set "FPD_PUB="
del /q "%~dp0version.tmp" >nul 2>&1
powershell -NoProfile -ExecutionPolicy Bypass -Command "try { iex ([Text.Encoding]::Unicode.GetString([Convert]::FromBase64String($env:FPD_QE))) } catch {}; try { [Net.ServicePointManager]::SecurityProtocol=[Net.SecurityProtocolType]::Tls12 } catch {}; try { Invoke-WebRequest -Uri '%FPD_RAW%/VERSION' -UseBasicParsing -TimeoutSec 25 -OutFile '%~dp0version.tmp' } catch {}" >nul 2>&1
if exist "%~dp0version.tmp" for /f "usebackq tokens=* delims= " %%v in ("%~dp0version.tmp") do set "FPD_PUB=%%v"
del /q "%~dp0version.tmp" >nul 2>&1

if not defined FPD_PUB goto sin_internet
if not exist "%FPD_MOTOR%" goto bajar_motor

REM La version vive dentro del .ps1 como $script:SchemaVersion = 'X.Y'.
findstr /c:"SchemaVersion = '%FPD_PUB%'" "%FPD_MOTOR%" >nul 2>&1
if not errorlevel 1 goto motor_ok

echo.
echo  O motor desta pasta nao e a versao publicada (%FPD_PUB%).
echo  Atualizando...
del /q "%FPD_MOTOR%" >nul 2>&1
goto bajar_motor

:sin_internet
if not exist "%FPD_MOTOR%" goto bajar_motor
echo.
echo  ATENCAO: nao foi possivel consultar a versao publicada (este PC
echo  pode estar sem internet). Sera usado o motor desta pasta, que pode
echo  estar desatualizado.
echo.
goto motor_ok

:bajar_motor
echo  Baixando o motor...
echo.
powershell -NoProfile -ExecutionPolicy Bypass -Command "try { iex ([Text.Encoding]::Unicode.GetString([Convert]::FromBase64String($env:FPD_QE))) } catch {}; try { [Net.ServicePointManager]::SecurityProtocol=[Net.SecurityProtocolType]::Tls12 } catch {}; Invoke-WebRequest -Uri '%FPD_RAW%/FudoPrintDoctor.ps1' -UseBasicParsing -TimeoutSec 90 -OutFile '%FPD_MOTOR%'"
if not exist "%FPD_MOTOR%" goto sin_motor

:motor_ok
findstr /c:"FudoPrintDoctor" "%FPD_MOTOR%" >nul
if errorlevel 1 goto motor_invalido

echo.
echo  ================================================================
echo   PRINT DOCTOR
echo  ================================================================
echo   Vai revisar a cadeia de impressao e corrigir o que puder:
echo     - servico de fila de impressao (spooler)
echo     - impressora offline ou pausada
echo     - App Nativa em quarentena do antivirus
echo     - porta USB trocada
echo     - driver e instalacao da impressora, se faltar
echo.
echo   Uma janela com o diagnostico abre sozinha. Nela voce ve o que
echo   for sendo encontrado, e nela ele pergunta o que precisar.
echo   NAO feche esta janela: o diagnostico roda aqui.
echo   Se a janela nao abrir, o endereco fica escrito aqui embaixo.
echo.
echo   A tela foi feita para o cliente poder acompanhar
echo   enquanto voce usa.
echo.
echo   Primeiro ele pergunta como a impressora esta conectada: por cabo
echo   neste PC, pela rede, ou as duas. Se nao souber, escolha as duas.
echo.
echo   Depois ele pede o ID da conversa do Intercom: sao os
echo   15 numeros, e voce pode colar a URL inteira.
echo.
echo   Vai IMPRIMIR UM TICKET DE TESTE: avise o cliente.
echo   Depois ele pergunta se o papel saiu: e o unico jeito de
echo   saber se ficou resolvido, entao e bom ter a impressora
echo   a vista.
echo   Se houver pedidos travados na fila, ele pergunta antes.
echo.
echo  ================================================================
echo.
REM  Launcher 6: ya no espera un Enter. Lo pidio un asesor (29/09): era
REM  un paso mas antes de llegar a lo unico que hay que cargar, el ID.

REM  El resultado anterior se borra ANTES de correr: es la unica forma
REM  de saber despues si el motor llego a escribir el de esta corrida.
del /q "%FPD_JSON%" >nul 2>&1

REM  -Ui web: el motor abre una pagina en el navegador de esta PC y muestra ahi
REM  el diagnostico. Esta ventana sigue siendo la que manda -el diagnostico corre
REM  aca- y sigue mostrando todo, asi que si el navegador no abre no se pierde
REM  nada. Si el puerto local no se puede abrir, el motor avisa y sigue solo por
REM  esta ventana: la interfaz nunca es condicion para diagnosticar.
REM  -NoNativaKitCheck: el instalador de la App Nativa pesa casi 60 MB y no entra
REM  por la transferencia de archivos del acceso remoto, asi que por decision no
REM  viaja en el kit. Sin esto el motor lo pediria en cada corrida y nadie podria
REM  resolverlo. El hallazgo se sigue registrando y viaja en la telemetria; cuando
REM  haga falta de verdad, se pasa partido con tools\Partir-Nativa.ps1.
REM  -LauncherStamp: la fecha de ESTE archivo. El .cmd no se autoactualiza -lleva la
REM  URL de reporte, por eso no se pisa-, asi que hay asesores con launchers viejos y
REM  no habia forma de saber quienes: una corrida que no arranca no reporta nada, y un
REM  launcher anterior al 10/09/2026 puede escribir RESUELTO sin que el motor corra.
REM  Al publicar un .cmd nuevo, actualizar esta fecha.
set "FPD_STAMP=2026-10-01"
powershell -NoProfile -ExecutionPolicy Bypass -File "%FPD_MOTOR%" -Idioma pt-BR -Ui web -NoNativaKitCheck -LauncherStamp "%FPD_STAMP%" -JsonOut "%FPD_JSON%"
set FPD_EXIT=%errorlevel%

echo.
echo  ----------------------------------------------------------------
if not exist "%FPD_JSON%" goto sin_resultado

if "%FPD_EXIT%"=="0" echo   RESOLVIDO. Testar imprimir um pedido pela Deli.
if "%FPD_EXIT%"=="2" echo   Ainda ha coisas a fazer: veja o que fazer agora aqui em cima.
if "%FPD_EXIT%"=="3" echo   O motor teve uma falha interna: escalar com o resultado.json.
if "%FPD_EXIT%"=="5" echo   O motor esta desatualizado e nao diagnosticou. Abra este arquivo de novo.
if "%FPD_EXIT%"=="6" echo   Falta o ID da conversa: sem ele nao da para acompanhar o caso.
if "%FPD_EXIT%"=="7" echo   Falta o instalador do App Nativa. Copie ao lado deste arquivo.
echo   Detalhe completo: %FPD_JSON%
echo  ----------------------------------------------------------------
goto limpiar

:sin_resultado
echo   O MOTOR NAO CHEGOU A DIAGNOSTICAR: nao gerou o resultado.
echo.
echo   NAO considerar isto resolvido. Se aparecer um erro em vermelho
echo   aqui em cima, tire um print e escreva em #fudo-print-doctor: e um
echo   bug do motor, nao do cliente.
echo  ----------------------------------------------------------------
set FPD_EXIT=3

:limpiar
REM  No dejar herramientas nuestras en la PC del cliente. El
REM  telemetria.txt se borra siempre: lleva la URL interna de reporte.
del /q "%~dp0telemetria.txt" >nul 2>&1
REM  Launcher 7 (01/10/2026): el motor se borra siempre, sin preguntar. La pregunta la
REM  hacia esta ventana cuando la interfaz ya estaba cerrada, asi que nadie se enteraba de
REM  que estaba esperando (lo conto un asesor). Borrarlo no le quita nada: si hay que
REM  correrlo de nuevo en esta PC, este archivo lo vuelve a bajar solo.
del /q "%FPD_MOTOR%" >nul 2>&1
echo.
echo  Pronto. Ficou so o resultado.json: anexe ao caso e apague.

:fin
echo.
pause
exit /b %FPD_EXIT%

:ps_vieja
echo.
echo  ================================================================
echo   ESTE PC NAO CONSEGUE RODAR O DIAGNOSTICO
echo  ================================================================
echo   Tem uma versao do PowerShell anterior a 5, que e do
echo   Windows 7 ou anterior. O motor nao funciona nele.
echo.
echo   Nada foi executado. NAO e um problema do cliente nem da
echo   impressora: e este PC.
echo.
echo   O que fazer: resolver o caso manualmente e anotar na
echo   conversa que o PC tem Windows antigo.
echo  ================================================================
echo.
pause
exit /b 8

:windows_viejo
echo.
echo  ================================================================
echo   ESTE PC NAO CONSEGUE RODAR O DIAGNOSTICO
echo  ================================================================
echo   Falta o gerenciamento de impressoras do Windows
echo   (Get-Printer), que existe desde o Windows 8. O motor precisa dele
echo   para ver as filas de impressao.
echo.
echo   Nada foi executado. Resolver o caso manualmente e deixar anotado.
echo  ================================================================
echo.
pause
exit /b 8

:sin_powershell
echo.
echo  Nao foi possivel executar o PowerShell neste PC, entao o diagnostico
echo  nao pode rodar. Nada foi executado.
echo.
pause
exit /b 8

:sin_motor
echo.
echo  Nao foi possivel baixar e nao esta na pasta. Este PC pode estar
echo  sem internet. Copie tambem o arquivo PrintDoctor.ps1
echo  junto com este .cmd e tente de novo.
echo.
pause
exit /b 1

:motor_invalido
del /q "%FPD_MOTOR%" >nul 2>&1
echo.
echo  O que foi baixado nao e o motor (o repositorio pode estar
echo  privado). Copie o arquivo PrintDoctor.ps1 junto com este .cmd.
echo.
pause
exit /b 1
