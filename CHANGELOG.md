# Changelog

Formato: [Keep a Changelog](https://keepachangelog.com/es-ES/1.1.0/). Versionado del `schemaVersion` del JSON.

## [3.13] - 2026-09-03

La 3.12 subió el cierre de casos del 11% al 27%, y la revisión de hoy mostró que **3 de esos 4
cierres no verificaron nada del lado de Fudo** — y uno era falso otra vez. Esta vez la causa no
era el antivirus: era que el motor no distinguía *"Fudo sí imprime"* de *"no tengo idea"*.

### Corregido
- **Un caso podía cerrar diciendo que Fudo imprime cuando en realidad no había con qué saberlo.**
  El log de impresión de Windows **viene apagado de fábrica**. El motor lo enciende en esa misma
  corrida, así que el historial queda vacío: no hay ni una comanda que mirar. Ese chequeo salía
  con plano `os` ("falta un dato") y no con plano `fudo_config` ("falta la comanda"), así que no
  entraba en el cálculo y el caso cerraba con `fudoSinUso = false`, que se lee como *"Fudo está
  imprimiendo bien"*.
  En la telemetría fue **10 de 10 primeras corridas de cada PC**; y en la corrida siguiente de
  esas mismas PCs, con el log ya encendido, daba `true` **5 de 5**. Una PC cerró `resolved` a las
  11:32 y volvió como `volvio_a_fallar` 22 minutos después.
  Ahora el último tramo tiene **tres estados** en vez de un sí/no: `con_comandas` (el historial
  muestra comandas de Fudo), `sin_comandas` (se pudo mirar y no hay ninguna) y `sin_datos` (no hay
  con qué saberlo). Un cierre con `sin_datos` viaja marcado como `cierreSinVerificarFudo` y **le
  muestra al asesor una línea FALTA** diciendo que hay que mandar una comanda de prueba y volver a
  correr: antes ese caso cerraba mudo.
  *Consecuencia sobre la métrica: el cruce `resolved × fudoSinUso` daba 4/4 cierres completos y era
  un artefacto. Desde esta versión se puede separar el cierre completo del cierre a medio camino.*
- **El id de la causa y el texto de la causa salían de fuentes distintas.** Cuando el caso cerraba,
  el texto se armaba con la reparación de menor capa pero el id se tomaba de la lista de
  candidatos en `warn`. Se vio una fila con id `hw.notInstalled` y causa *"Puerto USB desmapeado"*
  —que es otro chequeo—, y con eso **la categoría salió de un chequeo que no era la causa**. Si el
  caso cerró, ahora manda la reparación: el id y el texto describen lo mismo.
- **Una corrida podía cerrar sin decir de dónde salió el cierre.** La rama que cierra sin haber
  reparado nada (la PC ya estaba sana) viajaba con `rootCauseCheckId` vacío. Tiene id propio:
  `ok.yaFuncionaba`. *La aserción que iba a garantizar esto en la 3.12 estaba mal escrita y pasaba
  siempre; ahora afirma el invariante de verdad.*
- **La causa de una prueba de impresión fallida era el título del paso.** Se veía
  `causaRaiz = "Prueba fisica ESC/POS por USB (RAW)"`, que no le dice nada al asesor. Las tres
  ramas de fallo ahora explican qué pasó (el ticket quedó en la cola / no se pudo enviar / no salió
  papel) y tienen categoría propia `hardware.no_imprime`.
- **El motor se mostraba a sí mismo en el historial del local.** El descarte de sus propios tickets
  de prueba estaba *después* de crear la entrada, así que una cola cuyo único trabajo fue el ticket
  del motor figuraba igual en el historial, con total 0 y con el nombre de su documento de prueba.
- **"No se pudo probar la impresión" decía siempre lo mismo por dos motivos distintos.** El motivo
  era `sin_impresora` tanto cuando no había nada enchufado como cuando la impresora **sí estaba**
  conectada y lo que faltaba era que Windows le asignara un puerto. Son dos casos con soluciones
  distintas: ahora el segundo dice `sin_puerto_asignado` y le explica al asesor que hay que
  reconectar el USB o instalar el driver genérico, que es lo que crea el puerto.

### Evaluado y NO implementado
- **Crear una cola de prueba cuando la impresora está conectada pero sin puerto asignado.** Se
  propuso a partir de un caso escalado sin prueba física. No se hizo, por dos razones: el motor
  **ya tiene** ese respaldo (cae a los puertos USB huérfanos cuando hay hardware presente sin
  mapeo), y en el caso concreto no había *ningún* puerto —ni vivo ni huérfano— sobre el que crear
  la cola. Inventar un puerto USB que no está respaldado por el dispositivo imprime al vacío, que
  es exactamente el bug que corrigió la 3.7 (el motor creando una cola y reportándola después como
  desconectada). Lo que sí se hizo es que el motivo del salteo diga la verdad, para que la próxima
  revisión pueda distinguir los dos casos con datos.
- **Renombrar el ticket de prueba con un prefijo propio para excluirlo del historial.** No hacía
  falta: el ticket ya se manda con el nombre `Fudo Print Doctor Test` y ya se excluía del conteo.
  Lo que estaba mal era el orden del descarte, corregido arriba. *El documento observado en la
  telemetría (`"Imprimir documento"` / `"Documento de Impressão"`) no es el ticket del motor: esa
  PC imprimió algo ajeno a Fudo de verdad.*
## [3.12] - 2026-09-02

La 3.11 cerró sus **primeros dos casos** —los primeros del proyecto— y uno de los dos fue un
**cierre falso**: cerró `resolved` a las 18:19:22 y 34 segundos después la misma PC volvió como
`volvio_a_fallar` re-aplicando exactamente las mismas dos reparaciones. Los dos cierres tenían la
misma causa raíz: la cuarentena de Defender sobre la App Nativa. Esta versión apuntala esa causa,
porque mientras siga disparando de más la métrica de cierre no mide nada.

### Corregido
- **La reparación del antivirus se ejecutaba en PCs donde no había nada que reparar.** El motor
  leía las detecciones de Defender con `Get-MpThreatDetection`, que devuelve el **historial de
  detecciones y no la cuarentena actual**: una detección de hace semanas sigue listada para
  siempre. Cualquier entrada de ese historial disparaba restaurar la Nativa de cuarentena y
  agregar exclusiones de Defender. En la telemetría aparecieron **6 corridas con la Nativa
  `0.0.37` —la firmada— instalada y presente que igual "repararon" el antivirus**, y esa quedó
  como la causa raíz de las dos únicas corridas que cerraron.
  Ahora la prueba de que la Nativa **no** está en cuarentena es que el archivo está en disco, y
  vale más que cualquier registro histórico: si está presente, no se toca la configuración del
  antivirus y la detección se informa como histórica, sin competir como causa raíz. Si el archivo
  **falta**, se repara igual que antes, incluso con la versión firmada: ahí el chequeo de versión
  no alcanza porque el archivo de verdad no está.
  *El gate de la 3.10 ("con la 0.0.37 el motor deja de tocar el antivirus") cubría la exclusión
  preventiva pero no esta rama.*
- **La categoría del caso salía de un regex sobre el texto de la causa.** Y ese texto lo escribe
  cada chequeo para que lo lea el asesor: *"App Nativa de Fudo NO instalada"* pegaba en el regex
  `no instalada` y caía en `os.driver_faltante`. En la planilla, **un mismo chequeo
  (`nativa.installed`) aparecía repartido en 4 categorías** (`nativa.install` ×12,
  `nativa.antivirus` ×5, `os.driver_faltante` ×4, `os.usb_port` ×2), así que la tabla CAUSA del
  dashboard no se podía agregar. Ahora la categoría sale del **id** del chequeo que ganó como
  causa; el texto para el asesor no cambió. Los ids cuya categoría depende del hallazgo concreto
  (`printer.exists`, que puede ser "no hay ninguna impresora real" o "solo hay virtuales") siguen
  resolviéndose por el texto.
- **Las corridas que reparaban algo sin confirmar el papel viajaban sin id de causa.** El
  `rootCauseCheckId` salía únicamente de la lista de candidatos, así que la rama *"se aplicaron
  reparaciones; falta confirmar que la comanda sale"* —**4 de 19 corridas** de la 3.11— llegaba
  vacía a la planilla y su categoría terminaba sin relación con la causa. Esa rama y las otras dos
  sin candidato tienen ahora id propio: `repair.pendingConfirm`, `fudo.configProbable` y
  `engine.inconclusive`.
- **`fudoSinUso` no viajaba en ningún payload.** Se calcula desde la 3.11 y era el dato que
  faltaba para separar el cierre completo del cierre a medio camino (la impresora imprime, pero
  todavía no salió ninguna comanda de Fudo). Sin eso no se puede saber si el criterio de cierre
  nuevo está midiendo bien. Ahora viaja, junto con `paperOk`, dentro del bloque de telemetría.

### Cambiado
- **Una cola con un solo trabajo trabado ya se informa.** El umbral eran 3 trabajos, y con eso
  `queue.otherBacklog` —el chequeo que la 3.11 agregó para mirar *todas* las colas— **no disparó
  ni una vez en 19 corridas**. El caso que se perdía: una PC con 8 colas arrastrando
  `REPOSTERIA [192.168.1.202]` con **un** trabajo trabado 28 minutos en tres corridas seguidas.
  Ahora entra desde 1 trabajo cuando el más viejo lleva 5 minutos o más, pero **solo informa**:
  lo que bloquea el cierre y compite como causa raíz sigue siendo el atasco de verdad (3 o más y
  de hace rato), para que un trabajo viejo no le gane la causa a nada. Una comanda recién
  encolada sigue sin decir nada: sería ruido en cada corrida de un local que imprime normal.
- **`printer.coverage` publica el valor y no solo el estado.** Viajaba como `ok`/`warn` sin el
  número, así que no había con qué decidir si la cobertura tiene que bloquear el cierre.

### Pendiente (no entró en esta versión)
- **Columnas propias de `fudoSinUso` y `paperOk` en la planilla.** Los dos datos ya viajan en el
  payload y se pueden leer del JSON, pero el receptor tiene una lista fija de columnas y
  agregarlas es un cambio en Apps Script que no cubre el self-test.
## [3.11] - 2026-09-01

Primera revisión con las 120 filas de la planilla legibles de punta a punta. Lo que apareció fue
que la métrica principal del proyecto —cuántos casos cierra el motor— **nunca midió nada**: el
motor no podía cerrar un caso ni cuando lo resolvía. Esta versión redefine cuándo un caso está
resuelto.

### Cambiado
- **Criterio de cierre: si la impresora imprime desde Windows, el caso está resuelto.** Eso es
  lo que este motor diagnostica y repara. Se sacan dos condiciones que hacían que casi nada
  pudiera cerrar:
  - **Se exigía que el historial del spooler mostrara alguna comanda de Fudo** (`fudo.usoReal`,
    gate de la 3.9). Eso vive en el backend de Fudo, no se puede verificar desde la PC del
    cliente y por lo tanto **iba a quedar pendiente siempre**. Ahora no bloquea: el caso cierra
    con confianza `media` en vez de `alta`, y el resumen agrega una línea **FALTA** diciendo que
    la impresora ya imprime pero que todavía no hay ninguna comanda de Fudo en el historial —
    hay que confirmar en Fudo que esté dada de alta con su cocina/área. El chequeo sigue vivo y
    sigue apareciendo en lo que el asesor tiene que revisar.
  - **Se exigía al menos una reparación aplicada.** Una PC que ya estaba sana y donde el ticket
    de prueba salía bien **no podía cerrar**: caía en *"Hardware imprime OK; causa probable en
    configuración de Fudo"* y la corrida entraba como `sigue_fallando`. Si imprime, está OK, se
    haya tocado algo o no. Esos casos ahora cierran con categoría `ok.ya_funcionaba`.

  *Lo que sigue bloqueando el cierre: cualquier chequeo en `fail` —ahí entran la Nativa no
  instalada, la cola atascada, el puerto sin dispositivo— y que no haya confirmación humana de
  que salió el papel.*

### Corregido
- **`resolved = true` y `status = needs_escalation` al mismo tiempo: el motor no podía cerrar un
  caso.** `needsEscalation` se calculaba como "no cerró **o** quedó algo residual", y el residual
  toma cualquier chequeo en `warn` con plano `fudo_config`. La capa 5 agrega cuatro
  (`fudo.printerRegistered`, `printerKitchen`, `categoryKitchen`, `rooms`) que **nacen en `warn`
  por construcción**: no se pueden verificar desde la PC, hacen falta la web app de Fudo o su
  backend. O sea que `needsEscalation` era siempre `true`, y como el `status` se armaba con
  `(resolved -and -not needsEscalation)`, **ninguna corrida podía salir `resolved`**.
  En la telemetría se vieron 5 filas con las dos cosas a la vez: la columna `resuelto` sumaba,
  el asesor leía ESCALAR en pantalla, y el bloque "qué resolvió" —que mira `status`— quedó vacío
  desde el día uno del proyecto. Los "18 resueltos" del resumen incluían casos que el propio
  motor mandaba a escalar.
  Ahora hay **una sola fuente de verdad**: el `status` se decide en `Resolve-Diagnosis` y de ahí
  lo leen la telemetría, el historial local de la PC y el código de salida.
  *La columna "qué resolvió" empieza a llenarse y el % de resueltos por fin mide algo. Si el
  número se mueve fuerte no es una regresión: antes medía humo.*
- **Una cola atascada de otra impresora ya no queda invisible.** La capa 2 sólo miraba la cola
  **objetivo**. En una PC del parque, `BARRA [192.168.0.17]` tenía **93 comandas** sin salir y
  `COCINA [192.168.0.50]` otras 13, y la causa raíz que ganó fue *"Ninguna impresora física
  conectada"* teniendo una `POS-80 [LPT1:]` sana. El mismo caso lo cerró un asesor a mano,
  preguntando "¿cola de impresión?".
  Ahora un chequeo nuevo (`queue.otherBacklog`) revisa **todas** las colas del cliente y levanta
  las que acumulan 3 o más trabajos. Si además el trabajo más viejo lleva 5 minutos o más
  esperando, entra como **causa raíz candidata y bloquea el cierre**; y si el puerto de esa cola
  sigue sirviendo (está vivo, o no es un USB), el veredicto USB —`hw.deviceConnected`,
  `hw.disconnected`, `conn.usb`— deja de poder ganar: si Fudo llegó a encolar comandas, decir
  que no hay ninguna impresora conectada es demostrablemente falso. Una ráfaga recién encolada
  queda en `warn` y no bloquea, porque puede estar drenando sola.
  *Además invierte el diagnóstico: comandas encoladas prueban que Fudo **sí** está mandando, así
  que el problema no está en la configuración de Fudo sino en esa cola o su impresora.*
- **El veredicto se armaba con una foto vieja de la PC.** El inventario de impresoras y colas se
  tomaba en la capa 1, **antes** de reparar, y nunca se volvía a leer. Una impresora que el motor
  acababa de poner en línea seguía contando como offline, una cola que acababa de purgar seguía
  contando como trabada, y un puerto recién re-bindeado seguía figurando sin dispositivo — en
  pantalla, en el veredicto y en la telemetría.
  Ahora hay un paso final de **re-escaneo** (`Update-PrintInventory`), después de limpiar las
  colas de prueba y antes de decidir la causa raíz: invalida el caché de presencia de
  dispositivos, vuelve a mapear qué puertos tienen algo enchufado y relee todas las colas con sus
  trabajos. Es sólo lectura. El chequeo de comandas encoladas se corrió también al final, para
  que una cola que el motor **sí** purgó deje de bloquear el cierre.
- **Un error dentro de `-SelfTest` escribía en la planilla de telemetría.** Se descubrió solo,
  desarrollando esta versión: una excepción adentro del self-test sale al `catch` global, y ese
  `catch` manda telemetría. Entró una fila `engine_error` de una corrida que jamás tocó una
  impresora, con el host de quien estaba desarrollando. Ahora `Send-Telemetry` corta de entrada
  cuando la corrida es un self-test.
- **Una corrida que explota ya no queda irrastreable.** Se vio una fila `engine_error` con `pcId`
  vacío, `entorno` en `null`, `corrida` en `null`, `duracionMs = 0`,
  `checks: [{"id":"","status":"","layer":null}]` y `autoFixesApplied: [null]` — y que sin embargo
  ya había re-bindeado un puerto USB y tocado una exclusión de Defender antes de crashear, sin
  dejar una línea de qué falló. La basura venía de que `@($null)` en PowerShell es un array de un
  elemento nulo, y el payload reducido lo serializaba como si fuera un chequeo real.
  Ahora el payload de `engine_error` lleva `pcId`, `entorno`, `duracionMs`, los chequeos que sí
  se alcanzaron a hacer, y un bloque `errorMotor` con el mensaje, el tipo, la línea, el comando,
  el stack, el último chequeo completado y el último paso que estaba corriendo. Los chequeos sin
  `id` se descartan.

### Agregado
- **`paperOk` viaja en la telemetría.** Se calculaba desde la 3.9 y no salía de la PC. Es lo que
  separa *"no sale nada"* de *"sale papel pero la comanda de Fudo todavía no"*, que son dos casos
  con acciones opuestas.
- **`fudoSinUso`**: marca las corridas que cerraron sin evidencia de que Fudo haya mandado nunca
  una comanda. Permite medir cuántos cierres quedan a medio camino sin volver a bloquearlos.
- **`printer.coverage`**: después del re-escaneo, dice cuántas de las impresoras del cliente
  quedaron en condiciones de imprimir y cuáles no, con el síntoma de cada una. Es informativo a
  propósito: no bloquea el cierre ni compite como causa raíz, porque un local puede tener una
  impresora vieja apagada que no tiene nada que ver con las comandas.
- **`colasQueMejoraron`**: las colas que estaban rotas al empezar y quedaron sanas al terminar.
  Es la medida directa de si las reparaciones sirvieron, por cola y no por corrida — hasta ahora
  no se podía calcular con nada de lo que llegaba a la planilla.
- **Antigüedad real de los trabajos en cola.** `Get-PrinterQueues` ahora devuelve
  `minutosMasViejo` además de la fecha formateada: sin el número no se puede distinguir una
  ráfaga que drena sola de 93 trabajos parados desde hace tres horas.

### Interno
- **El `.ps1` quedó 100% ASCII**, como pide la regla del proyecto. Quedaban tres caracteres
  acentuados: dos en textos de pantalla (se les sacó el acento) y uno dentro de un regex que
  matchea el driver "Genérico / Sólo texto" de un Windows en español — ese se conservó como
  escape `\xe9`, que .NET interpreta igual y no rompe en PCs con otra code page.

### Evaluado y no se hizo
- **Mover a un `finally` el rollback del re-bind de USB y de la exclusión de Defender.** No hay
  tal rollback que mover: esas dos son las **reparaciones**, no cambios temporales, y deshacerlas
  ante un crash dejaría al cliente peor. Lo que sí puede quedar colgado tras un crash es una cola
  `FUDO-TEST-*`, y eso ya lo limpia `Remove-StaleOwnQueues` en la corrida siguiente.
- **Mapear `pais` desde `paisProbable`.** Sigue viviendo en el receptor de telemetría
  (`tools/telemetria-appscript.gs`), fuera del alcance del self-test: no se toca a ciegas.

### Pendiente decidir
- **Un ticket de prueba por impresora.** El re-escaneo ya dice cuáles quedaron en condiciones de
  imprimir, pero la única con prueba física confirmada sigue siendo la cola objetivo. Probar
  todas implica un ticket y una confirmación del asesor por cada una: es un cambio de flujo para
  el asesor, va aparte.
- **Que `printer.coverage` bloquee el cierre.** Hoy avisa en `warn`. Hacerlo bloqueante es
  literalmente "todas las impresoras detectadas imprimiendo", pero un local con una impresora
  vieja apagada no cerraría nunca — que es justo el problema del que salimos. Conviene mirar
  primero cuántas PCs quedan con colas rotas ajenas a las comandas, que es un dato que esta
  versión recién empieza a mandar.

## [3.10] - 2026-08-28

Dos casos que un asesor probó en clientes reales el mismo día que salió la 3.9, y que entre los
dos explican por qué el motor casi nunca llegaba a cerrar un caso.

### Corregido
- **El ticket de prueba se imprimía pero quedaba adentro de la impresora.** El ticket terminaba
  con tres saltos de línea y `GS V 66 0` (cortar sin alimentar papel). En una térmica el cabezal
  está a 1-2 cm del cortador: con ese margen, el texto recién impreso **queda retenido dentro del
  mecanismo**, sale un pedazo de papel en blanco y lo impreso no asoma. El asesor mira, no ve
  nada y responde que no salió — con razón. El motor entonces daba por fallado un hardware que
  funcionaba, revertía el puerto y cerraba el caso como no resuelto.
  Se confirmó descartando todo lo demás: mismo puerto y mismo driver genérico que usa el motor,
  instalados a mano, imprimían bien y en menos de 3 segundos. Ahora el ticket empuja el papel
  (seis saltos de línea, más `ESC d` y corte con avance de 80 puntos) antes de cortar.
  *Esto afecta a toda prueba física que haya preguntado "¿salió el papel?": es candidato a
  explicar buena parte de las corridas que nunca cerraron como resueltas.*
- **Elegir "Red" ya no hace nada sobre las impresoras USB.** La 3.9, cuando no encontraba
  ninguna impresora del tipo elegido, seguía igual con todas "para no dejar el diagnóstico
  vacío". Estaba mal: el motor no sólo diagnostica, también repara e **imprime**. Un asesor que
  eligió Red terminó con un ticket de prueba saliendo de la impresora USB del cliente y el log
  del spooler modificado, sin haberlo pedido. Ahora se corta ahí: se informa lo que sí hay
  instalado, no se toca nada, y si hay alguien en la consola se le ofrece revisarlas igual. En
  modo agente nunca se sigue.

### Agregado
- **Evidencia de por qué falló cada puerto candidato.** `Repair-QueueRecreate` devolvía sólo
  "ninguno de los puertos probados imprimió un ticket de prueba", que colapsa tres causas muy
  distintas —no se pudo crear la cola / el ticket quedó encolado / el asesor dice que no salió
  papel— y dejaba el caso sin diagnosticar. Ahora cada intento queda registrado con su resultado
  en `diagnostics.intentosPuerto` y en la nota de la acción. Sin esto no se habría podido
  aislar el bug del ticket.
- **El motor sabe que la App Nativa nueva está firmada.** Desde la **v0.0.37** la Nativa está
  firmada digitalmente y los antivirus dejan de ponerla en cuarentena. El motor ya leía
  `nativaVersion`; ahora la compara y actúa en consecuencia:
  - Por debajo de 0.0.37 agrega `nativa.sinFirmar` en `warn`, diciendo que actualizar es la
    solución de fondo — en vez de agregar exclusiones de antivirus PC por PC.
  - En 0.0.37 o superior **ya no aplica la exclusión preventiva de Defender**. Tocar la
    configuración del antivirus en la PC de un cliente deja de justificarse, y menos disparado
    por una Nativa apagada, que con Fudo cerrado es el estado normal.
  - La comparación es numérica (`[version]`), no de texto: como texto `0.0.9` sería mayor que
    `0.0.37`. Si no se puede leer la versión no se afirma nada en ninguna dirección.
- Self-test: escenarios 56c (reescrito), 60 y 61 (227 asserts).

### Cambiado
- La espera para que el spooler deje utilizable una cola recién creada pasa de 0,6 a 1,2 s, y el
  drenaje de la cola de prueba de 6 a 10 s. No eran la causa del caso reportado (esa impresora
  tardaba menos de 3 s), pero el margen era ajustado.

### Pendiente, con dato nuevo del canal
- **Impresoras de red que existen pero Windows no tiene instaladas.** Reportado: si la impresora
  no está en el rango de red de la PC, el motor no la ve, mientras que el software del
  fabricante (3nStar) sí la detecta. El motor sólo mira las colas instaladas en Windows: no
  descubre nada por la red. Habilitarlo implica escanear, que es lento e invasivo en la red de
  un local, así que queda para decidir aparte.
- **Distribuir el instalador de la Nativa firmada.** El motor ya sabe instalarla
  (`-NativeInstallerUrl` / `-NativeInstallerPath`, y `Find-LocalNativeInstaller` la busca en
  Descargas y Escritorio antes de descargar nada). Falta decidir por dónde viaja el `.msi`: la
  opción sana es que la URL vaya en el `.cmd` interno, como ya viaja la de telemetría — el
  instalador no debería entrar a este repo, que es público.

## [3.9] - 2026-08-28

De la bitácora del 28/08, la primera con v3.8 en campo (22 de 27 corridas nuevas): el camino a
`resolved` por fin funcionó, y al funcionar dejó a la vista tres agujeros. Una corrida cerró
`resolved = true` teniendo la App Nativa caída y volvió como `sigue_fallando` 111 segundos
después; el `skipReason` que agregó la 3.7 no llegaba a la planilla, así que nada de la capa 4
se podía auditar; y un asesor reportó un cliente con dos impresoras de red al que el motor le
contestaba que no tenía ninguna impresora conectada.

### Corregido
- **Que salga el papel ya no alcanza para cerrar el caso si Fudo nunca llegó a mandar una
  comanda.** `Resolve-Diagnosis` exigía `hw.testprint = ok` y ningún check en `fail`, pero un
  `warn` no bloqueaba: una corrida cerró como resuelta y la corrida siguiente de esa misma PC,
  111 segundos después, volvió como `sigue_fallando` con `usoPrevio =
  imprimio_pero_no_comandas_de_fudo`. Sale papel de la prueba física, no salen las comandas.
  Ahora también tiene que haber evidencia de que la cadena de Fudo funciona; si no, el caso
  escala. Es el mismo falso positivo de siempre, esta vez en la capa de Fudo: **imprimir no es
  imprimir comandas.** La evidencia es el historial del spooler (`fudo.usoReal`), no que la
  Nativa esté corriendo — ver abajo.
- **La App Nativa apagada deja de ser un problema y una causa raíz.** Probado contra hardware
  real: la Nativa es un *native messaging host* (los manifiestos
  `do.fu.native_extension_chrome/firefox.json` lo confirman), así que el navegador la levanta
  cuando Fudo la necesita y la cierra después. Con Fudo cerrado —lo habitual cuando el asesor
  entra por acceso remoto— que no esté corriendo es el estado normal. El motor la daba como
  CAUSA del caso ("La App Nativa de Fudo NO está en ejecución") y recomendaba revisar el
  antivirus. Ahora `env.fudoApp`, `nativa.installed` (instalada pero apagada) y
  `nativa.defenderExclusion` dejan de ser candidatos a causa raíz, y el texto explica que sólo
  es un problema si Fudo está abierto en esa PC y aun así no corre. Que la Nativa **no esté
  instalada** sigue siendo causa y sigue bloqueando el cierre.
- **Una sola impresora se contaba como dos.** Encontrado con una Xprinter XP-410B enchufada:
  Windows representa el mismo aparato con dos nodos —el device USB padre
  (`USB\VID_2D37&PID_8327\...`) y su interfaz de impresión hija (`USBPRINT\...&USB002`), que es
  la única que trae el `PortName`— y la deduplicación sólo comparaba `instanceId`. El resumen
  decía "Impresoras físicas detectadas: 2", listaba una segunda impresora "sin puerto asignado"
  que no existe, sugería `-PrinterName` para desambiguar entre una sola impresora, y mandaba
  `cantidadHardware = 2` a la planilla. `Merge-DuplicateDevices` fusiona el nodo sin puerto
  contra el que sí lo tiene cuando son el mismo modelo; dos impresoras iguales de verdad tienen
  cada una su puerto, así que siguen contando como dos.
- **El diagnóstico USB ya no gana como causa raíz en un cliente que imprime por red.** Una PC
  con tres colas en puertos `IP_192.168.1.x`, todas sanas y sin ningún hardware USB, cerró cuatro
  corridas seguidas con "Ninguna impresora física conectada (Administrador de dispositivos)";
  otra tenía la térmica en `LPT1:` sana mientras el motor culpaba a una inkjet USB desconectada.
  Cuando la impresora objetivo está en un puerto que no es USB y hay colas del cliente sanas en
  puertos no-USB, `hw.deviceConnected`, `hw.disconnected` y `conn.usb` dejan de ser candidatos a
  causa raíz. El asesor leía que no había impresora cuando la impresora estaba y andaba.

### Agregado
- **`skipReason` y los ids de acción viajan en la telemetría.** El payload reducido mandaba cada
  check como `{id, status, layer}` y descartaba el `skipReason` que la 3.7 ya calculaba: hubo 22
  corridas en v3.8 sin un solo motivo de salteo ni un solo `testprint.retarget` en la planilla, y
  los tres `hw.testprint = skipped` no se pudieron auditar. Ahora el check reducido incluye
  `skipReason` cuando existe y `telemetry.acciones` lleva los ids de acción, no sólo los textos
  humanos de `autoFixesApplied`.
- **`-Modo USB | Red | Ambos`: el motor pregunta al arrancar qué hay que revisar.** Es la otra
  mitad del pedido del canal. La pregunta vive en el motor, no en el launcher, así que funciona
  igual por doble clic que por línea de comandos y no hace falta redistribuir el `.cmd`. En modo
  agente (o con la salida redirigida) equivale a `Ambos`, que es el comportamiento histórico.
  El modo acota **qué se diagnostica**, no qué se informa: la telemetría sigue viendo todas las
  colas del cliente. Si el filtro dejara el conjunto vacío no se fuerza — se avisa y se revisan
  todas, porque quedarse sin candidata es peor que diagnosticar la de la otra interfaz. El modo
  viaja en la telemetría (campo `modo`) y se muestra en el encabezado del resumen.
- **La prueba física por red ahora también pide confirmación humana.** El camino Ethernet
  marcaba `hw.testprint = ok` con que el socket TCP aceptara los bytes, que es exactamente el
  falso positivo que la 3.2 corrigió para USB: el envío tiene éxito igual sin rollo, con la tapa
  abierta o con la impresora en error. Ahora pasa por `Confirm-PaperCameOut` como el camino USB,
  y sin confirmar queda en `warn`, nunca en `ok`.
- `diagnosis.paperOk`: distingue "no imprime nada" de "imprime, pero la comanda de Fudo todavía
  no sale", incluso cuando el caso no cierra.
- Self-test: escenarios 52 a 59d (212 asserts).

### Cambiado
- **El resumen en pantalla se lee de un vistazo.** El semáforo abre cada línea con un símbolo
  fijo (`[ok] [!] [X] [+] [-]`) en vez de terminar con la palabra de estado después de una fila
  de puntos de largo variable, así se barre la columna sin leer todo. El veredicto quedó separado
  como una ficha con las etiquetas alineadas (`RESULTADO` / `IMPRESORA` / `CAUSA` / `SE ARREGLO`).
  Y el color se decide por el estado real de cada línea y no adivinando por palabras del texto:
  antes casi todo salía gris, y cualquier recomendación que contuviera la palabra "falla" se
  pintaba de rojo aunque no lo fuera.
- **El progreso en vivo ya no se mezcla con lo que se escribe encima.** La línea de progreso se
  dibuja con retorno de carro y sin salto: cuando algo escribía mientras estaba abierta —un
  prompt al asesor, un `WARN` del log, el banner de una acción irreversible— los dos textos se
  pisaban en el mismo renglón. Ahora `Suspend-LiveStatus` la cierra antes, desde los cuatro
  puntos por donde pasa todo: `Read-DoctorLine`, `Confirm-PaperCameOut`, `Confirm-Irreversible`
  e `Invoke-ReconnectFlow`, más `Write-DoctorLog`, que era el más frecuente porque dispara sin
  intervención del usuario (incluido el error que registra cualquier etapa que explote).
- En modo Red el resumen deja de listar el hardware USB y las impresoras desconectadas: mandaba
  al asesor a perseguir un cable que no tiene nada que ver con la impresora que está mirando.

### Corregido (encontrado al revisar la salida real, no venía de la bitácora)
- **La CAUSA mostraba el nombre de una reparación, o directamente lo contrario de lo que pasaba.**
  El nombre de un check es el texto que sale como CAUSA, así que tiene que decir lo que se
  encontró. `nativa.defenderExclusion` se llamaba "Exclusión preventiva de Defender para la
  Nativa" (se lee como si el problema fuera la exclusión) y `env.fudoApp` se llamaba "App Nativa
  de Fudo en ejecución" incluso cuando el check estaba en `warn` **porque no estaba en
  ejecución**. Ambos pasan a tener el nombre según lo que se encontró.
- **La causa raíz podía cambiar sola entre dos corridas con los mismos datos.** `Sort-Object` no
  es estable, así que dos candidatas de la misma capa competían en un orden arbitrario. Ahora
  cada check registra su orden de detección (`seq`) y ante empate de capa gana el que se detectó
  primero.

### Evaluado y no implementado
- **`Test-IsPosPrinter` demasiado laxo.** Sigue dependiendo de una pregunta abierta (si
  `node_printer` manda los trabajos a la cola en RAW o por driver), que es la que define si la
  prueba física es fiel o si está mal la impresora elegida. Cambiar la priorización a ciegas
  puede hacer que el motor deje de diagnosticar la cola que realmente falla.

## [3.8] - 2026-08-27

De la bitácora del 27/08: la misma PC (`43db236c6151dd8c`) mandó dos corridas seguidas con
`cantidadColas = 0`, `cantidadHardware = 0` e `impresoras = []`, pero con veredictos distintos
para `printer.exists` — una vez `ok`, otra vez `fail` — para lo que la telemetría mostraba como
el mismo estado.

### Corregido
- **`cantidadColas` podía venir en 0 aunque `printer.exists = ok`.** Cuando se invoca con
  `-PrinterName` explícito y esa impresora existe en Windows (Caso A de `Resolve-TargetPrinter`),
  la función devolvía el check en `ok` pero nunca llamaba a `Get-PrinterQueues`, a diferencia del
  camino de autodetección (Caso C) que sí lo hace. `$script:Diagnostics['colas']` quedaba vacío y
  la telemetría reportaba cero colas pese a haber encontrado una impresora real. Ahora el Caso A
  también llena `colas`, igual que el Caso C.
- Evaluadas y descartadas por ahora dos propuestas de la misma bitácora: auto-relanzar el motor
  al detectar versión nueva (`engine.updateAvailable`) contradice la decisión ya tomada de que el
  motor avisa pero no se autoactualiza (ver README/CLAUDE.md) — el aviso visible al asesor ya
  existe en `Build-HumanSummary`, así que no hay nada que cerrar ahí; y derivar `pais` desde la
  zona horaria en vez de la cultura, que vive en `tools/telemetria-appscript.gs` (el receptor de
  Google Apps Script), fuera del alcance del self-test y sin forma de verificarla en esta corrida.

### Agregado
- Self-test: escenario 51.

## [3.7] - 2026-08-26

Los hallazgos de la primera revisión diaria automática después de la migración: 12 corridas
nuevas, 8 de ellas ya en 3.6, con `hw.testprint = skipped` en 6 y ninguna capaz de llegar a
`resolved`.

### Corregido
- **La prueba física se reapunta en vez de saltearse.** Si la cola objetivo apunta a un puerto
  sin dispositivo pero el hardware está presente en otro puerto y ahí hay una cola del cliente,
  `Test-Layer4-HardwarePrint` prueba sobre esa (acción `testprint.retarget`). Sólo se saltea
  cuando de verdad no hay dónde probar. Con `hw.testprint = ok` como único camino a `resolved`,
  saltear era dejar la corrida sin poder cerrar nunca.
- **Una causa raíz obsoleta ya no gana.** `Resolve-Diagnosis` descarta un `printer.disconnected`
  / `hw.disconnected` en `fail` cuando hubo un re-bind del puerto (`hw.noPortBound`, `conn.usb`
  o `printer.exists` en `fixed`) y el puerto ya tiene dispositivo. Una PC diagnosticaba "la
  impresora 'FUDO-USB001' está desconectada" 35 segundos después de que la corrida anterior
  creara esa cola en ese mismo puerto.
- **La cola propia deja de ser un entregable cuando se queda sin hardware.**
  `Remove-OrphanOwnQueues` (nuevo, corre después del inventario de hardware) borra las colas
  `FUDO-USB00x` creadas por el motor si su puerto ya no tiene ningún dispositivo. Las que sí
  tienen hardware se conservan: siguen siendo el entregable de v3.6. Patrón nuevo
  `$script:OwnQueueRx`, que alcanza `FUDO-TEST-*` y `FUDO-USB00x`.
- **Restaurar de cuarentena y que vuelva una versión más vieja ya no es "reparado".**
  `Test-NativaDegradada` compara `nativaVersion` antes y después de la restauración; si baja, el
  check queda en `warn`, con ambas versiones en la evidencia y la recomendación cambiada a
  reinstalar. Explica el 0.0.36 → 0.0.18 de PC_ANTO y el 0.0.18 circulando en campo.

### Agregado
- `skipReason` en todo salteo de `hw.testprint` (`testprint_off`, `dry_run`, `sin_ip`,
  `sin_impresora`, `impresora_virtual`, `puerto_sin_dispositivo`), para que la telemetría
  distinga "no había fierro" de "no supe probar".
- Self-test: escenarios 47 a 50.


## [3.6] - 2026-08-26

Los tres hallazgos de la revisión diaria del 26/08, sobre 9 corridas reales en v3.5.

### Corregido
- **El motor creaba una cola paralela en un puerto que ya tenía una cola sana.** Confirmado en
  dos PCs: quedaban `FUDO-USB001 [USB001]` y la cola real del cliente `[USB001]` conviviendo,
  el asesor tenía que reconfigurar Fudo sin necesidad, y la prueba de impresión corría **sobre
  la cola nueva** en vez de la que el local usa (de ahí `hw.testprint = fail` con una cola
  sana al lado). Ahora `hw.noPortBound` busca primero si el puerto ya tiene una cola del
  cliente y, si la hay, la **adopta** sin crear nada (`Find-QueueForPort`). Solo crea cola
  cuando no existe ninguna.
- **`resolved = true` con `needsEscalation = true`, y la CAUSA era el nombre de la
  reparación.** `Resolve-Diagnosis` daba por resuelta cualquier corrida con un check en
  `fixed` y ninguno en `fail`, y tomaba el `rootCause` de ese `fixed`: salían causas como
  "Puerto USB desmapeado" o "Exclusión preventiva de Defender", que son reparaciones. Eso
  producía el **18% de "resueltas" con la columna "qué resolvió" vacía**, y la corrida
  siguiente de la misma PC volvía como `sigue_fallando`. Ahora el único camino a `resolved`
  es que la cadena imprima —`hw.testprint = ok`, que desde 3.2 requiere que un humano
  confirme el papel—; si se repararon cosas sin confirmar, la causa lo dice literalmente
  ("se aplicaron reparaciones; falta confirmar que la comanda sale") y `rootCauseCheckId`
  queda vacío en vez de apuntar a un `fixed`.
- **Las colas propias del motor entraban a la ruta de diagnóstico.** El filtro de 3.4 solo
  llegaba al inventario, así que una corrida terminó con la CAUSA *"la impresora
  'FUDO-TEST-USB002' está desconectada"*: el motor reportando su propia basura como el
  problema del local. Ahora `Remove-StaleOwnQueues` borra las `FUDO-TEST-*` que quedaron de
  corridas anteriores **antes** de diagnosticar, y ante empate de score `Get-PrinterQueues`
  ordena las colas del cliente antes que las del motor, para no probar sobre una propia
  cuando hay una real igual de sana.
- **`autoFixCount` no coincidía con `autoFixesApplied`** (se vio `1` contra lista vacía):
  contaba acciones, incluidas las que no son reparaciones. Ahora cuenta la lista; el total de
  acciones va aparte en `accionesCount`.

### Agregado
- Self-test: 147 asserts (S5/S5b el contrato nuevo de "reparar no es resolver", S45 adopción
  de la cola existente, S46 prioridad de la cola del cliente).

## [3.5] - 2026-08-25

Caso real de un asesor en Chile: Epson L5590 conectada por USB, el motor no le ofreció
asignarle puerto y hubo que instalarla a mano.

### Agregado
- **Replug por software.** Cuando `hw.noPortBound` detecta que Windows ve la impresora pero
  no le asignó puerto USB, el motor ya no se limita a pedirle al asesor que desenchufe el
  cable: hace lo mismo por software con `Restart-PnpDevice` + `pnputil /scan-devices`, espera
  a que aparezca el puerto y, si aparece, **crea la cola** (`Repair-BindUsbPort`).
- **La cola se levanta siempre, con el mejor driver disponible** (`New-FudoPrinterQueue`).
  Antes, si la impresora tenía driver de fabricante ya instalado (`oem_instalado`), el motor
  se abstenía y no creaba nada. Ahora usa ese driver si está en Windows —una Epson con su
  driver imprime mejor que con texto genérico— y si no está cae a `Generic / Text Only`. Si
  las dos cosas fallan, devuelve el error para que el asesor lo vea.
- **La opción `[I]` del menú aparece también cuando no hay ningún puerto USB**, que era
  exactamente este caso: antes se ofrecía solo si existía un puerto huérfano, así que en la
  PC del cliente no aparecía ninguna opción para levantar la impresora.
- **Nueva capa 3 para colas WSD** (`Test-Layer3-WsdPort`) y chequeo `conn.portMismatch`.

### Corregido
- **Un puerto WSD se tomaba como USB.** `Get-DetectedInterface` no reconocía `WSD-<guid>`, así
  que caía en el `return 'USB'` por defecto y la capa 3 informaba **"Puerto USB ... OK"** sobre
  una cola de red. En el caso real la única cola era la WSD (`Microsoft IPP Class Driver`)
  mientras el hardware estaba en USB: el ticket entraba a la cola y no salía nunca. Ahora se
  detecta como `WSD` y, si además hay hardware USB presente, se avisa el desajuste con la
  indicación de crear la cola sobre el puerto USB y apuntar Fudo ahí.

### Pendiente conocido
- `Test-IsPosPrinter` es demasiado laxo: marca `esPos = true` para una Epson L5590 (multifunción
  de tinta) y hasta para "OneNote for Windows 10". Por eso la prueba física le manda ESC/POS
  RAW a una impresora que no es térmica y el resultado ("la impresora no está respondiendo")
  es engañoso. Falta decidir qué prueba corresponde a una impresora con driver propio.

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
- **La URL de telemetría sobrevive a un launcher reemplazado.** Ya se guardaba en la variable
  de usuario `FUDO_TELEMETRY_URL`, pero eso es por usuario de Windows: si el `.cmd` se
  reemplazaba por el público (sin URL) y después corría otro usuario, se perdía. Ahora también
  se deja una copia en `telemetria.txt` al lado del motor, que viaja con la carpeta y está en
  `.gitignore` (nunca llega al repo público).
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
