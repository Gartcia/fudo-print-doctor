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

.PARAMETER NoUpdateCheck
    No consulta si hay una version mas nueva publicada.
    NOTA DE DISENO: el motor avisa cuando hay una version nueva, pero NUNCA se actualiza solo.
    Corre en la PC de un cliente y no esta firmado digitalmente: una actualizacion automatica
    propagaria cualquier bug (o cualquier cambio malicioso en el repo) a todos los locales sin que
    nadie lo revise. La actualizacion es una accion explicita: la opcion A del menu, o el
    Actualizar-FudoPrintDoctor.cmd del asesor. El chequeo ya se saltea solo en modo
    agente (-Quiet / -Json / salida redirigida) y nunca bloquea el diagnostico.

.PARAMETER CheckUpdate
    Solo consulta la version publicada, informa y termina. No diagnostica nada.

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
$script:SchemaVersion = '2.9'
# Distribucion: repo publico. VERSION es un archivo de una linea con la version publicada.
$script:RepoUrl    = 'https://github.com/Gartcia/fudo-print-doctor'
$script:RawBase    = 'https://raw.githubusercontent.com/Gartcia/fudo-print-doctor/main'
$script:UpdateNote = ''   # mensaje de "hay version nueva", si corresponde
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
}
$script:StepTotal   = 9      # usb y red son excluyentes
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
}

function Complete-LiveStatus {
    <# Cierra la linea de progreso de la etapa con su resultado y color. #>
    param([string]$Text, [string]$Color = 'Gray')
    if (-not (Test-IsInteractiveConsole)) { return }
    $line = '  ' + $Text
    Write-Host ("`r" + $line + (' ' * [Math]::Max(0, $script:LiveWidth - $line.Length))) -ForegroundColor $Color
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

function Test-IsInteractiveConsole {
    <# Hay un humano mirando esta consola? (no redirigida, no -Quiet, no -Json) #>
    if ($Quiet -or $Json -or $SelfTest) { return $false }
    try {
        if ([Console]::IsOutputRedirected -or [Console]::IsInputRedirected) { return $false }
    } catch { return $false }
    return $true
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

    [Console]::Error.WriteLine('')
    [Console]::Error.WriteLine('  ------------------------------------------------------------')
    [Console]::Error.WriteLine("  Hace falta una accion que NO se puede deshacer:")
    [Console]::Error.WriteLine("    $Description")
    if ($Impact) { [Console]::Error.WriteLine("    Consecuencia: $Impact") }
    [Console]::Error.WriteLine('  ------------------------------------------------------------')
    $ans = ''
    try { $ans = Read-Host '  Aplicar? (s = si / cualquier otra tecla = no)' } catch { return $false }
    return ($ans -match '(?i)^\s*(s|si|sí|y|yes)\s*$')
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
    [void]$sb.Append("`n`n`n")
    [void]$sb.Append($GS + 'V' + [char]66 + [char]0) # corte parcial con feed
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
    Add-Check -Id 'env.fudoApp' -Layer 0 -Name 'App Nativa de Fudo en ejecucion' -Status $(if($fudoPresent){'ok'}else{'warn'}) `
        -RootCauseCandidate (-not $fudoPresent) `
        -Evidence @{ processes = @($fudoProc | Select-Object -First 5 | ForEach-Object { $_.Name }); services = @($fudoSvc | ForEach-Object { $_.Name }) } `
        -ArticleRef 'https://soporte.fu.do/es/articles/16419361' `
        -Recommendation $(if($fudoPresent){''}else{'La App Nativa de Fudo es prerequisito para imprimir. Verificar instalacion/arranque.'})

    return $true
}

# ---------------------------------------------------------------------------
# LAYER 0b - App Nativa de Fudo vs Antivirus
# Causa muy frecuente: la App Nativa queda bloqueada / en cuarentena por Defender o Avast.
# Estrategia: exclusiones quirurgicas (ruta + proceso) en vez de desactivar el antivirus.
# ---------------------------------------------------------------------------
function Find-FudoNativeInstall {
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
                $regInfo += [ordered]@{ name = $_.DisplayName; version = $_.DisplayVersion; location = $_.InstallLocation }
                if ($_.InstallLocation) { $paths += $_.InstallLocation }
            }
        } catch {}
    }
    return [ordered]@{
        paths   = @($paths | Where-Object { $_ } | Select-Object -Unique)
        regInfo = $regInfo
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
                $state.fudoThreats += [ordered]@{ id = [string]$t.ThreatID; resources = $res; action = [string]$t.ActionSuccess }
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

function Test-Layer0b-NativeApp {
    $install = Find-FudoNativeInstall
    $av = Get-AntivirusState
    $script:Diagnostics['nativeInstall'] = $install
    $script:Diagnostics['antivirus']     = $av

    $procRunning = $false
    try { $procRunning = @(Get-Process -ErrorAction SilentlyContinue | Where-Object { $_.Name -like "*$FudoAppProcess*" }).Count -gt 0 } catch {}

    $installed = (@($install.paths).Count -gt 0) -or (@($install.regInfo).Count -gt 0)

    # 0b.1 Nativa instalada?
    if (-not $installed) {
        Add-Check -Id 'nativa.installed' -Layer 0 -Name 'App Nativa de Fudo instalada' -Status 'fail' -RootCauseCandidate $true -Plane 'fudo_config' `
            -Evidence @{ found = $false } -ArticleRef 'https://soporte.fu.do/es/articles/16419361' `
            -Recommendation 'La App Nativa no aparece instalada. Instalar Nativa + extension del navegador (accion asistida; frecuentemente bloqueada por antivirus).'
    } else {
        Add-Check -Id 'nativa.installed' -Layer 0 -Name 'App Nativa de Fudo instalada' -Status $(if($procRunning){'ok'}else{'warn'}) `
            -RootCauseCandidate (-not $procRunning) `
            -Evidence @{ paths = $install.paths; reg = $install.regInfo; running = $procRunning } `
            -Recommendation $(if($procRunning){''}else{'La Nativa esta instalada pero no en ejecucion: posible bloqueo por antivirus.'})
    }

    # 0b.2 Amenazas/cuarentena de Defender sobre la Nativa
    if (@($av.fudoThreats).Count -gt 0) {
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
        Add-Check -Id 'nativa.defenderQuarantine' -Layer 0 -Name 'Nativa en cuarentena de Windows Defender' -Status $(if($rem.applied){'fixed'}else{'fail'}) -RootCauseCandidate $true `
            -Evidence @{ threats = $av.fudoThreats } -ActionTaken $rem.note `
            -Recommendation 'Preferir exclusiones (ruta+proceso) a desactivar el antivirus. Reinstalar/reiniciar la Nativa tras excluir.'
    } elseif ($installed -and -not $procRunning -and $UseDefenderExclusions -and $av.defender) {
        # Nativa instalada pero no corre y Defender activo: exclusion preventiva quirurgica
        $rem = Invoke-Remediation -Description 'Agregar exclusiones preventivas de Defender para la Nativa' -Type 'defender.exclude' -Target 'FudoNativa' `
            -Before 'sin exclusiones' -After 'excluida' -Fix {
                $notes = @()
                foreach ($p in $install.paths) { try { Add-MpPreference -ExclusionPath $p -ErrorAction SilentlyContinue; $notes += "excl $p" } catch {} }
                try { Add-MpPreference -ExclusionProcess "$FudoAppProcess*.exe" -ErrorAction SilentlyContinue; $notes += 'excl process' } catch {}
                ($notes -join ' | ')
            }
        Add-Check -Id 'nativa.defenderExclusion' -Layer 0 -Name 'Exclusion preventiva de Defender para la Nativa' -Status $(if($rem.applied){'fixed'}else{'warn'}) -RootCauseCandidate $true `
            -Evidence @{ realTime = $av.realTime; paths = $install.paths } -ActionTaken $rem.note `
            -Recommendation 'Tras excluir, reiniciar la Nativa. Si sigue sin correr, reinstalar la Nativa.'
    }

    # 0b.3 Antivirus de terceros (Avast, etc.): no scriptable -> guiado/escalar
    if (@($av.thirdParty).Count -gt 0) {
        Add-Check -Id 'nativa.thirdPartyAV' -Layer 0 -Name 'Antivirus de terceros presente' -Status 'warn' -RootCauseCandidate (-not $procRunning) -Plane 'hardware' `
            -Evidence @{ products = $av.thirdParty } -Reversible $true `
            -Recommendation "Detectado $($av.thirdParty -join ', '). Puede poner la Nativa en cuarentena. Requiere accion guiada en el AV (excluir/restaurar), no automatizable de forma segura."
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
            $compat = Get-CompatibleIdList -WmiEntity $d -InstanceId $inst
            $verdict = Test-IsPrinterDevice -Name ([string]$d.Name) -InstanceId $inst `
                        -PnpClass ([string]$d.PNPClass) -Service ([string]$d.Service) -CompatibleIds $compat
            if ($verdict.isPrinter) {
                $devices += [ordered]@{
                    source = 'Win32_PnPEntity'; name = [string]$d.Name; instanceId = $inst
                    portName = ''; status = [string]$d.Status
                    problem = $(try { [int]$d.ConfigManagerErrorCode } catch { 0 })
                    deteccion = [string]$verdict.reason; certeza = [string]$verdict.confidence
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
    return @($byId.Values)
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
        if ($d -match '(?i)generic|gen[eé]rico' -and $d -match '(?i)text|texto') { return $d }
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
            if (-not $porImp.ContainsKey($imp)) {
                $porImp[$imp] = [ordered]@{ impresora = $imp; total = 0; deFudo = 0; ultimo = ''; ultimoDeFudo = ''; ejemploDoc = $doc }
            }
            $porImp[$imp].total++
            if (-not $porImp[$imp].ultimo) { $porImp[$imp].ultimo = $e.TimeCreated.ToString('dd/MM HH:mm') }
            # La Nativa manda los trabajos con este nombre
            if ($doc -match '(?i)node print job|fudo') {
                $porImp[$imp].deFudo++
                if (-not $porImp[$imp].ultimoDeFudo) { $porImp[$imp].ultimoDeFudo = $e.TimeCreated.ToString('dd/MM HH:mm') }
            }
        }
    } catch {}
    return [ordered]@{ habilitado = $true; porImpresora = @($porImp.Values) }
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
        if (@($jobs).Count -gt 0) {
            try {
                $t = @($jobs | Where-Object { $_.SubmittedTime } | Sort-Object SubmittedTime | Select-Object -First 1)
                if (@($t).Count -gt 0) { $masViejo = ([datetime]@($t)[0].SubmittedTime).ToString('dd/MM HH:mm') }
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
            offline = $offline; pausada = $pausada; trabajos = @($jobs).Count; trabajoMasViejo = $masViejo
            puertoVivo = [bool]$puertoVivo; esPos = (Test-IsPosPrinter $q)
            score = $score; sintomas = @($sintomas)
            estado = $(if ($score -eq 0) { 'sana' } elseif ($score -ge 40) { 'no imprime' } else { 'con problemas' })
        }
    }
    return @($out | Sort-Object -Property @{ Expression = { [int]$_.score }; Descending = $true })
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
    $script:Diagnostics['colas'] = $colas
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
        Write-LiveStatus ("  Esperando que desconectes y vuelvas a conectar el USB de la impresora... ${restante}s")
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
        [Console]::Error.WriteLine('')
        [Console]::Error.WriteLine('  ------------------------------------------------------------')
        [Console]::Error.WriteLine("  La cola '$($Printer.Name)' apunta a $($Printer.PortName), donde no hay ningun")
        [Console]::Error.WriteLine('  dispositivo conectado. Lo que suele resolverlo es desenchufar el')
        [Console]::Error.WriteLine('  cable USB de la impresora y volver a enchufarlo (con la impresora')
        [Console]::Error.WriteLine('  encendida): Windows la vuelve a detectar y le asigna un puerto.')
        [Console]::Error.WriteLine('  ------------------------------------------------------------')
        $ans = ''
        try { $ans = Read-Host '  Espero mientras lo haces? (s = si / cualquier otra tecla = no)' } catch {}
        $quiere = ($ans -match '(?i)^\s*(s|si|sí|y|yes)\s*$')
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
        Add-Check -Id 'queue.health' -Layer 2 -Name 'Cola de impresion trabada' -Status $(if($rem.applied){'fixed'}else{'warn'}) -RootCauseCandidate $true `
            -Evidence @{ jobs = @($jobs).Count; stuck = @($stuck).Count; statuses = @($jobs | ForEach-Object { [string]$_.JobStatus }) } `
            -ActionTaken $rem.note -Reversible $false `
            -Recommendation $(if ($rem.applied) {
                    'Un trabajo trabado bloquea toda la cola: se limpio. Volver a imprimir desde Fudo las comandas que estaban esperando.'
                } elseif (@($jobs).Count -ge 50) {
                    "Hay $(@($jobs).Count) trabajos acumulados: la App Nativa siguio mandando comandas que nunca salieron. Eso confirma que el problema NO es Fudo (las comandas llegan), sino la impresora o su cola en Windows. Limpiar la cola descarta esos trabajos (son comandas viejas que ya no sirven). Para hacerlo: correr el script en la consola y responder 's' cuando pregunte, o pasar -AllowQueuePurge `$true, o a mano: Get-PrintJob -PrinterName '$($Printer.Name)' | Remove-PrintJob"
                } else {
                    "Un trabajo trabado bloquea toda la cola: las comandas nuevas no salen hasta limpiarla. Limpiarla descarta los $(@($jobs).Count) trabajos pendientes (hay que reimprimirlos desde Fudo). Para hacerlo: correr el script en la consola y responder 's' cuando pregunte, o pasar -AllowQueuePurge `$true, o a mano: Get-PrintJob -PrinterName '$($Printer.Name)' | Remove-PrintJob"
                })
    } else {
        Add-Check -Id 'queue.health' -Layer 2 -Name 'Cola de impresion' -Status 'warn' `
            -Evidence @{ jobs = @($jobs).Count; note = 'trabajos presentes pero no evidentemente trabados' }
    }
}

# ---------------------------------------------------------------------------
# LAYER 3 - Conectividad / puerto
# ---------------------------------------------------------------------------
function Get-DetectedInterface {
    param($Printer)
    if ($Interface -ne 'auto') { return $Interface }
    if ($PrinterIp) { return 'Ethernet' }
    $port = ''
    if ($Printer) { try { $port = [string]$Printer.PortName } catch {} }
    if ($port -like 'USB*' -or $port -like 'LPT*' -or $port -like '*USB*') { return 'USB' }
    if ($port -match '^\d{1,3}(\.\d{1,3}){3}' -or $port -like 'IP_*' -or $port -like '*9100*') { return 'Ethernet' }
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

    Write-StepDetail "probando en que puerto responde '$nombre'"
    try {
        Initialize-RawPrinterHelper
        $ticket = [System.Text.Encoding]::GetEncoding(437).GetBytes((Get-EscPosTestTicket -Caption 'FUDO PORT TEST'))
        foreach ($cp in @($CandidatePorts)) {
            $tmp = ''
            try {
                Write-StepDetail "probando el puerto $cp"
                $tmp = New-FudoTestPrinter -PortName $cp
                if (-not $tmp) { continue }
                Start-Sleep -Milliseconds 600
                if ([FudoRawPrinter]::SendBytes($tmp, $ticket)) {
                    Start-Sleep -Milliseconds 1500
                    $pend = @()
                    try { $pend = @(Get-PrintJob -PrinterName $tmp -ErrorAction SilentlyContinue) } catch {}
                    if (@($pend).Count -eq 0) { $puertoOk = $cp; $temporal = $tmp; break }
                }
                try { Remove-Printer -Name $tmp -ErrorAction SilentlyContinue } catch {}
            } catch {}
        }
    } catch {}

    if (-not $puertoOk) {
        return @{ applied = $false; note = "ninguno de los puertos probados ($(@($CandidatePorts) -join ', ')) imprimio un ticket de prueba" }
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
                    Start-Sleep -Milliseconds 1800
                    $pend = @()
                    try { $pend = @(Get-PrintJob -PrinterName $Printer.Name -ErrorAction SilentlyContinue | Where-Object { [string]$_.DocumentName -match '(?i)fudo' }) } catch {}
                    if (@($pend).Count -gt 0) {
                        try { $pend | Remove-PrintJob -ErrorAction SilentlyContinue } catch {}
                        continue
                    }
                    $chosen = $cp; break
                } catch {}
            }
            if ($null -eq $chosen) {
                try { Set-Printer -Name $Printer.Name -PortName $currentPort -ErrorAction SilentlyContinue } catch {}
                "ningun candidato imprimio un ticket de verdad; puerto revertido a $currentPort"
            } else {
                "puerto reasignado a $chosen y el ticket salio de la cola"
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
        Add-Check -Id 'hw.testprint' -Layer 4 -Name 'Prueba fisica de impresion' -Status 'skipped' -Evidence @{ note = 'TestPrint deshabilitado' }
        return
    }
    if ($DryRun) {
        Add-Check -Id 'hw.testprint' -Layer 4 -Name 'Prueba fisica de impresion' -Status 'skipped' -Evidence @{ note = 'dry-run' }
        return
    }

    if ($DetectedInterface -eq 'Ethernet') {
        $ip = $script:Diagnostics['printerIp']
        if (-not $ip) { Add-Check -Id 'hw.testprint' -Layer 4 -Name 'Prueba fisica (TCP 9100)' -Status 'skipped' -Evidence @{ note = 'sin IP' }; return }
        try {
            Write-StepDetail ("enviando ticket de prueba a " + $ip + ":" + $Port)
            $ok = Send-EscPosOverTcp -Ip $ip -TcpPort $Port
            Add-Check -Id 'hw.testprint' -Layer 4 -Name 'Prueba fisica ESC/POS por red' -Status $(if($ok){'ok'}else{'fail'}) -RootCauseCandidate (-not $ok) `
                -Plane 'hardware' -Evidence @{ ip = $ip; port = $Port; sent = $ok } `
                -Recommendation $(if($ok){'El hardware imprime OK por red: si la comanda no sale, la causa esta en la config de Fudo (area/cocina/sala).'}else{'No se pudo enviar al hardware por red.'})
        } catch {
            Add-Check -Id 'hw.testprint' -Layer 4 -Name 'Prueba fisica ESC/POS por red' -Status 'fail' -RootCauseCandidate $true `
                -Plane 'hardware' -Evidence @{ ip = $ip; error = $_.Exception.Message } `
                -ArticleRef 'https://soporte.fu.do/es/articles/11730816'
        }
    } else {
        if ($null -eq $Printer) {
            Add-Check -Id 'hw.testprint' -Layer 4 -Name 'Prueba fisica de impresion' -Status 'skipped' -Plane 'hardware' `
                -Evidence @{ note = 'sin impresora real objetivo' } `
                -Recommendation 'No hay una impresora fisica instalada para probar: resolver primero la capa 1 (hardware/instalacion).'
            return
        }
        if (-not (Test-PortHasLiveDevice -PortName ([string]$Printer.PortName))) {
            Add-Check -Id 'hw.testprint' -Layer 4 -Name 'Prueba fisica de impresion' -Status 'skipped' -Plane 'hardware' `
                -Evidence @{ printer = [string]$Printer.Name; port = [string]$Printer.PortName } `
                -Recommendation ("No se prueba: en $($Printer.PortName) no hay ningun dispositivo conectado. " +
                                 'Enviar un ticket ahi solo lo dejaria encolado y daria un falso OK de hardware.')
            return
        }
        $v = Test-IsVirtualPrinter $Printer
        if ($v.isVirtual) {
            Add-Check -Id 'hw.testprint' -Layer 4 -Name 'Prueba fisica de impresion' -Status 'skipped' -Plane 'hardware' `
                -Evidence @{ printer = [string]$Printer.Name; reason = [string]$v.reason } `
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
            if ($ok) {
                Write-StepDetail 'verificando que el ticket haya salido'
                Start-Sleep -Milliseconds 1800
                try {
                    $pend = @(Get-PrintJob -PrinterName $Printer.Name -ErrorAction SilentlyContinue |
                              Where-Object { [string]$_.DocumentName -match '(?i)fudo print doctor' })
                    $quedoEnCola = (@($pend).Count -gt 0)
                } catch {}
            }
            if ($quedoEnCola) {
                Add-Check -Id 'hw.testprint' -Layer 4 -Name 'Prueba fisica ESC/POS por USB (RAW)' -Status 'fail' -RootCauseCandidate $true `
                    -Plane 'hardware' -Evidence @{ printer = $Printer.Name; sent = $true; quedoEnCola = $true } `
                    -ArticleRef 'https://soporte.fu.do/es/articles/11730817' `
                    -Recommendation ('El ticket entro a la cola pero no se imprimio: la impresora no esta respondiendo. ' +
                                     'Revisar que este encendida, con papel, la tapa cerrada y el cable USB firme. ' +
                                     'Si la luz esta en rojo o titilando, es falla de hardware o falta de papel.')
                return
            }

            Add-Check -Id 'hw.testprint' -Layer 4 -Name 'Prueba fisica ESC/POS por USB (RAW)' -Status $(if($ok){'ok'}else{'fail'}) -RootCauseCandidate (-not $ok) `
                -Plane 'hardware' -Evidence @{ printer = $Printer.Name; sent = $ok; quedoEnCola = $false } `
                -ArticleRef 'https://soporte.fu.do/es/articles/12044021' `
                -Recommendation $(if($ok){'El hardware imprime OK: si la comanda no sale, revisar config de Fudo (area/cocina/sala). Si imprime en blanco, revisar rollo/papel al reves.'}else{'El envio RAW fallo: revisar puerto/driver/cable.'})
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
        Add-Check -Id 'fudo.usoReal' -Layer 5 -Name 'Historial de impresion no disponible' -Status $(if ($rem.applied) { 'fixed' } else { 'skipped' }) -Plane 'os' `
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

    # Prioridad por capa (mas abajo primero: OS/HW antes que config)
    $ordered = @($rootCandidates | Sort-Object { $_.layer })

    $hwTest = $checks | Where-Object { $_.id -eq 'hw.testprint' } | Select-Object -First 1

    $resolved = $false
    $rootCause = $null
    $confidence = 'low'
    $residual = @()

    if (@($fixed).Count -gt 0 -and @($fails).Count -eq 0) {
        # Se aplicaron fixes y no quedan fallas duras
        if ($hwTest -and $hwTest.status -eq 'ok') {
            $resolved = $true; $confidence = 'high'
            $rootCause = ($fixed | Sort-Object { $_.layer } | Select-Object -First 1).name
        } else {
            $resolved = $true; $confidence = 'medium'
            $rootCause = ($fixed | Sort-Object { $_.layer } | Select-Object -First 1).name
        }
    }

    if (-not $resolved) {
        if (@($ordered).Count -gt 0) {
            $rootCause = $ordered[0].name
            $confidence = if ($ordered[0].plane -eq 'fudo_config') { 'medium' } else { 'medium' }
        } elseif ($hwTest -and $hwTest.status -eq 'ok') {
            # HW OK y nada roto en OS => casi seguro config Fudo
            $rootCause = 'Hardware imprime OK; causa probable en configuracion de Fudo (area/cocina/sala)'
            $confidence = 'medium'
        } else {
            $rootCause = 'No concluyente'
            $confidence = 'low'
        }
    }

    # Residual a escalar: cualquier check fudo_config en warn/fail o fallas no resueltas
    $residual = @($checks | Where-Object {
        ($_.status -in @('fail','warn')) -and ($_.plane -eq 'fudo_config' -or ($_.rootCauseCandidate -and $_.status -eq 'fail'))
    } | ForEach-Object { @{ id = $_.id; name = $_.name; plane = $_.plane; recommendation = $_.recommendation; articleRef = $_.articleRef } })

    $needsEscalation = (-not $resolved) -or (@($residual).Count -gt 0)

    $diag = [ordered]@{
        resolved        = $resolved
        rootCause       = $rootCause
        rootCauseCheckId = $(if (@($ordered).Count -gt 0) { [string]$ordered[0].id } elseif (@($fixed).Count -gt 0) { [string](@($fixed | Sort-Object { $_.layer })[0].id) } else { '' })
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

function Get-Category {
    param($Diag)
    # Categorizacion para telemetria: permite agrupar los casos por causa
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

function Build-HumanSummary {
    <# Resumen corto para humanos. El detalle completo vive en el JSON. #>
    param($Diag, $DetectedInterface)
    $L = New-Object System.Collections.ArrayList
    function Add-Line { param([string]$T = '') [void]$L.Add($T) }

    $bar = '=' * 78
    Add-Line $bar
    Add-Line ("  FUDO PRINT DOCTOR   v$($script:SchemaVersion)   PC: $env:COMPUTERNAME" +
              $(if ($CaseId) { "   Caso: $CaseId" } else { '' }))
    Add-Line ("  Modo: " + $(if ($DryRun) { 'solo diagnostico (-DryRun)' } elseif ($AutoFix) { 'diagnostico + reparacion' } else { 'solo diagnostico' }) +
              "   Interfaz: $DetectedInterface")
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
    $conn = @()
    if ($script:Diagnostics.Contains('printersConnected')) { $conn = @($script:Diagnostics['printersConnected']) }
    Add-Line ''
    Add-Line ("  HARDWARE DE IMPRESION CONECTADO: " + @($conn).Count)
    $desc = @()
    if ($script:Diagnostics.Contains('descartadosNoImpresora')) { $desc = @($script:Diagnostics['descartadosNoImpresora']) }
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
    foreach ($a in $areas) {
        $st = Get-AreaStatus -Ids $a.ids
        if ($st -eq '-' -and $a.t -eq 'Motor (fallas internas)') { continue }
        $dots = '.' * [Math]::Max(3, (30 - ([string]$a.t).Length))
        Add-Line ("    " + $a.t + ' ' + $dots + ' ' + $st)
    }

    # --- resultado
    $conf = switch ([string]$Diag.confidence) { 'high' { 'alta' } 'medium' { 'media' } default { 'baja' } }
    Add-Line ''
    $target = ''
    if ($script:Diagnostics.Contains('printer')) { $target = [string]$script:Diagnostics['printer'].name }
    if ($target) { Add-Line ("  IMPRESORA DIAGNOSTICADA: $target") }
    if ($Diag.resolved) { Add-Line ("  RESULTADO: RESUELTO   (confianza $conf)") }
    else { Add-Line ("  RESULTADO: NO RESUELTO AUTOMATICAMENTE   (confianza $conf)") }
    foreach ($ln in @(Format-Wrap -Text ("CAUSA: " + [string]$Diag.rootCause) -Indent '         ')) { Add-Line ("  $ln") }
    if (@($Diag.autoFixesApplied).Count -gt 0) {
        foreach ($ln in @(Format-Wrap -Text ("SE ARREGLO: " + (@($Diag.autoFixesApplied) -join '; ')) -Indent '         ')) { Add-Line ("  $ln") }
    }

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
    foreach ($ln in $lines) {
        $color = 'Gray'
        if ($ln -match '^=+$')                              { $color = 'DarkGray' }
        elseif ($ln -match 'FUDO PRINT DOCTOR')             { $color = 'Cyan' }
        elseif ($ln -match '\bFALLA\b|NO RESUELTO')         { $color = 'Red' }
        elseif ($ln -match '\bREVISAR\b')                   { $color = 'Yellow' }
        elseif ($ln -match '\bREPARADO\b|RESUELTO|SE ARREGLO') { $color = 'Green' }
        elseif ($ln -match '^\s{2}[A-Z][A-Z ()/]+$')        { $color = 'White' }
        elseif ($ln -match 'CAUSA:')                        { $color = 'Magenta' }
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
    Write-DoctorLog -Level 'INFO' -Message "Inicio FudoPrintDoctor (AutoFix=$AutoFix, DryRun=$DryRun, Interface=$Interface)"

    if (Test-IsInteractiveConsole) {
        Write-Host ''
        Write-Host '  Revisando la cadena de impresion...' -ForegroundColor Cyan
        Write-Host ''
    }

    $null = Invoke-Step -Name 'update.check' -Body { Test-UpdateAvailable }
    if ($script:UpdateNote) {
        Add-Check -Id 'engine.updateAvailable' -Layer 0 -Name 'Hay una version mas nueva del motor' -Status 'warn' -Plane 'os' `
            -Evidence @{ actual = $script:SchemaVersion } -Recommendation $script:UpdateNote
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
        $null = Invoke-Step -Name 'layer1a.hardwareInventory' -Body { Test-Layer1a-HardwareInventory }
        $printer = Invoke-Step -Name 'layer1.resolvePrinter' -Body { Resolve-TargetPrinter }
        $wmi = Invoke-Step -Name 'layer1.printerState' -Body { Test-Layer1-PrinterState -Printer $printer }
        if ($script:ReconnectedPort -and $printer) {
            $refrescada = Invoke-Step -Name 'layer1.refresh' -Body { Get-Printer -Name ([string]$printer.Name) -ErrorAction SilentlyContinue }
            if ($refrescada) { $printer = $refrescada }
        }
        $null = Invoke-Step -Name 'layer2.queue' -Body { Test-Layer2-Queue -Printer $printer -Wmi $wmi }
        $detectedInterface = Invoke-Step -Name 'layer3.detectInterface' -Body { Get-DetectedInterface -Printer $printer }
        if (-not $detectedInterface) { $detectedInterface = 'USB' }
        if ($detectedInterface -eq 'USB') {
            $null = Invoke-Step -Name 'layer3.usbPort' -Body { Test-Layer3-UsbPort -Printer $printer -Wmi $wmi }
        } else {
            $null = Invoke-Step -Name 'layer3.network' -Body { Test-Layer3-Network -Printer $printer }
        }
        $null = Invoke-Step -Name 'layer4.hardwarePrint' -Body { Test-Layer4-HardwarePrint -Printer $printer -DetectedInterface $detectedInterface }
        $null = Invoke-Step -Name 'layer5.fudoConfig' -Body { Test-Layer5-FudoConfig -DetectedInterface $detectedInterface }
    }

    # Colas temporales: se conservan por defecto (sirven para reprobar); -KeepTestPrinter:$false las borra.
    if (@($script:TestPrintersCreated).Count -gt 0) {
        $names = @($script:TestPrintersCreated)
        if ($script:BoundParams -and $script:BoundParams.ContainsKey('KeepTestPrinter') -and -not $KeepTestPrinter) {
            foreach ($n in $names) { try { Remove-Printer -Name $n -ErrorAction SilentlyContinue } catch {} }
            Add-Check -Id 'printer.testCleanup' -Layer 1 -Name 'Cola de prueba eliminada' -Status 'ok' -Evidence @{ removed = $names }
        } else {
            Add-Check -Id 'printer.testCleanup' -Layer 1 -Name 'Cola de prueba conservada' -Status 'warn' -Plane 'os' `
                -Evidence @{ kept = $names } `
                -Recommendation ("Queda instalada la cola de prueba " + ($names -join ', ') + ". Borrarla cuando se instale la definitiva: Remove-Printer -Name '" + (@($names)[0]) + "'")
        }
    }

    if (Test-IsInteractiveConsole) { Write-Host '' }

    $diag = Resolve-Diagnosis
    $durationMs = [int]((Get-Date) - $script:StartTime).TotalMilliseconds
    $category = Get-Category -Diag $diag

    $result = [ordered]@{
        schemaVersion = $script:SchemaVersion
        updateAvailable = [string]$script:UpdateNote
        telemetria    = $script:TelemetryStatus
        status        = $(if ($diag.resolved -and -not $diag.needsEscalation) { 'resolved' }
                          elseif (@($script:Errors).Count -gt 0) { 'partial_engine_error' }
                          else { 'needs_escalation' })
        caseId        = $CaseId
        clientId      = $ClientId
        host          = $env:COMPUTERNAME
        timestamp     = (Get-Date).ToString('o')
        interface     = $detectedInterface
        dryRun        = [bool]$DryRun
        autoFix       = [bool]$AutoFix
        printer       = $(if ($script:Diagnostics.Contains('printer')) { $script:Diagnostics['printer'] } else { $null })
        entorno       = $(Invoke-Step -Name 'env.info' -Body { Get-EnvironmentInfo })
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
            autoFixCount    = @($script:Actions).Count
            resolved        = $diag.resolved
            escalated       = $diag.needsEscalation
            category        = $category
            confidence      = $diag.confidence
            engineErrors    = @($script:Errors).Count
        }
        humanSummary  = (Build-HumanSummary -Diag $diag -DetectedInterface $detectedInterface)
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

    function Get-CheckById { param([string]$Id) return (@($script:Checks | Where-Object { $_.id -eq $Id }) | Select-Object -First 1) }

    function Reset-State {
        $script:Checks  = New-Object System.Collections.ArrayList
        $script:Actions = New-Object System.Collections.ArrayList
        $script:Errors  = New-Object System.Collections.ArrayList
        $script:Diagnostics = [ordered]@{}
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

    # Escenario 3: nada roto en OS + HW ok => no resuelto, apunta a config Fudo
    Reset-State
    Add-Check -Id 'hw.testprint' -Layer 4 -Name 'Prueba fisica' -Status 'ok' -Plane 'hardware'
    Add-Check -Id 'fudo.printerKitchen' -Layer 5 -Name 'Impresora con Cocina/Area asignada' -Status 'warn' -Plane 'fudo_config'
    $d = Resolve-Diagnosis
    Assert-Eq 'S3 escalado' $true $d.needsEscalation
    Assert-Eq 'S3 categoria' 'fudo_config' (Get-Category -Diag $d)

    # Escenario 4: impresora de red inalcanzable => no resuelto, net.ip, escalado
    Reset-State
    Add-Check -Id 'conn.net' -Layer 3 -Name 'Impresora de red inalcanzable (192.168.1.50:9100)' -Status 'fail' -RootCauseCandidate $true -Plane 'fudo_config'
    $d = Resolve-Diagnosis
    Assert-Eq 'S4 resuelto=false' $false $d.resolved
    Assert-Eq 'S4 categoria' 'net.ip' (Get-Category -Diag $d)
    Assert-Eq 'S4 escalado' $true $d.needsEscalation

    # Escenario 5: spooler reiniciado (sin HW test) => resuelto/medium
    Reset-State
    Add-Check -Id 'env.spooler' -Layer 0 -Name 'Servicio Print Spooler' -Status 'fixed' -RootCauseCandidate $true
    $d = Resolve-Diagnosis
    Assert-Eq 'S5 resuelto' $true $d.resolved
    Assert-Eq 'S5 categoria' 'os.spooler' (Get-Category -Diag $d)

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
        [ordered]@{ habilitado = $true; porImpresora = @(
            [ordered]@{ impresora='COCINA'; total=120; deFudo=118; ultimo='21/08 20:10'; ultimoDeFudo='21/08 20:10'; ejemploDoc='node print job' },
            [ordered]@{ impresora='HP LaserJet'; total=3; deFudo=0; ultimo='19/08 11:00'; ultimoDeFudo=''; ejemploDoc='Documento1.docx' }
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
        [ordered]@{ habilitado = $true; porImpresora = @(
            [ordered]@{ impresora='CAJA'; total=2; deFudo=0; ultimo='20/08 10:00'; ultimoDeFudo=''; ejemploDoc='Test Page' }
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
    if (@($huerfanos).Count -gt 0) { $ops += [ordered]@{ k = 'I'; t = ("Instalar la impresora conectada en " + (@($huerfanos) -join ', ') + ' (driver de texto generico)') } }

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
    $r = ''
    try { $r = Read-Host '   Opcion' } catch { return 'S' }
    $r = ([string]$r).Trim().ToUpper()
    if (-not $r) { return 'S' }
    if (@($ops | ForEach-Object { [string]$_.k }) -contains $r) { return $r }
    Write-Host '   Opcion invalida.' -ForegroundColor Yellow
    return '?'
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
                if ($puerto) { Write-Host ("  Apareció una impresora en " + $puerto) -ForegroundColor Green }
                else { Write-Host '  No se detecto ninguna impresora nueva.' -ForegroundColor Yellow }
            }
            $script:ForceWaitReconnect = $false
            return $true
        }

        'I' {
            $huerfanos = @()
            if ($script:Diagnostics.Contains('orphanLivePorts')) { $huerfanos = @($script:Diagnostics['orphanLivePorts'] | Where-Object { $_ }) }
            if (@($huerfanos).Count -eq 0) { Write-Host '  Ya no hay puertos con impresora sin instalar.' -ForegroundColor Yellow; return $true }
            $puerto = @($huerfanos)[0]
            $nombre = ''
            try { $nombre = Read-Host ("   Nombre para la impresora en $puerto (Enter = FUDO-TEST-$puerto)") } catch {}
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
            try { $sel = Read-Host '   Cual instalar? (numero, Enter para cancelar)' } catch {}
            if (-not $sel) { return $false }
            $idx = 0
            try { $idx = [int]$sel } catch { return $false }
            if ($idx -lt 1 -or $idx -gt @($enRed).Count) { Write-Host '  Numero invalido.' -ForegroundColor Yellow; return $false }
            $elegida = @($enRed)[$idx - 1]
            $nombre = ''
            try { $nombre = Read-Host ("   Nombre para la impresora (Enter = FUDO-" + (([string]$elegida.ip) -replace '\.', '-') + ')') } catch {}
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
                Start-Sleep -Milliseconds 1500
                $pend = @()
                try { $pend = @(Get-PrintJob -PrinterName $nombre -ErrorAction SilentlyContinue | Where-Object { [string]$_.DocumentName -match '(?i)fudo' }) } catch {}
                if ($ok -and @($pend).Count -eq 0) { Write-Host ("  Ticket enviado a '" + $nombre + "'. Si salio el papel, el hardware imprime.") -ForegroundColor Green }
                elseif ($ok) { Write-Host '  El ticket quedo en la cola: la impresora no esta respondiendo.' -ForegroundColor Yellow }
                else { Write-Host '  No se pudo enviar el ticket.' -ForegroundColor Red }
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
            try { $ruta = Read-Host '   Ruta del archivo (Enter = resultado.json aca al lado)' } catch {}
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
# ---------------------------------------------------------------------------
function Find-LocalNativeInstaller {
    <# Busca un instalador de la Nativa ya presente: al lado del script, en Descargas o en el Escritorio. #>
    if ($NativeInstallerPath) {
        if (Test-Path $NativeInstallerPath) { return (Resolve-Path $NativeInstallerPath).Path }
        return ''
    }
    $donde = @()
    try { $donde += (Split-Path -Parent $PSCommandPath) } catch {}
    try { $donde += (Get-Location).Path } catch {}
    if ($env:USERPROFILE) { $donde += @((Join-Path $env:USERPROFILE 'Downloads'), (Join-Path $env:USERPROFILE 'Desktop')) }
    foreach ($d in @($donde | Where-Object { $_ })) {
        foreach ($pat in @('Fudo*.exe','*fudo*.exe','*Nativa*.exe')) {
            try {
                $hit = @(Get-ChildItem -Path $d -Filter $pat -File -ErrorAction SilentlyContinue |
                         Where-Object { $_.Length -gt 200KB } | Sort-Object LastWriteTime -Descending) | Select-Object -First 1
                if ($hit) { return [string]$hit.FullName }
            } catch {}
        }
    }
    return ''
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
    $local = Find-LocalNativeInstaller
    if ($local) {
        Write-Host ''
        Write-Host ("  Instalador encontrado en la PC: " + $local) -ForegroundColor Cyan
        return (Invoke-Remediation -Description ('Instalar la App Nativa desde ' + $local) -Type 'nativa.install_local' -Target 'FudoNativa' `
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
                $pr = $null
                if ($NativeInstallerArgs) { $pr = Start-Process -FilePath $local -ArgumentList $NativeInstallerArgs -PassThru -Wait -ErrorAction Stop }
                else { $pr = Start-Process -FilePath $local -PassThru -Wait -ErrorAction Stop }
                $notas += "instalador finalizo con codigo $($pr.ExitCode)"
                Start-Sleep -Seconds 3
                $corriendo = $false
                try { $corriendo = (@(Get-Process -ErrorAction SilentlyContinue | Where-Object { $_.Name -like "*$FudoAppProcess*" }).Count -gt 0) } catch {}
                $notas += $(if ($corriendo) { 'la Nativa esta corriendo' } else { 'la Nativa todavia no aparece corriendo: puede requerir iniciar sesion en la web app de Fudo' })
                ($notas -join ' | ')
            })
    }

    if (-not $url) {
        Write-Host ''
        Write-Host '  No hay URL de instalador configurada, asi que hay que instalarla a mano:' -ForegroundColor Yellow
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
}

function Send-Telemetry {
    <#
      Manda el resultado a un endpoint para no depender de que el asesor guarde el JSON.
      Nunca corta el diagnostico: timeout corto y errores silenciados.
    #>
    param($Result)
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
                clientId      = [string]$Result.clientId
                host          = [string]$Result.host
                timestamp     = [string]$Result.timestamp
                interface     = [string]$Result.interface
                dryRun        = [bool]$Result.dryRun
                rootCause     = [string]$Result.diagnosis.rootCause
                rootCauseCheckId = [string]$Result.diagnosis.rootCauseCheckId
                resolved      = [bool]$Result.diagnosis.resolved
                confidence    = [string]$Result.diagnosis.confidence
                needsEscalation = [bool]$Result.diagnosis.needsEscalation
                autoFixesApplied = @($Result.diagnosis.autoFixesApplied)
                telemetry     = $(
                    $t = [ordered]@{}
                    try { foreach ($k in @($Result.telemetry.Keys)) { $t[$k] = $Result.telemetry[$k] } } catch {}
                    $t['impresoras'] = @($(if ($script:Diagnostics.Contains('colas')) { $script:Diagnostics['colas'] | ForEach-Object { [ordered]@{ nombre = $_.nombre; puerto = $_.puerto; estado = $_.estado; trabajos = $_.trabajos } } } else { @() }))
                    $t['cantidadColas'] = @($(if ($script:Diagnostics.Contains('colas')) { $script:Diagnostics['colas'] } else { @() })).Count
                    $t['cantidadHardware'] = @($(if ($script:Diagnostics.Contains('printersConnected')) { $script:Diagnostics['printersConnected'] } else { @() })).Count
                    $t['historialFudo'] = @($(if ($script:Diagnostics.Contains('historialImpresion')) { $script:Diagnostics['historialImpresion'].porImpresora } else { @() }))
                    $t['entorno'] = $Result.entorno
                    $t
                )
                entorno       = $Result.entorno
                checks        = @($Result.checks | ForEach-Object { [ordered]@{ id = [string]$_.id; status = [string]$_.status; layer = $_.layer } })
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

    $final = Invoke-FudoPrintDoctor
    Write-DoctorResult -Obj $final

    # Menu de acciones: permite volver a revisar o corregir sin cerrar y reabrir la app.
    if (-not $NoMenu -and (Test-IsInteractiveConsole)) {
        while ($true) {
            $op = Show-DoctorMenu
            if ($op -eq 'S') { break }
            if ($op -eq '?') { continue }
            $volverACorrer = Invoke-MenuAction -Op $op
            if ($volverACorrer) {
                Reset-RunState
                $final = Invoke-FudoPrintDoctor
                Write-DoctorResult -Obj $final
            }
        }
    }

    if (@($script:Errors).Count -gt 0)                                   { exit 3 }
    elseif ($final.diagnosis.resolved -and -not $final.diagnosis.needsEscalation) { exit 0 }
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
        timestamp     = (Get-Date).ToString('o')
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
}
