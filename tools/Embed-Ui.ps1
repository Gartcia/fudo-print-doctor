<#
.SYNOPSIS
    Embebe ui\fpd-ui.html dentro de FudoPrintDoctor.ps1.

.DESCRIPTION
    El motor se distribuye como UN archivo: el asesor copia el .cmd y el .ps1 a la PC del
    cliente y listo. La interfaz web tiene que viajar adentro del .ps1, no como un tercer
    archivo que alguien se olvide de copiar.

    Pero el .ps1 va SIN caracteres no ASCII (corre en el PowerShell 5.1 que trae Windows, en
    PCs con cualquier code page: una tilde guardada en UTF-8 y leida como cp437 rompe el
    parseo). El HTML si lleva acentos.

    POR QUE BASE64. El primer intento convertia cada caracter no ASCII a entidad HTML
    (&#243;). Funciona en el MARCADO, pero no adentro de una cadena de JavaScript: la pagina
    mostraba 'No se modific&#243; nada' escrito tal cual, y los caracteres de dibujo del panel
    de progreso salian igual de rotos. Base64 es ASCII puro y no toca el contenido, asi que
    sirve para el HTML, el CSS y el JS por igual. El motor lo decodifica en Get-UiHtml.

    Correr despues de tocar ui\fpd-ui.html, y antes del self-test.

.EXAMPLE
    powershell -NoProfile -ExecutionPolicy Bypass -File .\tools\Embed-Ui.ps1
#>
[CmdletBinding()]
param(
    [string]$Ui,
    [string]$Motor
)

$ErrorActionPreference = 'Stop'

# Los defaults se resuelven aca y no en el param: en Windows PowerShell 5.1 $PSScriptRoot
# todavia no esta poblado cuando se evaluan los valores por defecto de los parametros.
$raiz = Split-Path -Parent $MyInvocation.MyCommand.Path
$raiz = Split-Path -Parent $raiz
if (-not $Ui)    { $Ui    = Join-Path $raiz 'ui\fpd-ui.html' }
if (-not $Motor) { $Motor = Join-Path $raiz 'FudoPrintDoctor.ps1' }

$marcaIni = '# === UI HTML INICIO ==='
$marcaFin = '# === UI HTML FIN ==='

if (-not (Test-Path $Ui))    { throw "No esta la interfaz: $Ui" }
if (-not (Test-Path $Motor)) { throw "No esta el motor: $Motor" }

$bytes = [System.IO.File]::ReadAllBytes($Ui)
$b64   = [Convert]::ToBase64String($bytes)

# En lineas de 120: un here-string con una sola linea de 46.000 caracteres es ilegible en el
# diff y algunos editores lo parten solos. Get-UiHtml saca los saltos antes de decodificar.
$sb = New-Object System.Text.StringBuilder
for ($i = 0; $i -lt $b64.Length; $i += 120) {
    $largo = [Math]::Min(120, $b64.Length - $i)
    [void]$sb.AppendLine($b64.Substring($i, $largo))
}
$b64Lineas = $sb.ToString().TrimEnd("`r", "`n")

$textoMotor = [System.IO.File]::ReadAllText($Motor, [System.Text.Encoding]::UTF8)
$iIni = $textoMotor.IndexOf($marcaIni)
$iFin = $textoMotor.IndexOf($marcaFin)
if ($iIni -lt 0 -or $iFin -lt 0 -or $iFin -lt $iIni) {
    throw "No encontre las marcas de la interfaz en el motor. Se esperaban '$marcaIni' y '$marcaFin'."
}

$bloque = $marcaIni + "`n" + '$script:UiHtmlB64 = @''' + "`n" +
          (($b64Lineas -replace "`r`n", "`n")) + "`n" + '''@' + "`n" + $marcaFin
$nuevo  = $textoMotor.Substring(0, $iIni) + $bloque + $textoMotor.Substring($iFin + $marcaFin.Length)

# CRLF y sin BOM, como todo el archivo.
$nuevo = ($nuevo -replace "`r`n", "`n") -replace "`n", "`r`n"
[System.IO.File]::WriteAllText($Motor, $nuevo, (New-Object System.Text.UTF8Encoding($false)))

# Controles: el motor no puede tener un solo caracter no ASCII, y lo embebido tiene que
# volver a ser EXACTAMENTE el archivo original.
$texto = [System.IO.File]::ReadAllText($Motor, [System.Text.Encoding]::UTF8)
$noAscii = 0
foreach ($ch in $texto.ToCharArray()) { if ([int][char]$ch -gt 127) { $noAscii++ } }
if ($noAscii -gt 0) { throw "Quedaron $noAscii caracteres no ASCII en el motor." }

$vuelta = [Convert]::FromBase64String(($b64Lineas -replace '\s', ''))
if ($vuelta.Length -ne $bytes.Length) { throw 'El ida y vuelta de base64 no da el mismo tamano.' }
for ($i = 0; $i -lt $bytes.Length; $i++) {
    if ($vuelta[$i] -ne $bytes[$i]) { throw "El ida y vuelta de base64 difiere en el byte $i." }
}

Write-Host ("  Interfaz embebida: {0:N0} bytes -> {1:N0} de base64." -f $bytes.Length, $b64.Length)
Write-Host '  Ida y vuelta verificada byte por byte. Cero caracteres no ASCII en el motor.'
Write-Host '  OK. Correr el self-test antes de commitear.'
