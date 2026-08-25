# Changelog

Formato: [Keep a Changelog](https://keepachangelog.com/es-ES/1.1.0/). Versionado del `schemaVersion` del JSON.

## [3.4] - 2026-08-25

Salió de la primera corrida de la revisión diaria de telemetría: tres corridas de una misma
PC de prueba mostraron que el motor se estaba diagnosticando a sí mismo.

### Corregido
- **El motor se contaminaba con su propia cola de prueba.** `FUDO-TEST-*` contaba como cola
  del cliente: en la corrida 2 el `escenarioLlegada` saltaba de `primera_instalacion` a
  `todas_funcionan` y `cantidadColas` subía, o sea que la corrida N+1 diagnosticaba la basura
  de la corrida N (y la telemetría de escenarios quedaba inflada). Ahora cada cola lleva
  `esDePrueba` y las propias quedan fuera de `llegada`, de `cantidadColas` y de `impresoras`.
- **Los tickets de prueba del motor entraban al historial del spooler.** El filtro
  `(?i)node print job|fudo` también matcheaba `Fudo Print Doctor Test`, así que el motor
  podía concluir `si_imprimio_comandas_de_fudo` por sus propios tickets. Se descartan por
  nombre de documento antes de contar.
- **La cola de prueba se borra de verdad.** Tres intentos, limpiando los trabajos pendientes
  entre uno y otro (un trabajo colgado impide el borrado), y si sobrevive el chequeo pasa a
  `fail` con el `Remove-Printer` exacto — antes quedaba en `warn` y la cola se acumulaba.
- **`nativa.installed` decía lo contrario de lo que encontraba.** El nombre del chequeo es el
  texto que sale como CAUSA en consola y telemetría, y decía "App Nativa de Fudo instalada"
  con el status en `fail`. Ahora dice "NO instalada" (con la huella vacía como evidencia), o
  "instalada pero NO está corriendo" según el caso.
- **Restaurar de cuarentena se marcaba `fixed` sin verificar.** Se vio `fixed` en
  `nativa.defenderQuarantine` con `nativa.installed` en `fail` y la transición en
  `sigue_fallando` dos corridas seguidas. Ahora se vuelve a buscar la instalación después de
  restaurar: si la Nativa no aparece, queda en `warn` con la indicación de **reinstalar** —
  y si la corrida anterior de esa PC ya había intentado lo mismo, lo dice.
- **Habilitar el log de impresión ya no es una "reparación".** `fudo.usoReal` con historial no
  disponible pasa de `fixed` a `warn`: es un dato que falta, no un arreglo. Inflaba
  `autoFixCount`, ensuciaba la columna `reparaciones` y podía dar por resuelta una corrida que
  solo había encendido un log.

### Agregado
- Self-test: 129 asserts (S41 la cola del motor no cuenta como cola del cliente; S42 los
  patrones de auto-reconocimiento no confunden comandas ni colas reales).

## [3.3] - 2026-08-25

### Corregido
- **El menú de acciones no dejaba elegir nada.** Dos causas, las dos arregladas:
  - Apretar Enter sin escribir una letra caía en `if (-not $r) { return 'S' }`, o sea
    **cerraba la app en silencio**. Ahora vuelve a preguntar y avisa qué escribir; solo `S`
    sale.
  - Si la ventana se abre desde otro proceso (herramienta de acceso remoto, tarea
    programada, un acceso directo), `stdin` puede llegar cerrado: `pause` de cmd sigue
    funcionando porque lee la consola, pero `Read-Host` de PowerShell devuelve vacío al
    instante y el menú se cerraba solo. Ahora la lectura intenta `stdin` y, si no hay,
    abre **`CONIN$`** (el dispositivo de consola) directo. Si tampoco hay teclado, lo
    **dice** en vez de salir sin explicación.
- El menú ahora acepta **una sola tecla, sin Enter**.
- Los sub-prompts (nombre de la impresora, IP a instalar, ruta del JSON, confirmación de
  acciones irreversibles, "¿salió el papel?") usan la misma lectura, así que tampoco se
  saltean solos cuando `stdin` no sirve.

### Agregado
- `Resolve-MenuChoice`, la decisión del menú separada de la lectura del teclado para poder
  testearla. Self-test: 123 asserts (S40).

## [3.2] - 2026-08-25

Dos casos reales de asesores: uno dio "impresión OK" con la impresora sin imprimir, el otro
reconoció bien la cola rota pero no le cambió el puerto.

### Corregido
- **Falso positivo de "el hardware imprime"**. `WritePrinter` devuelve OK cuando el *spooler*
  acepta los bytes, y el spooler da el trabajo por impreso cuando el *dispositivo* los acepta:
  sin rollo, con la tapa abierta o con un adaptador USB-paralelo sin impresora del otro lado, la
  cola queda limpia y no salió nada. Ahora, cuando el ticket sale de la cola, se le **pregunta al
  humano** si salió el papel (`Confirm-PaperCameOut`). `hw.testprint` queda en `ok` solo si alguien
  lo confirmó; sin confirmar queda en `warn` ("enviado, sin confirmar") y nunca en `ok`. Aplica
  también a la opción `[T]` del menú, que era la que afirmaba "si salió el papel, el hardware
  imprime" sin verificar nada.
- **La verificación miraba una sola vez a los 1,5 s**. Reemplazada por `Wait-QueueDrain`, que
  espera hasta 8 s haciendo poll y además cuenta los **trabajos ajenos** que están delante.
- **El puerto no se cambiaba nunca cuando la cola estaba trabada**. Caso real: cola marcada
  offline con 11 comandas de julio atascadas; el motor probaba USB002 y USB003, el ticket de prueba
  quedaba detrás de las 11, todos los candidatos "fallaban" y revertía el puerto a USB001 dejando
  el problema intacto. Ahora `Unblock-QueueForTest` saca la marca offline, reanuda la cola y
  descarta tickets de prueba viejos *antes* de probar puertos; si además hay comandas del cliente
  bloqueando, se ofrece limpiarlas y, si no se confirma, el chequeo dice
  **"prueba bloqueada por la cola"** en vez de afirmar que ningún puerto imprime.
- **Puertos vivos fantasma**. Un nodo `USBPRINT` cuyo descriptor dice literalmente
  `No Printer Attached` (típico de adaptadores USB-paralelo y clones POS) ya no cuenta como
  dispositivo conectado: el puerto existe pero del otro lado no hay impresora.
- **Impresoras de red contadas como hardware USB**. Los devices `SWD\PRINTENUM\WSD-...` y
  `Microsoft IPP Class Driver` inflaban "HARDWARE DE IMPRESION CONECTADO" y generaban puertos
  candidatos que no existen. Se descartan del inventario USB.
- **Colas de prueba acumulándose en el panel del cliente** (se llegaron a ver 10 impresoras con
  `POS-80 (copy 1)`, `(copy 2)` y `FUDO-TEST-*`). Ahora la cola temporal se borra sola salvo que
  haya impreso de verdad; `-KeepTestPrinter` sigue forzando que se conserve.

### Agregado
- Chequeo `hw.noPortBound`: la impresora está presente y enumerada pero **Windows no le asignó
  ningún puerto USB** (no hay nodo `USBPRINT` con `PortName`). En ese estado ninguna cola puede
  imprimirle y cambiar el puerto de la cola no sirve: la indicación es desenchufar/enchufar con la
  impresora encendida en un puerto directo, o instalar el driver Genérico/Solo texto, que es lo que
  crea el puerto.
- `confirmadoPorHumano` en la evidencia de `hw.testprint`, para poder separar en la telemetría las
  corridas verificadas de las que quedaron sin confirmar.
- Self-test: 117 asserts (S37 sin consola no se afirma que salió papel; S38 `hw.noPortBound`).

## [2.1] - 2026-08-22

### Agregado
- **A qué cola le manda Fudo**: se lee el log del spooler
  (`Microsoft-Windows-PrintService/Operational`, evento 307) y se identifican los trabajos de la App
  Nativa (`node print job`). Dice qué cola recibió comandas y cuándo fue la última. Si el log está
  deshabilitado —viene así de fábrica— se habilita (reversible) para la próxima corrida.
- **Contexto de la PC** en el JSON y en la telemetría: sistema operativo con build y arquitectura,
  versión de PowerShell, Chrome, Edge, versión de la App Nativa, país, cultura, zona horaria,
  conexión de la PC (cable o wifi) y cantidad de colas e impresoras físicas.
- **Instalador local de la Nativa**: `-NativeInstallerPath` (y autodetección de `Fudo*.exe` al lado
  del script, en Descargas o en el Escritorio) para instalarla sin que el cliente descargue nada.
  `-NativeInstallerArgs` para flags de instalación silenciosa.
- Receptor de telemetría listo para usar: `tools/telemetria-appscript.gs` (Google Sheets + Apps
  Script) y `docs/telemetria.md`.
- La IP de una impresora de red detectada aparece en `nextActions`, con el paso concreto para
  cargarla en Fudo.

### Corregido
- `Join-Path` con base `$null` explotaba en Windows de 32 bits (donde no existe
  `ProgramFiles(x86)`) al buscar Chrome, Edge o el instalador de la Nativa.
- Los textos de impresoras de red distinguen los dos caminos de Fudo (Directo Ethernet, que no usa
  colas de Windows, vs impresora del sistema operativo) y ya no dan a entender que una cola de
  Windows implique que Fudo la tenga configurada.

## [2.0] - 2026-08-22

### Corregido
- El JSON se imprimía en pantalla arriba del resumen. La detección de redirección
  (`[Console]::IsOutputRedirected`) no es confiable en Windows PowerShell dentro de un `.cmd`, así
  que ahora el JSON va a stdout **solo con `-Json`**. El resumen humano quedó al final de la salida.

### Agregado
- **Menú de acciones** al terminar (consola interactiva): volver a revisar, esperar la reconexión del
  USB, instalar la impresora conectada, limpiar la cola, buscar impresoras por IP, instalar una de
  red, instalar la Nativa, imprimir un ticket de prueba, ver el detalle o guardar el JSON. Ya no hay
  que cerrar y reabrir la app para reintentar. `-NoMenu` lo desactiva.
- **Ethernet**: barrido de la subred con identificación real (`DLE EOT`, que una térmica responde),
  reporte de cuántas y cuáles se encontraron, detección de las que ya tienen cola en Windows, e
  instalación por IP con driver de texto genérico (`-InstallNetworkPrinter` o menú).
- **Telemetría opcional**: `-TelemetryUrl` / `$script:TelemetryUrl` envía por POST un resumen del
  resultado, para no depender de que el asesor guarde el JSON. `-TelemetryFull` manda todo.
- **App Nativa**: `-NativeInstallerUrl` permite descargarla e instalarla agregando primero las
  exclusiones de antivirus. Sin URL, se guían los pasos manuales.

## [1.9] - 2026-08-21

### Corregido
- **Se diagnosticaba la impresora equivocada.** En un local con caja y cocina, el motor tomaba la
  primera cola que encontraba: en un caso real eligió COCINA (que funcionaba) y devolvió "todo ok"
  mientras CAJA estaba offline, con el puerto muerto y **1440 trabajos encolados**. Ahora se evalúan
  todas las colas reales con un puntaje de severidad y se diagnostica la que falla. Las sanas se
  listan como "funcionando — no se toca".
- Contradicción en el resumen: la misma impresora podía aparecer a la vez como conectada y como
  desconectada (venía de dos fuentes con `InstanceId` distinto). Se deduplica por puerto y por
  nombre del equipo, y las entradas históricas se nombran con la cola de Windows que usa ese puerto.
- `No Printer Attached`, `Printer` y similares son etiquetas del driver, no modelos: cuando el
  device no dice nada útil se muestra el nombre de la cola.

### Agregado
- **Reconexión guiada**: cuando la cola apunta a un puerto muerto, el motor espera a que se
  desenchufe y se vuelva a enchufar el USB, detecta el puerto nuevo, apunta la cola ahí, prueba un
  ticket y, si hace falta, recrea la cola. Es la secuencia que resolvió el caso real.
- `Repair-QueueRecreate`: reemplazo seguro de una cola rota. Crea una cola temporal, comprueba que
  imprima, y solo entonces borra la vieja y renombra la nueva con el mismo nombre (Fudo encuentra la
  impresora por nombre). Nunca deja al cliente sin cola.
- Resumen reorganizado: primero las impresoras instaladas en Windows con estado y síntomas, después
  el hardware conectado.
- Mensaje específico con decenas de trabajos acumulados: las comandas llegan desde Fudo, el problema
  está en la impresora o su cola.
- Parámetros `-WaitReconnect`, `-ReconnectTimeoutSec`.

## [1.8] - 2026-08-21

### Agregado
- Distribución y actualización: `VERSION` publicado en el repo, `Actualizar-FudoPrintDoctor.cmd`
  para que el asesor tenga siempre la última, aviso en el resumen cuando corre una versión vieja,
  `-CheckUpdate` y `-NoUpdateCheck`. El launcher del cliente descarga el `.ps1` si falta.

## [1.7] - 2026-08-21

### Corregido
- **Una impresora desenchufada seguía figurando como conectada.** El registro `Enum\USBPRINT` es
  histórico: guarda toda impresora que estuvo conectada alguna vez. Ahora se cruza contra los
  dispositivos realmente presentes (`Win32_PnPEntity` / `Get-PnpDevice -PresentOnly`). Si la
  presencia no se puede verificar, no se afirma que esté desconectada.
- Ya no se "repara" el modo offline de una impresora desenchufada: el offline es consecuencia de
  la desconexión, y repararlo enmascaraba el problema real (y volvía a ponerse offline).
- La prueba física no corre sobre un puerto sin hardware, y cuando corre verifica que el ticket
  haya **salido** de la cola: `WritePrinter` OK solo significa que el spooler lo aceptó.

### Agregado
- Checks `hw.disconnected` ("instalada pero DESCONECTADA, estaba en USB00x") y
  `printer.disconnected` (la cola apunta a un puerto sin dispositivo).
- Sección `DESCONECTADAS` en el resumen, con el puerto donde estaba cada una.
- `diagnostics.impresorasDesconectadas[]` y `diagnostics.presenciaVerificada`.
- Categoría `hardware.desconectada`.

## [1.6] - 2026-08-21

### Agregado
- Progreso en vivo en la consola: una línea por etapa con `[n/9]`, resultado, color y duración, y
  detalle de lo que está haciendo mientras corre. Solo cuando hay un humano mirando; en modo
  agente no cambia nada.

## [1.5] - 2026-08-21

### Cambiado
- **Un solo punto de entrada**: `FudoPrintDoctor.cmd`. Los cuatro launchers anteriores confundían
  más de lo que ayudaban: había que elegir entre "diagnosticar", "reparar", "reparar todo" y "para
  el agente" antes de saber qué estaba pasando.
- La decisión sobre la única acción irreversible (limpiar la cola) se movió del launcher al script:
  si hay un humano en la consola se le pregunta; si corre un agente no se aplica y queda como
  acción pendiente en el JSON con el comando exacto. Se fuerza con `-AllowQueuePurge $true/$false`.

### Corregido
- `$PSBoundParameters` dentro de una función no es el del script, así que `-KeepTestPrinter:$false`
  nunca borraba la cola de prueba.

## [1.4] - 2026-08-21

### Corregido
- **Falso positivo de detección**: cualquier dispositivo USB podía pasar por impresora. El token
  `POS` de la lista de marcas matcheaba `USB Com`**`pos`**`ite Device` y `Generic` matcheaba
  `Generic USB Hub`. Ahora hay un clasificador explícito (`Test-IsPrinterDevice`) con señales
  ordenadas por certeza: interfaz `USBPRINT` / clase `Printer` / driver `usbprint` /
  `CompatibleID USB\Class_07` (clase USB 07h del estándar) → alta; VID de fabricante de
  impresoras → media; nombre que menciona impresora o modelo típico → baja. Mouse, teclados,
  hubs, composites, audio, cámaras y almacenamiento se descartan.
- `Test-IsPosPrinter` (heurística sobre colas de Windows) usa límites de palabra.
- `5890` y `80c` salieron de la lista de marcas: son números de modelo, y generaban etiquetas
  absurdas como "80c XP" para una `XP-80C`.

### Agregado
- `hardware.usbDevicesRejected[]`: qué dispositivos USB se descartaron y por qué.
- `deteccion` y `certeza` por impresora; el resumen las muestra cuando la certeza no es alta.
- `-SkipIrreversible`: repara todo menos lo que no se puede deshacer (hoy, la purga de la cola).
- Launcher `2-Diagnosticar-y-reparar.cmd` usa `-SkipIrreversible` y avisa qué va a hacer antes de
  arrancar; la purga de cola queda en `4-Reparar-todo-incluida-la-cola.cmd`.

## [1.3] - 2026-08-21

### Agregado
- Conteo y listado de impresoras físicas conectadas, con marca/modelo cuando se puede identificar
  (nombre + `InstanceId` + tabla de VID USB) y su puerto.
- Check `hw.driverPlan`: por cada impresora decide si corresponde el driver del fabricante
  (Epson, Bixolon, Star, Citizen, Zebra, Custom, Sam4s, Sewoo, Posiflex, Hasar) o el inbox
  `Generic / Text Only`. Si el driver OEM ya está instalado, lo usa para la cola de prueba.
- Switch `-Json` para forzar el JSON a stdout.

### Cambiado
- Consola legible: resumen compacto (impresoras detectadas, semáforo por área, causa, hasta 3
  acciones) con color cuando la consola es interactiva. `-Verbose` lista todos los chequeos.
- Si la salida no está redirigida, el JSON ya no se vuelca a pantalla: se guarda en
  `%TEMP%\FudoPrintDoctor-<fecha>.json` y se informa la ruta.
- `nextActions[].owner` simplificado a `cliente` / `asesor` / `soporte`.

## [1.2] - 2026-08-21

### Agregado
- **Capa 1a**: inventario de hardware antes de elegir impresora. Registro `Enum\USBPRINT`
  (mapeo device → USB00x), `Get-PnpDevice` y `Win32_PnPEntity` como fallback.
- Detección de puertos USB00x huérfanos y de dispositivos presentes sin driver (código 28).
- Instalación del driver inbox genérico + cola `FUDO-TEST-<puerto>` cuando hay hardware sin cola.
- Bloque `hardware` en el JSON. Categorías `hardware.no_conectada`, `os.driver_faltante`,
  `os.impresora_virtual`.
- Parámetros `-InstallGenericDriver`, `-KeepTestPrinter`.

### Corregido
- **Falso positivo grave**: el motor elegía `Microsoft Print to PDF` como objetivo y el envío RAW
  contra esa cola devolvía éxito, concluyendo "el hardware imprime OK". Ahora las impresoras
  virtuales se descartan por nombre, driver y puerto, y la prueba física se saltea sobre ellas.
- Capa 3 USB: compara el puerto de la cola contra el puerto donde está enumerado el device
  (caso del artículo 11730817) y prueba primero los puertos con hardware vivo.

## [1.1] - 2026-08-21

### Corregido
- **Crash en cualquier PC sin impresora POS**: con `Set-StrictMode -Version 2.0`, acceder a
  `.Count` sobre `$null` o un escalar lanza `PropertyNotFoundStrict`. `Resolve-TargetPrinter`
  hacía `$candidates = $allPrinters | Where-Object {...}` sin `@()`, y el run moría antes de
  emitir cualquier salida. Ahora `StrictMode 1.0` y todos los `.Count` blindados con `@()`.

### Agregado
- `Invoke-Step`: cada capa corre aislada; si una explota queda en `engineErrors[]` y el
  diagnóstico continúa.
- `try/catch` global: toda falla sale como JSON con `status:"engine_error"` y un `hint` accionable.
- `diagnosis.nextActions[]` priorizado con owner y artículo del Help Center.
- Preflight de parámetros, exit codes, stdout reservado al JSON delimitado.

## [1.0]

- Versión inicial: diagnóstico por capas, remediaciones idempotentes, JSON + resumen humano.
