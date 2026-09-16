<#
.SYNOPSIS
    Embebe ui\fpd-ui.html dentro de FudoPrintDoctor.ps1.

.DESCRIPTION
    El motor se distribuye como UN archivo: el asesor copia el .cmd y el .ps1 a la PC del
    cliente y listo. La interfaz web tiene que viajar adentro del .ps1, no como un tercer
    archivo que alguien se olvide de copiar.

    Pero el .ps1 va SIN caracteres no ASCII (corre en el PowerShell 5.1 que trae Windows, en
    PCs con cualquier code page: una tilde guardada en UTF-8 y leida como cp437 rompe el
    parseo). El HTML si lleva acentos. Este script hace la conversion: cada caracter no ASCII
    sale como entidad HTML numerica, que el navegador renderiza igual.

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

$html = [System.IO.File]::ReadAllText($Ui, [System.Text.Encoding]::UTF8)

# El here-string @'...'@ termina en una linea que EMPIEZA con '@. Si el HTML tuviera una,
# el .ps1 quedaria partido al medio y el motor no parsearia: mejor cortar aca.
foreach ($ln in ($html -split "`r?`n")) {
    if ($ln.TrimStart() -eq "'@") { throw "La interfaz tiene una linea que cierra el here-string ('@). Reescribir esa linea." }
}

# ASCII: todo lo de arriba de 127 sale como entidad numerica.
$sb = New-Object System.Text.StringBuilder
$convertidos = 0
foreach ($ch in $html.ToCharArray()) {
    $code = [int][char]$ch
    if ($code -gt 127) { [void]$sb.Append('&#' + $code + ';'); $convertidos++ }
    else               { [void]$sb.Append($ch) }
}
$htmlAscii = $sb.ToString() -replace "`r`n", "`n"

$textoMotor = [System.IO.File]::ReadAllText($Motor, [System.Text.Encoding]::UTF8)
$iIni = $textoMotor.IndexOf($marcaIni)
$iFin = $textoMotor.IndexOf($marcaFin)
if ($iIni -lt 0 -or $iFin -lt 0 -or $iFin -lt $iIni) {
    throw "No encontre las marcas de la interfaz en el motor. Se esperaban '$marcaIni' y '$marcaFin'."
}

$bloque = $marcaIni + "`n" + '$script:UiHtml = @''' + "`n" + $htmlAscii.TrimEnd("`n") + "`n" + '''@' + "`n" + $marcaFin
$nuevo  = $textoMotor.Substring(0, $iIni) + $bloque + $textoMotor.Substring($iFin + $marcaFin.Length)

# CRLF y sin BOM, como todo el archivo.
$nuevo = ($nuevo -replace "`r`n", "`n") -replace "`n", "`r`n"
[System.IO.File]::WriteAllText($Motor, $nuevo, (New-Object System.Text.UTF8Encoding($false)))

# Control: despues de esto el motor no puede tener un solo caracter no ASCII.
$noAscii = 0
foreach ($ch in ([System.IO.File]::ReadAllText($Motor, [System.Text.Encoding]::UTF8)).ToCharArray()) {
    if ([int][char]$ch -gt 127) { $noAscii++ }
}

Write-Host ("  Interfaz embebida: {0:N0} caracteres, {1} convertidos a entidades." -f $htmlAscii.Length, $convertidos)
Write-Host ("  Caracteres no ASCII en el motor: {0}" -f $noAscii)
if ($noAscii -gt 0) { throw 'Quedaron caracteres no ASCII en el motor.' }
Write-Host '  OK. Correr el self-test antes de commitear.'
