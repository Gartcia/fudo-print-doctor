<#
.SYNOPSIS
    FudoPrintDoctor - Motor autonomo de diagnostico y remediacion de impresion de comandas (Windows + termica).

.DESCRIPTION
    Corre en la PC Windows del cliente (via la herramienta de acceso remoto del agente).
    Recorre la cadena de impresion de la comanda por capas, identifica la causa raiz de
    "no imprime la comanda" y auto-resuelve los casos seguros (spooler, cola trabada,
    impresora pausada/offline, puerto USB desmapeado, IP Ethernet cambiada) de forma
    idempotente y reversible. Los casos de configuracion propia de Fudo (area/cocina/sala,
    impresora no registrada) se detectan cuando es posible y se devuelven como
    'requires_fudo_config' para que la capa orquestadora (LLM + API Fudo o asesor) los resuelva.

    Salida: objeto estructurado (JSON) + resumen humano (es-AR) + bloque de telemetria.
    Disenado para ser invocado de forma no-interactiva por un agente.

.NOTES
    Compatible con Windows PowerShell 5.1+ y PowerShell 7+.
    Grounding: articulos del Help Center de Fudo (USB 11730817, Ethernet 11730816,
    areas/cocinas/salas 11730815, instalacion USB 16419361).

.PARAMETER PrinterName
    Nombre de la impresora tal como quedo instalada en Windows / configurada en Fudo.
    Si se omite, el motor intenta autodetectar la(s) candidata(s) termica(s)/POS.

.PARAMETER Interface
    auto | USB | Ethernet. Default: auto.

.PARAMETER PrinterIp
    IP de la impresora Ethernet (interfaz 'Directo Ethernet' de Fudo).

.PARAMETER Port
    Puerto TCP de la impresora de red. Default: 9100 (raw / ESC-POS).

.PARAMETER AutoFix
    Aplica remediaciones seguras. Default: $true. Usar -AutoFix:$false para solo-diagnostico.

.PARAMETER DryRun
    No modifica nada: registra que remediacion *aplicaria* cada paso.

.PARAMETER TestPrint
    Emite un ticket de prueba ESC/POS directo al hardware para aislar HW vs config. Default: $true.

.PARAMETER FudoAppProcess
    Patron de nombre del proceso/servicio de la App Nativa de Fudo (para chequear prerequisito).
    Default cubre variantes conocidas; ajustar segun el binario real.

.PARAMETER WaitReconnect
    Cuando la impresora esta desconectada, esperar a que alguien desenchufe y vuelva a enchufar
    el USB, detectar el puerto nuevo y seguir la reparacion sola. Si no se pasa: en consola
    interactiva se pregunta; en modo agente no se espera.

.PARAMETER ReconnectTimeoutSec
    Cuanto esperar la reconexion del USB. Default: 120 segundos.

.PARAMETER NativeInstallerUrl
    URL del instalador de la App Nativa de Fudo. Si se indica (o si se fija
    $script:NativeInstallerUrl en el script), el motor puede descargarla e instalarla cuando falta,
    agregando antes las exclusiones de antivirus. Sin URL solo guia los pasos manuales.

.PARAMETER NativeInstallerPath
    Ruta a un instalador de la App Nativa que ya esta en la PC (por ejemplo, copiado por el asesor
    junto al script). Se usa antes que -NativeInstallerUrl: no hace falta que el cliente descargue
    nada. Si no se indica, se busca un archivo tipo Fudo*.exe al lado del script.

.PARAMETER NativeInstallerArgs
    Argumentos para el instalador (por ejemplo /S o /SILENT segun el empaquetador).

.PARAMETER InstallNetworkPrinter
    Instalar la impresora de red indicada con -PrinterIp como cola de Windows con driver de texto
    generico. El nombre se toma de -NewPrinterName (default: FUDO-<ip>).

.PARAMETER NewPrinterName
    Nombre para la cola que se cree (red o USB).

.PARAMETER NoMenu
    No mostrar el menu de acciones al terminar. El menu solo aparece en consola interactiva.

.PARAMETER TelemetryUrl
    URL donde reportar el resultado. Tambien se puede dejar en la variable de entorno
    FUDO_TELEMETRY_URL o en un archivo 'telemetria.url' al lado del script (una linea con la URL).
    A proposito NO va hardcodeada en el codigo: el repositorio es publico.
    Si se indica, al terminar se envia por POST
    un resumen del resultado a esa URL. Silencioso: si falla, no molesta ni corta el run.
    Por defecto viaja un payload REDUCIDO (sin rutas, sin log): version, caso, cliente, host,
    causa raiz, categoria, confianza, duracion y el id+estado de cada chequeo.

.PARAMETER TelemetryFull
    Enviar el JSON completo en lugar del payload reducido.

.PARAMETER TestTelemetry
    Manda una fila de prueba al endpoint de telemetria y termina, informando si llego. Sirve para
    validar la configuracion sin correr el diagnostico.

.PARAMETER NoNativaKitCheck
    No chequea al arrancar si el instalador de la App Nativa firmada esta al lado del script.
    Ese chequeo no mira lo que tiene el cliente: mira si el asesor trajo el .msi, porque sin el
    el motor no puede actualizar una Nativa vieja y el antivirus vuelve a comersela. Es un
    opt-out explicito y viaja en la telemetria.
.PARAMETER NoUpdateCheck
    No consulta si hay una version mas nueva publicada.
    NOTA DE DISENO: el motor avisa cuando hay una version nueva, pero NUNCA se actualiza solo.
    Corre en la PC de un cliente y no esta firmado digitalmente: una actualizacion automatica
    propagaria cualquier bug (o cualquier cambio malicioso en el repo) a todos los locales sin que
    nadie lo revise. La actualizacion es una accion explicita: la opcion A del menu, o el
    Actualizar-FudoPrintDoctor.cmd del asesor. El chequeo ya se saltea solo en modo
    agente (-Quiet / -Json / salida redirigida) y nunca bloquea el diagnostico.

.PARAMETER Modo
    Que parte de la cadena revisar: USB | Red | Ambos. Default 'auto', que en consola
    interactiva le PREGUNTA al asesor al arrancar y en modo agente equivale a 'Ambos'.
    Nace de un caso real: un cliente con dos impresoras de red sanas recibia como diagnostico
    "ninguna impresora fisica conectada", porque el camino USB gana y en esa PC no hay USB.
      USB   - solo colas y hardware USB. Las impresoras de red se listan pero no se diagnostican.
      Red   - solo colas en puertos de red (IP_*, *9100*, WSD-*). No se reporta la falta de
              hardware USB como problema.
      Ambos - revisa las dos y reporta lo que encuentra en cada una (comportamiento historico).
    El modo elegido viaja en la telemetria (campo modo) y se muestra en el encabezado.

.PARAMETER CheckUpdate
    Solo consulta la version publicada, informa y termina. No diagnostica nada.

.PARAMETER AllowNetProbe
    Permite que el motor le agregue una IP secundaria TEMPORAL a la placa de red del PC para
    poder ver una impresora que esta en otra subred, y la saque al terminar. Es lo unico que
    toca la configuracion de red del cliente. Sin este parametro se le pregunta al asesor si
    hay consola, y en modo agente no se hace. Default: no.
.PARAMETER AllowQueuePurge
    Decide sin preguntar si se limpia la cola de impresion (unica accion irreversible).
    Si no se pasa: en consola interactiva se le pregunta al asesor; en modo no interactivo
    (agente, -Quiet, -Json, salida redirigida) NO se aplica y queda como accion pendiente.

.PARAMETER SkipIrreversible
    No aplica las remediaciones marcadas como irreversibles (hoy: limpiar la cola de impresion,
    que descarta los trabajos pendientes). Todo lo demas se sigue reparando.

.PARAMETER InstallGenericDriver
    Si hay una impresora conectada por USB pero sin cola en Windows, instala el driver inbox
    "Generic / Text Only" (en Windows en espanol: "Generico / Solo texto") y crea una cola
    temporal FUDO-TEST-<puerto> para poder hacer la prueba fisica. Default: $true.
    Solo actua si -AutoFix es $true y no hay -DryRun.

.PARAMETER KeepTestPrinter
    Por defecto la cola FUDO-TEST-* queda instalada (sirve para reprobar). Con
    -KeepTestPrinter:$false el motor la borra al final del run.

.PARAMETER CaseId
    OPCIONAL. Etiqueta de correlacion (id de conversacion de Intercom / tarea de ClickUp).
    NO cambia en nada el diagnostico: solo viaja en el JSON (campo caseId) y en el resumen,
    para poder cruzar despues telemetria vs caso. Si se omite, va vacio.

.PARAMETER ClientId
    Identificador del cliente/local para correlacionar telemetria.

.PARAMETER JsonOut
    Ruta de archivo donde volcar el resultado JSON (ademas de stdout).

.PARAMETER Quiet
    No escribe el resumen humano en stderr. stdout sigue teniendo el JSON delimitado.

.EXAMPLE
    .\FudoPrintDoctor.ps1 -CaseId "IC-12345" -ClientId "local-987"
    Autodiagnostico + auto-fix, salida JSON por stdout.

.EXAMPLE
    .\FudoPrintDoctor.ps1 -PrinterName "POS-58" -Interface USB -DryRun
    Solo diagnostico, sin aplicar cambios.

.EXAMPLE
    powershell -NoProfile -ExecutionPolicy Bypass -File .\FudoPrintDoctor.ps1 -Quiet -JsonOut .\fpd.json
    Invocacion recomendada para un agente: JSON limpio en stdout + copia en archivo.

.EXAMPLE
    .\FudoPrintDoctor.ps1 -SelfTest
    Corre los 38 asserts de la logica de decision (no toca la PC ni necesita impresora).

CONTRATO DE SALIDA (v1.1)
    stdout : SOLO el JSON, entre los delimitadores <<<FUDO_JSON_BEGIN>>> y <<<FUDO_JSON_END>>>.
    Orden de capas: 0 entorno > 0b Nativa/antivirus > 1a HARDWARE (device manager + puertos) >
                    1 cola de Windows (descarta virtuales, instala si falta) > 2 cola de trabajos >
                    3 puerto USB / red > 4 prueba fisica ESC/POS > 5 config de Fudo.
    stderr : resumen humano (es-AR), logs WARN/ERROR y avisos. Silenciable con -Quiet.
    exit   : 0 = resuelto | 2 = requiere escalamiento | 3 = falla del motor | 4 = self-test fallido
    Campos clave del JSON: status, diagnosis.rootCause, diagnosis.confidence,
    diagnosis.nextActions[] (que hacer / quien lo hace / articulo), engineErrors[], checks[], telemetry.

CHANGELOG
    3.1  - Campo 'llegada': clasifica en que estado nos encontramos la PC, cruzando tres evidencias
             independientes (colas instaladas y su estado, entradas historicas del registro USBPRINT
             y puertos huerfanos, e historial de impresion del spooler):
               nunca_hubo_impresora_en_esta_pc | primera_instalacion |
               estaba_instalada_y_dejo_de_funcionar | instalada_pero_nunca_imprimio |
               una_funciona_y_otra_no | todas_funcionan | hardware_conectado_sin_instalar
             Incluye usoPrevio (si_imprimio_comandas_de_fudo / imprimio_pero_no_comandas_de_fudo /
             no_hay_registro_de_impresion / desconocido cuando el log del spooler esta apagado) y
             el alcance ('esta_pc'): desde la PC no se puede afirmar nada del resto del local.
    3.0  - Telemetria analizable sin pedirle datos a nadie:
             * pcId: hash SHA256 truncado del MachineGuid de Windows. Estable y anonimo: agrupa las
               corridas de una misma PC sin identificar al comercio ni permitir volver al original.
             * corrida: numero de corrida en esa PC, status y causa de la corrida ANTERIOR, y la
               transicion (primera | se_resolvio | volvio_a_fallar | sigue_ok | sigue_fallando).
               Con esto una sola fila cuenta que se hizo y si funciono, sin cruzar tablas.
             * nativaHuella: sondeo de %LOCALAPPDATA%\Fudo que reporta SOLO nombres de archivo y
               NOMBRES de clave de los json (ningun valor), para averiguar si la App Nativa guarda
               algun identificador de comercio aprovechable. Si aparece algo util, se evalua aparte.
           - El CaseId sigue existiendo pero pasa a ser opcional: para el analisis agregado no hace
             falta, y el pcId cubre el seguimiento de un mismo equipo.
    2.9b - Opcion A del menu: actualizar el motor a la ultima version publicada. Aparece solo si
             hay una version nueva, valida lo descargado (tamano, firma y version legible) y deja
             una copia .bak antes de reemplazar. Sigue siendo explicita: el motor no se
             autoactualiza (ver NOTA DE DISENO en -NoUpdateCheck).
    2.9  - FIX del payload de telemetria: impresoras, cantidadColas, cantidadHardware e
             historialFudo viajaban en la raiz, pero el receptor los lee dentro de 'telemetry', asi
             que esas columnas quedaban vacias (los datos igual estaban en la columna json). Ahora
             van anidados: el Apps Script ya desplegado los toma sin cambios.
           - El launcher pregunta el ID del caso (Enter para omitir) y lo pasa como -CaseId, para
             poder cruzar cada corrida con su conversacion.
    2.8  - La URL de telemetria, una vez conocida, queda guardada en la variable de entorno de
             USUARIO de esa PC (y se lee de ahi en las corridas siguientes). Asi deja de depender
             de un archivo que una actualizacion pueda reemplazar: alcanza con que UNA corrida la
             haya recibido. Queda registrado en actionsApplied y se borra con
             setx FUDO_TELEMETRY_URL "".
    2.7  - El error de telemetria se traduce a una instruccion concreta. Un 403 con HTML de Google
             significa que el Apps Script no esta publicado con acceso abierto, y ahora el mensaje
             dice exactamente que cambiar (Implementar > Administrar implementaciones >
             'Quien tiene acceso' = Cualquier persona).
    2.6  - La URL de telemetria puede viajar en el propio launcher (set FUDO_TELEMETRY_URL en el
             .cmd interno), asi no hay un archivo extra que el asesor pueda olvidarse de copiar:
             el .cmd es el archivo que si o si tiene que estar. El repo publico lo trae vacio.
           - Se busca el archivo de configuracion tambien en las carpetas redirigidas por OneDrive
             (Escritorio / Desktop), que es donde estaba el caso real.
           - El updater ya no sobrescribe el launcher si existe: ahi vive la configuracion local.
           - -TestTelemetry, cuando no encuentra la URL, lista todas las rutas donde busco.
    2.5  - FIX de observabilidad: el JSON se serializaba y se guardaba ANTES de enviar la
             telemetria, asi que el archivo siempre salia con telemetria=null y sin las lineas de
             log del envio: era imposible saber por que no llegaba. Ahora el envio ocurre primero y
             su resultado (y el log) quedan dentro del JSON.
           - El campo telemetria incluye 'dondeBusco': la lista de rutas donde se busco el archivo
             de configuracion, con el motivo por el que cada una no sirvio.
    2.4  - FIX (falso positivo, el mismo patron de siempre en el ultimo camino que faltaba): la
             reasignacion de puerto USB reportaba 'puerto reasignado (test HW OK)' con la impresora
             desenchufada, porque WritePrinter devuelve exito cuando el spooler acepta el trabajo.
             Ahora verifica que el ticket haya SALIDO de la cola, y si no hay ningun dispositivo
             conectado no prueba puertos: informa que primero hay que conectar la impresora.
           - Telemetria: el archivo de configuracion pasa a llamarse telemetria.txt (en Windows la
             extension .url esta reservada para accesos directos de Internet, y por eso el archivo
             no se leia); se busca tambien en Descargas y Escritorio, y se acepta .url por
             compatibilidad. Y ya no falla en silencio: si no esta configurada, queda en el log,
             en el resumen y en el JSON.
           - Entorno: campo paisProbable derivado de la zona horaria, porque el pais por cultura
             devuelve US cuando Windows esta en ingles.
    2.3  - FIX de telemetria: /exec de Apps Script responde 302 y, al seguir el redirect, el POST
             se convierte en GET y se pierde el cuerpo (la fila nunca llegaba). Ahora, si el primer
             intento no devuelve ok, se repite el POST contra el Location.
           - El resultado del envio se ve: linea en el resumen y campo 'telemetria' en el JSON.
             Antes un fallo quedaba solo en el log y nadie se enteraba.
           - Nuevo -TestTelemetry: manda una fila de prueba y dice si llego, sin diagnosticar nada.
    2.2  - La URL de telemetria ya no vive en el codigo: se toma de -TelemetryUrl, de la variable
             de entorno FUDO_TELEMETRY_URL o de un archivo 'telemetria.url' al lado del script.
             El repositorio es publico y una URL de escritura publicada se puede spamear.
    2.1  - Nuevo: se identifica A QUE COLA le manda Fudo, leyendo el log del spooler
             (Microsoft-Windows-PrintService/Operational, evento 307) y reconociendo los trabajos
             de la App Nativa ('node print job'). Si el log esta deshabilitado (viene asi de
             fabrica) se habilita para la proxima corrida. No reemplaza a la API de Fudo: dice a
             donde llegan los trabajos, no que cocina/area tiene asignada cada impresora.
           - Contexto de la PC en el JSON y en la telemetria: SO con build y arquitectura,
             PowerShell, Chrome, Edge, version de la Nativa, pais, cultura, zona horaria, conexion
             de la PC (cable o wifi) y cantidad de colas e impresoras fisicas.
           - App Nativa desde un instalador que ya esta en la PC (-NativeInstallerPath, o
             autodeteccion de Fudo*.exe al lado del script / Descargas / Escritorio), asi el
             cliente no tiene que descargar nada. -NativeInstallerArgs para instalacion silenciosa.
           - FIX: Join-Path con base $null explotaba en Windows de 32 bits al buscar Chrome, Edge
             o el instalador de la Nativa.
           - Los textos de impresoras de red distinguen los dos caminos de Fudo (Directo Ethernet,
             que no usa colas de Windows, vs impresora del sistema operativo) y ya no sugieren que
             una cola de Windows implique que Fudo la tenga configurada.
    2.0  - El JSON ya no se imprime en pantalla salvo que se pida con -Json: la deteccion de
             redireccion no es confiable en Windows PowerShell dentro de un .cmd y el asesor
             terminaba viendo el JSON entero. El resumen humano quedo al final de la salida.
           - Menu de acciones al terminar (solo consola interactiva): volver a revisar, esperar la
             reconexion del USB, instalar la impresora conectada, limpiar la cola, buscar impresoras
             por IP, instalar una de red, instalar la Nativa, imprimir un ticket, ver el detalle o
             guardar el JSON. Ya no hay que cerrar y reabrir la app para reintentar. -NoMenu lo saltea.
           - Ethernet: barrido de la subred con identificacion real (DLE EOT: una termica responde),
             reporte de cuantas y cuales, deteccion de las que ya tienen cola en Windows, e
             instalacion por IP con driver de texto generico (-InstallNetworkPrinter / menu).
           - Telemetria opcional: -TelemetryUrl (o $script:TelemetryUrl) envia por POST un resumen
             del resultado para no depender de que el asesor guarde el JSON. -TelemetryFull manda todo.
           - App Nativa: -NativeInstallerUrl permite descargarla e instalarla agregando primero las
             exclusiones de antivirus. Sin URL, guia los pasos manuales.
    1.9  - Multi-impresora: se revisan TODAS las colas reales de Windows (puerto, offline, pausada,
             trabajos en cola, si el puerto tiene hardware) y se diagnostica la que esta fallando,
             no la primera que aparece. Antes, en un local con caja y cocina podia elegir la que
             funcionaba y devolver 'todo ok' con la otra tapada con miles de trabajos.
             Las colas sanas se listan como 'funcionando -- no se toca'.
           - Flujo de reconexion guiada: cuando la cola apunta a un puerto muerto, el motor espera
             a que se desenchufe y se vuelva a enchufar el USB, detecta el puerto nuevo, apunta la
             cola ahi, prueba un ticket y, si la cola esta rota, la recrea con el MISMO nombre
             (Fudo encuentra la impresora por nombre). Es la secuencia que resuelve el caso real.
           - Repair-QueueRecreate: reemplazo seguro de una cola rota. Primero crea una cola
             temporal y comprueba que imprima; solo entonces borra la vieja y renombra la nueva.
             Nunca deja al cliente sin cola.
           - Resumen reorganizado: primero las impresoras instaladas en Windows con su estado y
             sintomas, despues el hardware conectado. Menos ruido, sin contradicciones entre
             'conectada' y 'desconectada' (se deduplica por puerto y por nombre del equipo).
           - Mensaje especifico cuando hay decenas de trabajos acumulados: las comandas llegan
             desde Fudo, el problema esta en la impresora o su cola.
    1.8  - Distribucion: chequeo de version publicada (-CheckUpdate / aviso en el resumen).
    1.7  - FIX: una impresora DESENCHUFADA seguia figurando como conectada. El registro
             Enum\USBPRINT es historico (guarda toda impresora que estuvo conectada alguna vez),
             asi que ahora se cruza contra los dispositivos realmente presentes
             (Win32_PnPEntity / Get-PnpDevice -PresentOnly). Si no se puede verificar la
             presencia, no se afirma que este desconectada.
           - Nuevos checks: hw.disconnected ('instalada pero DESCONECTADA, estaba en USB00x') y
             printer.disconnected (la cola apunta a un puerto sin dispositivo). En ese caso ya no
             se 'repara' el offline de una impresora desenchufada, que es lo que enmascaraba el
             problema real.
           - La prueba fisica no corre sobre un puerto sin hardware, y cuando corre verifica que
             el ticket haya SALIDO de la cola: WritePrinter OK solo significa que el spooler lo
             acepto, no que el papel salio.
           - Categoria nueva hardware.desconectada.
    1.6  - Progreso en vivo en la consola: una linea por etapa con [n/9], resultado, color y
             cuanto tardo, y detalle de lo que esta haciendo mientras corre (buscando la Nativa,
             consultando el antivirus, escaneando la subred, enviando el ticket...).
             Solo cuando hay un humano mirando: en modo agente no cambia nada.
    1.5  - Un solo punto de entrada: FudoPrintDoctor.cmd (doble clic). Los 4 launchers anteriores
             confundian mas de lo que ayudaban.
           - La decision sobre la unica accion irreversible (limpiar la cola) ya no vive en el
             launcher sino en el script: si hay un humano en la consola se le pregunta; si corre
             un agente no se aplica y queda como accion pendiente en el JSON con el comando exacto.
             Se puede forzar con -AllowQueuePurge $true/$false.
           - FIX: $PSBoundParameters dentro de una funcion no es el del script, asi que
             -KeepTestPrinter:$false nunca borraba la cola de prueba.
    1.4  - FIX importante de deteccion: se tomaba cualquier dispositivo USB por impresora.
             El token 'POS' de la lista de marcas matcheaba 'USB Com-POS-ite Device' y 'Generic'
             matcheaba 'Generic USB Hub'. Ahora hay un clasificador explicito
             (Test-IsPrinterDevice) con senales ordenadas por certeza:
               alta  = interfaz USBPRINT | clase de dispositivo Printer | driver usbprint |
                       CompatibleID USB\Class_07 (clase USB 07h = Printer, del estandar USB)
               media = VID de fabricante de impresoras (Epson, Bixolon, Star, Citizen, Zebra...)
               baja  = el nombre menciona impresora/POS/comandera
             Mouse, teclados, hubs, composites, audio, camaras y almacenamiento se descartan y
             quedan auditables en hardware.usbDevicesRejected con el motivo.
           - El listado muestra como se detecto cada impresora cuando la certeza no es alta.
           - Nuevo -SkipIrreversible: repara todo menos lo que no se puede deshacer
             (hoy, la purga de la cola de impresion).
    1.3  - Consola legible: resumen compacto (impresoras detectadas + semaforo por area +
             causa + hasta 3 acciones), con color cuando la consola es interactiva.
             El detalle completo queda en el JSON; -Verbose lista todos los chequeos.
           - Si la salida NO esta redirigida, el JSON ya no se vuelca a pantalla: se guarda
             en %TEMP%\FudoPrintDoctor-<fecha>.json y se informa la ruta. Con -Json (o
             redirigiendo stdout) vuelve el JSON delimitado para el agente.
           - Cuenta y lista las impresoras fisicas conectadas, con marca/modelo cuando se puede
             identificar (nombre + InstanceId + tabla de VID USB) y su puerto.
           - Nuevo check hw.driverPlan: por cada impresora decide si corresponde el driver del
             fabricante (Epson, Bixolon, Star, Citizen, Zebra, Custom, Sam4s, Sewoo, Posiflex, Hasar)
             o el inbox 'Generic / Text Only'. Si el driver OEM ya esta instalado, lo usa para la
             cola de prueba en vez del generico.
           - Owners simplificados en nextActions: cliente / asesor / soporte.
    1.2  - Capa 1a nueva: inventario de HARDWARE primero (Administrador de dispositivos).
             Enumera impresoras fisicas via registro USBPRINT (unico lugar con el mapeo
             device -> USB00x), Get-PnpDevice y Win32_PnPEntity como fallback.
             Si Windows no ve ningun device: causa raiz 'hardware.no_conectada' (cable/puerto/energia),
             y distingue puertos USB00x huerfanos (restos de instalaciones viejas) de puertos con device vivo.
           - Descarta SIEMPRE las impresoras virtuales de Windows (Print to PDF, XPS, OneNote, Fax,
             Adobe PDF, PDF24, CutePDF, etc.) por nombre, driver y puerto: nunca son objetivo,
             y la prueba fisica se saltea sobre ellas (antes daban un falso "el hardware imprime OK").
           - Si hay device conectado sin cola: instala el driver inbox generico de texto y crea
             una cola FUDO-TEST-<puerto> para aislar hardware vs configuracion de Fudo.
           - Detecta dispositivos presentes sin driver (codigo 28 del Administrador de dispositivos).
           - Capa 3 USB: ahora compara el puerto de la cola contra el puerto donde realmente esta
             enumerado el device (caso clasico del art. 11730817) y prueba primero los puertos vivos.
           - Nuevo bloque 'hardware' en el JSON + categorias hardware.no_conectada / os.driver_faltante /
             os.impresora_virtual.
    1.1  - FIX: Set-StrictMode 2.0 + '.Count' sobre $null/escalar tiraba
             PropertyNotFoundStrict y mataba el run entero antes de emitir nada
             (se disparaba en cualquier PC sin impresora POS detectada). Ahora StrictMode 1.0
             y todos los .Count blindados con @().
           - Cada capa corre aislada (Invoke-Step): si una explota, se registra en
             engineErrors[] y el diagnostico sigue.
           - try/catch global: toda falla sale igual como JSON con hint accionable.
           - Nuevo diagnosis.nextActions[] priorizado con owner (asesor / cliente / tecnico / soporte).
           - Preflight de parametros con mensajes en castellano.
           - stdout reservado al JSON delimitado; humano y logs a stderr. Exit codes.
    1.0  - Version inicial.
#>

[CmdletBinding()]
param(
    [string]$PrinterName,
    [ValidateSet('auto','USB','Red','Ambos')]
    [string]$Modo = 'auto',
    [ValidateSet('auto','USB','Ethernet')]
    [string]$Interface = 'auto',
    [string]$PrinterIp,
    [int]$Port = 9100,
    [bool]$AutoFix = $true,
    [switch]$DryRun,
    [bool]$TestPrint = $true,
    [string]$FudoAppProcess = 'Fudo',
    [string]$FudoNativePath = '',
    [bool]$UseDefenderExclusions = $true,
    [string]$CaseId = '',
    [string]$ClientId = '',
    [bool]$InstallGenericDriver = $true,
    [switch]$SkipIrreversible,
    [bool]$AllowQueuePurge,
    [bool]$AllowNetProbe,
    [switch]$KeepTestPrinter,
    [string]$JsonOut,
    [switch]$Quiet,
    [switch]$Json,
    [bool]$WaitReconnect,
    [int]$ReconnectTimeoutSec = 120,
    [string]$NativeInstallerUrl = '',
    [string]$NativeInstallerPath = '',
    [string]$NativeInstallerArgs = '',
    [switch]$InstallNetworkPrinter,
    [string]$NewPrinterName = '',
    [switch]$NoMenu,
    [string]$TelemetryUrl = '',
    [switch]$TelemetryFull,
    [switch]$NoUpdateCheck,
    [switch]$NoNativaKitCheck,
    [switch]$CheckUpdate,
    [switch]$TestTelemetry,
    [switch]$SelfTest
)

# Que parametros paso el invocador de verdad (dentro de una funcion $PSBoundParameters es
# el de la funcion, no el del script: hay que capturarlo aca).
$script:BoundParams = $PSBoundParameters

$ErrorActionPreference = 'Stop'
# IMPORTANTE: -Version 2.0 hace que acceder a .Count sobre $null o sobre un escalar
# tire PropertyNotFoundStrict ("No se encuentra la propiedad 'Count' en este objeto").
# Con 1.0 seguimos detectando variables no inicializadas sin ese falso positivo.
Set-StrictMode -Version 1.0

# ---------------------------------------------------------------------------
# Estado global del run
# ---------------------------------------------------------------------------
$script:Checks       = New-Object System.Collections.ArrayList
$script:Actions      = New-Object System.Collections.ArrayList   # remediaciones aplicadas (para rollback / auditoria)
$script:Log          = New-Object System.Collections.ArrayList
$script:StartTime    = Get-Date
$script:Diagnostics  = [ordered]@{}   # datos crudos recolectados
$script:Errors       = New-Object System.Collections.ArrayList   # fallas internas del motor
$script:TestPrintersCreated = New-Object System.Collections.ArrayList   # colas temporales creadas por el motor
# Las colas que crea el motor no son del cliente: no pueden contarse como evidencia.
$script:TestPrinterRx = '(?i)^FUDO-TEST-'
# Colas creadas por el motor: las FUDO-TEST-* (siempre descartables) y la FUDO-USB00x que crea
# hw.noPortBound cuando el cliente no tenia ninguna. Esa ultima SI es un entregable mientras el
# puerto tenga hardware; si el hardware se va, deja de serlo (ver Remove-OrphanOwnQueues).
$script:OwnQueueRx   = '(?i)^FUDO-(TEST-|USB\d)'
$script:TestDocRx    = '(?i)fudo print doctor'
$script:SchemaVersion = '3.20'
# Que se revisa en esta corrida: USB | Red | Ambos. Lo resuelve Resolve-RunMode al arrancar
# (pregunta al asesor si hay consola; en modo agente queda en 'Ambos').
$script:RunMode = 'Ambos'
# Hay una linea de progreso abierta (escrita con `r, sin salto)? Ver Suspend-LiveStatus.
$script:LiveOpen = $false
# Se corto el diagnostico porque no habia impresoras del tipo elegido y no se pidio revisar
# las otras. Ver Confirm-ReviewOtherInterface.
$script:AbortByMode = $false
# Primera version de la App Nativa firmada digitalmente. Desde aca, el antivirus deja de
# bloquearla, asi que las exclusiones preventivas de Defender ya no tienen sentido: si la
# Nativa esta por debajo de esta version, la accion de fondo es ACTUALIZARLA, no excluirla.
$script:NativaVersionFirmada = '0.0.37'
# Id de la extension de Fudo en la Chrome Web Store. Es publico (esta en la URL de la tienda) y
# ademas viaja dentro del manifest de native messaging que la Nativa deja en %LOCALAPPDATA%\Fudo.
$script:FudoExtensionId  = 'npcjljaedonmjndbliillcmkhidejhmb'
$script:FudoExtensionUrl = 'https://chromewebstore.google.com/detail/fudo/npcjljaedonmjndbliillcmkhidejhmb'
# Nombre del host de native messaging: es la clave que busca el navegador para encontrar la Nativa.
$script:FudoNativeHostName = 'do.fu.native_extension'
$script:MenuVacios = 0
# Distribucion: repo publico. VERSION es un archivo de una linea con la version publicada.
$script:RepoUrl    = 'https://github.com/Gartcia/fudo-print-doctor'
$script:RawBase    = 'https://raw.githubusercontent.com/Gartcia/fudo-print-doctor/main'
$script:UpdateNote = ''   # mensaje de "hay version nueva", si corresponde
$script:VersionBloqueada   = $false  # se corto la corrida por motor desactualizado
$script:VersionCheckFallo  = $false  # no se pudo consultar la version publicada (sin internet)
$script:VersionCheckOmitido = $false # se corrio con -NoUpdateCheck
$script:NativaKitOmitido    = $false # se corrio con -NoNativaKitCheck
$script:NativaKit           = $null  # resultado del chequeo del .msi de la Nativa firmada
$script:VersionPublicada   = ''      # la que contesto el repo, si contesto
$script:JsonBegin    = '<<<FUDO_JSON_BEGIN>>>'
$script:JsonEnd      = '<<<FUDO_JSON_END>>>'
$script:AutoJsonPath = ''
# Telemetria: la URL NO va hardcodeada aca. El repo es publico, y una URL de escritura
# en un repo publico se puede spamear. Se resuelve por fuera del repo, en este orden:
#   1) -TelemetryUrl <url>
#   2) variable de entorno FUDO_TELEMETRY_URL
#   3) archivo 'telemetria.url' al lado del script (una linea con la URL)
$script:TelemetryUrl = ''
# URL del instalador de la App Nativa (completar cuando este definida).
$script:NativeInstallerUrl = ''
$script:ForceWaitReconnect = $false
$script:LastResult = $null
$script:TelemetryStatus = $null
$script:TelemetryLookup = @()
# Progreso en vivo: titulo humano de cada etapa. Las etapas sin titulo no se muestran.
$script:StepPlan = [ordered]@{
    'layer0.environment'        = 'Entorno de Windows'
    'layer0b.nativeApp'         = 'App Nativa de Fudo y antivirus'
    'layer1a.hardwareInventory' = 'Impresoras conectadas'
    'layer1.resolvePrinter'     = 'Impresora en Windows'
    'layer1.printerState'       = 'Estado de la impresora'
    'layer2.queue'              = 'Cola de trabajos'
    'layer3.usbPort'            = 'Puerto USB'
    'layer3.network'            = 'Conexion de red'
    'layer4.hardwarePrint'      = 'Prueba de impresion'
    'layer5.fudoConfig'         = 'Configuracion de Fudo'
    'final.rescan'              = 'Estado final de las impresoras'
    'final.otherQueues'         = 'Comandas encoladas'
}
$script:StepTotal   = 11     # usb y red son excluyentes
$script:StepIndex   = 0
$script:StepLabel   = ''
$script:StepNote    = ''
$script:LiveWidth   = 76
$script:ReconnectedPort = ''   # puerto donde reaparecio la impresora tras reconectar el USB
$script:PresentIds   = $null   # cache de InstanceIds de dispositivos PRESENTES
$script:PresentIdsOk = $false  # pudimos determinar la presencia?

# Marcas reales de termicas/POS mas frecuentes en comercios (art. 16419361).
# OJO: aca NO van tokens genericos como 'POS', 'Generic' o 'Thermal': matchean
# 'USB Composite Device' y 'Generic USB Hub'. Esas palabras viven en $script:PrinterWordRx.
$script:PosBrands = @('Bixolon','Epson','Citizen','Hasar','Sam4s','3nStar','XPrinter','Rongta','Gprinter',
    'Nictom','Kretz','OCOM','Barpos','Solpos','Jaltech','Sprt','Sewoo','TM-T','TM20','RPT008','SerForce',
    'Ser force','Star Micronics','Zebra','Custom','Posiflex')

function Write-DoctorLog {
    param([string]$Level, [string]$Message)
    $entry = [ordered]@{
        ts      = (Get-Date).ToString('o')
        level   = $Level
        message = $Message
    }
    [void]$script:Log.Add($entry)
    # A stderr: stdout queda reservado exclusivamente para el JSON (contrato con el agente).
    if ($VerbosePreference -eq 'Continue' -or $Level -in @('WARN','ERROR')) {
        # Un WARN/ERROR puede caer en cualquier momento, incluso en medio de una etapa: si la
        # linea de progreso esta abierta, hay que cerrarla o los dos textos se pisan.
        Suspend-LiveStatus
        [Console]::Error.WriteLine(("[{0}] {1}" -f $Level, $Message))
    }
}

function Add-Check {
    <#
      status: ok | warn | fail | fixed | skipped
      Registra un nodo del arbol de diagnostico con su evidencia y accion.
    #>
    param(
        [string]$Id,
        [int]$Layer,
        [string]$Name,
        [ValidateSet('ok','warn','fail','fixed','skipped')]
        [string]$Status,
        [bool]$RootCauseCandidate = $false,
        $Evidence = $null,
        [string]$ActionTaken = '',
        [bool]$Reversible = $true,
        [string]$Plane = 'os',           # os | fudo_config | hardware
        [string]$ArticleRef = '',
        [string]$Recommendation = ''
    )
    $check = [ordered]@{
        id                 = $Id
        # Orden de registro. Sort-Object no es estable, asi que sin este desempate dos checks
        # de la misma capa competian por ser la causa raiz en un orden arbitrario: el resumen
        # llegaba a mostrar la reparacion intentada en vez del hallazgo que la motivo.
        seq                = @($script:Checks).Count
        layer              = $Layer
        name               = $Name
        status             = $Status
        plane              = $Plane
        rootCauseCandidate = $RootCauseCandidate
        evidence           = $Evidence
        actionTaken        = $ActionTaken
        reversible         = $Reversible
        articleRef         = $ArticleRef
        recommendation     = $Recommendation
    }
    [void]$script:Checks.Add($check)
    Write-DoctorLog -Level 'INFO' -Message ("[L{0}] {1} => {2}{3}" -f $Layer, $Name, $Status, $(if($ActionTaken){" | $ActionTaken"}else{""}))
    # NO emitir al pipeline: los checks se acumulan en $script:Checks.
}

function Add-Action {
    param([string]$Type, [string]$Target, [string]$Before, [string]$After, [bool]$Reversible = $true)
    $a = [ordered]@{
        type       = $Type
        target     = $Target
        before     = $Before
        after      = $After
        reversible = $Reversible
        ts         = (Get-Date).ToString('o')
    }
    [void]$script:Actions.Add($a)
}

function Write-LiveStatus {
    <# Reescribe la linea actual de progreso (solo si hay un humano mirando). #>
    param([string]$Text)
    if (-not (Test-IsInteractiveConsole)) { return }
    $line = '  ' + $Text
    if ($line.Length -gt $script:LiveWidth) { $line = $line.Substring(0, $script:LiveWidth - 1) + '.' }
    Write-Host ("`r" + $line + (' ' * [Math]::Max(0, $script:LiveWidth - $line.Length))) -NoNewline
    $script:LiveOpen = $true
}

function Complete-LiveStatus {
    <# Cierra la linea de progreso de la etapa con su resultado y color. #>
    param([string]$Text, [string]$Color = 'Gray')
    if (-not (Test-IsInteractiveConsole)) { return }
    $line = '  ' + $Text
    Write-Host ("`r" + $line + (' ' * [Math]::Max(0, $script:LiveWidth - $line.Length))) -ForegroundColor $Color
    $script:LiveOpen = $false
}

function Suspend-LiveStatus {
    <#
      Cierra la linea de progreso en curso ANTES de escribir cualquier otra cosa en pantalla.
      La linea de progreso se dibuja con `r y sin salto de linea: si algo escribe encima sin
      cerrarla (un prompt al asesor, un WARN del log, el banner de una accion irreversible),
      los dos textos se pisan y el asesor ve un renglon mezclado. Con esto, lo que venga
      despues arranca en una linea limpia.
    #>
    if (-not $script:LiveOpen) { return }
    $script:LiveOpen = $false
    if (-not (Test-IsInteractiveConsole)) { return }
    # Borra los restos de la linea viva y baja el cursor.
    Write-Host ("`r" + (' ' * $script:LiveWidth) + "`r") -NoNewline
}

function Write-StepDetail {
    <# Detalle de lo que se esta haciendo AHORA dentro de la etapa en curso. #>
    param([string]$Text)
    if (-not $script:StepLabel) { return }
    Write-LiveStatus ("$($script:StepLabel) - $Text")
}

function Set-StepNote {
    <# Dato corto que se muestra al cerrar la etapa (ej: '2 impresoras'). #>
    param([string]$Text)
    $script:StepNote = $Text
}

function Add-EngineError {
    param([string]$Step, [string]$Message, [string]$Type = '', [string]$At = '', [string]$Hint = '')
    $e = [ordered]@{
        step    = $Step
        message = $Message
        type    = $Type
        at      = $At
        hint    = $Hint
        ts      = (Get-Date).ToString('o')
    }
    [void]$script:Errors.Add($e)
    Write-DoctorLog -Level 'ERROR' -Message ("[{0}] {1}" -f $Step, $Message)
}

function Update-CheckFinding {
    <#
      Corrige un chequeo YA registrado porque una reparacion posterior lo dejo sin efecto.
      Sin esto el veredicto se decide con una foto vieja de la PC: es el bug que la v3.11
      corrigio para el inventario de colas y que reaparecio con la Nativa -restaurada de la
      cuarentena en la capa 0b.2, pero seguia contada como ausente por el chequeo de la capa
      0b.1, asi que el caso escalaba igual y el asesor tenia que correr el diagnostico otra vez-.
      Devuelve $true si encontro el chequeo y lo actualizo.
    #>
    param(
        [string]$Id,
        [ValidateSet('ok','warn','fail','fixed','skipped')]
        [string]$Status,
        [string]$Name = '',
        $RootCauseCandidate = $null,
        [string]$ActionTaken = '',
        [string]$Recommendation = '',
        $EvidenceExtra = $null
    )
    $c = @($script:Checks | Where-Object { $_.id -eq $Id }) | Select-Object -First 1
    if (-not $c) { return $false }
    $antes = [string]$c.status
    $c.status = $Status
    if ($Name) { $c.name = $Name }
    if ($null -ne $RootCauseCandidate) { $c.rootCauseCandidate = [bool]$RootCauseCandidate }
    if ($ActionTaken) { $c.actionTaken = $ActionTaken }
    if ($Recommendation) { $c.recommendation = $Recommendation }
    if ($null -ne $EvidenceExtra) {
        # Por que cambio queda con el chequeo: sin eso en la planilla se ve un 'fixed' sin
        # explicacion y no hay forma de auditar la correccion.
        try {
            if ($null -eq $c.evidence) { $c.evidence = @{} }
            foreach ($k in @($EvidenceExtra.Keys)) { $c.evidence[$k] = $EvidenceExtra[$k] }
        } catch {}
    }
    Write-DoctorLog -Level 'INFO' -Message ("[correccion] {0}: {1} -> {2}" -f $Id, $antes, $Status)
    return $true
}

function Get-ErrorHint {
    <#
      Traduce excepciones crudas de PowerShell a una accion concreta para el agente
      que esta corriendo el script. Si no hay match, devuelve ''.
    #>
    param($ErrorRecord)
    $probe = ''
    try { $probe = "{0} {1}" -f [string]$ErrorRecord.FullyQualifiedErrorId, [string]$ErrorRecord.Exception.Message } catch {}
    switch -Regex ($probe) {
        'PropertyNotFoundStrict|no se encuentra la propiedad|cannot be found on this object' {
            return "BUG DEL MOTOR (no es la PC del cliente): se accedio a una propiedad inexistente, tipicamente .Count sobre `$null. Reportar este JSON a Soporte Producto; no hace falta pedirle nada mas al cliente." }
        'CommandNotFoundException|no se reconoce como|is not recognized as' {
            return "Falta un cmdlet en esta PC (modulos PrintManagement / NetTCPIP o PowerShell muy viejo). Verificar con: `$PSVersionTable.PSVersion y Get-Module -ListAvailable PrintManagement. Requiere Windows PowerShell 5.1+." }
        'UnauthorizedAccessException|Acceso denegado|Access is denied|PermissionDenied' {
            return "Faltan permisos. Cerrar y abrir PowerShell como Administrador (clic derecho > Ejecutar como administrador) y reintentar el mismo comando." }
        'no se puede cargar el archivo|cannot be loaded because running scripts|ExecutionPolicy|UnauthorizedAccess.*\.ps1' {
            return "La ExecutionPolicy bloquea el script. Correr: powershell -NoProfile -ExecutionPolicy Bypass -File .\FudoPrintDoctor.ps1" }
        'Get-MpComputerStatus|Get-MpThreatDetection|Defender' {
            return "Windows Defender no responde (suele pasar si hay antivirus de terceros como Avast). El diagnostico sigue, pero los chequeos de cuarentena de la Nativa quedan sin verificar: revisarlos a mano en el AV instalado." }
        'Get-Printer|Get-PrintJob|PrintManagement' {
            return "El subsistema de impresion no responde. Verificar el servicio 'Cola de impresion' (Spooler) en services.msc y reintentar." }
        'Add-Type|CSharp|compil' {
            return "No se pudo compilar el helper de impresion RAW (.NET/Add-Type bloqueado, tipico con politicas de AppLocker o AV). Correr con -TestPrint:`$false para saltear la prueba fisica." }
        'TimeoutException|timeout|tiempo de espera' {
            return "Timeout de red hacia la impresora. Confirmar IP con el self-test de la impresora (apagar, mantener FEED y encender) y revisar cable/switch." }
        default { return '' }
    }
}

function Invoke-Step {
    <#
      Corre una etapa del diagnostico aislada: si explota, NO mata el run.
      Registra el detalle en $script:Errors + un check 'skipped' y devuelve $null.
    #>
    param([string]$Name, [scriptblock]$Body)

    $title = ''
    if ($script:StepPlan.Contains($Name)) { $title = [string]$script:StepPlan[$Name] }
    $checksBefore = @($script:Checks).Count
    $t0 = Get-Date
    if ($title) {
        $script:StepIndex++
        $script:StepNote  = ''
        $script:StepLabel = ("[{0}/{1}] {2}" -f $script:StepIndex, $script:StepTotal, $title)
        Write-LiveStatus ($script:StepLabel + '...')
    }

    try {
        $result = (& $Body)
        if ($title) {
            $nuevos = @()
            if (@($script:Checks).Count -gt $checksBefore) { $nuevos = @($script:Checks)[$checksBefore..(@($script:Checks).Count - 1)] }
            $estado = 'sin datos'; $color = 'DarkGray'
            if     (@($nuevos | Where-Object { $_.status -eq 'fail'  }).Count -gt 0) { $estado = 'FALLA';    $color = 'Red' }
            elseif (@($nuevos | Where-Object { $_.status -eq 'warn'  }).Count -gt 0) { $estado = 'revisar';  $color = 'Yellow' }
            elseif (@($nuevos | Where-Object { $_.status -eq 'fixed' }).Count -gt 0) { $estado = 'reparado'; $color = 'Green' }
            elseif (@($nuevos | Where-Object { $_.status -eq 'ok'    }).Count -gt 0) { $estado = 'ok';       $color = 'Green' }
            elseif (@($nuevos | Where-Object { $_.status -eq 'skipped'}).Count -gt 0){ $estado = 'omitido';  $color = 'DarkGray' }
            $ms = [int]((Get-Date) - $t0).TotalMilliseconds
            $dots = '.' * [Math]::Max(3, 44 - $script:StepLabel.Length)
            $extra = $(if ($script:StepNote) { " ($($script:StepNote))" } else { '' })
            Complete-LiveStatus ("$($script:StepLabel) $dots $estado$extra  ${ms}ms") $color
            $script:StepLabel = ''
        }
        return $result
    } catch {
        $hint = Get-ErrorHint -ErrorRecord $_
        $at = ''
        try { $at = "linea {0}: {1}" -f $_.InvocationInfo.ScriptLineNumber, ([string]$_.InvocationInfo.Line).Trim() } catch {}
        $type = ''
        try { $type = $_.Exception.GetType().FullName } catch {}
        Add-EngineError -Step $Name -Message ([string]$_.Exception.Message) -Type $type -At $at -Hint $hint
        Add-Check -Id ("engine." + $Name) -Layer 9 -Name ("Etapa '" + $Name + "' fallo internamente") -Status 'skipped' `
            -Evidence @{ error = [string]$_.Exception.Message; at = $at } `
            -Recommendation $(if ($hint) { $hint } else { 'Etapa omitida por una falla interna; el resto del diagnostico continuo. Adjuntar el JSON al escalamiento.' })
        if ($title) {
            $dots = '.' * [Math]::Max(3, 44 - $script:StepLabel.Length)
            Complete-LiveStatus ("$($script:StepLabel) $dots error interno") 'Red'
            $script:StepLabel = ''
        }
        return $null
    }
}

function Initialize-ConsoleInputHelper {
    <#
      Lee del dispositivo de consola (CONIN$) en vez de stdin. Hace falta porque cuando
      la ventana se abre desde otro proceso (herramienta de acceso remoto, tarea
      programada, un wrapper) stdin puede llegar cerrado: cmd sigue funcionando porque
      'pause' lee la consola, pero Read-Host de PowerShell devuelve vacio al instante y
      el menu se cerraba solo.
    #>
    if ('FudoConsoleIn' -as [type]) { return }
    Add-Type -Language CSharp -TypeDefinition @'
using System;
using System.IO;
using System.Runtime.InteropServices;
using Microsoft.Win32.SafeHandles;
public static class FudoConsoleIn {
    [DllImport("kernel32.dll", SetLastError=true, CharSet=CharSet.Unicode)]
    private static extern IntPtr CreateFileW(string name, uint access, uint share,
        IntPtr sec, uint disposition, uint flags, IntPtr template);
    public static string ReadLine() {
        IntPtr h = CreateFileW("CONIN$", 0xC0000000u, 0x3u, IntPtr.Zero, 3u, 0u, IntPtr.Zero);
        if (h == IntPtr.Zero || h == new IntPtr(-1)) { return null; }
        using (FileStream fs = new FileStream(new SafeFileHandle(h, true), FileAccess.Read))
        using (StreamReader sr = new StreamReader(fs)) { return sr.ReadLine(); }
    }
}
'@
}

function Read-DoctorLine {
    <#
      Una linea escrita por el asesor, probando las tres vias en orden:
        1) stdin normal (Read-Host / Console.In)
        2) la consola directo (CONIN$)
      Devuelve $null solo si NO hay teclado de ninguna forma: eso es distinto de
      "apreto Enter sin escribir nada" (que devuelve cadena vacia) y quien llama tiene
      que tratarlos distinto.
    #>
    param([string]$Prompt = '')
    Suspend-LiveStatus
    if ($Prompt) { Write-Host ($Prompt + ': ') -NoNewline }
    try {
        $l = [Console]::In.ReadLine()
        if ($null -ne $l) { return [string]$l }
    } catch {}
    try {
        Initialize-ConsoleInputHelper
        $l2 = [FudoConsoleIn]::ReadLine()
        if ($null -ne $l2) { return [string]$l2 }
    } catch {}
    return $null
}

function Read-DoctorKey {
    <#
      Una sola tecla, sin Enter, para el menu. Si no se puede (entrada redirigida),
      cae a leer una linea completa.
    #>
    param([string]$Prompt = '')
    if ($Prompt) { Write-Host ($Prompt + ': ') -NoNewline }
    try {
        if (-not [Console]::IsInputRedirected) {
            $k = [Console]::ReadKey($true)
            if ($k.Key -eq [ConsoleKey]::Enter) { Write-Host ''; return '' }
            Write-Host ([string]$k.KeyChar)
            return ([string]$k.KeyChar)
        }
    } catch {}
    $l = Read-DoctorLine
    if ($null -eq $l) { return $null }
    return [string]$l
}

function Test-IsInteractiveConsole {
    <# Hay un humano mirando esta consola? (no redirigida, no -Quiet, no -Json) #>
    if ($Quiet -or $Json -or $SelfTest) { return $false }
    try {
        if ([Console]::IsOutputRedirected -or [Console]::IsInputRedirected) { return $false }
    } catch { return $false }
    return $true
}

function Test-IsNetworkPort {
    <#
      El puerto de esta cola es de RED? Cubre las tres formas en que Windows nombra un
      puerto de red: IP_x.x.x.x, la IP pelada, el 9100 en el nombre, y los puertos WSD
      (descubrimiento automatico, sin IP en el nombre).
    #>
    param([string]$PortName)
    if (-not $PortName) { return $false }
    if ($PortName -match '^(?i)IP_')                      { return $true }
    if ($PortName -match '9100')                          { return $true }
    if ($PortName -match '^\d{1,3}(\.\d{1,3}){3}')        { return $true }
    if ($PortName -match '(?i)^WSD-')                     { return $true }
    if ($PortName -match '(?i)^\{?[0-9a-f]{8}-[0-9a-f]{4}-') { return $true }
    return $false
}

function Resolve-RunMode {
    <#
      Que revisar: USB, Red o Ambos.
      Nace de un caso real: un cliente con dos impresoras de red sanas recibia como
      diagnostico "ninguna impresora fisica conectada", porque el camino USB gana y en esa
      PC no hay nada por USB. Preguntarlo al arrancar evita ese diagnostico enganoso.
      'auto' = preguntar si hay un humano; en modo agente equivale a 'Ambos' (historico).
    #>
    if ($Modo -ne 'auto') { return $Modo }
    if (-not (Test-IsInteractiveConsole)) { return 'Ambos' }

    Write-Host ''
    Write-Host '  Que impresora hay que revisar?' -ForegroundColor Cyan
    Write-Host '    1  USB    - la impresora esta enchufada a esta PC con un cable USB'
    Write-Host '    2  Red    - la impresora tiene IP propia (cable de red o wifi)'
    Write-Host '    3  Ambas  - revisar las dos'
    Write-Host ''
    Write-Host '    Si no sabes, elegi 3.' -ForegroundColor DarkGray

    for ($i = 0; $i -lt 3; $i++) {
        $k = Read-DoctorKey -Prompt '  Opcion (1/2/3, Enter = ambas)'
        # $null = no hay teclado de ninguna forma (no es lo mismo que Enter pelado).
        if ($null -eq $k) { return 'Ambos' }
        $k = ([string]$k).Trim()
        if ($k -eq '')  { return 'Ambos' }
        if ($k -eq '1') { return 'USB' }
        if ($k -eq '2') { return 'Red' }
        if ($k -eq '3') { return 'Ambos' }
        Write-Host '    Opcion invalida. Escribi 1, 2 o 3.' -ForegroundColor Yellow
    }
    return 'Ambos'
}

function Confirm-ReviewOtherInterface {
    <#
      Se eligio un modo (USB o Red) y no hay ninguna impresora de ese tipo. Antes de tocar
      NADA de la otra interfaz hay que preguntar: el motor repara e imprime, asi que seguir
      por las bravas significa sacar papel de una impresora que el asesor no eligio.
      Sin consola (modo agente) la respuesta es NO: nunca se actua sobre algo no pedido.
      Devuelve $true solo si un humano dijo que si.
    #>
    param([string]$Modo, $Otras)
    $lista = @($Otras)
    if (-not (Test-IsInteractiveConsole)) { return $false }
    Suspend-LiveStatus
    $queSon = $(if ($Modo -eq 'Red') { 'por USB' } else { 'de red' })
    Write-Host ''
    Write-Host ("  No hay ninguna impresora " + $(if ($Modo -eq 'Red') { 'de red' } else { 'por USB' }) + ' instalada en esta PC.') -ForegroundColor Yellow
    if (@($lista).Count -gt 0) {
        Write-Host ("  Si hay " + @($lista).Count + " conectada(s) " + $queSon + ':')
        foreach ($o in $lista) { Write-Host ('    - ' + $o) }
    }
    Write-Host ''
    Write-Host '  Elegiste no revisar esas, asi que no se toco ninguna.' -ForegroundColor DarkGray
    $ans = Read-DoctorLine -Prompt '  Las reviso igual? (s = si / Enter = no, terminar)'
    if ($null -eq $ans) { return $false }
    # El archivo va en ASCII puro: la i con tilde se escribe como escape del regex.
    return ([string]$ans -match '(?i)^\s*(s|si|s\u00ED|y|yes)\s*$')
}

function Wait-QueueDrain {
    <#
      Espera a que el ticket de prueba SALGA de la cola en vez de mirar una sola vez.
      Un muestreo unico a 1.5s daba las dos clases de error: el spooler todavia no
      habia marcado el trabajo (falso "no imprimio") o el trabajo ya se habia
      descartado por error de puerto (falso "imprimio").
      Devuelve:
        quedoEnCola  -> el ticket sigue en la cola al vencer el timeout
        bloqueadoPor -> cuantos trabajos AJENOS (comandas viejas) hay delante
        esperaMs     -> cuanto se espero de verdad
    #>
    param([string]$Printer, [string]$DocMatch = 'fudo print doctor', [int]$TimeoutMs = 8000)
    $ajenos = 0
    try {
        $otros = @(Get-PrintJob -PrinterName $Printer -ErrorAction SilentlyContinue |
                   Where-Object { [string]$_.DocumentName -notmatch "(?i)$DocMatch" })
        $ajenos = @($otros).Count
    } catch {}
    $inicio = Get-Date
    $fin    = $inicio.AddMilliseconds($TimeoutMs)
    $quedo  = $true
    while ((Get-Date) -lt $fin) {
        Start-Sleep -Milliseconds 500
        $pend = @()
        try {
            $pend = @(Get-PrintJob -PrinterName $Printer -ErrorAction SilentlyContinue |
                      Where-Object { [string]$_.DocumentName -match "(?i)$DocMatch" })
        } catch {}
        if (@($pend).Count -eq 0) { $quedo = $false; break }
    }
    return @{ quedoEnCola = $quedo; bloqueadoPor = [int]$ajenos
              esperaMs = [int]((Get-Date) - $inicio).TotalMilliseconds }
}

function Confirm-PaperCameOut {
    <#
      El unico juez de si el ticket salio es el humano que esta al lado de la impresora.
      Ningun chequeo de software alcanza:
        - WritePrinter devuelve OK cuando el SPOOLER acepta los bytes;
        - el spooler marca el trabajo como impreso cuando el DEVICE los acepta,
          aunque no haya papel (rollo terminado, tapa abierta, adaptador
          USB-paralelo sin impresora del otro lado, papel al reves).
      Por eso, si hay consola, se pregunta. Devuelve $true / $false / $null (no se pudo).
    #>
    param([string]$Printer)
    if (-not (Test-IsInteractiveConsole)) { return $null }
    Suspend-LiveStatus
    Write-Host ''
    Write-Host ("  Mira la impresora: salio el ticket de prueba de '" + $Printer + "'?") -ForegroundColor Cyan
    $ans = ''
    $ans = Read-DoctorLine -Prompt '  (s = salio / n = no salio / Enter = no puedo verla ahora)'
    if ($null -eq $ans) { return $null }
    if ($ans -match '(?i)^\s*(s|si|y|yes|1)\s*$') { return $true }
    if ($ans -match '(?i)^\s*(n|no|0)\s*$')       { return $false }
    return $null
}

function Unblock-QueueForTest {
    <#
      Antes de probar puertos hay que dejar la cola en condiciones de imprimir.
      Caso real: la cola estaba offline y con 11 comandas viejas trabadas, asi que
      TODOS los puertos candidatos "fallaban" y el motor revertia el cambio.
      Devuelve la lista de cosas que destrabo (para poder contarlas en el JSON).
    #>
    param($Printer)
    $hechos = @()
    if ($null -eq $Printer) { return $hechos }
    $nombre = [string]$Printer.Name

    # 1) marca offline: mientras este puesta, ningun trabajo se manda al puerto
    $offline = $false
    try { $offline = [bool](Get-Printer -Name $nombre -ErrorAction SilentlyContinue).WorkOffline } catch {}
    if (-not $offline) {
        try { $offline = [bool](Get-CimInstance Win32_Printer -Filter ("Name='" + ($nombre -replace "'","''") + "'") -ErrorAction SilentlyContinue).WorkOffline } catch {}
    }
    if ($offline) {
        try { Set-Printer -Name $nombre -WorkOffline $false -ErrorAction Stop; $hechos += 'se quito la marca offline' } catch {}
    }
    # 2) cola pausada
    # v3.15: aca se llamaba a Resume-PrintQueue, que NO EXISTE en Windows (el modulo
    # PrintManagement trae Resume-PrintJob, para un trabajo, no para la cola). La llamada estaba
    # dentro de un try/catch, asi que en vez de romper fallaba en silencio: una cola pausada
    # nunca se reanudaba, el ticket de prueba quedaba encolado y el asesor contestaba -bien- que
    # no salio papel. Es el mismo falso negativo que la v3.10 corrigio por otra via.
    # La via que si existe es el metodo Resume() de Win32_Printer.
    $filtro = "Name='" + ($nombre -replace "'","''") + "'"
    $pausada = $false
    try { $pausada = [bool](Get-Printer -Name $nombre -ErrorAction SilentlyContinue).Paused } catch {}
    if (-not $pausada) {
        try { $pausada = ((([int](Get-CimInstance Win32_Printer -Filter $filtro -ErrorAction SilentlyContinue).PrinterState) -band 1) -ne 0) } catch {}
    }
    if ($pausada) {
        try {
            $wp = Get-CimInstance Win32_Printer -Filter $filtro -ErrorAction Stop
            $rr = Invoke-CimMethod -InputObject $wp -MethodName 'Resume' -ErrorAction Stop
            if ([int]$rr.ReturnValue -eq 0) { $hechos += 'se reanudo la cola' }
            else { $hechos += ('no se pudo reanudar la cola (codigo ' + [int]$rr.ReturnValue + ')') }
        } catch { $hechos += ('no se pudo reanudar la cola: ' + $_.Exception.Message) }
    }
    # 3) tickets de prueba nuestros que hayan quedado colgados (no son comandas del cliente)
    try {
        $mios = @(Get-PrintJob -PrinterName $nombre -ErrorAction SilentlyContinue | Where-Object { [string]$_.DocumentName -match '(?i)fudo print doctor' })
        if (@($mios).Count -gt 0) { $mios | Remove-PrintJob -ErrorAction SilentlyContinue; $hechos += ("se descartaron " + @($mios).Count + " tickets de prueba viejos") }
    } catch {}
    return $hechos
}

function Confirm-Irreversible {
    <#
      Decide si se aplica una remediacion que no se puede deshacer (hoy: purgar la cola).
      Orden de decision:
        -SkipIrreversible            -> no
        -AllowQueuePurge $true/$false -> lo que diga el invocador
        consola interactiva          -> se le pregunta al asesor
        no interactiva (agente)      -> NO se aplica, queda como accion pendiente en el JSON
    #>
    param([string]$Description, [string]$Impact = '')
    if ($SkipIrreversible) { return $false }
    if ($script:BoundParams -and $script:BoundParams.ContainsKey('AllowQueuePurge')) { return [bool]$AllowQueuePurge }
    if (-not (Test-IsInteractiveConsole)) { return $false }

    Suspend-LiveStatus
    [Console]::Error.WriteLine('')
    [Console]::Error.WriteLine('  ------------------------------------------------------------')
    [Console]::Error.WriteLine("  Hace falta una accion que NO se puede deshacer:")
    [Console]::Error.WriteLine("    $Description")
    if ($Impact) { [Console]::Error.WriteLine("    Consecuencia: $Impact") }
    [Console]::Error.WriteLine('  ------------------------------------------------------------')
    $ans = ''
    $ans = Read-DoctorLine -Prompt '  Aplicar? (s = si / cualquier otra tecla = no)'
    if ($null -eq $ans) { return $false }
    return ($ans -match '(?i)^\s*(s|si|s\u00ED|y|yes)\s*$')
}

function Invoke-Remediation {
    <#
      Envuelve una remediacion respetando DryRun/AutoFix.
      $Fix es un scriptblock que efectua el cambio y devuelve un string descriptivo.
    #>
    param(
        [string]$Description,
        [scriptblock]$Fix,
        [string]$Type,
        [string]$Target,
        [string]$Before = '',
        [string]$After = '',
        [bool]$Reversible = $true,
        [string]$Impact = ''
    )
    if (-not $AutoFix) {
        return @{ applied = $false; note = "auto-fix deshabilitado: $Description" }
    }
    if ($DryRun) {
        Write-DoctorLog -Level 'INFO' -Message "DRY-RUN: aplicaria -> $Description"
        return @{ applied = $false; note = "dry-run: $Description" }
    }
    if (-not $Reversible) {
        if (-not (Confirm-Irreversible -Description $Description -Impact $Impact)) {
            Write-DoctorLog -Level 'WARN' -Message "NO aplicada (irreversible, sin confirmacion): $Description"
            return @{ applied = $false; note = "pendiente de confirmacion (irreversible): $Description" }
        }
    }
    try {
        $result = & $Fix
        Add-Action -Type $Type -Target $Target -Before $Before -After $After -Reversible $Reversible
        Write-DoctorLog -Level 'INFO' -Message "FIX aplicado: $Description"
        return @{ applied = $true; note = ([string]$result) }
    } catch {
        Write-DoctorLog -Level 'ERROR' -Message "FIX fallo ($Description): $($_.Exception.Message)"
        return @{ applied = $false; note = "error: $($_.Exception.Message)" }
    }
}

# ---------------------------------------------------------------------------
# Helper: impresion RAW por WinSpool (para test ESC/POS por USB)
# ---------------------------------------------------------------------------
function Initialize-RawPrinterHelper {
    if ('FudoRawPrinter' -as [type]) { return }
    $code = @'
using System;
using System.Runtime.InteropServices;
public class FudoRawPrinter {
    [StructLayout(LayoutKind.Sequential, CharSet=CharSet.Ansi)]
    public class DOCINFOA { [MarshalAs(UnmanagedType.LPStr)] public string pDocName; [MarshalAs(UnmanagedType.LPStr)] public string pOutputFile; [MarshalAs(UnmanagedType.LPStr)] public string pDataType; }
    [DllImport("winspool.Drv", EntryPoint="OpenPrinterA", SetLastError=true, CharSet=CharSet.Ansi)] public static extern bool OpenPrinter(string src, out IntPtr hPrinter, IntPtr pd);
    [DllImport("winspool.Drv", EntryPoint="ClosePrinter", SetLastError=true)] public static extern bool ClosePrinter(IntPtr hPrinter);
    [DllImport("winspool.Drv", EntryPoint="StartDocPrinterA", SetLastError=true, CharSet=CharSet.Ansi)] public static extern bool StartDocPrinter(IntPtr hPrinter, int level, [In, MarshalAs(UnmanagedType.LPStruct)] DOCINFOA di);
    [DllImport("winspool.Drv", EntryPoint="EndDocPrinter", SetLastError=true)] public static extern bool EndDocPrinter(IntPtr hPrinter);
    [DllImport("winspool.Drv", EntryPoint="StartPagePrinter", SetLastError=true)] public static extern bool StartPagePrinter(IntPtr hPrinter);
    [DllImport("winspool.Drv", EntryPoint="EndPagePrinter", SetLastError=true)] public static extern bool EndPagePrinter(IntPtr hPrinter);
    [DllImport("winspool.Drv", EntryPoint="WritePrinter", SetLastError=true)] public static extern bool WritePrinter(IntPtr hPrinter, IntPtr pBytes, int dwCount, out int dwWritten);
    public static bool SendBytes(string printerName, byte[] bytes) {
        IntPtr hPrinter; int written = 0;
        DOCINFOA di = new DOCINFOA(); di.pDocName = "Fudo Print Doctor Test"; di.pDataType = "RAW";
        if (!OpenPrinter(printerName.Normalize(), out hPrinter, IntPtr.Zero)) return false;
        bool ok = false;
        try {
            if (StartDocPrinter(hPrinter, 1, di)) {
                if (StartPagePrinter(hPrinter)) {
                    IntPtr p = Marshal.AllocCoTaskMem(bytes.Length);
                    Marshal.Copy(bytes, 0, p, bytes.Length);
                    ok = WritePrinter(hPrinter, p, bytes.Length, out written);
                    Marshal.FreeCoTaskMem(p);
                    EndPagePrinter(hPrinter);
                }
                EndDocPrinter(hPrinter);
            }
        } finally { ClosePrinter(hPrinter); }
        return ok;
    }
}
'@
    Add-Type -TypeDefinition $code -Language CSharp
}

function Get-EscPosTestTicket {
    param([string]$Caption = 'FUDO PRINT DOCTOR')
    # ESC @ init, texto, feed, corte parcial (GS V)
    $ESC = [char]27; $GS = [char]29
    $sb = New-Object System.Text.StringBuilder
    [void]$sb.Append($ESC + '@')                     # init
    [void]$sb.Append($ESC + 'a' + [char]1)           # centro
    [void]$sb.Append($ESC + '!' + [char]56)          # doble alto/ancho + bold
    [void]$sb.Append($Caption + "`n")
    [void]$sb.Append($ESC + '!' + [char]0)           # normal
    [void]$sb.Append("Prueba de impresion`n")
    [void]$sb.Append((Get-Date).ToString('yyyy-MM-dd HH:mm:ss') + "`n")
    [void]$sb.Append("Si lees esto, el hardware imprime OK`n")
    # OJO: en una termica el cabezal esta a 1-2 cm del cortador. Con pocos saltos de linea el
    # texto recien impreso queda RETENIDO adentro del mecanismo: sale un pedazo de papel en
    # blanco y lo impreso no asoma. El asesor mira, no ve nada y responde que no salio, asi que
    # el motor da por fallado un hardware que anda. Caso real: el mismo puerto y el mismo driver
    # generico imprimian bien al probarlos a mano.
    # Se usan saltos de linea (universales, funcionan aunque la impresora no entienda ESC d) y
    # ademas se pide el avance en el propio comando de corte.
    [void]$sb.Append("`n`n`n`n`n`n")
    [void]$sb.Append($ESC + 'd' + [char]3)           # feed 3 lineas (si lo soporta)
    [void]$sb.Append($GS + 'V' + [char]66 + [char]80) # corte parcial alimentando 80 puntos (~10mm)
    return $sb.ToString()
}

function Send-EscPosOverTcp {
    param([string]$Ip, [int]$TcpPort, [int]$TimeoutMs = 4000)
    $client = New-Object System.Net.Sockets.TcpClient
    try {
        $iar = $client.BeginConnect($Ip, $TcpPort, $null, $null)
        if (-not $iar.AsyncWaitHandle.WaitOne($TimeoutMs)) { throw "timeout conectando a ${Ip}:${TcpPort}" }
        $client.EndConnect($iar)
        $stream = $client.GetStream()
        $payload = [System.Text.Encoding]::GetEncoding(437).GetBytes((Get-EscPosTestTicket))
        $stream.Write($payload, 0, $payload.Length)
        $stream.Flush()
        Start-Sleep -Milliseconds 300
        return $true
    } finally {
        $client.Close()
    }
}

# ---------------------------------------------------------------------------
# LAYER 0 - Prerequisitos de entorno
# ---------------------------------------------------------------------------
function Test-Layer0-Environment {
    # 0.1 OS Windows ($IsWindows existe en PS7; en Windows PowerShell 5.1 no existe -> asumimos Windows)
    if (Get-Variable -Name 'IsWindows' -Scope Global -ErrorAction SilentlyContinue) {
        $runningOnWindows = [bool]$IsWindows
    } else {
        $runningOnWindows = ($env:OS -eq 'Windows_NT') -or ($PSVersionTable.ContainsKey('Platform') -eq $false)
    }
    if (-not $runningOnWindows) {
        Add-Check -Id 'env.os' -Layer 0 -Name 'Sistema operativo Windows' -Status 'fail' -RootCauseCandidate $true `
            -Evidence @{ platform = $env:OS } -Plane 'os' `
            -Recommendation 'Este motor cubre Windows. Para Linux usar el flujo/articulos de Linux.'
        return $false
    }
    Add-Check -Id 'env.os' -Layer 0 -Name 'Sistema operativo Windows' -Status 'ok' -Evidence @{ os = $env:OS }

    # 0.2 Privilegios
    $isAdmin = $false
    try {
        $wi = [Security.Principal.WindowsIdentity]::GetCurrent()
        $wp = New-Object Security.Principal.WindowsPrincipal($wi)
        $isAdmin = $wp.IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)
    } catch {}
    $script:Diagnostics['isAdmin'] = $isAdmin
    Add-Check -Id 'env.admin' -Layer 0 -Name 'Privilegios de administrador' -Status $(if($isAdmin){'ok'}else{'warn'}) `
        -Evidence @{ isAdmin = $isAdmin } `
        -Recommendation $(if($isAdmin){''}else{'Sin admin algunas remediaciones (spooler, drivers) pueden fallar.'})

    # 0.3 Servicio Spooler
    $spooler = $null
    try { $spooler = Get-Service -Name 'Spooler' -ErrorAction Stop } catch {}
    if ($null -eq $spooler) {
        Add-Check -Id 'env.spooler' -Layer 0 -Name 'Servicio Print Spooler' -Status 'fail' -RootCauseCandidate $true `
            -Evidence @{ found = $false } -Recommendation 'No se encontro el servicio Spooler.'
    } elseif ($spooler.Status -ne 'Running') {
        $rem = Invoke-Remediation -Description 'Iniciar servicio Spooler' -Type 'service.start' -Target 'Spooler' `
            -Before ([string]$spooler.Status) -After 'Running' -Fix {
                Set-Service -Name 'Spooler' -StartupType Automatic -ErrorAction SilentlyContinue
                Start-Service -Name 'Spooler'
                (Get-Service -Name 'Spooler').Status.ToString()
            }
        Add-Check -Id 'env.spooler' -Layer 0 -Name 'Servicio Print Spooler' -Status $(if($rem.applied){'fixed'}else{'fail'}) -RootCauseCandidate $true `
            -Evidence @{ statusBefore = [string]$spooler.Status } -ActionTaken $rem.note `
            -Recommendation 'El spooler detenido impide toda impresion en Windows.'
    } else {
        Add-Check -Id 'env.spooler' -Layer 0 -Name 'Servicio Print Spooler' -Status 'ok' -Evidence @{ status = 'Running' }
    }

    # 0.4 App Nativa de Fudo (prerequisito para detectar/imprimir; art. 16419361)
    $fudoProc = @()
    try { $fudoProc = @(Get-Process -ErrorAction SilentlyContinue | Where-Object { $_.Name -like "*$FudoAppProcess*" }) } catch {}
    $fudoSvc = @()
    try { $fudoSvc = @(Get-Service -ErrorAction SilentlyContinue | Where-Object { $_.Name -like "*$FudoAppProcess*" -or $_.DisplayName -like "*$FudoAppProcess*" }) } catch {}
    $fudoPresent = (@($fudoProc).Count -gt 0) -or (@($fudoSvc).Count -gt 0)
    # El nombre sale como CAUSA: tiene que decir lo que se encontro. Con el nombre fijo, una PC
    # con la Nativa caida mostraba "CAUSA: App Nativa de Fudo en ejecucion", justo lo contrario.
    #
    # Y NO es candidata a causa raiz: la Nativa es un native messaging host, el navegador la
    # levanta cuando Fudo la necesita y la cierra despues. Con Fudo cerrado -lo habitual cuando
    # el asesor entra por acceso remoto- que no este corriendo es el estado normal, no una
    # falla. Se informa, pero la causa de que no salga la comanda tiene que salir de evidencia
    # real (fudo.usoReal: el historial del spooler).
    Add-Check -Id 'env.fudoApp' -Layer 0 `
        -Name $(if($fudoPresent){'App Nativa de Fudo en ejecucion'}else{'La App Nativa de Fudo no esta corriendo ahora'}) `
        -Status $(if($fudoPresent){'ok'}else{'warn'}) `
        -RootCauseCandidate $false `
        -Evidence @{ processes = @($fudoProc | Select-Object -First 5 | ForEach-Object { $_.Name }); services = @($fudoSvc | ForEach-Object { $_.Name }) } `
        -ArticleRef 'https://soporte.fu.do/es/articles/16419361' `
        -Recommendation $(if($fudoPresent){''}else{'La Nativa arranca sola cuando se abre Fudo en el navegador: si Fudo esta cerrado, esto es normal y no hay nada que hacer. Solo es un problema si Fudo esta abierto en esta PC y aun asi no corre (ahi si, revisar el antivirus).'})

    return $true
}

# ---------------------------------------------------------------------------
# LAYER 0b - App Nativa de Fudo vs Antivirus
# Causa muy frecuente: la App Nativa queda bloqueada / en cuarentena por Defender o Avast.
# Estrategia: exclusiones quirurgicas (ruta + proceso) en vez de desactivar el antivirus.
# ---------------------------------------------------------------------------
function Test-NativaDegradada {
    <#
      La version que quedo despues de restaurar de cuarentena es MAS VIEJA que la que habia
      antes? Tolerante: si alguna de las dos no se puede leer como version, no se afirma nada
      (igual que Test-PortHasLiveDevice, nunca inventa un problema).
    #>
    param([string]$Antes, [string]$Despues)
    if (-not $Antes -or -not $Despues) { return $false }
    if ($Antes -eq $Despues) { return $false }
    try { return ([bool]([version]$Despues -lt [version]$Antes)) } catch { return $false }
}

function Get-FudoDataDirs {
    # Donde la Nativa deja sus archivos. Es la misma carpeta que sondea Get-FudoNativeFingerprint.
    $d = @()
    try { if ($env:LOCALAPPDATA) { $d += (Join-Path $env:LOCALAPPDATA 'Fudo') } } catch {}
    try { if ($env:APPDATA)      { $d += (Join-Path $env:APPDATA 'Fudo') } } catch {}
    return @($d | Where-Object { $_ })
}

function Find-FudoNativeInstall {
    <#
      v3.19: hasta la 3.18 alcanzaba con una carpeta que matcheara 'Fudo*' o una entrada de
      registro para dar la Nativa por instalada, y las dos senales mienten.
      El caso que lo destapo: una app instalada desde el navegador (Chrome > Instalar pagina
      como app) se registra con DisplayName 'Fudo' y DisplayVersion 1.0. El motor la leia como
      una Nativa v1.0 y el guardarrail anti-degradacion de la 3.18 abortaba la instalacion del
      .msi para "no degradar" algo que ni siquiera era la Nativa: en esas PCs el motor no iba a
      instalar la Nativa nunca, por mas que el asesor trajera el instalador.
      El registro tambien queda huerfano cuando el antivirus se lleva los archivos.
      La unica senal que no miente son los archivos: fudo_native_extension en %LOCALAPPDATA%\Fudo.
    #>
    Write-StepDetail 'buscando la instalacion de la App Nativa'
    $paths = @()
    if ($FudoNativePath) { $paths += $FudoNativePath }
    $roots = @($env:LOCALAPPDATA, $env:APPDATA, ${env:ProgramFiles}, ${env:ProgramFiles(x86)}, "$env:LOCALAPPDATA\Programs")
    foreach ($r in $roots) {
        if (-not $r) { continue }
        foreach ($pat in @('Fudo*','*fudo*','FudoNativa*','Fudo Nativa*')) {
            try {
                $hits = Get-ChildItem -Path $r -Filter $pat -Directory -ErrorAction SilentlyContinue | Select-Object -First 3
                foreach ($h in $hits) { $paths += $h.FullName }
            } catch {}
        }
    }
    # Registro de desinstalacion
    $uninstallKeys = @(
        'HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\Uninstall\*',
        'HKLM:\SOFTWARE\WOW6432Node\Microsoft\Windows\CurrentVersion\Uninstall\*',
        'HKCU:\SOFTWARE\Microsoft\Windows\CurrentVersion\Uninstall\*'
    )
    $regInfo = @()
    foreach ($k in $uninstallKeys) {
        try {
            Get-ItemProperty -Path $k -ErrorAction SilentlyContinue | Where-Object { $_.DisplayName -like '*Fudo*' } | ForEach-Object {
                # Una app del navegador se desinstala con chrome.exe/msedge.exe --uninstall-app-id.
                # Esa es la firma explicita de la PWA y es lo que la separa de la Nativa de verdad:
                # sin esto, su DisplayVersion 1.0 se lee como "la Nativa instalada es la v1.0".
                $un = [string]$_.UninstallString
                $esPwa = [bool]($un -match '(?i)(chrome|msedge|chromium)\.exe')
                $regInfo += [ordered]@{ name = $_.DisplayName; version = $_.DisplayVersion
                                        location = $_.InstallLocation; esPwa = $esPwa }
                if ($_.InstallLocation -and -not $esPwa) { $paths += $_.InstallLocation }
            }
        } catch {}
    }
    # Los archivos reales de la Nativa. El ejecutable es el que manda. Los manifests de native
    # messaging sirven para el registro del host, pero se reescriben en cada reinstalacion y el
    # binario no, asi que fechar la instalacion por los .json tambien miente.
    $exe = ''
    $manifests = @()
    $carpeta = ''
    foreach ($c in @(Get-FudoDataDirs)) {
        try { if (-not (Test-Path $c)) { continue } } catch { continue }
        if (-not $carpeta) { $carpeta = $c }
        if (-not $exe) {
            try {
                $hit = @(Get-ChildItem -Path $c -Filter 'fudo_native_extension*' -File -ErrorAction SilentlyContinue |
                         Where-Object { $_.Extension -match '(?i)^(\.exe)?$' } | Select-Object -First 1)
                if (@($hit).Count -gt 0) { $exe = [string]@($hit)[0].FullName }
            } catch {}
        }
        foreach ($m in @('do.fu.native_extension_chrome.json','do.fu.native_extension_firefox.json')) {
            $mp = Join-Path $c $m
            try { if (Test-Path $mp) { $manifests += $mp } } catch {}
        }
    }
    $regReales = @(@($regInfo) | Where-Object { -not $_.esPwa })
    return [ordered]@{
        paths        = @($paths | Where-Object { $_ } | Select-Object -Unique)
        regInfo      = $regInfo
        exe          = [string]$exe
        manifests    = @($manifests)
        carpeta      = [string]$carpeta
        enDisco      = [bool]$exe
        soloRegistro = [bool]((-not $exe) -and (@($regReales).Count -gt 0))
        pwa          = [bool](@(@($regInfo) | Where-Object { $_.esPwa }).Count -gt 0)
    }
}

function Get-AntivirusState {
    Write-StepDetail 'consultando Defender y antivirus de terceros'
    $state = [ordered]@{ defender = $null; thirdParty = @(); realTime = $null; fudoThreats = @() }
    # Defender status
    try {
        $mp = Get-MpComputerStatus -ErrorAction Stop
        $state.realTime = [bool]$mp.RealTimeProtectionEnabled
        $state.defender = [ordered]@{
            amRunning              = [bool]$mp.AMServiceEnabled
            realTimeProtection     = [bool]$mp.RealTimeProtectionEnabled
            antivirusEnabled       = [bool]$mp.AntivirusEnabled
        }
    } catch {}
    # Amenazas/cuarentena relacionadas a Fudo
    try {
        $threats = Get-MpThreatDetection -ErrorAction SilentlyContinue
        foreach ($t in @($threats)) {
            $res = @($t.Resources) -join ';'
            if ($res -match '(?i)fudo' -or ([string]$t.ThreatID) -match '(?i)fudo') {
                # Get-MpThreatDetection devuelve el HISTORIAL de detecciones, no la
                # cuarentena actual: una deteccion de hace semanas sigue apareciendo para
                # siempre. Sin 'remediada' y 'detectada' no habia forma de distinguir una
                # cuarentena viva de un registro viejo, y se reparaba sobre el registro.
                $ok = $null
                try { if ($null -ne $t.ActionSuccess) { $ok = [bool]$t.ActionSuccess } } catch {}
                $state.fudoThreats += [ordered]@{ id = [string]$t.ThreatID; resources = $res
                                                  action = [string]$t.ActionSuccess
                                                  remediada = $ok
                                                  statusId = $(try { [int]$t.ThreatStatusID } catch { $null })
                                                  detectada = $(try { [string]$t.InitialDetectionTime } catch { '' }) }
            }
        }
    } catch {}
    # AV de terceros (Avast, etc.) via SecurityCenter2
    try {
        $avs = Get-CimInstance -Namespace 'root/SecurityCenter2' -ClassName AntiVirusProduct -ErrorAction Stop
        foreach ($a in @($avs)) {
            if ($a.displayName -notmatch '(?i)defender') {
                $state.thirdParty += [string]$a.displayName
            }
        }
    } catch {}
    return $state
}

function Test-DefenderThreatActionable {
    <#
      Una deteccion de Defender sobre la Nativa amerita repararla?
      Get-MpThreatDetection es el historial de detecciones, no la cuarentena viva: una
      deteccion de hace semanas sigue listada para siempre. Hasta la 3.11 cualquier entrada
      de ese historial disparaba la restauracion + exclusiones. En la telemetria del 02/09
      aparecieron 6 corridas 3.11 con la Nativa 0.0.37 (firmada) y presente que igual
      'repararon' Defender y quedaron con esa causa raiz: uno de los dos unicos cierres de la
      3.11 cerro asi y volvio a fallar 34 segundos despues.
      La regla: si la Nativa esta PRESENTE, no hay nada que restaurar. El .exe presente es la
      prueba directa de que no esta en cuarentena, y vale mas que cualquier registro historico.
      Si NO esta presente, se repara igual que antes (aunque la version sea la firmada: en ese
      caso el gate de version no alcanza porque el archivo de verdad falta).
      Devuelve: accionable (bool), motivo (texto para el asesor), pendientes (las detecciones
      que Defender no llego a remediar).
    #>
    param($Threats, $Firmada, $Presente)
    $lista = @($Threats | Where-Object { $_ })
    $pendientes = @($lista | Where-Object { $_.remediada -ne $true })
    if (@($lista).Count -eq 0) {
        return @{ accionable = $false; motivo = 'sin detecciones de Defender sobre la Nativa'; pendientes = @() }
    }
    if ([bool]$Presente) {
        $m = 'la Nativa esta presente en disco, asi que la deteccion de Defender es historica'
        if ($Firmada -eq $true) { $m = $m + ' y ademas la version instalada ya esta firmada' }
        return @{ accionable = $false; motivo = $m; pendientes = @($pendientes) }
    }
    return @{ accionable = $true; motivo = 'la Nativa no aparece en disco y Defender registra detecciones'; pendientes = @($pendientes) }
}
function Test-DefenderExclusionNeeded {
    <#
      Hace falta agregarle exclusiones de Defender a la Nativa en esta PC?
      Un solo lugar donde se decide. Hasta la 3.17 habia DOS caminos distintos decidiendo lo
      mismo -la restauracion tenia su gate desde la 3.12 y la exclusion preventiva se habia
      quedado sin el-, y por eso la bitacora semanal encontro dos PCs 3.14 donde el motor toco
      el antivirus del cliente teniendo la causa raiz en el hardware.
      La regla es la misma que Test-DefenderThreatActionable: si el archivo esta en disco, no
      hay nada que excluir ni restaurar. Y ni estar sin firmar ni estar apagada son evidencia de
      que el antivirus la moleste -apagada con Fudo cerrado es el estado normal-.
      Devuelve @{ haceFalta (bool); motivo (texto para el asesor) }
    #>
    param($Presente, $Corriendo, $Firmada, $Detecciones, $DefenderActivo)
    $det = @($Detecciones | Where-Object { $_ })
    if (-not [bool]$DefenderActivo) {
        return @{ haceFalta = $false; motivo = 'Windows Defender no esta activo en esta PC' }
    }
    if ([bool]$Presente) {
        return @{ haceFalta = $false
                  motivo = ('el archivo de la App Nativa esta en disco, asi que no hay nada que excluir' +
                            $(if (@($det).Count -gt 0) { ', y las detecciones de Defender son historicas' }
                              else { ', y Defender no registra ninguna deteccion sobre ella' })) }
    }
    if (@($det).Count -gt 0) {
        return @{ haceFalta = $true; motivo = 'la Nativa no esta en disco y Defender registra detecciones: hay algo que restaurar y excluir' }
    }
    return @{ haceFalta = $false; motivo = 'la Nativa no esta en disco pero Defender nunca la detecto: lo que falta es instalarla, no excluirla' }
}

function Get-NativaVersionState {
    <#
      La Nativa instalada, esta firmada? Devuelve:
        version  - la que se leyo del registro ('' si no se pudo)
        firmada  - $true / $false / $null (no se pudo determinar)
      Comparar con [version] y no como texto: '0.0.9' es mayor que '0.0.36' alfabeticamente.
    #>
    param($Install)
    $ver = ''
    try {
        # v3.19: las entradas de la app del navegador quedan afuera. Su DisplayVersion 1.0 se
        # leia como la version de la Nativa y rompia toda comparacion de versiones.
        $reg = @(@($Install.regInfo) | Where-Object { -not $_.esPwa })
        if (@($reg).Count -gt 0) { $ver = [string]@($reg)[0].version }
    } catch {}
    # confiable: si la Nativa no esta en disco, la version del registro es un recuerdo, no un
    # hecho. Nada que decida instalar o no instalar puede apoyarse en una version no confiable.
    $confiable = $false
    try { $confiable = [bool]$Install.enDisco } catch {}
    if (-not $ver) { return @{ version = ''; firmada = $null; confiable = $confiable } }
    $firmada = $null
    try { $firmada = ([version]$ver -ge [version]$script:NativaVersionFirmada) } catch { $firmada = $null }
    return @{ version = $ver; firmada = $firmada; confiable = $confiable }
}

function Get-NativeMessagingState {
    <#
      El host de native messaging, esta REGISTRADO?
      Es el eslabon que nunca se miro: el .msi deja el binario, pero el navegador solo lo
      encuentra por una clave de registro que apunta a un manifest .json. Sin esa clave la
      extension no puede hablarle a la Nativa y Fudo se comporta como si no estuviera instalada.
      De ahi el "instalala y volve a iniciar sesion" de la web app: lo que falta no es la
      sesion, es el registro -- y correr el ejecutable de la Nativa lo deja hecho.
      OJO: la clave vive en HKCU, o sea que es POR USUARIO (ver Get-SesionInteractiva).
      En Firefox no hay clave de registro: el manifest se deja como archivo en
      %APPDATA%\Mozilla\NativeMessagingHosts. Se mira igual, porque si el cliente usa Firefox y
      ahi SI esta registrada, decir "el navegador no la tiene registrada" seria falso.
    #>
    $out = [ordered]@{ registrado = $false; navegadores = @(); manifest = ''; exeDelManifest = ''
                       exeExiste = $false; extensionIds = @(); pendientes = @() }
    $claves = @(
        [ordered]@{ nav = 'Chrome';   ruta = ('HKCU:\Software\Google\Chrome\NativeMessagingHosts\' + $script:FudoNativeHostName) },
        [ordered]@{ nav = 'Edge';     ruta = ('HKCU:\Software\Microsoft\Edge\NativeMessagingHosts\' + $script:FudoNativeHostName) },
        [ordered]@{ nav = 'Chromium'; ruta = ('HKCU:\Software\Chromium\NativeMessagingHosts\' + $script:FudoNativeHostName) }
    )
    foreach ($c in $claves) {
        $json = ''
        try { $json = [string](Get-ItemProperty -Path ([string]$c.ruta) -ErrorAction SilentlyContinue).'(default)' } catch {}
        if (-not $json) { $out.pendientes += ([string]$c.nav + ': sin clave de registro'); continue }
        $existe = $false
        try { $existe = [bool](Test-Path $json) } catch {}
        if (-not $existe) { $out.pendientes += ([string]$c.nav + ': la clave apunta a un manifest que no existe'); continue }
        $out.navegadores += [string]$c.nav
        if (-not $out.manifest) { $out.manifest = [string]$json }
    }
    # Firefox: manifest suelto, sin registro.
    try {
        if ($env:APPDATA) {
            $ff = Join-Path $env:APPDATA ('Mozilla\NativeMessagingHosts\' + $script:FudoNativeHostName + '.json')
            if (Test-Path $ff) {
                $out.navegadores += 'Firefox'
                if (-not $out.manifest) { $out.manifest = [string]$ff }
            } else { $out.pendientes += 'Firefox: sin manifest' }
        }
    } catch {}
    if ($out.manifest) {
        try {
            $txt = Get-Content -Path ([string]$out.manifest) -Raw -ErrorAction Stop
            $mp = [regex]::Match($txt, '"path"\s*:\s*"([^"]+)"')
            if ($mp.Success) { $out.exeDelManifest = ($mp.Groups[1].Value -replace '\\\\', '\') }
            # Los ids de extension habilitados viajan en allowed_origins. De aca sale contra que
            # extension hay que cruzar, sin tener que asumir una sola.
            foreach ($m in @([regex]::Matches($txt, 'chrome-extension://([a-p]{32})'))) {
                $id = [string]$m.Groups[1].Value
                if (@($out.extensionIds) -notcontains $id) { $out.extensionIds += $id }
            }
        } catch {}
        if ($out.exeDelManifest) { try { $out.exeExiste = [bool](Test-Path ([string]$out.exeDelManifest)) } catch {} }
    }
    # Registrado de verdad = hay clave Y el manifest apunta a un ejecutable que existe. Una clave
    # que apunta a un binario que el antivirus se llevo no sirve para nada.
    $out.registrado = [bool]((@($out.navegadores).Count -gt 0) -and $out.exeExiste)
    return $out
}

function Get-FudoExtensionState {
    <#
      La extension del navegador: el otro eslabon que no se miraba. Un asesor encontro PCs con la
      Nativa instalada y el antivirus en orden donde la extension no estaba, y agregandola a mano
      desde la tienda la Nativa levanto sola.
      Se busca en disco, en los perfiles del navegador: no hace falta abrir Chrome ni leer sus
      preferencias.
    #>
    param([string[]]$Ids = @())
    $ids = @(@($Ids) | Where-Object { $_ })
    if (@($ids).Count -eq 0) { $ids = @($script:FudoExtensionId) }
    $out = [ordered]@{ instalada = $false; ids = @($ids); encontrada = ''; navegador = ''
                       perfil = ''; perfilesVistos = 0 }
    $bases = @()
    if ($env:LOCALAPPDATA) {
        $bases += [ordered]@{ nav = 'Chrome';   ruta = (Join-Path $env:LOCALAPPDATA 'Google\Chrome\User Data') }
        $bases += [ordered]@{ nav = 'Edge';     ruta = (Join-Path $env:LOCALAPPDATA 'Microsoft\Edge\User Data') }
        $bases += [ordered]@{ nav = 'Chromium'; ruta = (Join-Path $env:LOCALAPPDATA 'Chromium\User Data') }
    }
    foreach ($b in $bases) {
        try { if (-not (Test-Path ([string]$b.ruta))) { continue } } catch { continue }
        $perfiles = @()
        try {
            $perfiles = @(Get-ChildItem -Path ([string]$b.ruta) -Directory -ErrorAction SilentlyContinue |
                          Where-Object { $_.Name -eq 'Default' -or $_.Name -like 'Profile *' })
        } catch {}
        foreach ($p in @($perfiles)) {
            $out.perfilesVistos++
            foreach ($id in @($ids)) {
                try {
                    if (Test-Path (Join-Path $p.FullName ('Extensions\' + $id))) {
                        $out.instalada = $true
                        $out.encontrada = [string]$id
                        $out.navegador  = [string]$b.nav
                        $out.perfil     = [string]$p.Name
                        return $out
                    }
                } catch {}
            }
        }
    }
    return $out
}

function Get-SesionInteractiva {
    <#
      Quien esta usando la PC, contra quien esta corriendo el motor.
      Importa porque HKCU y %LOCALAPPDATA% son POR USUARIO: el launcher se eleva a administrador,
      y si esa elevacion se hizo con OTRA cuenta (el cliente usa una cuenta estandar y alguien
      tipeo credenciales de admin), el motor esta mirando -y registrando- el perfil equivocado.
      El Chrome del cliente no se entera de nada.
    #>
    $out = [ordered]@{ usuarioMotor = [string]$env:USERNAME; usuarioSesion = ''; otroPerfil = $false }
    try {
        $ex = @(Get-CimInstance -ClassName Win32_Process -Filter "Name='explorer.exe'" -ErrorAction Stop)
        foreach ($p in @($ex)) {
            $o = $null
            try { $o = Invoke-CimMethod -InputObject $p -MethodName 'GetOwner' -ErrorAction Stop } catch {}
            if ($o -and $o.User) { $out.usuarioSesion = [string]$o.User; break }
        }
    } catch {}
    if ($out.usuarioSesion -and $out.usuarioMotor) {
        $out.otroPerfil = [bool]($out.usuarioSesion -ne $out.usuarioMotor)
    }
    return $out
}

function Start-FudoNativeHostProcess {
    <#
      Aislada para poder mockearla en el self-test: lanza el ejecutable de la Nativa y no lo deja
      colgado. Es un host stdio, asi que sin el pipe del navegador del otro lado puede quedarse
      esperando para siempre; se le da un rato para que registre y se lo cierra.
    #>
    param([string]$Exe, [int]$TimeoutSeg = 8)
    $proc = $null
    try { $proc = Start-Process -FilePath $Exe -PassThru -WindowStyle Hidden -ErrorAction Stop }
    catch { return @{ lanzado = $false; quedoVivo = $false; error = [string]$_.Exception.Message } }
    if ($null -eq $proc) { return @{ lanzado = $false; quedoVivo = $false; error = 'no se pudo lanzar el proceso' } }
    $fin = (Get-Date).AddSeconds($TimeoutSeg)
    while ((Get-Date) -lt $fin) {
        $vivo = $true
        try { $vivo = -not $proc.HasExited } catch { $vivo = $false }
        if (-not $vivo) { break }
        Start-Sleep -Milliseconds 500
    }
    $quedoVivo = $false
    try { $quedoVivo = -not $proc.HasExited } catch {}
    if ($quedoVivo) {
        try { Stop-Process -Id $proc.Id -Force -ErrorAction SilentlyContinue } catch {}
    }
    return @{ lanzado = $true; quedoVivo = [bool]$quedoVivo; error = '' }
}

function Register-FudoNativeHost {
    <#
      Deja la Nativa registrada en el navegador corriendo su propio ejecutable: al arrancar
      reescribe los manifests y deja la clave del navegador apuntando a ellos. Es lo mismo que
      consigue el "cerra sesion y volve a entrar" que pide la web app, sin cerrar sesion.
      Verifica el EFECTO -vuelve a leer la clave y el manifest-, nunca el codigo de salida.
    #>
    param([string]$Exe)
    $antes = Get-NativeMessagingState
    if ($antes.registrado) {
        return @{ aplicado = $false; intento = $false; registrado = $true; estado = $antes
                  motivo = 'el host ya estaba registrado'; nota = '' }
    }
    if (-not $Exe) {
        return @{ aplicado = $false; intento = $false; registrado = $false; estado = $antes
                  motivo = 'la Nativa no esta en disco: no hay nada que registrar, hay que instalarla'; nota = '' }
    }
    $salida = @{ lanzado = $false; quedoVivo = $false; error = '' }
    $rem = Invoke-Remediation -Description 'Registrar la App Nativa en el navegador (ejecutandola una vez)' `
        -Type 'nativa.registrar_host' -Target ([string]$script:FudoNativeHostName) `
        -Before 'sin registrar' -After 'registrado' -Reversible $true -Fix {
            Write-StepDetail 'registrando la App Nativa en el navegador'
            $r = Start-FudoNativeHostProcess -Exe $Exe
            $salida.lanzado   = [bool]$r.lanzado
            $salida.quedoVivo = [bool]$r.quedoVivo
            $salida.error     = [string]$r.error
            $(if ([bool]$r.lanzado) {
                'se ejecuto la App Nativa' + $(if ([bool]$r.quedoVivo) { ' (quedo corriendo y se cerro al terminar)' } else { '' })
            } else { 'no se pudo ejecutar la App Nativa: ' + [string]$r.error })
        }
    $despues = Get-NativeMessagingState
    $motivo = $(
        if ([bool]$despues.registrado)   { 'el host quedo registrado' }
        elseif (-not [bool]$rem.applied) { 'no se intento: ' + [string]$rem.note }
        elseif (-not [bool]$salida.lanzado) { 'no se pudo ejecutar el archivo de la Nativa' }
        else { 'se ejecuto la App Nativa y la clave del navegador no aparecio' }
    )
    return @{ aplicado = [bool]$rem.applied; intento = [bool]$rem.applied
              registrado = [bool]$despues.registrado; estado = $despues
              navegadores = @($despues.navegadores); nota = [string]$rem.note
              lanzado = [bool]$salida.lanzado; motivo = [string]$motivo }
}

function Test-Layer0b-NativeApp {
    $install = Find-FudoNativeInstall
    $av = Get-AntivirusState
    $script:Diagnostics['nativeInstall'] = $install
    $script:Diagnostics['antivirus']     = $av

    $procRunning = $false
    try { $procRunning = @(Get-Process -ErrorAction SilentlyContinue | Where-Object { $_.Name -like "*$FudoAppProcess*" }).Count -gt 0 } catch {}

    # v3.19: instalada = el ejecutable esta en disco. Ni una carpeta que matchee 'Fudo*', ni una
    # entrada de registro: las dos las deja tambien la app del navegador y el registro sobrevive
    # a que el antivirus se lleve los archivos. Se midio: 12 corridas en 7 PCs daban la Nativa
    # por instalada con la carpeta vacia.
    $installed = [bool]$install.enDisco

    # 0b.1 Nativa instalada?
    if (-not $installed) {
        # OJO: el nombre del check es el texto que sale como CAUSA en la consola y en la
        # telemetria. Si dice 'App Nativa instalada' cuando el status es fail, el asesor lee
        # exactamente lo contrario de lo que pasa.
        # Que NO este en disco tiene tres sabores distintos, y el asesor necesita saber cual es:
        # no esta y nunca estuvo, quedo el registro sin los archivos (el antivirus), o lo que
        # figura instalado es la app del navegador.
        $nombreNoInst = 'App Nativa de Fudo NO instalada'
        $porQue = 'La App Nativa no aparece en disco. Sin la Nativa, Fudo no puede mandar ninguna comanda a la impresora: instalar Nativa + extension del navegador (frecuentemente bloqueada por antivirus).'
        if ([bool]$install.pwa) {
            $nombreNoInst = 'App Nativa de Fudo NO instalada (lo que figura instalado es la pagina web agregada como aplicacion)'
            $porQue = ('Lo que esta instalado es Fudo agregado como aplicacion desde el navegador (Instalar pagina como app), que NO es la App Nativa y no imprime. ' +
                       'La App Nativa se instala aparte y deja sus archivos en %LOCALAPPDATA%\Fudo. Instalarla.')
        } elseif ([bool]$install.soloRegistro) {
            $nombreNoInst = 'App Nativa de Fudo NO instalada (figura en el registro pero no esta en disco)'
            $porQue = ('Windows la tiene anotada como instalada pero los archivos no estan en %LOCALAPPDATA%\Fudo: el antivirus se los llevo o la desinstalaron a medias. ' +
                       'Reinstalar la App Nativa y verificar que el antivirus no la vuelva a tocar.')
        }
        # v3.19: el campo que la telemetria necesitaba para responder "las instalaciones quedan?"
        # venia null en 135 de 135 corridas, con nativa.install como causa raiz #1. El motivo no
        # era que no viajara: es que el motor NO instala la Nativa por su cuenta -solo desde la
        # opcion F del menu-, asi que no habia nada que contar. Ahora se cuenta eso mismo.
        $script:Diagnostics['nativaInstall'] = [ordered]@{
            intento = $false; instalador = ''; versionInstalador = ''; quedoInstalada = $false
            versionDespues = ''; exitCode = $null; corriendo = $null
            motivo = ('no se intento instalar: el motor solo instala la Nativa desde el menu (opcion F). ' +
                      $(if ($script:NativaKit -and [bool]$script:NativaKit.listo) { 'El instalador esta disponible al lado del script.' }
                        else { 'Ademas no hay un instalador utilizable al lado del script.' }))
        }
        Add-Check -Id 'nativa.installed' -Layer 0 -Name $nombreNoInst -Status 'fail' -RootCauseCandidate $true -Plane 'fudo_config' `
            -Evidence @{ found = $false; enDisco = $false; soloRegistro = [bool]$install.soloRegistro
                         pwa = [bool]$install.pwa; reg = $install.regInfo; carpeta = [string]$install.carpeta
                         huella = $(if ($script:Diagnostics.Contains('nativaHuella')) { $script:Diagnostics['nativaHuella'] } else { $null }) } `
            -ArticleRef 'https://soporte.fu.do/es/articles/16419361' `
            -Recommendation $porQue
    } else {
        # Instalada pero apagada NO es causa raiz: es un native messaging host y con Fudo
        # cerrado no corre. Que NO este instalada (rama de arriba, status fail) si lo es.
        Add-Check -Id 'nativa.installed' -Layer 0 -Name $(if($procRunning){'App Nativa de Fudo instalada y corriendo'}else{'App Nativa de Fudo instalada (no corre ahora: arranca con Fudo)'}) `
            -Status $(if($procRunning){'ok'}else{'warn'}) `
            -RootCauseCandidate $false `
            -Evidence @{ paths = $install.paths; reg = $install.regInfo; running = $procRunning } `
            -Recommendation $(if($procRunning){''}else{'Esta instalada y no corriendo. Es lo esperado si Fudo no esta abierto en el navegador: la levanta el navegador cuando hace falta. Si Fudo SI esta abierto en esta PC y aun asi no corre, revisar bloqueo del antivirus.'})

        # 0b.1b Version: desde la firmada, el antivirus deja de ser un tema. Por debajo, la
        # accion de fondo es actualizar la Nativa y no pelearse con el antivirus cada vez.
        $verState = Get-NativaVersionState -Install $install
        $script:Diagnostics['nativaFirmada'] = $verState.firmada
        if ($verState.firmada -eq $false) {
            # v3.14: hasta la 3.13 esto solo AVISABA. Con la Nativa 0.0.18 en 10 de 24 corridas
            # del 03/09 y solo 6 en la 0.0.37, avisar no alcanzaba: si hay un instalador en la
            # PC (al lado del script, tipicamente el .msi de la version vigente) y declara una
            # version mas nueva, se actualiza. Nunca a ciegas: si el instalador no dice su
            # version, no se toca (instalar a ciegas puede DEGRADARLA, ya paso en este proyecto).
            $up = @{ aplicado = $false; motivo = 'no se intento' }
            if ($AutoFix) { $up = Update-FudoNativeFromLocal -Instalada ([string]$verState.version) -Corriendo ([bool]$procRunning) }
            $script:Diagnostics['nativaUpdate'] = $up
            if ([bool]$up.aplicado -and [bool]$up.subio) {
                Add-Check -Id 'nativa.sinFirmar' -Layer 0 -Name ("App Nativa actualizada de la v$($verState.version) a la v$($up.versionDespues)") `
                    -Status 'fixed' -RootCauseCandidate $false -Plane 'fudo_config' `
                    -Evidence @{ version = $verState.version; versionDespues = $up.versionDespues
                                 versionFirmada = $script:NativaVersionFirmada; instalador = $up.instalador } `
                    -ActionTaken ([string]$up.nota) -Reversible $true `
                    -ArticleRef 'https://soporte.fu.do/es/articles/16419361' `
                    -Recommendation ("Se actualizo la App Nativa a la v$($up.versionDespues) con el instalador que estaba en la PC. " +
                                     $(if ([bool]$up.quedaSinFirmar) {
                                            'OJO: esa version sigue siendo ANTERIOR a la v' + $script:NativaVersionFirmada + ', que es la primera firmada, asi que el antivirus todavia puede ponerla en cuarentena. Para cerrar el tema hace falta el instalador de la v' + $script:NativaVersionFirmada + ' al lado de FudoPrintDoctor.cmd. '
                                       } else {
                                            'Desde la v' + $script:NativaVersionFirmada + ' esta firmada, asi que el antivirus deja de ponerla en cuarentena. '
                                       }) +
                                     'Abrir Fudo en el navegador y mandar una comanda de prueba.')
            } elseif ([bool]$up.intento) {
                # v3.15, caso reportado por una asesora y reproducido en telemetria: el motor
                # ejecuto nativa.update_local dos veces sobre la misma PC, la version no se movio
                # de la 0.0.18, no reporto ninguna reparacion y el check quedo en 'warn' con el
                # MISMO texto que cuando no se intento nada. Falla en silencio: la persona lo
                # intento tres veces y termino reinstalando a mano.
                # Queda en 'warn' y no en 'fail' a proposito: una Nativa vieja no impide que la
                # impresora imprima, y un 'fail' aca volveria a bloquear el cierre de casos que
                # la v3.11 desbloqueo. Lo que cambia es que ahora se VE, con el motivo.
                Add-Check -Id 'nativa.sinFirmar' -Layer 0 -Name ("NO se pudo actualizar la App Nativa: sigue en la v$($verState.version)") `
                    -Status 'warn' -RootCauseCandidate $false -Plane 'fudo_config' `
                    -Evidence @{ version = $verState.version; versionFirmada = $script:NativaVersionFirmada
                                 intentoUpdate = [string]$up.motivo; instalador = [string]$up.instalador
                                 versionInstalador = [string]$up.versionInstalador
                                 exitCode = $up.exitCode; porQueNo = [string]$up.porQueNo
                                 nativaCorriendo = [bool]$up.nativaCorriendo } `
                    -ActionTaken ([string]$up.nota) -Reversible $true `
                    -ArticleRef 'https://soporte.fu.do/es/articles/16419361' `
                    -Recommendation ('Se intento actualizar la App Nativa de la v' + [string]$verState.version + ' a la v' + [string]$up.versionInstalador +
                                     ' con el instalador ' + [string]$up.instalador + ' y NO tomo: ' + [string]$up.porQueNo + '. ' +
                                     $(if ([bool]$up.nativaCorriendo) { 'Cerrar Fudo en el navegador (y el proceso de la App Nativa) y volver a correr el diagnostico, o ' } else { '' }) +
                                     'correr el instalador a mano desde la PC del cliente y verificar que la version cambie.')
            } else {
                Add-Check -Id 'nativa.sinFirmar' -Layer 0 -Name ("App Nativa desactualizada (v$($verState.version)): la nueva esta firmada y el antivirus no la bloquea") `
                    -Status 'warn' -RootCauseCandidate $false -Plane 'fudo_config' `
                    -Evidence @{ version = $verState.version; versionFirmada = $script:NativaVersionFirmada
                                 intentoUpdate = [string]$up.motivo; instalador = [string]$up.instalador
                                 versionInstalador = [string]$up.versionInstalador } `
                    -ArticleRef 'https://soporte.fu.do/es/articles/16419361' `
                    -Recommendation ("Esta PC tiene la Nativa v$($verState.version). Desde la v$($script:NativaVersionFirmada) la App Nativa esta firmada digitalmente, " +
                                     'asi que los antivirus dejan de ponerla en cuarentena. Si este cliente tuvo problemas de antivirus con la Nativa, ' +
                                     'actualizarla es la solucion de fondo: evita tener que agregar exclusiones en cada PC. ' +
                                     'El motor puede hacerlo solo: copiar el instalador (.msi) de la Nativa al lado de FudoPrintDoctor.cmd y volver a correr. ' +
                                     'No se actualizo ahora porque ' + [string]$up.motivo + '.')
            }
        } elseif ($verState.firmada -eq $true) {
            Add-Check -Id 'nativa.sinFirmar' -Layer 0 -Name ("App Nativa v$($verState.version): version firmada") -Status 'ok' -Plane 'fudo_config' `
                -Evidence @{ version = $verState.version; versionFirmada = $script:NativaVersionFirmada }
        }
    }

    # 0b.2 Amenazas/cuarentena de Defender sobre la Nativa
    # v3.12: el historial de detecciones de Defender no es la cuarentena viva. Si la Nativa
    # esta en disco no hay nada que restaurar, y reparar sobre un registro viejo dejaba esa
    # causa raiz en corridas de PCs sanas (6 corridas 3.11 con la 0.0.37 firmada y presente).
    $qNativa = Test-DefenderThreatActionable -Threats $av.fudoThreats `
        -Firmada $(if ($script:Diagnostics.Contains('nativaFirmada')) { $script:Diagnostics['nativaFirmada'] } else { $null }) `
        -Presente $installed
    if (@($av.fudoThreats).Count -gt 0 -and -not $qNativa.accionable) {
        # Se informa (el asesor tiene que saber que el antivirus la toco alguna vez) pero no
        # se repara y no compite como causa raiz.
        Add-Check -Id 'nativa.defenderQuarantine' -Layer 0 `
            -Name ('Defender registro detecciones sobre la Nativa en el pasado (' + @($av.fudoThreats).Count + '), pero hoy no esta en cuarentena') `
            -Status 'warn' -RootCauseCandidate $false -Plane 'fudo_config' `
            -Evidence @{ threats = $av.fudoThreats; motivo = [string]$qNativa.motivo
                         presenteDespues = [bool]$installed; historica = $true
                         pendientes = @($qNativa.pendientes).Count } `
            -Recommendation ('Windows Defender tiene detecciones registradas sobre la App Nativa, pero ' + [string]$qNativa.motivo +
                             '. No se toco la configuracion del antivirus: no habia nada que restaurar. Si este cliente vuelve a quedarse sin la Nativa, la solucion de fondo es actualizarla a la version firmada.')
    } elseif ($qNativa.accionable) {
        $exclPath = @($install.paths | Select-Object -First 1)
        $rem = Invoke-Remediation -Description 'Restaurar Nativa de cuarentena + agregar exclusiones quirurgicas de Defender' -Type 'defender.restore_exclude' -Target 'FudoNativa' `
            -Before "amenazas=$(@($av.fudoThreats).Count)" -After 'restaurada + excluida' -Fix {
                $notes = @()
                # Restaurar amenazas de Fudo desde cuarentena via MpCmdRun
                $mpcmd = Join-Path $env:ProgramData 'Microsoft\Windows Defender\Platform'
                $mpExe = $null
                try { $mpExe = Get-ChildItem -Path $mpcmd -Recurse -Filter 'MpCmdRun.exe' -ErrorAction SilentlyContinue | Select-Object -Last 1 } catch {}
                if (-not $mpExe) { $mpExe = Get-Item "$env:ProgramFiles\Windows Defender\MpCmdRun.exe" -ErrorAction SilentlyContinue }
                foreach ($t in $av.fudoThreats) {
                    if ($mpExe -and $t.id) {
                        try { & $mpExe.FullName -Restore -Name $t.id 2>&1 | Out-Null; $notes += "restore $($t.id)" } catch { $notes += "restore fallo $($t.id)" }
                    }
                }
                # Exclusiones quirurgicas (ruta + proceso) en vez de desactivar Defender
                if ($UseDefenderExclusions) {
                    foreach ($p in $install.paths) {
                        try { Add-MpPreference -ExclusionPath $p -ErrorAction SilentlyContinue; $notes += "excl path $p" } catch {}
                    }
                    try { Add-MpPreference -ExclusionProcess "$FudoAppProcess*.exe" -ErrorAction SilentlyContinue; $notes += 'excl process' } catch {}
                }
                ($notes -join ' | ')
            }
        # Restaurar de cuarentena no garantiza que la Nativa vuelva: si el ejecutable sigue sin
        # estar, marcarlo 'fixed' es un falso positivo (se vio 'fixed' con nativa.installed en
        # fail y la transicion en sigue_fallando dos corridas seguidas).
        $volvio = $false
        # v3.7: restaurar de cuarentena puede devolver un binario VIEJO. Se vio 0.0.36 -> 0.0.18
        # despues de una restauracion, y 0.0.18 circulando en varias PCs. Si la version baja, la
        # Nativa quedo degradada: no alcanza con 'restaurada', hay que reinstalarla.
        $verAntes   = ''
        $verDespues = ''
        $degradada  = $false
        try { $verAntes = [string](@($install.regInfo)[0].version) } catch {}
        if ($rem.applied) {
            Start-Sleep -Milliseconds 800
            try {
                $reCheck = Find-FudoNativeInstall
                $volvio = ((@($reCheck.paths).Count -gt 0) -or (@($reCheck.regInfo).Count -gt 0))
                try { $verDespues = [string](@($reCheck.regInfo)[0].version) } catch {}
            } catch {}
        }
        $degradada = Test-NativaDegradada -Antes $verAntes -Despues $verDespues
        # v3.17 (bitacora semanal 31/08-06/09): la restauracion funcionaba y el caso escalaba
        # igual. 4 PCs con nativa.installed=fail, causa 'App Nativa de Fudo NO instalada' y
        # needs_escalation; en dos de ellas la corrida siguiente -1 y 3 minutos despues- ya
        # traia la 0.0.37. El motivo: nativa.installed se registra en la capa 0b.1, ANTES de
        # esta restauracion, y nadie lo volvia a mirar. El veredicto salia de una foto vieja de
        # la PC, el mismo bug que la 3.11 corrigio para las colas.
        if ($rem.applied -and $volvio -and -not $degradada) {
            [void](Update-CheckFinding -Id 'nativa.installed' -Status 'fixed' -RootCauseCandidate $false `
                -Name ('App Nativa de Fudo restaurada de la cuarentena del antivirus' + $(if ($verDespues) { " (v$verDespues)" } else { '' })) `
                -ActionTaken 'restaurada desde la cuarentena de Defender en esta corrida' `
                -Recommendation ('La Nativa no estaba porque el antivirus la habia puesto en cuarentena, y se restauro en esta misma corrida. ' +
                                 'Abrir Fudo en el navegador y mandar una comanda de prueba. Si vuelve a desaparecer, la solucion de fondo es actualizarla a la version firmada.') `
                -EvidenceExtra @{ restauradaEnEstaCorrida = $true; versionDespues = [string]$verDespues })
            # La version post-reparacion es la que tiene que viajar: antes se reportaba el vacio
            # de antes de restaurar, asi que en la planilla la PC figuraba sin Nativa.
            if ($verDespues) { $script:Diagnostics['nativaVersionPostFix'] = [string]$verDespues }
        }
        Add-Check -Id 'nativa.defenderQuarantine' -Layer 0 `
            -Name $(if (-not $rem.applied) { 'Nativa en cuarentena de Windows Defender' }
                    elseif ($degradada)    { "Nativa restaurada de cuarentena pero con una version mas vieja ($verAntes -> $verDespues)" }
                    elseif ($volvio)       { 'Nativa restaurada de la cuarentena de Defender' }
                    else                   { 'Nativa en cuarentena: se restauro pero sigue sin aparecer' }) `
            -Status $(if (-not $rem.applied) { 'fail' } elseif ($degradada) { 'warn' } elseif ($volvio) { 'fixed' } else { 'warn' }) -RootCauseCandidate $true `
            -Evidence @{ threats = $av.fudoThreats; presenteDespues = $volvio
                         versionAntes = $verAntes; versionDespues = $verDespues; degradada = $degradada } -ActionTaken $rem.note `
            -Recommendation $(if ($degradada) {
                    "La restauracion devolvio una version mas vieja de la Nativa ($verAntes -> $verDespues): Defender habia puesto en cuarentena el binario actualizado y lo que volvio es el anterior. " +
                    'NO darlo por resuelto: reinstalar la App Nativa desde la version vigente y recien despues verificar que la exclusion de Defender quedo puesta (ruta + proceso).'
                } elseif ($volvio) {
                    'Se restauro de la cuarentena y se agregaron exclusiones (ruta + proceso). Reiniciar la Nativa y probar una comanda.'
                } else {
                    'Se restauro de la cuarentena y se excluyo en Defender, pero la Nativa sigue sin aparecer instalada: el antivirus ya la habia borrado. Hay que REINSTALAR la App Nativa y despues verificar que el antivirus no la vuelva a tocar.' +
                    $(try {
                        $hPrev = Get-LocalRunHistory
                        if ([string]$hPrev.ultimaCausa -match '(?i)cuarentena') {
                            ' OJO: esto ya se intento en la corrida anterior de esta PC y no alcanzo, asi que no tiene sentido volver a correr el diagnostico esperando otro resultado: hay que reinstalar la Nativa.'
                        } else { '' }
                      } catch { '' })
                })
    } elseif ($installed -and -not $procRunning -and $av.defender -and
              ($script:Diagnostics['nativaFirmada'] -ne $true)) {
        # v3.17: aca el motor le agregaba exclusiones preventivas al antivirus del cliente. Ya no.
        #
        # Historia del disparador: la 3.10 lo apago para las Nativas firmadas y la 3.12 apago la
        # restauracion sobre detecciones historicas, pero la rama siguio viva para las Nativas
        # por debajo de 0.0.37. La bitacora semanal encontro dos PCs 3.14 (nativaVersion 0.0.19
        # y 0.0.24) donde el motor toco la configuracion del antivirus teniendo la causa raiz en
        # el hardware: printer.disconnected y hw.disconnected.
        #
        # Y mirando el if/elseif completo el caso es peor de lo que parecia: la rama de arriba se
        # queda con "hay detecciones y la Nativa esta presente" y la del medio con "hay
        # detecciones y no esta", asi que a ESTA rama solo se llega con CERO detecciones de
        # Defender sobre la Nativa. O sea que el motor modificaba el antivirus de PCs donde
        # Defender nunca habia tocado la Nativa, y el unico disparador real era que estuviera
        # apagada -que con Fudo cerrado es el estado NORMAL, como ya documentaba el codigo de al
        # lado-. No habia nada que prevenir.
        #
        # Estar sin firmar por si solo no alcanza: eso lo informa nativa.sinFirmar, y su solucion
        # de fondo es actualizar la Nativa, no pelearse con el antivirus en cada PC. Y si el
        # antivirus se la come mas adelante, nativa.defenderQuarantine lo detecta en la corrida
        # siguiente y ahi si hay algo concreto que reparar.
        $exc = Test-DefenderExclusionNeeded -Presente $installed -Corriendo $procRunning `
                    -Firmada $(if ($script:Diagnostics.Contains('nativaFirmada')) { $script:Diagnostics['nativaFirmada'] } else { $null }) `
                    -Detecciones $av.fudoThreats -DefenderActivo $av.defender
        Add-Check -Id 'nativa.defenderExclusion' -Layer 0 `
            -Name 'No se toco el antivirus: la App Nativa esta en disco' `
            -Status 'ok' -RootCauseCandidate $false `
            -Evidence @{ realTime = $av.realTime; paths = $install.paths
                         detecciones = @($av.fudoThreats).Count; excluida = $false
                         motivo = [string]$exc.motivo } `
            -Recommendation ('No se modifico la configuracion del antivirus porque ' + [string]$exc.motivo + '. ' +
                             'Que la Nativa no este corriendo es lo esperado con Fudo cerrado. Si esta version le da problemas de antivirus a ' +
                             'este cliente, la solucion de fondo es actualizarla a la version firmada.')
    }

    # 0b.3 Antivirus de terceros (Avast, etc.): no scriptable -> guiado/escalar
    if (@($av.thirdParty).Count -gt 0) {
        Add-Check -Id 'nativa.thirdPartyAV' -Layer 0 -Name 'Antivirus de terceros presente' -Status 'warn' -RootCauseCandidate (-not $procRunning) -Plane 'hardware' `
            -Evidence @{ products = $av.thirdParty } -Reversible $true `
            -Recommendation "Detectado $($av.thirdParty -join ', '). Puede poner la Nativa en cuarentena. Requiere accion guiada en el AV (excluir/restaurar), no automatizable de forma segura."
    }

    # 0b.4 Los dos eslabones que faltaban entre "la Nativa esta instalada" y "Fudo imprime".
    # Los dos salieron de casos de asesores de la misma semana y los dos terminaban igual: una
    # PC con todo verde, el asesor escalando, y la comanda sin salir.
    #   - El navegador encuentra a la Nativa por una clave de registro que apunta a un manifest.
    #     Si esa clave no esta, la extension no le puede hablar. Eso es lo que arregla el
    #     "cerra sesion y volve a entrar" que pide la web app -y tambien, sin cerrar sesion,
    #     ejecutar la Nativa una vez-.
    #   - Y si la extension no esta puesta en el navegador, no hay quien le hable.
    if ($installed) {
        Write-StepDetail 'revisando el registro de la Nativa en el navegador y la extension'
        $sesion = Get-SesionInteractiva
        $script:Diagnostics['sesionUsuario'] = $sesion
        $nmh = Get-NativeMessagingState
        $ext = Get-FudoExtensionState -Ids @($nmh.extensionIds)
        $script:Diagnostics['nativaHost'] = $nmh
        $script:Diagnostics['fudoExtension'] = $ext

        if ([bool]$sesion.otroPerfil) {
            # No se puede concluir NI reparar: el registro del host y las extensiones viven en el
            # perfil del usuario, y el motor esta corriendo con otra cuenta. Registrar aca seria
            # registrarlo para el administrador, y el Chrome del cliente no se enteraria.
            Add-Check -Id 'nativa.hostRegistrado' -Layer 0 -Name 'No se pudo revisar el registro de la Nativa (el motor corre con otro usuario)' `
                -Status 'skipped' -RootCauseCandidate $false -Plane 'fudo_config' `
                -Evidence @{ skipReason = 'otro_perfil'; usuarioMotor = [string]$sesion.usuarioMotor
                             usuarioSesion = [string]$sesion.usuarioSesion } `
                -Recommendation ('El diagnostico corre como ' + [string]$sesion.usuarioMotor + ' y la sesion de Windows es de ' + [string]$sesion.usuarioSesion +
                                 '. El registro de la Nativa en el navegador y las extensiones son por usuario, asi que desde aca se estaria mirando el perfil equivocado. ' +
                                 'Correr el diagnostico desde la sesion del cliente (o revisar a mano en su Chrome) antes de sacar conclusiones sobre la Nativa.')
        } else {
            # Host registrado
            $reg = @{ aplicado = $false; intento = $false; registrado = [bool]$nmh.registrado; motivo = 'no se intento'; nota = '' }
            if ((-not $nmh.registrado) -and $AutoFix) {
                $reg = Register-FudoNativeHost -Exe ([string]$install.exe)
                $nmh = $reg.estado
                $script:Diagnostics['nativaHost'] = $nmh
                # El manifest recien escrito puede traer ids nuevos: releer la extension con esos.
                $ext = Get-FudoExtensionState -Ids @($nmh.extensionIds)
                $script:Diagnostics['fudoExtension'] = $ext
            }
            $script:Diagnostics['nativaHostRegistro'] = $reg
            if ([bool]$nmh.registrado) {
                Add-Check -Id 'nativa.hostRegistrado' -Layer 0 `
                    -Name $(if ([bool]$reg.aplicado) { 'App Nativa registrada en el navegador por el motor' } else { 'App Nativa registrada en el navegador' }) `
                    -Status $(if ([bool]$reg.aplicado) { 'fixed' } else { 'ok' }) -RootCauseCandidate $false -Plane 'fudo_config' `
                    -Evidence @{ navegadores = @($nmh.navegadores); manifest = [string]$nmh.manifest
                                 exe = [string]$nmh.exeDelManifest; extensionIds = @($nmh.extensionIds)
                                 pendientes = @($nmh.pendientes) } `
                    -ActionTaken ([string]$reg.nota) -Reversible $true `
                    -Recommendation $(if ([bool]$reg.aplicado) {
                            'La Nativa estaba instalada pero el navegador no la tenia registrada, que es lo que se arregla cerrando sesion en Fudo y volviendo a entrar. Se resolvio ejecutando la Nativa una vez, sin cerrar sesion. Recargar la pestana de Fudo y mandar una comanda de prueba.'
                        } else { '' })
            } else {
                # fail (que bloquea el cierre del caso) SOLO si hay evidencia de que en esta
                # cuenta hay un navegador Chromium: ahi "no esta registrada" es un hecho. Si no
                # se encontro ningun perfil, puede ser un cliente que usa otro navegador y el
                # motor no tiene con que afirmarlo: queda en warn, sigue siendo candidata a causa
                # raiz y se ve igual, pero no vuelve a bloquear cierres como pasaba antes de la
                # 3.11 con los chequeos del lado de Fudo.
                $hayNavegador = ([int]$ext.perfilesVistos -gt 0)
                Add-Check -Id 'nativa.hostRegistrado' -Layer 0 -Name 'La App Nativa esta instalada pero el navegador no la tiene registrada' `
                    -Status $(if ($hayNavegador) { 'fail' } else { 'warn' }) -RootCauseCandidate $true -Plane 'fudo_config' `
                    -Evidence @{ navegadores = @($nmh.navegadores); pendientes = @($nmh.pendientes)
                                 manifest = [string]$nmh.manifest; exe = [string]$nmh.exeDelManifest
                                 exeExiste = [bool]$nmh.exeExiste; intento = [bool]$reg.intento
                                 motivo = [string]$reg.motivo } `
                    -ActionTaken ([string]$reg.nota) -Reversible $true `
                    -ArticleRef 'https://soporte.fu.do/es/articles/16419361' `
                    -Recommendation ('La Nativa esta en disco pero el navegador no la encuentra: falta la clave que la registra, asi que Fudo se comporta como si no estuviera instalada. ' +
                                     $(if ([bool]$reg.intento) { 'El motor intento registrarla y no quedo (' + [string]$reg.motivo + '). ' } else { '' }) +
                                     'Se arregla ejecutando una vez ' + $(if ([string]$install.exe) { [string]$install.exe } else { 'el archivo fudo_native_extension de %LOCALAPPDATA%\Fudo' }) +
                                     ', o cerrando sesion en Fudo y volviendo a entrar. Despues recargar la pestana de Fudo y mandar una comanda de prueba.')
            }
            # Extension del navegador
            if ([int]$ext.perfilesVistos -eq 0) {
                Add-Check -Id 'fudo.extension' -Layer 0 -Name 'No se pudo revisar la extension de Fudo (no se encontro Chrome ni Edge en este perfil)' `
                    -Status 'skipped' -RootCauseCandidate $false -Plane 'fudo_config' `
                    -Evidence @{ skipReason = 'sin_navegador'; ids = @($ext.ids) } `
                    -Recommendation 'No se encontraron perfiles de Chrome, Edge ni Chromium en esta cuenta de Windows, asi que no se puede saber si la extension de Fudo esta puesta. Revisarlo a mano en el navegador que use el cliente.'
            } elseif ([bool]$ext.instalada) {
                Add-Check -Id 'fudo.extension' -Layer 0 -Name 'Extension de Fudo instalada en el navegador' -Status 'ok' `
                    -RootCauseCandidate $false -Plane 'fudo_config' `
                    -Evidence @{ id = [string]$ext.encontrada; navegador = [string]$ext.navegador
                                 perfil = [string]$ext.perfil; perfilesVistos = [int]$ext.perfilesVistos }
            } else {
                # Mismo criterio que arriba: se afirma con evidencia. Si la Nativa esta registrada
                # para un navegador Chromium, es que Fudo corre ahi, y que falte la extension es
                # un hecho -> fail. Si no esta registrada en ningun lado no sabemos en que
                # navegador trabaja el cliente (la Nativa tambien soporta Firefox): warn.
                $navegadorSeguro = [bool](@($nmh.navegadores | Where-Object { $_ -ne 'Firefox' }).Count -gt 0)
                Add-Check -Id 'fudo.extension' -Layer 0 -Name 'Falta la extension de Fudo en el navegador' `
                    -Status $(if ($navegadorSeguro) { 'fail' } else { 'warn' }) `
                    -RootCauseCandidate $true -Plane 'fudo_config' `
                    -Evidence @{ ids = @($ext.ids); perfilesVistos = [int]$ext.perfilesVistos
                                 navegadoresConHost = @($nmh.navegadores) } `
                    -ArticleRef 'https://soporte.fu.do/es/articles/16419361' `
                    -Recommendation ('La App Nativa esta instalada pero la extension de Fudo no aparece en ninguno de los ' + [int]$ext.perfilesVistos +
                                     ' perfil(es) de navegador de esta cuenta. Sin la extension nadie le habla a la Nativa y la comanda no sale, ' +
                                     'por mas que todo lo demas este bien. Agregarla desde ' + [string]$script:FudoExtensionUrl +
                                     ' y recargar la pestana de Fudo. Un asesor confirmo que agregandola la Nativa levanta sola.')
            }
        }
    }
}

# ---------------------------------------------------------------------------
# Impresoras virtuales / de sistema: NUNCA son objetivo de diagnostico.
# Un ticket "impreso" en Microsoft Print to PDF da falso OK de hardware.
# ---------------------------------------------------------------------------
$script:VirtualNamePatterns = @(
    'Microsoft Print to PDF','Microsoft XPS Document Writer','OneNote','Send To OneNote',
    'Impresora virtual protegida','Fax','Adobe PDF','PDF24','CutePDF','PDFCreator','Bullzip',
    'doPDF','Foxit.*PDF','Nitro.*PDF','novaPDF','PrimoPDF','Snagit','AnyDesk','TeamViewer',
    'WPS PDF','Print to Evernote','Guardar como PDF','Microsoft Shared Fax','Quicken PDF','ImagePrinter'
)
$script:VirtualDriverPatterns = @(
    'Microsoft Print To PDF','Microsoft XPS Document Writer','Send to Microsoft OneNote',
    'Microsoft Shared Fax Driver','PDF','XPS'
)
$script:VirtualPortPatterns = @(
    '^PORTPROMPT:','^nul:?$','^NUL$','^SHRFAX:','^XPSPort:','^FILE:','^Microsoft\.Office\.OneNote',
    '^PDF','^C:\\','^\\\\'
)

# ---------------------------------------------------------------------------
# Identificacion de impresoras fisicas: marca, modelo y que driver corresponde
# ---------------------------------------------------------------------------
$script:UsbVendorMap = [ordered]@{
    '04B8' = 'Epson';  '1504' = 'Bixolon';       '0519' = 'Star Micronics'; '2730' = 'Citizen'
    '0A5F' = 'Zebra';  '0DD4' = 'Custom';        '04E8' = 'Samsung';        '03F0' = 'HP'
    '04A9' = 'Canon';  '04F9' = 'Brother';       '0924' = 'Xerox';          '043D' = 'Lexmark'
    '0416' = 'Generica (chipset Winbond: XPrinter / 3nStar / similares)'
    '0483' = 'Generica (chipset STM)'
    '1FC9' = 'Generica (chipset NXP)'
    '1A86' = 'Adaptador USB-serie (CH340)'
    '067B' = 'Adaptador USB-serie (Prolific)'
}
# Marcas con driver propio que vale la pena usar (corte de papel, velocidad, utilitarios)
# Herramientas de configuracion de red por marca. Los nombres de los ejecutables salen del
# empaquetado que ya usa el equipo (Delitools > NetConfigTools): no se adivinan, y ninguno se
# llama como uno esperaria -la de Epson es ENConfig.exe, no EpsonNetConfig.exe-.
# Ninguna es un .exe suelto: todas necesitan su carpeta al lado (DLLs, .ini, Resources), asi que
# hay que lanzarlas CON el directorio de trabajo puesto ahi o arrancan rotas.
$script:NetConfigTools = @(
    [ordered]@{ marca = 'Epson';   carpeta = 'EPSON';    exe = 'ENConfig.exe'
                nota = 'EpsonNet Config descubre las impresoras Epson de la red aunque esten en otra subred, sin conectarlas al PC. La IP se cambia desde ahi.' },
    [ordered]@{ marca = 'Bixolon'; carpeta = 'BIXOLON';  exe = 'NetConfiguration.exe'
                nota = 'La utilidad de red de Bixolon lista las impresoras de la marca y permite cambiarles la IP.' },
    [ordered]@{ marca = 'Sam4s';   carpeta = 'SAM4S';    exe = 'GIANT&GCUBE Tool.exe'
                nota = 'Giant & GCube Tool: la configuracion de red esta en la seccion de Ethernet.' },
    [ordered]@{ marca = 'XPrinter'; carpeta = 'XPRINTER'; exe = 'XPrinter.exe'
                nota = 'No es una utilidad de red: es la herramienta general de la impresora. La IP se cambia en la pestana de configuracion Ethernet.' },
    [ordered]@{ marca = '3nStar';  carpeta = '3NSTAR';   exe = 'POS Printer Test.exe'
                nota = 'Misma herramienta OEM que la de XPrinter (comparten EnCodeQr.dll): sirve para las dos marcas. La IP se cambia en la pestana de configuracion Ethernet.' }
)
# Prefijos OUI (los 3 primeros bytes de la MAC) por fabricante, para identificar una impresora
# descubierta por barrido, donde no hay nombre: solo IP y MAC.
# ARRANCA VACIO A PROPOSITO. Poner OUIs sin verificarlos seria adivinar el fabricante, que es
# justo la familia de falsos positivos que este proyecto arrastra. Se llena con las MAC reales
# que empiecen a llegar por telemetria (campo 'mac' de impresorasEnRed): cada vez que una marca
# quede confirmada, se agrega su prefijo aca. Mientras este vacio, la identidad sale del propio
# protocolo (Get-EscPosIdentity) y el OUI viaja como dato crudo para poder armar la tabla.
$script:PrinterOuis = @{}
# IPs secundarias que agrego esta corrida y hay que sacar al terminar.
$script:TempIpsAdded = New-Object System.Collections.ArrayList
$script:BrandsWithOemDriver = @('Epson','Bixolon','Star Micronics','Citizen','Zebra','Custom','Sam4s','Sewoo','Posiflex','Hasar')
$script:BrandSupportUrl = [ordered]@{
    'Epson'          = 'https://www.epson.com.ar'
    'Bixolon'        = 'https://www.bixolon.com'
    'Star Micronics' = 'https://www.starmicronics.com'
    'Citizen'        = 'https://www.citizen-systems.co.jp'
    'Zebra'          = 'https://www.zebra.com'
}

function Get-DeviceIdentity {
    <#
      A partir de un device del inventario devuelve marca / modelo / VID-PID / etiqueta legible.
      Fuentes: nombre amigable, InstanceId (USBPRINT\<MARCA><MODELO>\... o USB\VID_xxxx&PID_xxxx).
    #>
    param($Device)
    $name = ''; $inst = ''
    try { $name = [string]$Device.name } catch {}
    try { $inst = [string]$Device.instanceId } catch {}

    # OJO: $pid es variable automatica read-only en PowerShell (Process Id) -> usar $devPid
    $vid = ''; $devPid = ''
    if ($inst -match '(?i)VID_([0-9A-F]{4})') { $vid = $Matches[1].ToUpper() }
    if ($inst -match '(?i)PID_([0-9A-F]{4})') { $devPid = $Matches[1].ToUpper() }

    # marca: primero por texto (nombre o instanceId), despues por VID
    $brand = ''
    $probe = ($name + ' ' + $inst)
    foreach ($b in $script:PosBrands) {
        if ($probe -match [regex]::Escape($b)) {
            $brand = switch -Regex ($b) {
                '(?i)^epson|TM-T|TM20' { 'Epson' }
                '(?i)^bixolon'         { 'Bixolon' }
                '(?i)^citizen'         { 'Citizen' }
                '(?i)^sewoo'           { 'Sewoo' }
                '(?i)^sam4s'           { 'Sam4s' }
                '(?i)^hasar'           { 'Hasar' }
                default                { $b }
            }
            break
        }
    }
    if (-not $brand -and $vid -and $script:UsbVendorMap.Contains($vid)) { $brand = [string]$script:UsbVendorMap[$vid] }

    # modelo: lo que quede del nombre / del segmento de USBPRINT.
    # Los nombres que pone Windows cuando no sabe que es ('USB Printing Support', etc.) no son modelo.
    $model = ''
    # 'No Printer Attached', 'Printer', 'USB Printing Support'... son etiquetas del driver, no modelos.
    if ($name -and ($name -notmatch '(?i)^(usb printing support|soporte de impresi|compatible usb|unknown|desconocid|dispositivo (compuesto|usb)|generic usb|no printer attached|sin impresora|printer|impresora)\s*$')) { $model = $name }
    elseif ($inst -match '(?i)^USBPRINT\\([^\\]+)') { $model = ($Matches[1] -replace '_+', ' ').Trim() }
    $brandFirst = ''
    if ($brand) { $brandFirst = ($brand -split ' ')[0] }
    if ($model -and $brandFirst -and ($model -match ('(?i)^' + [regex]::Escape($brandFirst)))) {
        $model = ($model -replace ('(?i)^' + [regex]::Escape($brandFirst)), '').Trim(' -_')
    }

    $label = ''
    if ($brand -match '^Generica') {
        $label = 'Impresora generica' + $(if ($vid) { " [VID_$vid]" } else { '' })
        if ($model) { $label = "$model (generica" + $(if ($vid) { " VID_$vid" } else { '' }) + ')' }
    }
    elseif ($brand -match '^Adaptador') { $label = $brand }
    elseif ($brand -and $model) { $label = "$brand $model" }
    elseif ($brand)             { $label = $brand }
    elseif ($model)             { $label = $model }
    else                        { $label = 'Impresora sin identificar' + $(if ($vid) { " [VID_$vid]" } else { '' }) }

    return [ordered]@{
        label = $label; brand = $brand; model = $model; vid = $vid; pid = $devPid
        hasOemDriver = [bool](@($script:BrandsWithOemDriver | Where-Object { $brand -like "$_*" }).Count -gt 0)
        vendorUrl = $(if ($brand -and $script:BrandSupportUrl.Contains($brand)) { [string]$script:BrandSupportUrl[$brand] } else { '' })
    }
}

function Get-InstalledDriverForBrand {
    <# Devuelve el nombre de un driver ya instalado en Windows que corresponda a la marca, o ''. #>
    param([string]$Brand)
    if (-not $Brand) { return '' }
    $key = ($Brand -split ' ')[0]
    if (-not $key) { return '' }
    $drivers = @()
    try { $drivers = @(Get-PrinterDriver -ErrorAction Stop | ForEach-Object { [string]$_.Name }) } catch {}
    foreach ($d in $drivers) {
        if ($d -match [regex]::Escape($key)) { return $d }
    }
    return ''
}

function Get-DriverPlan {
    <#
      Para un device fisico decide que driver corresponde:
        oem_instalado   -> la marca tiene driver propio y YA esta en Windows: usarlo
        oem_recomendado -> la marca tiene driver propio pero no esta instalado
        generico        -> impresora generica/desconocida: "Generic / Text Only" alcanza
    #>
    param($Identity)
    $oem = Get-InstalledDriverForBrand -Brand ([string]$Identity.brand)
    if ($oem) {
        return [ordered]@{
            kind = 'oem_instalado'; driverName = $oem
            note = "El driver de $($Identity.brand) ya esta instalado en Windows ('$oem'): se usa ese."
        }
    }
    if ($Identity.hasOemDriver) {
        $url = [string]$Identity.vendorUrl
        return [ordered]@{
            kind = 'oem_recomendado'; driverName = ''
            note = ("$($Identity.label) tiene driver propio de $($Identity.brand). Para comandas ESC/POS el generico de texto " +
                    "suele alcanzar, pero si el modelo necesita corte automatico o el generico falla, instalar el driver oficial" +
                    $(if ($url) { " ($url)" } else { '' }) + '.')
        }
    }
    return [ordered]@{
        kind = 'generico'; driverName = ''
        note = "$($Identity.label): no tiene driver propio relevante. El inbox 'Generic / Text Only' (Generico / Solo texto) es el correcto para comandas ESC/POS."
    }
}

function Test-IsVirtualPrinter {
    <# Devuelve @{ isVirtual = $true/$false; reason = '...' } #>
    param($P)
    $name = ''; $drv = ''; $port = ''
    try { $name = [string]$P.Name } catch {}
    try { $drv  = [string]$P.DriverName } catch {}
    try { $port = [string]$P.PortName } catch {}
    foreach ($pat in $script:VirtualNamePatterns)   { if ($name -match $pat) { return @{ isVirtual = $true; reason = "nombre coincide con impresora virtual ($pat)" } } }
    foreach ($pat in $script:VirtualDriverPatterns) { if ($drv  -match $pat) { return @{ isVirtual = $true; reason = "driver virtual ($drv)" } } }
    foreach ($pat in $script:VirtualPortPatterns)   { if ($port -match $pat) { return @{ isVirtual = $true; reason = "puerto no fisico ($port)" } } }
    return @{ isVirtual = $false; reason = '' }
}

function Test-IsPosPrinter {
    <#
      Heuristica para COLAS de Windows (no para hardware): el nombre o el driver sugieren
      una termica/POS. Usa limites de palabra para no matchear 'Generic USB Hub' o
      'USB Composite Device' (el token 'POS' esta dentro de 'com-POS-ite').
    #>
    param($P)
    $probe = ''
    try { $probe = "{0} {1}" -f [string]$P.Name, [string]$P.DriverName } catch {}
    if (-not $probe) { return $false }
    if ($probe -match '(?i)Generic\s*/\s*Text') { return $true }
    if ($probe -match $script:PrinterWordRx) { return $true }
    foreach ($b in $script:PosBrands) {
        $esc = [regex]::Escape($b)
        # marcas cortas o ambiguas exigen limite de palabra
        if ($probe -match ('(?i)(^|[^A-Za-z0-9])' + $esc + '([^A-Za-z0-9]|$)')) { return $true }
    }
    return $false
}

# ---------------------------------------------------------------------------
# LAYER 1a - INVENTARIO DE HARDWARE (Administrador de dispositivos + puertos)
# Se corre ANTES de elegir impresora: primero saber si hay fierro conectado.
# ---------------------------------------------------------------------------
function Get-PresentDeviceIds {
    <#
      InstanceIds de los dispositivos PRESENTES ahora mismo.
      Clave: el registro Enum\USBPRINT guarda TODA impresora que estuvo conectada alguna vez,
      asi que sin este cruce una impresora desenchufada sigue figurando como conectada.
    #>
    if ($null -ne $script:PresentIds) { return $script:PresentIds }
    $set = @{}
    $ok = $false
    try {
        foreach ($d in @(Get-CimInstance Win32_PnPEntity -ErrorAction Stop)) {
            $id = [string]$d.PNPDeviceID
            if ($id) { $set[$id.ToUpper()] = $true }
        }
        $ok = $true
    } catch {}
    if (-not $ok) {
        try {
            foreach ($d in @(Get-PnpDevice -PresentOnly -ErrorAction Stop)) {
                $id = [string]$d.InstanceId
                if ($id) { $set[$id.ToUpper()] = $true }
            }
            $ok = $true
        } catch {}
    }
    $script:PresentIdsOk = $ok
    $script:PresentIds   = $set
    return $set
}

function Get-CompatibleIdList {
    <# CompatibleIDs del device. La clase USB 07h ('USB\Class_07') es la senal canonica de impresora. #>
    param($WmiEntity, [string]$InstanceId)
    $ids = @()
    if ($WmiEntity) {
        try { $ids = @($WmiEntity.CompatibleID | Where-Object { $_ }) } catch {}
    }
    if (@($ids).Count -eq 0 -and $InstanceId) {
        try { $ids = @((Get-PnpDeviceProperty -InstanceId $InstanceId -KeyName 'DEVPKEY_Device_CompatibleIds' -ErrorAction Stop).Data | Where-Object { $_ }) } catch {}
    }
    return @($ids)
}

# Palabras que SI hablan de impresora, y palabras que la descartan de plano.
$script:PrinterWordRx    = '(?i)\b(printer|impresora|thermal|termica|receipt|ticket|comandera|usbprint|escpos|esc/pos)\b|\bPOS\b|\bPOS-?\d|\b(xp-?\d{2,3}|srp-?\d{2,3}|rpt-?\d{2,3}|tm-?[tu]?\d{2,3}|5890|80c|58mm|80mm)\b'
$script:NonPrinterWordRx = '(?i)\b(mouse|mice|keyboard|teclado|hub|composite|compuesto|camera|webcam|audio|speaker|headset|micro[fp]ono|mass storage|almacenamiento|disk|disco|flash|bluetooth|wireless receiver|receptor|hid|human interface|joystick|gamepad|scanner|escaner|network|ethernet|wi-?fi|modem|card reader|lector de tarjetas|fingerprint|monitor|display|touch|graphics|serial converter|root hub|controlador de host|host controller)\b'
# VIDs de fabricantes de impresoras: valen como senal por si solos.
$script:PrinterVids = @('04B8','1504','0519','2730','0A5F','0DD4','03F0','04A9','04F9','0924','043D','04E8')

function Test-IsDirectoUsbDevice {
    <#
      La impresora, esta manejada por un driver de acceso directo (WinUSB / libusb, lo que deja
      Zadig)? Esas impresoras NO tienen cola de Windows y no la necesitan: Fudo les habla directo
      por USB -en la ficha de Fudo figuran como "Directo USB" en vez de "driver del sistema
      operativo"-, y las instala soporte de nivel 2 a proposito.
      Importa porque el motor esta construido sobre el supuesto contrario ("si no hay cola, hay
      que crearla"): sin esto le hace un replug por software a un dispositivo que esta andando.
      El descriptor USB no cambia con Zadig, asi que estas impresoras se siguen detectando como
      impresoras por clase 07h o por VID; lo unico que cambia es el driver que las atiende.
    #>
    param([string]$Service)
    return [bool]($Service -match '(?i)^(winusb|libusb0|libusbk|libusb)$')
}

function Test-IsPrinterDevice {
    <#
      Decide si un dispositivo USB es realmente una impresora, con la razon y el nivel de certeza.
      Evita el clasico falso positivo de tomar un mouse o un "USB Composite Device" por una POS.

      Senales, de mas fuerte a mas debil:
        alta   - InstanceId empieza con USBPRINT\ (interfaz de impresora USB creada por usbprint.sys)
        alta   - PNPClass 'Printer' / Service 'usbprint'
        alta   - CompatibleID contiene USB\Class_07 (clase USB 07h = Printer, definida por el estandar)
        media  - VID de un fabricante de impresoras (Epson, Bixolon, Star, Citizen, Zebra, ...)
        baja   - el nombre habla de impresora (printer / impresora / termica / POS / comandera)
      Cualquier palabra de no-impresora (mouse, hub, composite, audio, ...) descarta,
      salvo que exista una senal alta.
    #>
    param([string]$Name, [string]$InstanceId, [string]$PnpClass, [string]$Service, [string[]]$CompatibleIds)

    $probe = "$Name $InstanceId"
    $compat = (@($CompatibleIds) -join ' ')

    if ($InstanceId -match '(?i)^USBPRINT\\') { return @{ isPrinter = $true; confidence = 'alta'; reason = 'interfaz USBPRINT (usbprint.sys)' } }
    if ($PnpClass -eq 'Printer')              { return @{ isPrinter = $true; confidence = 'alta'; reason = 'clase de dispositivo Printer' } }
    if ($Service -match '(?i)^usbprint$')     { return @{ isPrinter = $true; confidence = 'alta'; reason = 'driver usbprint' } }
    if ($compat -match '(?i)USB\\Class_07')   { return @{ isPrinter = $true; confidence = 'alta'; reason = 'clase USB 07h (Printer)' } }

    # Descartes explicitos: sin senal alta, un mouse/hub/composite no es impresora
    if ($Name -match $script:NonPrinterWordRx -and $Name -notmatch $script:PrinterWordRx) {
        return @{ isPrinter = $false; confidence = 'alta'; reason = 'el nombre corresponde a otro tipo de dispositivo' }
    }

    $vid = ''
    if ($InstanceId -match '(?i)VID_([0-9A-F]{4})') { $vid = $Matches[1].ToUpper() }
    if ($vid -and ($script:PrinterVids -contains $vid)) {
        return @{ isPrinter = $true; confidence = 'media'; reason = "VID_$vid es de un fabricante de impresoras" }
    }
    if ($probe -match $script:PrinterWordRx) {
        return @{ isPrinter = $true; confidence = 'baja'; reason = 'el nombre menciona impresora/POS' }
    }
    return @{ isPrinter = $false; confidence = 'alta'; reason = 'sin ninguna senal de impresora (ni clase, ni driver, ni VID, ni nombre)' }
}

function Get-UsbPrintDevices {
    <#
      Impresoras fisicas enumeradas por Windows, con su puerto USB00x.
      Fuentes:
        1) HKLM\SYSTEM\CurrentControlSet\Enum\USBPRINT -> Device Parameters\PortName
           (el unico lugar con el mapeo device -> USB00x)
        2) Win32_PnPEntity en UNA sola query (trae CompatibleID, Service, clase y estado)
        3) Get-PnpDevice como fallback
      Todo candidato pasa por Test-IsPrinterDevice; los descartados quedan registrados
      en $script:Diagnostics['descartadosNoImpresora'] para poder auditar la decision.
    #>
    Write-StepDetail 'leyendo el Administrador de dispositivos'
    $devices       = @()
    $rejected      = @()
    $desconectadas = @()

    # (1) Registro USBPRINT: mapeo device -> PortName
    try {
        $root = 'HKLM:\SYSTEM\CurrentControlSet\Enum\USBPRINT'
        if (Test-Path $root) {
            foreach ($hw in @(Get-ChildItem -Path $root -ErrorAction SilentlyContinue)) {
                foreach ($inst in @(Get-ChildItem -Path $hw.PSPath -ErrorAction SilentlyContinue)) {
                    $props = $null
                    try { $props = Get-ItemProperty -Path $inst.PSPath -ErrorAction SilentlyContinue } catch {}
                    $portName = ''
                    try {
                        $dp = Join-Path $inst.PSPath 'Device Parameters'
                        if (Test-Path $dp) { $portName = [string](Get-ItemProperty -Path $dp -Name 'PortName' -ErrorAction SilentlyContinue).PortName }
                    } catch {}
                    $desc = ''
                    if ($props) {
                        foreach ($k in @('FriendlyName','DeviceDesc','Mfg')) {
                            try { if ($props.$k) { $desc = [string]$props.$k; break } } catch {}
                        }
                    }
                    if ($desc -match ';') { $desc = ($desc -split ';')[-1] }
                    $instId = ('USBPRINT\' + $hw.PSChildName + '\' + $inst.PSChildName)

                    # El registro es historico: solo cuenta si el device esta PRESENTE ahora
                    $presentes = Get-PresentDeviceIds
                    $estaPresente = $true
                    if ($script:PresentIdsOk) { $estaPresente = [bool]$presentes.ContainsKey($instId.ToUpper()) }

                    # Algunos adaptadores USB-paralelo y clones POS publican el descriptor
                    # "No Printer Attached": el nodo existe y esta presente, pero del otro
                    # lado NO hay impresora. Tomarlo como puerto vivo hacia que el motor
                    # reasignara colas a un puerto que nunca iba a imprimir.
                    if ($desc -match '(?i)no printer attached') {
                        $desconectadas += [ordered]@{
                            nombre = 'Adaptador de impresora sin impresora conectada'
                            puerto = $portName
                            instanceId = $instId
                            motivo = 'el dispositivo se identifica como "No Printer Attached": el puerto existe pero del otro lado no hay impresora'
                        }
                        continue
                    }
                    if ($estaPresente) {
                        $devices += [ordered]@{
                            source = 'registry.USBPRINT'; name = $desc
                            instanceId = $instId
                            portName = $portName; status = 'enumerado'; problem = 0
                            deteccion = 'interfaz USBPRINT (usbprint.sys)'; certeza = 'alta'
                        }
                    } else {
                        $desconectadas += [ordered]@{
                            nombre = $(if ($desc) { $desc } else { 'Impresora sin identificar' })
                            puerto = $portName
                            instanceId = $instId
                            motivo = 'figura instalada en el registro de Windows pero el dispositivo no esta presente'
                        }
                    }
                }
            }
        }
    } catch {}

    # (2) WMI: una query y clasificamos en memoria
    $wmiOk = $false
    try {
        $all = @(Get-CimInstance Win32_PnPEntity -ErrorAction Stop)
        $wmiOk = $true
        foreach ($d in $all) {
            $inst = [string]$d.PNPDeviceID
            # solo miramos lo que esta colgado de USB (o ya es clase Printer)
            if ($inst -notmatch '(?i)^(USB|USBPRINT)\\' -and [string]$d.PNPClass -ne 'Printer') { continue }
            # Impresoras de RED enumeradas como device (WSD / IPP): existen, pero no son
            # hardware USB ni tienen puerto USB. Contarlas inflaba "hardware conectado"
            # y generaba puertos candidatos fantasma.
            if ($inst -match '(?i)^SWD\\PRINTENUM' -or [string]$d.Name -match '(?i)IPP Class Driver|WSD ') {
                $rejected += [ordered]@{ nombre = [string]$d.Name; motivo = 'impresora de red (WSD/IPP), no es hardware USB'; instanceId = $inst }
                continue
            }
            $compat = Get-CompatibleIdList -WmiEntity $d -InstanceId $inst
            $verdict = Test-IsPrinterDevice -Name ([string]$d.Name) -InstanceId $inst `
                        -PnpClass ([string]$d.PNPClass) -Service ([string]$d.Service) -CompatibleIds $compat
            if ($verdict.isPrinter) {
                $devices += [ordered]@{
                    source = 'Win32_PnPEntity'; name = [string]$d.Name; instanceId = $inst
                    portName = ''; status = [string]$d.Status
                    problem = $(try { [int]$d.ConfigManagerErrorCode } catch { 0 })
                    deteccion = [string]$verdict.reason; certeza = [string]$verdict.confidence
                    service = [string]$d.Service
                    directoUsb = [bool](Test-IsDirectoUsbDevice -Service ([string]$d.Service))
                }
            } else {
                $rejected += [ordered]@{ nombre = [string]$d.Name; motivo = [string]$verdict.reason; instanceId = $inst }
            }
        }
    } catch {}

    # (3) Fallback PnP moderno (si WMI no respondio)
    if (-not $wmiOk) {
        try {
            foreach ($d in @(Get-PnpDevice -PresentOnly -ErrorAction Stop)) {
                $inst = [string]$d.InstanceId
                if ($inst -notmatch '(?i)^(USB|USBPRINT)\\' -and [string]$d.Class -ne 'Printer') { continue }
                $compat = Get-CompatibleIdList -WmiEntity $null -InstanceId $inst
                $verdict = Test-IsPrinterDevice -Name ([string]$d.FriendlyName) -InstanceId $inst `
                            -PnpClass ([string]$d.Class) -Service '' -CompatibleIds $compat
                if ($verdict.isPrinter) {
                    $devices += [ordered]@{
                        source = 'PnpDevice'; name = [string]$d.FriendlyName; instanceId = $inst
                        portName = ''; status = [string]$d.Status
                        problem = $(try { [int]$d.ProblemCode } catch { 0 })
                        deteccion = [string]$verdict.reason; certeza = [string]$verdict.confidence
                        service = [string]$d.Service
                        directoUsb = [bool](Test-IsDirectoUsbDevice -Service ([string]$d.Service))
                    }
                } else {
                    $rejected += [ordered]@{ nombre = [string]$d.FriendlyName; motivo = [string]$verdict.reason; instanceId = $inst }
                }
            }
        } catch {}
    }

    $script:Diagnostics['descartadosNoImpresora'] = @($rejected)
    $script:Diagnostics['impresorasDesconectadas'] = @($desconectadas)
    $script:Diagnostics['presenciaVerificada']     = [bool]$script:PresentIdsOk

    # Dedup por instanceId, priorizando la entrada que trae portName
    $byId = [ordered]@{}
    foreach ($d in $devices) {
        $key = ([string]$d.instanceId).ToUpper()
        if (-not $byId.Contains($key)) { $byId[$key] = $d }
        elseif (-not $byId[$key].portName -and $d.portName) { $byId[$key] = $d }
    }
    return @(Merge-DuplicateDevices -Devices @($byId.Values))
}

function Get-DeviceNameKey {
    <#
      Clave para comparar nombres de dispositivo: sin mayusculas, sin espacios ni signos.
      'Xprinter XP-410B' y 'XPrinter XP410B' son el mismo aparato.
    #>
    param([string]$Name)
    if (-not $Name) { return '' }
    return (([string]$Name).ToLower() -replace '[^a-z0-9]', '')
}

function Merge-DuplicateDevices {
    <#
      La MISMA impresora puede aparecer dos veces con instanceId distinto, porque Windows la
      representa con dos nodos -el device USB padre (USB\VID_xxxx&PID_xxxx\serie) y su
      interfaz de impresion hija (USBPRINT\Modelo\...&USB00x)- y solo el hijo trae el
      PortName. Se vio contra hardware real: una sola Xprinter XP-410B reportada como
      "Impresoras fisicas detectadas: 2", con la segunda "sin puerto asignado", y
      cantidadHardware = 2 viajando a la telemetria.
      Solo se fusiona el nodo SIN puerto contra uno CON puerto del mismo modelo: dos
      impresoras iguales de verdad tienen cada una su propio puerto, asi que siguen siendo dos.
    #>
    param($Devices)
    $lista = @($Devices)
    $nombresConPuerto = @($lista | Where-Object { [string]$_.portName } |
                          ForEach-Object { Get-DeviceNameKey -Name ([string]$_.name) } |
                          Where-Object { $_ })
    $out = @()
    $vistosSinPuerto = @()
    foreach ($d in $lista) {
        if ([string]$d.portName) { $out += $d; continue }
        $k = Get-DeviceNameKey -Name ([string]$d.name)
        if (-not $k) { $out += $d; continue }
        # ya hay un nodo con puerto de este mismo modelo -> es el mismo aparato
        if (@($nombresConPuerto) -contains $k) { continue }
        # dos nodos sin puerto del mismo modelo tampoco son dos impresoras distintas
        if (@($vistosSinPuerto) -contains $k) { continue }
        $vistosSinPuerto += $k
        $out += $d
    }
    return @($out)
}

function Get-ProblemPrinterDevices {
    <#
      Dispositivos de impresion presentes con problema (28 = sin driver instalado).
      Mismo filtro que arriba: un mouse con driver roto no es asunto de este motor.
    #>
    $out = @()
    try {
        foreach ($d in @(Get-CimInstance Win32_PnPEntity -ErrorAction Stop | Where-Object { $_.ConfigManagerErrorCode -ne 0 })) {
            $inst = [string]$d.PNPDeviceID
            if ($inst -notmatch '(?i)^(USB|USBPRINT)\\' -and [string]$d.PNPClass -ne 'Printer') { continue }
            $compat = Get-CompatibleIdList -WmiEntity $d -InstanceId $inst
            $verdict = Test-IsPrinterDevice -Name ([string]$d.Name) -InstanceId $inst `
                        -PnpClass ([string]$d.PNPClass) -Service ([string]$d.Service) -CompatibleIds $compat
            if (-not $verdict.isPrinter) { continue }
            $out += [ordered]@{
                name = [string]$d.Name; instanceId = $inst; status = [string]$d.Status
                problem = [int]$d.ConfigManagerErrorCode; class = [string]$d.PNPClass
                deteccion = [string]$verdict.reason; certeza = [string]$verdict.confidence
            }
        }
        return @($out)
    } catch {}
    try {
        foreach ($d in @(Get-PnpDevice -PresentOnly -ErrorAction Stop | Where-Object { $_.Status -ne 'OK' })) {
            $inst = [string]$d.InstanceId
            if ($inst -notmatch '(?i)^(USB|USBPRINT)\\' -and [string]$d.Class -ne 'Printer') { continue }
            $verdict = Test-IsPrinterDevice -Name ([string]$d.FriendlyName) -InstanceId $inst `
                        -PnpClass ([string]$d.Class) -Service '' -CompatibleIds @(Get-CompatibleIdList -WmiEntity $null -InstanceId $inst)
            if (-not $verdict.isPrinter) { continue }
            $out += [ordered]@{
                name = [string]$d.FriendlyName; instanceId = $inst; status = [string]$d.Status
                problem = $(try { [int]$d.ProblemCode } catch { 0 }); class = [string]$d.Class
                deteccion = [string]$verdict.reason; certeza = [string]$verdict.confidence
            }
        }
    } catch {}
    return @($out)
}


function Get-GenericTextDriverName {
    <#
      Busca el driver inbox "Generic / Text Only" ya instalado (el nombre esta localizado:
      en Windows en espanol puede ser "Generico / Solo texto"). Devuelve '' si no esta.
    #>
    $drivers = @()
    try { $drivers = @(Get-PrinterDriver -ErrorAction Stop | ForEach-Object { [string]$_.Name }) } catch {}
    foreach ($d in $drivers) {
        if ($d -match '(?i)generic|gen[e\xe9]rico' -and $d -match '(?i)text|texto') { return $d }
    }
    return ''
}

function Install-GenericTextDriver {
    <# Instala el driver inbox generico. Devuelve el nombre instalado o ''. #>
    $already = Get-GenericTextDriverName
    if ($already) { return $already }
    $candidates = @('Generic / Text Only','Generic / Text only','Generico / Solo texto',
                    'Gen' + [char]233 + 'rico / Solo texto','Gen' + [char]233 + 'rico / S' + [char]243 + 'lo texto')
    foreach ($c in $candidates) {
        try { Add-PrinterDriver -Name $c -ErrorAction Stop; return $c } catch {}
    }
    # Fallback printui + ntprint.inf (sirve tambien en 5.1 sin PrintManagement)
    try {
        $inf = Join-Path $env:windir 'inf\ntprint.inf'
        $null = & rundll32 printui.dll,PrintUIEntry /ia /f "$inf" /m "Generic / Text Only" 2>&1
        Start-Sleep -Milliseconds 1500
        return (Get-GenericTextDriverName)
    } catch {}
    return ''
}

function New-FudoTestPrinter {
    <#
      Crea una cola temporal sobre $PortName. Si la impresora de ese puerto es de una marca
      con driver propio YA instalado en Windows, usa ese; si no, el inbox generico de texto.
    #>
    param([string]$PortName, [string]$PreferredDriver = '')
    $drv = ''
    if ($PreferredDriver) { $drv = $PreferredDriver }
    if (-not $drv -and $script:Diagnostics.Contains('printersConnected')) {
        $match = @($script:Diagnostics['printersConnected'] | Where-Object { $_.puerto -eq $PortName -and $_.driverNombre }) | Select-Object -First 1
        if ($match) { $drv = [string]$match.driverNombre }
    }
    if (-not $drv) {
        Write-StepDetail 'instalando el driver de texto generico'
        $drv = Install-GenericTextDriver
    }
    if (-not $drv) { throw "No se pudo instalar el driver generico de texto (necesario para la prueba de impresion)." }

    $name = 'FUDO-TEST-' + ($PortName -replace '[^A-Za-z0-9]', '')
    $exists = $false
    try { $exists = [bool](Get-Printer -Name $name -ErrorAction SilentlyContinue) } catch {}
    if ($exists) { return $name }

    # El puerto USB00x lo crea usbprint al enumerar el device; si falta, lo intentamos crear.
    $portOk = $false
    try { $portOk = [bool](Get-PrinterPort -Name $PortName -ErrorAction SilentlyContinue) } catch {}
    if (-not $portOk) { try { Add-PrinterPort -Name $PortName -ErrorAction Stop; $portOk = $true } catch {} }

    try {
        Add-Printer -Name $name -DriverName $drv -PortName $PortName -ErrorAction Stop
    } catch {
        $null = & rundll32 printui.dll,PrintUIEntry /if /b "$name" /f (Join-Path $env:windir 'inf\ntprint.inf') /r "$PortName" /m "$drv" 2>&1
        Start-Sleep -Milliseconds 2000
    }
    $created = $null
    try { $created = Get-Printer -Name $name -ErrorAction SilentlyContinue } catch {}
    if ($created) {
        [void]$script:TestPrintersCreated.Add($name)
        return $name
    }
    return ''
}

function Get-ArrivalScenario {
    <#
      En que estado nos encontramos la PC. Es la pregunta "en que estado llegan los clientes":
      nunca tuvieron impresora, la tenian y dejo de andar, tienen una andando y otra no, etc.

      Se apoya en tres evidencias independientes:
        - colas reales instaladas y su estado (capa 1)
        - entradas historicas del registro USBPRINT y puertos USB00x huerfanos (impresoras que
          ALGUNA VEZ estuvieron en esta PC)
        - historial de impresion del spooler (si esa cola imprimio de verdad alguna vez)
      Cuando el log del spooler esta apagado, el uso previo queda como 'desconocido' en lugar de
      afirmar que nunca imprimio.
    #>
    $colas = @()
    if ($script:Diagnostics.Contains('colas')) { $colas = @($script:Diagnostics['colas']) }
    # Las colas FUDO-TEST-* las creo el motor: si cuentan como colas del cliente, la corrida
    # N+1 diagnostica la basura de la corrida N (el escenario saltaba a 'todas_funcionan').
    $colas   = @($colas | Where-Object { -not $_.esDePrueba })
    $sanas   = @($colas | Where-Object { [int]$_.score -eq 0 })
    $malas   = @($colas | Where-Object { [int]$_.score -gt 0 })

    $historicas = @()
    if ($script:Diagnostics.Contains('impresorasDesconectadas')) { $historicas = @($script:Diagnostics['impresorasDesconectadas']) }
    $puertosUsb = @()
    if ($script:Diagnostics.Contains('usbPorts')) { $puertosUsb = @($script:Diagnostics['usbPorts'] | Where-Object { $_ }) }
    $hwPresente = 0
    if ($script:Diagnostics.Contains('hwDeviceCount')) { $hwPresente = [int]$script:Diagnostics['hwDeviceCount'] }

    # el motor instalo una cola en esta corrida?
    $instaloAhora = (@($script:Actions | Where-Object { [string]$_.type -in @('printer.install_generic','printer.recreate') }).Count -gt 0)

    # uso previo real, segun el log del spooler
    $usoPrevio = 'desconocido'
    if ($script:Diagnostics.Contains('historialImpresion')) {
        $h = $script:Diagnostics['historialImpresion']
        if ($h.habilitado) {
            $conFudo = @($h.porImpresora | Where-Object { [int]$_.deFudo -gt 0 })
            $conAlgo = @($h.porImpresora | Where-Object { [int]$_.total -gt 0 })
            if (@($conFudo).Count -gt 0)      { $usoPrevio = 'si_imprimio_comandas_de_fudo' }
            elseif (@($conAlgo).Count -gt 0)  { $usoPrevio = 'imprimio_pero_no_comandas_de_fudo' }
            else                              { $usoPrevio = 'no_hay_registro_de_impresion' }
        }
    }

    # Huellas de que en esta PC ALGUNA VEZ hubo una impresora instalada
    $huboAntes = ((@($historicas).Count -gt 0) -or (@($puertosUsb).Count -gt 0) -or (@($colas).Count -gt 0))

    $esc = 'indeterminado'
    if (@($colas).Count -eq 0 -and -not $huboAntes -and $hwPresente -eq 0) {
        $esc = 'nunca_hubo_impresora_en_esta_pc'
    } elseif ($instaloAhora -and -not (@($historicas).Count -gt 0)) {
        $esc = 'primera_instalacion'
    } elseif (@($sanas).Count -gt 0 -and @($malas).Count -gt 0) {
        $esc = 'una_funciona_y_otra_no'
    } elseif (@($colas).Count -gt 0 -and @($malas).Count -eq 0) {
        $esc = 'todas_funcionan'
    } elseif (@($malas).Count -gt 0) {
        if ($usoPrevio -eq 'si_imprimio_comandas_de_fudo' -or @($historicas).Count -gt 0) {
            $esc = 'estaba_instalada_y_dejo_de_funcionar'
        } elseif ($usoPrevio -eq 'no_hay_registro_de_impresion') {
            $esc = 'instalada_pero_nunca_imprimio'
        } else {
            $esc = 'instalada_y_no_funciona_sin_historial'
        }
    } elseif (@($colas).Count -eq 0 -and $hwPresente -gt 0) {
        $esc = 'hardware_conectado_sin_instalar'
    }

    return [ordered]@{
        escenario          = $esc
        usoPrevio          = $usoPrevio
        colasTotales       = @($colas).Count
        colasSanas         = @($sanas).Count
        colasConProblema   = @($malas).Count
        impresorasHistoricas = @($historicas).Count
        hardwarePresente   = $hwPresente
        instaloEnEstaCorrida = [bool]$instaloAhora
        # 'primera vez' se puede afirmar de esta PC, no del comercio: desde la PC no hay
        # forma de saber si en otra maquina del local ya hay impresoras funcionando.
        alcance            = 'esta_pc'
    }
}

function Get-PcId {
    <#
      Identificador ESTABLE y ANONIMO de la PC, para poder agrupar las corridas de una misma
      maquina y ver la secuencia "fallaba -> se hizo X -> quedo resuelto".
      Es un hash (SHA256 truncado) del MachineGuid de Windows: no permite volver al dato original
      ni identificar al comercio, solo saber que dos corridas vienen del mismo lugar.
    #>
    $base = ''
    try { $base = [string](Get-ItemProperty -Path 'HKLM:\SOFTWARE\Microsoft\Cryptography' -Name 'MachineGuid' -ErrorAction Stop).MachineGuid } catch {}
    if (-not $base) { try { $base = [string](Get-CimInstance Win32_ComputerSystemProduct -ErrorAction Stop).UUID } catch {} }
    if (-not $base) { $base = "$env:COMPUTERNAME|$env:USERNAME" }
    try {
        $sha = [System.Security.Cryptography.SHA256]::Create()
        $bytes = $sha.ComputeHash([System.Text.Encoding]::UTF8.GetBytes('fudo-print-doctor|' + $base))
        return ((([BitConverter]::ToString($bytes)) -replace '-', '').Substring(0, 16).ToLower())
    } catch { return '' }
}

function Get-LocalRunHistory {
    <# Que paso en las corridas anteriores de ESTA PC (guardado en HKCU, sin datos del cliente). #>
    $r = [ordered]@{ corridas = 0; ultimoStatus = ''; ultimaCausa = ''; ultimaFecha = '' }
    try {
        $k = 'HKCU:\Software\Fudo\PrintDoctor'
        if (Test-Path $k) {
            $v = Get-ItemProperty -Path $k -ErrorAction Stop
            try { $r.corridas    = [int]$v.Corridas } catch {}
            try { $r.ultimoStatus = [string]$v.UltimoStatus } catch {}
            try { $r.ultimaCausa  = [string]$v.UltimaCausa } catch {}
            try { $r.ultimaFecha  = [string]$v.UltimaFecha } catch {}
        }
    } catch {}
    return $r
}

function Save-LocalRunHistory {
    <# Deja el resultado de esta corrida para que la proxima pueda contar la transicion. #>
    param([string]$Status, [string]$Causa, [int]$Corridas)
    try {
        $k = 'HKCU:\Software\Fudo\PrintDoctor'
        if (-not (Test-Path $k)) { New-Item -Path $k -Force -ErrorAction Stop | Out-Null }
        New-ItemProperty -Path $k -Name 'Corridas'     -Value $Corridas -PropertyType DWord  -Force -ErrorAction SilentlyContinue | Out-Null
        New-ItemProperty -Path $k -Name 'UltimoStatus' -Value $Status   -PropertyType String -Force -ErrorAction SilentlyContinue | Out-Null
        New-ItemProperty -Path $k -Name 'UltimaCausa'  -Value $Causa    -PropertyType String -Force -ErrorAction SilentlyContinue | Out-Null
        New-ItemProperty -Path $k -Name 'UltimaFecha'  -Value ((Get-Date).ToString('o')) -PropertyType String -Force -ErrorAction SilentlyContinue | Out-Null
    } catch {}
}

function Get-FudoNativeFingerprint {
    <#
      Sondeo para averiguar SI la App Nativa guarda algun identificador de comercio que se pueda
      usar como identificador (y asi no tener que pedirle nada al asesor).
      A proposito manda solo NOMBRES de archivo y NOMBRES de clave: ningun valor, para no
      transportar tokens ni credenciales. Con esto decidimos si hay algo aprovechable.
    #>
    $out = [ordered]@{ carpeta = ''; archivos = @(); clavesJson = @() }
    $carpetas = @()
    try { if ($env:LOCALAPPDATA) { $carpetas += (Join-Path $env:LOCALAPPDATA 'Fudo') } } catch {}
    try { if ($env:APPDATA) { $carpetas += (Join-Path $env:APPDATA 'Fudo') } } catch {}
    foreach ($c in @($carpetas | Where-Object { $_ })) {
        try { if (-not (Test-Path $c)) { continue } } catch { continue }
        $out.carpeta = $c
        try {
            $archivos = @(Get-ChildItem -Path $c -Recurse -File -ErrorAction SilentlyContinue | Select-Object -First 40)
            $out.archivos = @($archivos | ForEach-Object { [ordered]@{ nombre = $_.Name; kb = [int]($_.Length / 1KB) } })
            foreach ($f in @($archivos | Where-Object { $_.Extension -match '(?i)^\.(json|cfg|ini|conf)$' -and $_.Length -lt 200KB })) {
                try {
                    $txt = Get-Content -Path $f.FullName -Raw -ErrorAction Stop
                    foreach ($m in @([regex]::Matches($txt, '"([A-Za-z0-9_\-]{2,40})"\s*:'))) {
                        $clave = $m.Groups[1].Value
                        if (@($out.clavesJson) -notcontains $clave) { $out.clavesJson += $clave }
                    }
                } catch {}
            }
            $out.clavesJson = @(@($out.clavesJson) | Select-Object -First 40)
        } catch {}
        break
    }
    return $out
}

function Get-EnvironmentInfo {
    <#
      Contexto de la PC: sistema operativo, navegador, region, tipo de red.
      Sirve para telemetria y para entender el caso sin pedirle datos al cliente.
    #>
    $os = [ordered]@{}
    try {
        $w = Get-CimInstance Win32_OperatingSystem -ErrorAction Stop
        $os = [ordered]@{
            nombre = [string]$w.Caption; version = [string]$w.Version
            build = [string]$w.BuildNumber; arquitectura = [string]$w.OSArchitecture
        }
    } catch {
        try { $os = [ordered]@{ nombre = 'Windows'; version = [string][Environment]::OSVersion.Version } } catch {}
    }

    # Chrome: la extension de Fudo corre ahi, asi que la version importa.
    # OJO: Join-Path explota si la base es $null (pasa con ProgramFiles(x86) en 32 bits).
    $chrome = ''
    $rutasChrome = @()
    foreach ($base in @($env:ProgramFiles, ${env:ProgramFiles(x86)}, $env:LOCALAPPDATA)) {
        if ($base) { $rutasChrome += (Join-Path $base 'Google\Chrome\Application\chrome.exe') }
    }
    foreach ($r in $rutasChrome) {
        try { if (Test-Path $r) { $chrome = [string](Get-Item $r).VersionInfo.ProductVersion; break } } catch {}
    }
    if (-not $chrome) {
        foreach ($k in @('HKLM:\SOFTWARE\Wow6432Node\Google\Update\Clients\*','HKLM:\SOFTWARE\Google\Update\Clients\*')) {
            try {
                $hit = @(Get-ItemProperty -Path $k -ErrorAction SilentlyContinue | Where-Object { $_.name -match '(?i)^Google Chrome$' }) | Select-Object -First 1
                if ($hit -and $hit.pv) { $chrome = [string]$hit.pv; break }
            } catch {}
        }
    }

    # Otros navegadores (por si el local usa Edge)
    $edge = ''
    foreach ($base in @(${env:ProgramFiles(x86)}, $env:ProgramFiles)) {
        if (-not $base) { continue }
        try {
            $r = Join-Path $base 'Microsoft\Edge\Application\msedge.exe'
            if (Test-Path $r) { $edge = [string](Get-Item $r).VersionInfo.ProductVersion; break }
        } catch {}
    }

    # Region / pais / zona horaria (local, sin consultar nada por internet)
    # El pais por cultura miente cuando Windows esta en ingles (da US aunque el local sea de AR),
    # asi que ademas derivamos un pais probable de la zona horaria.
    $tzPais = [ordered]@{
        'Argentina Standard Time' = 'AR'; 'E. South America Standard Time' = 'BR'
        'Central Brazilian Standard Time' = 'BR'; 'Bahia Standard Time' = 'BR'
        'Pacific SA Standard Time' = 'CL'; 'Easter Island Standard Time' = 'CL'
        'SA Pacific Standard Time' = 'CO/PE/EC'; 'SA Western Standard Time' = 'BO/DO/PR'
        'Central America Standard Time' = 'CR/GT/HN/NI/SV'
        'Central Standard Time (Mexico)' = 'MX'; 'Mountain Standard Time (Mexico)' = 'MX'
        'Pacific Standard Time (Mexico)' = 'MX'; 'Montevideo Standard Time' = 'UY'
        'Paraguay Standard Time' = 'PY'; 'Venezuela Standard Time' = 'VE'
        'Romance Standard Time' = 'ES'; 'W. Europe Standard Time' = 'EU'
    }
    $pais = ''; $paisNombre = ''; $cultura = ''; $tz = ''
    try { $cultura = [string](Get-Culture).Name } catch {}
    try {
        $ri = [System.Globalization.RegionInfo]::CurrentRegion
        $pais = [string]$ri.TwoLetterISORegionName; $paisNombre = [string]$ri.EnglishName
    } catch {}
    try { $tz = [string](Get-TimeZone -ErrorAction Stop).Id } catch { try { $tz = [string][TimeZoneInfo]::Local.Id } catch {} }

    # Como esta conectada la PC: cable o wifi (importa para impresoras de red)
    $redes = @()
    try {
        foreach ($a in @(Get-NetAdapter -Physical -ErrorAction Stop | Where-Object { $_.Status -eq 'Up' })) {
            $tipo = 'cable'
            if (([string]$a.InterfaceDescription -match '(?i)wi-?fi|wireless|802\.11') -or ([string]$a.Name -match '(?i)wi-?fi|inalambr')) { $tipo = 'wifi' }
            $redes += [ordered]@{ nombre = [string]$a.Name; descripcion = [string]$a.InterfaceDescription; tipo = $tipo; velocidad = [string]$a.LinkSpeed }
        }
    } catch {
        try {
            foreach ($a in @(Get-CimInstance Win32_NetworkAdapter -ErrorAction Stop | Where-Object { $_.NetEnabled -eq $true -and $_.PhysicalAdapter })) {
                $tipo = $(if ([string]$a.Name -match '(?i)wi-?fi|wireless|802\.11') { 'wifi' } else { 'cable' })
                $redes += [ordered]@{ nombre = [string]$a.NetConnectionID; descripcion = [string]$a.Name; tipo = $tipo; velocidad = '' }
            }
        } catch {}
    }

    $nativaVer = ''
    try {
        if ($script:Diagnostics.Contains('nativeInstall')) {
            $reg = @($script:Diagnostics['nativeInstall'].regInfo)
            if (@($reg).Count -gt 0) { $nativaVer = [string]@($reg)[0].version }
        }
    } catch {}

    $paisProbable = $pais
    if ($tz -and $tzPais.Contains($tz)) { $paisProbable = [string]$tzPais[$tz] }

    return [ordered]@{
        so             = $os
        powershell     = [string]$PSVersionTable.PSVersion
        chrome         = $chrome
        edge           = $edge
        nativaVersion  = $nativaVer
        cultura        = $cultura
        pais           = $pais
        paisNombre     = $paisNombre
        paisProbable   = $paisProbable
        zonaHoraria    = $tz
        redes          = @($redes)
        tipoConexionPC = $(if (@($redes | Where-Object { $_.tipo -eq 'cable' }).Count -gt 0) { 'cable' } elseif (@($redes).Count -gt 0) { 'wifi' } else { 'sin red' })
        esAdmin        = $(if ($script:Diagnostics.Contains('isAdmin')) { [bool]$script:Diagnostics['isAdmin'] } else { $false })
    }
}

function Test-IsGenericDocName {
    <#
      El nombre que Windows le pone a un trabajo cuando el programa que imprime no le pone
      ninguno. Son los unicos que aparecieron en 146 entradas de historial de 229 corridas:
      'Imprimir documento' (134), 'Documento de Impressao' (7) y 'Print Document' (5). Un nombre
      asi NO distingue una comanda de Fudo de cualquier otra impresion, en ningun idioma: es
      ausencia de dato, no evidencia de que Fudo no imprimio.
    #>
    param([string]$Doc)
    $d = ([string]$Doc).Trim()
    if (-not $d) { return $true }
    return [bool]($d -match '(?i)^(imprimir documento|print document|impresion de documento|documento de impresion)$' -or
                  $d -match '(?i)^documento de impress')
}

function Get-PrintHistory {
    <#
      Historial real de impresion desde el log del spooler (evento 307 = trabajo impreso).
      Es la unica forma, desde la PC, de saber a que cola le esta mandando Fudo: los trabajos de
      la App Nativa se llaman 'node print job'.
      El log viene DESHABILITADO de fabrica en Windows; si esta apagado lo decimos.
    #>
    param([int]$MaxEventos = 300)
    $log = 'Microsoft-Windows-PrintService/Operational'
    $habilitado = $false
    try { $habilitado = [bool](Get-WinEvent -ListLog $log -ErrorAction Stop).IsEnabled } catch {}
    if (-not $habilitado) { return [ordered]@{ habilitado = $false; porImpresora = @() } }

    $porImp = @{}
    try {
        foreach ($e in @(Get-WinEvent -LogName $log -MaxEvents $MaxEventos -ErrorAction Stop | Where-Object { $_.Id -eq 307 })) {
            $doc = ''; $imp = ''
            try { $doc = [string]$e.Properties[1].Value } catch {}
            try { $imp = [string]$e.Properties[4].Value } catch {}
            if (-not $imp) { continue }
            # Los tickets de prueba del motor no son historial del local: contarlos hacia que
            # la corrida siguiente creyera que esa cola imprimio (o peor: que imprimio comandas).
            # v3.13: el descarte estaba DESPUES de crear la entrada, asi que una cola cuyo unico
            # trabajo fue el ticket del motor igual aparecia en el historial con total=0 y con
            # ejemploDoc = 'Fudo Print Doctor Test'. El motor se mostraba a si mismo.
            if ($doc -match $script:TestDocRx) { continue }
            # v3.15: descartar por nombre de documento no alcanzaba. En la telemetria del 04/09
            # habia 40 entradas de colas FUDO-TEST-* cuyo documento Windows reporto con el nombre
            # generico del spooler, asi que el filtro de arriba no las veia y el motor se contaba
            # a si mismo como historial de impresion del local.
            if ($imp -match $script:TestPrinterRx) { continue }
            if (-not $porImp.ContainsKey($imp)) {
                $porImp[$imp] = [ordered]@{ impresora = $imp; total = 0; deFudo = 0; ultimo = ''; ultimoDeFudo = ''; ejemploDoc = $doc; docsInformativos = 0 }
            }
            $porImp[$imp].total++
            if (-not $porImp[$imp].ultimo) { $porImp[$imp].ultimo = $e.TimeCreated.ToString('dd/MM HH:mm') }
            # Cuantos trabajos traen un nombre de documento que dice algo. Sin este conteo el
            # motor leia "ningun trabajo se llama como Fudo" y concluia "Fudo no esta mandando":
            # con nombres genericos esa conclusion no se puede sacar.
            if (-not (Test-IsGenericDocName -Doc $doc)) { $porImp[$imp].docsInformativos++ }
            # La Nativa manda los trabajos con este nombre
            if ($doc -match '(?i)node print job|fudo') {
                $porImp[$imp].deFudo++
                if (-not $porImp[$imp].ultimoDeFudo) { $porImp[$imp].ultimoDeFudo = $e.TimeCreated.ToString('dd/MM HH:mm') }
            }
        }
    } catch {}
    $trabajos = 0
    $infoDocs = 0
    try { $trabajos = [int](@($porImp.Values | ForEach-Object { [int]$_.total }) | Measure-Object -Sum).Sum } catch {}
    try { $infoDocs = [int](@($porImp.Values | ForEach-Object { [int]$_.docsInformativos }) | Measure-Object -Sum).Sum } catch {}
    return [ordered]@{
        habilitado = $true
        porImpresora = @($porImp.Values)
        trabajos = $trabajos
        docsInformativos = $infoDocs
        # Se puede atribuir algo a partir de este historial? Solo si hay al menos un trabajo con
        # nombre de documento util. Con el historial vacio, o con todos los nombres genericos, el
        # matcher por nombre no dice nada: ni a favor ni en contra de que Fudo haya impreso.
        atribuible = [bool]($infoDocs -gt 0)
    }
}

function Get-PrinterQueues {
    <#
      Todas las colas REALES de Windows (sin virtuales) con su estado, para poder decidir cual
      es la que esta fallando. En un local hay caja y cocina: la que anda no se toca.
      'score' mide que tan mal esta: 0 = sana. Se elige como objetivo la de score mas alto.
    #>
    $out = @()
    $all = @()
    try { $all = @(Get-Printer -ErrorAction Stop) } catch { return @() }

    foreach ($q in $all) {
        if ((Test-IsVirtualPrinter $q).isVirtual) { continue }
        $nombre = [string]$q.Name
        $puerto = [string]$q.PortName

        $offline = $false; $pausada = $false
        try {
            $w = Get-CimInstance Win32_Printer -Filter "Name='$($nombre -replace "'","''")'" -ErrorAction Stop
            if ($w) {
                try { $offline = [bool]$w.WorkOffline } catch {}
                try { $pausada = ((([int]$w.PrinterState) -band 1) -ne 0) } catch {}
            }
        } catch {}

        $jobs = @()
        try { $jobs = @(Get-PrintJob -PrinterName $nombre -ErrorAction Stop) } catch {}
        $masViejo = ''
        # Minutos que lleva esperando el trabajo mas viejo (-1 = no se pudo saber). La fecha
        # formateada sirve para el resumen en pantalla; para decidir si una cola esta trabada
        # hace falta el numero: una rafaga recien encolada drena sola, 93 trabajos de hace tres
        # horas no.
        $minViejo = -1
        if (@($jobs).Count -gt 0) {
            try {
                $t = @($jobs | Where-Object { $_.SubmittedTime } | Sort-Object SubmittedTime | Select-Object -First 1)
                if (@($t).Count -gt 0) {
                    $masViejo = ([datetime]@($t)[0].SubmittedTime).ToString('dd/MM HH:mm')
                    $minViejo = [int]((Get-Date) - [datetime]@($t)[0].SubmittedTime).TotalMinutes
                }
            } catch {}
        }

        $puertoVivo = Test-PortHasLiveDevice -PortName $puerto

        $score = 0
        $sintomas = @()
        if (@($jobs).Count -ge 3)  { $score += 40; $sintomas += "$(@($jobs).Count) trabajos encolados" + $(if ($masViejo) { " (el mas viejo del $masViejo)" } else { '' }) }
        elseif (@($jobs).Count -gt 0) { $score += 10; $sintomas += "$(@($jobs).Count) trabajo(s) en cola" }
        if (-not $puertoVivo)      { $score += 30; $sintomas += "el puerto $puerto no tiene ningun dispositivo conectado" }
        if ($offline)              { $score += 25; $sintomas += 'marcada como sin conexion (offline)' }
        if ($pausada)              { $score += 20; $sintomas += 'pausada' }

        $out += [ordered]@{
            nombre = $nombre; puerto = $puerto; driver = [string]$q.DriverName
            esDePrueba = [bool]($nombre -match $script:TestPrinterRx)
            offline = $offline; pausada = $pausada; trabajos = @($jobs).Count; trabajoMasViejo = $masViejo
            minutosMasViejo = [int]$minViejo
            puertoVivo = [bool]$puertoVivo; esPos = (Test-IsPosPrinter $q)
            score = $score; sintomas = @($sintomas)
            estado = $(if ($score -eq 0) { 'sana' } elseif ($score -ge 40) { 'no imprime' } else { 'con problemas' })
        }
    }
    # score primero; ante empate, las colas del CLIENTE antes que las del motor, para no
    # diagnosticar (ni probar) sobre una cola nuestra cuando hay una real igual de sana.
    return @($out | Sort-Object -Property @{ Expression = { [int]$_.score }; Descending = $true },
                                            @{ Expression = { [bool]$_.esDePrueba }; Descending = $false })
}

function Test-PortHasLiveDevice {
    <#
      El puerto USB00x tiene un dispositivo PRESENTE detras?
      Devuelve $true si no se puede afirmar lo contrario (nunca inventa una desconexion).
    #>
    param([string]$PortName)
    if (-not $PortName) { return $true }
    if ($PortName -notmatch '^(?i)USB\d+') { return $true }     # solo aplica a puertos USB fisicos
    if (-not $script:PresentIdsOk) { return $true }             # no pudimos verificar presencia
    $live = @()
    if ($script:Diagnostics.Contains('livePorts')) { $live = @($script:Diagnostics['livePorts'] | Where-Object { $_ }) }
    $hwCount = 0
    if ($script:Diagnostics.Contains('hwDeviceCount')) { $hwCount = [int]$script:Diagnostics['hwDeviceCount'] }
    if (@($live).Count -eq 0 -and $hwCount -gt 0) { return $true }  # hay hardware pero sin mapeo de puerto
    return ([bool](@($live) -contains $PortName))
}

function Test-Layer1a-HardwareInventory {
    <#
      Primero el fierro: que hay conectado (Administrador de dispositivos) y en que puerto.
      Recien despues miramos si esta instalado como cola de Windows.
    #>
    $devices   = @(Get-UsbPrintDevices)
    $problems  = @(Get-ProblemPrinterDevices)
    $ports     = @()
    try { $ports = @(Get-PrinterPort -ErrorAction Stop | ForEach-Object { [ordered]@{ name = [string]$_.Name; description = [string]$_.Description } }) } catch {}
    $usbPorts  = @($ports | Where-Object { $_.name -match '^USB\d+' } | ForEach-Object { $_.name })
    $devPorts  = @($devices | Where-Object { $_.portName } | ForEach-Object { $_.portName } | Select-Object -Unique)

    # Identidad + plan de driver por device
    $identified = @()
    foreach ($d in @($devices)) {
        $id = Get-DeviceIdentity -Device $d
        $plan = Get-DriverPlan -Identity $id
        $identified += [ordered]@{
            nombre        = [string]$id.label
            marca         = [string]$id.brand
            modelo        = [string]$id.model
            vidPid        = $(if ($id.vid) { "VID_$($id.vid)" + $(if ($id.pid) { "&PID_$($id.pid)" } else { '' }) } else { '' })
            puerto        = [string]$d.portName
            estado        = [string]$d.status
            instanceId    = [string]$d.instanceId
            driverSugerido = [string]$plan.kind
            driverNombre  = [string]$plan.driverName
            driverNota    = [string]$plan.note
            deteccion     = [string]$d.deteccion
            certeza       = [string]$d.certeza
            nombreCrudo   = [string]$d.name
            service       = [string]$d.service
            directoUsb    = [bool]$d.directoUsb
        }
    }
    $script:Diagnostics['printersConnected'] = $identified
    $script:Diagnostics['hwDevices']      = $devices
    $script:Diagnostics['hwProblemDevs']  = $problems
    $script:Diagnostics['printerPorts']   = @($ports | ForEach-Object { $_.name })
    $script:Diagnostics['usbPorts']       = $usbPorts
    $script:Diagnostics['livePorts']      = $devPorts
    $script:Diagnostics['hwDeviceCount']  = (@($devices).Count + @($problems).Count)

    # 1a.1c Impresoras que Windows conoce pero que NO estan conectadas ahora.
    # Dedup: una entrada historica cuyo puerto esta vivo, o que coincide con una impresora
    # presente, es la MISMA impresora. Listarla como desconectada seria contradictorio.
    $desconectadas = @()
    if ($script:Diagnostics.Contains('impresorasDesconectadas')) {
        $nombresPresentes = @(@($identified | ForEach-Object { [string]$_.nombre }) + @($identified | ForEach-Object { [string]$_.nombreCrudo }) | Where-Object { $_ })
        $desconectadas = @($script:Diagnostics['impresorasDesconectadas'] | Where-Object {
            $mismoPuertoVivo = ($_.puerto -and (@($devPorts) -contains [string]$_.puerto))
            $mismoNombre     = ([string]$_.nombre -and (@($nombresPresentes) -contains [string]$_.nombre))
            -not ($mismoPuertoVivo -or $mismoNombre)
        })
        # colapsar duplicados por puerto (el registro guarda una entrada por reconexion)
        $vistos = @{}
        $unicas = @()
        foreach ($d in @($desconectadas)) {
            $k = (([string]$d.nombre) + '|' + ([string]$d.puerto)).ToUpper()
            if (-not $vistos.ContainsKey($k)) { $vistos[$k] = $true; $unicas += $d }
        }
        # Si el puerto coincide con una cola instalada, nombrarla: conecta los puntos para el asesor
        foreach ($d in @($unicas)) {
            $colaDeEsePuerto = ''
            try {
                $m = @($installed | Where-Object { [string]$_.PortName -eq [string]$d.puerto -and -not (Test-IsVirtualPrinter $_).isVirtual }) | Select-Object -First 1
                if ($m) { $colaDeEsePuerto = [string]$m.Name }
            } catch {}
            $d['colaWindows'] = $colaDeEsePuerto
            if ($colaDeEsePuerto -and ([string]$d.nombre -match '(?i)^(no printer attached|printer|impresora|sin impresora|impresora sin identificar)\s*$')) {
                $d['nombre'] = $colaDeEsePuerto
            }
        }
        $desconectadas = @($unicas)
        $script:Diagnostics['impresorasDesconectadas'] = $desconectadas
    }
    if (@($desconectadas).Count -gt 0) {
        $detalle = @($desconectadas | ForEach-Object { $_.nombre + $(if ($_.puerto) { " (estaba en $($_.puerto))" } else { '' }) })
        Add-Check -Id 'hw.disconnected' -Layer 1 -Name ('Impresora instalada pero DESCONECTADA: ' + ($detalle -join ' | ')) `
            -Status $(if (@($identified).Count -eq 0) { 'fail' } else { 'warn' }) -RootCauseCandidate (@($identified).Count -eq 0) -Plane 'hardware' `
            -Evidence @{ desconectadas = $desconectadas; conectadasAhora = @($identified).Count } `
            -ArticleRef 'https://soporte.fu.do/es/articles/11730817' `
            -Recommendation ("Windows tiene instalada esta impresora pero el dispositivo no esta presente: esta apagada o desenchufada. " +
                             $(if (@($desconectadas).Count -eq 1 -and @($desconectadas)[0].puerto) {
                                    "Conectarla al MISMO puerto USB donde estaba ($(@($desconectadas)[0].puerto)), encenderla"
                                } else {
                                    'Encenderlas y conectarlas, de ser posible en el mismo puerto USB donde estaban'
                                }) +
                             " y volver a correr el diagnostico. Si se conecta en otro puerto, el motor reasigna la cola.")
    }

    # 1a.1 Hay una impresora fisica conectada?
    if (@($devices).Count -eq 0 -and @($problems).Count -eq 0) {
        # En modo Red la ausencia de hardware USB no es un problema: es lo esperado. Reportarla
        # como 'fail' era lo que producia el diagnostico "ninguna impresora fisica conectada" en
        # locales que imprimen por IP y tienen todas sus colas sanas.
        if ($script:RunMode -eq 'Red') {
            Add-Check -Id 'hw.deviceConnected' -Layer 1 -Name 'Hardware USB: no se revisa (modo Red)' -Status 'skipped' -Plane 'hardware' `
                -Evidence @{ usbPrintDevices = 0; skipReason = 'modo_red' } `
                -Recommendation 'Se eligio revisar solo impresoras de red: no se evalua el hardware USB.'
            return
        }
        $yaSabemos = @()
        if ($script:Diagnostics.Contains('impresorasDesconectadas')) { $yaSabemos = @($script:Diagnostics['impresorasDesconectadas']) }
        Add-Check -Id 'hw.deviceConnected' -Layer 1 -Name 'Ninguna impresora fisica conectada (Administrador de dispositivos)' -Status 'fail' -RootCauseCandidate (@($yaSabemos).Count -eq 0) -Plane 'hardware' `
            -Evidence @{ usbPrintDevices = 0; usbPortsHuerfanos = $usbPorts
                         conocidasDesconectadas = @($(if ($script:Diagnostics.Contains('impresorasDesconectadas')) { $script:Diagnostics['impresorasDesconectadas'] } else { @() })) } `
            -ArticleRef 'https://soporte.fu.do/es/articles/11730817' `
            -Recommendation ('Windows NO ve ninguna impresora conectada por USB. Antes de tocar software: 1) que la impresora este encendida (luz fija, no roja); 2) probar OTRO puerto USB de la PC, directo (sin hub); 3) probar otro cable USB; 4) hacer el self-test de la impresora (apagar, mantener FEED, encender) para confirmar que el fierro funciona. ' +
                             $(if (@($usbPorts).Count -gt 0) { "Ojo: existen puertos $($usbPorts -join ', ') en Windows pero son huerfanos (quedaron de una instalacion previa, no tienen device detras)." } else { '' }))
        return
    }

    Set-StepNote ("$(@($identified).Count) impresora(s)")
    $cant = @($identified).Count
    $descartados = @()
    if ($script:Diagnostics.Contains('descartadosNoImpresora')) { $descartados = @($script:Diagnostics['descartadosNoImpresora']) }
    $listado = @($identified | ForEach-Object { $_.nombre + $(if ($_.puerto) { " ($($_.puerto))" } else { '' }) })
    Add-Check -Id 'hw.deviceConnected' -Layer 1 -Name ("Impresoras fisicas detectadas: $cant" + $(if ($cant -gt 0) { ' -> ' + ($listado -join ' | ') } else { '' })) -Status 'ok' -Plane 'hardware' `
        -Evidence @{ cantidad = $cant; impresoras = $identified; livePorts = $devPorts
                     dispositivosUsbDescartados = @($descartados).Count
                     descartados = @($descartados | Select-Object -First 15) } `
        -Recommendation $(if ($cant -gt 1) { "Hay $cant impresoras conectadas. Si el diagnostico apunta a la equivocada, correr con -PrinterName '<nombre exacto de la cola en Windows>'." } else { '' })

    # 1a.1b-pre Impresora presente pero SIN puerto USB asignado por Windows.
    # Caso real: el device USB (clase 07h) esta enumerado y OK, pero no existe ningun nodo
    # USBPRINT con PortName, asi que NINGUNA cola puede imprimirle. El motor probaba puertos
    # sueltos (USB002, USB003) que no corresponden a este device y concluia "ningun puerto
    # imprimio", cuando lo que falta es que Windows le asigne puerto.
    # Las impresoras por Directo USB (Zadig: WinUSB/libusb) no llevan cola de Windows y andan
    # asi a proposito. Antes de esto el motor las contaba como "conectada pero sin puerto
    # asignado" y les hacia un replug por software para que Windows les diera puerto: le estaba
    # tocando el dispositivo a una impresora que funcionaba. Quedan fuera de ese camino.
    $directoUsb = @($identified | Where-Object { [bool]$_.directoUsb })
    if (@($directoUsb).Count -gt 0) {
        Add-Check -Id 'hw.directoUsb' -Layer 1 `
            -Name ('Impresora(s) por Directo USB, sin cola de Windows a proposito: ' + ((@($directoUsb | ForEach-Object { [string]$_.nombre })) -join ' | ')) `
            -Status 'ok' -RootCauseCandidate $false -Plane 'hardware' `
            -Evidence @{ cantidad = @($directoUsb).Count
                         impresoras = @($directoUsb | ForEach-Object { [ordered]@{ nombre = [string]$_.nombre; service = [string]$_.service; instanceId = [string]$_.instanceId } }) } `
            -Recommendation ('Esta(s) impresora(s) estan instaladas con driver de acceso directo (' + ((@($directoUsb | ForEach-Object { [string]$_.service }) | Select-Object -Unique) -join ', ') +
                             '), que es como las deja soporte de nivel 2 con Zadig. En Fudo se configuran como "Directo USB": no llevan cola de Windows y no hay que instalarles ninguna. ' +
                             'El motor no les toca el dispositivo ni les crea cola. Si el cliente no imprime con una de estas, revisar la configuracion en Fudo, no Windows.')
    }
    $paraPuerto = @($identified | Where-Object { -not [bool]$_.directoUsb })
    if ($cant -gt 0 -and @($devPorts).Count -eq 0 -and @($paraPuerto).Count -gt 0) {
        $sinPuerto = @($paraPuerto | ForEach-Object { [string]$_.nombre })
        $idsSinPuerto = @($paraPuerto | Where-Object { -not $_.puerto } | ForEach-Object { [string]$_.instanceId } | Where-Object { $_ })

        # Antes de mandarle al asesor a desenchufar el cable, hacer el replug por software.
        $bind = @{ puertos = @(); nota = '' }
        if (@($idsSinPuerto).Count -gt 0) {
            $rem = Invoke-Remediation -Description 'Reiniciar el dispositivo para que Windows le asigne un puerto USB (replug por software)' `
                -Type 'device.rebind' -Target ($sinPuerto -join ', ') -Before 'sin puerto USB' -After 'puerto asignado' -Reversible $true -Fix {
                    $r = Repair-BindUsbPort -InstanceIds $idsSinPuerto
                    $script:Diagnostics['rebindPorts'] = @($r.puertos)
                    if (@($r.puertos).Count -gt 0) { 'Windows asigno ' + (@($r.puertos) -join ', ') + ' (' + [string]$r.nota + ')' }
                    else { 'no se pudo: ' + [string]$r.nota }
                }
            if ($rem.applied -and $script:Diagnostics.Contains('rebindPorts')) { $bind.puertos = @($script:Diagnostics['rebindPorts']) }
            $bind.nota = [string]$rem.note
        }

        if (@($bind.puertos).Count -gt 0) {
            # Aparecio el puerto: ahora si se puede levantar la cola.
            $devPorts = @($bind.puertos)
            $script:Diagnostics['livePorts'] = @($devPorts)
            $script:Diagnostics['usbPorts']  = @($devPorts)
            $puertoNuevo = @($devPorts)[0]
            # Si el puerto ya tiene una cola del cliente, se adopta: no se crea nada.
            $yaHay = Find-QueueForPort -PortName $puertoNuevo
            if ($yaHay) {
                Add-Check -Id 'hw.noPortBound' -Layer 1 -Name 'Puerto USB asignado (la cola que ya existia sirve)' -Status 'fixed' -RootCauseCandidate $true -Plane 'os' `
                    -Evidence @{ impresoras = $sinPuerto; puertoNuevo = @($devPorts); colaAdoptada = [string]$yaHay.Name } `
                    -ActionTaken ([string]$bind.nota + " | se adopto la cola existente '" + [string]$yaHay.Name + "'") -Reversible $true `
                    -ArticleRef 'https://soporte.fu.do/es/articles/11730817' `
                    -Recommendation ("Windows no le habia asignado puerto USB a la impresora: se reinicio el dispositivo y quedo en $puertoNuevo. " +
                                     "Ya existia la cola '$([string]$yaHay.Name)' apuntando a ese puerto, asi que NO se creo ninguna cola nueva: se usa esa. " +
                                     'Probar una comanda desde Fudo.')
                return
            }
            $oem = ''
            try { $oem = [string](@($identified | Where-Object { $_.driverNombre })[0].driverNombre) } catch {}
            $cola = New-FudoPrinterQueue -PortName $puertoNuevo -PreferDriver $oem
            Add-Check -Id 'hw.noPortBound' -Layer 1 `
                -Name $(if ($cola.ok) { 'Puerto USB asignado y cola creada' } else { 'Puerto USB asignado (falta crear la cola)' }) `
                -Status $(if ($cola.ok) { 'fixed' } else { 'warn' }) -RootCauseCandidate $true -Plane 'os' `
                -Evidence @{ impresoras = $sinPuerto; puertoNuevo = @($devPorts); driverUsado = [string]$cola.driver } `
                -ActionTaken ([string]$bind.nota + ' | ' + [string]$cola.nota) -Reversible $true `
                -ArticleRef 'https://soporte.fu.do/es/articles/16419361' `
                -Recommendation $(if ($cola.ok) {
                        "Windows no le habia asignado puerto USB a la impresora: se reinicio el dispositivo y quedo en $(@($devPorts)[0]), con la cola '$($cola.name)' usando el driver '$($cola.driver)'. Falta registrarla en Fudo (Administracion > Impresoras) con su cocina/area."
                    } else {
                        "El puerto $(@($devPorts)[0]) ya existe, pero no se pudo crear la cola automaticamente: $($cola.nota). Crearla a mano: Agregar impresora > la que busco no esta en la lista > agregar local con ese puerto."
                    })
            return
        }

        Add-Check -Id 'hw.noPortBound' -Layer 1 -Name 'Impresora conectada pero sin puerto USB asignado' -Status 'fail' -RootCauseCandidate $true -Plane 'os' `
            -Evidence @{ impresoras = $sinPuerto; puertosUsbExistentes = $usbPorts; livePorts = @(); rebind = [string]$bind.nota } `
            -ArticleRef 'https://soporte.fu.do/es/articles/11730817' `
            -Recommendation ('Windows ve la impresora conectada pero no le asigno ningun puerto USB (no hay nodo USBPRINT con PortName), ' +
                             'asi que ninguna cola puede imprimirle y cambiar el puerto de la cola no sirve de nada. ' +
                             'Con la impresora ENCENDIDA: desenchufar el USB, esperar 5 segundos y volver a enchufarlo en un puerto directo de la PC (sin hub); ' +
                             'Windows la re-detecta y crea el puerto. Si sigue sin aparecer, instalar el driver "Generico / Solo texto" ' +
                             '(Agregar impresora > la que busco no esta en la lista > agregar local), que es lo que crea el puerto USB.' +
                             $(if (@($usbPorts).Count -gt 0) { " Los puertos $($usbPorts -join ', ') que figuran en Windows son huerfanos: quedaron de instalaciones previas y no apuntan a esta impresora." } else { '' }))
    }

    # 1a.1b Que driver corresponde a cada una
    if ($cant -gt 0) {
        $oemPend = @($identified | Where-Object { $_.driverSugerido -eq 'oem_recomendado' })
        $notas   = @($identified | ForEach-Object { "$($_.nombre): $($_.driverNota)" })
        Add-Check -Id 'hw.driverPlan' -Layer 1 -Name 'Driver que corresponde por impresora' -Status $(if (@($oemPend).Count -gt 0) { 'warn' } else { 'ok' }) -Plane 'os' `
            -Evidence @{ plan = @($identified | ForEach-Object { [ordered]@{ nombre = $_.nombre; tipo = $_.driverSugerido; driver = $_.driverNombre } }) } `
            -ArticleRef 'https://soporte.fu.do/es/articles/16419361' `
            -Recommendation ($notas -join ' ')
    }

    # 1a.2 Dispositivos presentes sin driver (codigo 28 = "no se instalaron los controladores")
    if (@($problems).Count -gt 0) {
        Add-Check -Id 'hw.driverMissing' -Layer 1 -Name 'Dispositivo de impresion sin driver instalado' -Status 'warn' -RootCauseCandidate $true -Plane 'os' `
            -Evidence @{ devices = $problems } `
            -ArticleRef 'https://soporte.fu.do/es/articles/16419361' `
            -Recommendation 'Hay un dispositivo de impresion presente pero sin driver (aparece con signo de exclamacion en el Administrador de dispositivos). El motor va a intentar instalar el driver generico de texto para poder imprimir la prueba.'
    }

    # 1a.3 Device presente pero SIN cola de Windows asociada
    $installed = @()
    try { $installed = @(Get-Printer -ErrorAction SilentlyContinue) } catch {}
    $installedRealPorts = @($installed | Where-Object { -not (Test-IsVirtualPrinter $_).isVirtual } | ForEach-Object { [string]$_.PortName })
    # cruzar cada impresora fisica con su cola de Windows (si tiene)
    if ($script:Diagnostics.Contains('printersConnected')) {
        foreach ($pc in @($script:Diagnostics['printersConnected'])) {
            $cola = ''
            if ($pc.puerto) {
                $m = @($installed | Where-Object { [string]$_.PortName -eq [string]$pc.puerto -and -not (Test-IsVirtualPrinter $_).isVirtual }) | Select-Object -First 1
                if ($m) { $cola = [string]$m.Name }
            }
            $pc['colaWindows'] = $cola
            # 'No Printer Attached' y similares no dicen nada: mostrar el nombre de la cola
            if ($cola -and ([string]$pc.nombre -match '(?i)^(impresora sin identificar|no printer attached|printer|impresora)')) {
                $pc['nombre'] = ($cola + $(if ($pc.puerto) { '' } else { '' }))
            }
        }
    }
    $orphanPorts = @($devPorts | Where-Object { $installedRealPorts -notcontains $_ })
    $script:Diagnostics['orphanLivePorts'] = $orphanPorts

    if (@($orphanPorts).Count -gt 0) {
        Add-Check -Id 'hw.notInstalled' -Layer 1 -Name 'Impresora conectada pero no instalada en Windows' -Status 'warn' -RootCauseCandidate $true -Plane 'os' `
            -Evidence @{ livePortsSinCola = $orphanPorts; colasReales = $installedRealPorts } `
            -ArticleRef 'https://soporte.fu.do/es/articles/16419361' `
            -Recommendation "Hay una impresora conectada en $($orphanPorts -join ', ') que no tiene cola de impresion en Windows. Si esa es la comandera, instalarla sobre ese puerto (driver del fabricante si lo tiene, o 'Generico / Solo texto'). Cuando no hay ninguna otra impresora real, el motor crea una cola FUDO-TEST-* automaticamente para aislar hardware vs configuracion."
    }
}

# ---------------------------------------------------------------------------
# LAYER 1 - Objeto impresora en Windows (descarta virtuales; instala si hace falta)
# ---------------------------------------------------------------------------
function Resolve-TargetPrinter {
    $allPrinters = @()
    try { $allPrinters = @(Get-Printer -ErrorAction Stop) } catch {
        try { $allPrinters = @(Get-CimInstance Win32_Printer -ErrorAction Stop) } catch {}
    }

    $inventory = @($allPrinters | ForEach-Object {
        $v = Test-IsVirtualPrinter $_
        [ordered]@{ name = [string]$_.Name; driver = [string]$_.DriverName; port = [string]$_.PortName
                    isVirtual = [bool]$v.isVirtual; virtualReason = [string]$v.reason; isPos = (Test-IsPosPrinter $_) }
    })
    $script:Diagnostics['printersFound'] = $inventory

    $real = @($allPrinters | Where-Object { -not (Test-IsVirtualPrinter $_).isVirtual })
    $virtualNames = @($inventory | Where-Object { $_.isVirtual } | ForEach-Object { $_.name })

    # El modo acota QUE colas son candidatas a diagnosticarse. Si el filtro deja el conjunto
    # vacio no se fuerza: se avisa y se sigue con todas, porque quedarse sin candidata es peor
    # que diagnosticar una de la otra interfaz.
    if ($script:RunMode -in @('USB','Red') -and @($real).Count -gt 0) {
        $delModo = @($real | Where-Object {
            $esRed = Test-IsNetworkPort -PortName ([string]$_.PortName)
            if ($script:RunMode -eq 'Red') { $esRed } else { -not $esRed }
        })
        if (@($delModo).Count -gt 0) {
            $descartadasPorModo = @($real | Where-Object { [string]$_.Name -notin @($delModo | ForEach-Object { [string]$_.Name }) } | ForEach-Object { [string]$_.Name })
            if (@($descartadasPorModo).Count -gt 0) {
                Add-Check -Id 'printer.modeFilter' -Layer 1 -Name ("Modo $($script:RunMode): se revisan " + @($delModo).Count + ' de ' + @($real).Count + ' impresoras') -Status 'ok' `
                    -Evidence @{ modo = $script:RunMode
                                 seRevisan = @($delModo | ForEach-Object { [string]$_.Name + ' [' + [string]$_.PortName + ']' })
                                 seDescartan = $descartadasPorModo } `
                    -Recommendation ("Quedaron fuera por el modo elegido: " + ($descartadasPorModo -join ', ') + '. Para revisarlas, volver a correr y elegir la otra opcion (o "Ambas").')
            }
            $real = $delModo
        } else {
            # No hay ninguna del tipo elegido. Hasta v3.9 se seguia igual con todas "para no
            # dejar el diagnostico vacio", y eso estaba mal: el motor no solo diagnostica,
            # tambien repara e IMPRIME. Un asesor que eligio Red termino con un ticket de
            # prueba saliendo de la impresora USB del cliente y el log del spooler modificado,
            # sin haberlo pedido (caso reportado en el canal). Ahora se corta y, si hay alguien
            # mirando, se le ofrece seguir; en modo agente no se sigue nunca.
            $otras = @($real | ForEach-Object { [string]$_.Name + ' [' + [string]$_.PortName + ']' })
            $seguir = Confirm-ReviewOtherInterface -Modo ([string]$script:RunMode) -Otras $otras
            Add-Check -Id 'printer.modeFilter' -Layer 1 -Name ("Modo $($script:RunMode): no hay ninguna impresora de ese tipo") -Status 'warn' -Plane 'os' `
                -Evidence @{ modo = $script:RunMode; instaladas = $otras; continuoIgual = $seguir } `
                -Recommendation $(if ($seguir) {
                        "Se eligio revisar $($script:RunMode) y no hay ninguna de ese tipo. El asesor pidio revisar igual las otras: " + ($otras -join ', ') + '.'
                    } else {
                        "Se eligio revisar $($script:RunMode) pero ninguna de las impresoras instaladas es de ese tipo (hay: " + ($otras -join ', ') +
                        "). No se reviso ni se toco ninguna. Si la comandera de este cliente es una de esas, volver a correr y elegir la opcion que corresponda."
                    })
            if (-not $seguir) {
                $script:AbortByMode = $true
                return $null
            }
        }
    }

    # --- Caso A: nombre explicito
    if ($PrinterName) {
        $target = $allPrinters | Where-Object { $_.Name -eq $PrinterName } | Select-Object -First 1
        if ($null -eq $target) {
            Add-Check -Id 'printer.exists' -Layer 1 -Name "Impresora '$PrinterName' presente" -Status 'fail' -RootCauseCandidate $true -Plane 'fudo_config' `
                -Evidence @{ requested = $PrinterName; available = @($inventory | ForEach-Object { $_.name }) } `
                -Recommendation "La impresora '$PrinterName' no existe en Windows. Verificar el nombre exacto (Panel de control > Dispositivos e impresoras) o reinstalarla."
            return $null
        }
        $v = Test-IsVirtualPrinter $target
        if ($v.isVirtual) {
            Add-Check -Id 'printer.virtualTarget' -Layer 1 -Name "'$PrinterName' es una impresora virtual" -Status 'fail' -RootCauseCandidate $true -Plane 'fudo_config' `
                -Evidence @{ requested = $PrinterName; reason = $v.reason } `
                -Recommendation "'$PrinterName' es una impresora virtual de Windows ($($v.reason)): no puede imprimir comandas. Elegir la impresora termica real."
            return $null
        }
        Add-Check -Id 'printer.exists' -Layer 1 -Name "Impresora '$($target.Name)' presente en Windows" -Status 'ok' `
            -Evidence @{ name = [string]$target.Name; driver = [string]$target.DriverName; port = [string]$target.PortName }
        # v3.8: a diferencia del Caso C, este camino no llamaba a Get-PrinterQueues, asi que
        # $script:Diagnostics['colas'] quedaba sin llenar y la telemetria reportaba
        # cantidadColas=0 pese a que printer.exists dio 'ok' (se vio en 43db236c6151dd8c).
        $script:Diagnostics['colas'] = @(Get-PrinterQueues)
        return $target
    }

    # --- Caso B: no hay ninguna cola real -> intentar instalarla sobre el puerto con device vivo
    if (@($real).Count -eq 0) {
        $hwCount = -1
        if ($script:Diagnostics.Contains('hwDeviceCount')) { $hwCount = [int]$script:Diagnostics['hwDeviceCount'] }

        # Sin hardware detectado no tiene sentido crear colas: el problema es fisico (capa 1a).
        if ($hwCount -eq 0) {
            Add-Check -Id 'printer.exists' -Layer 1 -Name 'Sin impresora real instalada y sin hardware detectado' -Status 'fail' -RootCauseCandidate $true -Plane 'hardware' `
                -Evidence @{ soloVirtuales = $virtualNames; hwDevices = 0 } `
                -ArticleRef 'https://soporte.fu.do/es/articles/11730817' `
                -Recommendation ("En esta PC solo hay impresoras virtuales ($($virtualNames -join ', ')) y Windows no detecta ninguna impresora fisica conectada. " +
                                 'Resolver primero el hardware (ver check hw.deviceConnected): energia, cable y puerto USB. Recien despues instalar el driver y registrarla en Fudo.')
            return $null
        }

        $livePorts = @()
        if ($script:Diagnostics.Contains('orphanLivePorts')) { $livePorts = @($script:Diagnostics['orphanLivePorts'] | Where-Object { $_ }) }
        if (@($livePorts).Count -eq 0 -and $script:Diagnostics.Contains('livePorts')) { $livePorts = @($script:Diagnostics['livePorts'] | Where-Object { $_ }) }
        # Solo caemos a los USB00x genericos si HAY device presente pero sin mapeo de puerto conocido
        if (@($livePorts).Count -eq 0 -and $hwCount -gt 0 -and $script:Diagnostics.Contains('usbPorts')) { $livePorts = @($script:Diagnostics['usbPorts']) }

        if (@($livePorts).Count -eq 0 -or -not $InstallGenericDriver) {
            Add-Check -Id 'printer.exists' -Layer 1 -Name 'Sin impresora real instalada (solo impresoras virtuales de Windows)' -Status 'fail' -RootCauseCandidate $true -Plane 'os' `
                -Evidence @{ soloVirtuales = $virtualNames; puertosCandidatos = $livePorts; installGenericDriver = [bool]$InstallGenericDriver } `
                -ArticleRef 'https://soporte.fu.do/es/articles/16419361' `
                -Recommendation ("En esta PC solo hay impresoras virtuales de Windows ($($virtualNames -join ', ')): ninguna puede imprimir una comanda. " +
                                 'Instalar la impresora termica (driver del fabricante o generico de texto) y registrarla en Fudo.')
            return $null
        }

        $chosenName = ''
        $rem = Invoke-Remediation -Description "Instalar cola de prueba con driver generico de texto en $($livePorts -join ', ')" -Type 'printer.install_generic' -Target ($livePorts -join ',') `
            -Before 'sin cola real' -After 'cola FUDO-TEST creada' -Reversible $true -Fix {
                $notes = @()
                foreach ($lp in $livePorts) {
                    try {
                        $n = New-FudoTestPrinter -PortName $lp
                        if ($n) { $notes += "cola '$n' creada en $lp"; break }
                    } catch { $notes += "fallo en $lp : $($_.Exception.Message)" }
                }
                ($notes -join ' | ')
            }
        if ($rem.applied -and $rem.note -match "cola '([^']+)'") { $chosenName = $Matches[1] }

        if ($chosenName) {
            $target = $null
            try { $target = Get-Printer -Name $chosenName -ErrorAction Stop } catch {}
            Add-Check -Id 'printer.exists' -Layer 1 -Name "Cola de prueba '$chosenName' instalada con driver generico" -Status 'fixed' -RootCauseCandidate $true -Plane 'os' `
                -Evidence @{ created = $chosenName; port = @($livePorts)[0]; soloVirtuales = $virtualNames } -ActionTaken $rem.note -Reversible $true `
                -ArticleRef 'https://soporte.fu.do/es/articles/16419361' `
                -Recommendation "La impresora estaba conectada pero no instalada. Se creo '$chosenName' (Generic / Text Only) para la prueba fisica. Si imprime, instalar/registrar la impresora definitiva en Fudo y borrar la de prueba con: Remove-Printer -Name '$chosenName'."
            return $target
        }

        Add-Check -Id 'printer.exists' -Layer 1 -Name 'Sin impresora real instalada (no se pudo crear la cola de prueba)' -Status 'fail' -RootCauseCandidate $true -Plane 'os' `
            -Evidence @{ soloVirtuales = $virtualNames; puertosProbados = $livePorts; nota = $rem.note } `
            -ArticleRef 'https://soporte.fu.do/es/articles/16419361' `
            -Recommendation ('No se pudo crear la cola de prueba automaticamente (' + $rem.note + '). Instalar a mano: Panel de control > Dispositivos e impresoras > Agregar impresora > la que busco no esta en la lista > Agregar impresora local con puerto ' + (@($livePorts)[0]) + ' > Generico / Solo texto.')
        return $null
    }

    # --- Caso C: hay colas reales.
    # Primero miramos el estado de TODAS: si una esta fallando (cola tapada, offline, puerto
    # muerto) esa es la que hay que diagnosticar. Las que andan bien no se tocan.
    $colas = @(Get-PrinterQueues)
    # La telemetria y el resumen siguen viendo TODAS las colas del cliente: el modo acota que
    # se diagnostica, no que se informa. Sin esto, en modo Red se elegia igual la inkjet USB
    # "enferma" y la termica de red sana quedaba sin mirar (caso real 52564e5e).
    $script:Diagnostics['colas'] = $colas
    $colasDelModo = $colas
    if ($script:RunMode -in @('USB','Red')) {
        $filtradas = @($colas | Where-Object {
            $esRed = Test-IsNetworkPort -PortName ([string]$_.puerto)
            if ($script:RunMode -eq 'Red') { $esRed } else { -not $esRed }
        })
        if (@($filtradas).Count -gt 0) { $colasDelModo = $filtradas }
    }
    $colas = $colasDelModo
    if (@($colas).Count -gt 0) {
        $enfermas = @($colas | Where-Object { [int]$_.score -gt 0 })
        $sanas    = @($colas | Where-Object { [int]$_.score -eq 0 })

        if (@($colas).Count -gt 1) {
            Add-Check -Id 'printer.multiple' -Layer 1 -Name ("Hay $(@($colas).Count) impresoras instaladas en Windows") -Status $(if (@($enfermas).Count -gt 0) { 'warn' } else { 'ok' }) `
                -Evidence @{ colas = @($colas | ForEach-Object { [ordered]@{ nombre = $_.nombre; puerto = $_.puerto; estado = $_.estado; trabajos = $_.trabajos; sintomas = $_.sintomas } }) } `
                -Recommendation $(if (@($enfermas).Count -gt 0) {
                        "Se diagnostica '" + [string]@($enfermas)[0].nombre + "', que es la que presenta problemas. " +
                        $(if (@($sanas).Count -gt 0) { 'Las que estan funcionando (' + (@($sanas | ForEach-Object { $_.nombre }) -join ', ') + ') no se tocan.' } else { '' })
                    } else { 'Ninguna presenta problemas evidentes. Si el cliente dice que una no imprime, correr con -PrinterName "<nombre exacto>".' })
        }

        if (@($enfermas).Count -gt 0) {
            $elegida = @($enfermas)[0]
            $target = $real | Where-Object { [string]$_.Name -eq [string]$elegida.nombre } | Select-Object -First 1
            if ($target) {
                Add-Check -Id 'printer.exists' -Layer 1 -Name "Impresora '$($target.Name)' presente en Windows (la que falla)" -Status 'ok' `
                    -Evidence @{ name = [string]$target.Name; driver = [string]$target.DriverName; port = [string]$target.PortName
                                 sintomas = @($elegida.sintomas); score = $elegida.score } `
                    -Recommendation ("Sintomas detectados en '$($target.Name)': " + (@($elegida.sintomas) -join '; ') + '.')
                return $target
            }
        }
    }

    $pos = @($real | Where-Object { Test-IsPosPrinter $_ })
    $byPort = @($real | Where-Object { ([string]$_.PortName -match '^USB\d+') -or ([string]$_.PortName -match '9100') -or ([string]$_.PortName -match '^\d{1,3}(\.\d{1,3}){3}') -or ([string]$_.PortName -match '^IP_') })
    $ranked = @(@($pos) + @($byPort) + @($real) | Select-Object -Unique)
    $target = @($ranked)[0]

    if (@($pos).Count -eq 0) {
        Add-Check -Id 'printer.autodetect' -Layer 1 -Name 'Autodeteccion de impresora termica' -Status 'warn' `
            -Evidence @{ elegida = [string]$target.Name; reales = @($real | ForEach-Object { [string]$_.Name }); descartadasVirtuales = $virtualNames } `
            -Recommendation "No se reconocio marca POS/termica conocida. Se tomo '$($target.Name)' (impresora real, no virtual). Si no es la correcta, pasar -PrinterName."
    } elseif (@($ranked).Count -gt 1) {
        Add-Check -Id 'printer.autodetect' -Layer 1 -Name 'Autodeteccion de impresora termica' -Status 'ok' `
            -Evidence @{ elegida = [string]$target.Name; candidatas = @($ranked | ForEach-Object { [string]$_.Name }); descartadasVirtuales = $virtualNames } `
            -Recommendation $(if (@($pos).Count -gt 1) { "Hay varias termicas; se tomo '$($target.Name)'. Usar -PrinterName para desambiguar." } else { '' })
    }

    Add-Check -Id 'printer.exists' -Layer 1 -Name "Impresora '$($target.Name)' presente en Windows" -Status 'ok' `
        -Evidence @{ name = [string]$target.Name; driver = [string]$target.DriverName; port = [string]$target.PortName; descartadasVirtuales = $virtualNames }
    return $target
}

function Wait-ForPrinterReconnect {
    <#
      Espera a que alguien desenchufe y vuelva a enchufar el USB de la impresora.
      Windows re-enumera el dispositivo y le asigna un puerto USB00x: eso es lo que buscamos.
      Devuelve el puerto nuevo (o '' si no aparecio nada).
    #>
    param([int]$TimeoutSec = 120)

    $script:PresentIds = $null
    $antesDev = @(Get-UsbPrintDevices)
    $antesIds = @($antesDev | ForEach-Object { ([string]$_.instanceId).ToUpper() })
    $antesPorts = @($antesDev | Where-Object { $_.portName } | ForEach-Object { [string]$_.portName })

    $t0 = Get-Date
    while (((Get-Date) - $t0).TotalSeconds -lt $TimeoutSec) {
        $restante = [int]($TimeoutSec - ((Get-Date) - $t0).TotalSeconds)
        Write-LiveStatus ("Esperando que desconectes y vuelvas a conectar el USB de la impresora... ${restante}s")
        Start-Sleep -Seconds 3

        $script:PresentIds = $null
        $ahora = @(Get-UsbPrintDevices)
        $nuevosDev = @($ahora | Where-Object { $antesIds -notcontains ([string]$_.instanceId).ToUpper() })
        $puertosNuevos = @($ahora | Where-Object { $_.portName -and ($antesPorts -notcontains [string]$_.portName) } | ForEach-Object { [string]$_.portName })

        if (@($puertosNuevos).Count -gt 0) { return [string]@($puertosNuevos)[0] }
        if (@($nuevosDev).Count -gt 0) {
            # aparecio el device pero Windows todavia no le mapeo el puerto: darle un momento
            Start-Sleep -Seconds 4
            $script:PresentIds = $null
            $ahora2 = @(Get-UsbPrintDevices)
            $pp = @($ahora2 | Where-Object { $_.portName } | ForEach-Object { [string]$_.portName })
            $nuevo = @($pp | Where-Object { $antesPorts -notcontains $_ })
            if (@($nuevo).Count -gt 0) { return [string]@($nuevo)[0] }
            if (@($pp).Count -gt 0) { return [string]@($pp)[0] }
        }
    }
    return ''
}

function Invoke-ReconnectFlow {
    <#
      Caso tipico: la cola apunta a un puerto muerto. La solucion real suele ser reconectar el
      cable USB (Windows re-enumera y crea el puerto) y despues apuntar la cola ahi.
      Este flujo lo acompana: espera la reconexion, reasigna la cola al puerto nuevo, prueba un
      ticket y, si la cola esta rota, la recrea con el mismo nombre.
      Devuelve @{ recovered = $bool; note = '...'; port = '...' }
    #>
    param($Printer)

    if (-not $AutoFix -or $DryRun) { return @{ recovered = $false; note = 'sin auto-fix / dry-run'; port = '' } }

    $quiere = $false
    if ($script:ForceWaitReconnect) { $quiere = $true }
    elseif ($script:BoundParams -and $script:BoundParams.ContainsKey('WaitReconnect')) { $quiere = [bool]$WaitReconnect }
    elseif (Test-IsInteractiveConsole) {
        Suspend-LiveStatus
        [Console]::Error.WriteLine('')
        [Console]::Error.WriteLine('  ------------------------------------------------------------')
        [Console]::Error.WriteLine("  La cola '$($Printer.Name)' apunta a $($Printer.PortName), donde no hay ningun")
        [Console]::Error.WriteLine('  dispositivo conectado. Lo que suele resolverlo es desenchufar el')
        [Console]::Error.WriteLine('  cable USB de la impresora y volver a enchufarlo (con la impresora')
        [Console]::Error.WriteLine('  encendida): Windows la vuelve a detectar y le asigna un puerto.')
        [Console]::Error.WriteLine('  ------------------------------------------------------------')
        $ans = ''
        $ans = [string](Read-DoctorLine -Prompt '  Espero mientras lo haces? (s = si / cualquier otra tecla = no)')
        $quiere = ($ans -match '(?i)^\s*(s|si|s\u00ED|y|yes)\s*$')
    }
    if (-not $quiere) { return @{ recovered = $false; note = 'no se espero la reconexion'; port = '' } }

    $puerto = Wait-ForPrinterReconnect -TimeoutSec $ReconnectTimeoutSec
    if (-not $puerto) {
        return @{ recovered = $false; note = "se esperaron $ReconnectTimeoutSec segundos y Windows no detecto ninguna impresora nueva"; port = '' }
    }

    Write-StepDetail ("la impresora reaparecio en " + $puerto + ", apuntando la cola ahi")
    $script:ReconnectedPort = $puerto

    # 1) reasignar la cola al puerto nuevo y probar
    $notas = @()
    try {
        Set-Printer -Name $Printer.Name -PortName $puerto -ErrorAction Stop
        Add-Action -Type 'printer.setport' -Target ([string]$Printer.Name) -Before ([string]$Printer.PortName) -After $puerto
        $notas += "cola reasignada a $puerto"
        Start-Sleep -Milliseconds 800
        Initialize-RawPrinterHelper
        $ticket = [System.Text.Encoding]::GetEncoding(437).GetBytes((Get-EscPosTestTicket -Caption 'FUDO RECONEXION'))
        if ([FudoRawPrinter]::SendBytes([string]$Printer.Name, $ticket)) {
            Start-Sleep -Milliseconds 1800
            $pend = @()
            try { $pend = @(Get-PrintJob -PrinterName ([string]$Printer.Name) -ErrorAction SilentlyContinue | Where-Object { [string]$_.DocumentName -match '(?i)fudo' }) } catch {}
            if (@($pend).Count -eq 0) {
                return @{ recovered = $true; note = ($notas -join ' | ') + ' y el ticket de prueba salio'; port = $puerto }
            }
            $notas += 'el ticket quedo en la cola'
        } else { $notas += 'el envio RAW fallo' }
    } catch { $notas += "no se pudo reasignar el puerto: $($_.Exception.Message)" }

    # 2) la cola esta rota: recrearla con el mismo nombre en el puerto que ya sabemos bueno
    $rec = Repair-QueueRecreate -Printer $Printer -CandidatePorts @($puerto)
    if ($rec.applied) {
        return @{ recovered = $true; note = ($notas -join ' | ') + ' | ' + [string]$rec.note; port = $puerto }
    }
    return @{ recovered = $false; note = ($notas -join ' | ') + ' | ' + [string]$rec.note; port = $puerto }
}

function Test-Layer1-PrinterState {
    param($Printer)
    if ($null -eq $Printer) { return }

    # Estado via WMI Win32_Printer (metodos utiles: Resume, CancelAllJobs, PrintTestPage; props WorkOffline/PrinterState)
    $wmi = $null
    try { $wmi = Get-CimInstance Win32_Printer -Filter "Name='$($Printer.Name -replace "'","''")'" -ErrorAction Stop } catch {}

    $workOffline = $false
    $printerState = $null
    $printerStatus = $null
    if ($wmi) {
        try { $workOffline = [bool]$wmi.WorkOffline } catch {}
        try { $printerState = [int]$wmi.PrinterState } catch {}
        try { $printerStatus = [int]$wmi.PrinterStatus } catch {}
    }
    $script:Diagnostics['printer'] = [ordered]@{
        name = $Printer.Name; driver = [string]$Printer.DriverName; port = [string]$Printer.PortName
        workOffline = $workOffline; printerState = $printerState; printerStatus = $printerStatus
    }

    # 1.0 La cola apunta a un puerto sin hardware presente => esta desconectada.
    # Sin esto se "repara" el offline de una impresora desenchufada, que vuelve a ponerse offline.
    $portLive = Test-PortHasLiveDevice -PortName ([string]$Printer.PortName)
    if (-not $portLive) {
        $conocida = @()
        if ($script:Diagnostics.Contains('impresorasDesconectadas')) { $conocida = @($script:Diagnostics['impresorasDesconectadas']) }

        # La solucion real suele ser reconectar el USB: si hay alguien ahi, lo acompanamos.
        $flow = Invoke-ReconnectFlow -Printer $Printer
        if ($flow.recovered) {
            Add-Check -Id 'printer.disconnected' -Layer 1 -Name "Impresora '$($Printer.Name)' recuperada tras reconectar el USB" `
                -Status 'fixed' -RootCauseCandidate $true -Plane 'hardware' `
                -Evidence @{ printer = [string]$Printer.Name; puertoAnterior = [string]$Printer.PortName; puertoNuevo = [string]$flow.port } `
                -ActionTaken ([string]$flow.note) `
                -ArticleRef 'https://soporte.fu.do/es/articles/11730817' `
                -Recommendation ("La impresora estaba enumerada en un puerto que ya no existia. Al reconectar el USB, Windows la detecto en $($flow.port) y la cola quedo apuntando ahi. " +
                                 'Verificar en Fudo que siga asignada a su area/cocina y mandar una comanda de prueba.')
            return $wmi
        }

        Add-Check -Id 'printer.disconnected' -Layer 1 -Name "La impresora '$($Printer.Name)' esta desconectada (puerto $($Printer.PortName) sin dispositivo)" `
            -Status 'fail' -RootCauseCandidate $true -Plane 'hardware' `
            -Evidence @{ printer = [string]$Printer.Name; port = [string]$Printer.PortName; workOffline = $workOffline
                         livePorts = @($(if ($script:Diagnostics.Contains('livePorts')) { $script:Diagnostics['livePorts'] } else { @() }))
                         conocidasDesconectadas = $conocida } `
            -ArticleRef 'https://soporte.fu.do/es/articles/11730817' `
            -Recommendation ("La cola '$($Printer.Name)' apunta a $($Printer.PortName), pero ahi no hay ningun dispositivo conectado. " +
                             'Con la impresora encendida, DESENCHUFAR el cable USB y volver a ENCHUFARLO: Windows la re-detecta y le asigna un puerto nuevo. ' +
                             'Correr el script de nuevo y responder que si cuando pregunte si espera la reconexion: apunta la cola al puerto nuevo, prueba un ticket y, si la cola esta rota, la recrea con el mismo nombre. ' +
                             'Si tras reconectar Windows sigue sin verla, probar otro cable y otro puerto USB directo (sin hub).' +
                             $(if (@($flow.note)) { ' [' + [string]$flow.note + ']' } else { '' }))
        return $wmi
    }

    # 1.1 Impresora en 'Usar impresora sin conexion' / offline
    if ($workOffline) {
        $rem = Invoke-Remediation -Description 'Quitar modo offline (Usar impresora sin conexion) + reactivar' -Type 'printer.online' -Target $Printer.Name `
            -Before 'WorkOffline=True' -After 'WorkOffline=False' -Fix {
                # Resume por WMI + restart spooler suele reactivar el device
                try { $null = Invoke-CimMethod -InputObject $wmi -MethodName 'Resume' -ErrorAction SilentlyContinue } catch {}
                Restart-Service -Name 'Spooler' -Force -ErrorAction SilentlyContinue
                Start-Sleep -Milliseconds 800
                $after = Get-CimInstance Win32_Printer -Filter "Name='$($Printer.Name -replace "'","''")'"
                "WorkOffline ahora = $($after.WorkOffline)"
            }
        Add-Check -Id 'printer.offline' -Layer 1 -Name 'Impresora marcada offline / pausada' -Status $(if($rem.applied){'fixed'}else{'warn'}) -RootCauseCandidate $true `
            -Evidence @{ workOffline = $workOffline } -ActionTaken $rem.note `
            -Recommendation 'El estado offline hace que los trabajos queden en cola sin imprimir.'
    } else {
        Add-Check -Id 'printer.offline' -Layer 1 -Name 'Impresora en linea (no offline)' -Status 'ok' -Evidence @{ workOffline = $false }
    }

    # 1.2 Impresora pausada (PrinterState bit 1 = paused en algunas versiones) -> Resume
    $paused = $false
    if ($null -ne $printerState) { $paused = (($printerState -band 1) -ne 0) }
    if ($paused) {
        $rem = Invoke-Remediation -Description 'Reanudar impresora pausada' -Type 'printer.resume' -Target $Printer.Name `
            -Before 'paused' -After 'resumed' -Fix {
                $null = Invoke-CimMethod -InputObject $wmi -MethodName 'Resume' -ErrorAction SilentlyContinue
                'Resume() invocado'
            }
        Add-Check -Id 'printer.paused' -Layer 1 -Name 'Impresora pausada' -Status $(if($rem.applied){'fixed'}else{'warn'}) -RootCauseCandidate $true `
            -Evidence @{ printerState = $printerState } -ActionTaken $rem.note
    }

    return $wmi
}

# ---------------------------------------------------------------------------
# LAYER 2 - Salud de la cola de impresion
# ---------------------------------------------------------------------------
function Test-Layer2-Queue {
    param($Printer, $Wmi)
    if ($null -eq $Printer) { return }
    Write-StepDetail 'revisando trabajos en cola'
    $jobs = @()
    try { $jobs = @(Get-PrintJob -PrinterName $Printer.Name -ErrorAction Stop) } catch {}
    Set-StepNote ("$(@($jobs).Count) trabajo(s)")
    $script:Diagnostics['queueDepth'] = @($jobs).Count

    if (@($jobs).Count -eq 0) {
        Add-Check -Id 'queue.health' -Layer 2 -Name 'Cola de impresion' -Status 'ok' -Evidence @{ jobs = 0 }
        return
    }

    # Detectar trabajos trabados/errored o antiguos
    $stuck = @($jobs | Where-Object {
        $st = [string]$_.JobStatus
        ($st -match 'Error') -or ($st -match 'Blocked') -or ($st -match 'Offline') -or ($st -match 'PaperOut') -or `
        ($_.SubmittedTime -and ($_.SubmittedTime -lt (Get-Date).AddMinutes(-5)))
    })
    $isStuck = (@($stuck).Count -gt 0) -or (@($jobs).Count -ge 3)

    if ($isStuck) {
        $rem = Invoke-Remediation -Description "Limpiar cola trabada ($(@($jobs).Count) trabajos) en '$($Printer.Name)'" -Type 'queue.purge' -Target $Printer.Name `
            -Before "$(@($jobs).Count) jobs" -After '0 jobs' -Reversible $false `
            -Impact 'se descartan las comandas que estan esperando en la cola; hay que volver a imprimirlas desde Fudo' -Fix {
                try {
                    if ($Wmi) { $null = Invoke-CimMethod -InputObject $Wmi -MethodName 'CancelAllJobs' -ErrorAction Stop; 'CancelAllJobs() OK' }
                    else { Get-PrintJob -PrinterName $Printer.Name | Remove-PrintJob -ErrorAction SilentlyContinue; 'Remove-PrintJob OK' }
                } catch {
                    Get-PrintJob -PrinterName $Printer.Name | Remove-PrintJob -ErrorAction SilentlyContinue; 'Remove-PrintJob (fallback) OK'
                }
            }
        # v3.18: purgar y volver a purgar no estaba alcanzando y no habia con que entender por
        # que. Un asesor destrabo a mano un local con 218 y 1182 comandas encoladas y conto lo
        # que el motor no podia ver: el cliente tenia DECENAS de impresoras instaladas, varias ya
        # muertas, y cada prueba generaba unos 50 trabajos. Purgar funcionaba perfecto -las
        # comandas se borraban- y no podia ganar nunca. Lo que resolvio el caso fue borrar
        # impresoras. Asi que ahora se MIDE: cuantos habia, cuantos quedaron, cuantos volvieron
        # y contra cuantas colas instaladas. Medir primero; borrar colas del cliente es
        # irreversible y no se hace sin datos.
        $antes = @($jobs).Count
        $despues = $antes
        $rebote = $antes
        if ($rem.applied) {
            try { $despues = @(Get-PrintJob -PrinterName $Printer.Name -ErrorAction SilentlyContinue).Count } catch {}
            Start-Sleep -Milliseconds 2500
            try { $rebote = @(Get-PrintJob -PrinterName $Printer.Name -ErrorAction SilentlyContinue).Count } catch {}
        }
        $colasTodas = @()
        if ($script:Diagnostics.Contains('colas')) { $colasTodas = @($script:Diagnostics['colas'] | Where-Object { -not $_.esDePrueba }) }
        $sinHw = @($colasTodas | Where-Object { $_.Contains('puertoVivo') -and (-not $_.puertoVivo) })
        $script:Diagnostics['purgaMedicion'] = [ordered]@{
            antes = $antes; despues = $despues; rebote = $rebote
            volvieron = [int]([Math]::Max(0, $rebote - $despues))
            colasInstaladas = @($colasTodas).Count; colasSinHardware = @($sinHw).Count
        }
        # Si volvieron trabajos despues de purgar, purgar no es la solucion: algo los esta
        # regenerando. Con muchas colas instaladas, una sola comanda se multiplica.
        if ($rem.applied -and $rebote -gt $despues) {
            Add-Check -Id 'queue.rebotePurga' -Layer 2 -Name ("La cola se volvio a llenar despues de limpiarla (" + [int]($rebote - $despues) + " trabajo(s) en 2 segundos)") `
                -Status 'warn' -RootCauseCandidate $false -Plane 'os' `
                -Evidence @{ antes = $antes; despues = $despues; rebote = $rebote
                             colasInstaladas = @($colasTodas).Count; colasSinHardware = @($sinHw).Count } `
                -Recommendation ('Limpiar la cola funciono (de ' + $antes + ' trabajos a ' + $despues + ') pero volvieron ' + [int]($rebote - $despues) +
                                 ' en dos segundos, asi que limpiarla no es la solucion: algo los esta regenerando. ' +
                                 'Esta PC tiene ' + @($colasTodas).Count + ' impresora(s) instalada(s) en Windows' +
                                 $(if (@($sinHw).Count -gt 0) { ' y ' + @($sinHw).Count + ' de ellas no tienen hardware presente' } else { '' }) +
                                 '. Cuando hay muchas impresoras instaladas, una sola comanda se multiplica en decenas de trabajos y la cola se tapa sola: ' +
                                 'revisar en Dispositivos e impresoras y borrar las que el cliente ya no usa. Un caso real se resolvio asi.')
        }
        # v3.19: la 3.18 agrego la medicion y despues nadie la leia. En 11 de 32 corridas con
        # purgaMedicion la cola NO bajo (despues >= antes) y 7 de esas quedaron con
        # queue.health = fixed y "Cola de impresion trabada" listada como reparacion aplicada.
        # El motor decia que habia arreglado lo que no habia arreglado. Es la quinta vez que
        # aparece el mismo patron en este proyecto: reparar y no verificar el efecto.
        # Como autoFixesApplied se arma con los checks en 'fixed', sacarlo de 'fixed' tambien lo
        # saca de la lista de reparaciones.
        $bajo = ($despues -lt $antes)
        $purgaVacia = ([bool]$rem.applied -and -not $bajo)
        Add-Check -Id 'queue.health' -Layer 2 `
            -Name $(if ($purgaVacia) { 'La cola se limpio y no bajo: sigue trabada' } else { 'Cola de impresion trabada' }) `
            -Status $(if ($purgaVacia) { 'fail' } elseif ($rem.applied) { 'fixed' } else { 'warn' }) -RootCauseCandidate $true `
            -Evidence @{ jobs = @($jobs).Count; stuck = @($stuck).Count; statuses = @($jobs | ForEach-Object { [string]$_.JobStatus })
                         antes = $antes; despues = $despues; rebote = $rebote; bajo = [bool]$bajo
                         colasInstaladas = @($colasTodas).Count; colasSinHardware = @($sinHw).Count } `
            -ActionTaken $rem.note -Reversible $false `
            -Recommendation $(if ($purgaVacia) {
                    'Se ejecuto la limpieza de la cola y la cantidad de trabajos no bajo (de ' + $antes + ' a ' + $despues + '): la purga no esta ganando. ' +
                    $(if (@($sinHw).Count -gt 0) {
                        'Esta PC tiene ' + @($colasTodas).Count + ' impresora(s) instalada(s) en Windows y ' + @($sinHw).Count + ' de ellas sin hardware presente: cada comanda se multiplica por cada cola y la cola se vuelve a tapar mas rapido de lo que se limpia. Revisar en Dispositivos e impresoras y borrar las que el cliente ya no usa.'
                      } else {
                        'Revisar si hay algo regenerando trabajos (varias impresoras instaladas apuntando al mismo puerto) o si el spooler no esta drenando: reiniciar el servicio de cola de impresion y volver a correr el diagnostico.'
                      })
                } elseif ($rem.applied) {
                    'Un trabajo trabado bloquea toda la cola: se limpio (de ' + $antes + ' trabajos a ' + $despues + '). Volver a imprimir desde Fudo las comandas que estaban esperando.'
                } elseif (@($jobs).Count -ge 50) {
                    # v3.18: antes esto afirmaba "eso CONFIRMA que el problema no es Fudo".
                    # No lo confirma: con muchas impresoras instaladas una sola comanda se
                    # multiplica en decenas de trabajos, asi que la cantidad no dice cuantas
                    # comandas mando Fudo. Se vio una PC con 1182 trabajos que eran unas pocas
                    # comandas multiplicadas por las colas instaladas.
                    "Hay $(@($jobs).Count) trabajos acumulados, asi que a esta cola SI le llegaron comandas y no salieron: el problema esta en la impresora o en su cola, no en que Fudo no mande. Ojo: la cantidad no dice cuantas comandas se mandaron -- si el cliente tiene muchas impresoras instaladas en Windows, una sola comanda se multiplica en decenas de trabajos; en ese caso limpiar la cola no alcanza y hay que borrar las impresoras que ya no usa. Limpiar la cola descarta esos trabajos (son comandas viejas que ya no sirven). Para hacerlo: correr el script en la consola y responder 's' cuando pregunte, o pasar -AllowQueuePurge `$true, o a mano: Get-PrintJob -PrinterName '$($Printer.Name)' | Remove-PrintJob"
                } else {
                    "Un trabajo trabado bloquea toda la cola: las comandas nuevas no salen hasta limpiarla. Limpiarla descarta los $(@($jobs).Count) trabajos pendientes (hay que reimprimirlos desde Fudo). Para hacerlo: correr el script en la consola y responder 's' cuando pregunte, o pasar -AllowQueuePurge `$true, o a mano: Get-PrintJob -PrinterName '$($Printer.Name)' | Remove-PrintJob"
                })
    } else {
        Add-Check -Id 'queue.health' -Layer 2 -Name 'Cola de impresion' -Status 'warn' `
            -Evidence @{ jobs = @($jobs).Count; note = 'trabajos presentes pero no evidentemente trabados' }
    }
}

function Test-Layer2-OtherQueuesBacklog {
    <#
      v3.11: la capa 2 solo miraba la cola OBJETIVO. En una PC del parque, BARRA
      [192.168.0.17] tenia 93 trabajos sin drenar y COCINA [192.168.0.50] otros 13, y la causa
      raiz que gano fue "Ninguna impresora fisica conectada" teniendo una POS-80 en LPT1: sana.
      El mismo caso lo cerro un asesor a mano preguntando "cola de impresion?".
      Una cola del cliente con comandas encoladas que nadie drena es un sintoma de primera
      clase, y ademas es el sintoma que MAS informacion trae: si Fudo llego a encolar comandas,
      el problema no esta en la configuracion de Fudo sino en esa cola o en su impresora.
    #>
    param($Printer)
    $objetivo = ''
    if ($Printer) { $objetivo = [string]$Printer.Name }
    $colas = @()
    try { if ($script:Diagnostics.Contains('colas')) { $colas = @($script:Diagnostics['colas']) } } catch {}
    $delCliente = @($colas | Where-Object { -not $_.esDePrueba })
    # v3.12: el umbral de 3 trabajos dejaba fuera el caso mas frecuente. Se vio una PC con
    # REPOSTERIA [192.168.1.202] arrastrando UN trabajo trabado 28 minutos en tres corridas
    # seguidas sin que este chequeo dijera nada (19 de 19 corridas 3.11 en 'ok'). Un solo
    # trabajo que no drena desde hace rato ya prueba que Fudo encolo y que la cola no sale.
    # Ahora entra desde 1 trabajo, pero lo que BLOQUEA el cierre y compite como causa raiz
    # sigue siendo el atasco de verdad (3 o mas y el mas viejo de hace 5 minutos o mas).
    $conTrabajos = @($delCliente | Where-Object {
        ([string]$_.nombre -ne $objetivo) -and ([int]$_.trabajos -ge 1)
    })
    # Atasco: acumula Y el mas viejo lleva rato. Es lo unico que puede ser causa raiz.
    $trabadas = @($conTrabajos | Where-Object { [int]$_.trabajos -ge 3 -and [int]$_.minutosMasViejo -ge 5 })
    # Sintoma informativo: pocos trabajos pero uno viejo, o varios recien encolados.
    $aInformar = @($conTrabajos | Where-Object { [int]$_.trabajos -ge 3 -or [int]$_.minutosMasViejo -ge 5 })
    if (@($aInformar).Count -eq 0) {
        Add-Check -Id 'queue.otherBacklog' -Layer 2 -Name 'Ninguna otra cola con comandas acumuladas' -Status 'ok' `
            -Evidence @{ colasRevisadas = @($delCliente).Count; objetivo = $objetivo
                         conTrabajos = @($conTrabajos).Count; trabadas = 0 }
        return
    }
    $conTrabajos = @($aInformar)
    # Si el puerto de la cola trabada sigue sirviendo (esta vivo, o no es un USB), entonces el
    # veredicto "no hay ninguna impresora conectada" es demostrablemente falso: hay una cola
    # real recibiendo comandas. Eso es lo que habilita bajar de rango al diagnostico USB.
    $puertoUtil = (@($trabadas | Where-Object {
        [bool]$_.puertoVivo -or ([string]$_.puerto -notmatch '^(?i)USB\d+')
    }).Count -gt 0)

    $lista = @($conTrabajos | ForEach-Object {
        [string]$_.nombre + ' [' + [string]$_.puerto + ']: ' + [int]$_.trabajos + ' trabajo(s) sin imprimir' +
        $(if ([string]$_.trabajoMasViejo) { ' (el mas viejo del ' + [string]$_.trabajoMasViejo + ')' } else { '' })
    })
    $peor = @($conTrabajos | Sort-Object -Property @{ Expression = { [int]$_.trabajos }; Descending = $true })[0]

    Add-Check -Id 'queue.otherBacklog' -Layer 2 `
        -Name ('Otra cola con comandas acumuladas que no salen: ' + [string]$peor.nombre + ' (' + [int]$peor.trabajos + ' trabajos)') `
        -Status $(if (@($trabadas).Count -gt 0) { 'fail' } else { 'warn' }) `
        -RootCauseCandidate (@($trabadas).Count -gt 0) -Plane 'os' `
        -Evidence @{ colas = @($lista); conTrabajos = @($conTrabajos).Count; trabadas = @($trabadas).Count
                     puertoUtil = [bool]$puertoUtil; objetivo = $objetivo } `
        -ArticleRef 'https://soporte.fu.do/es/articles/11730815' `
        -Recommendation ('Hay comandas encoladas que no salen en: ' + ($lista -join ' | ') +
                         '. Que Fudo las haya encolado prueba que el problema NO es la configuracion de Fudo, sino esa cola o su impresora. Revisar esa impresora (encendida, con papel, en linea y no pausada) y despues limpiar la cola: Get-PrintJob -PrinterName ''' + [string]$peor.nombre + ''' | Remove-PrintJob. Si esa es la impresora de comandas del local, volver a correr el diagnostico apuntando a ella con -PrinterName ''' + [string]$peor.nombre + '''.')
}

function Update-PrintInventory {
    <#
      v3.11: el veredicto se armaba con la foto de la capa 1, tomada ANTES de reparar. Una
      impresora que el motor acababa de poner en linea seguia contando como offline, una cola
      que acababa de purgar seguia contando como trabada, y un puerto recien re-bindeado seguia
      figurando sin dispositivo. Todo eso llegaba asi a la pantalla y a la telemetria.
      Aca se vuelve a leer el estado real: se invalida el cache de presencia de dispositivos, se
      re-mapea que puertos tienen algo enchufado y se releen todas las colas con sus trabajos.
      Es solo lectura: no repara ni toca nada.
    #>
    $previas = @()
    try { if ($script:Diagnostics.Contains('colas')) { $previas = @($script:Diagnostics['colas']) } } catch {}
    $script:Diagnostics['colasIniciales'] = @($previas)

    # El cache de InstanceIds presentes es de antes del re-bind: hay que tirarlo.
    $script:PresentIds   = $null
    $script:PresentIdsOk = $false
    $devices = @()
    try { $devices = @(Get-UsbPrintDevices) } catch {}
    # Get-UsbPrintDevices deja el cache de presencia armado al pasar por Get-PresentDeviceIds.
    # Si no llego a hacerlo, se vuelve a pedir explicitamente: con PresentIdsOk en false
    # Test-PortHasLiveDevice contesta siempre "hay algo detras del puerto" -es su regla de no
    # inventar desconexiones-, y el re-escaneo dejaria de ver justo los puertos que quedaron
    # vacios, que es la mitad de para lo que existe.
    if (-not $script:PresentIdsOk) { $null = Get-PresentDeviceIds }
    $script:Diagnostics['livePorts'] = @(@($devices | Where-Object { $_.portName } |
        ForEach-Object { [string]$_.portName }) | Select-Object -Unique)
    $script:Diagnostics['hwDeviceCount'] = @($devices).Count

    $colas = @()
    try { $colas = @(Get-PrinterQueues) } catch {}
    $script:Diagnostics['colas'] = @($colas)

    $delCliente = @($colas | Where-Object { -not $_.esDePrueba })
    $rotas = @($delCliente | Where-Object { [int]$_.score -gt 0 })
    $sanas = @($delCliente | Where-Object { [int]$_.score -eq 0 })
    Set-StepNote ("$(@($sanas).Count) sana(s), $(@($rotas).Count) con problemas")

    # Cuantas dejaron de estar rotas respecto de la foto inicial: es la medida directa de si las
    # reparaciones sirvieron, y hasta ahora no se podia calcular.
    $rotasAntes = @(@($previas | Where-Object { -not $_.esDePrueba -and [int]$_.score -gt 0 }) |
        ForEach-Object { [string]$_.nombre })
    $rotasAhora = @($rotas | ForEach-Object { [string]$_.nombre })
    $mejoraron  = @($rotasAntes | Where-Object { $rotasAhora -notcontains $_ })
    $script:Diagnostics['colasQueMejoraron'] = @($mejoraron)
    # printer.coverage viajaba solo como status (ok/warn) y sin el valor no se podia decidir
    # si la cobertura tiene que bloquear el cierre. Ahora va el numero.
    $script:Diagnostics['cobertura'] = [ordered]@{
        sanas = @($sanas).Count; rotas = @($rotas).Count; total = @($delCliente).Count
    }

    $detalle = @($rotas | ForEach-Object {
        [string]$_.nombre + ' [' + [string]$_.puerto + ']: ' + (@($_.sintomas) -join ', ')
    })

    if (@($rotas).Count -eq 0) {
        Add-Check -Id 'printer.coverage' -Layer 1 `
            -Name ('Todas las impresoras del cliente quedaron en condiciones de imprimir (' + @($sanas).Count + ')') -Status 'ok' -Plane 'os' `
            -Evidence @{ sanas = @($sanas | ForEach-Object { [string]$_.nombre }); rotas = @(); mejoraron = @($mejoraron) }
    } else {
        # Informativo a proposito: NO bloquea el cierre ni compite como causa raiz. Un local
        # puede tener una impresora vieja apagada que no tiene nada que ver con las comandas.
        # Lo que si bloquea es una cola con comandas encoladas sin drenar (queue.otherBacklog).
        Add-Check -Id 'printer.coverage' -Layer 1 `
            -Name ('Quedan ' + @($rotas).Count + ' de ' + @($delCliente).Count + ' impresoras del cliente sin poder imprimir') `
            -Status 'warn' -RootCauseCandidate $false -Plane 'os' `
            -Evidence @{ rotas = @($detalle); sanas = @($sanas | ForEach-Object { [string]$_.nombre }); mejoraron = @($mejoraron) } `
            -Recommendation ('Despues de todo lo que hizo el motor, estas colas siguen sin poder imprimir: ' +
                             ($detalle -join ' | ') +
                             '. Si alguna de estas es una impresora de comandas del local, volver a correr el diagnostico apuntando a ella con -PrinterName. Si son impresoras que el cliente ya no usa, conviene borrarlas para que dejen de ensuciar el diagnostico.')
    }
    return $colas
}

# ---------------------------------------------------------------------------
# LAYER 3 - Conectividad / puerto
# ---------------------------------------------------------------------------
function Remove-StaleOwnQueues {
    <#
      Colas FUDO-TEST-* que quedaron de una corrida anterior. No son del cliente y si se
      dejan, el motor las diagnostica como si lo fueran: se vio una corrida cuya CAUSA fue
      "la impresora 'FUDO-TEST-USB002' esta desconectada", o sea el motor reportando su
      propia basura como el problema del local.
    #>
    $borradas = @()
    try {
        foreach ($q in @(Get-Printer -ErrorAction SilentlyContinue | Where-Object { [string]$_.Name -match $script:TestPrinterRx })) {
            $n = [string]$q.Name
            try { Get-PrintJob -PrinterName $n -ErrorAction SilentlyContinue | Remove-PrintJob -ErrorAction SilentlyContinue } catch {}
            try { Remove-Printer -Name $n -ErrorAction Stop; $borradas += $n } catch {}
        }
    } catch {}
    if (@($borradas).Count -gt 0) {
        Add-Action -Type 'printer.remove_stale_test' -Target ($borradas -join ', ') -Before 'cola de prueba de una corrida anterior' -After 'borrada' -Reversible $true
        Write-DoctorLog -Level 'INFO' -Message ('Colas de prueba viejas borradas antes de diagnosticar: ' + ($borradas -join ', '))
    }
    return @($borradas)
}

function Remove-OrphanOwnQueues {
    <#
      Las colas que crea el motor (FUDO-USB00x) NO se borran como las FUDO-TEST-*: cuando el
      cliente no tenia ninguna, esa cola es el entregable. Pero si quedo apuntando a un puerto
      donde ya no hay ningun dispositivo, dejo de ser un entregable y pasa a ser basura que el
      motor se diagnostica a si mismo: se vio una corrida cuya causa raiz fue "la impresora
      'FUDO-USB001' esta desconectada", 35 segundos despues de que la corrida anterior la
      creara en ese mismo puerto.
      Corre DESPUES del inventario de hardware, que es lo que llena livePorts.
    #>
    $borradas = @()
    try {
        foreach ($q in @(Get-Printer -ErrorAction SilentlyContinue | Where-Object { [string]$_.Name -match $script:OwnQueueRx })) {
            $n = [string]$q.Name
            if (Test-PortHasLiveDevice -PortName ([string]$q.PortName)) { continue }
            try { Get-PrintJob -PrinterName $n -ErrorAction SilentlyContinue | Remove-PrintJob -ErrorAction SilentlyContinue } catch {}
            try { Remove-Printer -Name $n -ErrorAction Stop; $borradas += $n } catch {}
        }
    } catch {}
    if (@($borradas).Count -gt 0) {
        Add-Action -Type 'printer.remove_orphan_own' -Target ($borradas -join ', ') `
            -Before 'cola creada por el motor, apuntando a un puerto sin dispositivo' -After 'borrada' -Reversible $true
        Write-DoctorLog -Level 'INFO' -Message ('Colas propias huerfanas borradas antes de elegir impresora: ' + ($borradas -join ', '))
    }
    return @($borradas)
}

function Find-QueueForPort {
    <#
      Ya existe una cola del cliente apuntando a este puerto? Si existe y esta sana, hay que
      ADOPTARLA, no crear otra al lado. Se vieron dos PCs con 'FUDO-USB001' conviviendo con la
      cola real en el mismo USB001: el asesor tenia que reconfigurar Fudo sin necesidad, y la
      prueba de impresion corria sobre la cola nueva en vez de la que el local usa.
    #>
    param([string]$PortName)
    $out = $null
    try {
        $out = @(Get-Printer -ErrorAction SilentlyContinue | Where-Object {
                    [string]$_.PortName -eq $PortName -and
                    -not (Test-IsVirtualPrinter $_).isVirtual -and
                    [string]$_.Name -notmatch $script:TestPrinterRx
                 })[0]
    } catch {}
    return $out
}

function Repair-BindUsbPort {
    <#
      Windows ve la impresora USB pero no le asigno puerto (no hay nodo USBPRINT con
      PortName). Sin puerto, ninguna cola puede imprimirle y cambiar el puerto de una cola
      existente no sirve de nada.
      La receta manual es desenchufar y volver a enchufar el USB. Esto es lo mismo por
      software: deshabilitar y volver a habilitar el device (equivale al replug) y pnputil
      /scan-devices fuerza una redeteccion. Despues se vuelven a leer los puertos.
      Devuelve @{ puertos = @(...); nota = '...' }
    #>
    param([string[]]$InstanceIds)
    $notas = @()
    foreach ($id in @($InstanceIds | Where-Object { $_ })) {
        try {
            Write-StepDetail 'reiniciando el dispositivo (equivale a desenchufar y enchufar)'
            # v3.15: aca se llamaba a Restart-PnpDevice, que NO EXISTE en Windows (el modulo
            # PnpDevice trae Disable-PnpDevice y Enable-PnpDevice). Estaba dentro de un
            # try/catch, asi que el replug por software nunca se hizo: quedaba solo el
            # pnputil /scan-devices y la nota decia "no se pudo reiniciar el device" en todas
            # las corridas. Deshabilitar y volver a habilitar ES el replug.
            Disable-PnpDevice -InstanceId $id -Confirm:$false -ErrorAction Stop
            Start-Sleep -Milliseconds 1500
            Enable-PnpDevice -InstanceId $id -Confirm:$false -ErrorAction Stop
            $notas += 'device reiniciado (deshabilitado y habilitado)'
        } catch {
            $notas += ('no se pudo reiniciar el device: ' + $_.Exception.Message)
            # Si el disable anduvo y el enable no, la impresora queda deshabilitada en Windows y
            # el cliente termina peor que antes: hay que volver a habilitarla si o si.
            try { Enable-PnpDevice -InstanceId $id -Confirm:$false -ErrorAction SilentlyContinue } catch {}
        }
    }
    try {
        Write-StepDetail 'pidiendole a Windows que vuelva a detectar dispositivos'
        $exe = Join-Path $env:WINDIR 'System32\pnputil.exe'
        if (Test-Path $exe) { & $exe /scan-devices 2>&1 | Out-Null; $notas += 'redeteccion de PnP' }
    } catch {}

    # Windows tarda en crear el nodo USBPRINT y el puerto: se espera con reintentos.
    $puertos = @()
    for ($i = 0; $i -lt 8; $i++) {
        Start-Sleep -Milliseconds 1200
        try {
            $puertos = @(Get-PrinterPort -ErrorAction Stop | Where-Object { $_.Name -like 'USB*' } | ForEach-Object { [string]$_.Name })
        } catch {}
        if (@($puertos).Count -gt 0) { break }
    }
    return @{ puertos = @($puertos); nota = ($notas -join ' | ') }
}

function New-FudoPrinterQueue {
    <#
      Crea la cola de Windows para una impresora fisica.
      Decision del equipo (25/08): levantarla SIEMPRE. Si el driver del fabricante ya esta
      en Windows se usa ese (una Epson con su driver imprime mejor que con texto generico);
      si no esta, se usa 'Generico / Solo texto', que alcanza para comandas ESC/POS.
      Si las dos cosas fallan, se devuelve el error para que el asesor lo vea.
    #>
    param([string]$PortName, [string]$PreferDriver = '', [string]$Name = '')
    if (-not $Name) { $Name = 'FUDO-' + ($PortName -replace '[^A-Za-z0-9]', '') }
    $intentos = @()
    $drivers = @()
    if ($PreferDriver) { $drivers += $PreferDriver }
    $gen = ''
    try { $gen = Get-GenericTextDriverName } catch {}
    if (-not $gen) { try { $gen = Install-GenericTextDriver } catch {} }
    if ($gen -and ($drivers -notcontains $gen)) { $drivers += $gen }

    foreach ($d in @($drivers | Where-Object { $_ })) {
        try {
            Add-Printer -Name $Name -DriverName $d -PortName $PortName -ErrorAction Stop
            return @{ ok = $true; name = $Name; driver = $d; nota = ("cola '" + $Name + "' creada en " + $PortName + " con el driver '" + $d + "'") }
        } catch {
            $intentos += ("'" + $d + "': " + $_.Exception.Message)
        }
    }
    return @{ ok = $false; name = ''; driver = ''; nota = ('no se pudo crear la cola en ' + $PortName + ' -> ' + ($intentos -join ' | ')) }
}

function Get-DetectedInterface {
    param($Printer)
    if ($Interface -ne 'auto') { return $Interface }
    if ($PrinterIp) { return 'Ethernet' }
    $port = ''
    if ($Printer) { try { $port = [string]$Printer.PortName } catch {} }
    if ($port -like 'USB*' -or $port -like 'LPT*' -or $port -like '*USB*') { return 'USB' }
    if ($port -match '^\d{1,3}(\.\d{1,3}){3}' -or $port -like 'IP_*' -or $port -like '*9100*') { return 'Ethernet' }
    # WSD: la cola es de red aunque no tenga IP en el nombre del puerto (Windows la descubrio
    # sola por la red). Tratarla como USB hacia que la capa 3 dijera 'Puerto USB OK'.
    if ($port -match '(?i)^WSD-' -or $port -match '(?i)^\{?[0-9a-f]{8}-[0-9a-f]{4}-') { return 'WSD' }
    return 'USB'
}

function Repair-QueueRecreate {
    <#
      Ultimo recurso para una cola que no imprime en ningun puerto: recrearla.
      Secuencia segura (nunca deja al cliente sin cola):
        1) crear una cola TEMPORAL con driver de texto generico en cada puerto candidato y probar
           un ticket real;
        2) recien cuando una imprime, borrar la cola vieja y RENOMBRAR la temporal con el nombre
           original (Fudo apunta a la impresora por nombre: el nombre no puede cambiar);
        3) si ninguna imprime, no se borra nada.
      El borrado de la cola vieja es irreversible -> pasa por la confirmacion.
    #>
    param($Printer, [string[]]$CandidatePorts)

    $nombre = [string]$Printer.Name
    $puertoOk = ''
    $temporal = ''

    # Por que fallo CADA candidato. Sin esto la nota decia solo "ninguno de los puertos
    # probados imprimio", que colapsa tres causas muy distintas -no se pudo crear la cola /
    # el ticket quedo encolado / el humano dijo que no salio papel- y deja el caso sin
    # diagnosticar. Paso en un caso real: el motor no logro imprimir en USB002 y el asesor,
    # creando la cola a mano en ese mismo puerto, imprimio sin problemas.
    $intentos = @()

    Write-StepDetail "probando en que puerto responde '$nombre'"
    try {
        Initialize-RawPrinterHelper
        $ticket = [System.Text.Encoding]::GetEncoding(437).GetBytes((Get-EscPosTestTicket -Caption 'FUDO PORT TEST'))
        foreach ($cp in @($CandidatePorts)) {
            $tmp = ''
            $paso = [ordered]@{ puerto = $cp; colaCreada = $false; envioOk = $false
                                quedoEnCola = $null; confirmadoPorHumano = $null; resultado = '' }
            try {
                Write-StepDetail "probando el puerto $cp"
                $tmp = New-FudoTestPrinter -PortName $cp
                if (-not $tmp) {
                    $paso.resultado = 'no se pudo crear la cola de prueba en ese puerto'
                    $intentos += $paso
                    continue
                }
                $paso.colaCreada = $true
                # El spooler necesita un momento para dejar la cola nueva utilizable.
                Start-Sleep -Milliseconds 1200
                $paso.envioOk = [bool][FudoRawPrinter]::SendBytes($tmp, $ticket)
                if (-not $paso.envioOk) {
                    $paso.resultado = 'la cola se creo pero el envio RAW fallo'
                } else {
                    $d = Wait-QueueDrain -Printer $tmp -TimeoutMs 10000
                    $paso.quedoEnCola = [bool]$d.quedoEnCola
                    if ($d.quedoEnCola) {
                        $paso.resultado = 'el ticket entro a la cola y no salio (la impresora no lo tomo)'
                    } else {
                        # La cola temporal esta limpia y sin offline, asi que si el trabajo salio,
                        # el puerto responde. El papel lo confirma el humano.
                        $conf = Confirm-PaperCameOut -Printer $tmp
                        $paso.confirmadoPorHumano = $conf
                        if ($conf -eq $false) {
                            $paso.resultado = 'el ticket salio de la cola pero el asesor dice que no salio papel'
                        } else {
                            $paso.resultado = $(if ($conf) { 'imprimio (confirmado)' } else { 'imprimio (sin confirmar)' })
                            $puertoOk = $cp; $temporal = $tmp
                            $intentos += $paso
                            break
                        }
                    }
                }
                try { Remove-Printer -Name $tmp -ErrorAction SilentlyContinue } catch {}
            } catch {
                $paso.resultado = 'error al probar el puerto: ' + [string]$_.Exception.Message
            }
            $intentos += $paso
        }
    } catch {}
    $script:Diagnostics['intentosPuerto'] = @($intentos)

    if (-not $puertoOk) {
        $detalle = @($intentos | ForEach-Object { [string]$_.puerto + ': ' + [string]$_.resultado })
        return @{ applied = $false
                  note = "ninguno de los puertos probados imprimio un ticket de prueba -- " + ($detalle -join ' | ')
                  intentos = @($intentos) }
    }

    # Hay un puerto que imprime: ahora si vale reemplazar la cola vieja.
    $rem = Invoke-Remediation -Description "Reemplazar la cola '$nombre' por una nueva con driver de texto generico en $puertoOk (ya probada: imprimio)" `
        -Type 'printer.recreate' -Target $nombre -Before "$([string]$Printer.DriverName) en $([string]$Printer.PortName)" -After "Generic / Text Only en $puertoOk" `
        -Reversible $false -Impact "se elimina la cola '$nombre' con sus trabajos pendientes y sus preferencias; se recrea con el mismo nombre para que Fudo la siga encontrando" -Fix {
            try { Get-PrintJob -PrinterName $nombre -ErrorAction SilentlyContinue | Remove-PrintJob -ErrorAction SilentlyContinue } catch {}
            Remove-Printer -Name $nombre -ErrorAction Stop
            Start-Sleep -Milliseconds 500
            $renombrada = $false
            try { Rename-Printer -Name $temporal -NewName $nombre -ErrorAction Stop; $renombrada = $true } catch {}
            if (-not $renombrada) {
                $drv = Get-GenericTextDriverName
                if (-not $drv) { $drv = Install-GenericTextDriver }
                Add-Printer -Name $nombre -DriverName $drv -PortName $puertoOk -ErrorAction Stop
                try { Remove-Printer -Name $temporal -ErrorAction SilentlyContinue } catch {}
            }
            $i = $script:TestPrintersCreated.IndexOf($temporal)
            if ($i -ge 0) { $script:TestPrintersCreated.RemoveAt($i) }
            "cola '$nombre' recreada con driver de texto generico en $puertoOk (ticket de prueba OK)"
        }

    if (-not $rem.applied) {
        # No se confirmo el reemplazo: dejamos la temporal como evidencia de donde SI imprime.
        return @{ applied = $false
                  note = "el puerto correcto es $puertoOk (la cola de prueba '$temporal' imprimio). " + [string]$rem.note }
    }
    return $rem
}

function Test-Layer3-WsdPort {
    <#
      La cola apunta a un puerto WSD (Web Services on Devices): Windows descubrio la
      impresora POR LA RED y creo la cola sola, con el driver 'Microsoft IPP Class Driver'.
      Caso real (Epson L5590, CL): la impresora estaba conectada por USB, la unica cola de
      Windows era la WSD, y el ticket quedaba en la cola para siempre. Mientras Fudo le mande
      a esa cola, depende de que la impresora este accesible por la red.
    #>
    param($Printer)
    if ($null -eq $Printer) { return }
    $puerto = [string]$Printer.PortName
    $hwUsb = 0
    if ($script:Diagnostics.Contains('hwDeviceCount')) { $hwUsb = [int]$script:Diagnostics['hwDeviceCount'] }
    $usbPorts = @()
    if ($script:Diagnostics.Contains('usbPorts')) { $usbPorts = @($script:Diagnostics['usbPorts'] | Where-Object { $_ }) }

    if ($hwUsb -gt 0) {
        Add-Check -Id 'conn.portMismatch' -Layer 3 -Name 'La cola es de red (WSD) pero la impresora esta conectada por USB' -Status 'warn' -RootCauseCandidate $true -Plane 'os' `
            -Evidence @{ puerto = $puerto; driver = [string]$Printer.DriverName; hardwareUsb = $hwUsb; puertosUsb = $usbPorts } `
            -ArticleRef 'https://soporte.fu.do/es/articles/16419361' `
            -Recommendation ("La cola '$($Printer.Name)' usa el puerto $puerto, que es un puerto de RED (WSD): Windows encontro la impresora por wifi/cable y creo la cola sola. " +
                             'Pero el hardware esta conectado por USB, asi que si la impresora no esta accesible por la red, todo lo que Fudo manda a esa cola se queda esperando. ' +
                             'Lo correcto para comandas es una cola sobre el puerto USB: el motor la crea con la opcion [I] del menu, o a mano con Agregar impresora > agregar local > puerto USB00x. ' +
                             'Despues hay que apuntar Fudo a esa cola nueva (Administracion > Impresoras).')
        return
    }
    Add-Check -Id 'conn.wsd' -Layer 3 -Name 'Cola de red (WSD)' -Status 'warn' -Plane 'os' `
        -Evidence @{ puerto = $puerto; driver = [string]$Printer.DriverName; hardwareUsb = 0 } `
        -Recommendation ("La cola '$($Printer.Name)' apunta a un puerto WSD (la impresora se descubrio por la red). " +
                         'Para comandas conviene una cola directa: por USB, o por IP fija con el puerto 9100 (Directo Ethernet en Fudo). ' +
                         'Con WSD, si la impresora cambia de IP o se va de la red, las comandas se acumulan en la cola sin aviso.')
}

function Test-Layer3-UsbPort {
    param($Printer, $Wmi)
    if ($null -eq $Printer) { return }
    $currentPort = [string]$Printer.PortName
    $usbPorts = @()
    try { $usbPorts = @(Get-PrinterPort -ErrorAction Stop | Where-Object { $_.Name -like 'USB*' }) } catch {}
    $script:Diagnostics['usbPorts'] = @($usbPorts | ForEach-Object { $_.Name })

    # Puertos USB ocupados por otras impresoras (para no pisarlos)
    $usedPorts = @()
    try { $usedPorts = @(Get-Printer -ErrorAction SilentlyContinue | Where-Object { $_.Name -ne $Printer.Name } | ForEach-Object { [string]$_.PortName }) } catch {}
    $candidatePorts = @($usbPorts | Where-Object { $_.Name -ne $currentPort -and ($usedPorts -notcontains $_.Name) } | ForEach-Object { $_.Name })

    # Puertos con device fisico detras (del inventario de hardware, capa 1a): son los que valen
    $livePorts = @()
    if ($script:Diagnostics.Contains('livePorts')) { $livePorts = @($script:Diagnostics['livePorts'] | Where-Object { $_ }) }
    if (@($livePorts).Count -gt 0) {
        # probar primero los puertos que si tienen impresora conectada
        $candidatePorts = @(@($livePorts | Where-Object { $_ -ne $currentPort }) + @($candidatePorts) | Select-Object -Unique)
    }

    # Si Windows no ve ningun dispositivo de impresion, no hay puerto a donde apuntar:
    # probar candidatos solo genera falsos positivos.
    $hwCount = -1
    if ($script:Diagnostics.Contains('hwDeviceCount')) { $hwCount = [int]$script:Diagnostics['hwDeviceCount'] }
    if ($hwCount -eq 0) {
        Add-Check -Id 'conn.usb' -Layer 3 -Name 'Puerto USB: no hay ningun dispositivo conectado' -Status 'fail' -RootCauseCandidate $true -Plane 'hardware' `
            -Evidence @{ currentPort = $currentPort; usbPorts = $usbPorts; hwDevices = 0 } `
            -ArticleRef 'https://soporte.fu.do/es/articles/11730817' `
            -Recommendation ('No tiene sentido reasignar el puerto: Windows no detecta ninguna impresora conectada. ' +
                             'Conectar el USB con la impresora encendida (el motor puede esperar la reconexion y seguir solo) y recien despues revisar el puerto.')
        return
    }

    # Sintoma que dispara el remapeo (art. 11730817: se reconecto a otro puerto USB)
    $needsPortFix = $false
    $reason = ''
    if ($script:Diagnostics.Contains('printer')) {
        $ps = $script:Diagnostics['printer']
        if ($ps.workOffline) { $needsPortFix = $true; $reason = 'la impresora esta offline' }
    }
    if (@($livePorts).Count -gt 0 -and ($livePorts -notcontains $currentPort)) {
        $needsPortFix = $true
        $reason = "la cola apunta a '$currentPort' pero el hardware esta enumerado en $($livePorts -join ', ')"
    }
    # Si el ultimo test de HW por USB fallara, tambien se reintenta (se maneja en test print)

    if (-not $needsPortFix) {
        Add-Check -Id 'conn.usb' -Layer 3 -Name 'Puerto USB' -Status 'ok' `
            -Evidence @{ currentPort = $currentPort; usbPorts = $script:Diagnostics['usbPorts']; livePorts = $livePorts; candidates = $candidatePorts }
        return
    }

    if (@($candidatePorts).Count -eq 0) {
        Add-Check -Id 'conn.usb' -Layer 3 -Name 'Puerto USB desmapeado (sospecha)' -Status 'warn' -RootCauseCandidate $true `
            -Evidence @{ currentPort = $currentPort; usbPorts = $script:Diagnostics['usbPorts']; livePorts = $livePorts; motivo = $reason } `
            -ArticleRef 'https://soporte.fu.do/es/articles/11730817' `
            -Recommendation 'La impresora podria estar en otro puerto USB fisico. Reconectar y/o reasignar el puerto (Propiedades de impresora > Puertos).'
        return
    }

    # Antes de probar puertos hay que dejar la cola en condiciones de imprimir. Caso real:
    # cola offline + 11 comandas viejas trabadas => todos los candidatos "fallaban" y el
    # motor revertia el puerto, dejando el problema intacto.
    $destrabado = Unblock-QueueForTest -Printer $Printer
    if (@($destrabado).Count -gt 0) { Write-StepDetail ('destrabando la cola: ' + ($destrabado -join '; ')) }
    $trabajosDelante = 0
    try { $trabajosDelante = @(Get-PrintJob -PrinterName $Printer.Name -ErrorAction SilentlyContinue).Count } catch {}
    if ($trabajosDelante -gt 0) {
        $purga = Invoke-Remediation -Description "Limpiar $trabajosDelante trabajo(s) atascado(s) en '$($Printer.Name)' para poder probar los puertos" `
            -Type 'queue.purge_for_test' -Target $Printer.Name -Before "$trabajosDelante trabajos" -After 'cola vacia' -Reversible $false `
            -Impact 'se descartan comandas viejas que nunca salieron (hay que reimprimirlas desde Fudo)' -Fix {
                Get-PrintJob -PrinterName $Printer.Name -ErrorAction SilentlyContinue | Remove-PrintJob -ErrorAction SilentlyContinue
                Start-Sleep -Milliseconds 400
                "cola vaciada para poder probar los puertos"
            }
        if (-not $purga.applied) {
            # Sin vaciar la cola, cualquier prueba de puerto da un falso negativo.
            Add-Check -Id 'conn.usb' -Layer 3 -Name 'Puerto USB: prueba bloqueada por la cola' -Status 'warn' -RootCauseCandidate $true `
                -Evidence @{ currentPort = $currentPort; candidates = $candidatePorts; livePorts = $livePorts
                             trabajosDelante = $trabajosDelante; destrabado = $destrabado } `
                -ArticleRef 'https://soporte.fu.do/es/articles/11730817' `
                -Recommendation ("No se puede saber en que puerto responde la impresora: hay $trabajosDelante trabajo(s) atascado(s) delante en '$($Printer.Name)' y cualquier ticket de prueba queda detras. " +
                                 "Limpiar la cola primero (Get-PrintJob -PrinterName '$($Printer.Name)' | Remove-PrintJob, o correr el script y responder 's' cuando pregunte) y volver a correr el diagnostico.")
            return
        }
        try { $trabajosDelante = @(Get-PrintJob -PrinterName $Printer.Name -ErrorAction SilentlyContinue).Count } catch { $trabajosDelante = 0 }
    }

    # Auto-fix conservador: probar candidatos con test raw y quedarse con el que imprime; si ninguno, revertir.
    $rem = Invoke-Remediation -Description "Reasignar puerto USB probando candidatos: $($candidatePorts -join ', ')" -Type 'printer.setport' -Target $Printer.Name `
        -Before $currentPort -After '(a determinar)' -Fix {
            Initialize-RawPrinterHelper
            $ticket = [System.Text.Encoding]::GetEncoding(437).GetBytes((Get-EscPosTestTicket -Caption 'FUDO USB PORT TEST'))
            $chosen = $null
            foreach ($cp in $candidatePorts) {
                try {
                    Write-StepDetail ("probando el puerto " + $cp)
                    Set-Printer -Name $Printer.Name -PortName $cp -ErrorAction Stop
                    Start-Sleep -Milliseconds 500
                    if (-not ([FudoRawPrinter]::SendBytes($Printer.Name, $ticket))) { continue }
                    # OJO: SendBytes OK solo dice que el spooler acepto el trabajo. Si el papel no
                    # sale, el trabajo queda en la cola. Sin esta verificacion se reportaba
                    # "puerto reasignado (test HW OK)" con la impresora desenchufada.
                    $d = Wait-QueueDrain -Printer $Printer.Name -TimeoutMs 6000
                    if ($d.quedoEnCola) {
                        try { Get-PrintJob -PrinterName $Printer.Name -ErrorAction SilentlyContinue | Where-Object { [string]$_.DocumentName -match '(?i)fudo print doctor' } | Remove-PrintJob -ErrorAction SilentlyContinue } catch {}
                        continue
                    }
                    # El puerto acepto los bytes. Que salga papel solo lo puede confirmar el humano.
                    $conf = Confirm-PaperCameOut -Printer $Printer.Name
                    if ($conf -eq $false) { continue }
                    $script:Diagnostics['puertoConfirmado'] = $conf
                    $chosen = $cp; break
                } catch {}
            }
            if ($null -eq $chosen) {
                try { Set-Printer -Name $Printer.Name -PortName $currentPort -ErrorAction SilentlyContinue } catch {}
                "ningun candidato imprimio un ticket de verdad; puerto revertido a $currentPort"
            } elseif ($script:Diagnostics.Contains('puertoConfirmado') -and $script:Diagnostics['puertoConfirmado'] -eq $true) {
                "puerto reasignado a $chosen (confirmado: salio el ticket)"
            } else {
                "puerto reasignado a $chosen y el ticket salio de la cola (sin confirmar que salio papel)"
            }
        }
    $fixedOk = $rem.applied -and ($rem.note -match 'reasignado')

    # Si cambiar el puerto no alcanzo, la cola en si puede estar rota: recrearla en el puerto
    # donde el hardware realmente responde (con el mismo nombre, para no romper Fudo).
    if (-not $fixedOk -and $InstallGenericDriver) {
        $rec = Repair-QueueRecreate -Printer $Printer -CandidatePorts $candidatePorts
        if ($rec.applied) {
            Add-Check -Id 'conn.usb' -Layer 3 -Name "Cola '$($Printer.Name)' recreada en el puerto correcto" -Status 'fixed' -RootCauseCandidate $true `
                -Evidence @{ antes = @{ puerto = [string]$Printer.PortName; driver = [string]$Printer.DriverName }; candidatos = $candidatePorts } `
                -ActionTaken $rec.note -Reversible $false `
                -ArticleRef 'https://soporte.fu.do/es/articles/11730817' `
                -Recommendation ("La cola apuntaba a un puerto que no responde y no alcanzo con reasignarla, asi que se recreo con driver de texto generico en el puerto donde el hardware si imprime. " +
                                 'Verificar en Fudo que la impresora siga asignada a su area/cocina (el nombre se mantuvo).')
            return
        }
        if ($rec.note -match 'el puerto correcto es') {
            Add-Check -Id 'conn.usb' -Layer 3 -Name 'Puerto USB desmapeado (reemplazo de cola pendiente de confirmacion)' -Status 'warn' -RootCauseCandidate $true `
                -Evidence @{ currentPort = $currentPort; candidates = $candidatePorts; livePorts = $livePorts; motivo = $reason } `
                -ActionTaken $rec.note -ArticleRef 'https://soporte.fu.do/es/articles/11730817' `
                -Recommendation ([string]$rec.note + " Para aplicarlo: correr el script en la consola y confirmar cuando pregunte, o pasar -AllowQueuePurge `$true.")
            return
        }
        $rem = @{ applied = $rem.applied; note = ([string]$rem.note + ' | ' + [string]$rec.note) }
    }

    Add-Check -Id 'conn.usb' -Layer 3 -Name 'Puerto USB desmapeado' -Status $(if($fixedOk){'fixed'}elseif($rem.applied){'warn'}else{'warn'}) -RootCauseCandidate $true `
        -Evidence @{ currentPort = $currentPort; candidates = $candidatePorts; livePorts = $livePorts; motivo = $reason } -ActionTaken $rem.note `
        -ArticleRef 'https://soporte.fu.do/es/articles/11730817' `
        -Recommendation 'Caso clasico: la impresora se reconecto a otro puerto USB y la cola apunta al viejo.'
}

function Get-LocalSubnetPrefixes {
    <# Prefijos /24 de las placas de red locales, para saber donde buscar. #>
    $out = @()
    try {
        foreach ($ip in @(Get-NetIPAddress -AddressFamily IPv4 -ErrorAction Stop | Where-Object { $_.IPAddress -notmatch '^(127\.|169\.254\.)' })) {
            $p = (([string]$ip.IPAddress) -split '\.')[0..2] -join '.'
            if ($p -and ($out -notcontains $p)) { $out += $p }
        }
    } catch {
        try {
            foreach ($c in @(Get-CimInstance Win32_NetworkAdapterConfiguration -ErrorAction Stop | Where-Object { $_.IPEnabled })) {
                foreach ($a in @($c.IPAddress)) {
                    if ($a -match '^\d{1,3}(\.\d{1,3}){3}$' -and $a -notmatch '^(127\.|169\.254\.)') {
                        $p = ($a -split '\.')[0..2] -join '.'
                        if ($out -notcontains $p) { $out += $p }
                    }
                }
            }
        } catch {}
    }
    return @($out)
}

function Test-IsEscPosDevice {
    <#
      Confirma que lo que escucha en ese puerto sea una impresora ESC/POS y no otra cosa.
      Se manda DLE EOT 1 (pedido de estado en tiempo real): una termica responde 1 byte.
    #>
    param([string]$Ip, [int]$TcpPort, [int]$TimeoutMs = 1200)
    $client = New-Object System.Net.Sockets.TcpClient
    try {
        $iar = $client.BeginConnect($Ip, $TcpPort, $null, $null)
        if (-not $iar.AsyncWaitHandle.WaitOne($TimeoutMs)) { return $false }
        $client.EndConnect($iar)
        $stream = $client.GetStream()
        $stream.WriteTimeout = $TimeoutMs
        $stream.ReadTimeout  = $TimeoutMs
        $stream.Write([byte[]]@(0x10, 0x04, 0x01), 0, 3)
        $stream.Flush()
        Start-Sleep -Milliseconds 250
        $buf = New-Object byte[] 4
        try { return (($stream.Read($buf, 0, 4)) -gt 0) } catch { return $false }
    } catch { return $false }
    finally { try { $client.Close() } catch {} }
}

function Find-NetworkPrinters {
    <#
      Barre la subred buscando el puerto de impresion (9100 por defecto) y, en cada hallazgo,
      chequea si responde como ESC/POS. Devuelve la lista de candidatas.
    #>
    param([string]$Prefix, [int]$TcpPort = 9100, [int]$WaitMs = 900)
    $found = @()
    if (-not $Prefix) { return @() }
    Write-StepDetail ("buscando impresoras en " + $Prefix + ".1-254 (puerto " + $TcpPort + ")")
    $pend = @()
    try {
        foreach ($h in 1..254) {
            $cand = "$Prefix.$h"
            $cli = New-Object System.Net.Sockets.TcpClient
            $ar  = $cli.BeginConnect($cand, $TcpPort, $null, $null)
            $pend += [pscustomobject]@{ ip = $cand; client = $cli; ar = $ar }
        }
        Start-Sleep -Milliseconds $WaitMs
        foreach ($j in $pend) {
            try {
                if ($j.ar.AsyncWaitHandle.WaitOne(0)) {
                    $j.client.EndConnect($j.ar)
                    $found += [string]$j.ip
                }
            } catch {}
            finally { try { $j.client.Close() } catch {} }
        }
    } catch {}

    $res = @()
    foreach ($ip in @($found)) {
        Write-StepDetail ("verificando si " + $ip + " es una impresora")
        $esc = Test-IsEscPosDevice -Ip $ip -TcpPort $TcpPort
        $res += [ordered]@{ ip = $ip; puerto = $TcpPort; respondeEscPos = [bool]$esc
                            tipo = $(if ($esc) { 'impresora termica (responde ESC/POS)' } else { 'dispositivo con el puerto abierto (no confirmado como impresora)' }) }
    }
    return @($res)
}

function Test-PathExists {
    <# Envoltorio de Test-Path para poder probar la resolucion de rutas sin tocar el disco. #>
    param([string]$Path)
    if (-not $Path) { return $false }
    try { return [bool](Test-Path -LiteralPath $Path) } catch { return $false }
}

function Test-IpAlive {
    <#
      Responde algo en esa IP? Envuelto en una funcion propia a proposito: es lo que permite
      probar la logica que decide una IP libre sin depender de la red real.
    #>
    param([string]$Ip, [int]$TimeoutMs = 300)
    if (-not $Ip) { return $false }
    try { return ((((New-Object System.Net.NetworkInformation.Ping).Send($Ip, $TimeoutMs)).Status) -eq 'Success') } catch { return $false }
}

function Convert-EscPosInfoBytes {
    <#
      Texto util de la respuesta a GS I n: viene con un byte de encabezado y termina en NUL, y
      lo unico que interesa es lo imprimible. Separado del socket para poder probarlo.
    #>
    param([byte[]]$Bytes, [int]$Leidos = -1)
    $n = $(if ($Leidos -ge 0) { $Leidos } else { @($Bytes).Count })
    # GS I n contesta con un byte de encabezado (0x5F) y termina en NUL. El 0x5F es imprimible,
    # asi que si no se saltea queda pegado al texto: '_EPSON' en vez de 'EPSON'.
    $desde = 0
    if ($n -gt 0 -and ([int]$Bytes[0]) -eq 0x5F) { $desde = 1 }
    $txt = ''
    for ($i = $desde; $i -lt $n; $i++) {
        $b = [int]$Bytes[$i]
        if ($b -ge 32 -and $b -le 126) { $txt += [char]$b }
    }
    return ([string]$txt).Trim()
}

function Resolve-BrandFromText {
    <# Marca conocida dentro de un texto libre, contra la lista que ya usa el resto del motor. #>
    param([string]$Texto)
    $t = ([string]$Texto).Trim()
    if (-not $t) { return '' }
    foreach ($m in @($script:PosBrands)) {
        if ($t -match ('(?i)' + [regex]::Escape($m))) { return [string]$m }
    }
    if ($t -match '(?i)seiko|epson') { return 'Epson' }
    return ''
}

function Confirm-NetProbe {
    <#
      Decide si se le agrega una IP secundaria temporal a la placa del cliente.
      Es reversible, pero es lo mas invasivo que hace el motor y NUNCA se probo contra hardware
      real, asi que no va por default. Orden de decision:
        -AllowNetProbe $true/$false -> lo que diga el invocador
        consola interactiva         -> se le pregunta al asesor
        modo agente                 -> NO se hace, y el motor explica que quedo sin revisar
      OJO: no depende de -SkipIrreversible, porque esto SI se puede deshacer.
    #>
    param([string]$Prefijo, [string]$Motivo)
    if ($script:BoundParams -and $script:BoundParams.ContainsKey('AllowNetProbe')) { return [bool]$AllowNetProbe }
    if (-not (Test-IsInteractiveConsole)) { return $false }

    Suspend-LiveStatus
    [Console]::Error.WriteLine('')
    [Console]::Error.WriteLine('  ------------------------------------------------------------')
    [Console]::Error.WriteLine('  Puede haber una impresora de red en una subred distinta a la del PC.')
    [Console]::Error.WriteLine(("    Subred a revisar: " + $Prefijo + '.0/24'))
    if ($Motivo) { [Console]::Error.WriteLine("    Por que: $Motivo") }
    [Console]::Error.WriteLine('')
    [Console]::Error.WriteLine('  Para poder verla, el motor le agrega una segunda direccion IP a la placa de')
    [Console]::Error.WriteLine('  red de esta PC y la saca al terminar. La PC NO pierde internet ni la conexion')
    [Console]::Error.WriteLine('  remota: conserva su IP actual y suma una.')
    [Console]::Error.WriteLine('  ------------------------------------------------------------')
    $ans = Read-DoctorLine -Prompt '  Revisar esa subred? (s = si / cualquier otra tecla = no)'
    if ($null -eq $ans) { return $false }
    return ($ans -match '(?i)^\s*(s|si|s\u00ED|y|yes)\s*$')
}

function Get-PrimaryIpv4Interface {
    <# La placa por la que sale el trafico: es a la que hay que sumarle la IP secundaria. #>
    $out = [ordered]@{ indice = 0; ip = ''; prefijo = '' }
    try {
        $a = @(Get-NetIPAddress -AddressFamily IPv4 -ErrorAction Stop |
               Where-Object { $_.IPAddress -notmatch '^(127\.|169\.254\.)' } |
               Sort-Object -Property @{ Expression = { [int]$_.InterfaceIndex } }) | Select-Object -First 1
        if ($a) {
            $out.indice = [int]$a.InterfaceIndex
            $out.ip = [string]$a.IPAddress
            $out.prefijo = (([string]$a.IPAddress) -split '\.')[0..2] -join '.'
        }
    } catch {}
    return $out
}

function Add-TempSubnetIp {
    <#
      Le suma una IP secundaria a la placa, en la subred que se quiere revisar. La PC conserva
      su direccion actual: no pierde internet ni la asistencia remota, que es exactamente el
      bloqueo que hacia que esto se resolviera desenchufando el cable del router.
      Devuelve @{ aplicado; ip; indice; motivo }
    #>
    param([string]$Prefijo)
    $nic = Get-PrimaryIpv4Interface
    if (-not $nic.indice) { return @{ aplicado = $false; ip = ''; indice = 0; motivo = 'no se encontro una placa de red con IPv4' } }
    $libre = Get-FreeIpInSubnet -Prefix $Prefijo
    if (-not $libre) { return @{ aplicado = $false; ip = ''; indice = [int]$nic.indice; motivo = ('no se encontro una direccion libre en ' + $Prefijo + '.0/24') } }
    try {
        New-NetIPAddress -InterfaceIndex ([int]$nic.indice) -IPAddress $libre -PrefixLength 24 -ErrorAction Stop | Out-Null
        [void]$script:TempIpsAdded.Add([ordered]@{ ip = $libre; indice = [int]$nic.indice })
        Add-Action -Type 'net.tempIp' -Target ($libre + '/24') -Before 'sin direccion en esa subred' -After 'direccion secundaria agregada' -Reversible $true
        Start-Sleep -Milliseconds 800
        return @{ aplicado = $true; ip = $libre; indice = [int]$nic.indice; motivo = '' }
    } catch {
        return @{ aplicado = $false; ip = $libre; indice = [int]$nic.indice; motivo = ('no se pudo agregar la direccion: ' + $_.Exception.Message) }
    }
}

function Remove-TempSubnetIps {
    <#
      Saca las IPs secundarias que agrego esta corrida. Se llama SIEMPRE, tambien si el
      diagnostico fallo: dejarle una direccion de mas a la placa del cliente seria peor que no
      haber revisado nada.
    #>
    $sacadas = @()
    foreach ($t in @($script:TempIpsAdded)) {
        try {
            Remove-NetIPAddress -IPAddress ([string]$t.ip) -InterfaceIndex ([int]$t.indice) -Confirm:$false -ErrorAction Stop
            $sacadas += [string]$t.ip
        } catch {
            Write-DoctorLog -Level 'WARN' -Message ('no se pudo sacar la IP temporal ' + [string]$t.ip + ': ' + $_.Exception.Message)
        }
    }
    $script:TempIpsAdded = New-Object System.Collections.ArrayList
    return @($sacadas)
}

function Get-DefaultGatewayIp {
    <# El router. Es uno de los valores que hay que ponerle a la impresora. #>
    try {
        $r = @(Get-NetRoute -DestinationPrefix '0.0.0.0/0' -ErrorAction Stop |
               Where-Object { $_.NextHop -and $_.NextHop -ne '0.0.0.0' } |
               Sort-Object -Property @{ Expression = { [int]$_.RouteMetric } }) | Select-Object -First 1
        if ($r) { return [string]$r.NextHop }
    } catch {}
    try {
        foreach ($c in @(Get-CimInstance Win32_NetworkAdapterConfiguration -ErrorAction Stop | Where-Object { $_.IPEnabled })) {
            foreach ($g in @($c.DefaultIPGateway)) { if ($g -match '^\d{1,3}(\.\d{1,3}){3}$') { return [string]$g } }
        }
    } catch {}
    return ''
}

function Resolve-NetworkPrinterPlan {
    <#
      LA instruccion unica. El asesor no tiene que averiguar nada: el motor decide cual es la
      impresora, de que marca es, con que herramienta se le cambia la IP, que valores poner y
      que se va a verificar despues. Si esto devuelve un plan, el trabajo del asesor son dos
      clicks en una GUI ajena; sin esto, son veinte minutos de tanteo.
      Devuelve @{ hay; ip; marca; mac; oui; modelo; ipSugerida; mascara; gateway; herramienta; pasos }
    #>
    param($Encontrada, [string]$PrefijoPc, [string]$Gateway)
    $plan = [ordered]@{
        hay = $false; ip = ''; marca = ''; mac = ''; oui = ''; modelo = ''
        ipSugerida = ''; mascara = '255.255.255.0'; gateway = [string]$Gateway
        herramienta = $null; pasos = @()
    }
    if (-not $Encontrada) { return $plan }
    $plan.hay = $true
    $plan.ip = [string]$Encontrada.ip
    $plan.mac = [string]$Encontrada.mac
    $plan.oui = [string]$Encontrada.oui
    $plan.modelo = [string]$Encontrada.modelo
    $plan.marca = [string]$Encontrada.marca
    if ($PrefijoPc) { $plan.ipSugerida = Get-FreeIpInSubnet -Prefix $PrefijoPc -Evitar @([string]$Gateway) }
    if ($plan.marca) { $plan.herramienta = Find-NetConfigTool -Marca ([string]$plan.marca) }

    $pasos = @()
    $quien = $(if ($plan.marca) { 'La impresora es ' + $plan.marca + $(if ($plan.modelo) { ' (' + $plan.modelo + ')' } else { '' }) }
               else { 'No se pudo identificar la marca' + $(if ($plan.oui) { ' (OUI de la MAC: ' + $plan.oui + ')' } else { '' }) })
    $pasos += ($quien + ' y esta en ' + $plan.ip + ', que NO es la red de esta PC' +
               $(if ($PrefijoPc) { ' (' + $PrefijoPc + '.0/24)' } else { '' }) + '.')
    if ($plan.mac) { $pasos += ('MAC: ' + $plan.mac + ' (no cambia aunque cambie la IP: sirve para reconocerla).') }
    if ($plan.ipSugerida) {
        $pasos += ('Ponerle esta configuracion: IP ' + $plan.ipSugerida + ' - mascara ' + $plan.mascara +
                   $(if ($plan.gateway) { ' - gateway ' + $plan.gateway } else { '' }) +
                   '. Esa direccion se probo y esta libre.')
    } else {
        $pasos += 'No se pudo proponer una IP libre en la red del PC: elegir una a mano que no este en uso.'
    }
    if ($plan.herramienta -and [bool]$plan.herramienta.encontrada) {
        $pasos += ('La herramienta para cambiarsela esta en esta PC: ' + [string]$plan.herramienta.ruta + '. ' + [string]$plan.herramienta.nota)
    } elseif ($plan.herramienta) {
        $pasos += ('Para cambiarsela hace falta ' + [string]$plan.herramienta.exe + ' (carpeta ' + [string]$plan.herramienta.carpeta +
                   ' de NetConfigTools, que viene con Delitools). No esta en esta PC: instalando Delitools, la proxima corrida la encuentra sola. ' +
                   [string]$plan.herramienta.nota)
    } else {
        $pasos += ('Sin marca identificada no hay herramienta que abrir: leer la IP con el self-test de la impresora ' +
                   '(apagar, mantener FEED, encender) y cambiarla por la utilidad del fabricante o su pagina web.')
    }
    $pasos += ('Cuando este cambiada, volver a correr el diagnostico: el motor verifica que responda en la IP nueva y apunta la cola de Windows ahi.')
    $plan.pasos = @($pasos)
    return $plan
}

function Get-EscPosIdentity {
    <#
      Le pregunta a la impresora quien es, por su propio protocolo y por el mismo socket 9100.
      GS I n (1D 49 n) devuelve datos del equipo: n=66 fabricante, n=67 modelo, n=1 id de modelo.
      Es mejor que deducir la marca del OUI de la MAC: no hay tabla que mantener ni que adivinar,
      y lo contesta el aparato. No todas lo soportan -las OEM chinas suelen no contestar-, y en
      ese caso se devuelve vacio, que es un resultado honesto: no se pudo saber.
      Devuelve @{ fabricante = '...'; modelo = '...'; marca = '<de PosBrands>' }
    #>
    param([string]$Ip, [int]$TcpPort = 9100, [int]$TimeoutMs = 1200)
    $out = [ordered]@{ fabricante = ''; modelo = ''; marca = '' }
    if (-not $Ip) { return $out }
    $client = New-Object System.Net.Sockets.TcpClient
    try {
        $iar = $client.BeginConnect($Ip, $TcpPort, $null, $null)
        if (-not $iar.AsyncWaitHandle.WaitOne($TimeoutMs)) { return $out }
        $client.EndConnect($iar)
        $stream = $client.GetStream()
        $stream.WriteTimeout = $TimeoutMs
        $stream.ReadTimeout  = $TimeoutMs
        foreach ($par in @(@{ n = 66; campo = 'fabricante' }, @{ n = 67; campo = 'modelo' })) {
            try {
                $stream.Write([byte[]]@(0x1D, 0x49, [byte]$par.n), 0, 3)
                $stream.Flush()
                Start-Sleep -Milliseconds 300
                $buf = New-Object byte[] 64
                $leidos = 0
                try { $leidos = $stream.Read($buf, 0, 64) } catch {}
                if ($leidos -gt 0) { $out[$par.campo] = (Convert-EscPosInfoBytes -Bytes $buf -Leidos $leidos) }
            } catch {}
        }
    } catch { return $out }
    finally { try { $client.Close() } catch {} }
    # La marca se resuelve contra la lista que el motor ya usa para el resto del diagnostico.
    $out.marca = Resolve-BrandFromText -Texto ((([string]$out.fabricante) + ' ' + ([string]$out.modelo)).Trim())
    return $out
}

function Get-MacForIp {
    <#
      MAC de una IP de la red local, leida de la tabla ARP. Sirve para dos cosas: identificar el
      fabricante por OUI cuando la impresora no contesta quien es, y darle al asesor un dato que
      no cambia aunque la IP si.
      Se parsea por patron de IP + MAC y no por columnas, porque la salida de arp esta traducida.
    #>
    param([string]$Ip)
    if (-not $Ip) { return '' }
    try {
        # Un paquete cualquiera primero, para que la entrada exista en la tabla ARP.
        try { [void](New-Object System.Net.NetworkInformation.Ping).Send($Ip, 300) } catch {}
        foreach ($linea in @(& "$env:WINDIR\System32\ARP.EXE" -a 2>$null)) {
            $l = [string]$linea
            if ($l -match ('(?<![\d.])' + [regex]::Escape($Ip) + '(?![\d.])') -and
                $l -match '([0-9a-fA-F]{2}([-:])[0-9a-fA-F]{2}(\2[0-9a-fA-F]{2}){4})') {
                return ((([string]$Matches[1]) -replace ':', '-').ToLower())
            }
        }
    } catch {}
    return ''
}

function Get-OuiBrand {
    <#
      Fabricante segun los 3 primeros bytes de la MAC. Devuelve @{ oui = 'aa-bb-cc'; marca = '' }.
      Con la tabla vacia devuelve el OUI igual: el dato crudo es lo que permite armar la tabla.
    #>
    param([string]$Mac)
    $out = [ordered]@{ oui = ''; marca = '' }
    $m = ([string]$Mac) -replace ':', '-'
    if ($m -notmatch '^([0-9a-fA-F]{2}-[0-9a-fA-F]{2}-[0-9a-fA-F]{2})') { return $out }
    $out.oui = ([string]$Matches[1]).ToLower()
    if ($script:PrinterOuis.ContainsKey($out.oui)) { $out.marca = [string]$script:PrinterOuis[$out.oui] }
    return $out
}

function Get-PrinterSubnetCandidates {
    <#
      Subredes donde puede estar una impresora que NO esta en la del PC. Ordenadas por fuerza de
      la evidencia:
        1. la subred de una cola de Windows que apunta afuera -> ahi HUBO una impresora, es lo
           mas fuerte que se puede tener sin verla;
        2. los defaults de fabrica de las comanderas, que es como llegan de la caja.
      Se excluyen las subredes del propio PC: esas ya las barre el camino normal.
      Devuelve @( @{ prefijo = '192.168.1'; motivo = '...' } )
    #>
    param([int]$Max = 3)
    $propias = @(Get-LocalSubnetPrefixes)
    $out = @()
    $vistos = @()
    foreach ($inst in @(Get-InstalledNetworkPrinters)) {
        $ip = [string]$inst.ip
        if ($ip -notmatch '^\d{1,3}(\.\d{1,3}){3}$') { continue }
        $p = ($ip -split '\.')[0..2] -join '.'
        if ($propias -contains $p -or $vistos -contains $p) { continue }
        $vistos += $p
        $out += [ordered]@{ prefijo = $p
                            motivo = ('hay una cola de Windows apuntando a ' + $ip + ', que esta fuera de la red del PC' +
                                      $(if (@($inst.colas).Count -gt 0) { " (cola '" + (@($inst.colas) -join ', ') + "')" } else { ' (puerto sin cola)' })) }
    }
    # Defaults de fabrica mas frecuentes en comanderas termicas.
    foreach ($p in @('192.168.1', '192.168.0', '192.168.123', '10.0.0')) {
        if ($propias -contains $p -or $vistos -contains $p) { continue }
        $vistos += $p
        $out += [ordered]@{ prefijo = $p; motivo = 'subred de fabrica frecuente en comanderas' }
    }
    return @(@($out) | Select-Object -First $Max)
}

function Get-FreeIpInSubnet {
    <#
      Una IP libre en la subred del PC, para proponerle al asesor que se la ponga a la impresora.
      Se prueba de verdad que no responda: proponer una IP ocupada crearia un conflicto, que es
      uno de los problemas que venimos a resolver.
      Se buscan primero direcciones altas (.200-.250): las bajas son las que suele repartir el
      DHCP del router y las que ya usan los equipos del local.
    #>
    param([string]$Prefix, [string[]]$Evitar = @())
    if (-not $Prefix) { return '' }
    $ocupadas = @($Evitar | Where-Object { $_ })
    try { $ocupadas += @(Get-NetIPAddress -AddressFamily IPv4 -ErrorAction SilentlyContinue | ForEach-Object { [string]$_.IPAddress }) } catch {}
    try { $ocupadas += @(Get-InstalledNetworkPrinters | ForEach-Object { [string]$_.ip }) } catch {}
    foreach ($h in @(@(200..250) + @(60..99))) {
        $cand = "$Prefix.$h"
        if ($ocupadas -contains $cand) { continue }
        if (-not (Test-IpAlive -Ip $cand)) { return $cand }
    }
    return ''
}

function Find-NetConfigTool {
    <#
      La utilidad de configuracion de red de una marca, si esta en la PC.
      Se busca primero en la instalacion de Delitools, que es el empaquetado que ya mantiene el
      equipo (NetConfigTools queda en una ruta fija), y despues en una carpeta NetConfigTools al
      lado del script, para quien la copie suelta.
      NO se busca en Descargas: aca se termina LANZANDO un ejecutable, y una carpeta donde cae
      cualquier cosa no es un lugar del que convenga ejecutar nada.
      Devuelve @{ marca; exe; carpeta; ruta; encontrada; nota }
    #>
    param([string]$Marca)
    $def = @($script:NetConfigTools | Where-Object { [string]$_.marca -eq [string]$Marca }) | Select-Object -First 1
    if (-not $def) { return [ordered]@{ marca = [string]$Marca; encontrada = $false; ruta = ''; exe = ''; carpeta = ''; nota = '' } }
    $bases = @()
    foreach ($pf in @($env:ProgramFiles, ${env:ProgramFiles(x86)})) {
        if ($pf) { $bases += (Join-Path $pf 'Delitools\NetConfigTools') }
    }
    try { $bases += (Join-Path (Split-Path -Parent $PSCommandPath) 'NetConfigTools') } catch {}
    foreach ($b in @($bases | Where-Object { $_ })) {
        $carpeta = Join-Path $b ([string]$def.carpeta)
        $ruta = Join-Path $carpeta ([string]$def.exe)
        if (Test-PathExists -Path $ruta) {
            return [ordered]@{ marca = [string]$def.marca; encontrada = $true; ruta = $ruta
                               carpeta = $carpeta; exe = [string]$def.exe; nota = [string]$def.nota }
        }
    }
    return [ordered]@{ marca = [string]$def.marca; encontrada = $false; ruta = ''
                       carpeta = [string]$def.carpeta; exe = [string]$def.exe; nota = [string]$def.nota }
}

function Get-InstalledNetworkPrinters {
    <# Colas de Windows que apuntan a una IP: para no instalar dos veces la misma impresora. #>
    $out = @()
    $ports = @()
    try { $ports = @(Get-PrinterPort -ErrorAction Stop | Where-Object { $_.PrinterHostAddress }) } catch {}
    $printers = @()
    try { $printers = @(Get-Printer -ErrorAction SilentlyContinue) } catch {}
    foreach ($pt in $ports) {
        $colas = @($printers | Where-Object { [string]$_.PortName -eq [string]$pt.Name } | ForEach-Object { [string]$_.Name })
        $out += [ordered]@{
            ip = [string]$pt.PrinterHostAddress
            puertoTcp = $(try { [int]$pt.PortNumber } catch { 0 })
            puertoWindows = [string]$pt.Name
            colas = @($colas)
        }
    }
    return @($out)
}

function New-NetworkPrinter {
    <#
      Instala una impresora de red con el driver de texto generico apuntando a IP:puerto.
      Devuelve el nombre creado o ''.
    #>
    param([string]$Ip, [int]$TcpPort = 9100, [string]$Name = '')
    if (-not $Name) { $Name = ('FUDO-' + ($Ip -replace '\.', '-')) }
    $drv = Get-GenericTextDriverName
    if (-not $drv) { $drv = Install-GenericTextDriver }
    if (-not $drv) { throw 'no se pudo instalar el driver de texto generico' }

    $portName = "IP_$Ip"
    $existePuerto = $false
    try { $existePuerto = [bool](Get-PrinterPort -Name $portName -ErrorAction SilentlyContinue) } catch {}
    if (-not $existePuerto) {
        try { Add-PrinterPort -Name $portName -PrinterHostAddress $Ip -PortNumber $TcpPort -ErrorAction Stop }
        catch { throw "no se pudo crear el puerto TCP/IP ${portName}: $($_.Exception.Message)" }
    }
    $existe = $false
    try { $existe = [bool](Get-Printer -Name $Name -ErrorAction SilentlyContinue) } catch {}
    if (-not $existe) {
        Add-Printer -Name $Name -DriverName $drv -PortName $portName -ErrorAction Stop
    }
    return $Name
}

function Test-ForeignSubnetPrinters {
    <#
      Busca la impresora cuando NO esta en la red del PC. Es el caso que el motor no podia ver:
      una comandera con IP de fabrica (192.168.1.x) en un local cuyo router reparte 192.168.0.x
      esta en el mismo cable, pero el PC no tiene ninguna direccion en esa subred, asi que no le
      puede ni hablar. El camino manual era desenchufar el cable del router -que deja al cliente
      sin internet y al asesor sin asistencia remota- o pedir otra notebook.
      Aca se resuelve sumandole al PC una segunda direccion IP en la subred de la impresora: el
      PC conserva la suya, no pierde nada, y se saca al terminar.
      Detras de opt-in (Confirm-NetProbe): es lo mas invasivo que hace el motor y no esta
      probado contra hardware real.
      Devuelve $true si dejo un hallazgo concluyente.
    #>
    param([int]$TcpPort = 9100, [int]$MaxSubredes = 2)
    $cands = @(Get-PrinterSubnetCandidates -Max $MaxSubredes)
    $script:Diagnostics['subredesCandidatas'] = @($cands)
    if (@($cands).Count -eq 0) { return $false }

    $revisadas = @()
    $encontrada = $null
    $negado = $null
    foreach ($c in @($cands)) {
        if (-not (Confirm-NetProbe -Prefijo ([string]$c.prefijo) -Motivo ([string]$c.motivo))) {
            $negado = $c
            break
        }
        Write-StepDetail ('sumando una IP temporal para poder ver la subred ' + [string]$c.prefijo + '.0/24')
        $tmp = Add-TempSubnetIp -Prefijo ([string]$c.prefijo)
        if (-not $tmp.aplicado) {
            $revisadas += [ordered]@{ prefijo = [string]$c.prefijo; ok = $false; motivo = [string]$tmp.motivo; encontradas = 0 }
            continue
        }
        $enc = @(Find-NetworkPrinters -Prefix ([string]$c.prefijo) -TcpPort $TcpPort)
        # Identidad de cada hallazgo ANTES de sacar la IP temporal: despues ya no se le puede
        # hablar. Se le pregunta al aparato quien es y se guarda la MAC, que no cambia.
        $detalle = @()
        foreach ($e in @($enc)) {
            $mac = Get-MacForIp -Ip ([string]$e.ip)
            $oui = Get-OuiBrand -Mac $mac
            $ident = Get-EscPosIdentity -Ip ([string]$e.ip) -TcpPort $TcpPort
            $marca = [string]$ident.marca
            if (-not $marca) { $marca = [string]$oui.marca }
            $detalle += [ordered]@{
                ip = [string]$e.ip; puerto = $TcpPort; respondeEscPos = [bool]$e.respondeEscPos
                mac = [string]$mac; oui = [string]$oui.oui
                fabricante = [string]$ident.fabricante; modelo = [string]$ident.modelo; marca = $marca
                subred = [string]$c.prefijo
            }
        }
        [void](Remove-TempSubnetIps)
        $revisadas += [ordered]@{ prefijo = [string]$c.prefijo; ok = $true; motivo = [string]$c.motivo; encontradas = @($detalle).Count }
        if (@($detalle).Count -gt 0) {
            # Se prefiere la que contesto como ESC/POS: es una impresora confirmada, no un
            # equipo cualquiera con el 9100 abierto.
            $encontrada = @(@($detalle | Where-Object { $_.respondeEscPos }) + @($detalle)) | Select-Object -First 1
            $script:Diagnostics['impresorasOtraSubred'] = @($detalle)
            break
        }
    }
    $script:Diagnostics['subredesRevisadas'] = @($revisadas)

    if ($negado) {
        Add-Check -Id 'conn.otherSubnet' -Layer 3 -Name 'No se reviso si hay una impresora en otra subred' -Status 'skipped' -Plane 'os' `
            -Evidence @{ candidatas = @($cands); motivoSalteo = 'sin_confirmacion' } `
            -ArticleRef 'https://soporte.fu.do/es/articles/11730816' `
            -Recommendation ('Puede haber una impresora de red en ' + [string]$negado.prefijo + '.0/24 (' + [string]$negado.motivo + '), ' +
                             'que no es la subred de esta PC. Para verla el motor necesita sumarle una IP secundaria temporal a la placa ' +
                             '(la PC no pierde internet ni la conexion remota, y se saca al terminar). No se hizo porque nadie lo confirmo: ' +
                             'volver a correr y aceptar, o pasarle -AllowNetProbe $true.')
        return $false
    }
    if (-not $encontrada) {
        if (@($revisadas | Where-Object { $_.ok }).Count -gt 0) {
            Add-Check -Id 'conn.otherSubnet' -Layer 3 -Name 'Tampoco hay impresoras en las otras subredes revisadas' -Status 'ok' -Plane 'os' `
                -Evidence @{ revisadas = @($revisadas); candidatas = @($cands) } `
                -Recommendation ('Se revisaron ' + (@($revisadas | Where-Object { $_.ok } | ForEach-Object { [string]$_.prefijo + '.0/24' }) -join ', ') +
                                 ' y no respondio ninguna impresora. Si el cliente dice que tiene una comandera de red, esta apagada, sin cable, o en una subred distinta de las revisadas.')
        }
        return $false
    }

    $nic = Get-PrimaryIpv4Interface
    $plan = Resolve-NetworkPrinterPlan -Encontrada $encontrada -PrefijoPc ([string]$nic.prefijo) -Gateway (Get-DefaultGatewayIp)
    $script:Diagnostics['planRedImpresora'] = $plan
    Add-Check -Id 'conn.otherSubnet' -Layer 3 `
        -Name ('La impresora de red esta en otra subred que el PC: ' + [string]$plan.ip + $(if ($plan.marca) { ' (' + [string]$plan.marca + ')' } else { '' })) `
        -Status 'warn' -RootCauseCandidate $true -Plane 'os' `
        -Evidence @{ plan = $plan; encontradas = @($script:Diagnostics['impresorasOtraSubred']); revisadas = @($revisadas) } `
        -ArticleRef 'https://soporte.fu.do/es/articles/11730816' `
        -Recommendation ((@($plan.pasos) -join ' ') +
                         ' Mientras la impresora y el PC esten en subredes distintas, Windows no le puede mandar ninguna comanda.')
    return $true
}

function Test-Layer3-Network {
    param($Printer)
    $ip = $PrinterIp
    if (-not $ip -and $Printer) {
        $pn = [string]$Printer.PortName
        if ($pn -match '(\d{1,3}\.\d{1,3}\.\d{1,3}\.\d{1,3})') { $ip = $Matches[1] }
    }
    if (-not $ip) {
        # Sin IP conocida: barremos la red para ver si hay alguna impresora esperando.
        $prefijos = @(Get-LocalSubnetPrefixes)
        $enc = @()
        foreach ($pref in @($prefijos | Select-Object -First 2)) { $enc += @(Find-NetworkPrinters -Prefix $pref -TcpPort $Port) }
        $script:Diagnostics['impresorasEnRed'] = @($enc)
        $yaInstaladas = @(Get-InstalledNetworkPrinters)
        $script:Diagnostics['impresorasRedInstaladas'] = @($yaInstaladas)

        if (@($enc).Count -eq 0) {
            # v3.16: antes se cerraba aca con 'no hay impresoras en la red', y eso era falso
            # cuando la impresora estaba en otra subred -el caso de la comandera con IP de
            # fabrica-. Se busca ahi antes de afirmar que no hay nada.
            $hayOtra = Invoke-Step -Name 'layer3.otherSubnet' -Body { Test-ForeignSubnetPrinters -TcpPort $Port }
            if ($hayOtra) {
                Add-Check -Id 'conn.net' -Layer 3 -Name 'No hay impresoras por IP en la red del PC (si en otra subred, ver arriba)' `
                    -Status 'warn' -RootCauseCandidate $false -Plane 'os' `
                    -Evidence @{ subredes = $prefijos; puerto = $Port; encontradas = 0; otraSubred = $true } `
                    -Recommendation 'La impresora existe pero esta en otra subred: la causa y los pasos estan en el chequeo de la subred.'
                return
            }
            Add-Check -Id 'conn.net' -Layer 3 -Name ('No se encontraron impresoras por IP en la red' + $(if (@($prefijos).Count -gt 0) { ' (' + (@($prefijos | ForEach-Object { $_ + '.0/24' }) -join ', ') + ')' } else { '' })) `
                -Status 'fail' -RootCauseCandidate $true -Plane 'fudo_config' `
                -Evidence @{ subredes = $prefijos; puerto = $Port; encontradas = 0; yaInstaladas = $yaInstaladas } `
                -ArticleRef 'https://soporte.fu.do/es/articles/11730816' `
                -Recommendation ("Ningun equipo de la red responde en el puerto $Port. Si la comandera es Ethernet: revisar que este encendida y con el cable de red puesto (luces del puerto verde/naranja), " +
                                 'y hacer el self-test de la impresora (apagar, mantener FEED, encender) para leer su IP. Si la IP que imprime el self-test es de otra subred, hay que corregirla o poner la PC en la misma red.')
            return
        }

        $lista = @($enc | ForEach-Object { $_.ip + ' (' + $_.tipo + ')' })
        Add-Check -Id 'conn.net' -Layer 3 -Name ("Se encontraron $(@($enc).Count) impresora(s) por IP en la red") -Status 'warn' -Plane 'fudo_config' `
            -Evidence @{ encontradas = $enc; yaInstaladas = $yaInstaladas; puerto = $Port } `
            -ArticleRef 'https://soporte.fu.do/es/articles/11730816' `
            -Recommendation ('Detectadas en: ' + ($lista -join ' | ') + '. ' +
                             $(if (@($yaInstaladas).Count -gt 0) {
                                    'Hay colas de Windows apuntando a: ' + (@($yaInstaladas | ForEach-Object { $_.ip + $(if (@($_.colas).Count -gt 0) { ' -> ' + (@($_.colas) -join ', ') } else { ' (puerto sin cola)' }) }) -join ' | ') + ' (que exista la cola no significa que Fudo la tenga configurada). '
                                } else { 'Ninguna tiene cola de Windows todavia. ' }) +
                             'DOS CAMINOS EN FUDO, segun como se quiera configurar: ' +
                             '(A) Directo Ethernet -> NO hace falta instalar nada en Windows, alcanza con cargar la IP en Fudo (Administracion > Impresoras > Directo Ethernet, puerto 9100). ' +
                             '(B) Impresora del sistema operativo -> hay que instalar la cola en Windows (opcion del menu o -PrinterIp <ip> -InstallNetworkPrinter) y despues elegirla por nombre en Fudo. ' +
                             'Si en Fudo solo aparece el campo de IP, es la opcion A.')
        return
    }
    $script:Diagnostics['printerIp'] = $ip

    Write-StepDetail "haciendo ping a $ip"
    $pingOk = $false
    try { $pingOk = Test-Connection -ComputerName $ip -Count 2 -Quiet -ErrorAction Stop } catch {}
    Write-StepDetail ("probando el puerto $Port en " + $ip)
    $portOk = $false
    try {
        $t = Test-NetConnection -ComputerName $ip -Port $Port -WarningAction SilentlyContinue -ErrorAction Stop
        $portOk = [bool]$t.TcpTestSucceeded
    } catch {
        # Fallback socket
        try {
            $c = New-Object System.Net.Sockets.TcpClient
            $iar = $c.BeginConnect($ip, $Port, $null, $null)
            $portOk = $iar.AsyncWaitHandle.WaitOne(3000)
            if ($portOk) { $c.EndConnect($iar) }
            $c.Close()
        } catch {}
    }

    if ($portOk) {
        $esc = Test-IsEscPosDevice -Ip $ip -TcpPort $Port
        $yaInstaladas = @(Get-InstalledNetworkPrinters | Where-Object { [string]$_.ip -eq [string]$ip })
        $script:Diagnostics['impresorasRedInstaladas'] = @(Get-InstalledNetworkPrinters)
        Add-Check -Id 'conn.net' -Layer 3 -Name "Conectividad a impresora de red ${ip}:${Port}" -Status 'ok' `
            -Evidence @{ ip = $ip; ping = $pingOk; port9100 = $true; respondeEscPos = $esc; colasQueLaUsan = @($yaInstaladas | ForEach-Object { @($_.colas) } | Where-Object { $_ }) } `
            -Recommendation $(if (@($yaInstaladas).Count -eq 0) {
                    "La impresora responde en ${ip}:${Port}, asi que el hardware y la red estan bien. En Fudo se puede usar de dos formas: (A) Directo Ethernet, cargando solo esta IP y el puerto $Port, sin instalar nada en Windows; o (B) como impresora del sistema operativo, instalando la cola en Windows (opcion del menu o -PrinterIp $ip -InstallNetworkPrinter) y eligiendola por nombre en Fudo. Hoy no hay ninguna cola de Windows apuntando a esta IP."
                } elseif (-not $esc) {
                    "Hay algo escuchando en ${ip}:${Port} pero no respondio como impresora ESC/POS: confirmar que la IP sea la de la comandera y no de otro equipo."
                } else { '' })
        return
    }

    # Puerto 9100 caido: posible IP cambiada por DHCP. Intentar descubrir el nuevo host con 9100 abierto en la /24.
    Write-DoctorLog -Level 'WARN' -Message "Impresora ${ip}:${Port} inalcanzable. Buscando IP alternativa en la subred..."
    $discovered = @()
    try {
        $prefix = ($ip -split '\.')[0..2] -join '.'
        Write-StepDetail ("impresora inalcanzable: escaneando $prefix.1-254 buscando el puerto $Port")
        $localIps = @()
        try { $localIps = @(Get-NetIPAddress -AddressFamily IPv4 -ErrorAction SilentlyContinue | ForEach-Object { $_.IPAddress }) } catch {}
        # Escaneo acotado y en paralelo liviano (1..254) del puerto 9100
        $jobsList = @()
        foreach ($h in 1..254) {
            $cand = "$prefix.$h"
            if ($cand -eq $ip) { continue }
            $cli = New-Object System.Net.Sockets.TcpClient
            $ar  = $cli.BeginConnect($cand, $Port, $null, $null)
            $jobsList += [pscustomobject]@{ ip = $cand; client = $cli; ar = $ar }
        }
        Start-Sleep -Milliseconds 700
        foreach ($j in $jobsList) {
            try {
                if ($j.ar.AsyncWaitHandle.WaitOne(0)) { $j.client.EndConnect($j.ar); $discovered += $j.ip }
            } catch {}
            finally { try { $j.client.Close() } catch {} }
        }
    } catch {}
    $script:Diagnostics['discovered9100'] = $discovered

    $rec = if (@($discovered).Count -eq 1) {
        "Se detecto un unico host con 9100 abierto ($($discovered[0])). Probable nueva IP de la impresora (DHCP). Actualizar en Fudo: Administracion > Impresoras > editar IP, puerto 9100."
    } elseif (@($discovered).Count -gt 1) {
        "Hosts con 9100 abierto: $($discovered -join ', '). Confirmar por self-test cual corresponde y actualizar la IP en Fudo."
    } else {
        "Sin hosts con 9100 en la subred. Revisar cable/switch, luces del puerto Ethernet (verde+naranja), self-test (FEED al encender) para leer IP ADDRESS, y luz roja = falla HW (a tecnico)."
    }

    Add-Check -Id 'conn.net' -Layer 3 -Name "Impresora de red inalcanzable (${ip}:${Port})" -Status 'fail' -RootCauseCandidate $true `
        -Plane 'fudo_config' `
        -Evidence @{ ip = $ip; ping = $pingOk; port9100 = $false; discovered = $discovered } `
        -ArticleRef 'https://soporte.fu.do/es/articles/11730816' `
        -Recommendation $rec
}

# ---------------------------------------------------------------------------
# LAYER 4 - Prueba fisica de hardware (aisla HW vs config Fudo)
# ---------------------------------------------------------------------------
function Test-Layer4-HardwarePrint {
    param($Printer, $DetectedInterface)
    if (-not $TestPrint) {
        Add-Check -Id 'hw.testprint' -Layer 4 -Name 'Prueba fisica de impresion' -Status 'skipped' -Evidence @{ note = 'TestPrint deshabilitado'; skipReason = 'testprint_off' }
        return
    }
    if ($DryRun) {
        Add-Check -Id 'hw.testprint' -Layer 4 -Name 'Prueba fisica de impresion' -Status 'skipped' -Evidence @{ note = 'dry-run'; skipReason = 'dry_run' }
        return
    }

    if ($DetectedInterface -eq 'Ethernet') {
        $ip = $script:Diagnostics['printerIp']
        if (-not $ip) { Add-Check -Id 'hw.testprint' -Layer 4 -Name 'Prueba fisica (TCP 9100)' -Status 'skipped' -Evidence @{ note = 'sin IP'; skipReason = 'sin_ip' }; return }
        try {
            Write-StepDetail ("enviando ticket de prueba a " + $ip + ":" + $Port)
            $ok = Send-EscPosOverTcp -Ip $ip -TcpPort $Port
            if (-not $ok) {
                Add-Check -Id 'hw.testprint' -Layer 4 -Name 'Prueba fisica ESC/POS por red' -Status 'fail' -RootCauseCandidate $true `
                    -Plane 'hardware' -Evidence @{ ip = $ip; port = $Port; sent = $false } `
                    -ArticleRef 'https://soporte.fu.do/es/articles/11730816' `
                    -Recommendation ("No se pudo abrir la conexion a $ip por el puerto $Port. Revisar que la impresora este encendida y en la misma red, " +
                                     'que la IP sea la correcta (self-test de la impresora: apagar, mantener FEED y encender) y que ningun firewall bloquee el 9100.')
                return
            }
            # Mismo criterio que por USB: que el socket TCP acepte los bytes NO prueba que haya
            # salido papel. Sin rollo, con la tapa abierta o con la impresora en error, el envio
            # igual da exito. El unico juez es el humano que esta al lado.
            $salio = Confirm-PaperCameOut -Printer ("$ip" + ':' + $Port)
            $script:Diagnostics['ticketConfirmado'] = $salio
            if ($salio -eq $false) {
                Add-Check -Id 'hw.testprint' -Layer 4 -Name 'Prueba fisica ESC/POS por red' -Status 'fail' -RootCauseCandidate $true `
                    -Plane 'hardware' -Evidence @{ ip = $ip; port = $Port; sent = $true; confirmadoPorHumano = $false } `
                    -ArticleRef 'https://soporte.fu.do/es/articles/11730816' `
                    -Recommendation ('La impresora acepto los datos por red pero no salio papel. Eso descarta la red y Windows: ' +
                                     'revisar rollo (que quede papel y del lado correcto) y que la tapa este bien cerrada. ' +
                                     'Si la luz esta en rojo o titilando, es hardware.')
                return
            }
            if ($null -eq $salio) {
                Add-Check -Id 'hw.testprint' -Layer 4 -Name 'Prueba fisica ESC/POS por red: enviado, sin confirmar' -Status 'warn' `
                    -Plane 'hardware' -Evidence @{ ip = $ip; port = $Port; sent = $true; confirmadoPorHumano = $null } `
                    -ArticleRef 'https://soporte.fu.do/es/articles/11730816' `
                    -Recommendation ("La impresora acepto el ticket por red, que es todo lo que se puede verificar por software. " +
                                     'Confirmar con alguien en el local si salio el papel: recien ahi se puede dar por resuelto.')
                return
            }
            Add-Check -Id 'hw.testprint' -Layer 4 -Name 'Prueba fisica ESC/POS por red' -Status 'ok' `
                -Plane 'hardware' -Evidence @{ ip = $ip; port = $Port; sent = $true; confirmadoPorHumano = $true } `
                -Recommendation 'Salio el papel por red: el hardware y la red estan bien. Si la comanda no sale, la causa esta en la config de Fudo (area/cocina/sala).'
        } catch {
            Add-Check -Id 'hw.testprint' -Layer 4 -Name 'No se pudo mandar el ticket de prueba a la impresora de red' -Status 'fail' -RootCauseCandidate $true `
                -Plane 'hardware' -Evidence @{ ip = $ip; error = $_.Exception.Message } `
                -ArticleRef 'https://soporte.fu.do/es/articles/11730816'
        }
    } else {
        if ($null -eq $Printer) {
            # v3.13: el motivo decia 'sin_impresora' tambien cuando SI habia hardware presente y
            # lo que faltaba era que Windows le asignara un puerto. Se vio una PC con
            # hardwarePresente=1 y cantidadColas=0 escalando con skipReason='sin_impresora': el
            # motivo no permitia distinguir 'no hay nada enchufado' de 'esta enchufada y Windows
            # no le dio puerto', que son dos casos con soluciones distintas.
            $hwPres = 0
            if ($script:Diagnostics.Contains('hwDeviceCount')) { $hwPres = [int]$script:Diagnostics['hwDeviceCount'] }
            if ($hwPres -gt 0) {
                Add-Check -Id 'hw.testprint' -Layer 4 -Name 'No se pudo probar: la impresora esta conectada pero Windows no le asigno ningun puerto' -Status 'skipped' -Plane 'hardware' `
                    -Evidence @{ note = 'hardware presente sin puerto asignado'; skipReason = 'sin_puerto_asignado'; hardwarePresente = $hwPres } `
                    -ArticleRef 'https://soporte.fu.do/es/articles/11730817' `
                    -Recommendation ('Windows ve la impresora conectada pero no le asigno puerto, asi que no hay ninguna cola por donde mandarle el ticket de prueba. ' +
                                     'NO se crea una cola de prueba sobre un puerto inventado: imprimiria al vacio. ' +
                                     'Con la impresora ENCENDIDA: desenchufar el USB, esperar 5 segundos y volver a enchufarlo en un puerto directo de la PC (sin hub). ' +
                                     'Si sigue sin aparecer, instalar el driver "Generico / Solo texto", que es lo que crea el puerto USB.')
            } else {
                Add-Check -Id 'hw.testprint' -Layer 4 -Name 'No se pudo probar: no hay ninguna impresora fisica instalada' -Status 'skipped' -Plane 'hardware' `
                    -Evidence @{ note = 'sin impresora real objetivo'; skipReason = 'sin_impresora'; hardwarePresente = 0 } `
                    -Recommendation 'No hay una impresora fisica instalada para probar: resolver primero la capa 1 (hardware/instalacion).'
            }
            return
        }
        if (-not (Test-PortHasLiveDevice -PortName ([string]$Printer.PortName))) {
            # v3.7: antes se salteaba y la corrida no podia cerrar nunca (6 de 8 corridas 3.6
            # terminaron en 'skipped'). Si el fierro esta presente pero en OTRO puerto -tipico
            # despues de un replug, o con una cola vieja mal apuntada- y ahi hay una cola del
            # cliente, la prueba se reapunta a esa en vez de saltearse.
            $otra = $null
            try {
                $vivos = @()
                if ($script:Diagnostics.Contains('livePorts')) {
                    $vivos = @($script:Diagnostics['livePorts'] | Where-Object { $_ -and ([string]$_ -ne [string]$Printer.PortName) })
                }
                foreach ($pv in $vivos) {
                    $cand = Find-QueueForPort -PortName ([string]$pv)
                    if ($cand) { $otra = $cand; break }
                }
            } catch {}
            if ($otra) {
                Write-StepDetail ("se reapunta la prueba a '" + [string]$otra.Name + "' (" + [string]$otra.PortName + "): ahi esta el hardware")
                Add-Action -Type 'testprint.retarget' -Target ([string]$otra.Name) `
                    -Before ([string]$Printer.Name + ' @ ' + [string]$Printer.PortName) `
                    -After  ([string]$otra.Name + ' @ ' + [string]$otra.PortName) -Reversible $true
                $Printer = $otra
            } else {
                Add-Check -Id 'hw.testprint' -Layer 4 -Name 'Prueba fisica de impresion' -Status 'skipped' -Plane 'hardware' `
                    -Evidence @{ printer = [string]$Printer.Name; port = [string]$Printer.PortName; skipReason = 'puerto_sin_dispositivo' } `
                    -Recommendation ("No se prueba: en $($Printer.PortName) no hay ningun dispositivo conectado. " +
                                     'Enviar un ticket ahi solo lo dejaria encolado y daria un falso OK de hardware.')
                return
            }
        }
        $v = Test-IsVirtualPrinter $Printer
        if ($v.isVirtual) {
            Add-Check -Id 'hw.testprint' -Layer 4 -Name 'Prueba fisica de impresion' -Status 'skipped' -Plane 'hardware' `
                -Evidence @{ printer = [string]$Printer.Name; reason = [string]$v.reason; skipReason = 'impresora_virtual' } `
                -Recommendation "No se prueba sobre '$($Printer.Name)': es una impresora virtual y daria un falso OK de hardware."
            return
        }
        try {
            Write-StepDetail "enviando ticket de prueba a '$($Printer.Name)'"
            Initialize-RawPrinterHelper
            $bytes = [System.Text.Encoding]::GetEncoding(437).GetBytes((Get-EscPosTestTicket -Caption 'FUDO HW TEST'))
            $ok = [FudoRawPrinter]::SendBytes($Printer.Name, $bytes)

            # WritePrinter OK solo significa "el spooler lo acepto". Si el trabajo sigue en la
            # cola despues de un momento, el papel NO salio.
            $quedoEnCola = $false
            $bloqueadoPor = 0
            if ($ok) {
                Write-StepDetail 'verificando que el ticket haya salido'
                $drain = Wait-QueueDrain -Printer $Printer.Name
                $quedoEnCola  = [bool]$drain.quedoEnCola
                $bloqueadoPor = [int]$drain.bloqueadoPor
            }
            if ($quedoEnCola) {
                # El nombre del check es el texto que sale como CAUSA. Decia el titulo del paso
                # ('Prueba fisica ESC/POS por USB (RAW)'), que no explica nada al asesor.
                Add-Check -Id 'hw.testprint' -Layer 4 `
                    -Name $(if ($bloqueadoPor -gt 0) { "El ticket de prueba quedo en la cola: hay $bloqueadoPor comanda(s) vieja(s) delante bloqueandola" }
                            else { 'El ticket de prueba entro a la cola y no se imprimio: la impresora no responde' }) `
                    -Status 'fail' -RootCauseCandidate $true `
                    -Plane 'hardware' -Evidence @{ printer = $Printer.Name; sent = $true; quedoEnCola = $true; trabajosDelante = $bloqueadoPor } `
                    -ArticleRef 'https://soporte.fu.do/es/articles/11730817' `
                    -Recommendation $(if ($bloqueadoPor -gt 0) {
                            "El ticket de prueba entro a la cola pero no salio, y hay $bloqueadoPor comanda(s) vieja(s) delante bloqueandola. Primero limpiar la cola (opcion del script o Get-PrintJob -PrinterName '$($Printer.Name)' | Remove-PrintJob) y recien despues volver a probar: hasta que la cola no este vacia, la prueba de impresion no dice nada sobre la impresora."
                        } else {
                            'El ticket entro a la cola pero no se imprimio: la impresora no esta respondiendo. ' +
                            'Revisar que este encendida, con papel, la tapa cerrada y el cable USB firme. ' +
                            'Si la luz esta en rojo o titilando, es falla de hardware o falta de papel.'
                        })
                return
            }

            if (-not $ok) {
                Add-Check -Id 'hw.testprint' -Layer 4 -Name 'No se pudo enviar el ticket de prueba a la impresora (envio RAW rechazado)' -Status 'fail' -RootCauseCandidate $true `
                    -Plane 'hardware' -Evidence @{ printer = $Printer.Name; sent = $false } `
                    -ArticleRef 'https://soporte.fu.do/es/articles/12044021' `
                    -Recommendation 'El envio RAW fallo: revisar puerto/driver/cable.'
                return
            }

            # El trabajo salio de la cola, pero eso NO prueba que haya salido papel: el
            # spooler lo da por impreso en cuanto el device acepta los bytes. Sin rollo,
            # con la tapa abierta o con un adaptador USB-paralelo sin impresora del otro
            # lado, la cola queda limpia y no se imprimio nada. Preguntamos.
            $salio = Confirm-PaperCameOut -Printer $Printer.Name
            $script:Diagnostics['ticketConfirmado'] = $salio
            if ($salio -eq $false) {
                Add-Check -Id 'hw.testprint' -Layer 4 -Name 'La impresora recibio el ticket de prueba pero no salio papel' -Status 'fail' -RootCauseCandidate $true `
                    -Plane 'hardware' -Evidence @{ printer = $Printer.Name; sent = $true; quedoEnCola = $false; confirmadoPorHumano = $false } `
                    -ArticleRef 'https://soporte.fu.do/es/articles/11730817' `
                    -Recommendation ('El spooler dice que el ticket se imprimio pero no salio papel. Eso descarta Windows y la cola: ' +
                                     'revisar rollo (que quede papel y que este del lado correcto), tapa bien cerrada, ' +
                                     'y si la impresora entra por un adaptador USB-paralelo, que el cable llegue a la impresora. ' +
                                     'Si la luz esta en rojo o titilando, es hardware.')
                return
            }
            if ($null -eq $salio) {
                Add-Check -Id 'hw.testprint' -Layer 4 -Name 'Prueba fisica ESC/POS por USB (RAW): enviado, sin confirmar' -Status 'warn' `
                    -Plane 'hardware' -Evidence @{ printer = $Printer.Name; sent = $true; quedoEnCola = $false; confirmadoPorHumano = $null } `
                    -ArticleRef 'https://soporte.fu.do/es/articles/12044021' `
                    -Recommendation ('El ticket salio de la cola de Windows, que es todo lo que se puede verificar por software. ' +
                                     'Hay que mirar la impresora: si salio el papel, el hardware esta bien y el problema es config de Fudo (area/cocina/sala); ' +
                                     'si no salio, es rollo, tapa o cable.')
                return
            }
            Add-Check -Id 'hw.testprint' -Layer 4 -Name 'Prueba fisica ESC/POS por USB (RAW)' -Status 'ok' `
                -Plane 'hardware' -Evidence @{ printer = $Printer.Name; sent = $true; quedoEnCola = $false; confirmadoPorHumano = $true } `
                -ArticleRef 'https://soporte.fu.do/es/articles/12044021' `
                -Recommendation 'El hardware imprime OK (confirmado: salio el papel). Si la comanda no sale, el problema es la config de Fudo (area/cocina/sala/categorias).'
        } catch {
            Add-Check -Id 'hw.testprint' -Layer 4 -Name 'Prueba fisica ESC/POS por USB (RAW)' -Status 'fail' -RootCauseCandidate $true `
                -Plane 'hardware' -Evidence @{ error = $_.Exception.Message }
        }
    }
}

# ---------------------------------------------------------------------------
# LAYER 5 - Plano de configuracion Fudo (deteccion + escalamiento)
# ---------------------------------------------------------------------------
function Test-Layer5-FudoConfig {
    param($DetectedInterface)

    # 5.0 A que cola le esta mandando Fudo REALMENTE (evidencia local, no hace falta la API)
    Write-StepDetail 'revisando el historial de impresion del spooler'
    $hist = Get-PrintHistory
    $script:Diagnostics['historialImpresion'] = $hist

    if (-not $hist.habilitado) {
        $rem = Invoke-Remediation -Description 'Habilitar el log de impresion de Windows (para saber que cola usa Fudo)' `
            -Type 'log.enable' -Target 'Microsoft-Windows-PrintService/Operational' -Before 'deshabilitado' -After 'habilitado' -Reversible $true -Fix {
                & wevtutil sl 'Microsoft-Windows-PrintService/Operational' /e:true 2>&1 | Out-Null
                'log de PrintService habilitado'
            }
        # No es una reparacion: es un dato que falta. Marcarlo 'fixed' inflaba autoFixCount,
        # ensuciaba la columna 'reparaciones' y podia dar por 'resuelta' una corrida que solo
        # habia encendido un log.
        Add-Check -Id 'fudo.usoReal' -Layer 5 -Name 'Historial de impresion no disponible' -Status $(if ($rem.applied) { 'warn' } else { 'skipped' }) -Plane 'os' `
            -Evidence @{ log = 'Microsoft-Windows-PrintService/Operational'; habilitado = $false } -ActionTaken $rem.note `
            -Recommendation $(if ($rem.applied) {
                    'Windows no registraba los trabajos de impresion. Se activo el registro: a partir de ahora, cada corrida va a poder decir a que cola le manda Fudo y cuando fue la ultima comanda. Volver a correr el diagnostico despues de intentar imprimir una comanda.'
                } else {
                    'El log de impresion de Windows esta deshabilitado (viene asi de fabrica), por eso no se puede ver el historial. Habilitarlo con: wevtutil sl "Microsoft-Windows-PrintService/Operational" /e:true'
                })
    } else {
        $conFudo = @($hist.porImpresora | Where-Object { [int]$_.deFudo -gt 0 } | Sort-Object -Property @{ Expression = { [int]$_.deFudo }; Descending = $true })
        if (@($conFudo).Count -gt 0) {
            $detalle = @($conFudo | ForEach-Object { "$($_.impresora): $($_.deFudo) comanda(s), ultima el $($_.ultimoDeFudo)" })
            Add-Check -Id 'fudo.usoReal' -Layer 5 -Name ('Fudo le manda comandas a: ' + (@($conFudo | ForEach-Object { $_.impresora }) -join ', ')) -Status 'ok' -Plane 'fudo_config' `
                -Evidence @{ porImpresora = @($hist.porImpresora) } `
                -Recommendation ('Historial del spooler: ' + ($detalle -join ' | ') + '. Esto confirma que en Fudo esa impresora esta configurada y recibiendo comandas; si el papel no sale, el problema esta en la impresora o su cola, no en la configuracion de Fudo.')
        } elseif (-not $hist.atribuible) {
            # v3.15, telemetria del 04/09: deFudo = 0 en 146 de 146 entradas de historial de 229
            # corridas, y los unicos nombres de documento que Windows reporta son los genericos
            # del spooler. Con eso el motor NO puede decir "Fudo no esta mandando comandas":
            # puede decir que no tiene con que saberlo. Antes lo afirmaba igual, como causa raiz
            # y en plano fudo_config, y mandaba al asesor a revisar la configuracion de Fudo de un
            # local donde Fudo podia estar imprimiendo perfectamente. Es el mismo patron de los
            # catorce falsos positivos del proyecto: una ausencia de dato leida como evidencia.
            $otras = @($hist.porImpresora | Where-Object { [int]$_.total -gt 0 })
            Add-Check -Id 'fudo.usoReal' -Layer 5 -Name 'No se puede saber si Fudo mando comandas (el historial no dice que programa imprimio)' `
                -Status 'warn' -RootCauseCandidate $false -Plane 'os' `
                -Evidence @{ porImpresora = @($hist.porImpresora); atribuible = $false
                             trabajos = [int]$hist.trabajos; docsInformativos = [int]$hist.docsInformativos } `
                -ArticleRef 'https://soporte.fu.do/es/articles/11730815' `
                -Recommendation ('El historial de impresion de Windows ' +
                                 $(if (@($otras).Count -gt 0) { 'tiene trabajos (' + (@($otras | ForEach-Object { $_.impresora }) -join ', ') + ') pero ninguno' } else { 'todavia no tiene trabajos que' }) +
                                 ' dice que programa los mando: Windows los registra con el nombre generico del spooler. Por eso el motor no puede confirmar ni descartar que la comanda de Fudo haya salido. Hay que verificarlo a mano: mandar una comanda desde Fudo y ver si sale el papel.')
        } else {
            $otras = @($hist.porImpresora | Where-Object { [int]$_.total -gt 0 })
            Add-Check -Id 'fudo.usoReal' -Layer 5 -Name 'Ninguna cola recibio comandas de Fudo en el historial' -Status 'warn' -RootCauseCandidate $true -Plane 'fudo_config' `
                -Evidence @{ porImpresora = @($hist.porImpresora) } `
                -ArticleRef 'https://soporte.fu.do/es/articles/11730815' `
                -Recommendation ('En el historial de impresion de Windows no hay ningun trabajo de la App Nativa de Fudo' +
                                 $(if (@($otras).Count -gt 0) { ' (si hay de otros programas: ' + (@($otras | ForEach-Object { $_.impresora }) -join ', ') + ')' } else { '' }) +
                                 '. Eso apunta a que Fudo no esta llegando a mandar la comanda: revisar que la impresora este registrada en Fudo con su cocina/area y que las categorias tengan cocina asignada. Tambien puede ser que el historial sea corto: probar imprimir una comanda y volver a correr.')
        }
    }

    # Estos chequeos viven en el backend de Fudo (no en el OS). El motor los deja
    # como 'requires_fudo_config' con la guia puntual; la capa orquestadora (API Fudo o asesor) resuelve.
    $items = @(
        @{ id='fudo.printerRegistered'; name='Impresora registrada en Fudo (Administracion > Impresoras)'; art='https://soporte.fu.do/es/articles/16419361';
           rec='Confirmar que la impresora este dada de alta con la interfaz correcta (USB o Directo Ethernet).' },
        @{ id='fudo.printerKitchen'; name='Impresora con Cocina/Area asignada'; art='https://soporte.fu.do/es/articles/11730815';
           rec='Si la impresora no tiene cocinas/areas asignadas, NO imprime ninguna comanda. Asignar el area correspondiente.' },
        @{ id='fudo.categoryKitchen'; name='Categorias/subcategorias con Cocina asignada'; art='https://soporte.fu.do/es/articles/11730815';
           rec='Cada categoria debe tener una cocina asignada; si falta, esos productos no se imprimen en la comanda.' },
        @{ id='fudo.rooms'; name='Salas seleccionadas en la impresora (si usa Salas)'; art='https://soporte.fu.do/es/articles/11730815';
           rec='Si el local trabaja con salas, la impresora debe tener tildadas las salas correspondientes.' }
    )
    foreach ($it in $items) {
        Add-Check -Id $it.id -Layer 5 -Name $it.name -Status 'warn' -Plane 'fudo_config' `
            -Evidence @{ verifiable = 'requiere API/backend Fudo o verificacion en la web app' } `
            -ArticleRef $it.art -Recommendation $it.rec
    }
}

# ---------------------------------------------------------------------------
# Diagnostico final: eleccion de causa raiz + resolucion
# ---------------------------------------------------------------------------
function Resolve-Diagnosis {
    $checks = @($script:Checks)
    $fixed  = @($checks | Where-Object { $_.status -eq 'fixed' })
    $fails  = @($checks | Where-Object { $_.status -eq 'fail' })
    $rootCandidates = @($checks | Where-Object { $_.rootCauseCandidate -and $_.status -in @('fail','warn') })

    # v3.7: una causa vieja no puede ganarle a la reparacion que la dejo sin efecto. Se vio la
    # corrida 2 de una PC diagnosticando "la impresora 'FUDO-USB001' esta desconectada" 35
    # segundos despues de que la corrida 1 bindeara ese puerto y creara esa cola. Si hubo un
    # re-bind del puerto y ahi ahora hay un dispositivo, ese 'fail' quedo obsoleto.
    $reBind = @($fixed | Where-Object { $_.id -in @('hw.noPortBound','conn.usb','printer.exists','printer.disconnected') })
    if (@($reBind).Count -gt 0) {
        $rootCandidates = @($rootCandidates | Where-Object {
            $esViejo = ($_.id -in @('printer.disconnected','hw.disconnected')) -and ($_.status -eq 'fail')
            if (-not $esViejo) { return $true }
            $puerto = ''
            try { $puerto = [string]$_.evidence.port } catch {}
            -not (Test-PortHasLiveDevice -PortName $puerto)
        })
    }

    # v3.9: en un cliente que imprime por RED, el diagnostico USB no puede ser la causa raiz.
    # Se vieron PCs con las colas de comandas en puertos IP_192.168.x.x sanas y cero hardware USB
    # cerrando con "Ninguna impresora fisica conectada", y otra con la termica en LPT1: sana
    # mientras el motor culpaba a una inkjet USB desconectada. El asesor lee que no hay impresora
    # cuando en realidad la impresora esta y anda.
    $puertoObjetivo = ''
    try { if ($script:Diagnostics.Contains('printer')) { $puertoObjetivo = [string]$script:Diagnostics['printer'].port } } catch {}
    $objetivoEsUsb = ($puertoObjetivo -match '^(?i)USB\d+')
    $colasNoUsbSanas = @()
    try {
        if ($script:Diagnostics.Contains('colas')) {
            $colasNoUsbSanas = @($script:Diagnostics['colas'] | Where-Object {
                -not $_.esDePrueba -and [int]$_.score -eq 0 -and ([string]$_.puerto -notmatch '^(?i)USB\d+')
            })
        }
    } catch {}

    if ($puertoObjetivo -and -not $objetivoEsUsb -and @($colasNoUsbSanas).Count -gt 0) {
        $script:Diagnostics['modoRedDetectado'] = [ordered]@{
            puertoObjetivo = $puertoObjetivo
            colasNoUsbSanas = @($colasNoUsbSanas | ForEach-Object { [string]$_.nombre + ' (' + [string]$_.puerto + ')' })
        }
        $rootCandidates = @($rootCandidates | Where-Object {
            $_.id -notin @('hw.deviceConnected','hw.disconnected','conn.usb')
        })
    }

    # v3.11: si una cola del cliente tiene comandas encoladas que no drenan y su puerto sigue
    # sirviendo, el veredicto "no hay ninguna impresora conectada" es demostrablemente falso:
    # alguien recibio esas comandas. Se vio una PC con BARRA [192.168.0.17] con 93 trabajos y
    # COCINA [192.168.0.50] con 13 cerrando como hardware.no_conectada mientras tenia una
    # POS-80 en LPT1: sana, y ese mismo caso lo resolvio un asesor a mano mirando la cola.
    $backlog = $checks | Where-Object { $_.id -eq 'queue.otherBacklog' -and $_.status -eq 'fail' } | Select-Object -First 1
    $backlogUtil = $false
    try { if ($backlog) { $backlogUtil = [bool]$backlog.evidence.puertoUtil } } catch {}
    if ($backlogUtil) {
        $script:Diagnostics['colaAtascadaGana'] = @($backlog.evidence.colas)
        $rootCandidates = @($rootCandidates | Where-Object {
            $_.id -notin @('hw.deviceConnected','hw.disconnected','conn.usb')
        })
    }

    # Prioridad por capa (mas abajo primero: OS/HW antes que config); ante empate, el que se
    # detecto primero, para que la causa no cambie de una corrida a otra con los mismos datos.
    $ordered = @($rootCandidates | Sort-Object @{ Expression = { [int]$_.layer } }, @{ Expression = { [int]$_.seq } })

    $hwTest = $checks | Where-Object { $_.id -eq 'hw.testprint' } | Select-Object -First 1

    $resolved = $false
    $rootCause = $null
    # v3.12: el id de la causa se decide en el mismo lugar que el texto. Antes salia solo
    # de $ordered, asi que las ramas sin candidato (se reparo algo pero nadie confirmo el
    # papel; hardware OK sin nada roto) viajaban con rootCauseCheckId vacio: 2 de las 19
    # corridas 3.11 del 02/09, y la categoria de esas filas quedaba sin relacion con la causa.
    $rootCheckId = ''
    $confidence = 'low'
    $residual = @()

    # OJO: aplicar una reparacion NO es cerrar el caso. Se declaraba 'resolved' con solo
    # tener un check en 'fixed' y ninguno en 'fail', y encima la CAUSA salia del nombre de la
    # reparacion ("Puerto USB desmapeado", "Exclusion preventiva de Defender"). Resultado: la
    # planilla marcaba 18% de corridas resueltas con la columna "que resolvio" vacia, y la
    # corrida siguiente de la misma PC volvia como sigue_fallando.
    # Ahora el unico camino a 'resuelto' es que la cadena imprima: hw.testprint en 'ok', que
    # desde 3.2 solo pasa si un humano confirmo que salio el papel.
    # La evidencia NO es que la Nativa este apagada: la Nativa es un native messaging host que
    # el navegador levanta cuando Fudo la necesita, asi que con Fudo cerrado estar apagada es lo
    # normal (probado en una PC real: sin Fudo abierto el proceso no existe). Tomarlo como
    # bloqueante habria impedido cerrar cualquier caso diagnosticado con Fudo cerrado.
    #
    # v3.11 - CRITERIO DE CIERRE, decision de alcance. Lo que este motor diagnostica y repara es
    # la cadena de impresion de WINDOWS: el caso cierra cuando la impresora imprime. Dos gates
    # anteriores se sacan porque hacian que casi nada pudiera cerrar:
    #  1) v3.9 exigia que el historial del spooler mostrara alguna comanda de Fudo
    #     (fudo.usoReal). Eso vive en el backend de Fudo, no se puede verificar desde la PC del
    #     cliente y por lo tanto iba a quedar pendiente SIEMPRE. Ahora no bloquea: baja la
    #     confianza a 'medium' y se avisa en pantalla que falta ese tramo.
    #  2) Se exigia @($fixed).Count -gt 0, o sea al menos una reparacion. Una PC que ya estaba
    #     sana y donde el ticket de prueba salio bien NO podia cerrar: caia en "Hardware imprime
    #     OK; causa probable en configuracion de Fudo". Si imprime, esta OK, se haya tocado algo
    #     o no.
    # Lo que sigue bloqueando: cualquier check en 'fail' (ahi entra la Nativa no instalada, la
    # cola atascada, el puerto sin dispositivo) y que no haya confirmacion humana de que salio
    # el papel (hw.testprint distinto de 'ok').
    $fudoSinUso = @($checks | Where-Object {
        $_.id -eq 'fudo.usoReal' -and $_.status -eq 'warn' -and $_.plane -eq 'fudo_config'
    })
    # v3.13: 'fudoSinUso = false' significaba dos cosas opuestas y no habia forma de
    # distinguirlas: 'Fudo SI imprimio' y 'no tenemos idea'. Cuando el log de impresion venia
    # apagado (viene asi de fabrica), el motor lo habilita en esa misma corrida y el historial
    # queda vacio: el check fudo.usoReal sale con plano 'os' -no 'fudo_config'-, no entra en el
    # filtro de arriba, y el caso cerraba con fudoSinUso=false como si Fudo estuviera
    # imprimiendo. En la telemetria del 02/09 fue 10 de 10 primeras corridas de cada PC, y la
    # corrida siguiente de esas mismas PCs daba true 5 de 5. Con eso, el cruce
    # 'resolved x fudoSinUso' daba 4/4 cierres completos y era un artefacto.
    $usoReal = $checks | Where-Object { $_.id -eq 'fudo.usoReal' } | Select-Object -First 1
    $fudoUsoEstado = 'sin_datos'
    if ($usoReal -and $usoReal.status -eq 'ok') { $fudoUsoEstado = 'con_comandas' }
    elseif (@($fudoSinUso).Count -gt 0)         { $fudoUsoEstado = 'sin_comandas' }
    # v3.15: hay historial, pero no identifica quien imprimio. No es 'sin_comandas' (eso afirma
    # que Fudo no mando nada) ni 'sin_datos' (eso dice que no hay historial): es que el dato que
    # hay no alcanza para atribuir. Con el matcher por nombre de documento roto en el 100% de las
    # corridas, este es hoy el estado real de casi todas.
    elseif ($usoReal -and $usoReal.status -eq 'warn' -and $usoReal.evidence -and ($usoReal.evidence.atribuible -eq $false)) { $fudoUsoEstado = 'no_atribuible' }
    $paperOk = [bool]($hwTest -and $hwTest.status -eq 'ok')

    if (@($fails).Count -eq 0 -and $paperOk) {
        $resolved = $true
        # No se puede cerrar con confianza alta si el ultimo tramo -que la comanda de Fudo
        # llegue- no se pudo confirmar.
        $confidence = $(if (@($fudoSinUso).Count -gt 0 -or $fudoUsoEstado -eq 'no_atribuible') { 'medium' } else { 'high' })
        $rootCause = $(if (@($fixed).Count -gt 0) {
                ($fixed | Sort-Object { $_.layer } | Select-Object -First 1).name
            } else {
                'La impresora ya imprimia bien desde Windows: el ticket de prueba salio sin necesidad de reparar nada'
            })
    }

    if (-not $resolved) {
        if (@($ordered).Count -gt 0) {
            $rootCause = $ordered[0].name
            $confidence = if ($ordered[0].plane -eq 'fudo_config') { 'medium' } else { 'medium' }
        } elseif (@($fixed).Count -gt 0) {
            # Se repararon cosas pero nadie confirmo que la comanda sale. Es un estado del
            # motor, no un hallazgo de la PC, y por eso ningun check lo representa: sin id
            # propio estas corridas quedaban sin clasificar (4 de 19 el 02/09).
            $rootCause = 'Se aplicaron reparaciones (' + ((@($fixed | Sort-Object { $_.layer } | ForEach-Object { $_.name })) -join '; ') + '); falta confirmar que la comanda sale'
            $rootCheckId = 'repair.pendingConfirm'
            $confidence = 'medium'
        } elseif ($hwTest -and $hwTest.status -eq 'ok') {
            # HW OK y nada roto en OS => casi seguro config Fudo
            $rootCause = 'Hardware imprime OK; causa probable en configuracion de Fudo (area/cocina/sala)'
            $rootCheckId = 'fudo.configProbable'
            $confidence = 'medium'
        } else {
            $rootCause = 'No concluyente'
            $rootCheckId = 'engine.inconclusive'
            $confidence = 'low'
        }
    }

    # Residual a escalar: cualquier check fudo_config en warn/fail o fallas no resueltas
    $residual = @($checks | Where-Object {
        ($_.status -in @('fail','warn')) -and ($_.plane -eq 'fudo_config' -or ($_.rootCauseCandidate -and $_.status -eq 'fail'))
    } | ForEach-Object { @{ id = $_.id; name = $_.name; plane = $_.plane; recommendation = $_.recommendation; articleRef = $_.articleRef } })

    # v3.11: needsEscalation era SIEMPRE $true, y con eso ninguna corrida podia salir con
    # status 'resolved'. $residual toma cualquier check en warn con plano 'fudo_config', y la
    # capa 5 agrega cuatro (fudo.printerRegistered, fudo.printerKitchen, fudo.categoryKitchen,
    # fudo.rooms) que nacen en 'warn' por construccion: no se pueden verificar desde la PC del
    # cliente, hacen falta la web app de Fudo o su backend. Lo que se vio en la planilla fueron
    # 5 filas con resolved=true y status=needs_escalation a la vez: la columna "resuelto"
    # sumaba, el asesor leia ESCALAR en pantalla, y el bloque "que resolvio" -que mira status-
    # quedaba vacio desde el dia uno del proyecto.
    # Ahora hay una sola fuente de verdad: si el caso cerro, no se escala, y el status se
    # decide aca y no en tres lugares distintos. $residual sigue viajando por lo que es: la
    # lista informativa de lo que igual conviene revisar en Fudo.
    $needsEscalation = (-not $resolved)
    $status = $(if ($resolved) { 'resolved' }
                elseif (@($script:Errors).Count -gt 0) { 'partial_engine_error' }
                else { 'needs_escalation' })

    $diag = [ordered]@{
        resolved        = $resolved
        # Unico lugar donde se decide el status del caso. La telemetria, el historial local y
        # el codigo de salida lo leen de aca.
        status          = $status
        # Salio el papel de la prueba fisica, aunque el caso no cierre. Distingue "no imprime
        # nada" de "imprime, pero la comanda de Fudo todavia no sale".
        paperOk         = $paperOk
        # El historial del spooler esta disponible y no muestra ni una comanda de Fudo. No
        # impide cerrar (es config del backend de Fudo, fuera del alcance del motor) pero hay
        # que decirlo: es el tramo que queda por confirmar despues de que el papel salga.
        fudoSinUso      = [bool](@($fudoSinUso).Count -gt 0)
        # Los estados posibles del ultimo tramo, sin ambiguedad:
        #   con_comandas   - el historial muestra comandas de Fudo
        #   sin_comandas   - el historial esta disponible, con nombres utiles, y no hay ninguna
        #   no_atribuible  - hay historial pero no identifica que programa imprimio (v3.15)
        #   sin_datos      - no hay historial (log recien habilitado, apagado, o sin evaluar)
        fudoUsoEstado   = [string]$fudoUsoEstado
        # Un cierre que no pudo verificar el tramo de Fudo. Es el dato que hacia falta para
        # que la metrica de cierre no cuente humo: cerro porque la impresora imprime, pero
        # nadie pudo confirmar que la comanda de Fudo llegue.
        # v3.15: 'no_atribuible' entra aca. Un cierre con historial que no identifica quien
        # imprimio no verifico el tramo de Fudo, igual que uno sin historial.
        cierreSinVerificarFudo = [bool]($resolved -and $fudoUsoEstado -in @('sin_datos','no_atribuible'))
        rootCause       = $rootCause
        # v3.13: el id y el texto de la causa salian de fuentes distintas. Cuando el caso
        # cerraba, el texto se armaba con la reparacion de menor capa ($fixed) pero el id se
        # tomaba de $ordered -los candidatos en fail/warn-, asi que se vio una fila con
        # rootCauseCheckId = 'hw.notInstalled' y causa 'Puerto USB desmapeado' (que es
        # conn.usb), y con eso la categoria salio de un check que no era la causa. Si cerro,
        # manda $fixed; el id y el texto tienen que describir lo mismo.
        rootCauseCheckId = $(if ($resolved) {
                                  if (@($fixed).Count -gt 0) { [string](@($fixed | Sort-Object { $_.layer })[0].id) }
                                  else { 'ok.yaFuncionaba' }
                              }
                              elseif (@($ordered).Count -gt 0) { [string]$ordered[0].id }
                              else { [string]$rootCheckId })
        confidence      = $confidence
        autoFixesApplied = @($fixed | ForEach-Object { $_.name })
        residualEscalation = $residual
        needsEscalation = $needsEscalation
        engineErrorCount = @($script:Errors).Count
    }
    $diag['nextActions'] = @(Get-NextActions -Diag $diag)
    return $diag
}

function Get-NextActions {
    <#
      Lista ordenada y accionable para el agente/asesor: que hacer, quien lo hace y con que articulo.
      owner: motor = ya lo intento el script | asesor = accion en la web app de Fudo |
             cliente = accion fisica en el local | tecnico = service de hardware
    #>
    param($Diag)
    $out = @()
    $pending = @($script:Checks | Where-Object { $_.status -in @('fail','warn') } | Sort-Object { $_.layer })
    foreach ($c in $pending) {
        if (-not $c.recommendation) { continue }
        # owner: quien tiene que hacer la accion. cliente = en el local (cable, AV, impresora);
        # asesor = en la PC o en la web app de Fudo; soporte = Soporte Producto.
        $owner = switch ([string]$c.plane) {
            'fudo_config' { 'asesor' }
            'hardware'    { 'cliente' }
            default       { 'asesor' }
        }
        $out += [ordered]@{
            priority   = (@($out).Count + 1)
            checkId    = [string]$c.id
            layer      = $c.layer
            status     = [string]$c.status
            what       = [string]$c.name
            do         = [string]$c.recommendation
            owner      = $owner
            articleRef = [string]$c.articleRef
        }
    }
    $enRed = @()
    if ($script:Diagnostics.Contains('impresorasEnRed')) { $enRed = @($script:Diagnostics['impresorasEnRed'] | Where-Object { $_.respondeEscPos }) }
    if (@($enRed).Count -gt 0) {
        $out += [ordered]@{
            priority   = (@($out).Count + 1)
            checkId    = 'conn.net.ip'
            layer      = 3
            status     = 'info'
            what       = ('Impresora(s) de red detectada(s): ' + (@($enRed | ForEach-Object { $_.ip + ':' + $_.puerto }) -join ', '))
            do         = ('Cargar esta IP en Fudo (Administracion > Impresoras > Directo Ethernet, puerto ' + [string]@($enRed)[0].puerto + '): ' + [string]@($enRed)[0].ip + '. Si en cambio se quiere usar como impresora del sistema operativo, instalar primero la cola en Windows.')
            owner      = 'asesor'
            articleRef = 'https://soporte.fu.do/es/articles/11730816'
        }
    }

    if (@($script:Errors).Count -gt 0) {
        foreach ($e in @($script:Errors)) {
            $out += [ordered]@{
                priority   = (@($out).Count + 1)
                checkId    = ('engine.' + [string]$e.step)
                layer      = 9
                status     = 'engine_error'
                what       = ("Falla interna del motor en la etapa '" + [string]$e.step + "': " + [string]$e.message)
                do         = $(if ($e.hint) { [string]$e.hint } else { 'Adjuntar el JSON completo al escalamiento a Soporte Producto.' })
                owner      = 'soporte'
                articleRef = ''
            }
        }
    }
    if (@($out).Count -eq 0 -and -not $Diag.resolved) {
        $out += [ordered]@{
            priority = 1; checkId = 'none'; layer = 9; status = 'inconclusive'
            what = 'El motor no encontro nada roto en Windows y no pudo concluir.'
            do   = 'Reintentar con parametros explicitos: -PrinterName "<nombre exacto en Windows>" y, si es Ethernet, -PrinterIp <ip> -Interface Ethernet. Si sigue igual, revisar el plano de config de Fudo (impresora registrada, cocina/area, salas).'
            owner = 'asesor'; articleRef = 'https://soporte.fu.do/es/articles/11730815'
        }
    }
    return $out
}

# Categoria por id de chequeo. La categoria se derivaba de un regex sobre el TEXTO de la causa,
# y el texto lo escribe cada check para el asesor: 'App Nativa de Fudo NO instalada' caia en el
# regex 'no instalada' -> os.driver_faltante. En la planilla del 02/09 el mismo id
# nativa.installed aparecia repartido en 4 categorias (nativa.install x12, nativa.antivirus x5,
# os.driver_faltante x4, os.usb_port x2), asi que la tabla CAUSA del dashboard no era agregable.
# Solo entran aca los ids cuya categoria es inequivoca. Los que dependen del hallazgo concreto
# (printer.exists, que puede ser 'no hay impresora real' o 'solo hay virtuales') siguen
# resolviendose por el texto, mas abajo.
$script:CategoryByCheckId = @{
    'nativa.installed'          = 'nativa.install'
    'nativa.sinFirmar'          = 'nativa.install'
    'nativa.hostRegistrado'     = 'nativa.sin_registrar'
    'fudo.extension'            = 'nativa.sin_extension'
    'nativa.defenderQuarantine' = 'nativa.antivirus'
    'nativa.defenderExclusion'  = 'nativa.antivirus'
    'nativa.thirdPartyAV'       = 'nativa.antivirus_3p'
    'env.spooler'               = 'os.spooler'
    'queue.health'              = 'os.queue'
    'queue.otherBacklog'        = 'os.queue'
    'conn.usb'                  = 'os.usb_port'
    'hw.noPortBound'            = 'os.usb_port'
    'conn.net'                  = 'net.ip'
    'conn.otherSubnet'          = 'net.otra_subred'
    'hw.deviceConnected'        = 'hardware.no_conectada'
    'hw.disconnected'           = 'hardware.desconectada'
    'printer.disconnected'      = 'hardware.desconectada'
    'hw.notInstalled'           = 'os.driver_faltante'
    'hw.directoUsb'             = 'hardware.directo_usb'
    'hw.testprint'              = 'hardware.no_imprime'
    'ok.yaFuncionaba'           = 'ok.ya_funcionaba'
    'repair.pendingConfirm'     = 'repair.pendiente_confirmar'
    'fudo.configProbable'       = 'fudo_config'
    'engine.inconclusive'       = 'unknown'
    'engine.fatal'              = 'engine_error'
}
function Get-Category {
    param($Diag)
    # Categorizacion para telemetria: permite agrupar los casos por causa
    # v3.11: una PC que ya estaba sana y donde el ticket salio bien ahora cierra. Sin este caso
    # la causa ("...salio sin necesidad de reparar nada") caia en el regex de 'fisic' y se
    # contaba como un problema de hardware.
    if ([bool]$Diag.resolved -and @($Diag.autoFixesApplied).Count -eq 0) { return 'ok.ya_funcionaba' }
    # v3.12: primero el id de la causa. El texto de la causa es para el asesor y cambia con
    # cada redaccion; el id no.
    $rcid = [string]$Diag.rootCauseCheckId
    if ($rcid) {
        if ($script:CategoryByCheckId.ContainsKey($rcid)) { return [string]$script:CategoryByCheckId[$rcid] }
        if ($rcid.StartsWith('fudo.')) { return 'fudo_config' }
    }
    $rc = [string]$Diag.rootCause
    switch -Regex ($rc) {
        'DESCONECTADA|esta desconectada|sin dispositivo' { return 'hardware.desconectada' }
        'no esta respondiendo|quedo en la cola' { return 'hardware' }
        'Ninguna impresora fisica|no conectada|Administrador de dispositivos|sin hardware detectado' { return 'hardware.no_conectada' }
        'virtual' { return 'os.impresora_virtual' }
        'sin driver|driver generico|no instalada|cola de prueba|driver instalado' { return 'os.driver_faltante' }
        'cuarentena|Defender|antivirus|Antivirus' { return 'nativa.antivirus' }
        'Nativa|nativa'      { return 'nativa.install' }
        'Spooler'            { return 'os.spooler' }
        'cola'               { return 'os.queue' }
        'offline|pausada'    { return 'os.printer_state' }
        'USB|puerto'         { return 'os.usb_port' }
        'red|Ethernet|9100|IP' { return 'net.ip' }
        'terceros'           { return 'nativa.antivirus_3p' }
        'registrada|agregar|Cocina|Area|sala|config' { return 'fudo_config' }
        'blanco|feed|cable|fisic|Hardware|hardware' { return 'hardware' }
        default              { return 'unknown' }
    }
}

function Format-Wrap {
    <# Envuelve texto a $Width columnas con sangria, para que la consola sea legible. #>
    param([string]$Text, [int]$Width = 74, [string]$Indent = '       ')
    $words = @(($Text -replace '\s+', ' ').Trim() -split ' ')
    $out = @(); $cur = ''
    foreach ($w in $words) {
        if ($cur -and (($cur.Length + 1 + $w.Length) -gt $Width)) { $out += $cur; $cur = $w }
        elseif ($cur) { $cur = "$cur $w" }
        else { $cur = $w }
    }
    if ($cur) { $out += $cur }
    $res = @()
    for ($k = 0; $k -lt @($out).Count; $k++) {
        if ($k -eq 0) { $res += $out[$k] } else { $res += ($Indent + $out[$k]) }
    }
    return @($res)
}

function Get-AreaStatus {
    <# Colapsa varios checks en un semaforo por area: FALLA > REVISAR > REPARADO > OK > - #>
    param([string[]]$Ids)
    $mine = @($script:Checks | Where-Object {
        $id = [string]$_.id
        $hit = $false
        foreach ($pfx in $Ids) { if ($id -eq $pfx -or $id.StartsWith($pfx)) { $hit = $true; break } }
        $hit
    })
    if (@($mine).Count -eq 0) { return '-' }
    if (@($mine | Where-Object { $_.status -eq 'fail' }).Count  -gt 0) { return 'FALLA' }
    if (@($mine | Where-Object { $_.status -eq 'warn' }).Count  -gt 0) { return 'REVISAR' }
    if (@($mine | Where-Object { $_.status -eq 'fixed' }).Count -gt 0) { return 'REPARADO' }
    if (@($mine | Where-Object { $_.status -eq 'ok' }).Count    -gt 0) { return 'OK' }
    if (@($mine | Where-Object { $_.status -eq 'skipped' }).Count -gt 0) { return 'omitido' }
    return '-'
}

function Get-ShortActions {
    <#
      Acciones para la consola: colapsa los 4 checks genericos de config de Fudo en una sola
      linea y devuelve como maximo $Max, con el resto contabilizado.
    #>
    param($Diag, [int]$Max = 3)
    $acts = @($Diag.nextActions)
    $fudo = @($acts | Where-Object { ([string]$_.checkId).StartsWith('fudo.') })
    $rest = @($acts | Where-Object { -not ([string]$_.checkId).StartsWith('fudo.') })
    $list = @()
    foreach ($a in $rest) {
        $list += [ordered]@{ owner = [string]$a.owner; text = [string]$a.do; ref = [string]$a.articleRef }
    }
    if (@($fudo).Count -ge 2) {
        $list += [ordered]@{
            owner = 'asesor'
            text  = 'Verificar en la web app de Fudo: impresora registrada con la interfaz correcta, cocina/area asignada a la impresora, categorias con cocina, y salas tildadas si el local usa salas.'
            ref   = 'https://soporte.fu.do/es/articles/11730815'
        }
    } elseif (@($fudo).Count -eq 1) {
        $list += [ordered]@{ owner = 'asesor'; text = [string]@($fudo)[0].do; ref = [string]@($fudo)[0].articleRef }
    }
    return [ordered]@{ shown = @($list | Select-Object -First $Max); total = @($list).Count }
}

function Build-HumanSummarySafe {
    <#
      El resumen en pantalla es PRESENTACION: si su armado se cae, el diagnostico ya esta
      calculado y no hay ninguna razon para perderlo. v3.15: una llamada a una funcion que no
      existia en produccion hizo abortar la corrida completa en engine_error y el asesor se
      quedo sin nada. Ahora un fallo del armado queda registrado como error del motor y se
      devuelve un resumen crudo con lo minimo: resultado, causa y que hacer.
    #>
    param($Diag, $DetectedInterface)
    try {
        return (Build-HumanSummary -Diag $Diag -DetectedInterface $DetectedInterface)
    } catch {
        $msg = [string]$_.Exception.Message
        $tipo = ''
        try { $tipo = [string]$_.Exception.GetType().FullName } catch {}
        $at = ''
        try { $at = "linea {0}: {1}" -f $_.InvocationInfo.ScriptLineNumber, ([string]$_.InvocationInfo.Line).Trim() } catch {}
        Add-EngineError -Step 'summary.build' -Message $msg -Type $tipo -At $at `
            -Hint 'Fallo el armado del resumen en pantalla, no el diagnostico. El JSON de la corrida esta completo: adjuntarlo al escalamiento.'
        $l = New-Object System.Collections.ArrayList
        [void]$l.Add('=' * 78)
        [void]$l.Add("  FUDO PRINT DOCTOR   v$($script:SchemaVersion)   PC: $env:COMPUTERNAME")
        [void]$l.Add('=' * 78)
        [void]$l.Add('')
        [void]$l.Add('  El resumen en pantalla no se pudo armar, pero el diagnostico SI se completo.')
        [void]$l.Add('')
        [void]$l.Add('  RESULTADO    ' + $(if ($Diag -and $Diag.resolved) { 'RESUELTO' } else { 'NO RESUELTO AUTOMATICAMENTE' }))
        [void]$l.Add('  CAUSA        ' + [string]$(if ($Diag -and $Diag.rootCause) { $Diag.rootCause } else { 'sin determinar' }))
        if ($Diag -and @($Diag.nextActions).Count -gt 0) {
            [void]$l.Add('')
            [void]$l.Add('  QUE HACER AHORA')
            $i = 0
            foreach ($a in @($Diag.nextActions)) {
                $i++
                if ($i -gt 3) { break }
                [void]$l.Add(('    ' + $i + '. [' + [string]$a.owner + '] ' + [string]$a.do))
            }
        }
        [void]$l.Add('')
        [void]$l.Add('  El detalle completo esta en el JSON de la corrida (resultado.json).')
        [void]$l.Add('=' * 78)
        return (($l -join "`r`n") + "`r`n")
    }
}

function Build-HumanSummary {
    <# Resumen corto para humanos. El detalle completo vive en el JSON. #>
    param($Diag, $DetectedInterface)
    $L = New-Object System.Collections.ArrayList
    function Add-Line { param([string]$T = '') [void]$L.Add($T) }
    # Campo con etiqueta en columna: la primera linea lleva la etiqueta y las de continuacion
    # quedan alineadas debajo del texto, no debajo de la etiqueta.
    function Add-Field {
        param([string]$Label, [string]$Text, [int]$Col = 13)
        $sangria = ' ' * $Col
        $lineas = @(Format-Wrap -Text $Text -Width (76 - $Col) -Indent $sangria)
        if (@($lineas).Count -eq 0) { return }
        $etiqueta = $Label + (' ' * [Math]::Max(1, $Col - $Label.Length))
        Add-Line ('  ' + $etiqueta + $lineas[0])
        for ($i = 1; $i -lt @($lineas).Count; $i++) { Add-Line ('  ' + $lineas[$i]) }
    }

    $bar = '=' * 78
    Add-Line $bar
    Add-Line ("  FUDO PRINT DOCTOR   v$($script:SchemaVersion)   PC: $env:COMPUTERNAME" +
              $(if ($CaseId) { "   Caso: $CaseId" } else { '' }))
    Add-Line ("  Revisado: " + $(switch ([string]$script:RunMode) { 'USB' { 'solo USB' } 'Red' { 'solo red' } default { 'USB y red' } }) +
              "   Interfaz: $DetectedInterface" +
              "   " + $(if ($DryRun) { 'solo diagnostico (-DryRun)' } elseif ($AutoFix) { 'diagnostico + reparacion' } else { 'solo diagnostico' }))
    Add-Line $bar

    if ($script:UpdateNote) {
        Add-Line ''
        Add-Line ('  * ' + $script:UpdateNote)
    }

    # --- colas de Windows (lo primero que hay que entender: que impresoras hay configuradas)
    $colas = @()
    if ($script:Diagnostics.Contains('colas')) { $colas = @($script:Diagnostics['colas']) }
    if (@($colas).Count -gt 0) {
        Add-Line ''
        Add-Line ("  IMPRESORAS INSTALADAS EN WINDOWS: " + @($colas).Count)
        foreach ($c in $colas) {
            $marca = $(if ([int]$c.score -gt 0) { '  >>' } else { '    ' })
            $etiqueta = switch ([string]$c.estado) {
                'no imprime'    { 'NO IMPRIME' }
                'con problemas' { 'con problemas' }
                default         { 'funcionando -- no se toca' }
            }
            Add-Line ($marca + ' ' + [string]$c.nombre + $(if ($c.puerto) { "  [$($c.puerto)]" } else { '' }) + '  ' + $etiqueta)
            foreach ($sin in @($c.sintomas)) {
                foreach ($ln in @(Format-Wrap -Text $sin -Width 64 -Indent '           ')) { Add-Line ('         - ' + $ln) }
            }
        }
    }

    # --- hardware fisico detectado
    # En modo Red no se revisa el hardware USB, asi que listarlo (y sobre todo listar las
    # "desconectadas") contradice el propio semaforo y manda al asesor a perseguir un cable
    # que no tiene nada que ver con la impresora que esta diagnosticando.
    $conn = @()
    if ($script:Diagnostics.Contains('printersConnected')) { $conn = @($script:Diagnostics['printersConnected']) }
    $modoRed = ($script:RunMode -eq 'Red')
    if ($modoRed) {
        $colasRed = @($colas | Where-Object { Test-IsNetworkPort -PortName ([string]$_.puerto) })
        Add-Line ''
        Add-Line ("  IMPRESORAS DE RED: " + @($colasRed).Count)
        foreach ($cr in $colasRed) {
            Add-Line ('    - ' + [string]$cr.nombre + '  [' + [string]$cr.puerto + ']  ' + [string]$cr.estado)
        }
        if (@($colasRed).Count -eq 0) {
            Add-Line '    (ninguna instalada en Windows con puerto de red)'
        }
        Add-Line '    (el hardware USB no se revisa en este modo)'
    }
    $desc = @()
    if ($script:Diagnostics.Contains('descartadosNoImpresora')) { $desc = @($script:Diagnostics['descartadosNoImpresora']) }
    if (-not $modoRed) {
    Add-Line ''
    Add-Line ("  HARDWARE DE IMPRESION CONECTADO: " + @($conn).Count)
    if (@($conn).Count -eq 0) {
        Add-Line '    (ninguna: Windows no ve hardware de impresion conectado)'
    } else {
        foreach ($c in $conn) {
            $cola = [string]$c.colaWindows
            $nombre = $(if ($cola) { $cola } else { [string]$c.nombre })
            $donde = $(if ($c.puerto) { [string]$c.puerto } else { 'sin puerto asignado' })
            $nota = $(if ($cola) { '' } else { '  -- sin cola en Windows' })
            Add-Line ("    - $donde : $nombre$nota")
            if ($cola -and [string]$c.nombre -and ([string]$c.nombre -ne $cola)) {
                Add-Line ("        equipo: " + [string]$c.nombre)
            }
            if ($c.certeza -and $c.certeza -ne 'alta') {
                Add-Line ("        deteccion: " + [string]$c.deteccion + " (certeza $($c.certeza))")
            }
            if ($c.driverSugerido -eq 'oem_recomendado') {
                Add-Line ("        driver: tiene driver propio de $($c.marca); el generico de texto igual alcanza")
            } elseif ($c.driverSugerido -eq 'oem_instalado') {
                Add-Line ("        driver: usa el de $($c.marca) ya instalado ($($c.driverNombre))")
            }
        }
    }

    if (@($desc).Count -gt 0) {
        Add-Line ("    (se descartaron " + @($desc).Count + " dispositivos USB que no son impresoras: mouse, hubs, etc.)")
    }
    $off = @()
    if ($script:Diagnostics.Contains('impresorasDesconectadas')) { $off = @($script:Diagnostics['impresorasDesconectadas']) }
    if (@($off).Count -gt 0) {
        Add-Line ''
        Add-Line ("  DESCONECTADAS (instaladas en Windows, sin hardware presente): " + @($off).Count)
        foreach ($o in $off) {
            $ext = ''
            if ($o.colaWindows -and ([string]$o.colaWindows -ne [string]$o.nombre)) { $ext = "  (es la cola '$($o.colaWindows)')" }
            Add-Line ("    - " + [string]$o.nombre + $(if ($o.puerto) { "  [estaba en $($o.puerto)]" } else { '' }) + $ext)
        }
        Add-Line '      -> encender la impresora y conectar el USB, preferentemente en el mismo puerto'
    }
    }

    # Corte por modo: el resumen tiene que decir por que no hay diagnostico, o el asesor lee
    # una pantalla vacia y cree que el motor fallo.
    if ($script:AbortByMode) {
        # v3.15: aca vivia una llamada a Get-CheckById, que solo existe DENTRO de Invoke-SelfTest.
        # En la PC del cliente la funcion no esta en scope: el resumen tiraba
        # CommandNotFoundException y la corrida entera terminaba en engine_error con el
        # diagnostico ya calculado y sin mostrarlo (6 minutos de trabajo, 12 checks, cero
        # diagnostico para el asesor). El self-test no lo veia porque ahi la funcion SI existe.
        # Lookup directo sobre la coleccion de checks, que es lo que hace el resto del motor.
        $mf = @($script:Checks | Where-Object { $_.id -eq 'printer.modeFilter' }) | Select-Object -First 1
        Add-Line ''
        Add-Line ('  NO SE REVISO NADA: no hay impresoras ' + $(if ($script:RunMode -eq 'Red') { 'de red' } else { 'por USB' }) + ' en esta PC')
        if ($mf -and $mf.evidence -and $mf.evidence.instaladas) {
            Add-Line ''
            Add-Line '  Lo que si hay instalado (no se toco):'
            foreach ($i in @($mf.evidence.instaladas)) { Add-Line ('    - ' + [string]$i) }
        }
        Add-Line ''
        Add-Line '  QUE HACER AHORA'
        Add-Line '    1. [asesor] Si la comandera del cliente es alguna de esas, volve a correr'
        Add-Line '           el diagnostico y eligi la opcion que corresponda (o "ambas").'
        Add-Line ''
        Add-Line $bar
        return (($L -join "`r`n") + "`r`n")
    }

    # v3.16: la instruccion unica para el caso de la impresora en otra subred. Va antes de los
    # chequeos porque es lo que el asesor tiene que hacer, y con los valores ya resueltos: sin
    # esto la informacion existe pero repartida en el JSON, y averiguarla a mano es el rato que
    # se le queria ahorrar.
    if ($script:Diagnostics.Contains('planRedImpresora')) {
        $pl = $script:Diagnostics['planRedImpresora']
        if ($pl -and [bool]$pl.hay) {
            Add-Line ''
            Add-Line '  IMPRESORA DE RED EN OTRA SUBRED'
            Add-Field -Label 'ESTA EN' -Text ([string]$pl.ip + $(if ($pl.marca) { '   marca: ' + [string]$pl.marca } else { '' }) + $(if ($pl.mac) { '   MAC: ' + [string]$pl.mac } else { '' }))
            if ($pl.ipSugerida) {
                Add-Field -Label 'PONERLE' -Text ('IP ' + [string]$pl.ipSugerida + '   mascara ' + [string]$pl.mascara +
                                                  $(if ($pl.gateway) { '   gateway ' + [string]$pl.gateway } else { '' }) + '  (esa IP se probo y esta libre)')
            }
            if ($pl.herramienta) {
                Add-Field -Label 'CON' -Text $(if ([bool]$pl.herramienta.encontrada) { [string]$pl.herramienta.ruta } else { [string]$pl.herramienta.exe + ' (no esta en esta PC: viene con Delitools)' })
            }
            Add-Field -Label 'DESPUES' -Text 'volver a correr el diagnostico: el motor verifica la IP nueva y apunta la cola de Windows ahi.'
        }
    }

    # --- semaforo por area
    Add-Line ''
    Add-Line '  CHEQUEOS'
    $areas = @(
        @{ t = 'Windows / spooler';       ids = @('env.','args.') },
        @{ t = 'App Nativa + antivirus';  ids = @('nativa.') },
        @{ t = 'Hardware conectado';      ids = @('hw.deviceConnected','hw.driverMissing','hw.notInstalled','hw.driverPlan') },
        @{ t = 'Instalada en Windows';    ids = @('printer.') },
        @{ t = 'Cola de trabajos';        ids = @('queue.') },
        @{ t = 'Conexion USB / red';      ids = @('conn.') },
        @{ t = 'Prueba de impresion';     ids = @('hw.testprint') },
        @{ t = 'Configuracion de Fudo';   ids = @('fudo.') },
        @{ t = 'Motor (fallas internas)'; ids = @('engine.') }
    )
    # Un simbolo fijo al principio de cada linea: se barre la columna de un vistazo y se ve
    # donde esta el problema sin leer todo. Antes el estado iba al final, despues de una fila
    # de puntos de largo variable, y habia que recorrer la linea entera para encontrarlo.
    foreach ($a in $areas) {
        $st = Get-AreaStatus -Ids $a.ids
        if ($st -eq '-' -and $a.t -eq 'Motor (fallas internas)') { continue }
        $sim = switch ($st) {
            'FALLA'    { '[X]' }
            'REVISAR'  { '[!]' }
            'REPARADO' { '[+]' }
            'OK'       { '[ok]' }
            'omitido'  { '[-]' }
            default    { '[-]' }
        }
        $nota = switch ($st) {
            'FALLA'    { 'falla' }
            'REVISAR'  { 'revisar' }
            'REPARADO' { 'reparado' }
            'OK'       { 'ok' }
            'omitido'  { 'no se reviso' }
            default    { 'no aplica' }
        }
        $pad = ' ' * [Math]::Max(1, 5 - $sim.Length)
        $dots = '.' * [Math]::Max(3, (32 - ([string]$a.t).Length))
        Add-Line ('    ' + $sim + $pad + $a.t + ' ' + $dots + ' ' + $nota)
    }

    # --- resultado
    # El veredicto es lo unico que el asesor tiene que leer si o si: va separado del resto por
    # una linea propia y con las etiquetas alineadas en columna, para que se lea como una ficha
    # y no como un parrafo mas.
    $conf = switch ([string]$Diag.confidence) { 'high' { 'alta' } 'medium' { 'media' } default { 'baja' } }
    Add-Line ''
    Add-Line ('  ' + ('-' * 76))
    $target = ''
    if ($script:Diagnostics.Contains('printer')) { $target = [string]$script:Diagnostics['printer'].name }
    if ($Diag.resolved) { Add-Line ("  RESULTADO    RESUELTO                    (confianza $conf)") }
    else { Add-Line ("  RESULTADO    NO RESUELTO AUTOMATICAMENTE  (confianza $conf)") }
    if ($target) { Add-Line ("  IMPRESORA    $target") }
    Add-Field -Label 'CAUSA' -Text ([string]$Diag.rootCause)
    # El caso cierra porque la impresora imprime, que es lo que este motor arregla. Pero si el
    # historial de Windows no muestra ni una comanda de Fudo, falta el ultimo tramo y el asesor
    # tiene que saberlo antes de dar el caso por terminado con el cliente.
    if ($Diag.resolved -and $Diag.fudoSinUso) {
        Add-Field -Label 'FALTA' -Text ('la impresora YA IMPRIME, pero en el historial de Windows no hay ninguna comanda de Fudo todavia. ' +
                                        'Confirmar en Fudo que esta impresora este dada de alta con su cocina/area y mandar una comanda de prueba.')
    }
    # v3.13: este caso quedaba MUDO. Con el log de impresion recien habilitado no hay historial
    # que mirar, asi que el caso cerraba sin decir que el ultimo tramo no se pudo verificar.
    elseif ($Diag.resolved -and [string]$Diag.fudoUsoEstado -eq 'no_atribuible') {
        Add-Field -Label 'FALTA' -Text ('la impresora YA IMPRIME, pero el historial de Windows no dice que programa mando cada trabajo, ' +
                                        'asi que desde la PC no se puede confirmar que la comanda de Fudo llegue. Mandar una comanda desde Fudo y ver si sale el papel.')
    }
    elseif ($Diag.resolved -and [string]$Diag.fudoUsoEstado -eq 'sin_datos') {
        Add-Field -Label 'FALTA' -Text ('la impresora YA IMPRIME, pero Windows todavia no tiene historial de impresion para mirar ' +
                                        '(el registro estaba apagado y se acaba de encender). Mandar una comanda de prueba desde Fudo y volver a correr el diagnostico: ' +
                                        'recien ahi se puede confirmar que la comanda llega.')
    }
    # Salio el papel pero el caso no cierra: sin esto se lee como si no hubiera imprimido nada.
    if ($Diag.paperOk -and -not $Diag.resolved) {
        Add-Field -Label 'OJO' -Text 'la prueba SI imprimio papel; lo que falta es la cadena de Fudo'
    }
    if (@($Diag.autoFixesApplied).Count -gt 0) {
        Add-Field -Label 'SE ARREGLO' -Text ((@($Diag.autoFixesApplied) -join '; '))
    }
    Add-Line ('  ' + ('-' * 76))

    # --- que hacer ahora (maximo 3)
    $short = Get-ShortActions -Diag $Diag -Max 3
    if (@($short.shown).Count -gt 0) {
        Add-Line ''
        Add-Line '  QUE HACER AHORA'
        $n = 0
        foreach ($a in @($short.shown)) {
            $n++
            $head = "    $n. [$($a.owner)] "
            $wrapped = @(Format-Wrap -Text ([string]$a.text) -Width 68 -Indent '       ')
            Add-Line ($head + $wrapped[0])
            for ($k = 1; $k -lt @($wrapped).Count; $k++) { Add-Line ('    ' + $wrapped[$k]) }
            if ($a.ref) { Add-Line ("       ver: " + $a.ref) }
        }
        if ($short.total -gt @($short.shown).Count) {
            Add-Line ("    (+" + ($short.total - @($short.shown).Count) + " accion(es) mas en el JSON)")
        }
    }

    Add-Line ''
    Add-Line ("  Detalle: " + @($script:Checks).Count + " chequeos con evidencia en el JSON" +
              $(if (@($script:Errors).Count -gt 0) { ' | ' + @($script:Errors).Count + ' falla(s) del motor' } else { '' }))
    Add-Line $bar

    # --- detalle completo solo si se pidio -Verbose
    if ($VerbosePreference -eq 'Continue') {
        Add-Line ''
        Add-Line '  DETALLE DE CHEQUEOS'
        foreach ($c in @($script:Checks)) {
            Add-Line ("    [{0,-8}] L{1} {2}" -f [string]$c.status, $c.layer, [string]$c.name)
            if ($c.actionTaken) { Add-Line ("               accion: " + [string]$c.actionTaken) }
        }
        Add-Line $bar
    }

    return (($L -join "`r`n") + "`r`n")
}

function Write-HumanReport {
    <#
      Escribe el resumen para el humano. Si la consola es interactiva usa color;
      si la salida esta redirigida (agente) va a stderr en texto plano,
      para que stdout quede limpio con solo el JSON.
    #>
    param([string]$Text)
    $redirected = $true
    try { $redirected = [Console]::IsOutputRedirected } catch {}
    $lines = $Text -split "`r?`n"
    if ($redirected) {
        foreach ($ln in $lines) { [Console]::Error.WriteLine($ln) }
        return
    }
    # El color se decide por el simbolo de estado al principio de la linea, que lo pone
    # Build-HumanSummary, en vez de adivinar por palabras sueltas del texto. Antes casi todo
    # terminaba en gris y las lineas con la palabra "falla" adentro de una recomendacion se
    # pintaban de rojo aunque no fueran una falla.
    foreach ($ln in $lines) {
        $color = 'Gray'
        if     ($ln -match '^\s*=+$')                       { $color = 'DarkGray' }
        elseif ($ln -match '^\s*-+$')                       { $color = 'DarkGray' }
        elseif ($ln -match 'FUDO PRINT DOCTOR')             { $color = 'Cyan' }
        elseif ($ln -match '^\s{4}\[X\]')                   { $color = 'Red' }
        elseif ($ln -match '^\s{4}\[!\]')                   { $color = 'Yellow' }
        elseif ($ln -match '^\s{4}\[\+\]')                  { $color = 'Green' }
        elseif ($ln -match '^\s{4}\[ok\]')                  { $color = 'Green' }
        elseif ($ln -match '^\s{4}\[-\]')                   { $color = 'DarkGray' }
        elseif ($ln -match '^\s{2}RESULTADO\s+RESUELTO')    { $color = 'Green' }
        elseif ($ln -match '^\s{2}RESULTADO\s+NO RESUELTO') { $color = 'Red' }
        elseif ($ln -match '^\s{2}CAUSA\s')                 { $color = 'Magenta' }
        elseif ($ln -match '^\s{2}OJO\s')                   { $color = 'Yellow' }
        elseif ($ln -match '^\s{2}SE ARREGLO\s')            { $color = 'Green' }
        elseif ($ln -match '^\s{2}IMPRESORA\s')             { $color = 'White' }
        elseif ($ln -match '^\s{2}QUE HACER AHORA\s*$')     { $color = 'White' }
        elseif ($ln -match '^\s{2}[A-Z][A-Z0-9 ()/:.]+$')   { $color = 'White' }
        elseif ($ln -match 'NO IMPRIME')                    { $color = 'Red' }
        elseif ($ln -match 'con problemas')                 { $color = 'Yellow' }
        Write-Host $ln -ForegroundColor $color
    }
}

# ---------------------------------------------------------------------------
# PREFLIGHT - valida como fue invocado y avisa en lenguaje claro (no explota)
# ---------------------------------------------------------------------------
function Get-PublishedVersion {
    <#
      Version publicada en el repo. Timeout corto y silencioso: en la PC de un cliente puede no
      haber internet, y el diagnostico no depende de esto.
    #>
    param([int]$TimeoutSec = 4)
    try {
        try { [Net.ServicePointManager]::SecurityProtocol = [Net.SecurityProtocolType]::Tls12 } catch {}
        $r = Invoke-WebRequest -Uri ($script:RawBase + '/VERSION') -UseBasicParsing -TimeoutSec $TimeoutSec -ErrorAction Stop
        $v = ([string]$r.Content).Trim()
        if ($v -match '^\d+(\.\d+){1,3}$') { return $v }
    } catch {}
    return ''
}

function Test-UpdateAvailable {
    <# Deja el aviso en $script:UpdateNote si hay una version mas nueva. #>
    if ($NoUpdateCheck -or $Quiet -or $Json) { return }
    Write-StepDetail 'verificando si hay una version mas nueva'
    $pub = Get-PublishedVersion
    if (-not $pub) { return }
    try {
        if ([version]$pub -gt [version]$script:SchemaVersion) {
            $script:UpdateNote = "Hay una version mas nueva publicada: $pub (esta corriendo la $($script:SchemaVersion)). Actualizar con Actualizar-FudoPrintDoctor.cmd o bajarla de $($script:RepoUrl)"
        }
    } catch {}
}

function Test-CaseIdValido {
    <#
      El ID de conversacion de Intercom son 15 digitos (verificado contra la API: 215475776099648,
      215475776190952, 215475755436482). Se acepta tambien una URL pegada de Intercom, porque es lo
      que el asesor tiene a mano en el navegador: de ahi se extraen los 15 digitos.
      Devuelve el id normalizado, o '' si no hay ninguno valido.
    #>
    param([string]$Texto)
    $t = [string]$Texto
    if (-not $t) { return '' }
    $t = $t.Trim()
    # Un id pelado.
    if ($t -match '^\d{15}$') { return $t }
    # Una URL o un texto con el id adentro (.../conversation/215475776099648).
    $m = [regex]::Match($t, '(?<![0-9])([0-9]{15})(?![0-9])')
    if ($m.Success) { return [string]$m.Groups[1].Value }
    return ''
}

function Resolve-CaseIdObligatorio {
    <#
      El ID de conversacion pasa a ser OBLIGATORIO. Hasta la 3.13 era opcional (el launcher decia
      'Enter para omitir') y llegaba vacio a la planilla en casi todas las corridas: sin el no se
      puede cruzar una corrida con la conversacion del cliente, que es lo que permite entender que
      paso de verdad en el caso.
      Con consola: se pregunta hasta que sea valido. Sin consola (agente, -Json, -Quiet): no se
      pregunta, se corta con codigo 6, porque no hay nadie a quien preguntarle.
    #>
    param([string]$Actual)
    $id = Test-CaseIdValido -Texto $Actual
    if ($id) { return $id }
    if (-not (Test-IsInteractiveConsole)) {
        [Console]::Error.WriteLine('')
        [Console]::Error.WriteLine('  FALTA EL ID DE CONVERSACION.')
        [Console]::Error.WriteLine('  Es obligatorio: son los 15 digitos de la conversacion de Intercom.')
        [Console]::Error.WriteLine('  Pasarlo con -CaseId <15 digitos> (tambien se acepta la URL de la conversacion).')
        exit 6
    }
    for ($i = 1; $i -le 5; $i++) {
        Write-Host ''
        Write-Host '  ID de conversacion (obligatorio): son los 15 digitos de la conversacion de Intercom.' -ForegroundColor Yellow
        Write-Host '  Se puede pegar la URL de la conversacion y el motor extrae el numero.' -ForegroundColor DarkGray
        $resp = Read-DoctorLine -Prompt '  ID de conversacion: '
        $id = Test-CaseIdValido -Texto $resp
        if ($id) { return $id }
        Write-Host '  Eso no parece un ID de conversacion (hacen falta 15 digitos).' -ForegroundColor Red
    }
    Write-Host ''
    Write-Host '  Sin ID de conversacion no se puede correr el diagnostico.' -ForegroundColor Red
    Write-Host '  Buscalo en la URL de la conversacion de Intercom y volve a abrir FudoPrintDoctor.cmd.' -ForegroundColor Yellow
    exit 6
}

function Test-VersionBloqueada {
    <#
      Una corrida con motor viejo no solo da diagnosticos ya corregidos: ensucia la planilla con la
      que se decide que arreglar. El 03/09 una sola corrida 3.8 reprodujo cuatro bugs ya
      corregidos y sumo una fila a 'resueltas' con resolved+needsEscalation a la vez.
      CRITERIO: se bloquea solo cuando se CONFIRMA que hay una version mas nueva. Si no se pudo
      consultar -cliente sin internet, red del local bloqueando GitHub- NO se bloquea: eso no es
      'version vieja', es 'no se sabe', y dejaria al asesor sin herramienta justo donde mas se usa.
      Con -NoUpdateCheck no se consulta y por lo tanto no se bloquea (es un opt-out explicito, no
      un bypass silencioso: queda registrado en la telemetria).
      Devuelve $true si hay que cortar.
    #>
    if ($NoUpdateCheck) { $script:VersionCheckOmitido = $true; return $false }
    $pub = Get-PublishedVersion -TimeoutSec 8
    if (-not $pub) { $script:VersionCheckFallo = $true; return $false }
    $script:VersionPublicada = $pub
    $vieja = $false
    try { $vieja = ([version]$pub -gt [version]$script:SchemaVersion) } catch { return $false }
    if (-not $vieja) { return $false }
    $script:VersionBloqueada = $true
    [Console]::Error.WriteLine('')
    [Console]::Error.WriteLine('  ESTE MOTOR ESTA DESACTUALIZADO Y NO PUEDE CORRER.')
    [Console]::Error.WriteLine("  Version de esta copia: $($script:SchemaVersion)   |   publicada: $pub")
    [Console]::Error.WriteLine('')
    [Console]::Error.WriteLine('  Las versiones viejas dan diagnosticos que ya sabemos que estan mal, y las corridas')
    [Console]::Error.WriteLine('  que generan no sirven para mejorar el motor.')
    [Console]::Error.WriteLine('')
    [Console]::Error.WriteLine('  COMO ACTUALIZAR: cerrar esta ventana y abrir Actualizar-FudoPrintDoctor.cmd')
    [Console]::Error.WriteLine("  (esta en la misma carpeta). O bajar la ultima de $($script:RepoUrl)")
    [Console]::Error.WriteLine('')
    return $true
}
function Test-Preflight {
    $problems = @()

    if ($PSVersionTable.PSVersion.Major -lt 5) {
        $problems += "PowerShell $($PSVersionTable.PSVersion) es demasiado viejo. Se necesita Windows PowerShell 5.1+ (o PowerShell 7+)."
    }
    if ($PrinterIp -and ($PrinterIp -notmatch '^\d{1,3}(\.\d{1,3}){3}$')) {
        $problems += "-PrinterIp '$PrinterIp' no es una IPv4 valida. Formato esperado: 192.168.0.50 (se lee del self-test de la impresora: apagar, mantener FEED y encender)."
    }
    if ($Port -lt 1 -or $Port -gt 65535) {
        $problems += "-Port $Port fuera de rango. Para impresoras termicas ESC/POS usar 9100."
    }
    if ($Interface -eq 'Ethernet' -and -not $PrinterIp) {
        Add-Check -Id 'args.ethernetSinIp' -Layer 0 -Name 'Interfaz Ethernet sin -PrinterIp' -Status 'warn' `
            -Evidence @{ interface = $Interface } `
            -Recommendation 'Se pidio Ethernet sin IP: el motor va a intentar leerla del puerto de Windows. Si no la encuentra, pasar -PrinterIp <ip>.'
    }
    if ($DryRun -and $AutoFix) {
        Add-Check -Id 'args.dryRun' -Layer 0 -Name 'Modo DryRun (solo diagnostico)' -Status 'skipped' `
            -Evidence @{ dryRun = $true } `
            -Recommendation 'DryRun no aplica ninguna remediacion ni imprime ticket de prueba. Para que el motor repare, correr sin -DryRun.'
    }
    return @($problems)
}

# ---------------------------------------------------------------------------
# MAIN
# ---------------------------------------------------------------------------
function Invoke-FudoPrintDoctor {
    # Se pregunta ANTES de arrancar el diagnostico: una vez que empieza el progreso en vivo,
    # cualquier pregunta pisa la linea que se esta reescribiendo.
    $script:RunMode = Resolve-RunMode
    Write-DoctorLog -Level 'INFO' -Message "Inicio FudoPrintDoctor (AutoFix=$AutoFix, DryRun=$DryRun, Interface=$Interface, Modo=$($script:RunMode))"

    if (Test-IsInteractiveConsole) {
        Write-Host ''
        Write-Host ('  Revisando la cadena de impresion (' + $(switch ($script:RunMode) { 'USB' { 'solo USB' } 'Red' { 'solo red' } default { 'USB y red' } }) + ')...') -ForegroundColor Cyan
        Write-Host ''
    }

    $null = Invoke-Step -Name 'update.check' -Body { Test-UpdateAvailable }
    if ($script:UpdateNote) {
        Add-Check -Id 'engine.updateAvailable' -Layer 0 -Name 'Hay una version mas nueva del motor' -Status 'warn' -Plane 'os' `
            -Evidence @{ actual = $script:SchemaVersion } -Recommendation $script:UpdateNote
    }

    if ($script:NativaKit -and -not [bool]$script:NativaKit.listo) {
        Add-Check -Id 'env.nativaKit' -Layer 0 -Name 'Falta el instalador de la App Nativa firmada en esta PC' -Status 'warn' -Plane 'os' `
            -Evidence @{ motivo = [string]$script:NativaKit.motivo; versionFirmada = [string]$script:NativaVersionFirmada
                         candidatos = @(@($script:NativaKit.candidatos) | ForEach-Object { [ordered]@{ ruta = [string]$_.ruta; version = [string]$_.version } })
                         omitido = [bool]$script:NativaKitOmitido } `
            -ArticleRef 'https://soporte.fu.do/es/articles/16419361' `
            -Recommendation ('No hay un instalador de la App Nativa v' + $script:NativaVersionFirmada + ' o superior en esta PC (' + [string]$script:NativaKit.motivo + '). ' +
                             'Si este cliente tiene una version vieja, el motor no la puede actualizar y el antivirus se la va a volver a comer. ' +
                             'Copiar el .msi junto a los dos archivos que se copian a la PC del cliente: se arregla una vez y sirve para todos los casos.')
    }

    $badArgs = @(Test-Preflight)
    if (@($badArgs).Count -gt 0) {
        foreach ($b in $badArgs) {
            Add-EngineError -Step 'preflight' -Message $b -Type 'ArgumentError' -Hint 'Corregir el parametro y reintentar. Ver .EXAMPLE en la cabecera del script.'
            Add-Check -Id 'args.invalid' -Layer 0 -Name 'Parametros de invocacion invalidos' -Status 'fail' -RootCauseCandidate $false `
                -Evidence @{ problem = $b } -Recommendation $b
        }
    }

    $envOk = Invoke-Step -Name 'layer0.environment' -Body { Test-Layer0-Environment }
    $printer = $null
    $detectedInterface = 'USB'
    if ($envOk) {
        $null = Invoke-Step -Name 'layer0b.nativeApp' -Body { Test-Layer0b-NativeApp }
        $null = Invoke-Step -Name 'layer0c.staleQueues' -Body { Remove-StaleOwnQueues }
        $null = Invoke-Step -Name 'layer1a.hardwareInventory' -Body { Test-Layer1a-HardwareInventory }
        $null = Invoke-Step -Name 'layer1a.orphanOwnQueues' -Body { Remove-OrphanOwnQueues }
        $printer = Invoke-Step -Name 'layer1.resolvePrinter' -Body { Resolve-TargetPrinter }
    }

    # Si el asesor eligio un modo, no hay impresoras de ese tipo y dijo que no revisara las
    # otras, se corta aca: nada de capas 1 a 5, ninguna reparacion y ningun ticket de prueba
    # sobre una impresora que no eligio. El resumen explica por que quedo sin diagnosticar.
    if ($script:AbortByMode) {
        Write-DoctorLog -Level 'INFO' -Message ("Corte por modo " + $script:RunMode + ": no hay impresoras de ese tipo y no se pidio revisar las otras")
    }
    if ($envOk -and -not $script:AbortByMode) {
        $wmi = Invoke-Step -Name 'layer1.printerState' -Body { Test-Layer1-PrinterState -Printer $printer }
        if ($script:ReconnectedPort -and $printer) {
            $refrescada = Invoke-Step -Name 'layer1.refresh' -Body { Get-Printer -Name ([string]$printer.Name) -ErrorAction SilentlyContinue }
            if ($refrescada) { $printer = $refrescada }
        }
        $null = Invoke-Step -Name 'layer2.queue' -Body { Test-Layer2-Queue -Printer $printer -Wmi $wmi }
        $detectedInterface = Invoke-Step -Name 'layer3.detectInterface' -Body { Get-DetectedInterface -Printer $printer }
        if (-not $detectedInterface) { $detectedInterface = 'USB' }
        if ($detectedInterface -eq 'WSD') {
            $null = Invoke-Step -Name 'layer3.wsdPort' -Body { Test-Layer3-WsdPort -Printer $printer }
        } elseif ($detectedInterface -eq 'USB') {
            $null = Invoke-Step -Name 'layer3.usbPort' -Body { Test-Layer3-UsbPort -Printer $printer -Wmi $wmi }
        } else {
            $null = Invoke-Step -Name 'layer3.network' -Body { Test-Layer3-Network -Printer $printer }
        }
        $null = Invoke-Step -Name 'layer4.hardwarePrint' -Body { Test-Layer4-HardwarePrint -Printer $printer -DetectedInterface $detectedInterface }
        $null = Invoke-Step -Name 'layer5.fudoConfig' -Body { Test-Layer5-FudoConfig -DetectedInterface $detectedInterface }
    }

    # Colas temporales: SE BORRAN salvo que hayan servido para algo (una cola de prueba que
    # no imprimio solo ensucia el panel del cliente: se llegaron a ver 10 impresoras con
    # POS-80 (copy 1), (copy 2) y FUDO-TEST-* acumuladas).
    if (@($script:TestPrintersCreated).Count -gt 0) {
        $names = @($script:TestPrintersCreated)
        $pidioConservar = ($script:BoundParams -and $script:BoundParams.ContainsKey('KeepTestPrinter') -and $KeepTestPrinter)
        $sirvio = $false
        try {
            $tp = $script:Checks | Where-Object { $_.id -eq 'hw.testprint' -and $_.status -eq 'ok' } | Select-Object -First 1
            if ($tp) { $sirvio = $true }
        } catch {}
        if (-not ($pidioConservar -or $sirvio)) {
            $sobrevivieron = @()
            foreach ($n in $names) {
                for ($i = 0; $i -lt 3; $i++) {
                    try { Remove-Printer -Name $n -ErrorAction SilentlyContinue } catch {}
                    Start-Sleep -Milliseconds 400
                    $sigue = $false
                    try { $sigue = [bool](Get-Printer -Name $n -ErrorAction SilentlyContinue) } catch {}
                    if (-not $sigue) { break }
                    # Un trabajo pendiente puede impedir el borrado: se limpia y se reintenta.
                    try { Get-PrintJob -PrinterName $n -ErrorAction SilentlyContinue | Remove-PrintJob -ErrorAction SilentlyContinue } catch {}
                }
                $quedo = $false
                try { $quedo = [bool](Get-Printer -Name $n -ErrorAction SilentlyContinue) } catch {}
                if ($quedo) { $sobrevivieron += $n }
            }
            if (@($sobrevivieron).Count -gt 0) {
                Add-Check -Id 'printer.testCleanup' -Layer 1 -Name 'La cola de prueba no se pudo borrar' -Status 'fail' -Plane 'os' `
                    -Evidence @{ sobrevivieron = $sobrevivieron; intentos = 3 } `
                    -Recommendation ("No se pudo borrar " + ($sobrevivieron -join ', ') + ". Hay que borrarla a mano, porque si queda instalada la proxima corrida la va a contar como una impresora del cliente: Remove-Printer -Name '" + (@($sobrevivieron)[0]) + "'")
            } else {
                Add-Check -Id 'printer.testCleanup' -Layer 1 -Name 'Cola de prueba eliminada' -Status 'ok' `
                    -Evidence @{ removed = $names; motivo = 'no imprimio, no deja rastro en el panel del cliente' }
            }
        } else {
            Add-Check -Id 'printer.testCleanup' -Layer 1 -Name 'Cola de prueba conservada' -Status 'warn' -Plane 'os' `
                -Evidence @{ kept = $names } `
                -Recommendation ("Queda instalada la cola de prueba " + ($names -join ', ') + " porque SI imprimio: sirve como cola definitiva o como referencia del puerto correcto. Borrarla cuando se instale la definitiva: Remove-Printer -Name '" + (@($names)[0]) + "'")
        }
    }

    # Re-lectura final: el veredicto y la telemetria tienen que salir del estado en el que
    # queda la PC, no de la foto de la capa 1. Va DESPUES de limpiar las colas de prueba, para
    # que las propias del motor no entren en el conteo, y antes de decidir la causa raiz.
    # El chequeo de comandas encoladas se corre aca por lo mismo: si el motor purgo la cola
    # trabada, ya no tiene que bloquear el cierre.
    if ($envOk -and -not $script:AbortByMode) {
        $null = Invoke-Step -Name 'final.rescan'      -Body { Update-PrintInventory }
        $null = Invoke-Step -Name 'final.otherQueues' -Body { Test-Layer2-OtherQueuesBacklog -Printer $printer }
    }

    if (Test-IsInteractiveConsole) { Write-Host '' }

    $diag = Resolve-Diagnosis
    $durationMs = [int]((Get-Date) - $script:StartTime).TotalMilliseconds
    $category = Get-Category -Diag $diag

    $result = [ordered]@{
        schemaVersion = $script:SchemaVersion
        updateAvailable = [string]$script:UpdateNote
        telemetria    = $script:TelemetryStatus
        status        = [string]$diag.status
        caseId        = $CaseId
        clientId      = $ClientId
        host          = $env:COMPUTERNAME
        timestamp     = (Get-Date).ToString('o')
        interface     = $detectedInterface
        modo          = [string]$script:RunMode
        dryRun        = [bool]$DryRun
        autoFix       = [bool]$AutoFix
        printer       = $(if ($script:Diagnostics.Contains('printer')) { $script:Diagnostics['printer'] } else { $null })
        pcId          = $(Invoke-Step -Name 'env.pcid' -Body { Get-PcId })
        corrida       = $(
            $h = Invoke-Step -Name 'env.history' -Body { Get-LocalRunHistory }
            if (-not $h) { $h = [ordered]@{ corridas = 0; ultimoStatus = ''; ultimaCausa = ''; ultimaFecha = '' } }
            $nro = ([int]$h.corridas + 1)
            $st = [string]$diag.status
            $trans = 'primera'
            if ([int]$h.corridas -gt 0) {
                if ($st -eq 'resolved' -and [string]$h.ultimoStatus -ne 'resolved') { $trans = 'se_resolvio' }
                elseif ($st -ne 'resolved' -and [string]$h.ultimoStatus -eq 'resolved') { $trans = 'volvio_a_fallar' }
                elseif ($st -eq 'resolved') { $trans = 'sigue_ok' }
                else { $trans = 'sigue_fallando' }
            }
            $null = Invoke-Step -Name 'env.saveHistory' -Body { Save-LocalRunHistory -Status $st -Causa ([string]$diag.rootCause) -Corridas $nro }
            [ordered]@{
                numero = $nro
                statusAnterior = [string]$h.ultimoStatus
                causaAnterior  = [string]$h.ultimaCausa
                fechaAnterior  = [string]$h.ultimaFecha
                transicion     = $trans
            }
        )
        llegada       = $(Invoke-Step -Name 'env.scenario' -Body { Get-ArrivalScenario })
        entorno       = $(Invoke-Step -Name 'env.info' -Body { Get-EnvironmentInfo })
        nativaHuella  = $(Invoke-Step -Name 'env.nativeFingerprint' -Body { Get-FudoNativeFingerprint })
        hardware      = [ordered]@{
            devicesConnected = $(if ($script:Diagnostics.Contains('hwDevices')) { @($script:Diagnostics['hwDevices']) } else { @() })
            problemDevices   = $(if ($script:Diagnostics.Contains('hwProblemDevs')) { @($script:Diagnostics['hwProblemDevs']) } else { @() })
            printersIdentified = $(if ($script:Diagnostics.Contains('printersConnected')) { @($script:Diagnostics['printersConnected']) } else { @() })
            usbDevicesRejected = $(if ($script:Diagnostics.Contains('descartadosNoImpresora')) { @($script:Diagnostics['descartadosNoImpresora']) } else { @() })
            livePorts        = $(if ($script:Diagnostics.Contains('livePorts')) { @($script:Diagnostics['livePorts']) } else { @() })
            usbPorts         = $(if ($script:Diagnostics.Contains('usbPorts')) { @($script:Diagnostics['usbPorts']) } else { @() })
            printersFound    = $(if ($script:Diagnostics.Contains('printersFound')) { @($script:Diagnostics['printersFound']) } else { @() })
            testPrintersCreated = @($script:TestPrintersCreated)
        }
        diagnosis     = $diag
        checks        = @($script:Checks)
        actionsApplied = @($script:Actions)
        engineErrors  = @($script:Errors)
        diagnostics   = $script:Diagnostics
        telemetry     = [ordered]@{
            durationMs      = $durationMs
            checksTotal     = @($script:Checks).Count
            # Antes contaba acciones (incluidas las que no son reparaciones, como habilitar un
            # log), asi que no coincidia con la lista de autoFixesApplied.
            autoFixCount    = @($diag.autoFixesApplied).Count
            accionesCount   = @($script:Actions).Count
            resolved        = $diag.resolved
            escalated       = $diag.needsEscalation
            category        = $category
            confidence      = $diag.confidence
            engineErrors    = @($script:Errors).Count
        }
        humanSummary  = (Build-HumanSummarySafe -Diag $diag -DetectedInterface $detectedInterface)
        log           = @($script:Log)
    }
    return $result
}

# ---------------------------------------------------------------------------
# SELF-TEST: valida la logica de decision con checks sinteticos (sin Windows)
# ---------------------------------------------------------------------------
function Invoke-SelfTest {
    $pass = 0; $fail = 0
    function Assert-Eq($name, $expected, $actual) {
        if ("$expected" -eq "$actual") { Write-Host "  PASS  $name"; $script:__p++ }
        else { Write-Host "  FAIL  $name (esperado '$expected', obtenido '$actual')"; $script:__f++ }
    }
    $script:__p = 0; $script:__f = 0

    # Escenario 76 (v3.14 en campo, 03/09): el motor abortaba armando el resumen.
    # Build-HumanSummary llamaba a Get-CheckById, que solo existe DENTRO de Invoke-SelfTest: en
    # el self-test la funcion esta en scope y los 360 asserts pasaban, en la PC del cliente no
    # existe y la corrida moria en engine_error (6 minutos, 12 checks, cero diagnostico para el
    # asesor). Este bug NO se detecta ejecutando escenarios: hay que mirar el codigo.
    # Va PRIMERO, antes de que el self-test defina un solo mock: en este punto la sesion tiene
    # las funciones del motor y los cmdlets de Windows y nada mas, o sea el entorno real. Si un
    # nombre que usa una funcion del motor no resuelve aca, en la PC del cliente tampoco.
    # El escaneo pregunta si cada nombre resuelve. En PowerShell 7 estos modulos vienen de
    # Windows PowerShell por capa de compatibilidad y no siempre autocargan en una busqueda de
    # comando: se piden a mano primero, para no dar por inexistente un cmdlet que si esta.
    foreach ($mod76 in @('PrintManagement','PnpDevice','NetAdapter','NetTCPIP','Defender','ConfigDefender','Microsoft.PowerShell.Management')) {
        try { if (-not (Get-Module -Name $mod76)) { Import-Module $mod76 -ErrorAction SilentlyContinue -WarningAction SilentlyContinue | Out-Null } } catch {}
    }
    $ast76 = [System.Management.Automation.Language.Parser]::ParseFile($PSCommandPath, [ref]$null, [ref]$null)
    $esFn76 = { param($n) $n -is [System.Management.Automation.Language.FunctionDefinitionAst] }
    $esCmd76 = { param($n) $n -is [System.Management.Automation.Language.CommandAst] }
    $todas76 = @($ast76.FindAll($esFn76, $true))
    # Las funciones anidadas dentro de otra (los Add-Line / Add-Field del resumen) se evaluan
    # como parte de su contenedora, que es donde estan sus hermanas en scope.
    $anidadas76 = @()
    foreach ($f76 in $todas76) { $anidadas76 += @($f76.Body.FindAll($esFn76, $true)) }
    $huerfanas76 = @()
    foreach ($fn76 in @($todas76 | Where-Object { [string]$_.Name -ne 'Invoke-SelfTest' -and $anidadas76 -notcontains $_ })) {
        $locales76 = @($fn76.Body.FindAll($esFn76, $true) | ForEach-Object { [string]$_.Name })
        foreach ($uso76 in @($fn76.Body.FindAll($esCmd76, $true) | ForEach-Object { [string]$_.GetCommandName() } | Where-Object { $_ } | Sort-Object -Unique)) {
            if ($uso76 -in $locales76) { continue }
            if (Get-Command $uso76 -ErrorAction SilentlyContinue) { continue }
            $huerfanas76 += ([string]$fn76.Name + ' -> ' + $uso76)
        }
    }
    Assert-Eq 'S76 ninguna funcion llama a algo que no existe fuera del self-test' '' ((@($huerfanas76) | Sort-Object -Unique) -join '; ')

    function Get-CheckById { param([string]$Id) return (@($script:Checks | Where-Object { $_.id -eq $Id }) | Select-Object -First 1) }

    function Reset-State {
        $script:Checks  = New-Object System.Collections.ArrayList
        $script:Actions = New-Object System.Collections.ArrayList
        $script:Errors  = New-Object System.Collections.ArrayList
        $script:Diagnostics = [ordered]@{}
        $script:AbortByMode = $false
    }

    # Foto de las funciones que existen ANTES de que el self-test defina un solo mock: todo lo
    # que aparezca despues, o cambie de cuerpo, es un mock de un escenario.
    $script:__fnBase = @{}
    foreach ($f in @(Microsoft.PowerShell.Management\Get-ChildItem Function: -ErrorAction SilentlyContinue)) {
        $script:__fnBase[[string]$f.Name] = $f.ScriptBlock
    }

    function Reset-Mocks {
        <#
          Saca los mocks que dejaron los escenarios anteriores.
          Hace falta porque los mocks de un escenario quedan en scope para todos los que vienen
          despues, y eso ya hizo pasar tres escenarios por el motivo equivocado: uno se aprobo
          contra un mock viejo en vez de contra el codigo real (Get-PrintHistory, v3.15), otro
          contra un Repair-BindUsbPort mockeado que devolvia justo el texto esperado (v3.15), y
          un tercero se cayo porque un mock que explota a proposito seguia vivo (v3.16). Un
          escenario que pasa por el motivo equivocado es lo peor que le puede pasar a un
          self-test: se ve verde y no esta probando nada.
          Todavia NO se llama desde Reset-State: hay escenarios viejos escritos contando con que
          el mock del anterior siga vivo, y migrarlos es un trabajo aparte. Los escenarios nuevos
          lo llaman explicitamente.
          v3.19: los cmdlets van CALIFICADOS con su modulo. El escenario 92 mockea Get-ChildItem
          para probar la eleccion del instalador, y ese mock se comia el de aca: Reset-Mocks
          listaba los "archivos" del mock en vez de las funciones, no encontraba ningun mock que
          sacar, y quedaba en silencio sin hacer nada. O sea que desde el escenario 92 en adelante
          TODOS los Reset-Mocks eran decorativos y los escenarios corrian con los mocks del
          anterior -que es exactamente lo que esta funcion existe para evitar-. Se descubrio
          porque un escenario nuevo leyo '0.0.37' de un mock de 40 lineas mas arriba.
        #>
        foreach ($f in @(Microsoft.PowerShell.Management\Get-ChildItem Function: -ErrorAction SilentlyContinue)) {
            $n = [string]$f.Name
            # Ojo: Reset-Mocks se define DESPUES de la foto, asi que sin esta linea se borra a
            # si misma en la primera llamada y la segunda tira CommandNotFound.
            if ($n -eq 'Reset-Mocks') { continue }
            if (-not $n) { continue }
            $esMock = $false
            if (-not $script:__fnBase.ContainsKey($n)) { $esMock = $true }
            elseif ($script:__fnBase[$n] -ne $f.ScriptBlock) { $esMock = $true }
            if ($esMock) { try { Microsoft.PowerShell.Management\Remove-Item ('Function:\' + $n) -ErrorAction SilentlyContinue } catch {} }
        }
    }

    # Escenario 1: antivirus cuarentena resuelto + HW ok  => resuelto/high/nativa.antivirus
    Reset-State
    Add-Check -Id 'nativa.defenderQuarantine' -Layer 0 -Name 'Nativa en cuarentena de Windows Defender' -Status 'fixed' -RootCauseCandidate $true
    Add-Check -Id 'hw.testprint' -Layer 4 -Name 'Prueba fisica ESC/POS por USB (RAW)' -Status 'ok' -Plane 'hardware'
    $d = Resolve-Diagnosis
    Assert-Eq 'S1 resuelto' $true $d.resolved
    Assert-Eq 'S1 categoria' 'nativa.antivirus' (Get-Category -Diag $d)

    # Escenario 2: puerto USB reasignado + HW ok => resuelto/os.usb_port
    Reset-State
    Add-Check -Id 'conn.usb' -Layer 3 -Name 'Puerto USB desmapeado' -Status 'fixed' -RootCauseCandidate $true
    Add-Check -Id 'hw.testprint' -Layer 4 -Name 'Prueba fisica' -Status 'ok' -Plane 'hardware'
    $d = Resolve-Diagnosis
    Assert-Eq 'S2 resuelto' $true $d.resolved
    Assert-Eq 'S2 categoria' 'os.usb_port' (Get-Category -Diag $d)

    # Escenario 3 (revisado en v3.11): nada roto en OS + el papel salio. Hasta la 3.10 esto
    # NO cerraba y se escalaba a "config de Fudo", porque el criterio exigia al menos una
    # reparacion aplicada y ademas los chequeos de capa 5 -que nacen en 'warn' porque solo se
    # verifican en la web app de Fudo- forzaban el escalamiento. Con el criterio de la 3.11 la
    # impresora imprime desde Windows, que es lo que este motor arregla: el caso cierra.
    # Lo de Fudo sigue listado como lo que hay que revisar, pero ya no impide cerrar.
    Reset-State
    Add-Check -Id 'hw.testprint' -Layer 4 -Name 'Prueba fisica' -Status 'ok' -Plane 'hardware'
    Add-Check -Id 'fudo.printerKitchen' -Layer 5 -Name 'Impresora con Cocina/Area asignada' -Status 'warn' -Plane 'fudo_config'
    $d = Resolve-Diagnosis
    Assert-Eq 'S3 cierra: imprime desde Windows' $true $d.resolved
    Assert-Eq 'S3 no escala' $false $d.needsEscalation
    Assert-Eq 'S3 categoria' 'ok.ya_funcionaba' (Get-Category -Diag $d)
    Assert-Eq 'S3 pero deja lo de Fudo para revisar' 1 (@($d.residualEscalation | Where-Object { $_.id -eq 'fudo.printerKitchen' })).Count

    # Escenario 4: impresora de red inalcanzable => no resuelto, net.ip, escalado
    Reset-State
    Add-Check -Id 'conn.net' -Layer 3 -Name 'Impresora de red inalcanzable (192.168.1.50:9100)' -Status 'fail' -RootCauseCandidate $true -Plane 'fudo_config'
    $d = Resolve-Diagnosis
    Assert-Eq 'S4 resuelto=false' $false $d.resolved
    Assert-Eq 'S4 categoria' 'net.ip' (Get-Category -Diag $d)
    Assert-Eq 'S4 escalado' $true $d.needsEscalation

    # Escenario 5: se reparo algo pero NADIE confirmo que la comanda sale => NO resuelto.
    # (Antes daba resuelto solo por tener un check en 'fixed', y la CAUSA salia del nombre de
    # la reparacion: eso inflaba la columna 'resuelto' de la planilla y dejaba vacia la de
    # 'que resolvio'.)
    Reset-State
    Add-Check -Id 'env.spooler' -Layer 0 -Name 'Servicio Print Spooler' -Status 'fixed' -RootCauseCandidate $true
    $d = Resolve-Diagnosis
    Assert-Eq 'S5 reparar no es resolver' $false $d.resolved
    Assert-Eq 'S5 lo dice explicito' $true ([bool]($d.rootCause -match 'falta confirmar'))
    Assert-Eq 'S5 la causa no es la reparacion' $false ([bool]($d.rootCause -eq 'Servicio Print Spooler'))
    # Hasta la 3.11 esta rama viajaba con rootCauseCheckId VACIO (2 de las 19 corridas 3.11
    # del 02/09), y con eso la categoria caia en cualquier lado. Lo que no puede pasar sigue
    # siendo atribuirle la causa a la reparacion; el id propio dice exactamente lo que es.
    Assert-Eq 'S5 la causa no se le atribuye a la reparacion' $false ([string]$d.rootCauseCheckId -eq 'env.spooler')
    Assert-Eq 'S5 tiene id propio de rama pendiente' 'repair.pendingConfirm' ([string]$d.rootCauseCheckId)
    Assert-Eq 'S5 y su categoria' 'repair.pendiente_confirmar' (Get-Category -Diag $d)

    # Escenario 5b: la misma reparacion + un humano que confirmo el papel => resuelto/high
    Reset-State
    Add-Check -Id 'env.spooler' -Layer 0 -Name 'Servicio Print Spooler' -Status 'fixed' -RootCauseCandidate $true
    Add-Check -Id 'hw.testprint' -Layer 4 -Name 'Prueba fisica ESC/POS por USB (RAW)' -Status 'ok' -Plane 'hardware'
    $d = Resolve-Diagnosis
    Assert-Eq 'S5b con papel confirmado si resuelve' $true $d.resolved
    Assert-Eq 'S5b confianza alta' 'high' ([string]$d.confidence)
    Assert-Eq 'S5b categoria' 'os.spooler' (Get-Category -Diag $d)

    # Escenario 6 (REGRESION doble): solo impresoras virtuales y ningun device conectado
    #   a) no debe explotar (bug PropertyNotFoundStrict)
    #   b) NO debe elegir Microsoft Print to PDF como objetivo
    Reset-State
    function Get-Printer { @(
        [pscustomobject]@{ Name='Microsoft Print to PDF'; DriverName='Microsoft Print To PDF'; PortName='PORTPROMPT:' },
        [pscustomobject]@{ Name='OneNote (Desktop)'; DriverName='Send to Microsoft OneNote 16 Driver'; PortName='nul:' },
        [pscustomobject]@{ Name='Fax'; DriverName='Microsoft Shared Fax Driver'; PortName='SHRFAX:' }
    ) }
    $r6 = $null; $err6 = ''
    try { $r6 = Resolve-TargetPrinter } catch { $err6 = $_.Exception.Message }
    Assert-Eq 'S6 no explota' '' $err6
    Assert-Eq 'S6 NO elige impresora virtual' $true ($null -eq $r6)
    Assert-Eq 'S6 marca fail en printer.exists' 'fail' (Get-CheckById 'printer.exists').status
    Assert-Eq 'S6 categoria' 'os.impresora_virtual' (Get-Category -Diag (Resolve-Diagnosis))

    # Escenario 7: virtual + POS real => elige la POS real
    Reset-State
    function Get-Printer { @(
        [pscustomobject]@{ Name='Microsoft Print to PDF'; DriverName='Microsoft Print To PDF'; PortName='PORTPROMPT:' },
        [pscustomobject]@{ Name='POS-58'; DriverName='Generic / Text Only'; PortName='USB001' }
    ) }
    $r7 = $null; $err7 = ''
    try { $r7 = Resolve-TargetPrinter } catch { $err7 = $_.Exception.Message }
    Assert-Eq 'S7 no explota' '' $err7
    Assert-Eq 'S7 elige la POS' 'POS-58' $(if ($r7) { $r7.Name } else { '' })
    Assert-Eq 'S7 descarta la virtual' $true ((Get-CheckById 'printer.exists').evidence.descartadasVirtuales -contains 'Microsoft Print to PDF')

    # Escenario 8: cola con UN solo trabajo trabado (era el otro .Count escalar)
    Reset-State
    function Get-PrintJob { @([pscustomobject]@{ Id=1; JobStatus='Error'; SubmittedTime=(Get-Date).AddMinutes(-30) }) }
    $err8 = ''
    try { Test-Layer2-Queue -Printer ([pscustomobject]@{ Name='POS-58' }) -Wmi $null } catch { $err8 = $_.Exception.Message }
    Assert-Eq 'S8 cola con 1 job no explota' '' $err8

    # Escenario 9: nextActions siempre presente y accionable cuando no resolvio
    Reset-State
    Add-Check -Id 'fudo.printerKitchen' -Layer 5 -Name 'Impresora con Cocina/Area asignada' -Status 'warn' -Plane 'fudo_config' -Recommendation 'Asignar el area.'
    $d9 = Resolve-Diagnosis
    Assert-Eq 'S9 hay nextActions' $true (@($d9.nextActions).Count -gt 0)
    Assert-Eq 'S9 owner asesor' 'asesor' (@($d9.nextActions)[0].owner)

    # Escenario 10: Invoke-Step aisla una etapa que explota
    Reset-State
    $script:Errors = New-Object System.Collections.ArrayList
    $r10 = Invoke-Step -Name 'test.boom' -Body { throw 'boom sintetico' }
    Assert-Eq 'S10 devuelve null' $true ($null -eq $r10)
    Assert-Eq 'S10 registra el error' 1 (@($script:Errors).Count)
    Assert-Eq 'S10 no mata el run' 'test.boom' (@($script:Errors)[0].step)

    # Escenario 11: clasificador de impresoras virtuales vs reales
    Reset-State
    $virtuales = @(
        [pscustomobject]@{ Name='Microsoft Print to PDF'; DriverName='Microsoft Print To PDF'; PortName='PORTPROMPT:' },
        [pscustomobject]@{ Name='Microsoft XPS Document Writer'; DriverName='Microsoft XPS Document Writer v4'; PortName='XPSPort:' },
        [pscustomobject]@{ Name='OneNote (escritorio) - Impresora virtual protegida'; DriverName='Send to Microsoft OneNote 16 Driver'; PortName='nul:' },
        [pscustomobject]@{ Name='Fax'; DriverName='Microsoft Shared Fax Driver'; PortName='SHRFAX:' },
        [pscustomobject]@{ Name='Adobe PDF'; DriverName='Adobe PDF Converter'; PortName='Documents\*.pdf' }
    )
    $malClasificadas = @($virtuales | Where-Object { -not (Test-IsVirtualPrinter $_).isVirtual } | ForEach-Object { $_.Name })
    Assert-Eq 'S11 todas las virtuales detectadas' '' ($malClasificadas -join ',')
    $reales = @(
        [pscustomobject]@{ Name='3nStar RPT008'; DriverName='Generic / Text Only'; PortName='USB001' },
        [pscustomobject]@{ Name='Comandera Cocina'; DriverName='XPrinter XP-80C'; PortName='192.168.0.50:9100' },
        [pscustomobject]@{ Name='EPSON TM-T20'; DriverName='EPSON TM-T20III ReceiptE4'; PortName='ESDPRT001' }
    )
    $falsosPositivos = @($reales | Where-Object { (Test-IsVirtualPrinter $_).isVirtual } | ForEach-Object { $_.Name })
    Assert-Eq 'S11 ninguna real marcada virtual' '' ($falsosPositivos -join ',')

    # Escenario 12: no hay hardware conectado => fail de hardware, no se inventa nada
    Reset-State
    function Get-UsbPrintDevices { @() }
    function Get-ProblemPrinterDevices { @() }
    function Get-PrinterPort { @([pscustomobject]@{ Name='USB001'; Description='Puerto de impresora virtual para USB' }) }
    function Get-Printer { @([pscustomobject]@{ Name='Microsoft Print to PDF'; DriverName='Microsoft Print To PDF'; PortName='PORTPROMPT:' }) }
    $err12 = ''
    try { Test-Layer1a-HardwareInventory } catch { $err12 = $_.Exception.Message }
    Assert-Eq 'S12 inventario no explota' '' $err12
    Assert-Eq 'S12 hardware fail' 'fail' (Get-CheckById 'hw.deviceConnected').status
    Assert-Eq 'S12 es causa raiz' $true (Get-CheckById 'hw.deviceConnected').rootCauseCandidate
    Assert-Eq 'S12 categoria' 'hardware.no_conectada' (Get-Category -Diag (Resolve-Diagnosis))

    # Escenario 13: device conectado en USB001 sin cola => detecta huerfano e instala cola de prueba
    Reset-State
    function Get-UsbPrintDevices { @([ordered]@{ source='registry.USBPRINT'; name='3nStar RPT008'; instanceId='USBPRINT\3NSTAR'; portName='USB001'; status='enumerado'; problem=0 }) }
    function Get-ProblemPrinterDevices { @() }
    function Get-PrinterPort { @([pscustomobject]@{ Name='USB001'; Description='USB' }) }
    function Get-Printer { @([pscustomobject]@{ Name='Microsoft Print to PDF'; DriverName='Microsoft Print To PDF'; PortName='PORTPROMPT:' }) }
    Test-Layer1a-HardwareInventory
    Assert-Eq 'S13 device detectado' 'ok' (Get-CheckById 'hw.deviceConnected').status
    Assert-Eq 'S13 detecta no instalada' 'warn' (Get-CheckById 'hw.notInstalled').status
    function New-FudoTestPrinter { param([string]$PortName) [void]$script:TestPrintersCreated.Add('FUDO-TEST-' + $PortName); return ('FUDO-TEST-' + $PortName) }
    # Mock sensible a -Name: sin -Name devuelve solo la virtual (para que Resolve entre por el caso B)
    function Get-Printer {
        $named = ''
        for ($i = 0; $i -lt $args.Count; $i++) { if ("$($args[$i])" -eq '-Name') { $named = "$($args[$i+1])" } }
        if ($named) { @([pscustomobject]@{ Name = $named; DriverName = 'Generic / Text Only'; PortName = 'USB001' }) }
        else { @([pscustomobject]@{ Name = 'Microsoft Print to PDF'; DriverName = 'Microsoft Print To PDF'; PortName = 'PORTPROMPT:' }) }
    }
    $r13 = Resolve-TargetPrinter
    Assert-Eq 'S13 instala cola de prueba' 'FUDO-TEST-USB001' $(if ($r13) { $r13.Name } else { '' })
    Assert-Eq 'S13 check fixed' 'fixed' (Get-CheckById 'printer.exists').status

    # Escenario 14: la prueba fisica NUNCA corre sobre una impresora virtual (falso OK de hardware)
    Reset-State
    $err14 = ''
    try { Test-Layer4-HardwarePrint -Printer ([pscustomobject]@{ Name='Microsoft Print to PDF'; DriverName='Microsoft Print To PDF'; PortName='PORTPROMPT:' }) -DetectedInterface 'USB' } catch { $err14 = $_.Exception.Message }
    Assert-Eq 'S14 no explota' '' $err14
    Assert-Eq 'S14 test salteado' 'skipped' (Get-CheckById 'hw.testprint').status

    # Escenario 15: -PrinterName apuntando a una virtual => error claro, no falso OK
    Reset-State
    $script:__pn = $PrinterName
    $PrinterName = 'Microsoft Print to PDF'
    function Get-Printer { @([pscustomobject]@{ Name='Microsoft Print to PDF'; DriverName='Microsoft Print To PDF'; PortName='PORTPROMPT:' }) }
    $r15 = Resolve-TargetPrinter
    Assert-Eq 'S15 rechaza virtual explicita' $true ($null -eq $r15)
    Assert-Eq 'S15 check dedicado' 'fail' (Get-CheckById 'printer.virtualTarget').status
    $PrinterName = $script:__pn

    # Escenario 16: clasificador de dispositivos USB (el falso positivo del mouse / composite)
    Reset-State
    $noImpresoras = @(
        @{ n = 'USB Composite Device';            i = 'USB\VID_1234&PID_5678\5&1';    c = 'USB';     s = 'usbccgp'; cid = @('USB\Class_00') },
        @{ n = 'Generic USB Hub';                 i = 'USB\VID_8087&PID_0024\5&2';    c = 'USB';     s = 'usbhub';  cid = @('USB\Class_09') },
        @{ n = 'Logitech USB Optical Mouse';      i = 'USB\VID_046D&PID_C077\6&3';    c = 'HIDClass';s = 'HidUsb';  cid = @('USB\Class_03') },
        @{ n = 'Dispositivo compuesto USB';       i = 'USB\VID_0BDA&PID_0129\7&4';    c = 'USB';     s = '';        cid = @() },
        @{ n = 'Realtek USB Audio';               i = 'USB\VID_0BDA&PID_4014\8&5';    c = 'MEDIA';   s = 'usbaudio';cid = @('USB\Class_01') },
        @{ n = 'USB Mass Storage Device';         i = 'USB\VID_0781&PID_5581\9&6';    c = 'USB';     s = 'USBSTOR'; cid = @('USB\Class_08') },
        @{ n = 'Standard PS/2 Keyboard';          i = 'ACPI\PNP0303\4&7';             c = 'Keyboard';s = 'i8042prt';cid = @() },
        @{ n = 'Generic PnP Monitor';             i = 'DISPLAY\GSM5B10\5&8';          c = 'Monitor'; s = 'monitor'; cid = @() }
    )
    $falsosPos = @()
    foreach ($d in $noImpresoras) {
        $v = Test-IsPrinterDevice -Name $d.n -InstanceId $d.i -PnpClass $d.c -Service $d.s -CompatibleIds $d.cid
        if ($v.isPrinter) { $falsosPos += ($d.n + ' [' + $v.reason + ']') }
    }
    Assert-Eq 'S16 no toma mouse/hub/composite como impresora' '' ($falsosPos -join ' ; ')

    $siImpresoras = @(
        @{ n = 'EPSON TM-T20III';        i = 'USBPRINT\EPSONTM-T20III\6&1';  c = 'Printer'; s = 'usbprint'; cid = @();                 esp = 'alta' },
        @{ n = 'XP-80C';                 i = 'USB\VID_0416&PID_5011\6&2';    c = 'USB';     s = '';         cid = @('USB\Class_07');   esp = 'alta' },
        @{ n = 'Impresora termica';      i = 'USB\VID_1FC9&PID_2016\6&3';    c = 'USB';     s = '';         cid = @();                 esp = 'baja' },
        @{ n = 'Dispositivo desconocido';i = 'USB\VID_04B8&PID_0E15\6&4';    c = 'Unknown'; s = '';         cid = @();                 esp = 'media' },
        @{ n = 'BIXOLON SRP-350III';     i = 'USB\VID_1504&PID_0006\6&5';    c = 'USB';     s = '';         cid = @();                 esp = 'media' }
    )
    $falsosNeg = @(); $certezas = @()
    foreach ($d in $siImpresoras) {
        $v = Test-IsPrinterDevice -Name $d.n -InstanceId $d.i -PnpClass $d.c -Service $d.s -CompatibleIds $d.cid
        if (-not $v.isPrinter) { $falsosNeg += $d.n }
        elseif ($v.confidence -ne $d.esp) { $certezas += ($d.n + ': ' + $v.confidence + ' != ' + $d.esp) }
    }
    Assert-Eq 'S16 detecta las impresoras reales' '' ($falsosNeg -join ' ; ')
    Assert-Eq 'S16 certeza correcta por senal' '' ($certezas -join ' ; ')

    # Escenario 17: colas de Windows con nombres ambiguos (regresion del token 'POS'/'Generic')
    Reset-State
    Assert-Eq 'S17 POS-58 es POS' $true (Test-IsPosPrinter ([pscustomobject]@{ Name='POS-58'; DriverName='Generic / Text Only' }))
    Assert-Eq 'S17 comandera es POS' $true (Test-IsPosPrinter ([pscustomobject]@{ Name='Comandera Cocina'; DriverName='XPrinter XP-80C' }))
    Assert-Eq 'S17 Composite NO es POS' $false (Test-IsPosPrinter ([pscustomobject]@{ Name='USB Composite Device'; DriverName='' }))
    Assert-Eq 'S17 Generic USB Hub NO es POS' $false (Test-IsPosPrinter ([pscustomobject]@{ Name='Generic USB Hub'; DriverName='' }))

    # Escenario 18: -SkipIrreversible no aplica la purga de cola pero si el resto
    Reset-State
    $script:SkipIrreversibleBackup = $SkipIrreversible
    $SkipIrreversible = $true
    $r18a = Invoke-Remediation -Description 'purga' -Type 'queue.purge' -Target 'X' -Reversible $false -Fix { 'purgado' }
    $r18b = Invoke-Remediation -Description 'reversible' -Type 'service.start' -Target 'X' -Reversible $true -Fix { 'ok' }
    Assert-Eq 'S18 omite la irreversible' $false $r18a.applied
    Assert-Eq 'S18 aplica la reversible' $true $r18b.applied
    $SkipIrreversible = $script:SkipIrreversibleBackup

    # Escenario 19: modo agente (no interactivo) NO aplica la irreversible y la deja pendiente
    Reset-State
    $qBackup = $Quiet; $bpBackup = $script:BoundParams
    $Quiet = $true                      # fuerza no-interactivo de forma determinista
    $script:BoundParams = @{}
    $r19 = Invoke-Remediation -Description 'purga' -Type 'queue.purge' -Target 'X' -Reversible $false -Impact 'se pierden comandas' -Fix { 'purgado' }
    Assert-Eq 'S19 no aplica sin confirmacion' $false $r19.applied
    Assert-Eq 'S19 queda como pendiente' $true ([bool]($r19.note -match 'pendiente de confirmacion'))

    # Escenario 20: -AllowQueuePurge $true la aplica sin preguntar
    Reset-State
    $script:BoundParams = @{ 'AllowQueuePurge' = $true }
    $AllowQueuePurge = $true
    $r20 = Invoke-Remediation -Description 'purga' -Type 'queue.purge' -Target 'X' -Reversible $false -Fix { 'purgado' }
    Assert-Eq 'S20 aplica con flag explicito' $true $r20.applied
    $script:BoundParams = @{ 'AllowQueuePurge' = $false }
    $AllowQueuePurge = $false
    $r20b = Invoke-Remediation -Description 'purga' -Type 'queue.purge' -Target 'X' -Reversible $false -Fix { 'purgado' }
    Assert-Eq 'S20 respeta el flag en false' $false $r20b.applied
    $Quiet = $qBackup; $script:BoundParams = $bpBackup

    # Escenario 21: impresora desenchufada -> NO figura como conectada, si como desconectada
    Reset-State
    $script:PresentIdsOk = $true
    function Get-UsbPrintDevices {
        # el registro tenia la XPrinter en USB002, pero el device ya no esta presente
        $script:Diagnostics['impresorasDesconectadas'] = @(
            [ordered]@{ nombre='XPrinter XP-410B'; puerto='USB002'; instanceId='USBPRINT\XPRINTER\7&1'
                        motivo='figura instalada en el registro de Windows pero el dispositivo no esta presente' })
        return @()
    }
    function Get-ProblemPrinterDevices { @() }
    function Get-PrinterPort { @([pscustomobject]@{ Name='USB002'; Description='USB' }) }
    function Get-Printer { @([pscustomobject]@{ Name='FUDO-TEST-USB002'; DriverName='Generic / Text Only'; PortName='USB002' }) }
    Test-Layer1a-HardwareInventory
    Assert-Eq 'S21 hardware en fail' 'fail' (Get-CheckById 'hw.deviceConnected').status
    Assert-Eq 'S21 avisa que esta desconectada' $true ([bool]((Get-CheckById 'hw.disconnected') -ne $null))
    Assert-Eq 'S21 dice el puerto donde estaba' $true ([bool]((Get-CheckById 'hw.disconnected').name -match 'USB002'))
    Assert-Eq 'S21 categoria' 'hardware.desconectada' (Get-Category -Diag (Resolve-Diagnosis))

    # Escenario 22: la cola apunta a un puerto sin device -> no se toca el offline
    Reset-State
    $script:PresentIdsOk = $true
    $script:Diagnostics['livePorts'] = @()
    $script:Diagnostics['hwDeviceCount'] = 0
    Assert-Eq 'S22 puerto sin device' $false (Test-PortHasLiveDevice -PortName 'USB002')
    Assert-Eq 'S22 puerto no USB no se juzga' $true (Test-PortHasLiveDevice -PortName 'PORTPROMPT:')
    $script:Diagnostics['livePorts'] = @('USB001')
    $script:Diagnostics['hwDeviceCount'] = 1
    Assert-Eq 'S22 puerto con device' $true (Test-PortHasLiveDevice -PortName 'USB001')
    $script:PresentIdsOk = $false
    Assert-Eq 'S22 sin poder verificar no afirma' $true (Test-PortHasLiveDevice -PortName 'USB002')
    $script:PresentIdsOk = $true

    # Escenario 23: la prueba fisica no corre sobre un puerto sin hardware
    Reset-State
    $script:PresentIdsOk = $true
    $script:Diagnostics['livePorts'] = @()
    $script:Diagnostics['hwDeviceCount'] = 0
    Test-Layer4-HardwarePrint -Printer ([pscustomobject]@{ Name='FUDO-TEST-USB002'; DriverName='Generic / Text Only'; PortName='USB002' }) -DetectedInterface 'USB'
    Assert-Eq 'S23 no da falso OK de hardware' 'skipped' (Get-CheckById 'hw.testprint').status
    Assert-Eq 'S23 deja el motivo del salteo' 'puerto_sin_dispositivo' ([string](Get-CheckById 'hw.testprint').evidence.skipReason)

    # Escenario 47 (v3.7): la cola apunta a un puerto muerto pero el fierro esta en otro,
    # con una cola del cliente ahi -> la prueba se reapunta en vez de saltearse.
    Reset-State
    $script:PresentIdsOk = $true
    $script:Diagnostics['livePorts'] = @('USB001')
    $script:Diagnostics['hwDeviceCount'] = 1
    function Find-QueueForPort { param([string]$PortName) [pscustomobject]@{ Name='CAJA'; PortName=$PortName; DriverName='Microsoft Print To PDF' } }
    Test-Layer4-HardwarePrint -Printer ([pscustomobject]@{ Name='FUDO-USB003'; DriverName='Generic / Text Only'; PortName='USB003' }) -DetectedInterface 'USB'
    Assert-Eq 'S47 reapunta a la cola del cliente' 'CAJA' ([string](Get-CheckById 'hw.testprint').evidence.printer)
    Assert-Eq 'S47 no lo cuenta como puerto sin dispositivo' 'impresora_virtual' ([string](Get-CheckById 'hw.testprint').evidence.skipReason)
    # devolver la implementacion real: los escenarios que siguen dependen de ella
    function Find-QueueForPort {
        param([string]$PortName)
        $out = $null
        try {
            $out = @(Get-Printer -ErrorAction SilentlyContinue | Where-Object {
                        [string]$_.PortName -eq $PortName -and
                        -not (Test-IsVirtualPrinter $_).isVirtual -and
                        [string]$_.Name -notmatch $script:TestPrinterRx
                     })[0]
        } catch {}
        return $out
    }

    # Escenario 48 (v3.7): una causa raiz obsoleta no le gana a la reparacion que la anulo.
    Reset-State
    $script:PresentIdsOk = $true
    $script:Diagnostics['livePorts'] = @('USB001')
    $script:Diagnostics['hwDeviceCount'] = 1
    Add-Check -Id 'printer.disconnected' -Layer 1 -Name "La impresora 'FUDO-USB001' esta desconectada (puerto USB001 sin dispositivo)" `
        -Status 'fail' -RootCauseCandidate $true -Plane 'hardware' -Evidence @{ port = 'USB001' }
    Add-Check -Id 'hw.noPortBound' -Layer 1 -Name 'Puerto USB asignado y cola creada' -Status 'fixed' -RootCauseCandidate $true -Plane 'os'
    $d48 = Resolve-Diagnosis
    Assert-Eq 'S48 no usa la causa vieja' $false ([bool]([string]$d48.rootCause -match 'esta desconectada'))
    Assert-Eq 'S48 pide confirmar la comanda' $true ([bool]([string]$d48.rootCause -match 'falta confirmar'))

    # Escenario 49 (v3.7): la cola que creo el motor deja de ser un entregable cuando su puerto
    # se queda sin hardware -> se borra antes de diagnosticar, no se diagnostica a si misma.
    Reset-State
    $script:PresentIdsOk = $true
    $script:Diagnostics['livePorts'] = @('USB002')
    $script:Diagnostics['hwDeviceCount'] = 1
    $script:__borradas49 = @()
    function Get-Printer {
        @([pscustomobject]@{ Name='FUDO-USB001'; DriverName='Generic / Text Only'; PortName='USB001' },
          [pscustomobject]@{ Name='FUDO-USB002'; DriverName='Generic / Text Only'; PortName='USB002' },
          [pscustomobject]@{ Name='CAJA';        DriverName='Generic / Text Only'; PortName='USB003' })
    }
    function Get-PrintJob { param([string]$PrinterName, $ErrorAction) @() }
    function Remove-PrintJob { param($InputObject, $ErrorAction) }
    function Remove-Printer { param([string]$Name, $ErrorAction) $script:__borradas49 += $Name }
    $r49 = @(Remove-OrphanOwnQueues)
    Assert-Eq 'S49 borra la propia sin hardware' $true ([bool](@($r49) -contains 'FUDO-USB001'))
    Assert-Eq 'S49 conserva la propia que si tiene hardware' $false ([bool](@($r49) -contains 'FUDO-USB002'))
    Assert-Eq 'S49 no toca las colas del cliente' $false ([bool](@($r49) -contains 'CAJA'))
    Assert-Eq 'S49 el patron alcanza a las FUDO-USB' $true ([bool]('FUDO-USB001' -match $script:OwnQueueRx))
    Assert-Eq 'S49 el patron alcanza a las FUDO-TEST' $true ([bool]('FUDO-TEST-USB001' -match $script:OwnQueueRx))
    Assert-Eq 'S49 el patron no alcanza a una cola del cliente' $false ([bool]('FUDOCAJA' -match $script:OwnQueueRx))

    # Escenario 50 (v3.7): restaurar de cuarentena puede devolver una Nativa mas vieja
    Reset-State
    Assert-Eq 'S50 detecta el downgrade' $true  (Test-NativaDegradada -Antes '0.0.36' -Despues '0.0.18')
    Assert-Eq 'S50 misma version no es downgrade' $false (Test-NativaDegradada -Antes '0.0.36' -Despues '0.0.36')
    Assert-Eq 'S50 upgrade no es downgrade' $false (Test-NativaDegradada -Antes '0.0.18' -Despues '0.0.36')
    Assert-Eq 'S50 sin dato no afirma nada' $false (Test-NativaDegradada -Antes '' -Despues '0.0.18')
    Assert-Eq 'S50 version ilegible no afirma nada' $false (Test-NativaDegradada -Antes 'beta' -Despues '0.0.18')

    # Escenario 51 (v3.8): -PrinterName explicito que matchea una cola real no dejaba
    # $script:Diagnostics['colas'] lleno (Caso A no llamaba a Get-PrinterQueues como el Caso
    # C). La telemetria reportaba cantidadColas=0 con printer.exists=ok (43db236c6151dd8c).
    Reset-State
    $script:__pn = $PrinterName
    $PrinterName = 'CAJA'
    function Get-Printer { @([pscustomobject]@{ Name='CAJA'; DriverName='Generic / Text Only'; PortName='USB001' }) }
    function Get-CimInstance { [pscustomobject]@{ WorkOffline = $false; PrinterState = 0 } }
    function Get-PrintJob { @() }
    $r51 = Resolve-TargetPrinter
    Assert-Eq 'S51 encuentra la impresora' 'CAJA' $(if ($r51) { $r51.Name } else { '' })
    Assert-Eq 'S51 check ok' 'ok' (Get-CheckById 'printer.exists').status
    Assert-Eq 'S51 llena colas para la telemetria' 1 (@($script:Diagnostics['colas'])).Count
    Assert-Eq 'S51 la cola es la matcheada' 'CAJA' ([string]@($script:Diagnostics['colas'])[0].nombre)
    $PrinterName = $script:__pn

    # Escenario 52 (v3.9, revisado en v3.11): salio el papel pero el historial dice que Fudo
    # nunca mando una comanda. La 3.9 lo tomaba como bloqueante del cierre; la 3.11 lo saca por
    # alcance -lo que arregla el motor es que la impresora imprima en Windows; que este dada de
    # alta en Fudo vive en el backend de Fudo, no se puede verificar desde la PC y por lo tanto
    # iba a quedar pendiente siempre-. El caso cierra, con confianza 'medium' y avisando que
    # falta ese tramo.
    Reset-State
    Add-Check -Id 'conn.usb' -Layer 3 -Name 'Puerto USB desmapeado' -Status 'fixed' -RootCauseCandidate $true
    Add-Check -Id 'hw.testprint' -Layer 4 -Name 'Prueba fisica de impresion' -Status 'ok'
    Add-Check -Id 'fudo.usoReal' -Layer 5 -Name 'Ninguna cola recibio comandas de Fudo en el historial' -Status 'warn' -RootCauseCandidate $true -Plane 'fudo_config'
    $d52 = Resolve-Diagnosis
    Assert-Eq 'S52 cierra: la impresora imprime en Windows' $true ([bool]$d52.resolved)
    Assert-Eq 'S52 deja constancia de que salio el papel' $true ([bool]$d52.paperOk)
    Assert-Eq 'S52 pero no con confianza alta' 'medium' ([string]$d52.confidence)
    Assert-Eq 'S52 y marca que falta el tramo de Fudo' $true ([bool]$d52.fudoSinUso)
    Assert-Eq 'S52 no escala si cerro' $false ([bool]$d52.needsEscalation)
    # El chequeo sigue vivo: aparece en la lista de lo que el asesor tiene que revisar en Fudo.
    Assert-Eq 'S52 sigue en la lista de que revisar' 1 (@($d52.residualEscalation | Where-Object { $_.id -eq 'fudo.usoReal' })).Count

    # Escenario 52f (v3.11): la PC ya estaba sana y el ticket de prueba salio. Antes NO cerraba,
    # porque el criterio exigia al menos una reparacion aplicada: caia en "Hardware imprime OK;
    # causa probable en configuracion de Fudo" y la corrida entraba como sigue_fallando.
    Reset-State
    Add-Check -Id 'printer.exists' -Layer 1 -Name 'Impresora instalada' -Status 'ok'
    Add-Check -Id 'queue.health' -Layer 2 -Name 'Cola de impresion' -Status 'ok'
    Add-Check -Id 'hw.testprint' -Layer 4 -Name 'Prueba fisica de impresion' -Status 'ok'
    Add-Check -Id 'fudo.usoReal' -Layer 5 -Name 'Fudo le manda comandas a: CAJA' -Status 'ok' -Plane 'fudo_config'
    $d52f = Resolve-Diagnosis
    Assert-Eq 'S52f si imprime, esta OK aunque no se haya reparado nada' $true ([bool]$d52f.resolved)
    Assert-Eq 'S52f sin reparaciones que listar' 0 (@($d52f.autoFixesApplied)).Count
    Assert-Eq 'S52f no se cuenta como problema de hardware' 'ok.ya_funcionaba' (Get-Category -Diag $d52f)

    # Escenario 52g: si el papel NO salio, no cierra por mas que no haya nada roto.
    Reset-State
    Add-Check -Id 'printer.exists' -Layer 1 -Name 'Impresora instalada' -Status 'ok'
    Add-Check -Id 'hw.testprint' -Layer 4 -Name 'Prueba fisica de impresion' -Status 'skipped'
    $d52g = Resolve-Diagnosis
    Assert-Eq 'S52g sin papel confirmado no cierra' $false ([bool]$d52g.resolved)

    # Escenario 52b: con el historial confirmando que Fudo manda comandas, si cierra (no se
    # rompio el camino a resolved que se valido en campo con v3.8).
    Reset-State
    Add-Check -Id 'conn.usb' -Layer 3 -Name 'Puerto USB desmapeado' -Status 'fixed' -RootCauseCandidate $true
    Add-Check -Id 'hw.testprint' -Layer 4 -Name 'Prueba fisica de impresion' -Status 'ok'
    Add-Check -Id 'fudo.usoReal' -Layer 5 -Name 'Fudo le manda comandas a: CAJA' -Status 'ok' -Plane 'fudo_config'
    $d52b = Resolve-Diagnosis
    Assert-Eq 'S52b cierra cuando Fudo si manda comandas' $true ([bool]$d52b.resolved)
    Assert-Eq 'S52b marca el papel' $true ([bool]$d52b.paperOk)
    Assert-Eq 'S52b con el historial a favor, confianza alta' 'high' ([string]$d52b.confidence)
    Assert-Eq 'S52b no falta nada de Fudo' $false ([bool]$d52b.fudoSinUso)

    # Escenario 52c (probado contra hardware real): la Nativa apagada porque Fudo esta cerrado
    # NO puede impedir el cierre. Es un native messaging host: lo levanta el navegador cuando
    # hace falta. Si esto bloqueara, ningun caso diagnosticado con Fudo cerrado podria cerrar.
    Reset-State
    Add-Check -Id 'conn.usb' -Layer 3 -Name 'Puerto USB desmapeado' -Status 'fixed' -RootCauseCandidate $true
    Add-Check -Id 'hw.testprint' -Layer 4 -Name 'Prueba fisica de impresion' -Status 'ok'
    Add-Check -Id 'env.fudoApp' -Layer 0 -Name 'La App Nativa de Fudo no esta corriendo ahora' -Status 'warn' -RootCauseCandidate $false
    Add-Check -Id 'nativa.installed' -Layer 0 -Name 'App Nativa de Fudo instalada (no corre ahora: arranca con Fudo)' -Status 'warn' -RootCauseCandidate $false
    Add-Check -Id 'fudo.usoReal' -Layer 5 -Name 'Fudo le manda comandas a: CAJA' -Status 'ok' -Plane 'fudo_config'
    $d52c = Resolve-Diagnosis
    Assert-Eq 'S52c la Nativa apagada no impide cerrar' $true ([bool]$d52c.resolved)

    # Escenario 52d: que la Nativa no este INSTALADA si bloquea (sin ella no hay cadena).
    Reset-State
    Add-Check -Id 'conn.usb' -Layer 3 -Name 'Puerto USB desmapeado' -Status 'fixed' -RootCauseCandidate $true
    Add-Check -Id 'hw.testprint' -Layer 4 -Name 'Prueba fisica de impresion' -Status 'ok'
    Add-Check -Id 'nativa.installed' -Layer 0 -Name 'App Nativa de Fudo NO instalada' -Status 'fail' -RootCauseCandidate $true -Plane 'fudo_config'
    $d52d = Resolve-Diagnosis
    # Sigue bloqueando, pero ahora por la regla general (es un 'fail'), no por un gate propio.
    Assert-Eq 'S52d sin la Nativa instalada no cierra' $false ([bool]$d52d.resolved)
    Assert-Eq 'S52d y la causa es la Nativa ausente' 'nativa.installed' ([string]$d52d.rootCauseCheckId)

    # Escenario 52e: el historial apagado (plano 'os') no alcanza como evidencia para bloquear.
    Reset-State
    Add-Check -Id 'conn.usb' -Layer 3 -Name 'Puerto USB desmapeado' -Status 'fixed' -RootCauseCandidate $true
    Add-Check -Id 'hw.testprint' -Layer 4 -Name 'Prueba fisica de impresion' -Status 'ok'
    Add-Check -Id 'fudo.usoReal' -Layer 5 -Name 'Historial de impresion no disponible' -Status 'warn' -Plane 'os'
    $d52e = Resolve-Diagnosis
    Assert-Eq 'S52e sin historial no se bloquea el cierre' $true ([bool]$d52e.resolved)

    # Escenario 53 (v3.9, pedido de un asesor): cliente que imprime por RED. Las colas de red
    # estan sanas y no hay hardware USB; el diagnostico USB no puede ganar como causa raiz.
    Reset-State
    $script:Diagnostics['printer'] = [ordered]@{ name='COMANDA'; driver='Generic / Text Only'; port='IP_192.168.1.230' }
    $script:Diagnostics['colas'] = @(
        [ordered]@{ nombre='COMANDA'; puerto='IP_192.168.1.230'; esDePrueba=$false; score=0; estado='sana' },
        [ordered]@{ nombre='CAJA';    puerto='IP_192.168.1.235'; esDePrueba=$false; score=0; estado='sana' }
    )
    Add-Check -Id 'hw.deviceConnected' -Layer 1 -Name 'Ninguna impresora fisica conectada (Administrador de dispositivos)' -Status 'fail' -RootCauseCandidate $true -Plane 'hardware'
    Add-Check -Id 'fudo.printerRegistered' -Layer 5 -Name 'No se pudo verificar la impresora registrada en Fudo' -Status 'warn' -RootCauseCandidate $true -Plane 'fudo_config'
    $d53 = Resolve-Diagnosis
    Assert-Eq 'S53 el diagnostico USB no gana en cliente de red' $false ([string]$d53.rootCauseCheckId -eq 'hw.deviceConnected')
    Assert-Eq 'S53 la causa pasa a la capa que si aplica' 'fudo.printerRegistered' ([string]$d53.rootCauseCheckId)
    Assert-Eq 'S53 deja registro del modo red' $true ([bool]$script:Diagnostics.Contains('modoRedDetectado'))

    # Escenario 53b: con la impresora objetivo en USB, el diagnostico USB sigue ganando.
    Reset-State
    $script:Diagnostics['printer'] = [ordered]@{ name='COCINA'; driver='Generic / Text Only'; port='USB001' }
    $script:Diagnostics['colas'] = @(
        [ordered]@{ nombre='COCINA'; puerto='USB001'; esDePrueba=$false; score=30; estado='con problemas' }
    )
    Add-Check -Id 'hw.deviceConnected' -Layer 1 -Name 'Ninguna impresora fisica conectada (Administrador de dispositivos)' -Status 'fail' -RootCauseCandidate $true -Plane 'hardware'
    $d53b = Resolve-Diagnosis
    Assert-Eq 'S53b en USB la causa de hardware se mantiene' 'hw.deviceConnected' ([string]$d53b.rootCauseCheckId)
    Assert-Eq 'S53b no marca modo red' $false ([bool]$script:Diagnostics.Contains('modoRedDetectado'))

    # Escenario 54 (v3.9): el motivo del salteo y los ids de accion tienen que sobrevivir al
    # payload reducido de telemetria. Con {id,status,layer} no se podia auditar nada de capa 4.
    Reset-State
    Add-Check -Id 'hw.testprint' -Layer 4 -Name 'Prueba fisica de impresion' -Status 'skipped' -Evidence @{ note = 'sin impresora real objetivo'; skipReason = 'sin_impresora' }
    Add-Check -Id 'env.spooler' -Layer 0 -Name 'Servicio de cola de impresion' -Status 'ok'
    Add-Action -Type 'testprint.retarget' -Target 'CAJA' -Before 'COCINA' -After 'CAJA'
    $reducidos54 = @(ConvertTo-TelemetryChecks -Checks @($script:Checks))
    Assert-Eq 'S54 el motivo del salteo viaja' 'sin_impresora' ([string]@($reducidos54 | Where-Object { $_.id -eq 'hw.testprint' })[0].skipReason)
    Assert-Eq 'S54 un check sin motivo no inventa el campo' $false ([bool]@($reducidos54 | Where-Object { $_.id -eq 'env.spooler' })[0].Contains('skipReason'))
    Assert-Eq 'S54 los ids de accion estan disponibles' 'testprint.retarget' ((@($script:Actions | ForEach-Object { [string]$_.type })) -join ',')

    # Escenario 55 (v3.9): reconocer un puerto de red en todas las formas en que Windows lo
    # nombra. El motor tiene que saber cual cola es de red para poder acotar el modo.
    Reset-State
    Assert-Eq 'S55 IP_ es red'        $true  (Test-IsNetworkPort -PortName 'IP_192.168.1.230')
    Assert-Eq 'S55 IP pelada es red'  $true  (Test-IsNetworkPort -PortName '192.168.1.230')
    Assert-Eq 'S55 9100 es red'       $true  (Test-IsNetworkPort -PortName 'COMANDA_9100')
    Assert-Eq 'S55 WSD es red'        $true  (Test-IsNetworkPort -PortName 'WSD-fedd4304-37e2-467d-91c1-bdce0e2ec1e9')
    Assert-Eq 'S55 USB no es red'     $false (Test-IsNetworkPort -PortName 'USB001')
    Assert-Eq 'S55 LPT no es red'     $false (Test-IsNetworkPort -PortName 'LPT1:')
    Assert-Eq 'S55 vacio no es red'   $false (Test-IsNetworkPort -PortName '')

    # Escenario 56 (v3.9, caso real 52564e5e): el cliente imprime por red y ademas tiene una
    # inkjet USB desconectada. En modo Red la inkjet "enferma" no puede ganar la eleccion.
    Reset-State
    $script:PresentIdsOk = $true
    $script:Diagnostics['livePorts'] = @()
    $script:Diagnostics['hwDeviceCount'] = 0
    $script:__modo56 = $script:RunMode
    $script:RunMode = 'Red'
    function Get-Printer { @(
        [pscustomobject]@{ Name='HP DeskJet 2130'; DriverName='HP DeskJet'; PortName='USB001' },
        [pscustomobject]@{ Name='COMANDA';         DriverName='Generic / Text Only'; PortName='IP_192.168.123.100' }
    ) }
    function Get-CimInstance { [pscustomobject]@{ WorkOffline=$false; PrinterState=0 } }
    function Get-PrintJob { @() }
    $t56 = Resolve-TargetPrinter
    Assert-Eq 'S56 en modo Red elige la de red' 'COMANDA' $(if ($t56) { [string]$t56.Name } else { '' })
    Assert-Eq 'S56 avisa que descarto la USB' $true ([bool]((Get-CheckById 'printer.modeFilter') -ne $null))
    Assert-Eq 'S56 la telemetria igual ve las dos colas' 2 (@($script:Diagnostics['colas'])).Count
    $script:RunMode = $script:__modo56

    # Escenario 56b: el mismo parque de impresoras en modo USB elige la USB.
    Reset-State
    $script:PresentIdsOk = $true
    $script:Diagnostics['livePorts'] = @()
    $script:Diagnostics['hwDeviceCount'] = 0
    $script:__modo56b = $script:RunMode
    $script:RunMode = 'USB'
    function Get-Printer { @(
        [pscustomobject]@{ Name='HP DeskJet 2130'; DriverName='HP DeskJet'; PortName='USB001' },
        [pscustomobject]@{ Name='COMANDA';         DriverName='Generic / Text Only'; PortName='IP_192.168.123.100' }
    ) }
    function Get-CimInstance { [pscustomobject]@{ WorkOffline=$false; PrinterState=0 } }
    function Get-PrintJob { @() }
    $t56b = Resolve-TargetPrinter
    Assert-Eq 'S56b en modo USB elige la USB' 'HP DeskJet 2130' $(if ($t56b) { [string]$t56b.Name } else { '' })
    $script:RunMode = $script:__modo56b

    # Escenario 56c (v3.10, caso real reportado en el canal): se eligio Red y no hay ninguna
    # impresora de red. Hasta v3.9 se seguia igual con las USB "para no dejar el diagnostico
    # vacio", y eso termino imprimiendo un ticket de prueba en la impresora USB de un cliente
    # sin que el asesor lo pidiera. Ahora se corta: sin consola (modo agente) nunca se sigue.
    Reset-State
    $script:PresentIdsOk = $true
    $script:Diagnostics['livePorts'] = @()
    $script:Diagnostics['hwDeviceCount'] = 0
    $script:__modo56c = $script:RunMode
    $script:RunMode = 'Red'
    function Get-Printer { @([pscustomobject]@{ Name='COCINA'; DriverName='Generic / Text Only'; PortName='USB001' }) }
    function Get-CimInstance { [pscustomobject]@{ WorkOffline=$false; PrinterState=0 } }
    function Get-PrintJob { @() }
    $t56c = Resolve-TargetPrinter
    Assert-Eq 'S56c sin impresoras del modo no se diagnostica nada' '' $(if ($t56c) { [string]$t56c.Name } else { '' })
    Assert-Eq 'S56c se marca el corte' $true ([bool]$script:AbortByMode)
    Assert-Eq 'S56c y lo avisa' 'warn' ([string](Get-CheckById 'printer.modeFilter').status)
    Assert-Eq 'S56c deja constancia de que no se siguio' $false ([bool](Get-CheckById 'printer.modeFilter').evidence.continuoIgual)
    Assert-Eq 'S56c informa lo que si habia' 'COCINA [USB001]' ([string]@((Get-CheckById 'printer.modeFilter').evidence.instaladas)[0])
    $script:AbortByMode = $false
    $script:RunMode = $script:__modo56c

    # Escenario 57 (v3.9): en modo Red la falta de hardware USB es lo esperado, no una falla.
    # Es lo que producia "Ninguna impresora fisica conectada" en locales que imprimen por IP.
    Reset-State
    $script:__modo57 = $script:RunMode
    $script:RunMode = 'Red'
    function Get-UsbPrintDevices { @() }
    function Get-ProblemPrinterDevices { @() }
    function Get-PrinterPort { @() }
    function Get-Printer { @([pscustomobject]@{ Name='COMANDA'; DriverName='Generic / Text Only'; PortName='IP_192.168.1.230' }) }
    $null = Test-Layer1a-HardwareInventory
    Assert-Eq 'S57 no marca falla de hardware USB' 'skipped' ([string](Get-CheckById 'hw.deviceConnected').status)
    Assert-Eq 'S57 deja el motivo' 'modo_red' ([string](Get-CheckById 'hw.deviceConnected').evidence.skipReason)
    Assert-Eq 'S57 no es causa raiz' $false ([bool](Get-CheckById 'hw.deviceConnected').rootCauseCandidate)
    $script:RunMode = $script:__modo57

    # Escenario 58 (v3.9): dos candidatas en la MISMA capa. Sort-Object no es estable, asi que
    # la causa raiz salia en orden arbitrario: se vio el resumen mostrando la reparacion
    # intentada ("Exclusion preventiva de Defender") en vez del hallazgo que la motivo.
    Reset-State
    Add-Check -Id 'nativa.installed' -Layer 0 -Name 'App Nativa de Fudo instalada pero NO esta corriendo' -Status 'warn' -RootCauseCandidate $true -Plane 'fudo_config'
    Add-Check -Id 'nativa.defenderExclusion' -Layer 0 -Name 'La App Nativa no esta corriendo y Defender puede estar bloqueandola' -Status 'warn' -RootCauseCandidate $true
    $d58 = Resolve-Diagnosis
    Assert-Eq 'S58 gana el hallazgo detectado primero' 'nativa.installed' ([string]$d58.rootCauseCheckId)
    Assert-Eq 'S58 el seq se registra en orden' '0,1' ((@($script:Checks | ForEach-Object { [string]$_.seq })) -join ',')

    # Escenario 58b: el mismo par en el orden inverso de deteccion respeta ese orden.
    Reset-State
    Add-Check -Id 'nativa.defenderExclusion' -Layer 0 -Name 'La App Nativa no esta corriendo y Defender puede estar bloqueandola' -Status 'warn' -RootCauseCandidate $true
    Add-Check -Id 'nativa.installed' -Layer 0 -Name 'App Nativa de Fudo instalada pero NO esta corriendo' -Status 'warn' -RootCauseCandidate $true -Plane 'fudo_config'
    $d58b = Resolve-Diagnosis
    Assert-Eq 'S58b sigue ganando el primero detectado' 'nativa.defenderExclusion' ([string]$d58b.rootCauseCheckId)

    # Escenario 58c: una capa mas baja le sigue ganando a una mas alta aunque se detecte despues.
    Reset-State
    Add-Check -Id 'fudo.printerRegistered' -Layer 5 -Name 'No se pudo verificar la impresora en Fudo' -Status 'warn' -RootCauseCandidate $true -Plane 'fudo_config'
    Add-Check -Id 'env.spooler' -Layer 0 -Name 'Servicio de cola de impresion detenido' -Status 'fail' -RootCauseCandidate $true
    $d58c = Resolve-Diagnosis
    Assert-Eq 'S58c la capa manda sobre el orden' 'env.spooler' ([string]$d58c.rootCauseCheckId)

    # Escenario 59 (v3.9, primer caso contra hardware real): una sola Xprinter XP-410B
    # enchufada se reportaba como "Impresoras fisicas detectadas: 2", porque Windows la
    # representa con dos nodos (el device USB padre y su interfaz USBPRINT hija) y el dedup
    # solo miraba instanceId. Inflaba cantidadHardware en la telemetria y el resumen listaba
    # una segunda impresora "sin puerto asignado" que no existe.
    Reset-State
    Assert-Eq 'S59 normaliza el nombre' 'xprinterxp410b' (Get-DeviceNameKey -Name 'Xprinter XP-410B')
    Assert-Eq 'S59 tolera variantes de escritura' (Get-DeviceNameKey -Name 'XPrinter XP410B') (Get-DeviceNameKey -Name 'Xprinter XP-410B')
    # La forma exacta del par observado en una PC con la impresora enchufada: el nodo USBPRINT
    # hijo (unico que trae PortName) y el nodo USB padre con VID/PID y numero de serie.
    $f59 = @(Merge-DuplicateDevices -Devices @(
        [ordered]@{ source='registry.USBPRINT'; name='Xprinter XP-410B'; instanceId='USBPRINT\XprinterXP-410B\6&0&USB002'; portName='USB002'; status='enumerado'; problem=0 },
        [ordered]@{ source='Win32_PnPEntity';   name='Xprinter XP-410B'; instanceId='USB\VID_2D37&PID_8327\SERIE'; portName=''; status='OK'; problem=0 }
    ))
    Assert-Eq 'S59 una impresora se cuenta una vez' 1 (@($f59)).Count
    Assert-Eq 'S59 sobrevive la que tiene puerto' 'USB002' ([string]@($f59)[0].portName)

    # Escenario 59b: dos impresoras iguales de verdad, cada una con su puerto, siguen siendo dos.
    $f59b = @(Merge-DuplicateDevices -Devices @(
        [ordered]@{ name='Xprinter XP-410B'; instanceId='USBPRINT\A\1'; portName='USB001' },
        [ordered]@{ name='Xprinter XP-410B'; instanceId='USBPRINT\B\1'; portName='USB002' }
    ))
    Assert-Eq 'S59b dos impresoras reales siguen siendo dos' 2 (@($f59b)).Count

    # Escenario 59c: dos modelos distintos, ninguno con puerto, no se fusionan entre si.
    $f59c = @(Merge-DuplicateDevices -Devices @(
        [ordered]@{ name='Xprinter XP-410B'; instanceId='USB\A'; portName='' },
        [ordered]@{ name='3nStar RPT008';    instanceId='USB\B'; portName='' }
    ))
    Assert-Eq 'S59c modelos distintos sin puerto se conservan' 2 (@($f59c)).Count

    # Escenario 59d: un device sin nombre no se pierde por no tener con que compararlo.
    $f59d = @(Merge-DuplicateDevices -Devices @(
        [ordered]@{ name=''; instanceId='USB\SINNOMBRE'; portName='' }
    ))
    Assert-Eq 'S59d sin nombre no se descarta' 1 (@($f59d)).Count

    # Escenario 60 (v3.10, caso real): el ticket de prueba tiene que EMPUJAR el papel fuera del
    # mecanismo antes de cortar. Con 3 saltos de linea y corte sin avance (GS V 66 0) el texto
    # quedaba retenido adentro: el asesor no veia nada, respondia que no salio, y el motor daba
    # por fallado un hardware que funcionaba. Se confirmo con el mismo puerto y el mismo driver
    # generico imprimiendo bien a mano.
    Reset-State
    $tk = Get-EscPosTestTicket -Caption 'FUDO HW TEST'
    $feeds = ([regex]::Matches($tk, "`n")).Count
    Assert-Eq 'S60 el ticket empuja el papel antes de cortar' $true ($feeds -ge 8)
    Assert-Eq 'S60 el corte pide avance de papel' $true ($tk.Contains([char]29 + 'V' + [char]66 + [char]80))
    Assert-Eq 'S60 ya no corta con avance cero' $false ($tk.Contains([char]29 + 'V' + [char]66 + [char]0))
    Assert-Eq 'S60 sigue arrancando con el init ESC @' $true ($tk.StartsWith([char]27 + '@'))
    Assert-Eq 'S60 el texto clave sigue estando' $true ($tk.Contains('el hardware imprime OK'))

    # Escenario 61 (v3.10): desde la v0.0.37 la Nativa esta firmada y el antivirus no la
    # bloquea. Por debajo de esa version, la accion de fondo es actualizarla en vez de andar
    # agregando exclusiones de Defender en cada PC.
    Reset-State
    $v61a = Get-NativaVersionState -Install @{ regInfo = @([ordered]@{ name='Fudo'; version='0.0.36' }) }
    Assert-Eq 'S61 0.0.36 no esta firmada' $false ([bool]$v61a.firmada)
    Assert-Eq 'S61 devuelve la version leida' '0.0.36' ([string]$v61a.version)
    $v61b = Get-NativaVersionState -Install @{ regInfo = @([ordered]@{ name='Fudo'; version='0.0.37' }) }
    Assert-Eq 'S61 0.0.37 si esta firmada' $true ([bool]$v61b.firmada)
    $v61c = Get-NativaVersionState -Install @{ regInfo = @([ordered]@{ name='Fudo'; version='0.1.0' }) }
    Assert-Eq 'S61 una posterior tambien' $true ([bool]$v61c.firmada)
    # La comparacion tiene que ser numerica: como texto, '0.0.9' > '0.0.37'.
    $v61d = Get-NativaVersionState -Install @{ regInfo = @([ordered]@{ name='Fudo'; version='0.0.9' }) }
    Assert-Eq 'S61 0.0.9 es anterior, no posterior' $false ([bool]$v61d.firmada)
    # Sin dato de version no se puede afirmar nada: ni firmada ni sin firmar.
    $v61e = Get-NativaVersionState -Install @{ regInfo = @() }
    Assert-Eq 'S61 sin version no se afirma nada' $true ($null -eq $v61e.firmada)
    $v61f = Get-NativaVersionState -Install @{ regInfo = @([ordered]@{ name='Fudo'; version='no-es-version' }) }
    Assert-Eq 'S61 version ilegible tampoco' $true ($null -eq $v61f.firmada)

    # Escenario 62 (v3.11): los 4 chequeos de capa 5 que nacen en 'warn' por construccion
    # (solo se pueden verificar en la web app de Fudo) hacian que needsEscalation fuera SIEMPRE
    # true. Y como el status se armaba con (resolved -and -not needsEscalation), ninguna corrida
    # podia salir 'resolved': se vieron 5 filas con resolved=true y status=needs_escalation a la
    # vez, la columna "resuelto" sumando y el bloque "que resolvio" vacio.
    Reset-State
    Add-Check -Id 'conn.usb' -Layer 3 -Name 'Puerto USB desmapeado' -Status 'fixed' -RootCauseCandidate $true
    Add-Check -Id 'hw.testprint' -Layer 4 -Name 'Prueba fisica' -Status 'ok' -Plane 'hardware'
    Add-Check -Id 'fudo.usoReal' -Layer 5 -Name 'Fudo le manda comandas a: CAJA' -Status 'ok' -Plane 'fudo_config'
    foreach ($idc62 in @('fudo.printerRegistered','fudo.printerKitchen','fudo.categoryKitchen','fudo.rooms')) {
        Add-Check -Id $idc62 -Layer 5 -Name 'Verificable solo en la web app de Fudo' -Status 'warn' -Plane 'fudo_config'
    }
    $d62 = Resolve-Diagnosis
    Assert-Eq 'S62 cierra el caso' $true ([bool]$d62.resolved)
    Assert-Eq 'S62 el status lo dice' 'resolved' ([string]$d62.status)
    Assert-Eq 'S62 y entonces no escala' $false ([bool]$d62.needsEscalation)
    # Que no escale no borra la lista: los 4 de capa 5 siguen viajando como informativos.
    Assert-Eq 'S62 igual deja que revisar en Fudo' $true (@($d62.residualEscalation).Count -ge 4)

    # Escenario 62b: si no cierra, escala, y el status es el mismo dato.
    Reset-State
    Add-Check -Id 'printer.exists' -Layer 1 -Name 'Sin impresora real instalada' -Status 'fail' -RootCauseCandidate $true
    $d62b = Resolve-Diagnosis
    Assert-Eq 'S62b no cierra' $false ([bool]$d62b.resolved)
    Assert-Eq 'S62b status coherente' 'needs_escalation' ([string]$d62b.status)
    Assert-Eq 'S62b escala' $true ([bool]$d62b.needsEscalation)

    # Escenario 63 (v3.11, caso real): la capa 2 solo miraba la cola OBJETIVO. En una PC con
    # BARRA [192.168.0.17] acumulando 93 trabajos y COCINA [192.168.0.50] otros 13, gano como
    # causa "Ninguna impresora fisica conectada" teniendo una POS-80 en LPT1: sana. Un asesor
    # cerro ese mismo caso a mano preguntando "cola de impresion?".
    Reset-State
    $script:Diagnostics['colas'] = @(
        [ordered]@{ nombre='POS-80'; puerto='LPT1:';            esDePrueba=$false; score=0;  estado='sana';       trabajos=0;  minutosMasViejo=-1;  trabajoMasViejo='';            puertoVivo=$true },
        [ordered]@{ nombre='BARRA';  puerto='IP_192.168.0.17';  esDePrueba=$false; score=40; estado='no imprime'; trabajos=93; minutosMasViejo=180; trabajoMasViejo='31/08 19:05'; puertoVivo=$false },
        [ordered]@{ nombre='COCINA'; puerto='IP_192.168.0.50';  esDePrueba=$false; score=40; estado='no imprime'; trabajos=13; minutosMasViejo=95;  trabajoMasViejo='31/08 20:30'; puertoVivo=$false }
    )
    Test-Layer2-OtherQueuesBacklog -Printer ([pscustomobject]@{ Name='POS-80' })
    $c63 = Get-CheckById 'queue.otherBacklog'
    Assert-Eq 'S63 la cola atascada de otra impresora se levanta' 'fail' ([string]$c63.status)
    Assert-Eq 'S63 es candidata a causa raiz' $true ([bool]$c63.rootCauseCandidate)
    Assert-Eq 'S63 nombra la peor cola' $true ([bool]([string]$c63.name -match 'BARRA'))
    Assert-Eq 'S63 cuenta las dos colas con trabajos' 2 ([int]$c63.evidence.conTrabajos)
    Add-Check -Id 'hw.deviceConnected' -Layer 1 -Name 'Ninguna impresora fisica conectada (Administrador de dispositivos)' -Status 'fail' -RootCauseCandidate $true
    $d63 = Resolve-Diagnosis
    Assert-Eq 'S63 el veredicto USB ya no gana' 'queue.otherBacklog' ([string]$d63.rootCauseCheckId)
    Assert-Eq 'S63 categoria' 'os.queue' (Get-Category -Diag $d63)
    Assert-Eq 'S63 no cierra con comandas sin salir' $false ([bool]$d63.resolved)

    # Escenario 63b: la cola objetivo no se cuenta dos veces (ya la mira Test-Layer2-Queue), y
    # una cola con 1 o 2 trabajos no es un atasco.
    Reset-State
    $script:Diagnostics['colas'] = @(
        [ordered]@{ nombre='CAJA';   puerto='USB001'; esDePrueba=$false; score=40; estado='no imprime'; trabajos=50; minutosMasViejo=200; trabajoMasViejo='31/08 18:00'; puertoVivo=$true },
        [ordered]@{ nombre='COCINA'; puerto='USB002'; esDePrueba=$false; score=10; estado='con problemas'; trabajos=2; minutosMasViejo=1; trabajoMasViejo='31/08 21:00'; puertoVivo=$true }
    )
    Test-Layer2-OtherQueuesBacklog -Printer ([pscustomobject]@{ Name='CAJA' })
    Assert-Eq 'S63b la cola objetivo no se duplica' 'ok' ([string](Get-CheckById 'queue.otherBacklog').status)

    # Escenario 63c: una rafaga recien encolada puede estar drenando sola. Queda en warn (se
    # informa y compite como causa) pero no bloquea el cierre como un atasco de hace horas.
    Reset-State
    $script:Diagnostics['colas'] = @(
        [ordered]@{ nombre='CAJA';   puerto='USB001'; esDePrueba=$false; score=0;  estado='sana'; trabajos=0; minutosMasViejo=-1; trabajoMasViejo=''; puertoVivo=$true },
        [ordered]@{ nombre='COCINA'; puerto='USB002'; esDePrueba=$false; score=40; estado='no imprime'; trabajos=4; minutosMasViejo=1; trabajoMasViejo='31/08 21:00'; puertoVivo=$true }
    )
    Test-Layer2-OtherQueuesBacklog -Printer ([pscustomobject]@{ Name='CAJA' })
    Assert-Eq 'S63c una rafaga reciente no es atasco' 'warn' ([string](Get-CheckById 'queue.otherBacklog').status)
    Assert-Eq 'S63c y no baja de rango el diagnostico USB' $false ([bool](Get-CheckById 'queue.otherBacklog').evidence.puertoUtil)

    # Escenario 63d: las colas de prueba del propio motor no cuentan como atasco del cliente.
    Reset-State
    $script:Diagnostics['colas'] = @(
        [ordered]@{ nombre='FUDO-TEST-USB001'; puerto='USB001'; esDePrueba=$true; score=40; estado='no imprime'; trabajos=9; minutosMasViejo=30; trabajoMasViejo='31/08 20:00'; puertoVivo=$true }
    )
    Test-Layer2-OtherQueuesBacklog -Printer ([pscustomobject]@{ Name='CAJA' })
    Assert-Eq 'S63d la cola de prueba propia no cuenta' 'ok' ([string](Get-CheckById 'queue.otherBacklog').status)

    # Escenario 64 (v3.11): una corrida que aborta mandaba a la planilla
    # checks: [{"id":"","status":"","layer":null}] y autoFixesApplied: [null], porque
    # @($null) es un array de un elemento nulo. Ese ruido entraba como si fuera un check real.
    Reset-State
    Assert-Eq 'S64 sin checks no se inventa ninguno' 0 (@(ConvertTo-TelemetryChecks -Checks $null)).Count
    Assert-Eq 'S64 un array vacio tampoco' 0 (@(ConvertTo-TelemetryChecks -Checks @())).Count
    Add-Check -Id 'env.spooler' -Layer 0 -Name 'Spooler' -Status 'ok'
    Assert-Eq 'S64 los checks reales si viajan' 1 (@(ConvertTo-TelemetryChecks -Checks @($script:Checks))).Count
    Assert-Eq 'S64 con su id' 'env.spooler' ([string]@(ConvertTo-TelemetryChecks -Checks @($script:Checks))[0].id)


    # Escenario 65 (v3.11): el veredicto salia de la foto de la capa 1, tomada ANTES de reparar.
    # Una impresora que el motor acababa de poner en linea seguia contando como offline y una
    # cola recien purgada seguia contando como trabada, en pantalla y en la telemetria.
    # Aca: CAJA estaba offline y con 40 trabajos al empezar; al re-escanear quedo sana.
    Reset-State
    $script:Diagnostics['colas'] = @(
        [ordered]@{ nombre='CAJA';   puerto='USB001'; esDePrueba=$false; score=65; estado='no imprime'; trabajos=40; minutosMasViejo=90; trabajoMasViejo='01/09 08:00'; puertoVivo=$true; offline=$true;  pausada=$false; sintomas=@('40 trabajos encolados','marcada como sin conexion (offline)') },
        [ordered]@{ nombre='COCINA'; puerto='USB002'; esDePrueba=$false; score=0;  estado='sana';       trabajos=0;  minutosMasViejo=-1; trabajoMasViejo='';            puertoVivo=$true; offline=$false; pausada=$false; sintomas=@() }
    )
    $script:PresentIdsOk = $true
    function Get-UsbPrintDevices {
        @([ordered]@{ source='registry.USBPRINT'; name='POS-80'; instanceId='USBPRINT\POS80'; portName='USB001'; status='enumerado'; problem=0 },
          [ordered]@{ source='registry.USBPRINT'; name='POS-58'; instanceId='USBPRINT\POS58'; portName='USB002'; status='enumerado'; problem=0 })
    }
    function Get-Printer { @(
        [pscustomobject]@{ Name='CAJA';   DriverName='Generic / Text Only'; PortName='USB001' },
        [pscustomobject]@{ Name='COCINA'; DriverName='Generic / Text Only'; PortName='USB002' }
    ) }
    function Get-CimInstance { [pscustomobject]@{ WorkOffline=$false; PrinterState=0 } }
    function Get-PrintJob { @() }
    $r65 = @(Update-PrintInventory)
    Assert-Eq 'S65 relee las colas del cliente' 2 (@($r65)).Count
    Assert-Eq 'S65 CAJA ya no figura rota' 0 ([int](@($r65 | Where-Object { $_.nombre -eq 'CAJA' })[0].score))
    Assert-Eq 'S65 la cobertura queda en ok' 'ok' ([string](Get-CheckById 'printer.coverage').status)
    Assert-Eq 'S65 registra que CAJA mejoro' 'CAJA' ((@($script:Diagnostics['colasQueMejoraron'])) -join ',')
    # printer.coverage viajaba solo como status: sin el valor no se puede decidir si la
    # cobertura tiene que bloquear el cierre.
    Assert-Eq 'S65 publica el valor de la cobertura' '2/2' ("$($script:Diagnostics['cobertura'].sanas)/$($script:Diagnostics['cobertura'].total)")
    Assert-Eq 'S65 guarda la foto inicial para comparar' 2 (@($script:Diagnostics['colasIniciales'])).Count
    # Y re-mapea que puertos tienen algo enchufado (antes quedaba el cache del arranque).
    Assert-Eq 'S65 refresca los puertos con dispositivo' 'USB001,USB002' ((@($script:Diagnostics['livePorts'])) -join ',')

    # Escenario 65b: si despues de todo queda una impresora sin poder imprimir, se dice -pero no
    # bloquea el cierre: un local puede tener una impresora vieja apagada que no es la de comandas.
    Reset-State
    $script:PresentIdsOk = $true
    function Get-UsbPrintDevices { @([ordered]@{ source='registry.USBPRINT'; name='POS-80'; instanceId='USBPRINT\POS80'; portName='USB002'; status='enumerado'; problem=0 }) }
    function Get-Printer { @(
        [pscustomobject]@{ Name='VIEJA';  DriverName='Generic / Text Only'; PortName='USB001' },
        [pscustomobject]@{ Name='COCINA'; DriverName='Generic / Text Only'; PortName='USB002' }
    ) }
    function Get-CimInstance { [pscustomobject]@{ WorkOffline=$false; PrinterState=0 } }
    function Get-PrintJob { @() }
    $null = Update-PrintInventory
    $c65b = Get-CheckById 'printer.coverage'
    Assert-Eq 'S65b avisa que queda una sin poder imprimir' 'warn' ([string]$c65b.status)
    Assert-Eq 'S65b la nombra' $true ([bool]([string]@($c65b.evidence.rotas)[0] -match 'VIEJA'))
    Assert-Eq 'S65b no compite como causa raiz' $false ([bool]$c65b.rootCauseCandidate)
    Add-Check -Id 'hw.testprint' -Layer 4 -Name 'Prueba fisica de impresion' -Status 'ok'
    $d65b = Resolve-Diagnosis
    Assert-Eq 'S65b y no impide cerrar si la de comandas imprime' $true ([bool]$d65b.resolved)

    # Escenario 65c: la cola de prueba del propio motor no cuenta como impresora del cliente.
    Reset-State
    $script:PresentIdsOk = $true
    function Get-UsbPrintDevices { @([ordered]@{ source='registry.USBPRINT'; name='POS-80'; instanceId='USBPRINT\POS80'; portName='USB001'; status='enumerado'; problem=0 }) }
    function Get-Printer { @(
        [pscustomobject]@{ Name='FUDO-TEST-USB001'; DriverName='Generic / Text Only'; PortName='USB001' },
        [pscustomobject]@{ Name='COCINA';           DriverName='Generic / Text Only'; PortName='USB001' }
    ) }
    function Get-CimInstance { [pscustomobject]@{ WorkOffline=$false; PrinterState=0 } }
    function Get-PrintJob { @() }
    $null = Update-PrintInventory
    Assert-Eq 'S65c no cuenta la cola de prueba del motor' $true ([bool]([string](Get-CheckById 'printer.coverage').name -match 'imprimir \(1\)'))


    # Escenario 66 (v3.11): el self-test nunca puede escribir en la planilla. Se descubrio
    # solo: un error dentro del self-test sale al catch global, y ese catch manda telemetria.
    # Entro una fila engine_error de una corrida que jamas toco una impresora.
    Reset-State
    Assert-Eq 'S66 el self-test no manda telemetria' $false ([bool](Send-Telemetry -Result @{ status = 'resolved' }))
    Assert-Eq 'S66 y deja dicho por que' 'no se envia: corrida de self-test' ([string]$script:TelemetryStatus.detalle)
    # Escenario 67 (v3.12, telemetria del 02/09): la reparacion de Defender se ejecutaba en PCs
    # que tenian la Nativa 0.0.37 FIRMADA y presente. Get-MpThreatDetection devuelve el
    # HISTORIAL de detecciones, no la cuarentena viva: una deteccion de hace semanas sigue
    # listada para siempre, y cualquier entrada disparaba restaurar + excluir. Aparecio en 6
    # corridas 3.11, y uno de los dos unicos cierres de la 3.11 cerro con esa causa y volvio a
    # fallar 34 segundos despues re-aplicando el mismo fix.
    Reset-State
    $amenaza = @([ordered]@{ id='2147519003'; resources='file:_C:\Users\x\AppData\Local\Fudo\fudo.exe'; remediada=$true })
    # La prueba directa de que no esta en cuarentena es que el archivo esta.
    $q67a = Test-DefenderThreatActionable -Threats $amenaza -Firmada $true -Presente $true
    Assert-Eq 'S67 con la Nativa presente no hay nada que restaurar' $false ([bool]$q67a.accionable)
    Assert-Eq 'S67 y lo explica' $true ([bool]([string]$q67a.motivo -match 'historica'))
    # Presente pero sin firmar: tampoco hay que restaurar (esta en disco). Lo que corresponde
    # ahi es actualizarla, que es lo que dice nativa.sinFirmar.
    $q67b = Test-DefenderThreatActionable -Threats $amenaza -Firmada $false -Presente $true
    Assert-Eq 'S67 presente sin firmar tampoco se restaura' $false ([bool]$q67b.accionable)
    # Si NO esta en disco, se repara: ahi la deteccion si es la explicacion.
    $q67c = Test-DefenderThreatActionable -Threats $amenaza -Firmada $false -Presente $false
    Assert-Eq 'S67 sin la Nativa en disco si se repara' $true ([bool]$q67c.accionable)
    # Y se repara incluso con la version firmada: si el archivo falta, el gate de version no
    # alcanza (era el punto (b) de la bitacora: el check podria estar leyendo mal).
    $q67d = Test-DefenderThreatActionable -Threats $amenaza -Firmada $true -Presente $false
    Assert-Eq 'S67 el gate de version no tapa un archivo que falta' $true ([bool]$q67d.accionable)
    # Sin detecciones no se toca el antivirus por ningun motivo.
    $q67e = Test-DefenderThreatActionable -Threats @() -Firmada $true -Presente $true
    Assert-Eq 'S67 sin detecciones no hay rama de cuarentena' $false ([bool]$q67e.accionable)
    # Las detecciones que Defender no llego a remediar se cuentan aparte, para el reporte.
    $q67f = Test-DefenderThreatActionable -Threats @([ordered]@{ id='1'; remediada=$false }) -Firmada $true -Presente $true
    Assert-Eq 'S67 cuenta las detecciones sin remediar' 1 (@($q67f.pendientes).Count)

    # Escenario 68 (v3.12, telemetria del 02/09): la categoria se derivaba de un regex sobre el
    # TEXTO de la causa, y ese texto lo escribe cada check para el asesor. 'App Nativa de Fudo
    # NO instalada' pegaba en el regex 'no instalada' y caia en os.driver_faltante: en la
    # planilla el id nativa.installed aparecia repartido en 4 categorias (nativa.install x12,
    # nativa.antivirus x5, os.driver_faltante x4, os.usb_port x2). La tabla CAUSA del dashboard
    # no era agregable.
    Reset-State
    Add-Check -Id 'nativa.installed' -Layer 0 -Name 'App Nativa de Fudo NO instalada' -Status 'fail' -RootCauseCandidate $true -Plane 'fudo_config'
    $d68 = Resolve-Diagnosis
    Assert-Eq 'S68 la causa es la Nativa ausente' 'nativa.installed' ([string]$d68.rootCauseCheckId)
    Assert-Eq 'S68 y su categoria sale del id, no del texto' 'nativa.install' (Get-Category -Diag $d68)
    # El texto que confundia al regex sigue siendo el que lee el asesor: no se cambio la
    # redaccion, se cambio de donde sale la categoria.
    Assert-Eq 'S68 el texto para el asesor no cambio' $true ([bool]([string]$d68.rootCause -match 'NO instalada'))

    # Escenario 68b: ninguna corrida que no sea un engine_error puede viajar sin id de causa.
    # Era el caso de las 2 filas 3.11 con rootCauseCheckId vacio.
    Reset-State
    Add-Check -Id 'hw.testprint' -Layer 4 -Name 'Prueba fisica' -Status 'ok' -Plane 'hardware'
    Add-Check -Id 'fudo.printerKitchen' -Layer 5 -Name 'Impresora con Cocina/Area asignada' -Status 'warn' -Plane 'fudo_config'
    $d68b = Resolve-Diagnosis
    # Esta asercion estaba mal escrita en la 3.12: el '-or resolved' la hacia pasar siempre y
    # dejo pasar justo el caso que iba a garantizar. En la telemetria del 02/09 aparecio una
    # fila cerrando resolved con rootCauseCheckId VACIO. Ahora se afirma el invariante.
    Assert-Eq 'S68b un cierre sin reparaciones igual dice de donde salio' 'ok.yaFuncionaba' ([string]$d68b.rootCauseCheckId)
    Assert-Eq 'S68b y no viaja sin id' $true (([string]$d68b.rootCauseCheckId).Length -gt 0)
    Reset-State
    Add-Check -Id 'nativa.installed' -Layer 0 -Name 'App Nativa de Fudo instalada' -Status 'warn' -RootCauseCandidate $false
    $d68c = Resolve-Diagnosis
    Assert-Eq 'S68c sin candidato ni papel, la corrida no queda sin id' 'engine.inconclusive' ([string]$d68c.rootCauseCheckId)
    Assert-Eq 'S68c y su categoria' 'unknown' (Get-Category -Diag $d68c)

    # Escenario 69 (v3.12, caso real): el umbral de 3 trabajos dejaba fuera el caso mas comun.
    # DESKTOP-HT51G4G (CL, Ethernet, 8 colas) arrastro REPOSTERIA [192.168.1.202] con UN
    # trabajo trabado 28 minutos en tres corridas seguidas, y queue.otherBacklog quedo en 'ok'
    # en 19 de 19 corridas 3.11: nunca disparo. Ahora se informa desde 1 trabajo, pero sin
    # ganarle la causa raiz a nada: solo el atasco de verdad compite.
    Reset-State
    $script:Diagnostics['colas'] = @(
        [ordered]@{ nombre='COCINA';    puerto='IP_192.168.1.206'; esDePrueba=$false; score=40; estado='no imprime'; trabajos=0; minutosMasViejo=-1; trabajoMasViejo=''; puertoVivo=$false },
        [ordered]@{ nombre='REPOSTERIA'; puerto='IP_192.168.1.202'; esDePrueba=$false; score=40; estado='no imprime'; trabajos=1; minutosMasViejo=28; trabajoMasViejo='01/09 20:11'; puertoVivo=$false }
    )
    Test-Layer2-OtherQueuesBacklog -Printer ([pscustomobject]@{ Name='COCINA' })
    $c69 = Get-CheckById 'queue.otherBacklog'
    Assert-Eq 'S69 un trabajo viejo ya se informa' 'warn' ([string]$c69.status)
    Assert-Eq 'S69 nombra la cola' $true ([bool]([string]$c69.name -match 'REPOSTERIA'))
    Assert-Eq 'S69 pero no compite como causa raiz' $false ([bool]$c69.rootCauseCandidate)
    # Y no baja de rango al diagnostico de conectividad: la causa sigue siendo la de la capa 3.
    Add-Check -Id 'conn.net' -Layer 3 -Name 'Impresora de red inalcanzable (192.168.1.206:9100)' -Status 'fail' -RootCauseCandidate $true -Plane 'fudo_config'
    $d69 = Resolve-Diagnosis
    Assert-Eq 'S69 la causa sigue siendo la impresora inalcanzable' 'conn.net' ([string]$d69.rootCauseCheckId)

    # Escenario 69b: un solo trabajo RECIEN encolado no es nada. No se informa (seria ruido en
    # cada corrida de un local que esta imprimiendo normal).
    Reset-State
    $script:Diagnostics['colas'] = @(
        [ordered]@{ nombre='CAJA';   puerto='USB001'; esDePrueba=$false; score=0;  estado='sana'; trabajos=0; minutosMasViejo=-1; trabajoMasViejo=''; puertoVivo=$true },
        [ordered]@{ nombre='COCINA'; puerto='USB002'; esDePrueba=$false; score=10; estado='con problemas'; trabajos=1; minutosMasViejo=0; trabajoMasViejo='02/09 09:40'; puertoVivo=$true }
    )
    Test-Layer2-OtherQueuesBacklog -Printer ([pscustomobject]@{ Name='CAJA' })
    Assert-Eq 'S69b una comanda recien mandada no es un atasco' 'ok' ([string](Get-CheckById 'queue.otherBacklog').status)

    # Escenario 69c: el atasco de verdad (3 o mas y de hace rato) no cambio: sigue en fail y
    # sigue siendo causa raiz. Es lo que la 3.11 agrego y no hay que perderlo.
    Reset-State
    $script:Diagnostics['colas'] = @(
        [ordered]@{ nombre='POS-80'; puerto='LPT1:';           esDePrueba=$false; score=0;  estado='sana';       trabajos=0;  minutosMasViejo=-1; trabajoMasViejo=''; puertoVivo=$true },
        [ordered]@{ nombre='BARRA';  puerto='IP_192.168.0.17'; esDePrueba=$false; score=40; estado='no imprime'; trabajos=93; minutosMasViejo=180; trabajoMasViejo='31/08 19:05'; puertoVivo=$false }
    )
    Test-Layer2-OtherQueuesBacklog -Printer ([pscustomobject]@{ Name='POS-80' })
    $c69c = Get-CheckById 'queue.otherBacklog'
    Assert-Eq 'S69c el atasco de verdad sigue en fail' 'fail' ([string]$c69c.status)
    Assert-Eq 'S69c y sigue siendo causa raiz' $true ([bool]$c69c.rootCauseCandidate)
    Assert-Eq 'S69c y sigue bajando de rango el veredicto USB' $true ([bool]$c69c.evidence.puertoUtil)
    # Escenario 70 (v3.13, telemetria del 02/09): `fudoSinUso = false` significaba dos cosas
    # opuestas -'Fudo SI imprimio' y 'no tenemos idea'- y no habia forma de distinguirlas. El log
    # de impresion de Windows viene APAGADO de fabrica: el motor lo habilita en esa misma corrida
    # y el historial queda vacio, asi que el check fudo.usoReal sale con plano 'os' (no
    # 'fudo_config'), no entra en el filtro, y el caso cerraba como si Fudo estuviera imprimiendo.
    # Fue 10 de 10 primeras corridas de cada PC, y la corrida siguiente daba true 5 de 5. Con eso
    # el cruce 'resolved x fudoSinUso' daba 4/4 cierres completos y era un artefacto.
    Reset-State
    Add-Check -Id 'fudo.usoReal' -Layer 5 -Name 'Historial de impresion no disponible' -Status 'warn' -Plane 'os'
    Add-Check -Id 'hw.testprint' -Layer 4 -Name 'Prueba fisica' -Status 'ok' -Plane 'hardware'
    $d70 = Resolve-Diagnosis
    Assert-Eq 'S70 cierra (la impresora imprime)' $true ([bool]$d70.resolved)
    Assert-Eq 'S70 no se puede saber si Fudo imprime' 'sin_datos' ([string]$d70.fudoUsoEstado)
    Assert-Eq 'S70 y el cierre queda marcado como no verificado' $true ([bool]$d70.cierreSinVerificarFudo)
    # El bool viejo sigue significando lo mismo que antes (no hay comandas Y hay con que mirar),
    # asi que aca es false: es justo el valor que enganaba, ahora desambiguado por el estado.
    Assert-Eq 'S70 el bool viejo no alcanzaba' $false ([bool]$d70.fudoSinUso)
    # Y el asesor tiene que verlo en pantalla: antes este caso cerraba mudo.
    $txt70 = ((Build-HumanSummary -Diag $d70 -DetectedInterface 'USB') -join ' ')
    Assert-Eq 'S70 la pantalla avisa que falta el tramo' $true ([bool]($txt70 -match 'FALTA'))
    Assert-Eq 'S70 y explica que no hay historial' $true ([bool]($txt70 -match 'historial de impresion'))

    # Escenario 70b: el log SI estaba disponible y no hay ninguna comanda de Fudo. Ese es el
    # 'sin_comandas' de verdad, y ese cierre si esta verificado (se pudo mirar y no habia).
    Reset-State
    Add-Check -Id 'fudo.usoReal' -Layer 5 -Name 'Ninguna cola recibio comandas de Fudo en el historial' -Status 'warn' -RootCauseCandidate $true -Plane 'fudo_config'
    Add-Check -Id 'hw.testprint' -Layer 4 -Name 'Prueba fisica' -Status 'ok' -Plane 'hardware'
    $d70b = Resolve-Diagnosis
    Assert-Eq 'S70b hay datos y no hay comandas' 'sin_comandas' ([string]$d70b.fudoUsoEstado)
    Assert-Eq 'S70b el bool viejo sigue valiendo' $true ([bool]$d70b.fudoSinUso)
    Assert-Eq 'S70b este cierre si esta verificado' $false ([bool]$d70b.cierreSinVerificarFudo)

    # Escenario 70c: Fudo le manda comandas. Cierre completo, sin FALTA.
    Reset-State
    Add-Check -Id 'fudo.usoReal' -Layer 5 -Name 'Fudo le manda comandas a: COCINA' -Status 'ok' -Plane 'fudo_config'
    Add-Check -Id 'hw.testprint' -Layer 4 -Name 'Prueba fisica' -Status 'ok' -Plane 'hardware'
    $d70c = Resolve-Diagnosis
    Assert-Eq 'S70c Fudo imprime' 'con_comandas' ([string]$d70c.fudoUsoEstado)
    Assert-Eq 'S70c cierre completo' $false ([bool]$d70c.cierreSinVerificarFudo)
    Assert-Eq 'S70c sin linea FALTA' $false ([bool](((Build-HumanSummary -Diag $d70c -DetectedInterface 'USB') -join ' ') -match 'FALTA'))

    # Escenario 70d: si la capa 5 no llego a evaluarse, tampoco se puede afirmar nada.
    Reset-State
    Add-Check -Id 'hw.testprint' -Layer 4 -Name 'Prueba fisica' -Status 'ok' -Plane 'hardware'
    Assert-Eq 'S70d sin capa 5 no se afirma nada' 'sin_datos' ([string](Resolve-Diagnosis).fudoUsoEstado)

    # Escenario 70e: el ticket de prueba del propio motor no puede aparecer en el historial del
    # local. El descarte estaba DESPUES de crear la entrada, asi que una cola cuyo unico trabajo
    # fue el ticket del motor figuraba igual con total=0 y ejemploDoc='Fudo Print Doctor Test'.
    Reset-State
    function Get-WinEvent {
        if ("$args" -match '-ListLog') { return [pscustomobject]@{ IsEnabled = $true } }
        $ev = {
            param($doc, $imp)
            [pscustomobject]@{ Id = 307; TimeCreated = (Get-Date); Properties = @(
                [pscustomobject]@{ Value = '' }, [pscustomobject]@{ Value = $doc },
                [pscustomobject]@{ Value = '' }, [pscustomobject]@{ Value = '' },
                [pscustomobject]@{ Value = $imp }) }
        }
        return @(
            (& $ev 'Fudo Print Doctor Test' 'FUDO-TEST-USB001'),
            (& $ev 'node print job' 'COCINA'),
            (& $ev 'Presupuesto.docx' 'HP LaserJet')
        )
    }
    $h70e = Get-PrintHistory
    Assert-Eq 'S70e el log figura habilitado' $true ([bool]$h70e.habilitado)
    # Dos colas, no tres: la del motor no entra ni con total 0.
    Assert-Eq 'S70e la cola de prueba del motor no aparece' 2 (@($h70e.porImpresora).Count)
    Assert-Eq 'S70e y no queda ni el nombre de su documento' $false ([bool]((@($h70e.porImpresora | ForEach-Object { [string]$_.ejemploDoc }) -join '|') -match 'Print Doctor'))
    $c70e = @($h70e.porImpresora | Where-Object { $_.impresora -eq 'COCINA' })[0]
    Assert-Eq 'S70e la comanda de Fudo si cuenta' 1 ([int]$c70e.deFudo)
    $l70e = @($h70e.porImpresora | Where-Object { $_.impresora -eq 'HP LaserJet' })[0]
    Assert-Eq 'S70e un trabajo ajeno cuenta pero no como Fudo' 0 ([int]$l70e.deFudo)
    Assert-Eq 'S70e y si suma al total' 1 ([int]$l70e.total)

    # Escenario 71 (v3.13, caso real): el motivo del salteo de la prueba decia 'sin_impresora'
    # tambien cuando SI habia hardware presente y lo que faltaba era que Windows le asignara un
    # puerto. Se vio una PC con hardwarePresente=1 y cantidadColas=0 escalando asi: el motivo no
    # dejaba distinguir 'no hay nada enchufado' de 'esta enchufada y Windows no le dio puerto'.
    Reset-State
    $script:Diagnostics['hwDeviceCount'] = 1
    # Reset-State no limpia las colas ya creadas (es a proposito, lo verifica S27), asi que se
    # mide el delta de esta corrida y no el acumulado del self-test.
    $colas71Antes = @($script:TestPrintersCreated).Count
    Test-Layer4-HardwarePrint -Printer $null -DetectedInterface 'USB'
    $c71 = Get-CheckById 'hw.testprint'
    Assert-Eq 'S71 con hardware presente el motivo es el puerto' 'sin_puerto_asignado' ([string]$c71.evidence.skipReason)
    Assert-Eq 'S71 y lo dice en la causa' $true ([bool]([string]$c71.name -match 'no le asigno ningun puerto'))
    Assert-Eq 'S71 deja el conteo de hardware' 1 ([int]$c71.evidence.hardwarePresente)
    # Y no se inventa una cola de prueba sobre un puerto que no existe: imprimir al vacio fue
    # justo el bug que la v3.7 corrigio (el motor reportando su propia cola como desconectada).
    Assert-Eq 'S71 no crea ninguna cola' $colas71Antes (@($script:TestPrintersCreated).Count)

    # Escenario 71b: sin hardware, el motivo sigue siendo el de siempre.
    Reset-State
    $script:Diagnostics['hwDeviceCount'] = 0
    Test-Layer4-HardwarePrint -Printer $null -DetectedInterface 'USB'
    Assert-Eq 'S71b sin hardware el motivo no cambia' 'sin_impresora' ([string](Get-CheckById 'hw.testprint').evidence.skipReason)

    # Escenario 72 (v3.13, telemetria del 02/09): el id y el texto de la causa salian de fuentes
    # distintas. Al cerrar, el texto se armaba con la reparacion de menor capa pero el id se tomaba
    # de los candidatos en fail/warn: se vio una fila con rootCauseCheckId='hw.notInstalled' y
    # causa 'Puerto USB desmapeado' (que es conn.usb), y la categoria salio de un check que no era
    # la causa. El mismo hw.notInstalled caia en os.driver_faltante en las otras corridas.
    Reset-State
    Add-Check -Id 'hw.notInstalled' -Layer 1 -Name 'Impresora conectada pero no instalada en Windows' -Status 'warn' -RootCauseCandidate $true -Plane 'os'
    Add-Check -Id 'conn.usb' -Layer 3 -Name 'Puerto USB desmapeado' -Status 'fixed' -RootCauseCandidate $true
    Add-Check -Id 'hw.testprint' -Layer 4 -Name 'Prueba fisica' -Status 'ok' -Plane 'hardware'
    $d72 = Resolve-Diagnosis
    Assert-Eq 'S72 cierra' $true ([bool]$d72.resolved)
    Assert-Eq 'S72 el id de la causa es el del check reparado' 'conn.usb' ([string]$d72.rootCauseCheckId)
    Assert-Eq 'S72 el texto describe lo mismo que el id' 'Puerto USB desmapeado' ([string]$d72.rootCause)
    Assert-Eq 'S72 y la categoria sale de ahi' 'os.usb_port' (Get-Category -Diag $d72)

    # Escenario 72b: cuando NO cierra, hw.notInstalled si es la causa, y ahora esta en la tabla
    # (la 3.12 lo dejo afuera y caia por regex en dos categorias distintas).
    Reset-State
    Add-Check -Id 'hw.notInstalled' -Layer 1 -Name 'Impresora conectada pero no instalada en Windows' -Status 'warn' -RootCauseCandidate $true -Plane 'os'
    $d72b = Resolve-Diagnosis
    Assert-Eq 'S72b la causa es la impresora sin instalar' 'hw.notInstalled' ([string]$d72b.rootCauseCheckId)
    Assert-Eq 'S72b categoria estable' 'os.driver_faltante' (Get-Category -Diag $d72b)

    # Escenario 72c: la causa de una prueba fallida no puede ser el titulo del paso. Se vieron 3
    # corridas con causaRaiz = 'Prueba fisica ESC/POS por USB (RAW)', que es el nombre del paso y
    # no dice nada. Las tres ramas de fallo ahora traen causa redactada y categoria propia.
    Reset-State
    Add-Check -Id 'hw.testprint' -Layer 4 -Name 'La impresora recibio el ticket de prueba pero no salio papel' -Status 'fail' -RootCauseCandidate $true -Plane 'hardware'
    $d72c = Resolve-Diagnosis
    Assert-Eq 'S72c la prueba fallida es la causa' 'hw.testprint' ([string]$d72c.rootCauseCheckId)
    Assert-Eq 'S72c y tiene su propia categoria' 'hardware.no_imprime' (Get-Category -Diag $d72c)
    Assert-Eq 'S72c la causa explica que paso' $true ([bool]([string]$d72c.rootCause -match 'no salio papel'))
    # Y el titulo del paso ya no puede ser una causa: ninguna rama de fallo lo usa como nombre.
    Reset-State
    Add-Check -Id 'hw.testprint' -Layer 4 -Name 'El ticket de prueba entro a la cola y no se imprimio: la impresora no responde' -Status 'fail' -RootCauseCandidate $true -Plane 'hardware'
    Assert-Eq 'S72c la rama de cola trabada tambien redacta' 'hardware.no_imprime' (Get-Category -Diag (Resolve-Diagnosis))
    # Escenario 73 (v3.14, pedido del equipo): el ID de conversacion pasa a ser OBLIGATORIO.
    # Hasta la 3.13 era opcional -el launcher decia 'Enter para omitir'- y llegaba vacio a la
    # planilla en casi todas las corridas, asi que no se podia cruzar una corrida con la
    # conversacion del cliente. Son 15 digitos: verificado contra la API de Intercom.
    Reset-State
    Assert-Eq 'S73 un id de 15 digitos sirve' '215475776099648' (Test-CaseIdValido -Texto '215475776099648')
    Assert-Eq 'S73 con espacios alrededor tambien' '215475776190952' (Test-CaseIdValido -Texto '  215475776190952  ')
    # Lo que el asesor tiene a mano es la URL del navegador, no el numero pelado.
    Assert-Eq 'S73 lo saca de una URL pegada' '215475755436482' (Test-CaseIdValido -Texto 'https://app.intercom.com/a/inbox/abc/inbox/conversation/215475755436482')
    Assert-Eq 'S73 y de un texto cualquiera que lo contenga' '215475776099648' (Test-CaseIdValido -Texto 'caso 215475776099648 del cliente')
    # Lo que NO puede pasar por valido.
    Assert-Eq 'S73 vacio no' '' (Test-CaseIdValido -Texto '')
    Assert-Eq 'S73 catorce digitos no' '' (Test-CaseIdValido -Texto '21547577609964')
    Assert-Eq 'S73 dieciseis digitos no' '' (Test-CaseIdValido -Texto '2154757760996489')
    Assert-Eq 'S73 el ticket de ClickUp no' '' (Test-CaseIdValido -Texto 'IC-12345')
    Assert-Eq 'S73 un numero mas largo no cuenta como id' '' (Test-CaseIdValido -Texto '99215475776099648')

    # Escenario 74 (v3.14, pedido del equipo): actualizar la Nativa con el instalador que ya esta
    # en la PC. El 03/09 la telemetria mostro la Nativa 0.0.18 en 10 de 24 corridas y solo 6 con la
    # 0.0.37 firmada. La regla: solo si el instalador declara una version MAS NUEVA.
    Reset-State
    $u74a = Test-NativaNecesitaUpdate -Instalada '0.0.18' -Disponible '0.0.37'
    Assert-Eq 'S74 con instalador mas nuevo se actualiza' $true ([bool]$u74a.actualizar)
    $u74b = Test-NativaNecesitaUpdate -Instalada '0.0.37' -Disponible '0.0.37'
    Assert-Eq 'S74 con la misma version no se toca' $false ([bool]$u74b.actualizar)
    # Lo importante: NUNCA degradar. Ya paso en este proyecto (0.0.36 -> 0.0.18).
    $u74c = Test-NativaNecesitaUpdate -Instalada '0.0.37' -Disponible '0.0.18'
    Assert-Eq 'S74 nunca degrada la Nativa' $false ([bool]$u74c.actualizar)
    # La comparacion tiene que ser numerica: como texto, '0.0.9' > '0.0.37'.
    $u74d = Test-NativaNecesitaUpdate -Instalada '0.0.9' -Disponible '0.0.37'
    Assert-Eq 'S74 compara numerico, no alfabetico' $true ([bool]$u74d.actualizar)
    # Si el instalador no dice su version, no se instala a ciegas.
    $u74e = Test-NativaNecesitaUpdate -Instalada '0.0.18' -Disponible ''
    Assert-Eq 'S74 sin version del instalador no se toca nada' $false ([bool]$u74e.actualizar)
    Assert-Eq 'S74 y dice por que' $true ([bool]([string]$u74e.motivo -match 'version legible'))
    # Sin Nativa instalada esto no es un update: es una instalacion, y va por otro camino.
    $u74f = Test-NativaNecesitaUpdate -Instalada '' -Disponible '0.0.37'
    Assert-Eq 'S74 sin Nativa instalada no es un update' $false ([bool]$u74f.actualizar)
    $u74g = Test-NativaNecesitaUpdate -Instalada '0.0.18' -Disponible 'no-es-version'
    Assert-Eq 'S74 version ilegible del instalador tampoco' $false ([bool]$u74g.actualizar)
    # Un .exe no tiene ProductVersion legible por esta via, y un archivo que no esta tampoco.
    Assert-Eq 'S74 un .exe no declara version por MSI' '' (Get-MsiProductVersion -Path 'C:\no-existe\Fudo.exe')
    Assert-Eq 'S74 un .msi inexistente no invita nada' '' (Get-MsiProductVersion -Path 'C:\no-existe\Fudo.msi')
    Assert-Eq 'S74 sin ruta no hay version' '' (Get-MsiProductVersion -Path '')
    Assert-Eq 'S74 sin instalador no se lanza nada' $true ($null -eq (Invoke-NativeInstallerFile -Path ''))

    # Escenario 75 (v3.14, pedido del equipo): una version vieja no puede correr. El 03/09 una
    # sola corrida 3.8 reprodujo cuatro bugs ya corregidos y sumo una fila a 'resueltas' con
    # resolved y needsEscalation a la vez.
    Reset-State
    function Get-PublishedVersion { param([int]$TimeoutSec = 4) return '9.9' }
    $script:VersionBloqueada = $false
    Assert-Eq 'S75 con una version publicada mas nueva no corre' $true (Test-VersionBloqueada)
    Assert-Eq 'S75 y queda registrado' $true ([bool]$script:VersionBloqueada)
    # Al dia: corre normal.
    function Get-PublishedVersion { param([int]$TimeoutSec = 4) return $script:SchemaVersion }
    $script:VersionBloqueada = $false
    Assert-Eq 'S75 al dia corre' $false (Test-VersionBloqueada)
    # Una copia MAS nueva que la publicada tampoco se bloquea (es la PC de desarrollo).
    function Get-PublishedVersion { param([int]$TimeoutSec = 4) return '0.1' }
    Assert-Eq 'S75 una copia mas nueva que la publicada corre' $false (Test-VersionBloqueada)

    # Escenario 75b: LO MAS IMPORTANTE de este cambio. Si no se pudo consultar la version
    # publicada -cliente sin internet, la red del local bloqueando GitHub- NO se bloquea: eso no
    # es 'version vieja', es 'no se sabe'. Bloquear ahi dejaria al asesor sin herramienta delante
    # del cliente, que es justo donde se usa.
    Reset-State
    function Get-PublishedVersion { param([int]$TimeoutSec = 4) return '' }
    $script:VersionCheckFallo = $false
    Assert-Eq 'S75b sin poder consultar NO se bloquea' $false (Test-VersionBloqueada)
    Assert-Eq 'S75b y queda constancia de que no se pudo' $true ([bool]$script:VersionCheckFallo)

    # Escenario 75c: -NoUpdateCheck no consulta, asi que tampoco bloquea. Es un opt-out explicito,
    # no un bypass silencioso: viaja en la telemetria para que se vea si alguien lo usa de atajo.
    Reset-State
    function Get-PublishedVersion { param([int]$TimeoutSec = 4) return '9.9' }
    Set-Variable -Name NoUpdateCheck -Value $true -Scope Script
    $script:VersionCheckOmitido = $false
    Assert-Eq 'S75c con -NoUpdateCheck no se bloquea' $false (Test-VersionBloqueada)
    Assert-Eq 'S75c y queda registrado el salteo' $true ([bool]$script:VersionCheckOmitido)
    Set-Variable -Name NoUpdateCheck -Value $false -Scope Script

    # Escenario 24 (caso real): caja tapada con miles de trabajos + cocina sana.
    # Antes se elegia la primera cola y se devolvia "todo ok" ignorando la que fallaba.
    Reset-State
    $script:PresentIdsOk = $true
    $script:Diagnostics['livePorts'] = @('USB001')      # solo cocina tiene hardware
    $script:Diagnostics['hwDeviceCount'] = 1
    function Get-Printer { @(
        [pscustomobject]@{ Name='Microsoft Print to PDF'; DriverName='Microsoft Print To PDF'; PortName='PORTPROMPT:' },
        [pscustomobject]@{ Name='CAJA';   DriverName='Generic / Text Only'; PortName='USB003' },
        [pscustomobject]@{ Name='COCINA'; DriverName='Generic / Text Only'; PortName='USB001' }
    ) }
    function Get-CimInstance {
        if ("$args" -match 'CAJA') { return [pscustomobject]@{ WorkOffline=$true;  PrinterState=0 } }
        return [pscustomobject]@{ WorkOffline=$false; PrinterState=0 }
    }
    function Get-PrintJob {
        $n=''; for ($i=0; $i -lt $args.Count; $i++) { if ("$($args[$i])" -eq '-PrinterName') { $n="$($args[$i+1])" } }
        if ($n -eq 'CAJA') { return @(1..1440 | ForEach-Object { [pscustomobject]@{ Id=$_; JobStatus='Normal'; DocumentName='node print job'; SubmittedTime=(Get-Date) } }) }
        return @()
    }
    $colas = @(Get-PrinterQueues)
    Assert-Eq 'S24 solo cuenta colas reales' 2 (@($colas).Count)
    Assert-Eq 'S24 ordena primero la que falla' 'CAJA' ([string]@($colas)[0].nombre)
    Assert-Eq 'S24 CAJA no imprime' 'no imprime' ([string]@($colas)[0].estado)
    Assert-Eq 'S24 COCINA sana' 'sana' ([string]@($colas | Where-Object { $_.nombre -eq 'COCINA' })[0].estado)
    Assert-Eq 'S24 detecta los 1440 trabajos' 1440 ([int]@($colas)[0].trabajos)
    $t24 = Resolve-TargetPrinter
    Assert-Eq 'S24 diagnostica la que falla' 'CAJA' $(if ($t24) { [string]$t24.Name } else { '' })
    Assert-Eq 'S24 avisa que hay varias' $true ([bool]((Get-CheckById 'printer.multiple') -ne $null))

    # Escenario 25: si el puerto esta vivo, esa impresora NO va a la lista de desconectadas
    Reset-State
    $script:PresentIdsOk = $true
    function Get-UsbPrintDevices {
        $script:Diagnostics['impresorasDesconectadas'] = @(
            [ordered]@{ nombre='COCINA-HW'; puerto='USB001'; instanceId='USBPRINT\A\1'; motivo='historico' },
            [ordered]@{ nombre='CAJA-HW';   puerto='USB003'; instanceId='USBPRINT\B\1'; motivo='historico' }
        )
        return @([ordered]@{ source='registry.USBPRINT'; name='COCINA-HW'; instanceId='USBPRINT\A\9'; portName='USB001'; status='enumerado'; problem=0; deteccion='interfaz USBPRINT (usbprint.sys)'; certeza='alta' })
    }
    function Get-ProblemPrinterDevices { @() }
    function Get-PrinterPort { @([pscustomobject]@{ Name='USB001'; Description='USB' }, [pscustomobject]@{ Name='USB003'; Description='USB' }) }
    function Get-Printer { @([pscustomobject]@{ Name='COCINA'; DriverName='Generic / Text Only'; PortName='USB001' }) }
    Test-Layer1a-HardwareInventory
    $off = @($script:Diagnostics['impresorasDesconectadas'])
    Assert-Eq 'S25 dedup por puerto vivo' 1 (@($off).Count)
    Assert-Eq 'S25 la que queda es la del puerto muerto' 'CAJA-HW' ([string]@($off)[0].nombre)

    # Escenario 26: el menu ofrece lo que corresponde segun lo encontrado
    Reset-State
    $base = @(Get-MenuOptions | ForEach-Object { [string]$_.k })
    Assert-Eq 'S26 siempre ofrece revisar' $true ($base -contains 'R')
    Assert-Eq 'S26 siempre ofrece buscar en red' $true ($base -contains 'N')
    Assert-Eq 'S26 siempre ofrece salir' $true ($base -contains 'S')
    Assert-Eq 'S26 sin desconexion no ofrece esperar USB' $false ($base -contains 'U')
    Assert-Eq 'S26 sin cola no ofrece limpiar' $false ($base -contains 'L')
    Add-Check -Id 'printer.disconnected' -Layer 1 -Name 'desconectada' -Status 'fail' -Plane 'hardware'
    $script:Diagnostics['colas'] = @([ordered]@{ nombre='CAJA'; puerto='USB003'; trabajos=1440; estado='no imprime' })
    $script:Diagnostics['impresorasEnRed'] = @([ordered]@{ ip='192.168.0.50'; puerto=9100; respondeEscPos=$true; tipo='impresora termica' })
    $conEstado = @(Get-MenuOptions | ForEach-Object { [string]$_.k })
    Assert-Eq 'S26 ofrece esperar el USB' $true ($conEstado -contains 'U')
    Assert-Eq 'S26 ofrece limpiar la cola' $true ($conEstado -contains 'L')
    Assert-Eq 'S26 ofrece instalar la de red' $true ($conEstado -contains 'P')

    # Escenario 27: Reset-RunState limpia el run pero conserva las colas ya creadas
    Reset-State
    [void]$script:TestPrintersCreated.Add('FUDO-TEST-USB001')
    Add-Check -Id 'x' -Layer 0 -Name 'x' -Status 'ok'
    $script:Diagnostics['algo'] = 'valor'
    Reset-RunState
    Assert-Eq 'S27 limpia los checks' 0 (@($script:Checks).Count)
    Assert-Eq 'S27 limpia diagnostics' $false ($script:Diagnostics.Contains('algo'))
    Assert-Eq 'S27 conserva las colas creadas' $true (@($script:TestPrintersCreated) -contains 'FUDO-TEST-USB001')
    $script:TestPrintersCreated = New-Object System.Collections.ArrayList

    # Escenario 28: identificacion ESC/POS contra sockets de verdad.
    # El servidor de prueba va en C#: un scriptblock casteado a Action no corre en su runspace.
    Reset-State
    if (-not ('FudoFakePrinter' -as [type])) {
        Add-Type -Language CSharp -TypeDefinition @'
using System.Net;
using System.Net.Sockets;
using System.Threading;
public class FudoFakePrinter {
    // Levanta un listener que imita una termica: contesta 1 byte de estado a DLE EOT.
    public static int Start(bool responde) {
        TcpListener l = new TcpListener(IPAddress.Loopback, 0);
        l.Start();
        int port = ((IPEndPoint)l.LocalEndpoint).Port;
        Thread t = new Thread(delegate() {
            try {
                TcpClient c = l.AcceptTcpClient();
                NetworkStream s = c.GetStream();
                byte[] b = new byte[8];
                s.Read(b, 0, 8);
                if (responde) { s.Write(new byte[] { 0x16 }, 0, 1); s.Flush(); }
                Thread.Sleep(600);
                c.Close();
            } catch { }
            try { l.Stop(); } catch { }
        });
        t.IsBackground = true;
        t.Start();
        return port;
    }
}
'@
    }
    $puertoEsc = [FudoFakePrinter]::Start($true)
    Assert-Eq 'S28 detecta el que responde como ESC/POS' $true (Test-IsEscPosDevice -Ip '127.0.0.1' -TcpPort $puertoEsc)
    $puertoMudo = [FudoFakePrinter]::Start($false)
    Assert-Eq 'S28 el que no contesta no es impresora' $false (Test-IsEscPosDevice -Ip '127.0.0.1' -TcpPort $puertoMudo -TimeoutMs 900)

    # Escenario 29: colas de red ya instaladas (para no instalar dos veces)
    Reset-State
    function Get-PrinterPort { @(
        [pscustomobject]@{ Name='IP_192.168.0.50'; PrinterHostAddress='192.168.0.50'; PortNumber=9100 },
        [pscustomobject]@{ Name='USB001'; Description='USB' }
    ) }
    function Get-Printer { @([pscustomobject]@{ Name='COMANDERA'; DriverName='Generic / Text Only'; PortName='IP_192.168.0.50' }) }
    $red = @(Get-InstalledNetworkPrinters)
    Assert-Eq 'S29 detecta 1 puerto de red' 1 (@($red).Count)
    Assert-Eq 'S29 con su IP' '192.168.0.50' ([string]@($red)[0].ip)
    Assert-Eq 'S29 y la cola que la usa' 'COMANDERA' ((@($red)[0].colas) -join ',')

    # Escenario 30: info de entorno (no debe explotar aunque no haya nada de Windows)
    Reset-State
    $env30 = $null; $err30 = ''
    try { $env30 = Get-EnvironmentInfo } catch { $err30 = $_.Exception.Message }
    Assert-Eq 'S30 entorno no explota' '' $err30
    Assert-Eq 'S30 trae la version de PowerShell' $true ([bool]([string]$env30.powershell -match '^\d'))
    Assert-Eq 'S30 tiene los campos que pide la telemetria' 'so,powershell,chrome,edge,nativaVersion,cultura,pais,paisNombre,paisProbable,zonaHoraria,redes,tipoConexionPC,esAdmin' (@($env30.Keys) -join ',')

    # Escenario 31: sin log de impresion habilitado no se afirma nada
    Reset-State
    function Get-WinEvent { throw 'log deshabilitado' }
    $h31 = Get-PrintHistory
    Assert-Eq 'S31 detecta el log deshabilitado' $false ([bool]$h31.habilitado)
    Assert-Eq 'S31 no inventa historial' 0 (@($h31.porImpresora).Count)

    # Escenario 32: con historial, se identifica a que cola le manda Fudo
    Reset-State
    function Get-PrintHistory {
        [ordered]@{ habilitado = $true; atribuible = $true; trabajos = 123; docsInformativos = 121; porImpresora = @(
            [ordered]@{ impresora='COCINA'; total=120; deFudo=118; ultimo='21/08 20:10'; ultimoDeFudo='21/08 20:10'; ejemploDoc='node print job'; docsInformativos=120 },
            [ordered]@{ impresora='HP LaserJet'; total=3; deFudo=0; ultimo='19/08 11:00'; ultimoDeFudo=''; ejemploDoc='Documento1.docx'; docsInformativos=3 }
        ) }
    }
    Test-Layer5-FudoConfig -DetectedInterface 'USB'
    $c32 = Get-CheckById 'fudo.usoReal'
    Assert-Eq 'S32 detecta la cola que usa Fudo' 'ok' ([string]$c32.status)
    Assert-Eq 'S32 la nombra' $true ([bool]($c32.name -match 'COCINA'))
    Assert-Eq 'S32 no confunde otras impresoras' $false ([bool]($c32.name -match 'LaserJet'))

    # Escenario 33: historial habilitado pero sin trabajos de Fudo => sospecha de config
    Reset-State
    function Get-PrintHistory {
        [ordered]@{ habilitado = $true; atribuible = $true; trabajos = 2; docsInformativos = 2; porImpresora = @(
            [ordered]@{ impresora='CAJA'; total=2; deFudo=0; ultimo='20/08 10:00'; ultimoDeFudo=''; ejemploDoc='Test Page'; docsInformativos=2 }
        ) }
    }
    Test-Layer5-FudoConfig -DetectedInterface 'USB'
    $c33 = Get-CheckById 'fudo.usoReal'
    Assert-Eq 'S33 marca la sospecha' 'warn' ([string]$c33.status)
    Assert-Eq 'S33 es candidata a causa raiz' $true ([bool]$c33.rootCauseCandidate)

    # Escenario 34: el POST de telemetria contra un servidor de verdad, incluido el 302
    # que hace Apps Script (que es lo que rompia el envio).
    Reset-State
    if (-not ('FudoFakeEndpoint' -as [type])) {
        Add-Type -Language CSharp -TypeDefinition @'
using System;
using System.IO;
using System.Net;
using System.Text;
using System.Threading;
public class FudoFakeEndpoint {
    public static string UltimoCuerpo = "";
    public static int Start(bool redirige) {
        HttpListener l = new HttpListener();
        int port = 0;
        // buscamos un puerto libre
        for (int p = 18500; p < 18600; p++) {
            try {
                l = new HttpListener();
                l.Prefixes.Add("http://127.0.0.1:" + p + "/exec/");
                l.Prefixes.Add("http://127.0.0.1:" + p + "/real/");
                l.Start();
                port = p;
                break;
            } catch { }
        }
        if (port == 0) { return 0; }
        HttpListener lis = l;
        int puerto = port;
        Thread t = new Thread(delegate() {
            try {
                for (int i = 0; i < 12; i++) {
                    HttpListenerContext ctx = lis.GetContext();
                    string path = ctx.Request.Url.AbsolutePath;
                    string cuerpo = new StreamReader(ctx.Request.InputStream, Encoding.UTF8).ReadToEnd();
                    byte[] resp;
                    // /exec: imita Apps Script y redirige a /real
                    if (redirige && path.StartsWith("/exec")) {
                        ctx.Response.StatusCode = 302;
                        ctx.Response.AddHeader("Location", "http://127.0.0.1:" + puerto + "/real/");
                        resp = Encoding.UTF8.GetBytes("moved");
                    } else if (ctx.Request.HttpMethod == "POST" && cuerpo.Length > 0) {
                        UltimoCuerpo = cuerpo;
                        resp = Encoding.UTF8.GetBytes("{" + (char)34 + "ok" + (char)34 + ":true}");
                    } else {
                        // POST convertido en GET por el redirect: cuerpo perdido
                        resp = Encoding.UTF8.GetBytes("{" + (char)34 + "ok" + (char)34 + ":false}");
                    }
                    ctx.Response.ContentType = "application/json";
                    ctx.Response.OutputStream.Write(resp, 0, resp.Length);
                    ctx.Response.OutputStream.Close();
                }
            } catch { }
            try { lis.Stop(); } catch { }
        });
        t.IsBackground = true;
        t.Start();
        return puerto;
    }
}
'@
    }
    $pDirecto = [int][FudoFakeEndpoint]::Start($false)
    if ($pDirecto -gt 0) {
        $r34 = Invoke-TelemetryPost -Url ("http://127.0.0.1:$pDirecto/exec/") -Body '{"schemaVersion":"2.3","status":"resolved"}'
        Assert-Eq 'S34 POST directo llega' $true ([bool]$r34.ok)
        Assert-Eq 'S34 el servidor recibio el cuerpo' $true ([bool]([FudoFakeEndpoint]::UltimoCuerpo -match 'schemaVersion'))
    }
    $pRedir = [int][FudoFakeEndpoint]::Start($true)
    if ($pRedir -gt 0) {
        [FudoFakeEndpoint]::UltimoCuerpo = ''
        $r35 = Invoke-TelemetryPost -Url ("http://127.0.0.1:$pRedir/exec/") -Body '{"schemaVersion":"2.3","status":"resolved","caseId":"CONREDIRECT"}'
        Assert-Eq 'S34 sobrevive al 302 de Apps Script' $true ([bool]$r35.ok)
        Assert-Eq 'S34 el cuerpo no se pierde en el redirect' $true ([bool]([FudoFakeEndpoint]::UltimoCuerpo -match 'CONREDIRECT'))
    }

    # Escenario 35: la opcion de actualizar aparece solo si hay version nueva
    Reset-State
    $script:UpdateNote = ''
    Assert-Eq 'S35 sin novedad no ofrece actualizar' $false (@(Get-MenuOptions | ForEach-Object { [string]$_.k }) -contains 'A')
    $script:UpdateNote = 'Hay una version mas nueva publicada: 9.9'
    Assert-Eq 'S35 con novedad ofrece actualizar' $true (@(Get-MenuOptions | ForEach-Object { [string]$_.k }) -contains 'A')
    $script:UpdateNote = ''

    # Escenario 36: clasificacion del estado en que se encuentra la PC
    Reset-State
    Assert-Eq 'S36 PC sin nada' 'nunca_hubo_impresora_en_esta_pc' ([string](Get-ArrivalScenario).escenario)

    Reset-State
    $script:Diagnostics['colas'] = @(
        [ordered]@{ nombre='COCINA'; puerto='USB001'; score=0;  estado='sana' },
        [ordered]@{ nombre='CAJA';   puerto='USB003'; score=95; estado='no imprime' })
    Assert-Eq 'S36 una anda y otra no' 'una_funciona_y_otra_no' ([string](Get-ArrivalScenario).escenario)
    Assert-Eq 'S36 cuenta las sanas' 1 ([int](Get-ArrivalScenario).colasSanas)

    Reset-State
    $script:Diagnostics['colas'] = @([ordered]@{ nombre='CAJA'; puerto='USB003'; score=95; estado='no imprime' })
    $script:Diagnostics['impresorasDesconectadas'] = @([ordered]@{ nombre='Xprinter'; puerto='USB003' })
    Assert-Eq 'S36 estaba instalada y dejo de andar' 'estaba_instalada_y_dejo_de_funcionar' ([string](Get-ArrivalScenario).escenario)

    Reset-State
    $script:Diagnostics['colas'] = @([ordered]@{ nombre='CAJA'; puerto='USB002'; score=40; estado='no imprime' })
    $script:Diagnostics['historialImpresion'] = [ordered]@{ habilitado = $true; porImpresora = @() }
    Assert-Eq 'S36 instalada pero nunca imprimio' 'instalada_pero_nunca_imprimio' ([string](Get-ArrivalScenario).escenario)
    Assert-Eq 'S36 uso previo sin registro' 'no_hay_registro_de_impresion' ([string](Get-ArrivalScenario).usoPrevio)

    Reset-State
    $script:Diagnostics['colas'] = @([ordered]@{ nombre='CAJA'; puerto='USB002'; score=40; estado='no imprime' })
    $script:Diagnostics['historialImpresion'] = [ordered]@{ habilitado = $false; porImpresora = @() }
    Assert-Eq 'S36 log apagado no afirma nada' 'desconocido' ([string](Get-ArrivalScenario).usoPrevio)

    Reset-State
    $script:Diagnostics['colas'] = @([ordered]@{ nombre='COCINA'; puerto='USB001'; score=0; estado='sana' })
    Assert-Eq 'S36 todo funciona' 'todas_funcionan' ([string](Get-ArrivalScenario).escenario)

    Reset-State
    $script:Diagnostics['hwDeviceCount'] = 1
    Assert-Eq 'S36 hardware sin instalar' 'hardware_conectado_sin_instalar' ([string](Get-ArrivalScenario).escenario)

    # Escenario 37: sin humano al lado, la prueba de impresion NO puede afirmar que salio papel
    Reset-State
    Assert-Eq 'S37 sin consola no confirma' $true ($null -eq (Confirm-PaperCameOut -Printer 'CAJA'))

    # Escenario 38: impresora presente pero sin puerto USB asignado por Windows.
    # (device enumerado OK, ningun nodo USBPRINT con PortName) => no se reasignan puertos
    # a ciegas: se pide replug / instalacion del driver que crea el puerto.
    Reset-State
    function Get-UsbPrintDevices {
        @([ordered]@{ source='Win32_PnPEntity'; name='Epson Compatibilidad con impresoras USB'
                      instanceId='USB\VID_04B8&PID_0E28\583741540123650000'; portName=''; status='OK'; problem=0
                      deteccion='driver usbprint'; certeza='alta' })
    }
    function Get-ProblemPrinterDevices { @() }
    function Get-PrinterPort { @([pscustomobject]@{ Name='USB001'; Description='Puerto de impresora virtual para USB' },
                                 [pscustomobject]@{ Name='USB002'; Description='Puerto de impresora virtual para USB' }) }
    function Get-Printer { @([pscustomobject]@{ Name='POS-80'; DriverName='Generic / Text Only'; PortName='USB002' }) }
    # el replug por software no consigue puerto: queda como fail con la guia manual
    function Repair-BindUsbPort { param([string[]]$InstanceIds) @{ puertos = @(); nota = 'no se pudo reiniciar el device' } }
    $err38 = ''
    try { Test-Layer1a-HardwareInventory } catch { $err38 = $_.Exception.Message }
    Assert-Eq 'S38 inventario no explota' '' $err38
    Assert-Eq 'S38 hardware detectado' 'ok' (Get-CheckById 'hw.deviceConnected').status
    Assert-Eq 'S38 avisa que no hay puerto' 'fail' (Get-CheckById 'hw.noPortBound').status
    Assert-Eq 'S38 es causa raiz' $true (Get-CheckById 'hw.noPortBound').rootCauseCandidate
    Assert-Eq 'S38 explica los puertos huerfanos' $true ([bool]((Get-CheckById 'hw.noPortBound').recommendation -match 'huerfanos'))

    # Escenario 43: el replug por software SI consigue puerto => se levanta la cola sola,
    # con el driver del fabricante si ya esta en Windows (decision del 25/08).
    Reset-State
    function Repair-BindUsbPort { param([string[]]$InstanceIds) @{ puertos = @('USB005'); nota = 'device reiniciado' } }
    # el driver de Epson ya esta en Windows: es el que hay que preferir
    function Get-DriverPlan { param($Identity) @{ kind='oem_instalado'; driverName='Epson ESC/P-R V4 Class Driver'; note='ya esta instalado' } }
    $script:__colaCreada = ''
    function New-FudoPrinterQueue {
        param([string]$PortName, [string]$PreferDriver = '', [string]$Name = '')
        $script:__colaCreada = $PreferDriver
        @{ ok = $true; name = 'FUDO-USB005'; driver = $PreferDriver; nota = 'cola creada' }
    }
    $null = Test-Layer1a-HardwareInventory
    Assert-Eq 'S43 el puerto aparece y se crea la cola' 'fixed' (Get-CheckById 'hw.noPortBound').status
    Assert-Eq 'S43 usa el driver de fabricante ya instalado' 'Epson ESC/P-R V4 Class Driver' $script:__colaCreada
    Assert-Eq 'S43 no manda a desenchufar nada' $false ([bool]((Get-CheckById 'hw.noPortBound').recommendation -match 'desenchufar'))

    # Escenario 45: si el puerto ya tiene una cola del cliente, se adopta (no se crea otra).
    # Se vieron dos PCs con FUDO-USB001 conviviendo con la cola real en el mismo USB001.
    Reset-State
    function Repair-BindUsbPort { param([string[]]$InstanceIds) @{ puertos = @('USB001'); nota = 'device reiniciado' } }
    function Get-DriverPlan { param($Identity) @{ kind='oem_instalado'; driverName='Epson ESC/P-R V4 Class Driver'; note='ya esta' } }
    function Find-QueueForPort { param([string]$PortName) [pscustomobject]@{ Name = 'Impresora'; PortName = $PortName; DriverName = 'Generic / Text Only' } }
    $script:__creoCola = $false
    function New-FudoPrinterQueue { param([string]$PortName, [string]$PreferDriver = '', [string]$Name = '') $script:__creoCola = $true; @{ ok = $true; name = 'FUDO-USB001'; driver = ''; nota = '' } }
    function Get-UsbPrintDevices {
        @([ordered]@{ source='Win32_PnPEntity'; name='Epson Compatibilidad con impresoras USB'
                      instanceId='USB\VID_04B8&PID_0E28\58374154'; portName=''; status='OK'; problem=0
                      deteccion='driver usbprint'; certeza='alta' })
    }
    function Get-ProblemPrinterDevices { @() }
    function Get-PrinterPort { @([pscustomobject]@{ Name='USB001'; Description='Puerto de impresora virtual para USB' }) }
    function Get-Printer { @([pscustomobject]@{ Name='Impresora'; DriverName='Generic / Text Only'; PortName='USB001' }) }
    $null = Test-Layer1a-HardwareInventory
    Assert-Eq 'S45 no crea una cola paralela' $false $script:__creoCola
    Assert-Eq 'S45 adopta la que ya estaba' $true ([bool]((Get-CheckById 'hw.noPortBound').recommendation -match 'NO se creo ninguna cola nueva'))
    Assert-Eq 'S45 queda como reparado' 'fixed' (Get-CheckById 'hw.noPortBound').status

    # Escenario 46: ante empate de score, la cola del cliente va antes que la del motor
    Reset-State
    function Get-Printer {
        @([pscustomobject]@{ Name='FUDO-TEST-USB001'; DriverName='Generic / Text Only'; PortName='USB001' },
          [pscustomobject]@{ Name='CAJA';             DriverName='Generic / Text Only'; PortName='USB001' })
    }
    function Get-PrintJob { @() }
    function Test-PortHasLiveDevice { param([string]$PortName) $true }
    $q46 = @(Get-PrinterQueues)
    Assert-Eq 'S46 primero la del cliente' 'CAJA' ([string](@($q46)[0].nombre))
    Assert-Eq 'S46 marca la propia como de prueba' $true ([bool](@($q46 | Where-Object { $_.nombre -eq 'FUDO-TEST-USB001' })[0].esDePrueba))

    # Escenario 44: un puerto WSD no es USB (antes la capa 3 decia 'Puerto USB OK')
    Reset-State
    Assert-Eq 'S44 detecta WSD' 'WSD' (Get-DetectedInterface -Printer ([pscustomobject]@{ PortName = 'WSD-fedd4304-37e2-467d-91c1-bdce0e2ec1e9' }))
    Assert-Eq 'S44 USB sigue siendo USB' 'USB' (Get-DetectedInterface -Printer ([pscustomobject]@{ PortName = 'USB001' }))
    Assert-Eq 'S44 IP sigue siendo Ethernet' 'Ethernet' (Get-DetectedInterface -Printer ([pscustomobject]@{ PortName = '192.168.1.50' }))
    $script:Diagnostics['hwDeviceCount'] = 1
    Test-Layer3-WsdPort -Printer ([pscustomobject]@{ Name = 'EPSON L5590 Series'; PortName = 'WSD-fedd4304'; DriverName = 'Microsoft IPP Class Driver' })
    Assert-Eq 'S44 avisa el desajuste cola de red / hardware USB' 'warn' (Get-CheckById 'conn.portMismatch').status
    Assert-Eq 'S44 es candidata a causa raiz' $true (Get-CheckById 'conn.portMismatch').rootCauseCandidate

    # Escenario 41: el motor no se diagnostica a si mismo.
    Reset-State
    $script:Diagnostics['colas'] = @(
        [ordered]@{ nombre='FUDO-TEST-USB001'; puerto='USB001'; score=0; estado='sana'; esDePrueba=$true },
        [ordered]@{ nombre='CAJA';             puerto='USB002'; score=95; estado='no imprime'; esDePrueba=$false }
    )
    $script:Diagnostics['historialImpresion'] = [ordered]@{ habilitado = $true; porImpresora = @() }
    $esc41 = Get-ArrivalScenario
    Assert-Eq 'S41 la cola del motor no cuenta como sana' $false ([bool]([string]$esc41.escenario -eq 'una_funciona_y_otra_no'))
    Assert-Eq 'S41 solo cuenta las colas del cliente' 1 ([int]$esc41.colasTotales)

    # Escenario 42: los tickets del propio motor no son historial del local
    Reset-State
    Assert-Eq 'S42 reconoce su propio ticket' $true ([bool]('Fudo Print Doctor Test' -match $script:TestDocRx))
    Assert-Eq 'S42 no confunde una comanda' $false ([bool]('node print job' -match $script:TestDocRx))
    Assert-Eq 'S42 reconoce sus colas' $true ([bool]('FUDO-TEST-USB001' -match $script:TestPrinterRx))
    Assert-Eq 'S42 no confunde una cola del cliente' $false ([bool]('CAJA' -match $script:TestPrinterRx))

    # Escenario 40: el menu no se cierra solo. Enter pelado vuelve a preguntar (antes salia),
    # y "no hay teclado" es un caso distinto de "no escribio nada".
    Reset-State
    $mk = @('R','T','D','S')
    Assert-Eq 'S40 Enter no cierra el menu' '?' (Resolve-MenuChoice -Raw '' -Keys $mk)
    Assert-Eq 'S40 espacios tampoco' '?' (Resolve-MenuChoice -Raw '   ' -Keys $mk)
    Assert-Eq 'S40 opcion valida' 'T' (Resolve-MenuChoice -Raw 't' -Keys $mk)
    Assert-Eq 'S40 opcion invalida' '?' (Resolve-MenuChoice -Raw 'z' -Keys $mk)
    Assert-Eq 'S40 sin teclado se distingue' 'NOKEY' (Resolve-MenuChoice -Raw $null -Keys $mk)
    Assert-Eq 'S40 salir sigue saliendo' 'S' (Resolve-MenuChoice -Raw 's' -Keys $mk)

    # Escenario 39: descarta impresoras de red (WSD/IPP) del inventario de hardware USB
    Reset-State
    $verdictWsd = Test-IsPrinterDevice -Name 'Microsoft IPP Class Driver' -InstanceId 'SWD\PRINTENUM\WSD-442FB327' -PnpClass 'Printer' -Service '' -CompatibleIds @()
    Assert-Eq 'S39 la clase Printer sola la daba por USB' $true ([bool]$verdictWsd.isPrinter)

    # Escenario 76b: la rama que se caia -el corte por modo, que es condicional y por eso no
    # aparecio en las otras corridas 3.14- tiene que armar su resumen sin explotar.
    Reset-State
    $script:AbortByMode = $true
    $modoAntes76 = [string]$script:RunMode
    $script:RunMode = 'Red'
    Add-Check -Id 'printer.modeFilter' -Layer 1 -Name 'No hay impresoras de red instaladas' -Status 'warn' -Plane 'os' `
        -Evidence @{ instaladas = @('COCINA [USB001]'); continuoIgual = $false }
    Add-Check -Id 'hw.noPortBound' -Layer 1 -Name 'Windows no le asigno puerto' -Status 'fixed' -Plane 'os'
    $err76 = ''
    $txt76 = ''
    try { $txt76 = ((Build-HumanSummary -Diag (Resolve-Diagnosis) -DetectedInterface '') -join ' ') } catch { $err76 = [string]$_.Exception.Message }
    $script:RunMode = $modoAntes76
    Assert-Eq 'S76 el resumen del corte por modo no explota' '' $err76
    Assert-Eq 'S76 y explica que no se reviso nada' $true ([bool]($txt76 -match 'NO SE REVISO NADA'))
    Assert-Eq 'S76 y lista lo que si habia instalado' $true ([bool]($txt76 -match 'USB001'))

    # Escenario 77 (v3.15): el historial de impresion no puede atribuir nada.
    # Telemetria del 04/09: deFudo = 0 en 146 de 146 entradas de 229 corridas, y los unicos
    # nombres de documento que Windows reporta son los genericos del spooler. El motor concluia
    # "Fudo no esta mandando comandas" -como causa raiz- de una ausencia de dato.
    Reset-State
    Assert-Eq 'S77 el nombre generico en es no dice nada' $true (Test-IsGenericDocName -Doc 'Imprimir documento')
    Assert-Eq 'S77 ni el de en' $true (Test-IsGenericDocName -Doc 'Print Document')
    Assert-Eq 'S77 ni el de pt' $true (Test-IsGenericDocName -Doc 'Documento de Impressao')
    Assert-Eq 'S77 ni un documento sin nombre' $true (Test-IsGenericDocName -Doc '')
    Assert-Eq 'S77 un nombre real si dice algo' $false (Test-IsGenericDocName -Doc 'Documento1.docx')
    Assert-Eq 'S77 y el de la Nativa tambien' $false (Test-IsGenericDocName -Doc 'node print job')

    # La cola de prueba del propio motor no puede entrar al historial ni cuando Windows le pone
    # el nombre generico al documento (40 de las 146 entradas del 04/09 eran FUDO-TEST-*).
    # Ojo: S33 dejo un mock de Get-PrintHistory en scope. Se saca el mock local para llegar a la
    # funcion de verdad, que es la que se quiere medir aca.
    Reset-State
    Remove-Item Function:\Get-PrintHistory -ErrorAction SilentlyContinue
    function Get-WinEvent {
        param($ListLog, $LogName, $MaxEvents, $ErrorAction)
        if ($ListLog) { return [pscustomobject]@{ IsEnabled = $true } }
        $ev = { param($d, $p) [pscustomobject]@{ Id = 307; TimeCreated = (Get-Date '2026-09-03 20:09:00')
                                                 Properties = @(@{Value=1}, @{Value=$d}, @{Value='u'}, @{Value='pc'}, @{Value=$p}) } }
        return @(
            (& $ev 'Imprimir documento' 'FUDO-TEST-USB009'),
            (& $ev 'Imprimir documento' 'POS-80C'),
            (& $ev 'node print job'     'POS-80C')
        )
    }
    $h77 = Get-PrintHistory
    Assert-Eq 'S77c la cola de prueba del motor no entra al historial' 1 (@($h77.porImpresora).Count)
    Assert-Eq 'S77c ni con nombre de documento generico' $false ([bool]((@($h77.porImpresora | ForEach-Object { [string]$_.impresora }) -join '|') -match 'FUDO-TEST'))
    Assert-Eq 'S77c el trabajo con nombre util se cuenta' 1 ([int]$h77.docsInformativos)
    Assert-Eq 'S77c y con eso el historial si atribuye' $true ([bool]$h77.atribuible)
    Assert-Eq 'S77c la comanda de la Nativa cuenta como de Fudo' 1 ([int]@($h77.porImpresora)[0].deFudo)
    Assert-Eq 'S77c y el generico suma al total igual' 2 ([int]@($h77.porImpresora)[0].total)

    # Historial con TODOS los nombres genericos: no se afirma nada y no es causa raiz.
    Reset-State
    function Get-PrintHistory {
        [ordered]@{ habilitado = $true; atribuible = $false; trabajos = 25; docsInformativos = 0; porImpresora = @(
            [ordered]@{ impresora='POS-80C'; total=25; deFudo=0; ultimo='03/09 20:09'; ultimoDeFudo=''; ejemploDoc='Imprimir documento'; docsInformativos=0 }
        ) }
    }
    Test-Layer5-FudoConfig -DetectedInterface 'USB'
    $c77 = Get-CheckById 'fudo.usoReal'
    Assert-Eq 'S77 no afirma que Fudo no mando comandas' $false ([bool]([string]$c77.name -match 'Ninguna cola recibio'))
    Assert-Eq 'S77 dice que no se puede saber' $true ([bool]([string]$c77.name -match 'No se puede saber'))
    Assert-Eq 'S77 y no es causa raiz' $false ([bool]$c77.rootCauseCandidate)
    Assert-Eq 'S77 no lo carga como config de Fudo' 'os' ([string]$c77.plane)
    # El estado del ultimo tramo tiene que ser el nuevo, no 'sin_comandas'.
    Add-Check -Id 'hw.testprint' -Layer 4 -Name 'Salio el papel' -Status 'ok' -Plane 'hardware'
    $d77 = Resolve-Diagnosis
    Assert-Eq 'S77 el estado es no_atribuible' 'no_atribuible' ([string]$d77.fudoUsoEstado)
    Assert-Eq 'S77 no se declara que Fudo no imprime' $false ([bool]$d77.fudoSinUso)
    Assert-Eq 'S77 cierra igual, que es lo que el motor arregla' $true ([bool]$d77.resolved)
    Assert-Eq 'S77 pero no con confianza alta' 'medium' ([string]$d77.confidence)
    Assert-Eq 'S77 y queda marcado como cierre sin verificar Fudo' $true ([bool]$d77.cierreSinVerificarFudo)
    Assert-Eq 'S77 el asesor lee que falta ese tramo' $true ([bool](((Build-HumanSummary -Diag $d77 -DetectedInterface 'USB') -join ' ') -match 'FALTA'))

    # Con al menos un nombre util y ninguna comanda de Fudo, la conclusion de antes sigue valiendo.
    Reset-State
    function Get-PrintHistory {
        [ordered]@{ habilitado = $true; atribuible = $true; trabajos = 2; docsInformativos = 2; porImpresora = @(
            [ordered]@{ impresora='CAJA'; total=2; deFudo=0; ultimo='20/08 10:00'; ultimoDeFudo=''; ejemploDoc='Presupuesto.pdf'; docsInformativos=2 }
        ) }
    }
    Test-Layer5-FudoConfig -DetectedInterface 'USB'
    Assert-Eq 'S77b con nombres utiles si se puede concluir' $true ([bool]([string](Get-CheckById 'fudo.usoReal').name -match 'Ninguna cola recibio'))
    Assert-Eq 'S77b y vuelve a ser candidata a causa raiz' $true ([bool](Get-CheckById 'fudo.usoReal').rootCauseCandidate)

    # Escenario 78 (v3.15, caso de una asesora reproducido en telemetria): el motor ejecuto
    # nativa.update_local dos veces, la version no se movio de la 0.0.18, no reporto ninguna
    # reparacion y el check quedo con el MISMO texto que cuando no se intenta nada. La persona lo
    # intento tres veces y termino reinstalando a mano.
    Reset-State
    function Find-LocalNativeInstaller { 'C:\Users\test\Desktop\FudoNativa.msi' }
    function Get-MsiProductVersion { param($Path) '0.0.27' }
    function Find-FudoNativeInstall { [ordered]@{ found = $true; paths = @() } }
    function Invoke-NativeInstallerFile { param($Path, $ExtraArgs) 1603 }
    function Get-NativaVersionState { param($Install) [ordered]@{ version = '0.0.18'; firmada = $false } }
    function Start-Sleep { param($Seconds) }
    $u78 = Update-FudoNativeFromLocal -Instalada '0.0.18' -Corriendo $true
    Assert-Eq 'S78 se intento' $true ([bool]$u78.intento)
    Assert-Eq 'S78 y no subio' $false ([bool]$u78.subio)
    Assert-Eq 'S78 el codigo de salida del instalador queda registrado' 1603 ([int]$u78.exitCode)
    Assert-Eq 'S78 y hay un motivo para mostrar' $true ([bool]([string]$u78.porQueNo -match '1603'))
    # El instalador que hay en la PC es mas nuevo que el instalado pero sigue por debajo de la
    # firmada: aunque tome, el antivirus sigue siendo un tema.
    Assert-Eq 'S78 avisa que el destino sigue sin firmar' $true ([bool]$u78.quedaSinFirmar)

    # El instalador dice que anduvo y la version no cambia: tampoco puede pasar por exito.
    Reset-State
    function Invoke-NativeInstallerFile { param($Path, $ExtraArgs) 0 }
    $u78b = Update-FudoNativeFromLocal -Instalada '0.0.18' -Corriendo $true
    Assert-Eq 'S78b sin cambio de version no es exito' $false ([bool]$u78b.subio)
    Assert-Eq 'S78b y el motivo apunta a la Nativa en uso' $true ([bool]([string]$u78b.porQueNo -match 'corriendo'))

    # Cuando si sube, no se inventa ningun motivo.
    Reset-State
    function Get-NativaVersionState { param($Install) [ordered]@{ version = '0.0.27'; firmada = $false } }
    $u78c = Update-FudoNativeFromLocal -Instalada '0.0.18'
    Assert-Eq 'S78c la actualizacion que toma se reporta como tal' $true ([bool]$u78c.subio)
    Assert-Eq 'S78c y sin motivo de falla' '' ([string]$u78c.porQueNo)

    # No se intento: el motivo tiene que seguir siendo el de la decision, no una falla.
    Reset-State
    function Find-LocalNativeInstaller { '' }
    $u78d = Update-FudoNativeFromLocal -Instalada '0.0.18'
    Assert-Eq 'S78d sin instalador no se intento nada' $false ([bool]$u78d.intento)
    Assert-Eq 'S78d y lo dice' $true ([bool]([string]$u78d.motivo -match 'no hay instalador'))

    # Y si el armado del resumen se cae igual, el diagnostico no se pierde: es presentacion.
    Reset-State
    function Build-HumanSummary { param($Diag, $DetectedInterface) throw 'falla de presentacion' }
    $txt79 = ((Build-HumanSummarySafe -Diag ([ordered]@{ resolved = $false; rootCause = 'Puerto USB desmapeado'
                                                          nextActions = @([ordered]@{ owner = 'asesor'; do = 'Reconectar el USB' }) }) `
                                       -DetectedInterface 'USB') -join ' ')
    Assert-Eq 'S79 un fallo del resumen no se lleva la causa' $true ([bool]($txt79 -match 'Puerto USB desmapeado'))
    Assert-Eq 'S79 ni lo que hay que hacer' $true ([bool]($txt79 -match 'Reconectar el USB'))
    Assert-Eq 'S79 y queda registrado como error del motor' 1 (@($script:Errors | Where-Object { [string]$_.step -eq 'summary.build' }).Count)
    # Este mock hace explotar el resumen a proposito: si queda en scope, se lleva puesto a
    # cualquier escenario posterior que lo use, y la excepcion sale del self-test sin dar ni el
    # conteo final. Se saca aca mismo.
    Remove-Item Function:\Build-HumanSummary -ErrorAction SilentlyContinue

    # Escenario 80 (v3.15): las dos reparaciones que llamaban a cmdlets que no existen. Las
    # encontro el escaneo de S76, no la telemetria: las dos estaban dentro de un try/catch, asi
    # que no rompian nada, simplemente no hacian nada. Las dos viven en caminos que el proyecto
    # nunca pudo probar contra hardware real (destrabar la cola antes de la prueba fisica y el
    # replug por software), asi que el silencio no se notaba.
    Reset-State
    $script:llamadas80 = New-Object System.Collections.ArrayList
    function Get-Printer { param($Name, $ErrorAction) [pscustomobject]@{ Name = 'COCINA'; Paused = $true; WorkOffline = $false } }
    function Get-CimInstance { param($ClassName, $Filter, $ErrorAction) [pscustomobject]@{ Name = 'COCINA'; PrinterState = 1; WorkOffline = $false } }
    function Invoke-CimMethod { param($InputObject, $MethodName, $ErrorAction) [void]$script:llamadas80.Add('cim:' + $MethodName); [pscustomobject]@{ ReturnValue = 0 } }
    function Get-PrintJob { param($PrinterName, $ErrorAction) @() }
    $h80 = @(Unblock-QueueForTest -Printer ([pscustomobject]@{ Name = 'COCINA' }))
    Assert-Eq 'S80 una cola pausada se reanuda de verdad' $true ([bool]((@($h80) -join '|') -match 'se reanudo la cola'))
    Assert-Eq 'S80 y por la via que existe (Win32_Printer.Resume)' 'cim:Resume' ((@($script:llamadas80) -join ','))

    # El replug por software: deshabilitar y volver a habilitar, en ese orden.
    # Escenarios anteriores dejaron un mock de Repair-BindUsbPort en scope -y devuelve justo
    # 'device reiniciado', asi que sin sacarlo este escenario se aprobaba contra el mock.
    Reset-State
    Remove-Item Function:\Repair-BindUsbPort -ErrorAction SilentlyContinue
    $script:llamadas80 = New-Object System.Collections.ArrayList
    function Write-StepDetail { param($T) }
    function Start-Sleep { param($Seconds, $Milliseconds) }
    function Disable-PnpDevice { param($InstanceId, $Confirm, $ErrorAction) [void]$script:llamadas80.Add('disable') }
    function Enable-PnpDevice { param($InstanceId, $Confirm, $ErrorAction) [void]$script:llamadas80.Add('enable') }
    function Get-PrinterPort { param($ErrorAction) @([pscustomobject]@{ Name = 'USB001' }) }
    $r80 = Repair-BindUsbPort -InstanceIds @('USB\VID_04B8&PID_0E15\ABC')
    Assert-Eq 'S80 el replug apaga y prende el dispositivo' 'disable,enable' ((@($script:llamadas80) -join ','))
    Assert-Eq 'S80 y lo reporta como reiniciado' $true ([bool]([string]$r80.nota -match 'device reiniciado'))
    Assert-Eq 'S80 y devuelve el puerto que aparecio' 'USB001' ([string]@($r80.puertos)[0])

    # Si el enable falla, la impresora no puede quedar deshabilitada: se reintenta habilitarla.
    Reset-State
    $script:llamadas80 = New-Object System.Collections.ArrayList
    function Enable-PnpDevice {
        param($InstanceId, $Confirm, $ErrorAction)
        [void]$script:llamadas80.Add('enable')
        if ($ErrorAction -eq 'Stop') { throw 'acceso denegado' }
    }
    $r80b = Repair-BindUsbPort -InstanceIds @('USB\VID_04B8&PID_0E15\ABC')
    Assert-Eq 'S80b si el enable falla se reintenta habilitar' 'disable,enable,enable' ((@($script:llamadas80) -join ','))
    Assert-Eq 'S80b y queda dicho que no se pudo' $true ([bool]([string]$r80b.nota -match 'no se pudo reiniciar el device'))

    # ---------------------------------------------------------------------
    # Escenarios 81-88 (v3.16): la impresora de red que esta en OTRA subred.
    # El caso que el motor no podia ver: una comandera con IP de fabrica en un local cuyo router
    # reparte otra subred esta en el mismo cable, pero el PC no tiene direccion ahi y no le puede
    # hablar. El camino manual era desenchufar el cable del router (deja al cliente sin internet
    # y al asesor sin asistencia remota) o pedir otra notebook.
    # ---------------------------------------------------------------------

    # Escenario 81: que subredes vale la pena revisar, y en que orden.
    Reset-State
    function Get-LocalSubnetPrefixes { @('192.168.0') }
    function Get-InstalledNetworkPrinters {
        @(
            [ordered]@{ ip = '192.168.1.21'; puertoTcp = 9100; puertoWindows = 'IP_192.168.1.21'; colas = @('COCINA') },
            [ordered]@{ ip = '192.168.0.30'; puertoTcp = 9100; puertoWindows = 'IP_192.168.0.30'; colas = @('CAJA') }
        )
    }
    $c81 = @(Get-PrinterSubnetCandidates -Max 3)
    # Primero la que tiene evidencia dura: hay una cola apuntando ahi.
    Assert-Eq 'S81 primero la subred de una cola que apunta afuera' '192.168.1' ([string]@($c81)[0].prefijo)
    Assert-Eq 'S81 y dice por que' $true ([bool]([string]@($c81)[0].motivo -match 'cola de Windows'))
    # La subred del PC no se propone: esa ya la barre el camino normal.
    Assert-Eq 'S81 no propone la subred del propio PC' $false ([bool]((@($c81 | ForEach-Object { [string]$_.prefijo }) -join '|') -match '192\.168\.0'))
    # Y despues los defaults de fabrica.
    Assert-Eq 'S81 despues los defaults de fabrica' $true ([bool]([string]@($c81)[1].motivo -match 'fabrica'))
    Assert-Eq 'S81 respeta el maximo' 3 (@($c81).Count)

    # Escenario 82: la IP que se le propone al asesor tiene que estar libre de verdad.
    # Proponer una ocupada crearia un conflicto de IP, que es uno de los problemas que venimos a
    # resolver (fue el pedido original del canal).
    Reset-State
    function Get-NetIPAddress { param($AddressFamily, $ErrorAction) @([pscustomobject]@{ IPAddress = '192.168.0.10'; InterfaceIndex = 12 }) }
    function Get-InstalledNetworkPrinters { @([ordered]@{ ip = '192.168.0.202'; colas = @('CAJA') }) }
    function Test-IpAlive { param($Ip, $TimeoutMs) return ([string]$Ip -in @('192.168.0.200','192.168.0.201')) }
    Assert-Eq 'S82 saltea las que responden' '192.168.0.203' (Get-FreeIpInSubnet -Prefix '192.168.0')
    Assert-Eq 'S82 y tampoco propone la del gateway' '192.168.0.204' (Get-FreeIpInSubnet -Prefix '192.168.0' -Evitar @('192.168.0.203'))
    function Test-IpAlive { param($Ip, $TimeoutMs) $true }
    Assert-Eq 'S82 si todas responden no inventa ninguna' '' (Get-FreeIpInSubnet -Prefix '192.168.0')

    # Escenario 83: la herramienta de la marca. Los nombres salen del empaquetado real que usa el
    # equipo (Delitools > NetConfigTools): ninguno se llama como uno esperaria.
    Reset-State
    function Test-PathExists { param($Path) return ([string]$Path -match 'EPSON') }
    $t83 = Find-NetConfigTool -Marca 'Epson'
    Assert-Eq 'S83 encuentra la de Epson' $true ([bool]$t83.encontrada)
    Assert-Eq 'S83 y no se llama EpsonNetConfig' 'ENConfig.exe' ([string]$t83.exe)
    Assert-Eq 'S83 la busca en la instalacion de Delitools' $true ([bool]([string]$t83.ruta -match 'Delitools'))
    Assert-Eq 'S83 dentro de NetConfigTools' $true ([bool]([string]$t83.ruta -match 'NetConfigTools'))
    # Una marca cuya carpeta no esta: se sabe que herramienta hace falta, aunque no este.
    $t83b = Find-NetConfigTool -Marca 'Bixolon'
    Assert-Eq 'S83b sin la carpeta no la da por encontrada' $false ([bool]$t83b.encontrada)
    Assert-Eq 'S83b pero dice cual hace falta' 'NetConfiguration.exe' ([string]$t83b.exe)
    # El ejecutable de SAM4S tiene un & en el nombre: si se pierde, no se abre nada.
    Assert-Eq 'S83c el nombre con & se conserva' 'GIANT&GCUBE Tool.exe' ([string](Find-NetConfigTool -Marca 'Sam4s').exe)
    # 3nStar y XPrinter comparten la herramienta OEM, pero cada una tiene su carpeta.
    Assert-Eq 'S83d 3nStar tiene su carpeta' '3NSTAR' ([string](Find-NetConfigTool -Marca '3nStar').carpeta)
    Assert-Eq 'S83d y XPrinter la suya' 'XPRINTER' ([string](Find-NetConfigTool -Marca 'XPrinter').carpeta)
    # Una marca que no esta en la tabla no puede inventar una herramienta.
    Assert-Eq 'S83e una marca desconocida no trae herramienta' '' ([string](Find-NetConfigTool -Marca 'Rongta').exe)

    # Escenario 84: LA instruccion unica. El asesor no tiene que averiguar nada.
    Reset-State
    function Get-NetIPAddress { param($AddressFamily, $ErrorAction) @([pscustomobject]@{ IPAddress = '192.168.0.10'; InterfaceIndex = 12 }) }
    function Get-InstalledNetworkPrinters { @() }
    function Test-IpAlive { param($Ip, $TimeoutMs) $false }
    function Test-PathExists { param($Path) return ([string]$Path -match 'EPSON') }
    $hall84 = [ordered]@{ ip = '192.168.1.100'; respondeEscPos = $true; mac = '00-26-ab-11-22-33'
                          oui = '00-26-ab'; marca = 'Epson'; modelo = 'TM-T20III'; subred = '192.168.1' }
    $p84 = Resolve-NetworkPrinterPlan -Encontrada $hall84 -PrefijoPc '192.168.0' -Gateway '192.168.0.1'
    Assert-Eq 'S84 hay plan' $true ([bool]$p84.hay)
    Assert-Eq 'S84 dice donde esta la impresora' '192.168.1.100' ([string]$p84.ip)
    Assert-Eq 'S84 propone una IP en la red del PC' $true ([bool]([string]$p84.ipSugerida -match '^192\.168\.0\.'))
    Assert-Eq 'S84 con su mascara' '255.255.255.0' ([string]$p84.mascara)
    Assert-Eq 'S84 y el gateway del local' '192.168.0.1' ([string]$p84.gateway)
    Assert-Eq 'S84 resuelve la herramienta de la marca' $true ([bool]$p84.herramienta.encontrada)
    $txt84 = (@($p84.pasos) -join ' ')
    Assert-Eq 'S84 los pasos nombran la marca y el modelo' $true ([bool]($txt84 -match 'Epson' -and $txt84 -match 'TM-T20III'))
    Assert-Eq 'S84 dan la MAC, que no cambia con la IP' $true ([bool]($txt84 -match '00-26-ab-11-22-33'))
    Assert-Eq 'S84 dicen la ruta de la herramienta' $true ([bool]($txt84 -match 'ENConfig\.exe'))
    Assert-Eq 'S84 y cierran diciendo que se verifica despues' $true ([bool]($txt84 -match 'volver a correr'))

    # Sin marca identificada el motor no puede inventar una herramienta, pero igual sirve: dice
    # donde esta, que ponerle y como leer la IP a mano.
    Reset-State
    function Get-NetIPAddress { param($AddressFamily, $ErrorAction) @([pscustomobject]@{ IPAddress = '192.168.0.10'; InterfaceIndex = 12 }) }
    function Get-InstalledNetworkPrinters { @() }
    function Test-IpAlive { param($Ip, $TimeoutMs) $false }
    $p84b = Resolve-NetworkPrinterPlan -Encontrada ([ordered]@{ ip = '192.168.1.87'; mac = 'aa-bb-cc-dd-ee-ff'; oui = 'aa-bb-cc'; marca = ''; modelo = '' }) `
                                       -PrefijoPc '192.168.0' -Gateway '192.168.0.1'
    $txt84b = (@($p84b.pasos) -join ' ')
    Assert-Eq 'S84b sin marca no hay herramienta' $true ([bool]($null -eq $p84b.herramienta))
    Assert-Eq 'S84b y lo dice en vez de inventarla' $true ([bool]($txt84b -match 'Sin marca identificada'))
    Assert-Eq 'S84b deja el OUI para poder identificarla despues' $true ([bool]($txt84b -match 'aa-bb-cc'))
    Assert-Eq 'S84b igual propone la IP a poner' $true ([bool]([string]$p84b.ipSugerida -match '^192\.168\.0\.'))
    # Sin hallazgo no hay plan: no se afirma nada.
    Assert-Eq 'S84c sin impresora no hay plan' $false ([bool](Resolve-NetworkPrinterPlan -Encontrada $null -PrefijoPc '192.168.0' -Gateway '').hay)

    # Escenario 85: el opt-in. Tocar la red del cliente no puede pasar por default, y en modo
    # agente (sin consola) no se hace nunca.
    Reset-State
    $script:BoundParams = @{}
    function Test-IsInteractiveConsole { $false }
    Assert-Eq 'S85 sin consola y sin parametro no se toca la red' $false (Confirm-NetProbe -Prefijo '192.168.1' -Motivo 'x')
    $script:BoundParams = @{ 'AllowNetProbe' = $true }
    $AllowNetProbe = $true
    Assert-Eq 'S85 con el parametro en true si' $true (Confirm-NetProbe -Prefijo '192.168.1' -Motivo 'x')
    $AllowNetProbe = $false
    Assert-Eq 'S85 y con el parametro en false no, aunque haya consola' $false (Confirm-NetProbe -Prefijo '192.168.1' -Motivo 'x')
    $script:BoundParams = @{}

    # Escenario 86: identidad por el propio protocolo de la impresora (GS I n) y por OUI.
    Reset-State
    $bytes86 = [byte[]]@(0x5F) + [System.Text.Encoding]::ASCII.GetBytes('EPSON') + [byte[]]@(0x00, 0x07)
    Assert-Eq 'S86 saca el texto util de la respuesta' 'EPSON' (Convert-EscPosInfoBytes -Bytes $bytes86 -Leidos @($bytes86).Count)
    Assert-Eq 'S86 sin respuesta no inventa nada' '' (Convert-EscPosInfoBytes -Bytes ([byte[]]@(0x00, 0x00)) -Leidos 2)
    Assert-Eq 'S86 reconoce la marca en el texto' 'Epson' (Resolve-BrandFromText -Texto 'EPSON TM-T20III')
    Assert-Eq 'S86 tambien por el fabricante' 'Epson' (Resolve-BrandFromText -Texto 'Seiko Epson Corp.')
    Assert-Eq 'S86 y una marca de la lista del motor' 'Bixolon' (Resolve-BrandFromText -Texto 'BIXOLON SRP-350')
    Assert-Eq 'S86 texto vacio no da marca' '' (Resolve-BrandFromText -Texto '')
    Assert-Eq 'S86 un texto sin marca conocida tampoco' '' (Resolve-BrandFromText -Texto 'POS-80 PRINTER')
    # La tabla de OUIs arranca vacia a proposito, pero el OUI crudo tiene que viajar igual: es
    # con lo que se va a armar la tabla desde la telemetria, sin adivinar fabricantes.
    Assert-Eq 'S86 devuelve el OUI aunque no conozca la marca' '00-26-ab' ([string](Get-OuiBrand -Mac '00-26-AB-11-22-33').oui)
    Assert-Eq 'S86 y no inventa la marca' '' ([string](Get-OuiBrand -Mac '00-26-AB-11-22-33').marca)
    Assert-Eq 'S86 una MAC ilegible no da OUI' '' ([string](Get-OuiBrand -Mac 'no-es-una-mac').oui)

    # Escenario 87: la IP temporal se saca SIEMPRE. Dejarle una direccion de mas a la placa del
    # cliente seria peor que no haber revisado nada.
    Reset-State
    $script:sacadas87 = New-Object System.Collections.ArrayList
    function Remove-NetIPAddress { param($IPAddress, $InterfaceIndex, $Confirm, $ErrorAction) [void]$script:sacadas87.Add([string]$IPAddress) }
    $script:TempIpsAdded = New-Object System.Collections.ArrayList
    [void]$script:TempIpsAdded.Add([ordered]@{ ip = '192.168.1.200'; indice = 12 })
    [void]$script:TempIpsAdded.Add([ordered]@{ ip = '192.168.123.200'; indice = 12 })
    $r87 = @(Remove-TempSubnetIps)
    Assert-Eq 'S87 saca todas las que agrego' '192.168.1.200,192.168.123.200' ((@($r87) -join ','))
    Assert-Eq 'S87 y queda sin nada pendiente' 0 (@($script:TempIpsAdded).Count)
    # Si una no se puede sacar, se intenta con las demas igual y no explota.
    $script:TempIpsAdded = New-Object System.Collections.ArrayList
    [void]$script:TempIpsAdded.Add([ordered]@{ ip = '10.0.0.200'; indice = 12 })
    [void]$script:TempIpsAdded.Add([ordered]@{ ip = '10.0.0.201'; indice = 12 })
    function Remove-NetIPAddress {
        param($IPAddress, $InterfaceIndex, $Confirm, $ErrorAction)
        if ([string]$IPAddress -eq '10.0.0.200') { throw 'acceso denegado' }
        [void]$script:sacadas87.Add([string]$IPAddress)
    }
    $r87b = @(Remove-TempSubnetIps)
    Assert-Eq 'S87b una que falla no impide sacar el resto' '10.0.0.201' ((@($r87b) -join ','))
    Assert-Eq 'S87b y la lista queda limpia igual' 0 (@($script:TempIpsAdded).Count)

    # Escenario 88: el camino completo. Sin confirmacion no se toca nada, pero se explica.
    Reset-State
    function Get-LocalSubnetPrefixes { @('192.168.0') }
    function Get-InstalledNetworkPrinters { @([ordered]@{ ip = '192.168.1.21'; colas = @('COCINA') }) }
    function Confirm-NetProbe { param($Prefijo, $Motivo) $false }
    Assert-Eq 'S88 sin confirmacion no encuentra nada' $false ([bool](Test-ForeignSubnetPrinters -TcpPort 9100))
    $c88 = Get-CheckById 'conn.otherSubnet'
    Assert-Eq 'S88 pero deja el hallazgo visible' 'skipped' ([string]$c88.status)
    Assert-Eq 'S88 con el motivo del salteo' 'sin_confirmacion' ([string]$c88.evidence.motivoSalteo)
    Assert-Eq 'S88 y dice como habilitarlo' $true ([bool]([string]$c88.recommendation -match 'AllowNetProbe'))
    Assert-Eq 'S88 no es causa raiz si no se reviso' $false ([bool]$c88.rootCauseCandidate)
    Assert-Eq 'S88 y no toco la red' 0 (@($script:TempIpsAdded).Count)

    # Con confirmacion y una impresora del otro lado: causa raiz y plan completo.
    Reset-State
    function Get-LocalSubnetPrefixes { @('192.168.0') }
    function Get-InstalledNetworkPrinters { @([ordered]@{ ip = '192.168.1.21'; colas = @('COCINA') }) }
    function Confirm-NetProbe { param($Prefijo, $Motivo) $true }
    function Add-TempSubnetIp { param($Prefijo) @{ aplicado = $true; ip = ($Prefijo + '.200'); indice = 12; motivo = '' } }
    function Remove-TempSubnetIps { @() }
    function Find-NetworkPrinters { param($Prefix, $TcpPort, $WaitMs) @([ordered]@{ ip = ($Prefix + '.21'); puerto = 9100; respondeEscPos = $true; tipo = 'impresora termica (responde ESC/POS)' }) }
    function Get-MacForIp { param($Ip) '00-26-ab-11-22-33' }
    function Get-EscPosIdentity { param($Ip, $TcpPort, $TimeoutMs) [ordered]@{ fabricante = 'EPSON'; modelo = 'TM-T20III'; marca = 'Epson' } }
    function Get-PrimaryIpv4Interface { [ordered]@{ indice = 12; ip = '192.168.0.10'; prefijo = '192.168.0' } }
    function Get-DefaultGatewayIp { '192.168.0.1' }
    function Get-NetIPAddress { param($AddressFamily, $ErrorAction) @([pscustomobject]@{ IPAddress = '192.168.0.10'; InterfaceIndex = 12 }) }
    function Test-IpAlive { param($Ip, $TimeoutMs) $false }
    function Test-PathExists { param($Path) return ([string]$Path -match 'EPSON') }
    Assert-Eq 'S88b con confirmacion la encuentra' $true ([bool](Test-ForeignSubnetPrinters -TcpPort 9100))
    $c88b = Get-CheckById 'conn.otherSubnet'
    Assert-Eq 'S88b y es la causa raiz' $true ([bool]$c88b.rootCauseCandidate)
    Assert-Eq 'S88b el nombre dice donde esta' $true ([bool]([string]$c88b.name -match '192\.168\.1\.21'))
    Assert-Eq 'S88b y de que marca es' $true ([bool]([string]$c88b.name -match 'Epson'))
    Assert-Eq 'S88b la categoria sale del id' 'net.otra_subred' ([string]$script:CategoryByCheckId['conn.otherSubnet'])
    $pl88 = $script:Diagnostics['planRedImpresora']
    Assert-Eq 'S88b queda el plan para el resumen' '192.168.1.21' ([string]$pl88.ip)
    Assert-Eq 'S88b con la IP a ponerle' $true ([bool]([string]$pl88.ipSugerida -match '^192\.168\.0\.'))
    Assert-Eq 'S88b y la MAC para la tabla de OUIs' '00-26-ab-11-22-33' ([string]$pl88.mac)
    # El resumen tiene que mostrarlo: la informacion suelta en el JSON no le sirve al asesor.
    $res88 = ((Build-HumanSummary -Diag (Resolve-Diagnosis) -DetectedInterface 'Ethernet') -join ' ')
    Assert-Eq 'S88b el resumen trae el bloque' $true ([bool]($res88 -match 'IMPRESORA DE RED EN OTRA SUBRED'))
    Assert-Eq 'S88b con la IP donde esta' $true ([bool]($res88 -match '192\.168\.1\.21'))
    Assert-Eq 'S88b y con que herramienta' $true ([bool]($res88 -match 'ENConfig\.exe'))

    # Y si en la otra subred no hay nada, se dice, sin afirmar que no hay impresoras en ningun lado.
    Reset-State
    function Find-NetworkPrinters { param($Prefix, $TcpPort, $WaitMs) @() }
    Assert-Eq 'S88c sin hallazgos no hay plan' $false ([bool](Test-ForeignSubnetPrinters -TcpPort 9100))
    Assert-Eq 'S88c y queda constancia de lo revisado' 'ok' ([string](Get-CheckById 'conn.otherSubnet').status)

    # Escenario 89 (v3.17, bitacora semanal 31/08-06/09): el motor le agregaba exclusiones al
    # antivirus del cliente sin ninguna evidencia de que el antivirus tuviera algo que ver.
    # Dos PCs 3.14 (nativaVersion 0.0.19 y 0.0.24) con la causa raiz en el hardware
    # (printer.disconnected / hw.disconnected) quedaron con nativa.defenderExclusion=fixed.
    # Es la tercera version que corrige esta misma familia: la 3.10 la apago para las firmadas,
    # la 3.12 apago la restauracion sobre detecciones historicas, y la rama seguia viva.
    Reset-State
    # Con el archivo en disco NUNCA hace falta, con o sin detecciones, firmada o no, corriendo o no.
    Assert-Eq 'S89 con la Nativa en disco no se toca el antivirus' $false ([bool](Test-DefenderExclusionNeeded -Presente $true -Corriendo $false -Firmada $false -Detecciones @() -DefenderActivo $true).haceFalta)
    Assert-Eq 'S89 y lo dice' $true ([bool]([string](Test-DefenderExclusionNeeded -Presente $true -Corriendo $false -Firmada $false -Detecciones @() -DefenderActivo $true).motivo -match 'esta en disco'))
    Assert-Eq 'S89 tampoco con detecciones historicas' $false ([bool](Test-DefenderExclusionNeeded -Presente $true -Corriendo $false -Firmada $false -Detecciones @([ordered]@{ id='1' }) -DefenderActivo $true).haceFalta)
    Assert-Eq 'S89 ni sin firmar y apagada, que es el caso de las dos PCs' $false ([bool](Test-DefenderExclusionNeeded -Presente $true -Corriendo $false -Firmada $false -Detecciones @() -DefenderActivo $true).haceFalta)
    Assert-Eq 'S89 ni firmada y corriendo' $false ([bool](Test-DefenderExclusionNeeded -Presente $true -Corriendo $true -Firmada $true -Detecciones @() -DefenderActivo $true).haceFalta)
    # Sin el archivo y con detecciones si: eso es la cuarentena de verdad, y sigue reparandose.
    Assert-Eq 'S89 sin el archivo y con detecciones si hace falta' $true ([bool](Test-DefenderExclusionNeeded -Presente $false -Corriendo $false -Firmada $false -Detecciones @([ordered]@{ id='1' }) -DefenderActivo $true).haceFalta)
    # Sin el archivo y sin detecciones: lo que falta es instalarla, no excluirla.
    $e89 = Test-DefenderExclusionNeeded -Presente $false -Corriendo $false -Firmada $null -Detecciones @() -DefenderActivo $true
    Assert-Eq 'S89 sin archivo y sin detecciones no se excluye' $false ([bool]$e89.haceFalta)
    Assert-Eq 'S89 y el motivo apunta a instalarla' $true ([bool]([string]$e89.motivo -match 'instalarla'))
    # Sin Defender activo no hay nada que tocar.
    Assert-Eq 'S89 sin Defender activo tampoco' $false ([bool](Test-DefenderExclusionNeeded -Presente $false -Corriendo $false -Firmada $false -Detecciones @([ordered]@{ id='1' }) -DefenderActivo $false).haceFalta)
    # El predicado tiene que decidir igual que el de la cuarentena: era el bug de fondo, dos
    # caminos distintos decidiendo lo mismo.
    foreach ($pres89 in @($true, $false)) {
        $a89 = [bool](Test-DefenderExclusionNeeded -Presente $pres89 -Corriendo $false -Firmada $false -Detecciones @([ordered]@{ id='1' }) -DefenderActivo $true).haceFalta
        $b89 = [bool](Test-DefenderThreatActionable -Threats @([ordered]@{ id='1' }) -Firmada $false -Presente $pres89).accionable
        Assert-Eq ('S89 los dos caminos deciden igual (presente=' + $pres89 + ')') $a89 $b89
    }

    # Escenario 90 (v3.17): una reparacion posterior tiene que poder corregir un hallazgo
    # anterior. La restauracion de la cuarentena funcionaba y el caso escalaba igual: 4 PCs con
    # nativa.installed=fail y needs_escalation, y en dos la corrida siguiente -1 y 3 minutos
    # despues- ya traia la 0.0.37. El asesor tenia que correrlo dos veces.
    Reset-State
    Add-Check -Id 'nativa.installed' -Layer 0 -Name 'App Nativa de Fudo NO instalada' -Status 'fail' -RootCauseCandidate $true -Plane 'fudo_config' `
        -Evidence @{ found = $false }
    Add-Check -Id 'hw.testprint' -Layer 4 -Name 'Salio el papel' -Status 'ok' -Plane 'hardware'
    # Antes de corregir: el hallazgo viejo bloquea el cierre y se lleva la causa.
    $d90a = Resolve-Diagnosis
    Assert-Eq 'S90 con la Nativa ausente no cierra' $false ([bool]$d90a.resolved)
    Assert-Eq 'S90 y la causa es la Nativa' 'nativa.installed' ([string]$d90a.rootCauseCheckId)
    # La restauracion la trajo de vuelta: el hallazgo anterior ya no describe la PC.
    Assert-Eq 'S90 el chequeo se puede corregir' $true ([bool](Update-CheckFinding -Id 'nativa.installed' -Status 'fixed' -RootCauseCandidate $false `
        -Name 'App Nativa de Fudo restaurada de la cuarentena del antivirus (v0.0.37)' `
        -ActionTaken 'restaurada desde la cuarentena de Defender en esta corrida' `
        -EvidenceExtra @{ restauradaEnEstaCorrida = $true; versionDespues = '0.0.37' }))
    $c90 = Get-CheckById 'nativa.installed'
    Assert-Eq 'S90 queda como reparado' 'fixed' ([string]$c90.status)
    Assert-Eq 'S90 y deja de ser candidata a causa raiz' $false ([bool]$c90.rootCauseCandidate)
    Assert-Eq 'S90 el nombre dice lo que paso' $true ([bool]([string]$c90.name -match 'restaurada'))
    Assert-Eq 'S90 la evidencia vieja no se pierde' $false ([bool]$c90.evidence.found)
    Assert-Eq 'S90 y se suma la nueva' '0.0.37' ([string]$c90.evidence.versionDespues)
    # Y lo que importa: el caso deja de escalar por algo que ya se arreglo.
    $d90b = Resolve-Diagnosis
    Assert-Eq 'S90 ahora si cierra' $true ([bool]$d90b.resolved)
    Assert-Eq 'S90 y no escala' $false ([bool]$d90b.needsEscalation)
    Assert-Eq 'S90 la causa es la reparacion, no el hallazgo viejo' $true ([bool]([string]$d90b.rootCause -match 'restaurada'))
    # Corregir un chequeo que no existe no puede explotar ni inventarlo.
    Assert-Eq 'S90b un id inexistente no hace nada' $false ([bool](Update-CheckFinding -Id 'no.existe' -Status 'fixed'))
    Assert-Eq 'S90b y no agrega chequeos' 2 (@($script:Checks).Count)

    # ---------------------------------------------------------------------
    # Escenarios 91-94 (v3.18): todos salieron de la respuesta de un asesor a un caso concreto,
    # no de la telemetria. Un local con 218 y 1182 comandas encoladas donde purgar corrio 16
    # veces sin resolver, y el mismo asesor reportando que "el motor dice que instala la nativa
    # pero al corroborar en la version web sigue sin detectarla".
    # ---------------------------------------------------------------------

    # Escenario 91: el .msi de la Nativa firmada es parte del kit del asesor. El chequeo NO mira
    # lo que tiene el cliente: mira si el asesor puede resolver una Nativa vieja cuando aparezca.
    Reset-State
    Reset-Mocks
    function Get-LocalNativeInstallers { @([ordered]@{ ruta='C:\kit\FudoNativa.msi'; version='0.0.37'; esMsi=$true; fecha=(Get-Date) }) }
    $k91 = Test-NativaKitReady
    Assert-Eq 'S91 con la firmada el kit esta listo' $true ([bool]$k91.listo)
    Assert-Eq 'S91 y dice cual es' '0.0.37' ([string]$k91.version)
    # Una posterior a la firmada tambien sirve: el numero no esta clavado.
    function Get-LocalNativeInstallers { @([ordered]@{ ruta='C:\kit\FudoNativa.msi'; version='0.0.41'; esMsi=$true; fecha=(Get-Date) }) }
    Assert-Eq 'S91 una posterior tambien sirve' $true ([bool](Test-NativaKitReady).listo)
    # Una anterior NO alcanza, y el motivo tiene que decir cual hay.
    function Get-LocalNativeInstallers { @([ordered]@{ ruta='C:\kit\FudoNativa.msi'; version='0.0.27'; esMsi=$true; fecha=(Get-Date) }) }
    $k91c = Test-NativaKitReady
    Assert-Eq 'S91 una anterior a la firmada no alcanza' $false ([bool]$k91c.listo)
    Assert-Eq 'S91 y el motivo dice cual hay' $true ([bool]([string]$k91c.motivo -match '0\.0\.27'))
    # Sin ningun instalador.
    function Get-LocalNativeInstallers { @() }
    Assert-Eq 'S91 sin instalador el kit no esta listo' $false ([bool](Test-NativaKitReady).listo)
    Assert-Eq 'S91 y lo dice' $true ([bool]([string](Test-NativaKitReady).motivo -match 'no hay ningun instalador'))
    # Un .exe no declara version: no se puede saber si sirve, asi que no cuenta.
    function Get-LocalNativeInstallers { @([ordered]@{ ruta='C:\kit\FudoNativa.exe'; version=''; esMsi=$false; fecha=(Get-Date) }) }
    $k91e = Test-NativaKitReady
    Assert-Eq 'S91 un .exe sin version no alcanza' $false ([bool]$k91e.listo)
    Assert-Eq 'S91 y el motivo lo explica' $true ([bool]([string]$k91e.motivo -match 'declara su version'))

    # La confirmacion: no bloquea el diagnostico y en modo agente nunca pregunta.
    Reset-State
    function Test-IsInteractiveConsole { $false }
    Assert-Eq 'S91b sin consola no bloquea (modo agente)' $true (Confirm-NativaKit -Kit ([ordered]@{ listo=$false; motivo='x' }))
    Assert-Eq 'S91b con el kit listo no pregunta nada' $true (Confirm-NativaKit -Kit ([ordered]@{ listo=$true; motivo='' }))

    # Escenario 92: el instalador se elige por VERSION, no por fecha. Este era el bug: el
    # cliente tenia uno viejo en Descargas, mas reciente por fecha, y el motor instalaba ESE.
    # Reset-Mocks es imprescindible aca: el escenario 91 deja mockeado Get-LocalNativeInstallers
    # y el 78 deja Find-LocalNativeInstaller, que son justo las dos funciones bajo prueba.
    Reset-State
    Reset-Mocks
    function Get-ChildItem {
        param($Path, $Filter, [switch]$File, $ErrorAction)
        @(
            [pscustomobject]@{ FullName='C:\Users\cliente\Downloads\FudoNativa.msi'; Length=3MB; LastWriteTime=(Get-Date) },
            [pscustomobject]@{ FullName='C:\kit\FudoNativa.msi'; Length=3MB; LastWriteTime=(Get-Date).AddDays(-90) }
        )
    }
    function Get-MsiProductVersion { param($Path) $(if ($Path -match 'Downloads') { '0.0.18' } else { '0.0.37' }) }
    $c92 = @(Get-LocalNativeInstallers)
    Assert-Eq 'S92 no duplica el mismo archivo' 2 (@($c92).Count)
    Assert-Eq 'S92 gana la version mas alta, no la mas reciente' '0.0.37' ([string]@($c92)[0].version)
    Assert-Eq 'S92 y Find devuelve ese' $true ([bool]((Find-LocalNativeInstaller) -match 'kit'))
    Assert-Eq 'S92 no el que estaba en Descargas' $false ([bool]((Find-LocalNativeInstaller) -match 'Downloads'))
    # Los que no declaran version van al final: no se instala a ciegas si hay uno que si la dice.
    function Get-ChildItem {
        param($Path, $Filter, [switch]$File, $ErrorAction)
        @(
            [pscustomobject]@{ FullName='C:\kit\FudoNativa.exe'; Length=3MB; LastWriteTime=(Get-Date) },
            [pscustomobject]@{ FullName='C:\kit\FudoNativa.msi'; Length=3MB; LastWriteTime=(Get-Date).AddDays(-5) }
        )
    }
    function Get-MsiProductVersion { param($Path) $(if ($Path -match '\.msi$') { '0.0.37' } else { '' }) }
    Assert-Eq 'S92b el que declara version va primero' $true ([bool]((Find-LocalNativeInstaller) -match '\.msi$'))

    # Escenario 93: instalar la Nativa verificando el EFECTO. El motor reportaba la reparacion
    # aplicada mirando solo el codigo de salida, con la Nativa sin instalar.
    Reset-State
    Reset-Mocks
    function Find-LocalNativeInstaller { 'C:\kit\FudoNativa.msi' }
    function Get-MsiProductVersion { param($Path) '0.0.37' }
    function Get-NativaVersionState { param($Install) [ordered]@{ version=[string](@($Install.regInfo)[0].version); firmada=$true } }
    function Invoke-NativeInstallerFile { param($Path, $ExtraArgs) 0 }
    function Add-MpPreference { param($ExclusionPath, $ExclusionProcess, $ErrorAction) }
    function Get-Process { param($ErrorAction) @() }
    function Start-Sleep { param($Seconds, $Milliseconds) }
    $script:i93 = 0
    function Find-FudoNativeInstall {
        $script:i93++
        if ($script:i93 -le 1) { [ordered]@{ paths=@(); regInfo=@(); exe=''; enDisco=$false } }
        else { [ordered]@{ paths=@('C:\Users\x\AppData\Local\Fudo'); regInfo=@([ordered]@{ version='0.0.37'; esPwa=$false })
                           exe='C:\Users\x\AppData\Local\Fudo\fudo_native_extension.exe'; enDisco=$true } }
    }
    # El hallazgo previo de "no instalada" tiene que quedar corregido por la instalacion.
    Add-Check -Id 'nativa.installed' -Layer 0 -Name 'App Nativa de Fudo NO instalada' -Status 'fail' -RootCauseCandidate $true -Plane 'fudo_config' -Evidence @{ found=$false }
    $r93 = Install-FudoNative
    Assert-Eq 'S93 la instalacion se reporta aplicada' $true ([bool]$r93.applied)
    Assert-Eq 'S93 y dice que quedo instalada' $true ([bool]([string]$r93.note -match 'quedo instalada'))
    Assert-Eq 'S93 el hallazgo viejo queda corregido' 'fixed' ([string](Get-CheckById 'nativa.installed').status)
    Assert-Eq 'S93 y deja de ser causa raiz' $false ([bool](Get-CheckById 'nativa.installed').rootCauseCandidate)

    # El instalador dice que anduvo y la Nativa no aparece: NO puede pasar por instalada.
    Reset-State
    function Find-FudoNativeInstall { [ordered]@{ paths=@(); regInfo=@() } }
    function Get-NativaVersionState { param($Install) [ordered]@{ version=''; firmada=$null } }
    $r93b = Install-FudoNative
    Assert-Eq 'S93b sin la Nativa en disco no se declara instalada' $false ([bool]$r93b.applied)
    Assert-Eq 'S93b y lo dice' $true ([bool]([string]$r93b.note -match 'NO quedo instalada'))

    # Y nunca degradar: con una mas nueva instalada, un instalador viejo no se ejecuta.
    Reset-State
    function Find-FudoNativeInstall { [ordered]@{ paths=@('C:\x'); regInfo=@([ordered]@{ version='0.0.37'; esPwa=$false })
                                                  exe='C:\x\fudo_native_extension.exe'; enDisco=$true } }
    function Get-NativaVersionState { param($Install) [ordered]@{ version='0.0.37'; firmada=$true; confiable=$true } }
    function Get-MsiProductVersion { param($Path) '0.0.18' }
    $script:llamoInstalador93 = $false
    function Invoke-NativeInstallerFile { param($Path, $ExtraArgs) $script:llamoInstalador93 = $true; 0 }
    $r93c = Install-FudoNative
    Assert-Eq 'S93c no degrada la Nativa instalada' $false ([bool]$r93c.applied)
    Assert-Eq 'S93c y ni siquiera corre el instalador' $false ([bool]$script:llamoInstalador93)
    Assert-Eq 'S93c el motivo lo explica' $true ([bool]([string]$r93c.note -match 'mas viejo'))

    # Escenario 94: por que purgar no alcanza. El caso real: purgar funcionaba -las comandas se
    # borraban- pero cada prueba generaba decenas de trabajos porque el cliente tenia muchas
    # impresoras instaladas. Purgar no podia ganar nunca y lo que resolvio fue borrar impresoras.
    Reset-State
    Reset-Mocks
    $script:Diagnostics['colas'] = @(
        [ordered]@{ nombre='POS-80C';           puerto='USB001'; esDePrueba=$false; puertoVivo=$true },
        [ordered]@{ nombre='POS-80C (copia 1)'; puerto='USB001'; esDePrueba=$false; puertoVivo=$false },
        [ordered]@{ nombre='POS-80C (copia 2)'; puerto='USB001'; esDePrueba=$false; puertoVivo=$false },
        [ordered]@{ nombre='BARRA TRAGOS';      puerto='USB002'; esDePrueba=$false; puertoVivo=$false }
    )
    function Confirm-Irreversible { param($Description, $Impact) $true }
    function Remove-PrintJob { param($ErrorAction) }
    function Start-Sleep { param($Seconds, $Milliseconds) }
    $script:j94 = 0
    function Get-PrintJob {
        param($PrinterName, $ErrorAction)
        $script:j94++
        if ($script:j94 -eq 1) { @(1..60 | ForEach-Object { [pscustomobject]@{ JobStatus='Normal'; SubmittedTime=(Get-Date).AddMinutes(-30) } }) }
        elseif ($script:j94 -le 3) { @() }
        else { @(1..47 | ForEach-Object { [pscustomobject]@{ JobStatus='Normal'; SubmittedTime=(Get-Date) } }) }
    }
    Test-Layer2-Queue -Printer ([pscustomobject]@{ Name='CAJA PRINCIPAL' }) -Wmi $null
    $m94 = $script:Diagnostics['purgaMedicion']
    Assert-Eq 'S94 mide cuantos habia' 60 ([int]$m94.antes)
    Assert-Eq 'S94 cuantos quedaron' 0 ([int]$m94.despues)
    Assert-Eq 'S94 y cuantos volvieron' 47 ([int]$m94.volvieron)
    Assert-Eq 'S94 cuenta las colas instaladas' 4 ([int]$m94.colasInstaladas)
    Assert-Eq 'S94 y las que no tienen hardware' 3 ([int]$m94.colasSinHardware)
    $c94 = Get-CheckById 'queue.rebotePurga'
    Assert-Eq 'S94 avisa que la cola se volvio a llenar' $true ([bool]($null -ne $c94))
    Assert-Eq 'S94 y no lo da como causa raiz todavia' $false ([bool]$c94.rootCauseCandidate)
    Assert-Eq 'S94 apunta a las impresoras instaladas' $true ([bool]([string]$c94.recommendation -match 'impresora'))
    Assert-Eq 'S94 y a borrar las que no se usan' $true ([bool]([string]$c94.recommendation -match 'borrar'))
    # Purgar y que NO vuelvan es el caso sano: no se avisa nada.
    Reset-State
    $script:j94 = 0
    function Get-PrintJob {
        param($PrinterName, $ErrorAction)
        $script:j94++
        if ($script:j94 -eq 1) { @(1..5 | ForEach-Object { [pscustomobject]@{ JobStatus='Error'; SubmittedTime=(Get-Date).AddMinutes(-30) } }) }
        else { @() }
    }
    Test-Layer2-Queue -Printer ([pscustomobject]@{ Name='CAJA' }) -Wmi $null
    Assert-Eq 'S94b si no vuelven no se avisa nada' $true ([bool]($null -eq (Get-CheckById 'queue.rebotePurga')))
    Assert-Eq 'S94b y la cola queda reparada' 'fixed' ([string](Get-CheckById 'queue.health').status)

    # Escenario 95: purgar y que la cola NO baje no es una reparacion. En 11 de 32 corridas con
    # medicion la cola quedo igual o peor, y 7 de esas cerraron con queue.health = fixed y la
    # purga listada como reparacion aplicada. La medicion ya existia desde la 3.18; no la leia
    # nadie.
    Reset-State
    Reset-Mocks
    $script:Diagnostics['colas'] = @(
        [ordered]@{ nombre='CAJA'; puerto='USB001'; esDePrueba=$false; puertoVivo=$true },
        [ordered]@{ nombre='MUERTA 1'; puerto='USB003'; esDePrueba=$false; puertoVivo=$false },
        [ordered]@{ nombre='MUERTA 2'; puerto='USB004'; esDePrueba=$false; puertoVivo=$false }
    )
    function Confirm-Irreversible { param($Description, $Impact) $true }
    function Remove-PrintJob { param($ErrorAction) }
    function Start-Sleep { param($Seconds, $Milliseconds) }
    function Get-PrintJob {
        param($PrinterName, $ErrorAction)
        @(1..8 | ForEach-Object { [pscustomobject]@{ JobStatus='Error'; SubmittedTime=(Get-Date).AddMinutes(-30) } })
    }
    Test-Layer2-Queue -Printer ([pscustomobject]@{ Name='CAJA' }) -Wmi $null
    $c95 = Get-CheckById 'queue.health'
    Assert-Eq 'S95 si la cola no bajo, la purga no reparo nada' 'fail' ([string]$c95.status)
    Assert-Eq 'S95 y el nombre dice lo que paso' $true ([bool]([string]$c95.name -match 'no bajo'))
    Assert-Eq 'S95 apunta a las colas sin hardware' $true ([bool]([string]$c95.recommendation -match 'sin hardware presente'))
    $d95 = Resolve-Diagnosis
    Assert-Eq 'S95 y no se lista como reparacion aplicada' $false ([bool](@($d95.autoFixesApplied) -match 'Cola de impresion trabada'))

    # Escenario 96: la pagina web agregada como aplicacion NO es la App Nativa. Se registra con
    # DisplayName 'Fudo' y DisplayVersion 1.0, y el guardarrail anti-degradacion de la 3.18
    # comparaba el .msi 0.0.37 contra esa 1.0 y abortaba: en esas PCs el motor no instalaba la
    # Nativa nunca, por mas que el asesor trajera el instalador.
    Reset-State
    Reset-Mocks
    $inst96 = [ordered]@{ paths=@(); exe=''; enDisco=$false; soloRegistro=$false; pwa=$true
                          regInfo=@([ordered]@{ name='Fudo'; version='1.0'; location=''; esPwa=$true }) }
    $v96 = Get-NativaVersionState -Install $inst96
    Assert-Eq 'S96 la version de la app del navegador no es la de la Nativa' '' ([string]$v96.version)
    Assert-Eq 'S96 y sin archivos en disco la version no es confiable' $false ([bool]$v96.confiable)
    $v96b = Get-NativaVersionState -Install ([ordered]@{ enDisco=$true
                          regInfo=@([ordered]@{ name='Fudo'; version='1.0'; esPwa=$true },
                                    [ordered]@{ name='Fudo Nativa'; version='0.0.37'; esPwa=$false }) })
    Assert-Eq 'S96 con las dos, gana la Nativa de verdad' '0.0.37' ([string]$v96b.version)
    # Y el instalador AHORA si se ejecuta.
    Reset-State
    function Find-LocalNativeInstaller { 'C:\kit\NATIVA FUDO.msi' }
    function Get-MsiProductVersion { param($Path) '0.0.37' }
    function Get-NativaVersionState { param($Install) [ordered]@{ version='1.0'; firmada=$true; confiable=$false } }
    function Add-MpPreference { param($ExclusionPath, $ExclusionProcess, $ErrorAction) }
    function Get-Process { param($ErrorAction) @() }
    function Start-Sleep { param($Seconds, $Milliseconds) }
    function Find-FudoNativeInstall { [ordered]@{ paths=@(); regInfo=@([ordered]@{ name='Fudo'; version='1.0'; esPwa=$true })
                                                  exe=''; enDisco=$false; soloRegistro=$false; pwa=$true } }
    $script:llamoInstalador96 = $false
    function Invoke-NativeInstallerFile { param($Path, $ExtraArgs) $script:llamoInstalador96 = $true; 0 }
    $r96 = Install-FudoNative
    Assert-Eq 'S96 con la PWA instalada el instalador SI se ejecuta' $true ([bool]$script:llamoInstalador96)
    Assert-Eq 'S96 y sin archivos no se declara instalada' $false ([bool]$r96.applied)

    # Escenario 97: los dos eslabones entre "la Nativa esta instalada" y "Fudo imprime". Los dos
    # los encontro un asesor en la misma semana, y los dos terminaban en una PC con todo verde:
    # la Nativa sin registrar en el navegador (el "cerra sesion y volve a entrar" de la web app)
    # y la extension sin agregar.
    Reset-State
    Reset-Mocks
    function Find-FudoNativeInstall {
        [ordered]@{ paths=@('C:\Users\x\AppData\Local\Fudo'); regInfo=@([ordered]@{ version='0.0.37'; esPwa=$false })
                    exe='C:\Users\x\AppData\Local\Fudo\fudo_native_extension.exe'
                    manifests=@(); carpeta='C:\Users\x\AppData\Local\Fudo'
                    enDisco=$true; soloRegistro=$false; pwa=$false }
    }
    function Get-AntivirusState { [ordered]@{ defender=$null; thirdParty=@(); realTime=$null; fudoThreats=@() } }
    function Get-NativaVersionState { param($Install) [ordered]@{ version='0.0.37'; firmada=$true; confiable=$true } }
    function Get-Process { param($ErrorAction) @() }
    function Get-SesionInteractiva { [ordered]@{ usuarioMotor='ana'; usuarioSesion='ana'; otroPerfil=$false } }
    function Get-NativeMessagingState {
        [ordered]@{ registrado=$true; navegadores=@('Chrome'); manifest='C:\Users\x\AppData\Local\Fudo\do.fu.native_extension_chrome.json'
                    exeDelManifest='C:\Users\x\AppData\Local\Fudo\fudo_native_extension.exe'; exeExiste=$true
                    extensionIds=@('npcjljaedonmjndbliillcmkhidejhmb'); pendientes=@() }
    }
    function Get-FudoExtensionState { param($Ids) [ordered]@{ instalada=$false; ids=@($Ids); encontrada=''
                                                              navegador=''; perfil=''; perfilesVistos=2 } }
    Test-Layer0b-NativeApp
    $e97 = Get-CheckById 'fudo.extension'
    Assert-Eq 'S97 sin la extension el caso tiene causa' 'fail' ([string]$e97.status)
    Assert-Eq 'S97 y es candidata a causa raiz' $true ([bool]$e97.rootCauseCandidate)
    Assert-Eq 'S97 con el link de la tienda' $true ([bool]([string]$e97.recommendation -match 'chromewebstore'))
    Assert-Eq 'S97 el host registrado no molesta' 'ok' ([string](Get-CheckById 'nativa.hostRegistrado').status)

    # Con la extension puesta, no hay hallazgo.
    Reset-State
    function Get-FudoExtensionState { param($Ids) [ordered]@{ instalada=$true; ids=@($Ids); encontrada='npcjljaedonmjndbliillcmkhidejhmb'
                                                              navegador='Chrome'; perfil='Default'; perfilesVistos=1 } }
    Test-Layer0b-NativeApp
    Assert-Eq 'S97b con la extension puesta el check cierra en ok' 'ok' ([string](Get-CheckById 'fudo.extension').status)

    # Sin navegador Chromium en el perfil no se puede concluir: skipped, nunca fail.
    Reset-State
    function Get-FudoExtensionState { param($Ids) [ordered]@{ instalada=$false; ids=@($Ids); encontrada=''
                                                              navegador=''; perfil=''; perfilesVistos=0 } }
    Test-Layer0b-NativeApp
    $e97c = Get-CheckById 'fudo.extension'
    Assert-Eq 'S97c sin navegador no se afirma nada' 'skipped' ([string]$e97c.status)
    Assert-Eq 'S97c y se dice por que' 'sin_navegador' ([string]$e97c.evidence.skipReason)

    # Escenario 98: la Nativa esta en disco y el navegador no la tiene registrada. Es lo que
    # arregla el "cerra sesion y volve a entrar", y se puede hacer sin cerrar sesion ejecutando
    # la Nativa una vez. Se verifica el EFECTO: vuelve a leerse la clave, no el codigo de salida.
    Reset-State
    Reset-Mocks
    function Find-FudoNativeInstall {
        [ordered]@{ paths=@('C:\Users\x\AppData\Local\Fudo'); regInfo=@([ordered]@{ version='0.0.37'; esPwa=$false })
                    exe='C:\Users\x\AppData\Local\Fudo\fudo_native_extension.exe'
                    manifests=@(); carpeta='C:\Users\x\AppData\Local\Fudo'
                    enDisco=$true; soloRegistro=$false; pwa=$false }
    }
    function Get-AntivirusState { [ordered]@{ defender=$null; thirdParty=@(); realTime=$null; fudoThreats=@() } }
    function Get-NativaVersionState { param($Install) [ordered]@{ version='0.0.37'; firmada=$true; confiable=$true } }
    function Get-Process { param($ErrorAction) @() }
    function Get-SesionInteractiva { [ordered]@{ usuarioMotor='ana'; usuarioSesion='ana'; otroPerfil=$false } }
    function Get-FudoExtensionState { param($Ids) [ordered]@{ instalada=$true; ids=@($Ids); encontrada='npcjljaedonmjndbliillcmkhidejhmb'
                                                              navegador='Chrome'; perfil='Default'; perfilesVistos=1 } }
    $script:n98 = 0
    function Get-NativeMessagingState {
        $script:n98++
        if ($script:n98 -le 2) {
            [ordered]@{ registrado=$false; navegadores=@(); manifest=''; exeDelManifest=''; exeExiste=$false
                        extensionIds=@(); pendientes=@('Chrome: sin clave de registro') }
        } else {
            [ordered]@{ registrado=$true; navegadores=@('Chrome'); manifest='m.json'
                        exeDelManifest='C:\Users\x\AppData\Local\Fudo\fudo_native_extension.exe'; exeExiste=$true
                        extensionIds=@('npcjljaedonmjndbliillcmkhidejhmb'); pendientes=@() }
        }
    }
    $script:corrio98 = ''
    function Start-FudoNativeHostProcess { param($Exe, $TimeoutSeg) $script:corrio98 = [string]$Exe; @{ lanzado=$true; quedoVivo=$false; error='' } }
    Test-Layer0b-NativeApp
    $h98 = Get-CheckById 'nativa.hostRegistrado'
    Assert-Eq 'S98 registra la Nativa en el navegador' 'fixed' ([string]$h98.status)
    Assert-Eq 'S98 ejecutando el archivo de la Nativa' 'C:\Users\x\AppData\Local\Fudo\fudo_native_extension.exe' ([string]$script:corrio98)
    Assert-Eq 'S98 y explica que evita cerrar sesion' $true ([bool]([string]$h98.recommendation -match 'sin cerrar sesion'))

    # Si se ejecuta y la clave NO aparece, no se declara reparado.
    Reset-State
    function Get-NativeMessagingState {
        [ordered]@{ registrado=$false; navegadores=@(); manifest=''; exeDelManifest=''; exeExiste=$false
                    extensionIds=@(); pendientes=@('Chrome: sin clave de registro') }
    }
    function Start-FudoNativeHostProcess { param($Exe, $TimeoutSeg) @{ lanzado=$true; quedoVivo=$true; error='' } }
    Test-Layer0b-NativeApp
    $h98b = Get-CheckById 'nativa.hostRegistrado'
    Assert-Eq 'S98b si la clave no aparece no se declara reparado' 'fail' ([string]$h98b.status)
    Assert-Eq 'S98b y es la causa raiz candidata' $true ([bool]$h98b.rootCauseCandidate)
    Assert-Eq 'S98b con el motivo' $true ([bool]([string]$h98b.evidence.motivo -match 'no aparecio'))

    # Y el matiz que evita repetir el bloqueo de cierres que destrabo la 3.11: sin evidencia de
    # cual es el navegador del cliente, el hallazgo se ve pero no bloquea el cierre.
    Reset-State
    function Get-NativeMessagingState {
        [ordered]@{ registrado=$false; navegadores=@(); manifest=''; exeDelManifest=''; exeExiste=$false
                    extensionIds=@(); pendientes=@('Chrome: sin clave de registro') }
    }
    function Start-FudoNativeHostProcess { param($Exe, $TimeoutSeg) @{ lanzado=$true; quedoVivo=$false; error='' } }
    function Get-FudoExtensionState { param($Ids) [ordered]@{ instalada=$false; ids=@($Ids); encontrada=''
                                                              navegador=''; perfil=''; perfilesVistos=0 } }
    Test-Layer0b-NativeApp
    Assert-Eq 'S98c sin navegador en la cuenta no se bloquea el cierre' 'warn' ([string](Get-CheckById 'nativa.hostRegistrado').status)
    Assert-Eq 'S98c pero sigue siendo candidata a causa raiz' $true ([bool](Get-CheckById 'nativa.hostRegistrado').rootCauseCandidate)

    # Con el host registrado en Chrome, que falte la extension SI es un hecho.
    Reset-State
    function Get-NativeMessagingState {
        [ordered]@{ registrado=$true; navegadores=@('Chrome'); manifest='m.json'
                    exeDelManifest='C:\Users\x\AppData\Local\Fudo\fudo_native_extension.exe'; exeExiste=$true
                    extensionIds=@('npcjljaedonmjndbliillcmkhidejhmb'); pendientes=@() }
    }
    function Get-FudoExtensionState { param($Ids) [ordered]@{ instalada=$false; ids=@($Ids); encontrada=''
                                                              navegador=''; perfil=''; perfilesVistos=3 } }
    Test-Layer0b-NativeApp
    Assert-Eq 'S98d con el host en Chrome, la extension ausente es fail' 'fail' ([string](Get-CheckById 'fudo.extension').status)
    # Si la Nativa solo esta registrada para Firefox, no se afirma sobre Chrome.
    Reset-State
    function Get-NativeMessagingState {
        [ordered]@{ registrado=$true; navegadores=@('Firefox'); manifest='m.json'
                    exeDelManifest='C:\Users\x\AppData\Local\Fudo\fudo_native_extension.exe'; exeExiste=$true
                    extensionIds=@('npcjljaedonmjndbliillcmkhidejhmb'); pendientes=@('Chrome: sin clave de registro') }
    }
    Test-Layer0b-NativeApp
    Assert-Eq 'S98e con Firefox no se afirma sobre la extension de Chrome' 'warn' ([string](Get-CheckById 'fudo.extension').status)

    # Escenario 99: el motor elevado con OTRA cuenta no puede mirar -ni tocar- el perfil del
    # cliente: HKCU y las extensiones son por usuario. Antes de esto habria registrado el host
    # para el administrador y el Chrome del cliente no se enteraba.
    Reset-State
    function Get-SesionInteractiva { [ordered]@{ usuarioMotor='admin'; usuarioSesion='cinthia'; otroPerfil=$true } }
    $script:corrio99 = $false
    function Start-FudoNativeHostProcess { param($Exe, $TimeoutSeg) $script:corrio99 = $true; @{ lanzado=$true; quedoVivo=$false; error='' } }
    Test-Layer0b-NativeApp
    $h99 = Get-CheckById 'nativa.hostRegistrado'
    Assert-Eq 'S99 con otro usuario no se concluye' 'skipped' ([string]$h99.status)
    Assert-Eq 'S99 y no se toca el perfil equivocado' $false ([bool]$script:corrio99)
    Assert-Eq 'S99 la extension tampoco se juzga' $true ([bool]($null -eq (Get-CheckById 'fudo.extension')))

    # Escenario 101: el asesor elige que version de la Nativa instalar. Sale del caso de un
    # asesor al que el antivirus del cliente le bloquea la 0.0.37 firmada siempre, y termina
    # instalando a mano una anterior. El motor elegia solo la mas alta y no habia forma de
    # pedirle otra.
    Reset-State
    Reset-Mocks
    function Get-LocalNativeInstallers {
        @([ordered]@{ ruta='C:\kit\NATIVA FUDO 0.0.37.msi'; version='0.0.37'; esMsi=$true; fecha=(Get-Date) },
          [ordered]@{ ruta='C:\kit\NATIVA FUDO 0.0.33.msi'; version='0.0.33'; esMsi=$true; fecha=(Get-Date) })
    }
    function Test-IsInteractiveConsole { $false }
    $s101 = Select-LocalNativeInstaller -Instalada ''
    Assert-Eq 'S101 sin consola elige la firmada' '0.0.37' ([string]$s101.version)
    Assert-Eq 'S101 y no cuenta como eleccion de una persona' $false ([bool]$s101.elegidoPorPersona)

    # Con consola, el asesor elige la 0.0.33 y confirma que baja de version.
    function Test-IsInteractiveConsole { $true }
    function Suspend-LiveStatus { }
    $script:r101 = @('2', 's')
    $script:i101 = 0
    function Read-DoctorLine { param($Prompt) $v = $script:r101[$script:i101]; $script:i101++; $v }
    $s101b = Select-LocalNativeInstaller -Instalada '0.0.37'
    Assert-Eq 'S101b el asesor puede elegir la mas vieja' '0.0.33' ([string]$s101b.version)
    Assert-Eq 'S101b y queda marcado que lo eligio una persona' $true ([bool]$s101b.elegidoPorPersona)

    # Si no confirma, no se instala nada.
    $script:r101 = @('2', 'n')
    $script:i101 = 0
    $s101c = Select-LocalNativeInstaller -Instalada '0.0.37'
    Assert-Eq 'S101c sin confirmar no se instala nada' '' ([string]$s101c.ruta)
    Assert-Eq 'S101c y el motivo lo dice' $true ([bool]([string]$s101c.motivo -match 'no confirmo'))

    # Enter = la recomendada, y eso NO habilita bajar de version.
    $script:r101 = @('')
    $script:i101 = 0
    $s101d = Select-LocalNativeInstaller -Instalada '0.0.37'
    Assert-Eq 'S101d Enter deja la recomendada' '0.0.37' ([string]$s101d.version)
    Assert-Eq 'S101d y sigue sin ser eleccion de una persona' $false ([bool]$s101d.elegidoPorPersona)

    # Sin instaladores no se inventa nada: se pide el archivo.
    function Get-LocalNativeInstallers { @() }
    $s101e = Select-LocalNativeInstaller -Instalada ''
    Assert-Eq 'S101e sin instaladores no hay ruta' '' ([string]$s101e.ruta)
    Assert-Eq 'S101e y se explica que falta' $true ([bool]([string]$s101e.motivo -match 'no hay ningun instalador'))

    # Y el guardarrail anti-degradacion no pisa lo que eligio el asesor.
    Reset-State
    Reset-Mocks
    function Get-LocalNativeInstallers {
        @([ordered]@{ ruta='C:\kit\NATIVA FUDO 0.0.33.msi'; version='0.0.33'; esMsi=$true; fecha=(Get-Date) })
    }
    function Test-IsInteractiveConsole { $true }
    function Suspend-LiveStatus { }
    function Read-DoctorLine { param($Prompt) 's' }
    function Get-MsiProductVersion { param($Path) '0.0.33' }
    function Find-FudoNativeInstall {
        [ordered]@{ paths=@('C:\Users\x\AppData\Local\Fudo'); regInfo=@([ordered]@{ version='0.0.37'; esPwa=$false })
                    exe='C:\Users\x\AppData\Local\Fudo\fudo_native_extension.exe'; enDisco=$true; soloRegistro=$false; pwa=$false }
    }
    function Get-NativaVersionState { param($Install) [ordered]@{ version='0.0.37'; firmada=$true; confiable=$true } }
    function Add-MpPreference { param($ExclusionPath, $ExclusionProcess, $ErrorAction) }
    function Get-Process { param($ErrorAction) @() }
    function Start-Sleep { param($Seconds, $Milliseconds) }
    $script:llamo101 = $false
    function Invoke-NativeInstallerFile { param($Path, $ExtraArgs) $script:llamo101 = $true; 0 }
    $NativeInstallerPath = 'C:\kit\NATIVA FUDO 0.0.33.msi'
    function Test-Path { param($Path, $ErrorAction) $true }
    function Resolve-Path { param($Path) [pscustomobject]@{ Path = [string]$Path } }
    $r101f = Install-FudoNative
    Assert-Eq 'S101f con -NativeInstallerPath se instala la que se pidio' $true ([bool]$script:llamo101)
    Assert-Eq 'S101f y queda instalada' $true ([bool]$r101f.applied)
    $NativeInstallerPath = ''  # no dejarlo puesto para los escenarios que siguen

    # Escenario 100: impresora instalada con Zadig (Directo USB). No tiene cola de Windows y no
    # la necesita: Fudo le habla directo. El motor le hacia replug por software para que Windows
    # le asignara puerto, o sea que le tocaba el dispositivo a una impresora que andaba bien.
    Reset-State
    Reset-Mocks
    function Get-UsbPrintDevices {
        @([ordered]@{ source='Win32_PnPEntity'; name='POS-80 Printer'; instanceId='USB\VID_0519&PID_0001\6&1234'
                      portName=''; status='OK'; problem=0; deteccion='clase USB 07h (Printer)'; certeza='alta'
                      service='WinUSB'; directoUsb=$true })
    }
    function Get-ProblemPrinterDevices { @() }
    function Get-PrinterPort { param($ErrorAction) @() }
    function Get-Printer { param($ErrorAction) @() }
    $script:replug100 = $false
    function Repair-BindUsbPort { param($InstanceIds) $script:replug100 = $true; @{ puertos=@(); nota='no deberia llamarse' } }
    Test-Layer1a-HardwareInventory
    $z100 = Get-CheckById 'hw.directoUsb'
    Assert-Eq 'S100 reconoce la impresora por Directo USB' $true ([bool]($null -ne $z100))
    Assert-Eq 'S100 y no la reporta como problema' 'ok' ([string]$z100.status)
    Assert-Eq 'S100 no le hace replug por software' $false ([bool]$script:replug100)
    Assert-Eq 'S100 ni la da como sin puerto asignado' $true ([bool]($null -eq (Get-CheckById 'hw.noPortBound')))
    Assert-Eq 'S100 dice que se configura en Fudo' $true ([bool]([string]$z100.recommendation -match 'Directo USB'))

    # Una impresora normal sin puerto sigue yendo por el camino de siempre.
    Reset-State
    function Get-UsbPrintDevices {
        @([ordered]@{ source='Win32_PnPEntity'; name='POS-80 Printer'; instanceId='USB\VID_0519&PID_0001\6&9999'
                      portName=''; status='OK'; problem=0; deteccion='clase USB 07h (Printer)'; certeza='alta'
                      service='usbprint'; directoUsb=$false })
    }
    $script:replug100b = $false
    function Repair-BindUsbPort { param($InstanceIds) $script:replug100b = $true; @{ puertos=@(); nota='sin puerto' } }
    Test-Layer1a-HardwareInventory
    Assert-Eq 'S100b a una impresora normal si se le intenta asignar puerto' $true ([bool]$script:replug100b)
    Assert-Eq 'S100b y no se la llama Directo USB' $true ([bool]($null -eq (Get-CheckById 'hw.directoUsb')))

    Write-Host ""
    Write-Host ("SELF-TEST: {0} PASS / {1} FAIL" -f $script:__p, $script:__f)
    # Salida explicita en los dos casos: si el script termina con 'return', $LASTEXITCODE
    # queda sin definir y cualquier automatizacion lo interpreta como fallo.
    if ($script:__f -gt 0) { exit 4 }
    exit 0
}

# ---------------------------------------------------------------------------
# MENU DE ACCIONES (solo consola interactiva)
# Permite volver a revisar o aplicar una accion sin cerrar y reabrir la app.
# ---------------------------------------------------------------------------
function Reset-RunState {
    <# Deja todo listo para una corrida nueva dentro de la misma sesion. #>
    $script:Checks      = New-Object System.Collections.ArrayList
    $script:Actions     = New-Object System.Collections.ArrayList
    $script:Errors      = New-Object System.Collections.ArrayList
    $script:Log         = New-Object System.Collections.ArrayList
    $script:Diagnostics = [ordered]@{}
    $script:StartTime   = Get-Date
    $script:StepIndex   = 0
    $script:StepLabel   = ''
    $script:StepNote    = ''
    $script:PresentIds  = $null
    $script:PresentIdsOk = $false
    $script:ReconnectedPort = ''
    $script:UpdateNote  = ''
    # $script:TestPrintersCreated NO se limpia: son colas reales ya creadas en la PC.
}

function Get-MenuOptions {
    <# Opciones disponibles segun lo que se encontro. Las letras son estables. #>
    $ops = @()
    $ops += [ordered]@{ k = 'R'; t = 'Volver a revisar todo' }

    $hayDesconectada = @($script:Checks | Where-Object { $_.id -in @('printer.disconnected','hw.disconnected') -and $_.status -eq 'fail' }).Count -gt 0
    if ($hayDesconectada) { $ops += [ordered]@{ k = 'U'; t = 'Esperar a que conectes/desconectes el USB y revisar de nuevo' } }

    $huerfanos = @()
    if ($script:Diagnostics.Contains('orphanLivePorts')) { $huerfanos = @($script:Diagnostics['orphanLivePorts'] | Where-Object { $_ }) }
    if (@($huerfanos).Count -gt 0) {
        $ops += [ordered]@{ k = 'I'; t = ("Instalar la impresora conectada en " + (@($huerfanos) -join ', ')) }
    } else {
        # Tambien cuando la impresora esta conectada pero Windows no le dio puerto: ahi la
        # opcion es reiniciar el device para que aparezca el puerto y despues crear la cola.
        $sinPuerto = @()
        if ($script:Diagnostics.Contains('printersConnected')) {
            $sinPuerto = @($script:Diagnostics['printersConnected'] | Where-Object { -not $_.puerto -and -not $_.colaWindows })
        }
        if (@($sinPuerto).Count -gt 0) {
            $ops += [ordered]@{ k = 'I'; t = ("Levantar la impresora conectada (" + [string](@($sinPuerto)[0].nombre) + "): reiniciar el dispositivo y crear la cola") }
        }
    }

    $conCola = @()
    if ($script:Diagnostics.Contains('colas')) { $conCola = @($script:Diagnostics['colas'] | Where-Object { [int]$_.trabajos -gt 0 }) }
    if (@($conCola).Count -gt 0) {
        $c0 = @($conCola)[0]
        $ops += [ordered]@{ k = 'L'; t = ("Limpiar la cola de '" + [string]$c0.nombre + "' (" + [string]$c0.trabajos + ' trabajos)'); target = [string]$c0.nombre }
    }

    $ops += [ordered]@{ k = 'N'; t = 'Buscar impresoras en la red (por IP)' }
    $enRed = @()
    if ($script:Diagnostics.Contains('impresorasEnRed')) { $enRed = @($script:Diagnostics['impresorasEnRed']) }
    if (@($enRed).Count -gt 0) { $ops += [ordered]@{ k = 'P'; t = 'Instalar una de las impresoras de red encontradas' } }

    $nativaMal = @($script:Checks | Where-Object { $_.id -like 'nativa.*' -and $_.status -in @('fail','warn') }).Count -gt 0
    if ($nativaMal) { $ops += [ordered]@{ k = 'F'; t = 'Instalar / reparar la App Nativa de Fudo' } }

    if ($script:UpdateNote) {
        $ops += [ordered]@{ k = 'A'; t = 'Actualizar el motor a la ultima version publicada' }
    }
    $ops += [ordered]@{ k = 'T'; t = 'Imprimir un ticket de prueba' }
    $ops += [ordered]@{ k = 'D'; t = 'Ver el detalle completo de los chequeos' }
    $ops += [ordered]@{ k = 'J'; t = 'Guardar el JSON en un archivo' }
    $ops += [ordered]@{ k = 'S'; t = 'Salir' }
    return @($ops)
}

function Resolve-MenuChoice {
    <#
      Decide que hacer con lo que escribio el asesor. Separado de la lectura para poder
      testearlo: 'NOKEY' = no hay teclado (avisar y salir), '?' = volver a preguntar
      (incluye Enter pelado, que antes cerraba la app en silencio).
    #>
    param($Raw, [string[]]$Keys)
    if ($null -eq $Raw) { return 'NOKEY' }
    $r = ([string]$Raw).Trim().ToUpper()
    if (-not $r) { return '?' }
    if (@($Keys) -contains $r) { return $r }
    return '?'
}

function Show-DoctorMenu {
    $ops = @(Get-MenuOptions)
    Write-Host ''
    Write-Host '  ==============================================================' -ForegroundColor DarkGray
    Write-Host '   QUE QUERES HACER AHORA' -ForegroundColor Cyan
    Write-Host '  ==============================================================' -ForegroundColor DarkGray
    foreach ($o in $ops) {
        $color = $(if ($o.k -eq 'S') { 'DarkGray' } else { 'Gray' })
        Write-Host ("   [" + $o.k + "]  " + $o.t) -ForegroundColor $color
    }
    Write-Host ''
    $r = Resolve-MenuChoice -Raw (Read-DoctorKey -Prompt '   Opcion') -Keys @($ops | ForEach-Object { [string]$_.k })
    if ($r -eq 'NOKEY') {
        # No hay teclado: antes esto se interpretaba como "salir" y el menu se cerraba
        # solo, dando la sensacion de que las opciones no se podian elegir.
        Write-Host ''
        Write-Host '   No puedo leer el teclado desde esta ventana.' -ForegroundColor Red
        Write-Host '   Cerra esta ventana y abri FudoPrintDoctor.cmd con doble clic' -ForegroundColor Yellow
        Write-Host '   (si se abrio desde una herramienta de acceso remoto o un acceso' -ForegroundColor Yellow
        Write-Host '   directo, la ventana puede quedar sin teclado).' -ForegroundColor Yellow
        return 'S'
    }
    if ($r -eq '?') { Write-Host '   Escribi la letra de la opcion (por ejemplo T) o S para salir.' -ForegroundColor DarkGray }
    return $r
}

function Invoke-MenuAction {
    <# Ejecuta la opcion elegida. Devuelve $true si hay que volver a diagnosticar. #>
    param([string]$Op)

    switch ($Op) {
        'R' { return $true }

        'U' {
            $script:ForceWaitReconnect = $true
            $nombre = ''
            if ($script:Diagnostics.Contains('printer')) { $nombre = [string]$script:Diagnostics['printer'].name }
            $pr = $null
            if ($nombre) { try { $pr = Get-Printer -Name $nombre -ErrorAction SilentlyContinue } catch {} }
            if ($pr) {
                $f = Invoke-ReconnectFlow -Printer $pr
                Write-Host ''
                Write-Host ('  ' + $(if ($f.recovered) { 'Recuperada: ' } else { 'Sin exito: ' }) + [string]$f.note) -ForegroundColor $(if ($f.recovered) { 'Green' } else { 'Yellow' })
            } else {
                Write-Host ''
                Write-Host '  Desenchufa y volve a enchufar el USB de la impresora (encendida)...' -ForegroundColor Cyan
                $puerto = Wait-ForPrinterReconnect -TimeoutSec $ReconnectTimeoutSec
                Write-Host ''
                if ($puerto) { Write-Host ("  Aparecio una impresora en " + $puerto) -ForegroundColor Green }
                else { Write-Host '  No se detecto ninguna impresora nueva.' -ForegroundColor Yellow }
            }
            $script:ForceWaitReconnect = $false
            return $true
        }

        'I' {
            $huerfanos = @()
            if ($script:Diagnostics.Contains('orphanLivePorts')) { $huerfanos = @($script:Diagnostics['orphanLivePorts'] | Where-Object { $_ }) }
            $oemDriver = ''
            if (@($huerfanos).Count -eq 0) {
                # No hay puerto todavia: primero el replug por software.
                $sinPuerto = @()
                if ($script:Diagnostics.Contains('printersConnected')) {
                    $sinPuerto = @($script:Diagnostics['printersConnected'] | Where-Object { -not $_.puerto })
                }
                if (@($sinPuerto).Count -eq 0) { Write-Host '  Ya no hay impresoras conectadas sin instalar.' -ForegroundColor Yellow; return $true }
                try { $oemDriver = [string](@($sinPuerto | Where-Object { $_.driverNombre })[0].driverNombre) } catch {}
                Write-Host ''
                Write-Host '  Reiniciando el dispositivo para que Windows le asigne un puerto USB...' -ForegroundColor Cyan
                $r = Repair-BindUsbPort -InstanceIds @($sinPuerto | ForEach-Object { [string]$_.instanceId })
                if (@($r.puertos).Count -eq 0) {
                    Write-Host ('  No se pudo: ' + [string]$r.nota) -ForegroundColor Yellow
                    Write-Host '  Probar a mano: con la impresora encendida, desenchufar el USB, esperar 5 segundos y enchufarlo en un puerto directo (sin hub).' -ForegroundColor Yellow
                    return $true
                }
                Write-Host ('  Windows asigno ' + (@($r.puertos) -join ', ')) -ForegroundColor Green
                $cola = New-FudoPrinterQueue -PortName (@($r.puertos)[0]) -PreferDriver $oemDriver
                if ($cola.ok) {
                    Write-Host ('  ' + [string]$cola.nota) -ForegroundColor Green
                    Write-Host '  Acordate de registrarla en Fudo (Administracion > Impresoras) con su cocina/area.' -ForegroundColor Yellow
                } else {
                    Write-Host ('  ' + [string]$cola.nota) -ForegroundColor Red
                }
                return $true
            }
            $puerto = @($huerfanos)[0]
            $nombre = ''
            try { $nombre = Read-DoctorLine -Prompt ("   Nombre para la impresora en $puerto (Enter = FUDO-TEST-$puerto)") } catch {}
            try {
                $creada = New-FudoTestPrinter -PortName $puerto
                if ($creada -and $nombre) {
                    try { Rename-Printer -Name $creada -NewName $nombre -ErrorAction Stop; $creada = $nombre
                          $i = $script:TestPrintersCreated.IndexOf($creada); if ($i -ge 0) { $script:TestPrintersCreated.RemoveAt($i) } } catch {}
                }
                Write-Host ("  Cola '" + $creada + "' creada en " + $puerto) -ForegroundColor Green
                Write-Host '  Acordate de registrarla en Fudo (Administracion > Impresoras) con su cocina/area.' -ForegroundColor Yellow
            } catch { Write-Host ("  No se pudo crear: " + $_.Exception.Message) -ForegroundColor Red }
            return $true
        }

        'L' {
            $conCola = @()
            if ($script:Diagnostics.Contains('colas')) { $conCola = @($script:Diagnostics['colas'] | Where-Object { [int]$_.trabajos -gt 0 }) }
            if (@($conCola).Count -eq 0) { Write-Host '  No hay colas con trabajos pendientes.' -ForegroundColor Yellow; return $true }
            $nombre = [string]@($conCola)[0].nombre
            $cant = [string]@($conCola)[0].trabajos
            if (Confirm-Irreversible -Description "Limpiar la cola de '$nombre' ($cant trabajos)" -Impact 'se descartan las comandas que estan esperando; hay que volver a imprimirlas desde Fudo') {
                try {
                    Get-PrintJob -PrinterName $nombre -ErrorAction SilentlyContinue | Remove-PrintJob -ErrorAction SilentlyContinue
                    Add-Action -Type 'queue.purge' -Target $nombre -Before "$cant jobs" -After '0 jobs' -Reversible $false
                    Write-Host ("  Cola de '" + $nombre + "' limpiada.") -ForegroundColor Green
                } catch { Write-Host ("  No se pudo limpiar: " + $_.Exception.Message) -ForegroundColor Red }
            }
            return $true
        }

        'N' {
            $prefijos = @(Get-LocalSubnetPrefixes)
            if (@($prefijos).Count -eq 0) { Write-Host '  No se pudo determinar la red local.' -ForegroundColor Yellow; return $false }
            Write-Host ''
            Write-Host ("  Buscando impresoras en " + (@($prefijos | ForEach-Object { $_ + '.0/24' }) -join ', ') + " ... (puede tardar unos segundos)") -ForegroundColor Cyan
            $enc = @()
            foreach ($pref in @($prefijos | Select-Object -First 2)) { $enc += @(Find-NetworkPrinters -Prefix $pref -TcpPort $Port) }
            $script:Diagnostics['impresorasEnRed'] = @($enc)
            $inst = @(Get-InstalledNetworkPrinters)
            $script:Diagnostics['impresorasRedInstaladas'] = @($inst)
            Write-Host ''
            if (@($enc).Count -eq 0) {
                Write-Host '  No se encontraron impresoras por IP en la red.' -ForegroundColor Yellow
                Write-Host '  Revisar que la comandera este encendida, con cable de red, y hacer su' -ForegroundColor DarkGray
                Write-Host '  self-test (apagar, mantener FEED, encender) para leer la IP que tiene.' -ForegroundColor DarkGray
            } else {
                Write-Host ("  Encontradas: " + @($enc).Count) -ForegroundColor Green
                foreach ($e in $enc) {
                    $ya = @($inst | Where-Object { [string]$_.ip -eq [string]$e.ip })
                    $extra = $(if (@($ya).Count -gt 0) { '  -> hay cola de Windows: ' + ((@($ya | ForEach-Object { @($_.colas) }) | Where-Object { $_ }) -join ', ') } else { '  -> sin cola en Windows' })
                    Write-Host ("    - " + [string]$e.ip + ':' + [string]$e.puerto + '  ' + [string]$e.tipo + $extra)
                }
            }
            return $false
        }

        'P' {
            $enRed = @()
            if ($script:Diagnostics.Contains('impresorasEnRed')) { $enRed = @($script:Diagnostics['impresorasEnRed']) }
            if (@($enRed).Count -eq 0) { Write-Host '  Primero buscar impresoras en la red (opcion N).' -ForegroundColor Yellow; return $false }
            Write-Host ''
            $i = 0
            foreach ($e in $enRed) { $i++; Write-Host ("   [$i] " + [string]$e.ip + ':' + [string]$e.puerto + '  ' + [string]$e.tipo) }
            $sel = ''
            try { $sel = Read-DoctorLine -Prompt '   Cual instalar? (numero, Enter para cancelar)' } catch {}
            if (-not $sel) { return $false }
            $idx = 0
            try { $idx = [int]$sel } catch { return $false }
            if ($idx -lt 1 -or $idx -gt @($enRed).Count) { Write-Host '  Numero invalido.' -ForegroundColor Yellow; return $false }
            $elegida = @($enRed)[$idx - 1]
            $nombre = ''
            try { $nombre = Read-DoctorLine -Prompt ("   Nombre para la impresora (Enter = FUDO-" + (([string]$elegida.ip) -replace '\.', '-') + ')') } catch {}
            try {
                $creada = New-NetworkPrinter -Ip ([string]$elegida.ip) -TcpPort ([int]$elegida.puerto) -Name $nombre
                Write-Host ("  Cola '" + $creada + "' creada apuntando a " + [string]$elegida.ip + ':' + [string]$elegida.puerto) -ForegroundColor Green
                Write-Host '  Mandando un ticket de prueba...' -ForegroundColor Cyan
                $ok = $false
                try { $ok = Send-EscPosOverTcp -Ip ([string]$elegida.ip) -TcpPort ([int]$elegida.puerto) } catch {}
                Write-Host ('  ' + $(if ($ok) { 'Ticket enviado: si salio el papel, la impresora esta lista.' } else { 'No se pudo enviar el ticket.' })) -ForegroundColor $(if ($ok) { 'Green' } else { 'Yellow' })
                Write-Host ''
                Write-Host '  Ahora, en Fudo (Administracion > Impresoras):' -ForegroundColor Yellow
                Write-Host ("    - Si la vas a usar como IMPRESORA DEL SISTEMA: elegila por su nombre '" + $creada + "'.") -ForegroundColor Yellow
                Write-Host ("    - Si vas a usar DIRECTO ETHERNET: no hace falta esta cola, alcanza con cargar la IP " + [string]$elegida.ip + " y el puerto " + [string]$elegida.puerto + '.') -ForegroundColor Yellow
                Write-Host '    En los dos casos hay que asignarle la cocina/area.' -ForegroundColor Yellow
            } catch { Write-Host ("  No se pudo instalar: " + $_.Exception.Message) -ForegroundColor Red }
            return $true
        }

        'F' { $null = Install-FudoNative; return $true }

        'A' {
            # Actualizacion explicita, pedida por la persona que esta mirando la consola.
            # A proposito NO es automatica: ver la nota en la cabecera del script.
            $destino = ''
            try { $destino = [string]$PSCommandPath } catch {}
            if (-not $destino) { Write-Host '  No se pudo determinar la ruta del script.' -ForegroundColor Red; return $false }
            $tmp = Join-Path $env:TEMP ('FudoPrintDoctor-nuevo-' + (Get-Date).ToString('HHmmss') + '.ps1')
            try {
                Write-Host ''
                Write-Host '  Descargando la ultima version...' -ForegroundColor Cyan
                try { [Net.ServicePointManager]::SecurityProtocol = [Net.SecurityProtocolType]::Tls12 } catch {}
                Invoke-WebRequest -Uri ($script:RawBase + '/FudoPrintDoctor.ps1') -UseBasicParsing -TimeoutSec 90 -OutFile $tmp -ErrorAction Stop

                # Validaciones antes de reemplazar nada
                $contenido = Get-Content -Path $tmp -Raw -ErrorAction Stop
                if ($contenido.Length -lt 50000 -or ($contenido -notmatch 'FudoPrintDoctor')) {
                    throw 'lo que se descargo no parece el motor (archivo corto o sin la firma esperada)'
                }
                $verNueva = ''
                $m = [regex]::Match($contenido, "SchemaVersion\s*=\s*'([\d.]+)'")
                if ($m.Success) { $verNueva = $m.Groups[1].Value }
                if (-not $verNueva) { throw 'no se pudo leer la version del archivo descargado' }

                # Copia de seguridad del actual, por si hay que volver atras
                $backup = "$destino.bak"
                try { Copy-Item -Path $destino -Destination $backup -Force -ErrorAction Stop } catch {}

                Move-Item -Path $tmp -Destination $destino -Force -ErrorAction Stop
                Write-Host ("  Actualizado a la version " + $verNueva + '.') -ForegroundColor Green
                Write-Host ("  Copia de la anterior: " + $backup) -ForegroundColor DarkGray
                Write-Host '  Cerra esta ventana y volve a abrir el Print Doctor para usar la version nueva.' -ForegroundColor Yellow
            } catch {
                Write-Host ("  No se pudo actualizar: " + $_.Exception.Message) -ForegroundColor Red
                Write-Host ('  Alternativa: bajar el ZIP de ' + $script:RepoUrl) -ForegroundColor DarkGray
                try { if (Test-Path $tmp) { Remove-Item $tmp -Force -ErrorAction SilentlyContinue } } catch {}
            }
            return $false
        }

        'T' {
            $nombre = ''
            if ($script:Diagnostics.Contains('printer')) { $nombre = [string]$script:Diagnostics['printer'].name }
            if (-not $nombre) { Write-Host '  No hay impresora objetivo para probar.' -ForegroundColor Yellow; return $false }
            try {
                Initialize-RawPrinterHelper
                $bytes = [System.Text.Encoding]::GetEncoding(437).GetBytes((Get-EscPosTestTicket -Caption 'FUDO PRUEBA MANUAL'))
                $ok = [FudoRawPrinter]::SendBytes($nombre, $bytes)
                if (-not $ok) { Write-Host '  No se pudo enviar el ticket (el spooler lo rechazo).' -ForegroundColor Red; return $false }
                Write-Host '  Enviado. Esperando que salga de la cola...' -ForegroundColor DarkGray
                $drain = Wait-QueueDrain -Printer $nombre
                if ($drain.quedoEnCola) {
                    Write-Host '  El ticket quedo en la cola: la impresora no esta respondiendo.' -ForegroundColor Yellow
                    if ([int]$drain.bloqueadoPor -gt 0) {
                        Write-Host ("  Ojo: hay " + [int]$drain.bloqueadoPor + " trabajo(s) viejo(s) delante bloqueando la cola. Limpiala y volve a probar.") -ForegroundColor Yellow
                    }
                    return $false
                }
                # Salio de la cola != salio papel. Preguntamos siempre: es la unica verificacion real.
                $salio = Confirm-PaperCameOut -Printer $nombre
                if ($salio -eq $true) {
                    Write-Host '  Confirmado: el hardware imprime. Si la comanda no sale, el problema es la config de Fudo (area/cocina/sala/categorias).' -ForegroundColor Green
                } elseif ($salio -eq $false) {
                    Write-Host '  El spooler lo dio por impreso pero no salio papel: no es Windows ni la cola.' -ForegroundColor Red
                    Write-Host '  Revisar rollo (que haya papel y este del lado correcto), tapa cerrada, y el cable hasta la impresora.' -ForegroundColor Yellow
                    Write-Host '  Si la impresora entra por un adaptador USB-paralelo, verificar que del otro lado haya impresora.' -ForegroundColor DarkGray
                } else {
                    Write-Host '  El ticket salio de la cola de Windows (es todo lo que se puede verificar por software).' -ForegroundColor Yellow
                    Write-Host '  Hay que mirar la impresora para saber si salio el papel.' -ForegroundColor DarkGray
                }
            } catch { Write-Host ("  Error: " + $_.Exception.Message) -ForegroundColor Red }
            return $false
        }

        'D' {
            Write-Host ''
            foreach ($c in @($script:Checks)) {
                $col = switch ([string]$c.status) { 'fail' { 'Red' } 'warn' { 'Yellow' } 'fixed' { 'Green' } 'ok' { 'DarkGreen' } default { 'DarkGray' } }
                Write-Host ("   [{0,-8}] L{1} {2}" -f [string]$c.status, $c.layer, [string]$c.name) -ForegroundColor $col
                if ($c.recommendation) { foreach ($ln in @(Format-Wrap -Text ([string]$c.recommendation) -Width 66 -Indent '            ')) { Write-Host ('          ' + $ln) -ForegroundColor DarkGray } }
            }
            return $false
        }

        'J' {
            $ruta = ''
            try { $ruta = Read-DoctorLine -Prompt '   Ruta del archivo (Enter = resultado.json aca al lado)' } catch {}
            if (-not $ruta) { $ruta = Join-Path (Get-Location) 'resultado.json' }
            try {
                ($script:LastResult | ConvertTo-Json -Depth 12) | Out-File -FilePath $ruta -Encoding UTF8
                Write-Host ("  Guardado en " + $ruta) -ForegroundColor Green
            } catch { Write-Host ("  No se pudo guardar: " + $_.Exception.Message) -ForegroundColor Red }
            return $false
        }
    }
    return $false
}

# ---------------------------------------------------------------------------
# CONTRATO DE SALIDA (para el agente que corre el script)
#   stdout : SOLO el JSON, delimitado por <<<FUDO_JSON_BEGIN>>> / <<<FUDO_JSON_END>>>
#   stderr : resumen humano (es-AR) y avisos. Usar -Quiet para silenciarlo.
#   exit   : 0 = resuelto | 2 = requiere escalamiento | 3 = falla del motor | 4 = self-test fallido
#            5 = motor desactualizado (no corrio) | 6 = falta el ID de conversacion (no corrio)
#            7 = falta el .msi de la App Nativa firmada y el asesor eligio no seguir (no corrio)
# ---------------------------------------------------------------------------
function Get-LocalNativeInstallers {
    <#
      TODOS los instaladores de la Nativa que hay en la PC, con la version que declara cada uno.
      Antes esto devolvia el primero que aparecia ordenando por fecha, y con eso el motor podia
      instalar un instalador viejo que el cliente tenia en Descargas de hace meses: una version
      sin firmar que el antivirus vuelve a comerse. Lo reporto un asesor -"siento que no instala
      la nativa correcta o al menos una version compatible"- y tenia razon.
      Devuelve @( @{ ruta; version; esMsi; fecha } ), ordenados por version descendente y, entre
      los que no declaran version, por fecha.
    #>
    $donde = @()
    try { $donde += (Split-Path -Parent $PSCommandPath) } catch {}
    try { $donde += (Get-Location).Path } catch {}
    if ($env:USERPROFILE) { $donde += @((Join-Path $env:USERPROFILE 'Downloads'), (Join-Path $env:USERPROFILE 'Desktop')) }
    $vistos = @()
    $out = @()
    foreach ($d in @($donde | Where-Object { $_ })) {
        # El .msi va primero: es el formato de la version vigente y el unico del que se puede
        # leer la version sin ejecutarlo.
        foreach ($pat in @('Fudo*.msi','*fudo*.msi','*Nativa*.msi','Fudo*.exe','*fudo*.exe','*Nativa*.exe')) {
            try {
                foreach ($f in @(Get-ChildItem -Path $d -Filter $pat -File -ErrorAction SilentlyContinue | Where-Object { $_.Length -gt 200KB })) {
                    $ruta = [string]$f.FullName
                    if ($vistos -contains $ruta.ToLower()) { continue }
                    $vistos += $ruta.ToLower()
                    $esMsi = [bool]($ruta -match '(?i)\.msi$')
                    $ver = ''
                    if ($esMsi) { $ver = [string](Get-MsiProductVersion -Path $ruta) }
                    $out += [ordered]@{ ruta = $ruta; version = $ver; esMsi = $esMsi; fecha = $f.LastWriteTime }
                }
            } catch {}
        }
    }
    # Orden: los que declaran version primero, de mayor a menor; despues los que no, por fecha.
    $conVer = @($out | Where-Object { $_.version } | Sort-Object -Property @{ Expression = {
                    $v = $null; try { $v = [version]$_.version } catch { $v = [version]'0.0.0' }; $v } ; Descending = $true })
    $sinVer = @($out | Where-Object { -not $_.version } | Sort-Object -Property fecha -Descending)
    return @(@($conVer) + @($sinVer))
}

function Find-LocalNativeInstaller {
    <#
      El MEJOR instalador de la Nativa que hay en la PC: el de version mas alta, no el mas
      reciente por fecha. Ver Get-LocalNativeInstallers para el por que.
    #>
    if ($NativeInstallerPath) {
        if (Test-Path $NativeInstallerPath) { return (Resolve-Path $NativeInstallerPath).Path }
        return ''
    }
    $c = @(Get-LocalNativeInstallers) | Select-Object -First 1
    if ($c) { return [string]$c.ruta }
    return ''
}

function Test-NativaKitReady {
    <#
      El asesor trajo el instalador de la Nativa firmada?
      OJO: esto NO mira lo que tiene instalado el cliente. Mira si en la PC hay un .msi que
      declare la version firmada o superior, que es lo unico con lo que el motor puede
      actualizar una Nativa vieja. Sin ese archivo, una PC con la 0.0.18 se queda con la 0.0.18
      y el antivirus vuelve a comersela: el motor avisa y no tiene con que resolverlo.
      Se chequea siempre, independientemente del cliente, porque es un item del kit del asesor
      -se arregla una vez y sirve para todos los casos- y no algo para descubrir cliente por
      cliente en medio de una llamada.
      Devuelve @{ listo; ruta; version; candidatos; motivo }
    #>
    $cands = @(Get-LocalNativeInstallers)
    $firmada = [string]$script:NativaVersionFirmada
    $ok = @($cands | Where-Object {
        $v = $null
        try { $v = [version]$_.version } catch { $v = $null }
        ($null -ne $v) -and ($v -ge [version]$firmada)
    }) | Select-Object -First 1
    if ($ok) {
        return [ordered]@{ listo = $true; ruta = [string]$ok.ruta; version = [string]$ok.version
                           candidatos = @($cands); motivo = '' }
    }
    $mejor = @($cands | Where-Object { $_.version }) | Select-Object -First 1
    $motivo = $(if (@($cands).Count -eq 0) { 'no hay ningun instalador de la App Nativa en esta PC' }
                elseif ($mejor) { 'el instalador que hay declara la version ' + [string]$mejor.version + ', anterior a la ' + $firmada }
                else { 'hay instaladores pero ninguno declara su version (solo .exe): no se puede saber si sirven' })
    return [ordered]@{ listo = $false; ruta = ''; version = ''; candidatos = @($cands); motivo = $motivo }
}

function Confirm-NativaKit {
    <#
      Le avisa al asesor que le falta el .msi de la Nativa firmada y le pide confirmacion para
      seguir igual. No bloquea el diagnostico: la impresora puede estar rota por algo que no
      tiene nada que ver con la Nativa, y dejar al asesor sin herramienta seria peor.
      Sin consola (modo agente) no se puede preguntar: se sigue y queda registrado.
      Devuelve $true si hay que seguir.
    #>
    param($Kit)
    if ($NoNativaKitCheck) { $script:NativaKitOmitido = $true; return $true }
    if ($Kit -and [bool]$Kit.listo) { return $true }
    if (-not (Test-IsInteractiveConsole)) { return $true }

    Suspend-LiveStatus
    [Console]::Error.WriteLine('')
    [Console]::Error.WriteLine('  ------------------------------------------------------------')
    [Console]::Error.WriteLine(('  FALTA EL INSTALADOR DE LA APP NATIVA (.msi de la v' + $script:NativaVersionFirmada + ')'))
    [Console]::Error.WriteLine('')
    [Console]::Error.WriteLine(('  ' + [string]$Kit.motivo + '.'))
    [Console]::Error.WriteLine('')
    [Console]::Error.WriteLine('  Sin ese archivo, si este cliente tiene una version vieja de la App Nativa el')
    [Console]::Error.WriteLine('  motor NO puede actualizarla, y el antivirus se la va a volver a comer. Desde')
    [Console]::Error.WriteLine(('  la v' + $script:NativaVersionFirmada + ' esta firmada y el antivirus deja de bloquearla.'))
    [Console]::Error.WriteLine('')
    [Console]::Error.WriteLine('  Copia el .msi a la misma carpeta que este script y volve a correrlo. Conviene')
    [Console]::Error.WriteLine('  tenerlo SIEMPRE junto a los dos archivos que copias a la PC del cliente: se')
    [Console]::Error.WriteLine('  arregla una vez y sirve para todos los casos.')
    [Console]::Error.WriteLine('  ------------------------------------------------------------')
    $ans = Read-DoctorLine -Prompt '  Seguir igual sin poder actualizar la Nativa? (s = si / cualquier otra tecla = cortar)'
    if ($null -eq $ans) { return $true }
    return ($ans -match '(?i)^\s*(s|si|s\u00ED|y|yes)\s*$')
}

function Get-MsiProductVersion {
    <#
      Version que declara un .msi, leida de su tabla Property (ProductVersion) con el COM de
      Windows Installer. Sin esto habria que instalar a ciegas o confiar en el nombre del archivo,
      y no se podria saber si el instalador que hay al lado del script es mas nuevo que lo que la
      PC ya tiene. Devuelve '' si no se puede leer.
    #>
    param([string]$Path)
    if (-not $Path) { return '' }
    if ($Path -notmatch '(?i)\.msi$') { return '' }
    if (-not (Test-Path $Path)) { return '' }
    $ver = ''
    $wi = $null; $db = $null; $vw = $null
    try {
        $wi = New-Object -ComObject WindowsInstaller.Installer
        $db = $wi.GetType().InvokeMember('OpenDatabase', 'InvokeMethod', $null, $wi, @((Resolve-Path $Path).Path, 0))
        $q  = "SELECT Value FROM Property WHERE Property = 'ProductVersion'"
        $vw = $db.GetType().InvokeMember('OpenView', 'InvokeMethod', $null, $db, @($q))
        $null = $vw.GetType().InvokeMember('Execute', 'InvokeMethod', $null, $vw, $null)
        $rec = $vw.GetType().InvokeMember('Fetch', 'InvokeMethod', $null, $vw, $null)
        if ($rec) { $ver = [string]$rec.GetType().InvokeMember('StringData', 'GetProperty', $null, $rec, @(1)) }
    } catch {}
    finally {
        try { if ($vw) { $null = $vw.GetType().InvokeMember('Close', 'InvokeMethod', $null, $vw, $null) } } catch {}
        foreach ($o in @($vw, $db, $wi)) {
            try { if ($o) { [void][Runtime.InteropServices.Marshal]::ReleaseComObject($o) } } catch {}
        }
    }
    return ([string]$ver).Trim()
}

function Test-NativaNecesitaUpdate {
    <#
      Conviene actualizar la Nativa con el instalador que hay en la PC?
      Solo si hay instalador, hay algo instalado, y el instalador declara una version MAS NUEVA.
      Si el instalador no dice su version no se toca nada: instalar a ciegas puede DEGRADAR la
      Nativa, que es un problema ya visto en este proyecto (una restauracion de cuarentena dejo
      0.0.36 -> 0.0.18, y la 0.0.18 despues aparecio circulando en varias PCs).
      Devuelve: actualizar (bool), motivo (texto).
    #>
    param([string]$Instalada, [string]$Disponible)
    if (-not $Disponible) { return @{ actualizar = $false; motivo = 'no hay instalador con version legible en la PC' } }
    if (-not $Instalada)  { return @{ actualizar = $false; motivo = 'no hay Nativa instalada: corresponde instalar, no actualizar' } }
    $mas = $null
    try { $mas = ([version]$Disponible -gt [version]$Instalada) } catch { $mas = $null }
    if ($null -eq $mas) { return @{ actualizar = $false; motivo = ('no se pudieron comparar las versiones (' + $Instalada + ' vs ' + $Disponible + ')') } }
    if (-not $mas)      { return @{ actualizar = $false; motivo = ('el instalador no es mas nuevo (instalada ' + $Instalada + ', instalador ' + $Disponible + ')') } }
    return @{ actualizar = $true; motivo = ('el instalador trae la ' + $Disponible + ' y la PC tiene la ' + $Instalada) }
}

function Invoke-NativeInstallerFile {
    <#
      Ejecuta el instalador de la Nativa. Un .msi NO se ejecuta directo: va por msiexec, y en
      silencio, para no dejar un asistente abierto en la PC del cliente.
      Devuelve el codigo de salida, o $null si no se pudo lanzar.
    #>
    param([string]$Path, [string]$ExtraArgs = '')
    if (-not $Path) { return $null }
    try {
        if ($Path -match '(?i)\.msi$') {
            $msiArgs = '/i "' + (Resolve-Path $Path).Path + '" /qn /norestart'
            if ($ExtraArgs) { $msiArgs = $msiArgs + ' ' + $ExtraArgs }
            $pr = Start-Process -FilePath 'msiexec.exe' -ArgumentList $msiArgs -PassThru -Wait -ErrorAction Stop
            return [int]$pr.ExitCode
        }
        $pr = $(if ($ExtraArgs) { Start-Process -FilePath $Path -ArgumentList $ExtraArgs -PassThru -Wait -ErrorAction Stop }
                else            { Start-Process -FilePath $Path -PassThru -Wait -ErrorAction Stop })
        return [int]$pr.ExitCode
    } catch { return $null }
}

function Update-FudoNativeFromLocal {
    <#
      Actualiza la Nativa con un instalador que ya esta en la PC (al lado del script, en Descargas
      o en el Escritorio). La telemetria del 03/09 mostro la Nativa 0.0.18 en 10 de 24 corridas y
      solo 6 con la 0.0.37 firmada: actualizarla es la solucion de fondo, porque la firmada ya no
      la bloquea el antivirus.
      Verifica DESPUES de instalar: si la version no subio, no se declara actualizada.
    #>
    param([string]$Instalada, [bool]$Corriendo = $false)
    $inst = Find-LocalNativeInstaller
    if (-not $inst) { return @{ aplicado = $false; subio = $false; intento = $false; motivo = 'no hay instalador de la Nativa en la PC' } }
    $verInst = Get-MsiProductVersion -Path $inst
    $dec = Test-NativaNecesitaUpdate -Instalada $Instalada -Disponible $verInst
    if (-not $dec.actualizar) {
        return @{ aplicado = $false; subio = $false; intento = $false; motivo = [string]$dec.motivo; instalador = $inst; versionInstalador = $verInst }
    }
    # v3.15: el codigo de salida del instalador se perdia adentro del scriptblock, asi que
    # cuando la actualizacion no tomaba no habia con que explicar por que. Se saca por un
    # hashtable (mutar el objeto si se ve desde afuera; reasignar la variable, no).
    $salida = @{ code = $null }
    $rem = Invoke-Remediation -Description ('Actualizar la App Nativa a la ' + $verInst + ' con el instalador que ya esta en la PC') `
        -Type 'nativa.update_local' -Target 'FudoNativa' -Before $Instalada -After $verInst -Reversible $true -Fix {
            $notas = @()
            $code = Invoke-NativeInstallerFile -Path $inst -ExtraArgs $NativeInstallerArgs
            $salida.code = $code
            $notas += $(if ($null -eq $code) { 'no se pudo lanzar el instalador' } else { 'el instalador termino con codigo ' + $code })
            Start-Sleep -Seconds 3
            ($notas -join ' | ')
        }
    $verDespues = ''
    if ($rem.applied) {
        try { $verDespues = [string](Get-NativaVersionState -Install (Find-FudoNativeInstall)).version } catch {}
    }
    $subio = $false
    try { $subio = ([bool]$verDespues -and ([version]$verDespues -gt [version]$Instalada)) } catch {}
    # Por que no tomo. Es lo que faltaba en pantalla y en la planilla: un asesor lo intento tres
    # veces sobre la misma PC y termino reinstalando a mano, sin que el motor dijera nada.
    $porQueNo = ''
    if ($rem.applied -and -not $subio) {
        $porQueNo = $(
            if ($null -eq $salida.code)      { 'no se pudo lanzar el instalador (' + $inst + ')' }
            elseif ([int]$salida.code -ne 0) { 'el instalador termino con codigo ' + $salida.code }
            elseif ($Corriendo)              { 'el instalador termino bien pero la version no cambio, y la App Nativa estaba corriendo: probablemente no pudo reemplazar los archivos en uso' }
            else                             { 'el instalador termino bien pero la version instalada no cambio (sigue en la ' + $Instalada + ')' }
        )
    }
    # El instalador que hay en la PC puede ser mas nuevo que el instalado y aun asi quedar por
    # debajo de la firmada: ahi el update funciona y el antivirus sigue siendo un tema.
    $quedaSinFirmar = $false
    try { $quedaSinFirmar = ([bool]$verInst -and ([version]$verInst -lt [version]$script:NativaVersionFirmada)) } catch {}
    return @{ aplicado = [bool]$rem.applied; subio = [bool]$subio; intento = [bool]$rem.applied; nota = [string]$rem.note
              instalador = $inst; versionInstalador = $verInst; versionDespues = $verDespues
              exitCode = $salida.code; porQueNo = $porQueNo; quedaSinFirmar = [bool]$quedaSinFirmar
              nativaCorriendo = [bool]$Corriendo
              motivo = [string]$dec.motivo }
}
function Select-LocalNativeInstaller {
    <#
      Que instalador de la Nativa usar. Hasta la 3.19 el motor elegia solo -el de version mas
      alta- y no habia forma de pedirle otro.
      Hace falta porque la firma de Microsoft no le dice nada a un antivirus de TERCEROS: un
      asesor viene reportando que con la 0.0.37 el AV del cliente la bloquea siempre y termina
      instalando a mano una version anterior que ese cliente si aguanta. Eso hoy es trabajo
      manual en medio de una llamada.
      Orden de decision:
        -NativeInstallerPath  -> ese, y cuenta como eleccion explicita de una persona
        ninguno disponible    -> no se inventa nada: se pide el .msi
        uno solo              -> ese
        varios + consola      -> se listan con su version y elige el asesor (Enter = recomendada)
        varios sin consola    -> la recomendada, igual que hasta ahora
      La recomendada es la version mas alta que ademas este firmada; si ninguna llega a la
      firmada, la mas alta.
      Bajar de version NUNCA pasa solo: solo si una persona lo elige y lo confirma en pantalla.
      Devuelve @{ ruta; version; elegidoPorPersona; motivo; candidatos }
    #>
    param([string]$Instalada = '')
    $cands = @(Get-LocalNativeInstallers)
    if ($NativeInstallerPath) {
        $p = ''
        try { if (Test-Path $NativeInstallerPath) { $p = [string](Resolve-Path $NativeInstallerPath).Path } } catch {}
        if (-not $p) {
            return @{ ruta = ''; version = ''; elegidoPorPersona = $false; candidatos = @($cands)
                      motivo = ('la ruta indicada en -NativeInstallerPath no existe: ' + [string]$NativeInstallerPath) }
        }
        $vp = ''
        try { $vp = [string](Get-MsiProductVersion -Path $p) } catch {}
        return @{ ruta = $p; version = $vp; elegidoPorPersona = $true; candidatos = @($cands)
                  motivo = 'instalador indicado con -NativeInstallerPath' }
    }
    if (@($cands).Count -eq 0) {
        return @{ ruta = ''; version = ''; elegidoPorPersona = $false; candidatos = @()
                  motivo = 'no hay ningun instalador de la App Nativa en esta PC' }
    }
    $reco = @($cands | Where-Object {
        $v = $null
        try { $v = [version]$_.version } catch { $v = $null }
        ($null -ne $v) -and ($v -ge [version]$script:NativaVersionFirmada)
    }) | Select-Object -First 1
    if (-not $reco) { $reco = @($cands)[0] }

    if (@($cands).Count -eq 1) {
        return @{ ruta = [string]@($cands)[0].ruta; version = [string]@($cands)[0].version
                  elegidoPorPersona = $false; candidatos = @($cands)
                  motivo = 'es el unico instalador que hay en la PC' }
    }
    if (-not (Test-IsInteractiveConsole)) {
        return @{ ruta = [string]$reco.ruta; version = [string]$reco.version
                  elegidoPorPersona = $false; candidatos = @($cands)
                  motivo = 'sin consola: se uso la version recomendada' }
    }

    Suspend-LiveStatus
    Write-Host ''
    Write-Host '  Hay mas de un instalador de la App Nativa en esta PC:' -ForegroundColor Cyan
    $i = 0
    foreach ($c in @($cands)) {
        $i++
        $etiquetas = @()
        if ([string]$c.ruta -eq [string]$reco.ruta) { $etiquetas += 'recomendada' }
        $vc = $null
        try { $vc = [version]$c.version } catch {}
        if ($null -ne $vc) {
            try { if ($vc -lt [version]$script:NativaVersionFirmada) { $etiquetas += 'SIN firmar' } else { $etiquetas += 'firmada' } } catch {}
        }
        if ($Instalada -and $c.version) {
            try { if ([version]$c.version -lt [version]$Instalada) { $etiquetas += ('mas vieja que la instalada v' + $Instalada) } } catch {}
        }
        Write-Host ("    $i) " + $(if ($c.version) { 'v' + [string]$c.version } else { '(no declara version)' }) +
                    $(if (@($etiquetas).Count -gt 0) { '  [' + (@($etiquetas) -join ' / ') + ']' } else { '' }))
        Write-Host ("       " + [string]$c.ruta) -ForegroundColor DarkGray
    }
    Write-Host ''
    $ans = Read-DoctorLine -Prompt ('  Cual instalar? (numero, o Enter para la recomendada' + $(if ($reco.version) { ' v' + [string]$reco.version } else { '' }) + ')')
    $elegido = $reco
    $porPersona = $false
    if ($null -ne $ans) {
        $t = ([string]$ans).Trim()
        if ($t) {
            $n = 0
            if ([int]::TryParse($t, [ref]$n) -and $n -ge 1 -and $n -le @($cands).Count) {
                $elegido = @($cands)[$n - 1]
                $porPersona = $true
            } else {
                Write-Host '  No entendi la respuesta: se usa la recomendada.' -ForegroundColor Yellow
            }
        }
    }
    # Bajar de version es una decision, no un accidente: se confirma aparte y se dice que implica.
    if ($porPersona -and $Instalada -and $elegido.version) {
        $baja = $false
        try { $baja = ([version]$elegido.version -lt [version]$Instalada) } catch {}
        if ($baja) {
            Write-Host ''
            Write-Host ("  OJO: vas a instalar la v" + [string]$elegido.version + " sobre la v" + [string]$Instalada + ', o sea BAJAR de version.') -ForegroundColor Yellow
            $sinFirmar = $false
            try { $sinFirmar = ([version]$elegido.version -lt [version]$script:NativaVersionFirmada) } catch {}
            if ($sinFirmar) {
                Write-Host ("  Esa version es anterior a la v" + [string]$script:NativaVersionFirmada + ', que es la primera firmada: Windows Defender puede volver a ponerla en cuarentena.') -ForegroundColor Yellow
                Write-Host '  Tiene sentido si el antivirus de este cliente bloquea la firmada; si no, no.' -ForegroundColor Yellow
            }
            $ok = Read-DoctorLine -Prompt '  Seguro? (s = si / cualquier otra tecla = no)'
            if (([string]$ok).Trim().ToLower() -ne 's') {
                Write-Host '  No se instalo nada.' -ForegroundColor Yellow
                return @{ ruta = ''; version = ''; elegidoPorPersona = $false; candidatos = @($cands)
                          motivo = 'el asesor no confirmo bajar de version' }
            }
        }
    }
    return @{ ruta = [string]$elegido.ruta; version = [string]$elegido.version
              elegidoPorPersona = [bool]$porPersona; candidatos = @($cands)
              motivo = $(if ($porPersona) { 'lo eligio el asesor en pantalla' } else { 'se uso la version recomendada' }) }
}

function Install-FudoNative {
    <#
      Instala la App Nativa de Fudo. Antes agrega las exclusiones de antivirus, porque el bloqueo
      del AV es la causa mas frecuente de que la Nativa no quede funcionando.
      Sin URL de instalador configurada, guia los pasos manuales.
    #>
    $url = $NativeInstallerUrl
    if (-not $url) { $url = $script:NativeInstallerUrl }

    # Preferimos un instalador que ya este en la PC: evita que el cliente tenga que descargar
    # (y que el antivirus borre la descarga a mitad de camino).
    # v3.20: cual instalar lo decide Select-LocalNativeInstaller, que le da la opcion al asesor
    # cuando hay mas de uno. Se lee primero lo que hay instalado, porque hace falta para poder
    # avisarle si lo que eligio baja de version.
    $instAntes = Find-FudoNativeInstall
    $verAntes = ''
    $verAntesConfiable = $false
    try {
        $vsAntes = Get-NativaVersionState -Install $instAntes
        $verAntes = [string]$vsAntes.version
        $verAntesConfiable = [bool]$vsAntes.confiable
    } catch {}
    $eleccion = Select-LocalNativeInstaller -Instalada $(if ($verAntesConfiable) { $verAntes } else { '' })
    $local = [string]$eleccion.ruta
    if ($local) {
        # v3.18: tres cosas estaban mal en este camino, y las tres las describio un asesor
        # ("el motor dice que instala la nativa, pero al corroborar en la version web sigue sin
        # detectarla... siento que no instala la nativa correcta").
        #  1. Se instalaba el instalador que apareciera primero por FECHA. Si el cliente tenia
        #     uno viejo en Descargas, el motor instalaba ESE: una version sin firmar que el
        #     antivirus vuelve a comerse. Ahora se elige por version (Find-LocalNativeInstaller)
        #     y no se degrada lo que ya esta instalado.
        #  2. Un .msi se lanzaba con Start-Process directo, o sea abriendo el ASISTENTE grafico
        #     en la pantalla del cliente y esperando a que alguien lo complete. Desde la 3.14 la
        #     Nativa se distribuye como .msi, asi que era el caso normal. Va por msiexec /qn,
        #     que es lo que el camino de actualizacion ya hacia bien desde la 3.14.
        #  3. No se verificaba nada: solo el codigo de salida y si el proceso estaba corriendo.
        #     La reparacion se reportaba aplicada con la Nativa sin instalar. Ahora se relee.
        $verNueva = [string]$eleccion.version
        if (-not $verNueva) { try { $verNueva = [string](Get-MsiProductVersion -Path $local) } catch {} }
        # v3.19: "ya estaba instalada" pasa a ser "el ejecutable esta en disco", y el guardarrail
        # anti-degradacion solo corre contra una version que salio de un archivo. Antes bastaba
        # una entrada de registro: con la pagina web agregada como aplicacion (DisplayVersion 1.0)
        # el motor comparaba 0.0.37 contra 1.0, decidia que iba a degradar, y no instalaba la
        # Nativa NUNCA en esa PC. El guardarrail estaba bien; el dato con el que decidia, no.
        # v3.20: el guardarrail deja de aplicarse cuando la version la eligio una PERSONA viendo
        # las que hay y confirmando que baja. El guardarrail existe para que el motor no degrade
        # solo, no para impedirle al asesor resolver el caso del antivirus de terceros.
        $yaEstaba = [bool]$instAntes.enDisco
        if ($yaEstaba -and $verAntesConfiable -and $verNueva -and $verAntes -and -not [bool]$eleccion.elegidoPorPersona) {
            $degradaria = $false
            try { $degradaria = ([version]$verNueva -lt [version]$verAntes) } catch { $degradaria = $false }
            if ($degradaria) {
                Write-Host ''
                Write-Host ("  NO se instalo nada: el instalador que hay en la PC es la v$verNueva y la instalada es la v$verAntes.") -ForegroundColor Yellow
                Write-Host '  Instalarlo la degradaria (ya paso en este proyecto: 0.0.36 -> 0.0.18).' -ForegroundColor Yellow
                Write-Host ("  Conseguir el .msi de la v$($script:NativaVersionFirmada) y copiarlo al lado de este script.") -ForegroundColor Yellow
                Write-Host ''
                $script:Diagnostics['nativaInstall'] = [ordered]@{
                    intento = $false; instalador = $local; versionInstalador = $verNueva
                    quedoInstalada = $true; versionDespues = $verAntes; exitCode = $null; corriendo = $null
                    motivo = 'no se instalo: el instalador local es mas viejo que la Nativa que ya esta en disco'
                }
                return @{ applied = $false; note = ("no se instalo: el instalador local (v$verNueva) es mas viejo que la instalada (v$verAntes)") }
            }
        }
        Write-Host ''
        Write-Host ("  Instalador encontrado en la PC: " + $local + $(if ($verNueva) { " (v$verNueva)" } else { ' (no declara version)' })) -ForegroundColor Cyan
        if ($verNueva) {
            $bajoFirmada = $false
            try { $bajoFirmada = ([version]$verNueva -lt [version]$script:NativaVersionFirmada) } catch {}
            if ($bajoFirmada) {
                Write-Host ("  OJO: es anterior a la v$($script:NativaVersionFirmada), que es la primera firmada. El antivirus puede volver a bloquearla.") -ForegroundColor Yellow
            }
        }
        $salida = @{ code = $null }
        $rem = Invoke-Remediation -Description ('Instalar la App Nativa desde ' + $local) -Type 'nativa.install_local' -Target 'FudoNativa' `
            -Before 'no instalada' -After 'instalada' -Reversible $true -Fix {
                $notas = @()
                if ($UseDefenderExclusions) {
                    $rutasExcl = @((Split-Path -Parent $local))
                    if ($env:LOCALAPPDATA) { $rutasExcl += @((Join-Path $env:LOCALAPPDATA 'Fudo'), (Join-Path $env:LOCALAPPDATA 'Programs')) }
                    foreach ($ruta in @($rutasExcl | Where-Object { $_ })) {
                        try { Add-MpPreference -ExclusionPath $ruta -ErrorAction SilentlyContinue; $notas += "excl $ruta" } catch {}
                    }
                    try { Add-MpPreference -ExclusionProcess "$FudoAppProcess*.exe" -ErrorAction SilentlyContinue } catch {}
                    try { Add-MpPreference -ExclusionPath $local -ErrorAction SilentlyContinue } catch {}
                }
                Write-StepDetail 'ejecutando el instalador local'
                $code = Invoke-NativeInstallerFile -Path $local -ExtraArgs $NativeInstallerArgs
                $salida.code = $code
                $notas += $(if ($null -eq $code) { 'no se pudo lanzar el instalador' } else { "el instalador termino con codigo $code" })
                Start-Sleep -Seconds 3
                ($notas -join ' | ')
            }
        # Verificar el EFECTO, no el codigo de retorno: es la regla del proyecto y este camino
        # no la cumplia.
        $instDespues = Find-FudoNativeInstall
        # Quedo instalada = el ejecutable esta en disco. Mirar el registro aca era justamente lo
        # que dejaba pasar "instalador OK, Nativa ausente" cuando quedaba una entrada huerfana.
        $quedo = [bool]$instDespues.enDisco
        $verDespues = ''
        try { $verDespues = [string](Get-NativaVersionState -Install $instDespues).version } catch {}
        $corriendo = $false
        try { $corriendo = (@(Get-Process -ErrorAction SilentlyContinue | Where-Object { $_.Name -like "*$FudoAppProcess*" }).Count -gt 0) } catch {}
        $script:Diagnostics['nativaInstall'] = [ordered]@{
            intento = $true
            instalador = $local; versionInstalador = $verNueva; quedoInstalada = [bool]$quedo
            versionDespues = $verDespues; exitCode = $salida.code; corriendo = [bool]$corriendo
            motivo = $(if ($quedo) { 'la Nativa quedo en disco' }
                       elseif ($null -eq $salida.code) { 'no se pudo lanzar el instalador' }
                       elseif ([int]$salida.code -ne 0) { 'el instalador termino con codigo ' + [string]$salida.code }
                       else { 'el instalador termino bien y la Nativa no quedo en disco' })
        }
        if ($quedo) {
            Write-Host ("  App Nativa instalada" + $(if ($verDespues) { " (v$verDespues)" } else { '' }) + '.') -ForegroundColor Green
            if (-not $corriendo) {
                Write-Host '  Todavia no aparece corriendo, y es lo esperado: la levanta el navegador cuando abris Fudo.' -ForegroundColor DarkGray
            }
            [void](Update-CheckFinding -Id 'nativa.installed' -Status 'fixed' -RootCauseCandidate $false `
                -Name ('App Nativa de Fudo instalada por el motor' + $(if ($verDespues) { " (v$verDespues)" } else { '' })) `
                -ActionTaken ([string]$rem.note) `
                -Recommendation 'Se instalo la App Nativa en esta corrida. Abrir Fudo en el navegador y mandar una comanda de prueba.' `
                -EvidenceExtra @{ instaladaEnEstaCorrida = $true; versionDespues = [string]$verDespues })
            return @{ applied = $true; note = ([string]$rem.note + ' | quedo instalada' + $(if ($verDespues) { " (v$verDespues)" } else { '' })) }
        }
        Write-Host ''
        Write-Host '  NO quedo instalada.' -ForegroundColor Red
        Write-Host ("  " + $(if ($null -eq $salida.code) { 'no se pudo lanzar el instalador.' }
                             elseif ([int]$salida.code -ne 0) { "el instalador termino con codigo $($salida.code)." }
                             else { 'el instalador dijo que termino bien, pero la Nativa no aparece en la PC: revisar si el antivirus la borro.' })) -ForegroundColor Red
        Write-Host '  Instalarla a mano desde la web app de Fudo y verificar que el antivirus no la toque.' -ForegroundColor Yellow
        Write-Host ''
        return @{ applied = $false; note = ([string]$rem.note + ' | NO quedo instalada') }
    }

    if (-not $url) {
        Write-Host ''
        Write-Host ('  No hay con que instalar la App Nativa: ' + [string]$eleccion.motivo + '.') -ForegroundColor Yellow
        Write-Host '  Lo mas rapido: copiar el .msi de la App Nativa al lado de FudoPrintDoctor.cmd' -ForegroundColor Yellow
        Write-Host '  (tambien lo busca en Descargas y en el Escritorio) y volver a correr el diagnostico.' -ForegroundColor Yellow
        Write-Host '  Si este cliente necesita una version distinta a la vigente -por ejemplo porque su' -ForegroundColor DarkGray
        Write-Host '  antivirus bloquea la firmada-, dejar los dos .msi: el motor te deja elegir cual.' -ForegroundColor DarkGray
        Write-Host ''
        Write-Host '  Si no lo tenes a mano, se instala desde la web app:' -ForegroundColor Yellow
        Write-Host '    1. Entrar a la web app de Fudo desde esta PC.'
        Write-Host '    2. Descargar la App Nativa desde el asistente de instalacion de impresoras.'
        Write-Host '    3. Si el antivirus la bloquea o la manda a cuarentena, primero correr este'
        Write-Host '       script (agrega las exclusiones de Defender) y despues reinstalar.'
        Write-Host '    Guia: https://soporte.fu.do/es/articles/16419361'
        Write-Host ''
        Write-Host '  Si ya tenes el instalador, copialo al lado de este script (o pasar' -ForegroundColor DarkGray
        Write-Host '  -NativeInstallerPath <ruta>) y el motor lo ejecuta sin descargar nada.' -ForegroundColor DarkGray
        return @{ applied = $false; note = 'sin URL de instalador configurada' }
    }

    return (Invoke-Remediation -Description 'Descargar e instalar la App Nativa de Fudo' -Type 'nativa.install' -Target 'FudoNativa' `
        -Before 'no instalada' -After 'instalada' -Reversible $true -Fix {
            $notas = @()
            # 1) exclusiones ANTES de bajar el instalador: si no, el AV lo borra en la descarga
            if ($UseDefenderExclusions) {
                $rutasExcl = @($env:TEMP)
                if ($env:LOCALAPPDATA) { $rutasExcl += @((Join-Path $env:LOCALAPPDATA 'Fudo'), (Join-Path $env:LOCALAPPDATA 'Programs')) }
                foreach ($ruta in @($rutasExcl | Where-Object { $_ })) {
                    try { Add-MpPreference -ExclusionPath $ruta -ErrorAction SilentlyContinue; $notas += "excl $ruta" } catch {}
                }
                try { Add-MpPreference -ExclusionProcess "$FudoAppProcess*.exe" -ErrorAction SilentlyContinue } catch {}
            }
            # 2) descargar
            $destino = Join-Path $env:TEMP ('FudoNativa-' + (Get-Date).ToString('yyyyMMddHHmmss') + '.exe')
            Write-StepDetail 'descargando el instalador de la App Nativa'
            try { [Net.ServicePointManager]::SecurityProtocol = [Net.SecurityProtocolType]::Tls12 } catch {}
            Invoke-WebRequest -Uri $url -UseBasicParsing -TimeoutSec 180 -OutFile $destino -ErrorAction Stop
            $tam = 0
            try { $tam = [int]((Get-Item $destino).Length / 1024) } catch {}
            if ($tam -lt 100) { throw "el archivo descargado pesa ${tam}KB: no parece un instalador (revisar la URL)" }
            $notas += "instalador descargado (${tam}KB)"
            # 3) ejecutar
            Write-StepDetail 'ejecutando el instalador (puede pedir confirmacion en pantalla)'
            $pr = Start-Process -FilePath $destino -PassThru -Wait -ErrorAction Stop
            $notas += "instalador finalizo con codigo $($pr.ExitCode)"
            Start-Sleep -Seconds 3
            $corriendo = $false
            try { $corriendo = (@(Get-Process -ErrorAction SilentlyContinue | Where-Object { $_.Name -like "*$FudoAppProcess*" }).Count -gt 0) } catch {}
            $notas += $(if ($corriendo) { 'la Nativa esta corriendo' } else { 'la Nativa todavia no aparece corriendo: puede requerir iniciar sesion en la web app' })
            ($notas -join ' | ')
        })
}

function Get-TelemetryUrl {
    <# Resuelve la URL de telemetria sin necesidad de tenerla en el codigo. #>
    $script:TelemetryLookup = @()
    if ($TelemetryUrl) { $script:TelemetryLookup += 'parametro -TelemetryUrl'; return $TelemetryUrl }
    if ($env:FUDO_TELEMETRY_URL) { $script:TelemetryLookup += 'variable FUDO_TELEMETRY_URL (del proceso / launcher)'; return [string]$env:FUDO_TELEMETRY_URL }
    try {
        $guardada = [Environment]::GetEnvironmentVariable('FUDO_TELEMETRY_URL', 'User')
        if ($guardada -and ([string]$guardada -match '^https://')) {
            $script:TelemetryLookup += 'variable FUDO_TELEMETRY_URL (guardada en esta PC)'
            return [string]$guardada
        }
    } catch {}
    # OJO: en Windows la extension .url esta reservada para accesos directos de Internet,
    # asi que el archivo preferido es telemetria.txt (se acepta .url por compatibilidad).
    $nombres = @('telemetria.txt','telemetria.url','fudo-telemetria.txt')
    $carpetas = @()
    try { if ($PSCommandPath) { $carpetas += (Split-Path -Parent $PSCommandPath) } } catch {}
    try { $carpetas += (Get-Location).Path } catch {}
    try {
        if ($env:USERPROFILE) {
            $carpetas += @((Join-Path $env:USERPROFILE 'Downloads'), (Join-Path $env:USERPROFILE 'Desktop'))
            # OneDrive redirige Escritorio/Documentos: hay que mirar ahi tambien
            $carpetas += @((Join-Path $env:USERPROFILE 'OneDrive\Escritorio'), (Join-Path $env:USERPROFILE 'OneDrive\Desktop'),
                           (Join-Path $env:USERPROFILE 'Escritorio'))
        }
        if ($env:OneDrive) { $carpetas += @((Join-Path $env:OneDrive 'Escritorio'), (Join-Path $env:OneDrive 'Desktop')) }
    } catch {}
    $rutas = @()
    foreach ($c in @($carpetas | Where-Object { $_ })) {
        foreach ($n in $nombres) { $rutas += (Join-Path $c $n) }
    }
    foreach ($r in @($rutas | Where-Object { $_ })) {
        $existe = $false
        try { $existe = [bool](Test-Path $r) } catch {}
        if (-not $existe) { $script:TelemetryLookup += ("no existe: " + $r); continue }
        try {
            $u = ((Get-Content -Path $r -TotalCount 1 -ErrorAction Stop) | Out-String).Trim()
            if ($u -match '^https://') {
                $script:TelemetryLookup += ("leido de: " + $r)
                return $u
            }
            $script:TelemetryLookup += ("existe pero no tiene una URL https en la primera linea: " + $r)
        } catch {
            $script:TelemetryLookup += ("no se pudo leer: " + $r + ' -> ' + $_.Exception.Message)
        }
    }
    if ($script:TelemetryUrl) { return $script:TelemetryUrl }
    return ''
}

function Get-TelemetryHint {
    <# Traduce las fallas tipicas del endpoint a una instruccion concreta. #>
    param([int]$Codigo, [string]$Cuerpo)
    $esHtmlDeGoogle = ($Cuerpo -match '(?i)<!DOCTYPE html' -and $Cuerpo -match '(?i)google|accounts\.google|script\.google')
    if ($Codigo -in @(401, 403) -or $esHtmlDeGoogle) {
        return ('El Apps Script no esta publicado con acceso abierto: Google devolvio su pagina de login en lugar de ejecutarlo. ' +
                'En el editor de Apps Script: Implementar > Administrar implementaciones > editar (lapiz) > ' +
                '"Quien tiene acceso" = Cualquier persona (NO "Cualquier persona con una cuenta de Google"), ' +
                '"Ejecutar como" = Yo, y Implementar. Si la cuenta es de Workspace y la organizacion bloquea esa opcion, ' +
                'hay que usar otro receptor (por ejemplo un webhook de Slack) o una cuenta personal de Gmail.')
    }
    if ($Codigo -eq 404) { return 'La URL no existe o la implementacion fue borrada: volver a implementar y actualizar la URL en el launcher.' }
    if ($Codigo -ge 500) { return 'El endpoint devolvio un error del servidor: revisar el codigo del Apps Script (los errores de doPost quedan en Ejecuciones).' }
    return 'El endpoint no acepto el reporte.'
}

function Invoke-TelemetryPost {
    <#
      POST robusto para Apps Script. El detalle importante: /exec responde 302 hacia
      script.googleusercontent.com, y al seguir el redirect el POST se convierte en GET y se pierde
      el cuerpo. Por eso, si el primer intento no devuelve ok, se repite el POST contra el Location.
      Devuelve @{ ok = $bool; note = '...' }
    #>
    param([string]$Url, [string]$Body)

    try { [Net.ServicePointManager]::SecurityProtocol = [Net.SecurityProtocolType]::Tls12 } catch {}
    $bytes = [Text.Encoding]::UTF8.GetBytes($Body)

    # --- intento 1: el camino simple
    try {
        $r = Invoke-RestMethod -Uri $Url -Method Post -Body $Body -ContentType 'application/json; charset=utf-8' -TimeoutSec 20 -ErrorAction Stop
        if ($r -and ($r.ok -eq $true)) { return @{ ok = $true; note = 'enviado' } }
        $txt = ''
        try { $txt = ([string]($r | ConvertTo-Json -Compress -Depth 4)) } catch { $txt = [string]$r }
        if ($txt.Length -gt 200) { $txt = $txt.Substring(0, 200) }
        $primero = "respuesta inesperada: $txt"
    } catch {
        $primero = "fallo directo: $($_.Exception.Message)"
    }

    # --- intento 2: POST -> 302 -> POST al Location (sin auto-redirect)
    try {
        $req = [Net.HttpWebRequest]::Create($Url)
        $req.Method = 'POST'
        $req.ContentType = 'application/json; charset=utf-8'
        $req.AllowAutoRedirect = $false
        $req.Timeout = 20000
        $req.ContentLength = $bytes.Length
        $st = $req.GetRequestStream(); $st.Write($bytes, 0, $bytes.Length); $st.Close()

        $res = $null
        try { $res = $req.GetResponse() } catch [Net.WebException] { $res = $_.Exception.Response }
        if (-not $res) { return @{ ok = $false; note = $primero } }

        $codigo = [int]$res.StatusCode
        $destino = [string]$res.Headers['Location']
        $cuerpo = ''
        try { $cuerpo = (New-Object IO.StreamReader($res.GetResponseStream())).ReadToEnd() } catch {}
        try { $res.Close() } catch {}

        if ($codigo -ge 300 -and $codigo -lt 400 -and $destino) {
            $req2 = [Net.HttpWebRequest]::Create($destino)
            $req2.Method = 'POST'
            $req2.ContentType = 'application/json; charset=utf-8'
            $req2.AllowAutoRedirect = $true
            $req2.Timeout = 20000
            $req2.ContentLength = $bytes.Length
            $st2 = $req2.GetRequestStream(); $st2.Write($bytes, 0, $bytes.Length); $st2.Close()
            $res2 = $null
            try { $res2 = $req2.GetResponse() } catch [Net.WebException] { $res2 = $_.Exception.Response }
            if ($res2) {
                $cuerpo2 = ''
                try { $cuerpo2 = (New-Object IO.StreamReader($res2.GetResponseStream())).ReadToEnd() } catch {}
                try { $res2.Close() } catch {}
                if ($cuerpo2 -match '"ok"\s*:\s*true') { return @{ ok = $true; note = 'enviado (via redirect)' } }
                $c2 = $cuerpo2; if ($c2.Length -gt 200) { $c2 = $c2.Substring(0, 200) }
                return @{ ok = $false; note = "el endpoint respondio: $c2" }
            }
        }

        if ($cuerpo -match '"ok"\s*:\s*true') { return @{ ok = $true; note = 'enviado' } }
        $c1 = $cuerpo; if ($c1.Length -gt 200) { $c1 = $c1.Substring(0, 200) }
        return @{ ok = $false; note = ((Get-TelemetryHint -Codigo $codigo -Cuerpo $cuerpo) + " [HTTP $codigo. $primero. Cuerpo: $c1]") }
    } catch {
        $extra = ''
        if ($primero -match '40[13]') { $extra = ' ' + (Get-TelemetryHint -Codigo 403 -Cuerpo '') }
        return @{ ok = $false; note = "$primero | segundo intento: $($_.Exception.Message).$extra" }
    }
}

function Save-TelemetryUrl {
    <#
      Una vez que la URL se conocio (por el launcher o por parametro), la dejamos guardada en una
      variable de entorno de USUARIO de esa PC. Asi sobrevive a cualquier actualizacion de archivos:
      si mas adelante el launcher se reemplaza por uno sin URL, la telemetria sigue funcionando.
      Es un cambio chico y reversible: setx FUDO_TELEMETRY_URL "" lo borra.
    #>
    param([string]$Url)
    if (-not $Url) { return }
    try {
        $actual = [Environment]::GetEnvironmentVariable('FUDO_TELEMETRY_URL', 'User')
        if ([string]$actual -eq $Url) { return }
        [Environment]::SetEnvironmentVariable('FUDO_TELEMETRY_URL', $Url, 'User')
        Add-Action -Type 'telemetry.persist' -Target 'FUDO_TELEMETRY_URL (usuario)' -Before ([string]$actual) -After $Url -Reversible $true
        Write-DoctorLog -Level 'INFO' -Message 'URL de telemetria guardada en la variable de usuario FUDO_TELEMETRY_URL'
    } catch {
        Write-DoctorLog -Level 'WARN' -Message "No se pudo guardar la URL de telemetria: $($_.Exception.Message)"
    }
    # Segunda copia, al lado del motor: la variable de entorno es por usuario de Windows,
    # asi que si el .cmd se reemplaza por el publico (sin URL) y despues corre otro usuario,
    # se perderia. telemetria.txt viaja con la carpeta y esta en .gitignore, nunca se publica.
    try {
        $dir = ''
        if ($PSCommandPath) { $dir = Split-Path -Parent $PSCommandPath }
        if ($dir) {
            $archivo = Join-Path $dir 'telemetria.txt'
            if (-not (Test-Path $archivo)) {
                Set-Content -Path $archivo -Value $Url -Encoding ASCII -ErrorAction Stop
                Add-Action -Type 'telemetry.persist_file' -Target $archivo -Before 'no existia' -After 'URL guardada' -Reversible $true
                Write-DoctorLog -Level 'INFO' -Message ('URL de telemetria respaldada en ' + $archivo)
            }
        }
    } catch {
        Write-DoctorLog -Level 'WARN' -Message "No se pudo respaldar la URL en telemetria.txt: $($_.Exception.Message)"
    }
}

function ConvertTo-TelemetryChecks {
    <#
      Version reducida de los checks para el payload de telemetria.
      v3.9: antes era solo {id, status, layer} y se perdia el skipReason que la 3.7 ya calculaba.
      En la planilla habia hw.testprint=skipped sin ningun motivo posible de auditar.
    #>
    param($Checks)
    # v3.11: sin el filtro, una corrida que abortaba mandaba checks: [{"id":"","status":"",
    # "layer":null}] -- @($null) es un array de un elemento nulo-. Ese ruido llegaba a la
    # planilla como si fuera un check real.
    return @(@($Checks) | Where-Object { $_ -and [string]$_.id } | ForEach-Object {
        $c = [ordered]@{ id = [string]$_.id; status = [string]$_.status; layer = $_.layer }
        $sr = ''
        try { if ($_.evidence) { $sr = [string]$_.evidence.skipReason } } catch {}
        if ($sr) { $c['skipReason'] = $sr }
        $c
    })
}

function Send-Telemetry {
    <#
      Manda el resultado a un endpoint para no depender de que el asesor guarde el JSON.
      Nunca corta el diagnostico: timeout corto y errores silenciados.
    #>
    param($Result)
    # v3.11: el self-test no puede escribir en la planilla. Si algo explotaba adentro de
    # -SelfTest, la excepcion salia al catch global y ese catch manda telemetria: entraba una
    # fila engine_error de una corrida que nunca toco una impresora, con el host de quien estaba
    # desarrollando. Ensucia el conteo y hace perder tiempo en la revision del dia siguiente.
    if ($SelfTest) {
        $script:TelemetryStatus = [ordered]@{
            enviada = $false; detalle = 'no se envia: corrida de self-test'; url = ''; dondeBusco = @()
        }
        return $false
    }
    $url = Get-TelemetryUrl
    if ($url) { Save-TelemetryUrl -Url $url }
    if (-not $url) {
        # Antes esto era un return silencioso y nadie se enteraba de que no estaba configurada.
        $script:TelemetryStatus = [ordered]@{
            enviada = $false
            detalle = 'no configurada: falta el archivo telemetria.txt junto al script (o -TelemetryUrl / FUDO_TELEMETRY_URL)'
            url = ''
            dondeBusco = @($script:TelemetryLookup)
        }
        Write-DoctorLog -Level 'WARN' -Message 'Telemetria no configurada: no se encontro telemetria.txt ni -TelemetryUrl'
        return $false
    }

    try {
        $payload = $Result
        if (-not $TelemetryFull) {
            $payload = [ordered]@{
                schemaVersion = [string]$Result.schemaVersion
                status        = [string]$Result.status
                caseId        = [string]$Result.caseId
                pcId          = [string]$Result.pcId
                corrida       = $Result.corrida
                llegada       = $Result.llegada
                nativaHuella  = $Result.nativaHuella
                clientId      = [string]$Result.clientId
                host          = [string]$Result.host
                timestamp     = [string]$Result.timestamp
                interface     = [string]$Result.interface
                modo          = [string]$Result.modo
                dryRun        = [bool]$Result.dryRun
                rootCause     = [string]$Result.diagnosis.rootCause
                rootCauseCheckId = [string]$Result.diagnosis.rootCauseCheckId
                resolved      = [bool]$Result.diagnosis.resolved
                confidence    = [string]$Result.diagnosis.confidence
                needsEscalation = [bool]$Result.diagnosis.needsEscalation
                # Salio el papel de la prueba fisica, aunque el caso no cierre. Se calculaba
                # desde la 3.9 y no viajaba: en la planilla no habia forma de separar "no sale
                # nada" de "sale papel pero la comanda de Fudo todavia no".
                paperOk       = [bool]$Result.diagnosis.paperOk
                # v3.12: fudoSinUso se calculaba desde la 3.11 y no viajaba en ningun payload,
                # asi que no se podia separar el cierre completo del cierre a medio camino
                # (imprime, pero todavia no salio ninguna comanda de Fudo). Ese cruce es la
                # unica forma de saber si el criterio de cierre nuevo esta midiendo bien.
                fudoSinUso    = [bool]$Result.diagnosis.fudoSinUso
                fudoUsoEstado = [string]$Result.diagnosis.fudoUsoEstado
                cierreSinVerificarFudo = [bool]$Result.diagnosis.cierreSinVerificarFudo
                # Un engine_error sin esto era irrastreable: se vio una fila con status
                # engine_error y ni el mensaje, ni la linea, ni el ultimo paso que corrio.
                errorMotor    = $(
                    if ($Result.error) {
                        [ordered]@{
                            mensaje     = [string]$Result.error.message
                            tipo        = [string]$Result.error.type
                            linea       = $Result.error.scriptLine
                            comando     = [string]$Result.error.command
                            stack       = [string]$Result.error.stack
                            ultimoCheck = [string]$Result.telemetry.ultimoCheck
                            ultimoPaso  = [string]$Result.telemetry.ultimoPaso
                        }
                    } else { $null }
                )
                autoFixesApplied = @(@($Result.diagnosis.autoFixesApplied) | Where-Object { $_ })
                telemetry     = $(
                    $t = [ordered]@{}
                    try { foreach ($k in @($Result.telemetry.Keys)) { $t[$k] = $Result.telemetry[$k] } } catch {}
                    $colasCliente = @($(if ($script:Diagnostics.Contains('colas')) { $script:Diagnostics['colas'] | Where-Object { -not $_.esDePrueba } } else { @() }))
                    $t['impresoras'] = @($colasCliente | ForEach-Object { [ordered]@{ nombre = $_.nombre; puerto = $_.puerto; estado = $_.estado; trabajos = $_.trabajos } })
                    $t['cantidadColas'] = @($colasCliente).Count
                    $t['cantidadHardware'] = @($(if ($script:Diagnostics.Contains('printersConnected')) { $script:Diagnostics['printersConnected'] } else { @() })).Count
                    # Colas que estaban rotas al empezar y quedaron sanas al terminar. Es la
                    # medida directa de si las reparaciones sirvieron, por cola y no por corrida.
                    $t['colasQueMejoraron'] = @($(if ($script:Diagnostics.Contains('colasQueMejoraron')) { $script:Diagnostics['colasQueMejoraron'] } else { @() }))
                    # Los mismos dos datos dentro de telemetry, que es de donde salen las
                    # columnas del receptor cuando se agreguen.
                    $t['paperOk'] = [bool]$Result.diagnosis.paperOk
                    $t['fudoSinUso'] = [bool]$Result.diagnosis.fudoSinUso
                    $t['fudoUsoEstado'] = [string]$Result.diagnosis.fudoUsoEstado
                    $t['cierreSinVerificarFudo'] = [bool]$Result.diagnosis.cierreSinVerificarFudo
                    $t['versionCheck'] = [ordered]@{
                        publicada = [string]$script:VersionPublicada
                        omitido   = [bool]$script:VersionCheckOmitido
                        fallo     = [bool]$script:VersionCheckFallo
                    }
                    $t['cobertura'] = $(if ($script:Diagnostics.Contains('cobertura')) { $script:Diagnostics['cobertura'] } else { $null })
                    # v3.18: por que purgar no alcanza. Sin estos numeros no se puede distinguir
                    # "purgar no borra" de "borra y se vuelve a llenar", que son dos problemas
                    # con arreglos opuestos.
                    $t['purgaMedicion'] = $(if ($script:Diagnostics.Contains('purgaMedicion')) { $script:Diagnostics['purgaMedicion'] } else { $null })
                    # Si el asesor trajo el .msi de la Nativa firmada, y el resultado de la
                    # instalacion cuando el motor la instalo.
                    $t['nativaKit'] = $(
                        if ($script:NativaKit) {
                            [ordered]@{ listo = [bool]$script:NativaKit.listo; version = [string]$script:NativaKit.version
                                        motivo = [string]$script:NativaKit.motivo
                                        candidatos = @(@($script:NativaKit.candidatos) | ForEach-Object { [string]$_.version })
                                        omitido = [bool]$script:NativaKitOmitido }
                        } else { $null }
                    )
                    $t['nativaInstall'] = $(if ($script:Diagnostics.Contains('nativaInstall')) { $script:Diagnostics['nativaInstall'] } else { $null })
                    # v3.16: impresoras vistas en una subred distinta a la del PC, con su MAC.
                    # La MAC es lo que permite armar la tabla de OUIs por fabricante con datos
                    # reales en vez de adivinarla, y el plan dice si el motor pudo resolver la
                    # instruccion completa o le falto algo.
                    $t['otraSubred'] = [ordered]@{
                        candidatas = @($(if ($script:Diagnostics.Contains('subredesCandidatas')) { $script:Diagnostics['subredesCandidatas'] } else { @() }))
                        revisadas  = @($(if ($script:Diagnostics.Contains('subredesRevisadas')) { $script:Diagnostics['subredesRevisadas'] } else { @() }))
                        encontradas = @($(if ($script:Diagnostics.Contains('impresorasOtraSubred')) { $script:Diagnostics['impresorasOtraSubred'] } else { @() }))
                        plan = $(if ($script:Diagnostics.Contains('planRedImpresora')) { $script:Diagnostics['planRedImpresora'] } else { $null })
                    }
                    $t['historialFudo'] = @($(if ($script:Diagnostics.Contains('historialImpresion')) { $script:Diagnostics['historialImpresion'].porImpresora } else { @() }))
                    # v3.15: la columna existia en el receptor y el motor NUNCA la mando (vacia
                    # en 229 de 229 filas), asi que no habia forma de saber a que cola le manda
                    # Fudo en las PCs donde el historial si dice algo. Cuando no se puede
                    # atribuir se manda 'no_atribuible', que es un dato distinto de vacio.
                    $t['colaQueUsaFudo'] = $(
                        $hf = $(if ($script:Diagnostics.Contains('historialImpresion')) { $script:Diagnostics['historialImpresion'] } else { $null })
                        $topFudo = @($(if ($hf) { @($hf.porImpresora | Where-Object { [int]$_.deFudo -gt 0 } | Sort-Object -Property @{ Expression = { [int]$_.deFudo }; Descending = $true }) } else { @() }))
                        if (@($topFudo).Count -gt 0) { [string]@($topFudo)[0].impresora }
                        elseif ([string]$Result.diagnosis.fudoUsoEstado -eq 'no_atribuible') { 'no_atribuible' }
                        else { '' }
                    )
                    # Resultado del intento de actualizar la Nativa. Sin esto, un update que no
                    # toma es indistinguible de uno que no se intento.
                    $t['nativaUpdate'] = $(
                        $nu = $(if ($script:Diagnostics.Contains('nativaUpdate')) { $script:Diagnostics['nativaUpdate'] } else { $null })
                        if ($nu) {
                            [ordered]@{ intento = [bool]$nu.intento; subio = [bool]$nu.subio
                                        versionInstalador = [string]$nu.versionInstalador
                                        versionDespues = [string]$nu.versionDespues
                                        exitCode = $nu.exitCode; porQueNo = [string]$nu.porQueNo
                                        quedaSinFirmar = [bool]$nu.quedaSinFirmar
                                        motivo = [string]$nu.motivo }
                        } else { $null }
                    )
                    # v3.9: los ids de accion (testprint.retarget, queue.rebind, ...) no viajaban:
                    # autoFixesApplied solo trae los textos humanos de las reparaciones. Sin esto
                    # no habia forma de auditar en la planilla si una ruta nueva se ejecuto.
                    $t['acciones'] = @($script:Actions | ForEach-Object { [string]$_.type } | Where-Object { $_ })
                    $t['entorno'] = $Result.entorno
                    $t
                )
                entorno       = $Result.entorno
                # Si el motor aborto, $Result.checks puede no existir: $script:Checks igual
                # tiene todo lo que se alcanzo a diagnosticar antes del crash.
                checks        = @(ConvertTo-TelemetryChecks -Checks $(if ($Result.checks) { $Result.checks } else { @($script:Checks) }))
            }
        }
        $body = $payload | ConvertTo-Json -Depth 8 -Compress
        $r = Invoke-TelemetryPost -Url $url -Body $body
        $script:TelemetryStatus = [ordered]@{ enviada = [bool]$r.ok; detalle = [string]$r.note; url = $url; dondeBusco = @($script:TelemetryLookup) }
        if ($r.ok) {
            Write-DoctorLog -Level 'INFO' -Message "Telemetria enviada ($($r.note))"
        } else {
            Write-DoctorLog -Level 'WARN' -Message "No se pudo enviar la telemetria: $($r.note)"
        }
        return [bool]$r.ok
    } catch {
        $script:TelemetryStatus = [ordered]@{ enviada = $false; detalle = [string]$_.Exception.Message; url = $url; dondeBusco = @($script:TelemetryLookup) }
        Write-DoctorLog -Level 'WARN' -Message "No se pudo enviar la telemetria: $($_.Exception.Message)"
        return $false
    }
}

function Write-DoctorResult {
    param($Obj)
    $script:LastResult = $Obj

    # La telemetria se manda ANTES de serializar: si no, el JSON se guardaba con
    # telemetria=null y sin las lineas de log del envio, y no habia forma de depurarlo.
    $null = Send-Telemetry -Result $Obj
    try {
        if ($Obj -is [System.Collections.IDictionary]) {
            $Obj['telemetria'] = $script:TelemetryStatus
            $Obj['log'] = @($script:Log)
        }
    } catch {}

    $json = $null
    try {
        $json = $Obj | ConvertTo-Json -Depth 12
    } catch {
        $json = '{"schemaVersion":"' + $script:SchemaVersion + '","status":"engine_error","error":{"message":"No se pudo serializar el resultado a JSON: ' + (([string]$_.Exception.Message) -replace '"','\"') + '"}}'
    }
    if ($JsonOut) {
        try {
            $json | Out-File -FilePath $JsonOut -Encoding UTF8
            [Console]::Error.WriteLine("Resultado JSON escrito en: $JsonOut")
        } catch {
            [Console]::Error.WriteLine("No se pudo escribir '$JsonOut': $($_.Exception.Message)")
        }
    }
    # El JSON va a pantalla SOLO si se pide con -Json. Nunca por deteccion automatica:
    # en Windows PowerShell dentro de un .cmd la deteccion de redireccion no es confiable,
    # y el asesor terminaba viendo el JSON entero arriba del resumen.
    $emitJson = [bool]$Json

    if (-not $emitJson -and -not $JsonOut) {
        try {
            $auto = Join-Path $env:TEMP ("FudoPrintDoctor-" + (Get-Date).ToString('yyyyMMdd-HHmmss') + ".json")
            $json | Out-File -FilePath $auto -Encoding UTF8
            $script:AutoJsonPath = $auto
        } catch {}
    }

    if ($emitJson) {
        Write-Output $script:JsonBegin
        Write-Output $json
        Write-Output $script:JsonEnd
    }

    if ($script:TelemetryStatus -and -not $Quiet) {
        if ($script:TelemetryStatus.enviada) {
            Write-HumanReport -Text ("  Reporte enviado al panel de telemetria.`r`n")
        } elseif ([string]$script:TelemetryStatus.detalle -match '^no configurada') {
            Write-HumanReport -Text ("  Telemetria no configurada (falta telemetria.txt junto al script).`r`n")
        } else {
            Write-HumanReport -Text ("  ATENCION: no se pudo enviar el reporte de telemetria.`r`n  " + [string]$script:TelemetryStatus.detalle + "`r`n")
        }
    }

    # El resumen humano va al final: es lo ultimo que queda en pantalla.
    if (-not $Quiet) {
        $hs = $null
        try { $hs = [string]$Obj.humanSummary } catch {}
        if ($hs) { Write-HumanReport -Text $hs }
        $where = $(if ($JsonOut) { $JsonOut } elseif ($script:AutoJsonPath) { $script:AutoJsonPath } else { '' })
        if ($where) { Write-HumanReport -Text ("  Detalle completo (JSON): $where`r`n") }
    }
}

try {
    if ($SelfTest) { Invoke-SelfTest; return }

    if ($TestTelemetry) {
        $u = Get-TelemetryUrl
        if (-not $u) {
            [Console]::Error.WriteLine('  No hay URL de telemetria configurada.')
            [Console]::Error.WriteLine('  Opciones: -TelemetryUrl <url>, la variable FUDO_TELEMETRY_URL (la setea el .cmd interno),')
            [Console]::Error.WriteLine('  o un archivo telemetria.txt junto al script. Se busco en:')
            foreach ($d in @($script:TelemetryLookup)) { [Console]::Error.WriteLine('    - ' + $d) }
            exit 3
        }
        [Console]::Error.WriteLine("  Probando el endpoint: $u")
        $prueba = [ordered]@{
            schemaVersion = $script:SchemaVersion; status = 'resolved'
            caseId = 'PRUEBA-TELEMETRIA'; clientId = ''; host = $env:COMPUTERNAME
            timestamp = (Get-Date).ToString('o'); interface = 'USB'; dryRun = $true
            rootCause = 'Prueba de conectividad de telemetria'; resolved = $true; confidence = 'high'
            telemetry = [ordered]@{ category = 'test'; durationMs = 0; entorno = (Get-EnvironmentInfo) }
            checks = @()
        }
        $r = Invoke-TelemetryPost -Url $u -Body ($prueba | ConvertTo-Json -Depth 8 -Compress)
        if ($r.ok) { [Console]::Error.WriteLine("  OK: el endpoint recibio la prueba ($($r.note)). Deberia aparecer una fila con caseId PRUEBA-TELEMETRIA."); exit 0 }
        [Console]::Error.WriteLine("  FALLO: $($r.note)")
        [Console]::Error.WriteLine('  Revisar en Apps Script: Implementar > Administrar implementaciones > "Quien tiene acceso" = Cualquier persona.')
        exit 3
    }

    if ($CheckUpdate) {
        $pub = Get-PublishedVersion -TimeoutSec 8
        if (-not $pub) {
            [Console]::Error.WriteLine("  No se pudo consultar la version publicada (sin internet o el repo no responde).")
            [Console]::Error.WriteLine("  Version local: $($script:SchemaVersion)")
            exit 3
        }
        $nueva = $false
        try { $nueva = ([version]$pub -gt [version]$script:SchemaVersion) } catch {}
        if ($nueva) {
            [Console]::Error.WriteLine("  Version local: $($script:SchemaVersion)  |  publicada: $pub  ->  HAY ACTUALIZACION")
            exit 2
        }
        [Console]::Error.WriteLine("  Version local: $($script:SchemaVersion)  |  publicada: $pub  ->  al dia")
        exit 0
    }

    # v3.14: dos requisitos previos. Ninguno diagnostica nada: si no se cumplen, no se corre.
    # v3.18: tres. El tercero es el .msi de la App Nativa firmada, que es parte del kit del
    # asesor y no algo para descubrir cliente por cliente: sin el, una PC con la Nativa vieja se
    # queda con la vieja y el antivirus se la vuelve a comer. Se chequea SIN mirar lo que tiene
    # el cliente -lo que importa es si el asesor puede resolverlo cuando aparezca- y se pregunta
    # antes que el ID del caso, para no hacerle pegar la conversacion de Intercom y recien
    # despues mandarlo a buscar un archivo.
    if (Test-VersionBloqueada) { exit 5 }
    $script:NativaKit = Test-NativaKitReady
    if (-not (Confirm-NativaKit -Kit $script:NativaKit)) {
        [Console]::Error.WriteLine('')
        [Console]::Error.WriteLine(('  Cortado. Copia el .msi de la App Nativa v' + $script:NativaVersionFirmada + ' al lado de este script y volve a correrlo.'))
        [Console]::Error.WriteLine('')
        exit 7
    }
    $CaseId = Resolve-CaseIdObligatorio -Actual $CaseId

    $final = Invoke-FudoPrintDoctor
    Write-DoctorResult -Obj $final

    # Menu de acciones: permite volver a revisar o corregir sin cerrar y reabrir la app.
    if (-not $NoMenu -and (Test-IsInteractiveConsole)) {
        while ($true) {
            $op = Show-DoctorMenu
            if ($op -eq 'S') { break }
            if ($op -eq '?') {
                # Freno: si nunca llega una opcion valida es que la ventana no tiene
                # teclado usable. Sin esto el menu podria repetirse para siempre.
                $script:MenuVacios = [int]$script:MenuVacios + 1
                if ($script:MenuVacios -ge 5) {
                    Write-Host ''
                    Write-Host '  No estoy recibiendo ninguna tecla. Cerra esta ventana y abri' -ForegroundColor Red
                    Write-Host '  FudoPrintDoctor.cmd con doble clic desde la carpeta.' -ForegroundColor Yellow
                    break
                }
                continue
            }
            $script:MenuVacios = 0
            $volverACorrer = Invoke-MenuAction -Op $op
            if ($volverACorrer) {
                Reset-RunState
                $final = Invoke-FudoPrintDoctor
                Write-DoctorResult -Obj $final
            }
        }
    }

    if (@($script:Errors).Count -gt 0)                                   { exit 3 }
    elseif ([string]$final.status -eq 'resolved')                        { exit 0 }
    else                                                                 { exit 2 }

} catch {
    # Red de seguridad: cualquier explosion no prevista sale igual como JSON accionable.
    $hint = ''
    try { $hint = Get-ErrorHint -ErrorRecord $_ } catch {}
    $msg = ''; $type = ''; $line = 0; $cmd = ''; $stack = ''
    try { $msg   = [string]$_.Exception.Message } catch {}
    try { $type  = $_.Exception.GetType().FullName } catch {}
    try { $line  = [int]$_.InvocationInfo.ScriptLineNumber } catch {}
    try { $cmd   = ([string]$_.InvocationInfo.Line).Trim() } catch {}
    try { $stack = [string]$_.ScriptStackTrace } catch {}

    # v3.11: una corrida que explota tiene que quedar rastreable. Se vio una fila con
    # status=engine_error, pcId vacio, entorno null, corrida null, duracionMs 0,
    # checks [{"id":""}] y autoFixesApplied [null]: no habia forma de saber en que PC fue, ni
    # que se alcanzo a hacer, ni que fallo -- y esa corrida ya habia rebindeado un puerto USB y
    # tocado una exclusion de Defender. Todo va con su propio try: aca ya explotamos una vez.
    $pcIdErr = ''
    try { $pcIdErr = [string](Get-PcId) } catch {}
    $entornoErr = $null
    try { $entornoErr = Get-EnvironmentInfo } catch {}
    $duracionErr = 0
    try { $duracionErr = [int]((Get-Date) - $script:StartTime).TotalMilliseconds } catch {}
    $ultimoCheckErr = ''
    try { if (@($script:Checks).Count -gt 0) { $ultimoCheckErr = [string](@($script:Checks)[-1].id) } } catch {}

    $human = New-Object System.Text.StringBuilder
    [void]$human.AppendLine("== FudoPrintDoctor ==")
    [void]$human.AppendLine("RESULTADO: ERROR DEL MOTOR (el diagnostico no se pudo completar).")
    [void]$human.AppendLine("Detalle: $msg")
    [void]$human.AppendLine("Donde: linea $line -> $cmd")
    if ($hint) { [void]$human.AppendLine("Que hacer: $hint") }
    else { [void]$human.AppendLine("Que hacer: reintentar con -Verbose y adjuntar este JSON al escalamiento a Soporte Producto.") }

    $err = [ordered]@{
        schemaVersion = $script:SchemaVersion
        status        = 'engine_error'
        caseId        = $CaseId
        clientId      = $ClientId
        host          = $env:COMPUTERNAME
        pcId          = $pcIdErr
        timestamp     = (Get-Date).ToString('o')
        entorno       = $entornoErr
        checks        = @($script:Checks)
        diagnosis     = [ordered]@{
            resolved         = $false
            status           = 'engine_error'
            paperOk          = $false
            rootCause        = ('El motor aborto: ' + $msg)
            rootCauseCheckId = 'engine.fatal'
            confidence       = 'low'
            autoFixesApplied = @()
            needsEscalation  = $true
            engineErrorCount = (@($script:Errors).Count + 1)
        }
        telemetry     = [ordered]@{
            durationMs    = $duracionErr
            checksTotal   = @($script:Checks).Count
            autoFixCount  = 0
            accionesCount = @($script:Actions).Count
            category      = 'engine_error'
            ultimoCheck   = $ultimoCheckErr
            ultimoPaso    = [string]$script:StepLabel
        }
        error         = [ordered]@{
            message    = $msg
            type       = $type
            errorId    = [string]$_.FullyQualifiedErrorId
            scriptLine = $line
            command    = $cmd
            stack      = $stack
            hint       = $hint
        }
        nextActions   = @(
            [ordered]@{ priority = 1; checkId = 'engine.fatal'; layer = 9; status = 'engine_error'
                        what = "El motor aborto: $msg"
                        do   = $(if ($hint) { $hint } else { 'Reintentar con -Verbose; si persiste, escalar a Soporte Producto con este JSON.' })
                        owner = 'soporte'; articleRef = '' }
        )
        partial       = [ordered]@{
            checks         = @($script:Checks)
            actionsApplied = @($script:Actions)
            engineErrors   = @($script:Errors)
            log            = @($script:Log)
        }
        humanSummary  = $human.ToString()
    }
    Write-DoctorResult -Obj $err
    exit 3
} finally {
    # La IP secundaria que se agrego para poder ver una impresora de otra subred se saca SIEMPRE,
    # tambien si el motor aborto: dejarle una direccion de mas a la placa del cliente seria peor
    # que no haber revisado nada. Va en finally justamente porque los caminos de salida son
    # varios exit distintos.
    try {
        $sacadasFin = @(Remove-TempSubnetIps)
        if (@($sacadasFin).Count -gt 0) {
            Write-DoctorLog -Level 'INFO' -Message ('IPs temporales retiradas: ' + (@($sacadasFin) -join ', '))
        }
    } catch {}
}
