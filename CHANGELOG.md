# Changelog

Formato: [Keep a Changelog](https://keepachangelog.com/es-ES/1.1.0/). Versionado del `schemaVersion` del JSON.

## [3.23] - 2026-09-18

**El informe de la PC.** La interfaz deja de mostrar solo el progreso y el veredicto: ahora
dibuja qué tiene esta computadora, qué impresoras hay instaladas y qué hay conectado en cada
puerto, con el estado de cada cosa y el botón de la gestión que la resuelve al lado. Y no
aparece al final: se pinta **apenas terminan las capas de lectura**, mientras el motor sigue
trabajando.

El motivo es el mismo de siempre, visto desde el otro lado: la corrida completa puede tardar
minutos —la prueba física espera a que un humano mire si salió el papel— y en todo ese rato el
asesor miraba una escalera de capas que le cuenta cómo anda el motor, no cómo está el local.
Ahora, a los pocos segundos, tiene el inventario en pantalla.

### Agregado

- **Evento `inventario`**: el motor lo empuja después de la capa 1 y otra vez después del
  rescan final, así el informe refleja lo que se reparó en el medio. Si la interfaz no está
  levantada, es un no-op.
- **`Get-PortInventory`**: cruza `printerPorts`, `printersConnected` y `colas` y devuelve, por
  puerto, qué hay del otro lado. Cuatro estados y ninguno es una opinión: *enganchada* (hay
  device y hay cola), *sin usar* (hay device y ninguna cola: está enchufada y Windows no la
  tiene instalada), *rota* (hay una cola apuntando a un USB vacío) y *sin estado* para lo que
  no tiene nada que decir. Un puerto de red **no** se da por bueno por existir: hereda el
  estado de su cola, porque hasta que la capa 3 lo pruebe no hay evidencia de que conteste.
- **Las impresoras desconectadas entran al informe.** Las que Windows conoce y hoy no están
  aparecen junto a las instaladas, con su motivo y el botón de reconectar. Faltaban justo
  donde el motor pone su causa raíz más común: en la corrida de prueba la causa fue *"Xprinter
  XP-410B (estaba en USB002)"* y el informe no la mencionaba en ningún lado.
- **"Qué hacer ahora" deja de repetir lo que el informe ya muestra.** Si un hallazgo tiene su
  tarjeta o su fila **con la acción al lado**, no necesita además un renglón en la lista. En la
  corrida de prueba pasó de 9 acciones a 2. Lo que se queda: la configuración de Fudo (capa 5,
  que es de la cuenta y no de la PC) y las instrucciones para una persona —mirar que esté
  encendida, que el cable esté firme, probarla sin el hub—, que no son el estado de nada y por
  eso no tienen tarjeta. Es la misma regla de 3.22 con los hallazgos informativos, un paso más.
  **Es sólo presentación: `nextActions` viaja entero en el JSON y en la telemetría.**
- **Se fue el cartel de la causa raíz, y con él medio resultado.** Repetía palabra por palabra
  lo que el informe ya muestra —en la corrida que lo destapó, los mismos dos nombres y los
  mismos dos puertos que las filas rojas de "impresoras instaladas"— y con el texto crudo del
  motor, escrito para el JSON. Lo único que el informe no puede decir es si el caso quedó
  resuelto: eso quedó como una palabra en la tira del semáforo. La causa sigue entera en el
  detalle técnico, en el JSON y en la telemetría. En la misma pasada: los tres pliegues de
  detalle y el pie se juntaron en **uno solo** ("Para soporte"), con un botón que copia el
  resumen para pegarlo en el caso; la sección "qué cambiamos" desaparece cuando no se cambió
  nada; y la línea de telemetría aparece **sólo si el envío falló** —que salga bien no le sirve
  a nadie en pantalla, que no salga sí, porque esa corrida no va a existir para el equipo.
- **Fuera "Confianza: medium" de la pantalla.** Vocabulario del motor; no le dice nada a quien
  mira —ni al cliente, que también mira— y no cambia lo que hay que hacer. Sigue en el JSON.
- **La IP local de la PC** viaja en `entorno.redes[].ip`. Sin ella, para decidir qué dirección
  ponerle a una impresora de red había que pedírsela al cliente por teléfono. Se descarta la
  169.254.*, que es la que Windows se autoasigna cuando **no** consiguió red: informarla como
  la IP del local sería peor que no decir nada. *Nota: `entorno` viaja en la telemetría, así
  que esta IP privada ahora también. Las IP de las impresoras ya viajaban.*

### Corregido

- **`entorno.nativaVersion` podía ser la de una PWA de Chrome.** Una app instalada desde el
  navegador (Chrome > Instalar página como app) se anota con DisplayName `Fudo` y
  DisplayVersion `1.0`. La 3.19 le puso el filtro `esPwa` a `Find-FudoNativeInstall`, pero
  `Get-EnvironmentInfo` seguía leyendo `regInfo` **crudo** y tomaba la primera entrada: si la
  PWA venía primero, la telemetría reportaba "Nativa 1.0". Estaba así desde la 3.19 y nadie lo
  vio porque el dato solo iba a la planilla; se destapó al ponerlo en una tarjeta en pantalla.
  *Un filtro puesto en la detección no protege a los otros lectores de la misma fuente.*

- **El semáforo decía "0 no funcionan" arriba de un cartel que decía "todavía no imprime".**
  Contaba cosas —tarjetas, colas, puertos— y una PC sin ninguna impresora instalada no era
  ninguna de esas cosas, así que no sumaba. Ahora una PC sin impresoras y cada impresora
  desconectada cuentan como rotas. *Dos afirmaciones opuestas en la misma pantalla, y la que
  estaba mal era la del resumen, no la del diagnóstico.*
- **El renglón que colapsa la capa 5 abría con "La impresora anda".** Aparece cada vez que
  quedan chequeos de configuración de Fudo sin resolver —ande la impresora o no—, y quedó
  arriba de un veredicto que decía *"impresora instalada pero DESCONECTADA"*. Un texto sobre la
  configuración de Fudo no puede afirmar el estado del hardware: no es lo que ese renglón miró.

- **El motor pedía dos veces el mismo ticket de prueba, en el mismo puerto.** Reportado por
  Alexis el 18/09 con la 3.22 en campo: un cliente con dos impresoras USB —una que Windows no
  estaba tomando— recibió dos impresiones de prueba y dos instalaciones del driver genérico.
  La causa son dos capas haciendo lo mismo: la capa 3 reasigna el puerto probando candidatos
  con un ticket real y preguntando *"¿salió el papel?"*, y la capa 4 manda otro ticket a la
  misma impresora en el mismo puerto y vuelve a preguntar. Ahora, cuando una persona confirma
  en la capa 3, queda anotado impresora + puerto y la capa 4 **reusa esa evidencia** en vez de
  repetir la prueba (`hw.testprint` con `reusadaDeCapa3 = true`).

  Los límites de esa memoria importan más que la memoria: sólo vale un **sí explícito** (un
  "salió de la cola pero nadie confirmó" no es evidencia), sólo para **esa impresora** —el caso
  de Alexis tenía dos, y la segunda se prueba igual—, sólo si la cola **sigue apuntando al
  mismo puerto** (se relee de Windows, no se confía en el objeto en memoria), y sólo dentro de
  **la misma corrida**: si el asesor pide revisar todo de nuevo, se vuelve a probar, porque lo
  más común que cambia entre dos corridas es justamente el cable.

  *Por qué no es sólo una molestia:* desde la 3.2 esa pregunta es la única fuente de verdad del
  motor. Una pregunta que se repite se empieza a contestar sin mirar, y ahí perdemos lo único
  que separa "el spooler dijo que sí" de "salió el papel".

- **El motor podía mandar una cola al puerto que ya usaba otra impresora.** Apareció
  revisando el reporte de Alexis, y es peor que el ticket duplicado. Los candidatos de puerto
  excluían los que ya usa otra cola… salvo los **puertos "vivos"** (los que tienen un
  dispositivo detrás), que se anteponían sin ese filtro. En un local con dos impresoras
  —cocina sana en USB001, caja que Windows no ve— el primer candidato para reparar la caja
  era **USB001, el puerto de la cocina**: el motor le reasignaba el puerto, mandaba el ticket,
  y **el papel salía de la impresora de cocina**. Como la pregunta es *"¿salió el ticket de
  prueba de 'Caja'?"*, el asesor veía papel y contestaba que sí —con razón—, y la caja quedaba
  "reparada" apuntando a la cocina, con dos colas en el mismo puerto y las comandas saliendo
  donde no van.

  Es la lección de la 3.10 con otra ropa: **"¿salió papel?" no distingue de cuál impresora
  salió.** Ahora ningún puerto ocupado por otra cola del cliente es candidato, y cuando el
  único puerto vivo está ocupado el motor lo dice con nombre y apellido —*"la cola 'Caja' no
  tiene a dónde apuntar: el único puerto con una impresora conectada lo usa 'Cocina'; NO hay
  que apuntar las dos al mismo puerto"*— en vez del genérico "reasignar el puerto", que llevaba
  al asesor a hacer a mano justo lo que el motor se niega a hacer. La elección de candidatos
  salió a una función pura (`Get-UsbPortCandidates`) para poder testearla.
- **El informe mostraba una sola cola por puerto.** Si dos apuntaban al mismo, la segunda era
  invisible: justo la situación que hay que ver. Ahora se listan las dos y el puerto baja a
  ámbar explicando que las dos imprimen en la misma impresora.

### Aprendido (y es lo que más va a durar)

Armando esta pantalla aparecieron **tres avisos falsos de la misma familia**, y ninguno salía
de un bug: salían de reglas escritas "por las dudas".

1. *"Estás por Wi-Fi, y una impresora de red se puede cortar"* — en una PC sin ninguna
   impresora de red. Ahora el wifi solo es ámbar **si hay una cola con IP propia**, y dice
   cuál.
2. *"15 sin revisar"* en una PC sana: se estaban contando los COM, LPT y los USB libres. Un
   puerto vacío no es algo que no pudimos revisar, es algo que no tiene nada que decir. En una
   tarjeta el gris sí significa "no lo miré", y ahí sigue contando.
3. *"No se pudo revisar si el antivirus se llevó algo de Fudo"* con la Nativa instalada y
   corriendo. Si la Nativa está y anda, Defender de hecho no se la está llevando: eso es
   evidencia, y la tarjeta dice "sin bloqueos".

La regla que queda: **una advertencia tiene que salir de algo que se observó, no de algo que
podría pasar.** Es la lección de los falsos positivos del motor aplicada a la presentación, y
tiene la misma consecuencia práctica: si el informe se llena de ámbar, el asesor deja de
mirarlo, que es exactamente lo contrario de para qué existe.

Un corolario de diseño, del mismo origen: **el estado de cada cosa sale de los checks que el
motor ya manda, no de una segunda opinión calculada en la interfaz.** Los datos que viajan son
valores (qué Windows, qué Chrome, qué versión); el color lo pone el check. Dos fuentes de
verdad sobre lo mismo terminan discrepando, y a este proyecto ya le pasó.

## [3.22] - 2026-09-16

**El motor deja de ser una ventana negra.** Con `-Ui web` levanta una página en `127.0.0.1`, la
abre en el navegador de la PC del cliente y muestra ahí lo mismo que mostraba en consola: el
progreso por capas, las preguntas, el resultado y el menú. Sin la opción, **nada cambia**: el
modo consola sigue siendo el default y el modo agente ni se entera.

Y buscando dónde enganchar la interfaz apareció un bug viejo que estaba a la vista de todos.

### Corregido

- **El JSON se imprimía en pantalla en todas las corridas, aunque nadie pidiera `-Json`.**
  Adentro de `Write-DoctorResult`, la variable con el texto serializado se llamaba `$json`.
  PowerShell no distingue mayúsculas: ese local **tapaba al parámetro `-Json` del script** para
  el resto de la función, así que el guard `$emitJson = [bool]$Json` evaluaba el texto
  serializado —que nunca está vacío— en vez del switch. Al lado había un comentario explicando
  que el problema estaba resuelto desde hacía varias versiones, y describía exactamente el
  síntoma que seguía pasando: *"el asesor terminaba viendo el JSON entero arriba del resumen"*.

  Tenía un segundo efecto que nadie había atado al primero: la copia automática del JSON en
  `%TEMP%` **no se escribía nunca**, porque esa rama pide `-not $emitJson`. Por eso el resumen
  tampoco mostraba la línea *"Detalle completo (JSON): &lt;ruta&gt;"*.

  *Un comentario que afirma que algo está arreglado no es evidencia de que lo esté.* Verificado
  corriendo la 3.21 publicada: sale con los delimitadores `<<<FUDO_JSON_BEGIN>>>` por stdout.

- **Escenario 105 del self-test: ninguna función puede tapar un parámetro del script.** Es del
  mismo tipo que el 76 (el que revisa que ninguna función llame a algo que no existe fuera del
  self-test): **no se encuentra corriendo escenarios, hay que mirar el código**. Recorre el AST y
  marca toda asignación local cuyo nombre coincida con un parámetro del script. Encontró otros
  dos casos además del que rompía la salida (`$json` en `Get-NativeMessagingState`, `$port` en
  `Test-IsVirtualPrinter` y en `Get-DetectedInterface`); esos tres eran inofensivos —se asignan
  antes de leerse— pero son el mismo patrón, así que se renombraron igual.

### Agregado

- **`-Ui web`: la interfaz.** El motor sirve una página desde sí mismo, sólo en `127.0.0.1` y
  con un token aleatorio por corrida. No instala nada, no sale a internet y muere con el proceso.
  Qué muestra:
  - **la cadena de impresión como una escalera**, con el mismo orden de capas, los mismos estados
    y los mismos milisegundos que la consola;
  - **las preguntas como tarjetas que no se pisan con nada**. La del papel —la única fuente de
    verdad del motor— muestra además **el ticket dibujado al lado**, para que el asesor sepa qué
    tiene que estar buscando. Es la corrección de diseño a la lección de la 3.10: si le
    preguntás a un humano, la pregunta tiene que poder contestarse bien;
  - **"lo que se tocó en esta PC"** como sección propia, con cada cambio marcado *reversible* o
    *no se deshace*. En consola eso quedaba desparramado entre el log y el resumen;
  - **el menú deja de ser un menú**: la acción que ejecuta una recomendación va como botón
    dentro de esa recomendación, y el resto vive en *Opciones avanzadas*, plegado. Ahí están
    **las diez gestiones siempre**, cada una con lo que hace —dato que el menú de consola nunca
    dio— y las que no aplican **dicen por qué** en vez de desaparecer.

- **`Test-HayHumano`, separado de `Test-IsInteractiveConsole`.** Eran la misma función
  contestando dos preguntas distintas: *"¿hay alguien?"* y *"¿puedo pintar esta consola?"*. Con
  la interfaz web la segunda es que no y la primera que sí. Si no se separaban, en modo web el
  motor se creía agente y **dejaba de preguntar si salió el papel**.

- **`-UiPort`, `-UiTimeoutSec` y `-UiNoOpen`.** Puerto fijo, cuánto esperar una respuesta antes
  de darla por abandonada (15 min por defecto; al vencer se comporta como si no hubiera nadie, o
  sea que nunca aplica por su cuenta algo que necesitaba un sí), y no abrir el navegador solo.

- **`tools/Embed-Ui.ps1`.** La página vive en `ui/fpd-ui.html` y este paso la embebe en el
  `.ps1` convirtiendo cada carácter no ASCII a entidad HTML. El motor sigue siendo **un solo
  archivo** sin un solo byte fuera de ASCII, y el asesor sigue copiando dos archivos.

### Sin cambios

El contrato del JSON, los códigos de salida, la telemetría, el orden de capas y todas las
decisiones del diagnóstico. **La interfaz es presentación: no decide nada.** Si el puerto no se
puede abrir —sin permisos, un antivirus en el medio— el motor **avisa y sigue por consola**: la
interfaz nunca puede ser condición para diagnosticar.

### La pantalla la mira el cliente

El asesor la usa por escritorio remoto, con el dueño del local al lado mirando la misma
pantalla. Eso cambia para quién está escrito todo:

- **La copia pasó a castellano llano y en primera persona del plural.** *¿Qué impresora hay
  que revisar?* → **¿Cómo está conectada la impresora que no anda?**, con opciones *Con un
  cable a esta computadora* / *Por la red* / *No sé, las dos*. *Lo que se tocó en esta PC* →
  **Qué cambiamos en esta computadora**. Los dueños de cada acción dejaron de ser etiquetas
  internas: `CLIENTE` → **en el local**, `ASESOR` → **lo hace soporte**.

- **Dos textos por recomendación, uno por público.** El texto que ya tenía el motor está
  escrito para el asesor y viaja al JSON, a la consola y a la telemetría: es el contrato con
  el agente y **no se tocó**. Al lado hay ahora una versión para el local, y el técnico queda
  a un clic. Por ejemplo, para `nativa.sinFirmar`:

  > **Para el local:** *La aplicación de Fudo está desactualizada. Las versiones viejas no
  > están firmadas y algunos antivirus las borran solas.*
  > **Técnico:** *Esta PC tiene la Nativa v0.0.36. Desde la v0.0.37 la App Nativa está
  > firmada digitalmente…*

  Vive en **una tabla única** (`$script:TextosLocal`) indexada por el id del chequeo, y no
  como un segundo parámetro en cada `Add-Check`: las recomendaciones están escritas en unos
  80 lugares del motor, y duplicar el texto ahí garantizaba que las dos versiones se
  desincronizaran. Lo que no está en la tabla cae al texto técnico: **mejor que el cliente
  lea algo técnico a que lea una traducción inventada que dice otra cosa.**

- **Escenario 106 del self-test:** cada clave de la tabla tiene que ser un chequeo que el
  motor realmente emite. Es una tabla paralela al código; si alguien renombra un check, el
  texto para el local desaparece **sin que nadie se entere**, porque la interfaz cae al
  técnico en silencio. Misma familia que los escenarios 76 y 105.

- **Los pasos internos quedan marcados.** El instalador de la Nativa y el número de caso
  llevan una marca *Paso del asesor*, para que el cliente no crea que le están pidiendo algo
  a él. Y se sacó lo que no va delante de un cliente: la anécdota del caso real en la
  pregunta del modo, y hablar de *“el motor”* en tercera persona.

- **La lista de recomendaciones dejó de ser un choclo.** Mostraba diez renglones, cinco de
  ellos la misma recomendación de configuración de Fudo partida en pedazos. Ahora usa
  `Get-ShortActions` — **la misma función del resumen de consola**, para que no puedan
  divergir — que colapsa esos cinco en una línea. De 10 a 6, con 3 a la vista y el resto
  plegado.

### Corregido durante las primeras corridas de la interfaz

Seis bugs que aparecieron probando la interfaz a mano. **Ninguno lo vio el self-test**: son
todos de la capa de presentación, que el self-test no toca.

- **Las acciones del resultado nunca se mostraban.** `nextActions` vive dentro de `diagnosis`,
  no en la raíz. Leerlo de la raíz daba `$null`, y `@($null)` **no es una lista vacía: es
  una lista de un elemento nulo**. La interfaz recibía `[null]`, lo filtraba y no dibujaba la
  sección *Qué hacer ahora* — la parte más útil del diagnóstico — sin que nada avisara.
- **Los acentos salían como `&#243;`.** El primer embebido convertía cada carácter no ASCII a
  entidad HTML: funciona en el marcado, pero **no dentro de una cadena de JavaScript**. Ahora
  la página va en base64 y el build **verifica el ida y vuelta byte por byte**.
- **Una pregunta repetida no se volvía a dibujar.** La página decidía si una pregunta era
  nueva comparando su contenido, y el tercer intento del número de caso es idéntico al
  segundo: quedaba tomado por ya contestado y la tarjeta desaparecía con el motor esperando.
  Cada pregunta lleva ahora su número de secuencia. **El mismo bug rompía reimprimir el
  ticket dos veces seguidas**, que es justo la única fuente de verdad del motor.
- **El error del número de caso era invisible.** Viajaba mezclado con el texto descriptivo y
  se dibujaba como un párrafo gris igual al de arriba; desde afuera parecía que la página se
  recargaba sola sin decir nada. Ahora va en campo propio, en rojo y con el contador de
  intentos, porque a los cinco la corrida se corta.
- **Las gestiones del menú no informaban nada.** `Invoke-MenuAction` cuenta lo que hizo con
  `Write-Host`, que en modo web no lo ve nadie: el asesor tocaba *esperar la reconexión del
  USB*, el motor esperaba dos minutos y en pantalla no pasaba nada. Ahora se ve qué se está
  ejecutando, la cuenta regresiva y con qué terminó. Y en `-DryRun` un cartel permanente
  avisa que no se va a cambiar nada.
- **Cortar por cinco intentos fallidos se mostraba como una caída.** Es una decisión del
  motor, no un error: ahora se distingue del cartel rojo de conexión perdida.

### Qué nombre le pone el antivirus a la Nativa

Lo pidió producto, y el planteo es correcto: hoy se cambian cosas de la App Nativa
**esperando** que el antivirus deje de marcarla, sin saber qué la marca. El nombre de la
detección define el trabajo, y son trabajos distintos:

- **`Trojan:Win32/Wacatac.B!ml`** — lo marcó un modelo estadístico, no una firma. Se ataca con
  **reputación**: firmar el binario, editor conocido, volumen de instalaciones.
- **`Behavior:Win32/Persistence`** — el antivirus objeta lo que el programa **hace**. Se ataca
  cambiando el código.

El motor ya leía el historial de Defender, pero guardaba el `ThreatID` — un número que no le
sirve a nadie para decidir. El nombre vive en otro cmdlet (`Get-MpThreat`), que se cruza por ese
mismo id. Ahora:

- **Cada detección sobre un archivo de Fudo viaja con su nombre**, su severidad y su
  clasificación automática (`ml` / `comportamiento` / `estatico`), en el JSON y en la
  telemetría.
- **Sin rutas del cliente**: viaja el nombre del archivo pelado (`fudo_native_extension.exe`),
  que es un binario nuestro. Hay un assert que lo verifica.
- **También viaja con qué antivirus convive cada PC**, para poder medir qué porcentaje de los
  casos queda fuera: el motor sólo puede leer el historial de Defender.

El dato llega **de todas las corridas y retroactivo** — `Get-MpThreatDetection` devuelve el
historial completo, no sólo lo del día —, así que no hace falta pedirle capturas a clientes
elegidos a mano.

**Escenario 110** del self-test: la clasificación de los tres tipos, el cruce del id con el
catálogo, y que la ruta del cliente no se escape en el payload.

> **Hallazgo de la misma sesión, sin resolver:** en dos builds distintos de la 0.0.37 (los `.msi`
> del 11/09 y del 16/09) **el instalador está firmado por Fudo Group LLC y el ejecutable que
> instala NO lo está**. El motor asume lo contrario: `NativaVersionFirmada = '0.0.37'` y le dice
> al asesor que desde esa versión los antivirus dejan de ponerla en cuarentena. Si el `.exe`
> sigue sin firma, actualizar no evita las cuarentenas. Queda para confirmar con quien arma el
> instalador antes de tocar esa constante.

### La Nativa dejó de distribuirse como `.msi`

El 17/09/2026 apareció `fudo_native_app_win_8_and_up.exe` (58,7 MB, firmado por Fudo Group
LLC), en lugar del `.msi`. Se instala solo, se desinstala con
`fudo_native_extension.exe --uninstall` y **Windows Installer no participa**.

Lo bueno: el motor ya lo reconocía sin cambios. Lee la versión instalada del **registro**, no
del archivo, así que detectó `Fudo Native Extension v0.0.38` y los cinco chequeos de la Nativa
dieron `ok` a la primera. Verificado contra una PC con la 0.0.38 recién instalada.

Lo que sí rompía, y arranca el mismo día:

- **El chequeo del kit del asesor le iba a dar aviso a todo el mundo, en cada corrida, con el
  instalador correcto al lado del script.** Exigía un instalador que **declarara** una versión
  igual o mayor a la firmada, y eso sólo lo hace un `.msi`. Un `.exe` no declara ninguna
  versión útil: **sus metadatos son los del runtime de Node que lleva adentro**
  (`ProductName: Node.js`, `ProductVersion: 20.18.1`, `OriginalFilename: node.exe`).

  Ojo con ese detalle, porque es una trampa: leer la versión del `.exe` parece el arreglo
  obvio y es peor que no leerla — el motor compararía `20.18.1` contra `0.0.38` y creería para
  siempre que hay una actualización pendiente.

  **El número de versión siempre fue un proxy de lo que importaba: que el binario esté
  firmado, para que el antivirus no se lo lleve.** Con el `.exe` el proxy dejó de funcionar,
  así que el kit ahora mira **el dato de verdad**: la firma Authenticode, y que el firmante
  sea Fudo. Una firma válida de cualquier otro no sirve. El camino histórico — un `.msi` que
  declara la versión firmada — sigue igual.

  **Escenario 112.** Verificado además contra los archivos reales de una PC: el `.exe` nuevo y
  los `.msi` de la 0.0.37 pasan; el `.msi` de la 0.0.27, que no está firmado, queda afuera.

- **El motor ya puede actualizar con un `.exe`.** `Test-NativaNecesitaUpdate` pide una versión
  legible del instalador para no degradar la Nativa — una restauración de cuarentena ya dejó
  una PC de 0.0.36 a 0.0.18 — y con el `.exe` esa versión parecía imposible de obtener.

  Sí se puede, pero **no de los metadatos del archivo**: el empaquetado deja adentro el
  `package.json` de la app, y ese declara la versión de verdad. Se lo busca por su nombre
  propio (`"name": "native-extension"`, `"description": "Fudo native extension"`) y **no por
  el primer `"version"` que aparezca**: adentro hay casi 200, uno por cada dependencia
  (`jsonwebtoken` 9.0.3, `printer` 0.4.0, `serialport` 13.0.0…). Agarrar el primero sería
  cuestión de suerte.

  Se lee **por bloques de 4 MB con solape**, no de una: son 60 MB y esto corre en la PC de un
  local. Medido sobre el archivo real: **398 ms**, y con caché por ruta+tamaño porque la lista
  de instaladores se arma varias veces por corrida.

  **Escenario 113**, sobre la parte que reconoce el patrón — separada a propósito de la que
  lee el disco, para que el self-test no necesite un archivo de 60 MB ni toque la PC. Incluye
  el caso que importa: con las dependencias **delante** de la app, igual encuentra la de la app.

> **Falta saber cómo se instala en silencio.** El `.exe` acepta `--uninstall` (es lo que usa
> su propia entrada de desinstalación), pero no se pudo confirmar cuál es el argumento de
> instalación desatendida: los `--silent` y `--quiet` que aparecen en el binario pueden ser de
> npm, que viaja adentro. El motor lo ejecuta sin argumentos, así que **puede abrir una
> ventana**; el asesor está presente y puede seguirla, pero conviene preguntarle a dev.

> **Y el hueco de la firma quedó cerrado.** En la 0.0.37 empaquetada como `.msi`, el instalador
> estaba firmado y el `fudo_native_extension.exe` que dejaba **no**. En la 0.0.38 el ejecutable
> instalado **sí** está firmado (`CN=Fudo Group LLC`). Queda pendiente revisar con dev si
> `NativaVersionFirmada = '0.0.37'` sigue siendo el umbral correcto: para el `.msi` de esa
> versión no lo era.

### Lo que falta probar

La interfaz se probó punta a punta contra el motor real, pero **contra una PC sin impresora
térmica**: la pregunta del papel, la reconexión guiada del USB y la elección de versión de la
Nativa se ejercitaron por HTTP, no con alguien mirando una impresora.

## [3.21] - 2026-09-15

**Una corrida cerró RESUELTO en la PC de un cliente que no podía imprimir una sola comanda.** Lo
reportaron tres asesores el mismo día —uno con video— y es una regresión que introdujo la 3.19.

### Corregido

- **La restauración de cuarentena se verificaba con el criterio que la 3.19 había reemplazado.**
  La 3.19 cambió "la Nativa está instalada" por *el ejecutable está en disco*, en todo el motor
  menos en un lugar: la re-lectura posterior a restaurar de la cuarentena de Defender, que seguía
  preguntando *"¿hay carpeta o entrada de registro?"*. Y ese lugar es justamente el que **corrige
  el hallazgo de la capa 0b.1**, así que el criterio flojo le ganaba al estricto.

  En el caso real: el antivirus se lleva `fudo_native_extension.exe` y deja la carpeta con los dos
  manifests y `node_printer.node`. El motor restauraba, veía la carpeta, daba la Nativa por
  restaurada, **pisaba el hallazgo correcto** de que no estaba, la capa 0b salía *"reparado"*, no
  quedaba ninguna falla, el ticket de prueba salía —el hardware estaba perfecto— y el caso cerraba
  **RESUELTO**. En la pantalla de Fudo la impresora seguía en *Desconocido*.

  *Es el falso positivo más caro desde el launcher que decía RESUELTO sin correr, y del mismo tipo:
  una verificación que mira el dato equivocado vale menos que no verificar, porque además tapa el
  diagnóstico que estaba bien.*

- **Reinstalar la Nativa sobre un producto que Windows tiene anotado no hacía nada.** Cuando el
  antivirus borra los archivos, el producto sigue registrado como instalado; en ese estado
  `msiexec /i` ve el producto presente, no reescribe nada y termina con código 0. Un asesor lo
  describió exacto: *"al colocar para que instale la nativa te daba todo ok, pero el
  fudo_native_extension.exe seguía sin estar"*. Ahora, cuando el producto figura instalado y los
  archivos no están, el motor **repara** (`msiexec /fa`, que reescribe los archivos del producto);
  si ese producto no estaba registrado de verdad, se cae solo a la instalación normal.
  Es lo que hasta ahora obligaba a desinstalar a mano antes de reinstalar.

- **El antivirus de terceros ahora dice qué hacer, y en qué orden.** El motor sólo sabe configurar
  exclusiones en Windows Defender: con Avast (o cualquier otro) no puede tocar nada, así que lo único
  útil que puede aportar es la indicación exacta. Ahora nombra el antivirus, **la carpeta concreta a
  excluir** y el orden — *excluir primero, reinstalar después*, porque al revés el antivirus se la
  vuelve a llevar y no se avanza. Sale del flujo que describió un asesor: *"desinstalo nativa, entro
  a printdoctor, instalo, después de eso añado extensión en avast, quedó ok"*.
- **Y ese check dejó de escalar casos de gratis.** Era candidato a causa raíz cuando la Nativa no
  estaba *corriendo* — y con Fudo cerrado no correr es el estado normal, como el propio motor
  documenta desde la 3.9. Aparecía en 32 corridas, daba la causa en 8 y 4 de ésas escalaban. Ahora
  sólo es candidato cuando la Nativa **no está en disco**, que es cuando hay algo real que explicar.

### Self-test

- Escenario 102: restaurar de cuarentena **sin** que el ejecutable vuelva no es una reparación, no
  corrige el hallazgo de la Nativa ausente, y el caso **no cierra**. Con el ejecutable de vuelta, sí.
- Escenario 103: producto anotado sin archivos ⇒ se repara; nada instalado ⇒ se instala.
- Escenario 104: con la Nativa en disco el antivirus de terceros no es causa raíz; sin ella sí, y
  el texto tiene que nombrar el antivirus, la carpeta a excluir y el orden.
- **602 asserts, todos pasando**, verificados también con un perfil de usuario vacío.

### Lo que esto deja abierto

- **La premisa de la 0.0.37 no se sostiene en campo.** Tres asesores reportan que Defender la sigue
  detectando y borrando *estando firmada*, y que la 0.0.33 es la que aguanta. El motor ya deja
  elegir versión (3.20), pero la exclusión que agrega no está impidiendo que se la vuelvan a llevar:
  falta verificar que la exclusión quede aplicada y volver a mirar el archivo unos segundos después,
  porque hoy se verifica el efecto **antes** de que el antivirus lo deshaga.
- **Los asesores con el launcher viejo siguen viendo RESUELTO sin que el motor corra.** El
  `.cmd` no se actualiza solo a propósito (lleva la URL de telemetría), así que el arreglo del
  09/09 no les llegó: se ve una PC con Windows 7 donde el `.ps1` ni siquiera parsea y el launcher
  igual escribe RESUELTO.

## [3.20] - 2026-09-14

De un caso que viene reportando un asesor desde el 03/09: *"sigo teniendo problemas con la nativa
0.37, el antivirus sigue detectándola como amenaza y la bloquea siempre que se descarga, y a pesar
de estar desde la carpeta de print doctor la bloquea... tengo que instalar la 0.33, que es la más
estable al día de hoy"*.

### Agregado

- **El asesor elige qué versión de la App Nativa instalar.** Hasta la 3.19 el motor elegía solo —la
  de versión más alta— y no había forma de pedirle otra. Ahora, si hay más de un instalador en la
  PC, los lista con su versión y **elige el asesor** (Enter = la recomendada, que es la más alta
  firmada). Con uno solo, ese; sin consola, la recomendada, igual que antes.

  El motivo es concreto: **la firma de Microsoft no le dice nada a un antivirus de terceros.** La
  0.0.37 resolvió el problema con Defender —86 corridas con 0.0.37+ y ninguna con la Nativa sin
  instalar— pero `nativa.thirdPartyAV` sale `warn` en 32 corridas, 18 de ellas con la 0.0.37 ya
  instalada. Son dos problemas distintos y los estábamos contando como uno.

- **Bajar de versión se puede, pero nunca solo.** El guardarraíl anti-degradación que arregló la
  3.19 sigue igual para el motor; lo que cambia es que **deja de aplicarse cuando la versión la
  eligió una persona** viendo la lista y confirmando en pantalla, con el aviso de qué está
  aceptando (*"esa versión es anterior a la primera firmada: Defender puede volver a ponerla en
  cuarentena"*). Si no confirma, no se instala nada.
  *El guardarraíl existe para que el motor no degrade solo, no para impedirle al asesor resolver el
  caso que tiene delante.*

- **Cuando no hay ningún instalador, el motor lo pide.** Antes caía en la guía de instalación
  manual sin decir lo más simple: copiar el `.msi` al lado de `FudoPrintDoctor.cmd`. Ahora lo dice
  primero, explica dónde más lo busca (Descargas y Escritorio) y avisa que **se pueden dejar los dos
  `.msi`** cuando el cliente necesita una versión distinta a la vigente.

- `-NativeInstallerPath` cuenta como elección explícita: apunta al archivo que se quiere instalar y
  el guardarraíl no lo pisa. Es el camino no interactivo del mismo cambio.

### Self-test

- Escenario 101, seis casos: sin consola gana la firmada; con consola el asesor puede elegir la
  más vieja; si no confirma no se instala nada; Enter deja la recomendada **y eso no habilita
  bajar de versión**; sin instaladores no se inventa ninguno; y con `-NativeInstallerPath` el
  instalador pedido se ejecuta aunque sea anterior al instalado. **586 asserts, todos pasando.**

- **Y una que encontró el CI, no el self-test local: cuatro escenarios de instalación estaban
  leyendo el disco de verdad.** Al pasar la elección del instalador por la función nueva, mockear
  `Find-LocalNativeInstaller` dejó de alcanzar — la elección sale de la que **escanea la PC**. En la
  máquina de desarrollo había *diez* `.msi` de la Nativa en Descargas, así que los escenarios
  pasaban leyendo archivos reales en vez de sus mocks; en el runner limpio se cayeron los siete
  asserts. Ahora se mockea la fuente, y el self-test se verificó corriendo con un perfil de usuario
  vacío para reproducir una PC sin instaladores.
  *Segunda vez en dos versiones que aparece lo mismo: un escenario que pasa por el motivo
  equivocado se ve exactamente igual que uno que pasa bien.*

## [3.19] - 2026-09-14

De la bitácora semanal del 07/09-13/09 y, sobre todo, de tres casos que reportó un asesor en el
canal en dos días. **Los tres eslabones que faltaban entre "la Nativa está instalada" y "Fudo
imprime" no se estaban mirando, y el motor cerraba esas PCs con todo verde.**

### Corregido

- **El motor daba la Nativa por instalada cuando no lo estaba, y por eso no la instalaba.** Hasta
  la 3.18 alcanzaba con una carpeta que matcheara `Fudo*` o una entrada en el registro de
  desinstalación. Las dos señales mienten:
  - **La página web agregada como aplicación desde el navegador** (Chrome › Instalar página como
    app) se registra con `DisplayName` *Fudo* y `DisplayVersion` **1.0**. El motor leía eso como
    "la Nativa instalada es la v1.0", y el guardarraíl anti-degradación que agregó la 3.18
    comparaba el `.msi` 0.0.37 contra esa 1.0 y **abortaba la instalación**. En esas PCs el motor
    no iba a instalar la Nativa nunca, por más que el asesor trajera el instalador. Lo encontró
    Iván Ruquet, y la captura del motor lo dice con todas las letras: *"NO se instalo nada: el
    instalador que hay en la PC es la v0.0.37 y la instalada es la v1.0"*.
  - **El registro queda huérfano** cuando el antivirus se lleva los archivos: 12 corridas en 7 PCs
    cerraron con `nativa.installed` en `ok`/`warn` y la carpeta de la Nativa vacía.

  Ahora la única señal que cuenta es el archivo: **`fudo_native_extension` en `%LOCALAPPDATA%\Fudo`**.
  Sin él la Nativa no está instalada, y el hallazgo dice *cuál* de los tres casos es (no está, quedó
  el registro sin los archivos, o lo que está instalado es la app del navegador). El guardarraíl
  anti-degradación sólo corre contra una versión que salió de un archivo en disco.
  *El guardarraíl estaba bien; el dato con el que decidía, no.*

- **La purga se declaraba reparación sin mirar la medición que la 3.18 agregó para eso.** En 11 de
  32 corridas con medición la cola no bajó (`despues >= antes`) y **7 de esas cerraron con
  `queue.health = fixed`** y "Cola de impresión trabada" listada como reparación aplicada. El campo
  se escribía y no lo leía nadie. Ahora `fixed` exige que la cola haya bajado; si no bajó es `fail`
  con causa propia y deja de figurar como reparación. *Quinta aparición del mismo patrón del
  proyecto: reparar y no verificar el efecto.*

- **El motor le hacía "replug por software" a impresoras que andan bien a propósito.** Las que
  instala soporte de nivel 2 con Zadig (WinUSB/libusb, en Fudo "Directo USB") **no tienen cola de
  Windows y no la necesitan**: Fudo les habla directo por USB. El motor, construido sobre el
  supuesto contrario, las veía como "conectada pero sin puerto asignado" y **le deshabilitaba y
  rehabilitaba el dispositivo a una impresora que estaba imprimiendo**. Ahora se reconocen por su
  driver, se informan como Directo USB y quedan fuera de ese camino. Reportado por Iván Ruquet.

### Agregado

- **El motor revisa si el navegador tiene registrada a la Nativa, y la registra.** Es el eslabón
  que explicaba el *"instalala y volvé a iniciar sesión para que la tome"*: el `.msi` deja el
  binario, pero el navegador sólo la encuentra por una clave de registro que apunta a un manifest.
  Sin esa clave, Fudo se comporta como si la Nativa no estuviera instalada. **Lo que falta no es la
  sesión: es el registro.** Ejecutar la Nativa una vez lo deja hecho, sin cerrar sesión — lo
  propuso Iván Ruquet y es lo que ahora hace el motor, verificando el efecto (vuelve a leer la
  clave y el manifest, nunca el código de salida).
  *Probado de punta a punta contra una instalación real: se borró la clave, el motor ejecutó la
  Nativa, la clave volvió y no quedó ningún proceso corriendo.*

- **El motor revisa la extensión de Fudo en el navegador.** Un asesor encontró PCs con la Nativa
  instalada y el antivirus en orden donde la extensión no estaba puesta, y agregándola a mano desde
  la tienda *la Nativa levantaba sola*. Si la Nativa está en disco y la extensión no aparece en
  ningún perfil de Chrome/Edge, **esa es la causa raíz** y la acción es el link de la tienda.
  *Se afirma con evidencia, para no repetir el bloqueo de cierres que destrabó la 3.11:* sólo
  pesa como `fail` —que impide cerrar el caso— cuando la Nativa está registrada para un
  navegador Chromium, o sea cuando sabemos que Fudo corre ahí. Si no hay ningún navegador
  Chromium en esa cuenta queda `skipped`, y si no se sabe en cuál trabaja el cliente (la
  Nativa también soporta Firefox, y ese registro ahora también se mira) queda `warn`: se ve
  y puede ser la causa, pero no bloquea el cierre.

- **Aviso cuando el motor corre con un usuario distinto al de la sesión.** El registro de la Nativa
  y las extensiones viven en `HKCU` y en `%LOCALAPPDATA%`, o sea que son **por usuario**. Si el
  cliente tiene cuenta estándar y la elevación se hizo con credenciales de administrador, el motor
  está mirando otro perfil: ahora lo detecta, lo dice, y **no registra nada en el perfil
  equivocado** en vez de "arreglar" algo que el Chrome del cliente no va a ver nunca.

- **`nativaInstall` viaja siempre en la telemetría**, incluido el caso "no se intentó" y por qué.
  Venía `null` en 135 de 135 corridas de la 3.18 con `nativa.install` como causa raíz #1, y el
  motivo no era que no viajara: **es que el motor no instala la Nativa por su cuenta, sólo desde la
  opción `F` del menú.** Ahora eso se ve en la planilla en vez de parecer un campo roto.

### Self-test

- **`Reset-Mocks` no hacía nada desde el escenario 92.** El escenario 92 mockea `Get-ChildItem`
  para probar la elección del instalador, y ese mock se comía el de `Reset-Mocks`: en vez de listar
  funciones listaba los "archivos" del mock, no encontraba ningún mock que sacar y **quedaba en
  silencio**. Desde ahí, todos los `Reset-Mocks` eran decorativos y cada escenario corría con los
  mocks del anterior — justo lo que esa función existe para evitar. Se descubrió porque un
  escenario nuevo leyó `0.0.37` de un mock definido 40 líneas más arriba. Ahora los cmdlets van
  calificados con su módulo. *Un escenario que pasa por el motivo equivocado se ve verde y no está
  probando nada.*
- Seis escenarios nuevos (95 a 100): la purga que no baja, la app del navegador tomada por Nativa,
  la extensión ausente/presente/no verificable, el registro del host (queda y no queda), el perfil
  equivocado, y Zadig. **570 asserts, todos pasando.**

### Pendiente (no entró en esta versión, a propósito)

- **Camino Bluetooth** (impresoras que exponen un puerto `COM`, con sus baudios): no se puede
  probar desde acá y el motor hoy descarta activamente esos dispositivos. Esperando un caso real.
- **Ofrecer borrar las colas muertas cuando la cola rebota** (rebote en 14 PCs): es irreversible y
  necesita una decisión sobre cuánto puede borrar el motor con confirmación del asesor.
- **`colaQueUsaFudo` no llega a la planilla**: viaja en el JSON en 63 de 135 corridas pero la
  columna está vacía. Es el receptor (`tools/telemetria-appscript.gs`), no el motor, y no se toca
  a ciegas desde acá.

## [3.18] - 2026-09-08

### Launcher (`FudoPrintDoctor.cmd`) - 2026-09-09

*Sin cambios en el motor: `VERSION` sigue en 3.18.* Cinco arreglos en el `.cmd`, y los cinco
salieron de una sola captura que mandó un asesor.

**Lo que se vio:** una PC donde el `.ps1` tiró un error de parseo en rojo y dos líneas más abajo el
launcher escribió *"RESUELTO. Probar imprimir una comanda desde Fudo"*.

- **El launcher decía RESUELTO sin que el motor corriera.** La PC tenía PowerShell 2.0, donde el
  operador `-in` no existe (es de PS 3.0), así que **el archivo entero no parseó y no se ejecutó una
  sola línea**. Y verificado acá: `powershell -File` con un error de parseo **sale con código 0**,
  que es justo el código con el que el launcher escribía RESUELTO.
  *Es el falso positivo más caro que produjo este proyecto, y estaba en el único archivo donde nunca
  aplicamos nuestra propia regla de verificar el efecto en vez del código de retorno.*
  Ahora el `resultado.json` anterior se borra **antes** de correr, y si al terminar no existe, el
  launcher dice que el motor no llegó a diagnosticar y pide una captura — nunca RESUELTO.
- **Además, no hay telemetría de esas corridas.** Sin ejecutar, no se reporta nada: *una PC donde el
  motor nunca funcionó es invisible en la planilla*. Puede haber un grupo de clientes con Windows
  viejo del que no tenemos un solo dato, y es candidato a explicar parte de los casos donde el
  script no se usa.
- **El launcher ahora verifica que la PC pueda correr el motor**, antes de todo: PowerShell 5 o
  superior y que exista `Get-Printer`. El segundo chequeo es el que importa de verdad — `Get-Printer`
  existe desde Windows 8, así que **en Windows 7 el motor no puede funcionar ni con PowerShell 5.1
  instalado**. Si no se cumple, corta con un mensaje que dice explícitamente *"no es un problema del
  cliente ni de la impresora: es esta PC"* y que hay que resolver el caso a mano.
  *El sondeo está escrito con sintaxis de PowerShell 2.0 a propósito: tiene que poder correr en las
  PCs que va a rechazar.*
- **El launcher verifica que el `.ps1` sea la versión publicada, y lo actualiza si no.** Antes sólo
  miraba si el archivo **existía**: una copia vieja se seguía usando para siempre. Es la explicación
  de las corridas 3.8 que siguen apareciendo en la planilla con el motor ya en 3.18 — y de por qué
  el gate de versión del motor no puede salvarnos, *porque un motor viejo no tiene el gate*. En esas
  filas se ve `engine.updateAvailable` en `warn`: el motor sabía que había una versión más nueva y
  seguía igual, que es lo que hacía la 3.8.
  Se compara contra el `VERSION` publicado buscando la línea del `SchemaVersion` dentro del `.ps1`.
  Sin internet no bloquea: usa lo que hay y **avisa** que puede estar desactualizado.
- **El launcher dejó de preguntar el ID del caso.** Lo pide el motor desde la 3.14, así que se
  preguntaba dos veces y el `set /p` le agregaba un espacio al final (se ve en las filas viejas como
  `"215475858914549 "`).
- **Deja la PC del cliente limpia.** El `telemetria.txt` se borra siempre —**lleva la URL interna de
  reporte**, y quedaba en el disco de cada cliente— y el motor se borra preguntando, con Enter = sí.
  Es el pedido de Gustavo, y resultó ser la causa raíz de las corridas viejas: un `.ps1` olvidado en
  el escritorio de un cliente lo vuelve a usar el próximo que abra el `.cmd` ahí.

### Agregado

- **`tools/Configurar-Telemetria.cmd`**: arma la copia interna del launcher con la URL de telemetría
  adentro, para distribuir. Se le puede arrastrar encima un `.cmd` interno que ya tenga la URL y la
  toma de ahí sin tipearla ni mostrarla. Valida que sea una URL de Apps Script (`https://` … `/exec`)
  y verifica el resultado antes de decir que salió bien.
  *La sustitución la hace PowerShell y no batch: copiar un `.cmd` línea por línea con `echo` pierde
  los `>nul 2>&1` y los `%~dp0`. Probado — cambia exactamente una línea y el resto queda byte a byte
  idéntico.* La URL no toca el repositorio en ningún momento.
- **Marcador `LAUNCHER-VERSION` en el `.cmd`.** El updater **no pisa** el launcher existente, a
  propósito, porque lleva la URL: por eso este archivo nunca se actualiza solo y hay que
  distribuirlo a mano. El marcador queda para que el updater pueda compararlo y refrescarlo
  preservando la URL — *pendiente, y es lo que haría que el próximo cambio de launcher no requiera
  otra distribución manual.*


Todo lo de esta versión salió de **la respuesta de un asesor a un caso concreto**, no de la
telemetría. Es la PC con 218 y 1.182 comandas encoladas donde `queue.purge` corrió 16 veces sin
resolver nada — el hallazgo que la bitácora semanal dejó abierto y sin propuesta. La respuesta
descartó las dos hipótesis que teníamos y dio una tercera, y de paso trajo un bug de la App Nativa
que la telemetría no podía ver.

> *"Cuando ingresé, el cliente tenía demasiadas impresoras instaladas... imprimió, pero fue a que
> eliminé tanta impresora que tenía instalada, algunas ya ni siquiera figuraban disponibles. Se
> borraron [las comandas], pero al enviar una prueba de nuevo, enviaba como 50 más."*

**Purgar funcionaba perfecto y no podía ganar nunca.** Cada comanda se multiplicaba por la cantidad
de colas instaladas, así que la cola se tapaba sola más rápido de lo que se limpiaba. Lo que
resolvió el caso fue **borrar impresoras**, que el motor no hace ni sugería.

### Agregado

- **El motor mide por qué purgar no alcanza.** Cuenta cuántos trabajos había, cuántos quedaron
  después de limpiar y **cuántos volvieron dos segundos más tarde**, contra cuántas colas hay
  instaladas y cuántas no tienen hardware presente. Si la cola se vuelve a llenar, lo dice y apunta
  a lo que hay que revisar: *"esta PC tiene N impresoras instaladas y M no tienen hardware; cuando
  hay muchas, una sola comanda se multiplica en decenas de trabajos"*.
  *Se mide, no se borra.* Borrar colas del cliente es irreversible y no se hace sin datos: primero
  hay que ver en la telemetría cuántas PCs están en esta situación.
- **El `.msi` de la App Nativa firmada pasa a ser parte del kit del asesor.** Se chequea al
  arrancar, **sin mirar lo que tiene el cliente**: lo que importa es si el asesor puede resolver una
  Nativa vieja cuando aparezca. Si falta, avisa fuerte, explica qué falta (no hay ninguno / el que
  hay es anterior a la firmada / hay un `.exe` que no declara su versión) y pide confirmación para
  seguir. Código de salida `7` si el asesor decide cortar; `-NoNativaKitCheck` es el opt-out y viaja
  en la telemetría.
  *No bloquea el diagnóstico si el asesor sigue: la impresora puede estar rota por algo que no tiene
  nada que ver con la Nativa, y dejarlo sin herramienta sería peor. Se arregla una vez —el archivo
  va junto a los dos que ya se copian a la PC del cliente— y sirve para todos los casos. El asesor
  del caso no sabía que había que pasarlo.*
- Self-test: **538 asserts** (eran 502).

### Corregido

Los tres del camino de instalación de la App Nativa, y los tres los describió el mismo asesor:
*"el motor dice que instala la nativa, pero al corroborar en la versión web muchas veces sigue sin
detectarla... siento que no instala la nativa correcta o al menos una versión compatible"*. **Tenía
razón en las tres.**

- **Se instalaba el instalador que apareciera primero por fecha.** Si el cliente tenía uno viejo en
  Descargas —muy probable, bajado meses atrás—, el motor instalaba **ese**: una versión sin firmar
  que el antivirus vuelve a comerse. Ahora se elige **por versión declarada**, no por fecha, y
  **nunca se degrada** lo que ya está instalado (el desastre `0.0.36 → 0.0.18` ya pasó en este
  proyecto). Si el mejor instalador disponible queda por debajo de la firmada, se instala pero se
  avisa que el antivirus puede volver a bloquearla.
- **Un `.msi` se lanzaba con `Start-Process` directo**, o sea abriendo el **asistente gráfico** en la
  pantalla del cliente y esperando a que alguien lo complete. Desde la 3.14 la Nativa se distribuye
  como `.msi` y la búsqueda lo prefiere, así que era el caso normal. Ahora va por `msiexec /qn`, que
  es lo que el camino de *actualización* ya hacía bien desde la 3.14. **Cuarta vez que aparece el
  mismo patrón: dos caminos que hacen lo mismo y uno se quedó sin el arreglo del otro.**
- **No se verificaba nada.** Se miraba el código de salida y si el proceso estaba corriendo — y el
  proceso normalmente **no** corre, porque lo levanta el navegador. La reparación se reportaba
  aplicada con la Nativa sin instalar. Ahora se relee el disco y el registro: si no quedó, se dice
  que no quedó y por qué; si quedó, el hallazgo previo de *"App Nativa NO instalada"* se corrige y
  el caso puede cerrar.
- **Una cola con muchos trabajos ya no "confirma" que Fudo esté mandando comandas.** El texto decía
  que N trabajos acumulados *confirman* que el problema no es Fudo. No lo confirman: con muchas
  impresoras instaladas, unas pocas comandas se convierten en cientos de trabajos. Se vio una PC con
  1.182 que eran unas pocas comandas multiplicadas.

### Interno

- **`Reset-Mocks` en el self-test.** Los mocks de un escenario quedaban en scope para todos los que
  venían después, y eso ya hizo pasar **tres** escenarios por el motivo equivocado: uno se aprobó
  contra un mock viejo en vez de contra el código real, otro contra un mock que devolvía justo el
  texto esperado, y un tercero se cayó porque un mock que explota a propósito seguía vivo. *Un
  escenario que pasa por el motivo equivocado es lo peor que le puede pasar a un self-test: se ve
  verde y no está probando nada.* Ahora hay una foto de las funciones previas a cualquier mock y una
  forma de volver a ese estado.
  Todavía **no** se llama desde `Reset-State`: hay escenarios viejos escritos contando con que el
  mock del anterior siga vivo, y migrarlos es un trabajo aparte. Los escenarios nuevos lo llaman
  explícitamente. *Esta versión ya lo aprovechó: el escenario 92 fallaba porque el 91 y el 78 dejaban
  mockeadas justo las dos funciones bajo prueba.*

### Pendiente

- **Borrar las colas que el cliente no usa.** Es lo que resolvió el caso a mano y el motor todavía no
  lo hace. Primero hay que ver en la telemetría (`purgaMedicion`) en cuántas PCs la cola rebota
  después de purgar y cuántas colas muertas hay, y recién entonces ofrecer borrarlas por el mismo
  camino de confirmación que la purga.
- Dónde se multiplica exactamente la comanda —si Fudo manda N copias, si la Nativa las fanout, o si
  son colas duplicadas sobre el mismo puerto— sigue sin confirmarse. La medición nueva es lo que va a
  permitir distinguirlo.
- Nada del camino Ethernet de la 3.16 se probó contra hardware real.

## [3.17] - 2026-09-07

De la bitácora **semanal** del 31/08 al 06/09 (45 corridas nuevas en 33 PCs, 33 de ellas en 3.14).
Las dos correcciones son de la misma familia y es la que más veces reapareció en este proyecto:
**reparar y no verificar.** Una toca el antivirus del cliente sin evidencia de que el antivirus
tenga algo que ver; la otra repara de verdad y el caso escala igual porque nadie vuelve a mirar.

### Corregido

- **El motor le agregaba exclusiones al antivirus del cliente sin ningún motivo.** Dos PCs en 3.14
  (`nativaVersion` `0.0.19` y `0.0.24`) quedaron con `nativa.defenderExclusion = fixed` teniendo la
  causa raíz en el hardware — `printer.disconnected` y `hw.disconnected`. O sea: el motor modificó
  la configuración de seguridad de una PC ajena mientras diagnosticaba una impresora desenchufada.
  **Es la tercera versión que corrige esta misma familia**: la 3.10 apagó la exclusión preventiva
  para las Nativas firmadas, la 3.12 apagó la restauración sobre detecciones históricas, y la rama
  siguió viva para las Nativas por debajo de `0.0.37`.
  *Mirando el `if/elseif` completo el caso resultó peor de lo que decía la bitácora:* la rama de
  arriba se queda con "hay detecciones y la Nativa está presente" y la del medio con "hay
  detecciones y no está", así que a esta rama **sólo se llega con CERO detecciones de Defender sobre
  la Nativa**. El único disparador real era que la Nativa estuviera apagada — que con Fudo cerrado
  es el estado normal, como ya documentaba el código de al lado. No había nada que prevenir.
  Ahora no se toca el antivirus: queda un chequeo que dice explícitamente que no se modificó nada y
  por qué. Y la decisión pasó a vivir en **un solo lugar** (`Test-DefenderExclusionNeeded`), que era
  el problema de fondo: había dos caminos distintos decidiendo lo mismo y uno se había quedado sin
  el gate del otro. El self-test verifica que los dos decidan igual.
- **La restauración de la cuarentena funcionaba y el caso escalaba igual.** 4 PCs en 3.14 con
  `nativa.installed = fail`, causa *"App Nativa de Fudo NO instalada"* y `needs_escalation`; en dos
  de ellas la corrida siguiente —1 y 3 minutos después— ya traía la `0.0.37`. **La reparación
  andaba; el asesor tenía que correr el diagnóstico dos veces** y la transición quedaba como
  `sigue_fallando`.
  El motivo: `nativa.installed` se registra en la capa 0b.1, **antes** de la restauración de la capa
  0b.2, y nadie lo volvía a mirar. *El veredicto salía de una foto vieja de la PC, que es el mismo
  bug que la 3.11 corrigió para el inventario de colas.*
  Faltaba un primitivo: **una reparación posterior tiene que poder corregir un hallazgo anterior**
  (`Update-CheckFinding`). Con la Nativa de vuelta en disco, el hallazgo pasa a `fixed`, deja de ser
  candidato a causa raíz, el caso cierra, y la versión post-reparación es la que viaja en la
  telemetría — antes se reportaba el vacío de antes de restaurar, así que en la planilla la PC
  figuraba sin Nativa.
  *La corrección no se aplica si la restauración devolvió una versión más vieja: eso sigue siendo un
  problema (lo detecta el chequeo de degradación desde la 3.7) y no puede pasar por resuelto.*

### Agregado

- Self-test: **502 asserts** (eran 478). Cubren las ocho combinaciones de la decisión del antivirus
  —incluida la equivalencia con el gate de la cuarentena—, la corrección de un hallazgo anterior y,
  sobre todo, **que el caso deje de escalar por algo que ya se arregló**, que es el daño real.

### Evaluado y NO implementado

- **Pasar los cuatro chequeos de capa Fudo de `warn` a `skipped`** (propuesta 3 de la bitácora).
  **No, y la premisa no se sostiene.** El argumento era *"son 5 líneas de advertencia por corrida que
  el asesor lee y no puede accionar"*. Leyendo el código: el semáforo del resumen muestra **una línea
  por área**, no una por chequeo, y las acciones de Fudo ya se **colapsan en una sola línea** desde la
  3.11 (*"Verificar en la web app de Fudo: impresora registrada, cocina/área, categorías, salas"*).
  El asesor ve **una** línea de semáforo y **una** acción, no cinco advertencias. Las cinco filas
  existen en el JSON y en la telemetría, no en pantalla.
  Y aplicarlo **rompería algo**: `Get-NextActions` sólo recorre chequeos en `fail`/`warn`, así que
  pasarlos a `skipped` eliminaría esa única acción útil — el último tramo del diagnóstico, que es
  precisamente lo que el asesor sí tiene que hacer. Rompería además la aserción del escenario 62.
  *Queda como pendiente real, pero de calidad de datos: cuatro filas que nunca varían son ruido para
  el análisis agregado, no para el asesor. No justifica tocar la superficie de cierre que estabilizó
  la 3.11.*

### Pendiente

- **Colas atascadas grandes que no se resuelven.** Una PC (CL, 04/09) con **218** trabajos en BARRA
  TRAGOS y **1.182** en CAJA PRINCIPAL; `queue.purge` corrió 16 veces en la semana y esa PC siguió en
  `sigue_fallando`. Es el hallazgo sin propuesta de esta bitácora y probablemente el más grande que
  queda abierto: purgar no está alcanzando y hay que entender por qué.
- `colaQueUsaFudo` vacío en 274/274 filas y `deFudo = 0`: **ya corregido en la 3.15**, que todavía no
  está publicada. Los cinco chequeos de capa Fudo que nunca concluyen dependen de eso.
- 27% de las corridas nuevas (12 de 45) siguen con motor viejo — 8 en 3.8 y 4 en 3.12. El gate de
  versión existe recién desde 3.14, así que no los frena: es distribución, no código.
- Caminos poco validados, sin novedad en toda la semana: 2 corridas Ethernet y 1 WSD.

## [3.16] - 2026-09-07

Pedido del canal (Karen, con aportes de Iván y datos de la bitácora del 04/09): **la impresora de
red que el motor no podía ver porque está en otra subred que el PC.** Una comandera con IP de
fábrica `192.168.1.x` en un local cuyo router reparte `192.168.0.x` está en el mismo cable, pero el
PC no tiene ninguna dirección en esa subred y no le puede ni hablar. Hasta acá el motor cerraba con
*"no se encontraron impresoras por IP en la red"*, que era falso.

**El criterio de esta versión es descubrir y explicar, no escribirle a la impresora.** El motor
resuelve todo lo que se puede resolver desde la PC —dónde está, de qué marca es, qué herramienta le
corresponde, qué valores poner— y el asesor hace lo único que no se puede automatizar: los dos
clicks en la utilidad del fabricante. Escribirle la IP por software queda afuera a propósito: ver
*Evaluado y NO implementado*.

### Agregado

- **Se busca la impresora en las subredes donde puede estar, no sólo en la del PC.** Las candidatas
  salen ordenadas por fuerza de la evidencia: primero la subred de una cola de Windows que apunta
  afuera (ahí **hubo** una impresora, es lo más fuerte que se puede tener sin verla), después los
  defaults de fábrica de las comanderas (`192.168.1`, `192.168.0`, `192.168.123`, `10.0.0`).
- **Para poder verla, el motor le suma una IP secundaria temporal a la placa del PC y la saca al
  terminar.** Esto es lo que destraba el caso: el bloqueo que reportó el canal era que la única
  salida conocida —desenchufar el cable del router y conectar la impresora al PC— deja al cliente
  **sin internet y al asesor sin asistencia remota**, y en una PC de escritorio sin WiFi no hay
  alternativa. Una placa puede tener más de una dirección: la PC conserva la suya y suma una en la
  subred de la impresora. No hace falta desenchufar nada, ni pedir otra notebook, y **no depende de
  la marca**.
  - **Va detrás de opt-in, no por default.** Es lo más invasivo que hace el motor y no está probado
    contra hardware real: si hay consola se le pregunta al asesor, en modo agente no se hace, y
    `-AllowNetProbe $true` lo fuerza. Cuando nadie confirma, el hallazgo **igual queda visible** con
    el motivo y cómo habilitarlo — no desaparece en silencio.
  - **La IP se saca siempre**, también si el motor aborta: la limpieza va en un `finally`, porque
    los caminos de salida son varios `exit` distintos. Dejarle una dirección de más a la placa del
    cliente sería peor que no haber revisado nada.
- **La impresora dice quién es, en su propio protocolo.** Sobre el mismo socket 9100 se le manda
  `GS I 66` / `GS I 67` (fabricante y modelo), que es lo que usa cualquier utilidad ESC/POS. Es
  mejor que deducir la marca del OUI de la MAC: no hay tabla que mantener ni que adivinar, y lo
  contesta el aparato. Si no contesta —las OEM chinas suelen no hacerlo— se dice que no se pudo
  saber, y se guarda la **MAC**, que no cambia aunque cambie la IP.
  - La tabla de OUIs por fabricante **arranca vacía a propósito**: poner prefijos sin verificarlos
    sería adivinar el fabricante, que es justo la familia de falsos positivos que este proyecto
    arrastra. Se llena con las MAC reales que empiecen a llegar por telemetría.
- **Una instrucción única en el resumen, con los valores ya resueltos.** Bloque
  *IMPRESORA DE RED EN OTRA SUBRED*: dónde está, la marca, la MAC, **qué IP ponerle** (probada,
  libre, en el rango del router), máscara, gateway, y con qué herramienta. *Ahí está el rato que se
  le quería ahorrar al asesor: no en clickear, en averiguar qué poner.*
- **La herramienta de configuración de red se busca en la PC, por marca.** Los nombres de los
  ejecutables salen del empaquetado que ya mantiene el equipo (Delitools › `NetConfigTools`), no se
  adivinan — y **ninguno se llama como uno esperaría**: la de Epson es `ENConfig.exe`, no
  `EpsonNetConfig.exe`. Se busca en la instalación de Delitools y en una carpeta `NetConfigTools`
  al lado del script.
  | Marca | Ejecutable |
  |---|---|
  | Epson | `ENConfig.exe` |
  | Bixolon | `NetConfiguration.exe` |
  | Sam4s | `GIANT&GCUBE Tool.exe` |
  | XPrinter | `XPrinter.exe` |
  | 3nStar | `POS Printer Test.exe` |
  - **No se busca en Descargas.** Acá se termina lanzando un ejecutable, y una carpeta donde cae
    cualquier cosa no es un lugar del que convenga ejecutar nada.
  - 3nStar y XPrinter comparten la herramienta OEM (comparten `EnCodeQr.dll` byte por byte), así
    que el mapa marca→herramienta no es 1 a 1. Y ninguna es un `.exe` suelto: todas necesitan su
    carpeta al lado (DLLs, `.ini`, `Resources`), así que se lanzan con el directorio de trabajo
    puesto ahí o arrancan rotas.
  - Si la herramienta **no** está, el motor igual dice cuál hace falta y de dónde sale, y avisa que
    instalando Delitools la próxima corrida la encuentra sola. *El diagnóstico es nuestro y funciona
    igual: que la herramienta esté sólo cambia si el motor la abre.*
- **`otraSubred` en la telemetría**: candidatas, revisadas, encontradas con MAC y OUI, y el plan.
  Es lo que permite saber si el motor está resolviendo la instrucción completa o quedándose corto.
- Self-test: **478 asserts** (eran 409). Escenarios nuevos para el orden de las subredes candidatas,
  la IP libre que no puede estar ocupada, la tabla de herramientas (incluido el `&` del ejecutable de
  SAM4S), la instrucción completa con y sin marca, el opt-in, la identidad por ESC/POS y OUI, la
  limpieza de la IP temporal —incluido el caso de una que no se puede sacar— y el camino completo.

### Corregido

- **El self-test se quedaba sin imprimir su propio resultado si un escenario posterior usaba el
  resumen.** El escenario que verifica el resguardo del resumen reemplaza `Build-HumanSummary` por
  uno que explota a propósito, y ese mock quedaba en scope: cualquier escenario nuevo que lo usara
  se caía, y la excepción salía del self-test entera, sin dar ni el conteo final. Ahora el mock se
  saca en el mismo escenario que lo pone. *Es la tercera vez en dos versiones que un mock que quedó
  en scope hace pasar o fallar un escenario por el motivo equivocado: hay que resolverlo de raíz.*

### Evaluado y NO implementado

- **Escribirle la IP a la impresora por software.** Es lo que uno querría, y no va. Las utilidades
  de marca lo hacen por SNMP (Epson) o por comandos propietarios sobre 9100 que **cambian según el
  modelo** (los clones Xprinter/3nStar). PowerShell 5.1 no trae SNMP nativo, y mandar comandos
  adivinados a una impresora que no conocemos tiene una falla posible muy cara: **la impresora queda
  en una IP inalcanzable y el local sin comandas**, peor que el problema que fuimos a resolver. Es
  la misma regla que la 3.10: un diagnóstico vacío es preferible a actuar sobre algo que nadie pidió.
- **Automatizar las GUIs de las utilidades.** Manejar `ENConfig.exe` por automatización de ventanas
  se rompe con cada versión de la app. El motor las encuentra, dice cuál abrir y con qué valores; los
  clicks son de una persona.
- **Empaquetar las utilidades en este repo.** Son ejecutables de terceros: redistribuirlos es un tema
  de licencia y el repo es público. Se apunta a lo que el equipo ya tiene instalado.

### Pendiente

- **Nada de esto se probó contra una impresora Ethernet real** — ni el barrido de la subred ajena, ni
  la IP secundaria, ni la identidad por `GS I`. Es la feature más grande del proyecto sobre la capa
  menos probada. Antes de anunciarla en el canal hace falta una térmica de red enchufada.
- La IP temporal se saca en el `finally`, pero si el proceso se mata de una forma que no lo ejecuta
  (corte de luz, kill), queda puesta. El motor la informa en pantalla y en la telemetría para poder
  sacarla a mano; una limpieza automática al arrancar la corrida siguiente queda pendiente.
- Reapuntar automáticamente el puerto de la cola cuando la impresora ya está en la IP correcta: hoy
  el plan lo indica y la verificación existe, pero el reapuntado sigue siendo un paso aparte.
- Alta por primera vez (impresora recién sacada de la caja, sin cola ni historial): reusa este mismo
  descubrimiento, pero todavía no tiene su propio camino en el diagnóstico.
- Impresoras fiscales: detectarlas por modelo y declarar que están fuera de alcance.

## [3.15] - 2026-09-04

De la bitácora del 04/09. El hallazgo de arranque fue un **crash en producción**: una corrida de
la 3.14 en la PC de un cliente terminó en `engine_error` a los 6 minutos, con los 12 chequeos
hechos y el diagnóstico calculado, porque el armado del resumen llamaba a una función que **sólo
existe dentro del self-test**. El asesor se quedó sin nada en pantalla.

Buscando otras llamadas del mismo tipo aparecieron **dos más**, las dos en reparaciones que el
proyecto nunca pudo probar contra hardware real. Ninguna de las tres las podía encontrar el
self-test ejecutando escenarios: en el self-test esas funciones sí existen. La lección nueva del
día es que **un self-test que comparte scope con el motor puede tapar exactamente el tipo de bug
que tiene que encontrar**, y que por eso hace falta un chequeo que mire el código y no sólo su
resultado.

### Corregido

- **El motor abortaba al armar el resumen cuando cortaba por modo.** `Build-HumanSummary` llamaba
  a `Get-CheckById`, que está definida adentro de `Invoke-SelfTest`: en la PC del cliente no está
  en scope y la corrida moría con `CommandNotFoundException`. Caso real: una corrida de 6 minutos,
  12 chequeos, `status=engine_error` y cero diagnóstico para el asesor. Estaba en una rama
  condicional (el corte "no hay impresoras del tipo elegido"), y por eso otra corrida de la misma
  versión con el mismo chequeo en `warn` no se cayó.
  Ahora el lookup es el mismo que usa el resto del motor, y **el resumen dejó de poder tirar la
  corrida**: si su armado falla, queda registrado como error del motor y se imprime un resumen
  crudo con el resultado, la causa y qué hacer. *El resumen es presentación; el diagnóstico ya
  está calculado y no hay ninguna razón para perderlo.*
- **Una cola pausada no se reanudaba nunca.** Antes de la prueba física el motor destraba la cola,
  y para eso llamaba a `Resume-PrintQueue`, que **no existe en Windows** (`PrintManagement` trae
  `Resume-PrintJob`, para un trabajo, no para la cola). La llamada vivía dentro de un `try/catch`,
  así que no rompía nada: simplemente no hacía nada, en silencio. Consecuencia: con la cola
  pausada el ticket de prueba quedaba encolado, no salía papel y el asesor contestaba —bien— que
  no salió. **Es el mismo falso negativo que la 3.10, por otra vía.** Ahora se reanuda con el
  método `Resume()` de `Win32_Printer`, que sí existe, y si falla se dice por qué.
- **El replug por software nunca reiniciaba el dispositivo.** Llamaba a `Restart-PnpDevice`, que
  tampoco existe (el módulo `PnpDevice` trae `Disable-PnpDevice` y `Enable-PnpDevice`). También
  dentro de un `try/catch`: quedaba corriendo sólo el `pnputil /scan-devices` y la nota decía
  *"no se pudo reiniciar el device"* en todas las corridas. Ahora deshabilita y vuelve a
  habilitar, que es literalmente el replug. **Con un resguardo:** si el `enable` falla después de
  un `disable` que anduvo, la impresora quedaría deshabilitada en Windows y el cliente terminaría
  peor que antes, así que se reintenta habilitarla siempre.
- **El motor afirmaba que Fudo no manda comandas sin tener con qué saberlo.** `deFudo = 0` en
  **146 de 146** entradas de historial de 229 corridas, y los únicos nombres de documento que
  Windows reporta son los genéricos del spooler (*"Imprimir documento"* 134, *"Documento de
  Impressão"* 7, *"Print Document"* 5). Con eso, el chequeo del último tramo salía en `warn`
  **como causa raíz**, en plano `fudo_config`, diciendo *"Ninguna cola recibió comandas de Fudo"*
  y mandando al asesor a revisar la configuración de Fudo de un local donde Fudo podía estar
  imprimiendo perfectamente. **Es el patrón de los catorce falsos positivos del proyecto: una
  ausencia de dato leída como evidencia.**
  Ahora, cuando ningún trabajo del historial trae un nombre que diga algo, el motor dice que **no
  se puede saber**: nuevo estado `no_atribuible` (ni `sin_comandas`, que afirma que Fudo no mandó
  nada, ni `sin_datos`, que dice que no hay historial), el chequeo deja de ser causa raíz y pasa
  a plano `os`, el cierre baja a confianza `medium` y cuenta como `cierreSinVerificarFudo`. El
  caso **sigue cerrando** si la impresora imprime —que es lo que este motor arregla— y el asesor
  lee la línea *FALTA* explicando que ese último tramo hay que verificarlo a mano.
  *Cuando hay un nombre de documento útil y ninguno es de Fudo, la conclusión de antes sigue
  valiendo: eso no cambió.*
- **La cola de prueba del propio motor volvía a contarse como historial del local.** El descarte
  era por nombre de documento, y **40 de las 146 entradas** eran colas `FUDO-TEST-*` cuyo trabajo
  Windows reportó con el nombre genérico, así que el filtro no las veía. Ahora se descartan
  también por nombre de cola. *El motor no puede contarse a sí mismo como evidencia* — tercera
  vez que aparece este mismo bug, ahora por la variante del nombre del documento.
- **`nativa.update_local` fallaba en silencio.** Caso reportado por una asesora (*"no me actualiza
  la nativa, lo intenté 3 veces"*, terminó reinstalando a mano) y reproducido en telemetría: el
  motor ejecutó la acción **dos veces** sobre la misma PC, la versión no se movió de la `0.0.18`,
  no reportó ninguna reparación, y el chequeo quedaba en `warn` **con el mismo texto que cuando no
  se intenta nada**. Ahora, si se intentó y la versión no subió, se dice explícitamente que **NO
  se pudo actualizar** y por qué: código de salida del instalador, instalador no lanzable, o
  *"terminó bien y la versión no cambió, y la App Nativa estaba corriendo"* — que es el caso
  probable, con los archivos en uso. También avisa qué hacer: cerrar Fudo y volver a correr, o
  correr el instalador a mano.
  *Queda en `warn` y no en `fail` a propósito: una Nativa vieja no impide que la impresora
  imprima, y un `fail` acá volvería a bloquear el cierre de casos que la 3.11 desbloqueó.*
- **Una actualización de la Nativa que funciona podía dejar la PC igual de expuesta.** El
  instalador que hay en la PC apunta hoy a la `0.0.27`, no a la `0.0.37` firmada: el update tomaba
  y el antivirus seguía siendo un tema, sin que nadie lo dijera. Ahora, cuando el destino queda
  por debajo de la firmada, se avisa en la recomendación. *El arreglo de fondo sigue siendo
  distribuir el `.msi` de la `0.0.37`, que no es código.*

### Agregado

- **El self-test verifica que el motor no llame a nada que no exista.** Recorre el AST del propio
  archivo y, para cada función del motor, comprueba que todo nombre que invoca resuelva en un
  entorno donde el self-test todavía no definió ningún mock ni helper. Es lo que encontró las tres
  llamadas fantasma de esta versión, y **corre primero**, antes que cualquier escenario.
  *Sin esto, agregar un escenario no alcanzaba: los 360 asserts de la 3.14 pasaban con el crash
  adentro, porque el self-test comparte scope con el motor y la función faltante sí existía ahí.*
- **`colaQueUsaFudo` viaja en la telemetría.** La columna existía en el receptor desde el día uno
  y el motor **nunca la mandó**: vacía en 229 de 229 filas. Cuando el historial no permite
  atribuir, viaja como `no_atribuible`, que es un dato distinto de vacío. Se corrigió también la
  regla de lectura en `docs/telemetria.md`, que decía que un valor vacío era sospecha de
  configuración en Fudo.
- **El resultado del intento de actualizar la Nativa viaja en la telemetría** (`nativaUpdate`:
  si se intentó, si subió, código de salida, motivo, y si el destino queda sin firmar). Sin esto,
  un update que no toma es indistinguible de uno que no se intentó — que es justamente por qué el
  caso de la asesora no se veía en la planilla.
- Self-test: **409 asserts** (eran 360). Escenarios nuevos para el crash del resumen y su
  resguardo, la atribución del historial, la cola propia con nombre genérico, el update de la
  Nativa que no toma, y las dos reparaciones que llamaban a cmdlets inexistentes.

### Evaluado y NO implementado

- **Atribuir las comandas de Fudo por proceso** (mejora 2 de la bitácora, punto b). El evento 307
  del log del spooler **no trae el proceso** que originó el trabajo: trae id, documento, usuario,
  máquina, cola, puerto y bytes. Atribuir por correlación temporal con la App Nativa corriendo
  sería una heurística, y aplicada sobre el único camino que habilita `resolved` fabricaría
  exactamente el tipo de falso positivo que este proyecto ya corrigió catorce veces. **Lo que sí
  entró es la mitad honesta: dejar de afirmar lo que no se puede saber.** Para poder afirmarlo, el
  cambio es del lado de la App Nativa: que nombre sus trabajos con un prefijo propio. Queda
  pendiente y no es de este repo.
- **Dedupe en el receptor de telemetría** (`tools/telemetria-appscript.gs`). Hay un duplicado
  exacto por reintento del POST sin idempotencia, pero el receptor está fuera del alcance del
  self-test y no hay forma de verificarlo desde acá: tocarlo a ciegas arriesga la telemetría en
  producción. Queda para revisión manual.
- **Contar sólo `status='resolved'` en el agregado de la planilla.** Cinco de las quince
  "resueltas" nuevas son filas 3.8 con `resuelto=TRUE` y `needs_escalation` a la vez, un bug
  anterior a la 3.11 que el resumen suma igual. También es del receptor, misma razón.

### Pendiente (no entró en esta versión)

- Cola de prueba de respaldo cuando `hw.noPortBound` no consigue puerto: se renombró el motivo del
  salteo a `sin_puerto_asignado`, pero el fallback no se creó. Hubo una PC con 3 corridas seguidas
  sin prueba física por esto.
- Rama del antivirus *"instalada pero no corriendo"*: una corrida 3.12 todavía agregó una
  exclusión con la Nativa presente, y esa exclusión se llevó la causa raíz de un cierre que en
  realidad resolvió el rebind del USB. No se reprodujo en ninguna corrida 3.14: hay que confirmar
  si la rama sigue viva antes de tocarla.
- Causa raíz sin redactar en la variante de red (*"Prueba fisica ESC/POS por red"*, el título del
  paso). La variante USB ya quedó redactada en 3.14.
- Inventario: colas de red con `estado: "sana"` que `conn.net` da como inalcanzables.
- Cambio de IP de impresoras de red (pedido del canal): confirmado que no hay vía genérica de
  fabricante. Lo genérico desde Windows es reapuntar el puerto RAW y descubrir la impresora en la
  red; sigue sin implementar.

## [3.14] - 2026-09-03

Tres pedidos del equipo, no hallazgos de telemetría. Los tres apuntan al mismo problema de fondo:
**la calidad de lo que llega a la planilla y la versión con la que se corre.** El 03/09 una sola
corrida con la 3.8 reprodujo cuatro bugs ya corregidos y sumó una fila a *"resueltas"* que no lo
estaba.

### Agregado
- **El motor no corre si está desactualizado.** Antes avisaba y seguía. Ahora, si confirma que hay
  una versión más nueva publicada, corta antes de diagnosticar (código de salida `5`) y explica
  cómo actualizar.
  *Criterio deliberado: se bloquea sólo cuando se **confirma** que hay una más nueva. Si no se pudo
  consultar —cliente sin internet, la red del local bloqueando GitHub— **no** se bloquea: eso no es
  "versión vieja", es "no se sabe", y bloquear ahí dejaría al asesor sin herramienta justo donde
  más se la necesita. `-NoUpdateCheck` no consulta y por lo tanto no bloquea; es un opt-out
  explícito, no un bypass silencioso, y viaja en la telemetría para que se vea si alguien lo usa
  de atajo.*
  **Ojo con el alcance:** esto sólo sirve de acá en adelante. Las copias que ya están en la calle
  (3.8, 3.11) no tienen este código y no se van a bloquear solas — eso se arregla con distribución.
- **El ID de conversación pasa a ser obligatorio.** Eran 15 dígitos: *verificado contra la API de
  Intercom* (`215475776099648`, `215475776190952`, `215475755436482`). Hasta la 3.13 era opcional
  —el launcher decía *"Enter para omitir"*— y llegaba vacío en casi todas las corridas, así que no
  se podía cruzar una corrida con la conversación del cliente, que es lo único que cuenta qué pasó
  de verdad en el caso.
  Se puede **pegar la URL de la conversación** y el motor extrae el número: es lo que el asesor
  tiene a mano en el navegador. Sin consola (agente, `-Json`, `-Quiet`) no se pregunta: corta con
  código `6`.
  *Esto revierte una decisión de la 2.9b, que lo había hecho opcional porque "para el análisis
  agregado no hace falta y el pcId cubre el seguimiento del equipo". Sigue siendo cierto para el
  agregado; lo que no cubre el pcId es leer la conversación.*
- **El motor actualiza la App Nativa del cliente con el instalador que ya está en la PC.** Alcanza
  con dejar el **`.msi`** de la Nativa al lado de `FudoPrintDoctor.cmd` (también lo busca en
  Descargas y en el Escritorio). Motivo: el 03/09 la telemetría mostró la Nativa `0.0.18` en **10
  de 24 corridas** y sólo 6 con la `0.0.37` firmada, y actualizarla es la solución de fondo —
  la firmada ya no la pone en cuarentena el antivirus.
  - **Un `.msi` no se encontraba**: la búsqueda de instaladores sólo miraba `*.exe`, así que el
    formato en que se distribuye la Nativa vigente era invisible para el motor.
  - **Un `.msi` tampoco se ejecuta directo**: ahora va por `msiexec /i ... /qn /norestart`, en
    silencio, para no dejar un asistente abierto en la PC del cliente.
  - **Nunca instala a ciegas.** Le lee la versión al `.msi` (`ProductVersion`) y sólo actualiza si
    es **más nueva** que la instalada. Si el instalador no declara su versión, no toca nada:
    instalar a ciegas puede **degradar** la Nativa, y eso ya pasó en este proyecto (una
    restauración de cuarentena dejó `0.0.36 → 0.0.18`, y la `0.0.18` después apareció circulando
    en varias PCs).
  - **Verifica después de instalar.** Si la versión no subió, no se declara actualizada.

### Cambiado
- **Códigos de salida nuevos**: `5` = el motor está desactualizado y no corrió; `6` = falta el ID
  de conversación y no corrió. *(Los de antes no cambian: `0` resuelto, `2` escalar, `3` falla del
  motor, `4` self-test fallido.)*

### Nota de distribución
**El launcher (`FudoPrintDoctor.cmd`) no se tocó, a propósito.** Los dos requisitos nuevos viven
enteros en el `.ps1`, que es lo único que reemplaza `Actualizar-FudoPrintDoctor.cmd`: el launcher
**no se pisa si ya existe**, justamente porque es donde vive la URL de telemetría de cada asesor.
Entonces:
- Con solo correr el updater, el ID obligatorio y el bloqueo por versión vieja aplican igual, con
  cualquier launcher.
- Un asesor con el launcher anterior verá su pregunta vieja (*"o Enter para omitir"*) y, si la
  omite, **el motor le pide el ID en pantalla** — la consola es interactiva, el mismo mecanismo con
  el que ya funciona la pregunta *"¿salió el ticket?"*.
- Se evaluó distribuir un launcher nuevo con la validación adelantada y los códigos `5`/`6`
  explicados, y **se descartó**: el `.cmd` del repositorio público tiene la URL de telemetría
  vacía, así que repartirlo tal cual dejaría a todo el equipo sin telemetría. No vale la pena por
  una mejora cosmética.
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
