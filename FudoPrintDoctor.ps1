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
    [switch]$KeepTestPrinter,
    [string]$JsonOut,
    [switch]$Quiet,
    [switch]$Json,
    [switch]$SelfTest
)

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
$script:SchemaVersion = '1.3'
$script:JsonBegin    = '<<<FUDO_JSON_BEGIN>>>'
$script:JsonEnd      = '<<<FUDO_JSON_END>>>'
$script:AutoJsonPath = ''

# Conocido: marcas de impresoras termicas/POS (art. 16419361 + registro real de asesores)
$script:PosBrands = @('Bixolon','Epson','Citizen','Hasar','Sam4s','POS','Thermal','Generic','Generica',
    '3nStar','3nstar','XPrinter','Xprinter','Rongta','Gprinter','Nictom','Kretz','OCOM','Barpos','Solpos',
    'Jaltech','Sprt','Sewoo','Giant','5890','80c','TM-T','TM20','RPT','IT 0','Ser force','SerForce')

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
    try {
        return (& $Body)
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
        return $null
    }
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
        [bool]$Reversible = $true
    )
    if (-not $AutoFix) {
        return @{ applied = $false; note = "auto-fix deshabilitado: $Description" }
    }
    if ($DryRun) {
        Write-DoctorLog -Level 'INFO' -Message "DRY-RUN: aplicaria -> $Description"
        return @{ applied = $false; note = "dry-run: $Description" }
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
# LAYER 0b - App Nativa de Fudo vs Antivirus (CAUSA RAIZ #1 segun registro real)
# ~46% de los casos: la App Nativa queda bloqueada / en cuarentena por Defender o Avast.
# Estrategia: exclusiones quirurgicas (ruta + proceso) en vez de desactivar el antivirus.
# ---------------------------------------------------------------------------
function Find-FudoNativeInstall {
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
    if ($name -and ($name -notmatch '(?i)^(usb printing support|soporte de impresi|compatible usb|unknown|desconocid|dispositivo (compuesto|usb)|generic usb)')) { $model = $name }
    elseif ($inst -match '(?i)^USBPRINT\\([^\\]+)') { $model = ($Matches[1] -replace '_+', ' ').Trim() }
    if ($model -and $brand -and $model -match [regex]::Escape(($brand -split ' ')[0])) {
        $model = ($model -replace [regex]::Escape(($brand -split ' ')[0]), '').Trim(' -_')
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
    param($P)
    $probe = ''
    try { $probe = "{0} {1}" -f [string]$P.Name, [string]$P.DriverName } catch {}
    foreach ($b in $script:PosBrands) { if ($probe -match [regex]::Escape($b)) { return $true } }
    return $false
}

# ---------------------------------------------------------------------------
# LAYER 1a - INVENTARIO DE HARDWARE (Administrador de dispositivos + puertos)
# Se corre ANTES de elegir impresora: primero saber si hay fierro conectado.
# ---------------------------------------------------------------------------
function Get-UsbPrintDevices {
    <#
      Impresoras fisicas enumeradas por Windows (usbprint / clase Printer) con su puerto USB00x.
      Fuentes, en orden de confiabilidad:
        1) HKLM\SYSTEM\CurrentControlSet\Enum\USBPRINT -> Device Parameters\PortName (mapea device -> USB00x)
        2) Get-PnpDevice -Class Printer/USB (Win8+)
        3) Win32_PnPEntity (Service='usbprint' o PNPClass='Printer')
    #>
    $devices = @()

    # (1) Registro USBPRINT: es el unico lugar donde vive el mapeo device -> PortName
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
                    $devices += [ordered]@{
                        source     = 'registry.USBPRINT'
                        name       = $desc
                        instanceId = ('USBPRINT\' + $hw.PSChildName + '\' + $inst.PSChildName)
                        portName   = $portName
                        status     = 'enumerado'
                        problem    = 0
                    }
                }
            }
        }
    } catch {}

    # (2) PnP moderno
    try {
        $pnp = @(Get-PnpDevice -PresentOnly -ErrorAction Stop | Where-Object {
            ($_.Class -eq 'Printer') -or ($_.Class -eq 'USB' -and $_.FriendlyName -match '(?i)printer|impresora|POS|thermal')
        })
        foreach ($d in $pnp) {
            $devices += [ordered]@{
                source     = 'PnpDevice'
                name       = [string]$d.FriendlyName
                instanceId = [string]$d.InstanceId
                portName   = ''
                status     = [string]$d.Status
                problem    = $(try { [int]$d.ProblemCode } catch { 0 })
            }
        }
    } catch {
        # (3) Fallback WMI
        try {
            $wmiDev = @(Get-CimInstance Win32_PnPEntity -ErrorAction Stop | Where-Object {
                ($_.Service -eq 'usbprint') -or ($_.PNPClass -eq 'Printer')
            })
            foreach ($d in $wmiDev) {
                $devices += [ordered]@{
                    source     = 'Win32_PnPEntity'
                    name       = [string]$d.Name
                    instanceId = [string]$d.PNPDeviceID
                    portName   = ''
                    status     = [string]$d.Status
                    problem    = $(try { [int]$d.ConfigManagerErrorCode } catch { 0 })
                }
            }
        } catch {}
    }

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
    <# Dispositivos presentes sin driver (codigo 28) o con error: candidatos a instalar driver generico. #>
    $out = @()
    try {
        # Ojo: no traer TODOS los dispositivos desconocidos de la PC (ruido y falsa causa raiz).
        # Solo clase Printer, o desconocidos colgados de USB (tipico POS sin driver, codigo 28).
        $bad = @(Get-PnpDevice -PresentOnly -ErrorAction Stop | Where-Object {
            $_.Status -ne 'OK' -and (
                ($_.Class -eq 'Printer') -or
                ($_.FriendlyName -match '(?i)printer|impresora|POS|thermal|USB Printing') -or
                (($_.Class -eq 'Unknown' -or $_.Class -eq 'Other' -or -not $_.Class) -and ([string]$_.InstanceId -match '^USB'))
            )
        })
        foreach ($d in $bad) {
            $out += [ordered]@{
                name = [string]$d.FriendlyName; instanceId = [string]$d.InstanceId
                status = [string]$d.Status; problem = $(try { [int]$d.ProblemCode } catch { 0 }); class = [string]$d.Class
            }
        }
    } catch {
        try {
            $bad = @(Get-CimInstance Win32_PnPEntity -ErrorAction Stop | Where-Object { $_.ConfigManagerErrorCode -ne 0 })
            foreach ($d in $bad) {
                if ([string]$d.Name -match '(?i)printer|impresora|POS|thermal|desconocido|unknown') {
                    $out += [ordered]@{
                        name = [string]$d.Name; instanceId = [string]$d.PNPDeviceID
                        status = [string]$d.Status; problem = [int]$d.ConfigManagerErrorCode; class = [string]$d.PNPClass
                    }
                }
            }
        } catch {}
    }
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
    if (-not $drv) { $drv = Install-GenericTextDriver }
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
        }
    }
    $script:Diagnostics['printersConnected'] = $identified
    $script:Diagnostics['hwDevices']      = $devices
    $script:Diagnostics['hwProblemDevs']  = $problems
    $script:Diagnostics['printerPorts']   = @($ports | ForEach-Object { $_.name })
    $script:Diagnostics['usbPorts']       = $usbPorts
    $script:Diagnostics['livePorts']      = $devPorts
    $script:Diagnostics['hwDeviceCount']  = (@($devices).Count + @($problems).Count)

    # 1a.1 Hay una impresora fisica conectada?
    if (@($devices).Count -eq 0 -and @($problems).Count -eq 0) {
        Add-Check -Id 'hw.deviceConnected' -Layer 1 -Name 'Ninguna impresora fisica conectada (Administrador de dispositivos)' -Status 'fail' -RootCauseCandidate $true -Plane 'hardware' `
            -Evidence @{ usbPrintDevices = 0; usbPortsHuerfanos = $usbPorts } `
            -ArticleRef 'https://soporte.fu.do/es/articles/11730817' `
            -Recommendation ('Windows NO ve ninguna impresora conectada por USB. Antes de tocar software: 1) que la impresora este encendida (luz fija, no roja); 2) probar OTRO puerto USB de la PC, directo (sin hub); 3) probar otro cable USB; 4) hacer el self-test de la impresora (apagar, mantener FEED, encender) para confirmar que el fierro funciona. ' +
                             $(if (@($usbPorts).Count -gt 0) { "Ojo: existen puertos $($usbPorts -join ', ') en Windows pero son huerfanos (quedaron de una instalacion previa, no tienen device detras)." } else { '' }))
        return
    }

    $cant = @($identified).Count
    $listado = @($identified | ForEach-Object { $_.nombre + $(if ($_.puerto) { " ($($_.puerto))" } else { '' }) })
    Add-Check -Id 'hw.deviceConnected' -Layer 1 -Name ("Impresoras fisicas detectadas: $cant" + $(if ($cant -gt 0) { ' -> ' + ($listado -join ' | ') } else { '' })) -Status 'ok' -Plane 'hardware' `
        -Evidence @{ cantidad = $cant; impresoras = $identified; livePorts = $devPorts } `
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

    # --- Caso C: hay colas reales -> elegir la mejor candidata (POS > puerto fisico)
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
    $jobs = @()
    try { $jobs = @(Get-PrintJob -PrinterName $Printer.Name -ErrorAction Stop) } catch {}
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
        $rem = Invoke-Remediation -Description "Limpiar cola trabada ($(@($jobs).Count) trabajos)" -Type 'queue.purge' -Target $Printer.Name `
            -Before "$(@($jobs).Count) jobs" -After '0 jobs' -Reversible $false -Fix {
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
            -Recommendation 'Un trabajo trabado bloquea toda la cola: las comandas nuevas no salen hasta limpiarla.'
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
                    Set-Printer -Name $Printer.Name -PortName $cp -ErrorAction Stop
                    Start-Sleep -Milliseconds 500
                    if ([FudoRawPrinter]::SendBytes($Printer.Name, $ticket)) { $chosen = $cp; break }
                } catch {}
            }
            if ($null -eq $chosen) {
                try { Set-Printer -Name $Printer.Name -PortName $currentPort -ErrorAction SilentlyContinue } catch {}
                "ningun candidato imprimio; puerto revertido a $currentPort"
            } else {
                "puerto reasignado a $chosen (test HW OK)"
            }
        }
    $fixedOk = $rem.applied -and ($rem.note -match 'reasignado')
    Add-Check -Id 'conn.usb' -Layer 3 -Name 'Puerto USB desmapeado' -Status $(if($fixedOk){'fixed'}elseif($rem.applied){'warn'}else{'warn'}) -RootCauseCandidate $true `
        -Evidence @{ currentPort = $currentPort; candidates = $candidatePorts; livePorts = $livePorts; motivo = $reason } -ActionTaken $rem.note `
        -ArticleRef 'https://soporte.fu.do/es/articles/11730817' `
        -Recommendation 'Caso clasico: la impresora se reconecto a otro puerto USB y la cola apunta al viejo.'
}

function Test-Layer3-Network {
    param($Printer)
    $ip = $PrinterIp
    if (-not $ip -and $Printer) {
        $pn = [string]$Printer.PortName
        if ($pn -match '(\d{1,3}\.\d{1,3}\.\d{1,3}\.\d{1,3})') { $ip = $Matches[1] }
    }
    if (-not $ip) {
        Add-Check -Id 'conn.net' -Layer 3 -Name 'Conectividad de red a la impresora' -Status 'skipped' `
            -Evidence @{ note = 'sin IP conocida (pasar -PrinterIp o interfaz Ethernet en Fudo)' } `
            -ArticleRef 'https://soporte.fu.do/es/articles/11730816'
        return
    }
    $script:Diagnostics['printerIp'] = $ip

    $pingOk = $false
    try { $pingOk = Test-Connection -ComputerName $ip -Count 2 -Quiet -ErrorAction Stop } catch {}
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
        Add-Check -Id 'conn.net' -Layer 3 -Name "Conectividad a impresora de red ${ip}:${Port}" -Status 'ok' `
            -Evidence @{ ip = $ip; ping = $pingOk; port9100 = $true }
        return
    }

    # Puerto 9100 caido: posible IP cambiada por DHCP. Intentar descubrir el nuevo host con 9100 abierto en la /24.
    Write-DoctorLog -Level 'WARN' -Message "Impresora ${ip}:${Port} inalcanzable. Buscando IP alternativa en la subred..."
    $discovered = @()
    try {
        $prefix = ($ip -split '\.')[0..2] -join '.'
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
        $v = Test-IsVirtualPrinter $Printer
        if ($v.isVirtual) {
            Add-Check -Id 'hw.testprint' -Layer 4 -Name 'Prueba fisica de impresion' -Status 'skipped' -Plane 'hardware' `
                -Evidence @{ printer = [string]$Printer.Name; reason = [string]$v.reason } `
                -Recommendation "No se prueba sobre '$($Printer.Name)': es una impresora virtual y daria un falso OK de hardware."
            return
        }
        try {
            Initialize-RawPrinterHelper
            $bytes = [System.Text.Encoding]::GetEncoding(437).GetBytes((Get-EscPosTestTicket -Caption 'FUDO HW TEST'))
            $ok = [FudoRawPrinter]::SendBytes($Printer.Name, $bytes)
            Add-Check -Id 'hw.testprint' -Layer 4 -Name 'Prueba fisica ESC/POS por USB (RAW)' -Status $(if($ok){'ok'}else{'fail'}) -RootCauseCandidate (-not $ok) `
                -Plane 'hardware' -Evidence @{ printer = $Printer.Name; sent = $ok } `
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
    # Categorizacion para telemetria / Contact Rate por causa
    $rc = [string]$Diag.rootCause
    switch -Regex ($rc) {
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

    # --- impresoras fisicas detectadas
    $conn = @()
    if ($script:Diagnostics.Contains('printersConnected')) { $conn = @($script:Diagnostics['printersConnected']) }
    Add-Line ''
    Add-Line ("  IMPRESORAS CONECTADAS: " + @($conn).Count)
    if (@($conn).Count -eq 0) {
        Add-Line '    (ninguna: Windows no ve hardware de impresion conectado)'
    } else {
        $n = 0
        foreach ($c in $conn) {
            $n++
            $cola = [string]$c.colaWindows
            $where = $(if ($cola) { "instalada como '$cola'" } else { 'SIN cola en Windows' })
            Add-Line ("    $n. " + [string]$c.nombre + $(if ($c.puerto) { "  [$($c.puerto)]" } else { '' }) + "  -> $where")
            if ($c.driverSugerido -eq 'oem_recomendado') {
                Add-Line ("       driver: tiene driver propio de $($c.marca) (opcional); el generico de texto alcanza")
            } elseif ($c.driverSugerido -eq 'oem_instalado') {
                Add-Line ("       driver: usa el de $($c.marca) ya instalado ($($c.driverNombre))")
            } elseif ($c.driverSugerido -eq 'generico') {
                Add-Line ('       driver: generico de texto (Generic / Text Only)')
            }
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
    foreach ($a in $areas) {
        $st = Get-AreaStatus -Ids $a.ids
        if ($st -eq '-' -and $a.t -eq 'Motor (fallas internas)') { continue }
        $dots = '.' * [Math]::Max(3, (30 - ([string]$a.t).Length))
        Add-Line ("    " + $a.t + ' ' + $dots + ' ' + $st)
    }

    # --- resultado
    $conf = switch ([string]$Diag.confidence) { 'high' { 'alta' } 'medium' { 'media' } default { 'baja' } }
    Add-Line ''
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
        if ($PSBoundParameters.ContainsKey('KeepTestPrinter') -and -not $KeepTestPrinter) {
            foreach ($n in $names) { try { Remove-Printer -Name $n -ErrorAction SilentlyContinue } catch {} }
            Add-Check -Id 'printer.testCleanup' -Layer 1 -Name 'Cola de prueba eliminada' -Status 'ok' -Evidence @{ removed = $names }
        } else {
            Add-Check -Id 'printer.testCleanup' -Layer 1 -Name 'Cola de prueba conservada' -Status 'warn' -Plane 'os' `
                -Evidence @{ kept = $names } `
                -Recommendation ("Queda instalada la cola de prueba " + ($names -join ', ') + ". Borrarla cuando se instale la definitiva: Remove-Printer -Name '" + (@($names)[0]) + "'")
        }
    }

    $diag = Resolve-Diagnosis
    $durationMs = [int]((Get-Date) - $script:StartTime).TotalMilliseconds
    $category = Get-Category -Diag $diag

    $result = [ordered]@{
        schemaVersion = $script:SchemaVersion
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
        hardware      = [ordered]@{
            devicesConnected = $(if ($script:Diagnostics.Contains('hwDevices')) { @($script:Diagnostics['hwDevices']) } else { @() })
            problemDevices   = $(if ($script:Diagnostics.Contains('hwProblemDevs')) { @($script:Diagnostics['hwProblemDevs']) } else { @() })
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

    Write-Host ""
    Write-Host ("SELF-TEST: {0} PASS / {1} FAIL" -f $script:__p, $script:__f)
    if ($script:__f -gt 0) { exit 4 }
}

# ---------------------------------------------------------------------------
# CONTRATO DE SALIDA (para el agente que corre el script)
#   stdout : SOLO el JSON, delimitado por <<<FUDO_JSON_BEGIN>>> / <<<FUDO_JSON_END>>>
#   stderr : resumen humano (es-AR) y avisos. Usar -Quiet para silenciarlo.
#   exit   : 0 = resuelto | 2 = requiere escalamiento | 3 = falla del motor | 4 = self-test fallido
# ---------------------------------------------------------------------------
function Write-DoctorResult {
    param($Obj)
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
    # Consola interactiva: mostramos SOLO el resumen y dejamos el JSON en un archivo.
    # Salida redirigida (agente) o -Json: JSON delimitado por stdout.
    $redirected = $true
    try { $redirected = [Console]::IsOutputRedirected } catch {}
    $emitJson = ($Json -or $redirected)

    if (-not $emitJson -and -not $JsonOut) {
        try {
            $auto = Join-Path $env:TEMP ("FudoPrintDoctor-" + (Get-Date).ToString('yyyyMMdd-HHmmss') + ".json")
            $json | Out-File -FilePath $auto -Encoding UTF8
            $script:AutoJsonPath = $auto
        } catch {}
    }

    if (-not $Quiet) {
        $hs = $null
        try { $hs = [string]$Obj.humanSummary } catch {}
        if ($hs) { Write-HumanReport -Text $hs }
        if (-not $emitJson) {
            $where = $(if ($JsonOut) { $JsonOut } elseif ($script:AutoJsonPath) { $script:AutoJsonPath } else { '' })
            if ($where) { Write-HumanReport -Text ("  JSON completo: $where`r`n  (para el agente: agregar -Json o redirigir la salida)`r`n") }
        }
    }

    if ($emitJson) {
        Write-Output $script:JsonBegin
        Write-Output $json
        Write-Output $script:JsonEnd
    }
}

try {
    if ($SelfTest) { Invoke-SelfTest; return }

    $final = Invoke-FudoPrintDoctor
    Write-DoctorResult -Obj $final

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
