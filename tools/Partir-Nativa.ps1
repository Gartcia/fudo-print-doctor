<#
.SYNOPSIS
    Parte el instalador de la App Nativa en pedazos que entren por TeamViewer.

.DESCRIPTION
    TeamViewer no transfiere archivos de mas de 25 MB, y el instalador de la Nativa pesa 58,7
    MB. Comprimirlo no sirve: ya viene comprimido.

    Bajarlo en el momento desde el panel de Fudo tampoco es una salida: cuando se esta
    diagnosticando la impresion, la red del local puede ser justamente parte del problema. El
    instalador tiene que viajar con el asesor.

    Este script lo parte en pedazos por debajo del limite y genera un Unir-Nativa.cmd que los
    vuelve a juntar en la PC del cliente. El armado VERIFICA el SHA256: un pedazo que llego
    cortado produce un ejecutable corrupto, y eso en la PC de un cliente es peor que no haber
    llevado nada.

.EXAMPLE
    powershell -NoProfile -ExecutionPolicy Bypass -File .\tools\Partir-Nativa.ps1
#>
[CmdletBinding()]
param(
    [string]$Instalador,
    [string]$Destino,
    [int]$LimiteMB = 20
)

$ErrorActionPreference = 'Stop'

$raiz = Split-Path -Parent $MyInvocation.MyCommand.Path
$raiz = Split-Path -Parent $raiz
if (-not $Instalador) {
    $kit = Join-Path $raiz 'tools\FudoPrintDoctor'
    $cand = @(Get-ChildItem -LiteralPath $kit -File -ErrorAction SilentlyContinue |
              Where-Object { $_.Name -match '(?i)fudo.*\.exe$' } | Sort-Object LastWriteTime -Descending)
    if (@($cand).Count -eq 0) { throw 'No encontre el instalador .exe de la Nativa en tools\FudoPrintDoctor' }
    $Instalador = @($cand)[0].FullName
}
if (-not $Destino) { $Destino = Join-Path $raiz 'tools\Nativa-partida' }

if (-not (Test-Path -LiteralPath $Instalador)) { throw "No existe: $Instalador" }

# Solo se parte un instalador firmado: si el asesor va a llevar 60 MB a la PC de un cliente,
# que sea algo que Windows pueda verificar.
$sig = Get-AuthenticodeSignature -LiteralPath $Instalador
if ([string]$sig.Status -ne 'Valid') { throw "El instalador no tiene firma valida ($($sig.Status)). No se parte." }
$firmante = ''
try { $firmante = [string]$sig.SignerCertificate.Subject.Split(',')[0] } catch {}

$nombre = [System.IO.Path]::GetFileName($Instalador)
$bytes  = (Get-Item -LiteralPath $Instalador).Length
$hash   = (Get-FileHash -LiteralPath $Instalador -Algorithm SHA256).Hash

Write-Host ''
Write-Host ("  Instalador : " + $nombre)
Write-Host ("  Tamano     : {0:N1} MB" -f ($bytes / 1MB))
Write-Host ("  Firmado por: " + $firmante)
Write-Host ("  SHA256     : " + $hash)
Write-Host ''

if (Test-Path -LiteralPath $Destino) { Remove-Item -LiteralPath $Destino -Recurse -Force }
New-Item -ItemType Directory -Path $Destino -Force | Out-Null

$pedazo = $LimiteMB * 1MB
$total  = [Math]::Ceiling($bytes / $pedazo)
$partes = @()

$fs = [System.IO.File]::OpenRead($Instalador)
try {
    $buf = New-Object byte[] 1MB
    for ($i = 1; $i -le $total; $i++) {
        $nomParte = ('nativa.part{0:d2}' -f $i)
        $ruta = Join-Path $Destino $nomParte
        $out = [System.IO.File]::Create($ruta)
        try {
            $escritos = 0
            while ($escritos -lt $pedazo) {
                $pedir = [Math]::Min($buf.Length, $pedazo - $escritos)
                $leidos = $fs.Read($buf, 0, $pedir)
                if ($leidos -le 0) { break }
                $out.Write($buf, 0, $leidos)
                $escritos += $leidos
            }
        } finally { $out.Close() }
        $partes += $nomParte
        Write-Host ("  {0}  {1,7:N1} MB" -f $nomParte, ((Get-Item -LiteralPath $ruta).Length / 1MB))
    }
} finally { $fs.Close() }

# El .cmd que las vuelve a unir, con el hash adentro.
$sb = New-Object System.Text.StringBuilder
[void]$sb.AppendLine('@echo off')
[void]$sb.AppendLine('REM ================================================================')
[void]$sb.AppendLine('REM  Une los pedazos del instalador de la App Nativa y verifica que')
[void]$sb.AppendLine('REM  haya llegado entero. Doble clic en la carpeta donde estan las')
[void]$sb.AppendLine('REM  partes. Existe porque TeamViewer no transfiere mas de 25 MB.')
[void]$sb.AppendLine('REM ================================================================')
[void]$sb.AppendLine('setlocal')
[void]$sb.AppendLine('cd /d "%~dp0"')
[void]$sb.AppendLine('title Unir instalador de la App Nativa')
[void]$sb.AppendLine('echo.')
[void]$sb.AppendLine('echo  Uniendo los pedazos...')
foreach ($p in $partes) {
    [void]$sb.AppendLine(('if not exist "' + $p + '" goto falta'))
}
[void]$sb.AppendLine(('copy /b ' + (($partes | ForEach-Object { '"' + $_ + '"' }) -join '+') + ' "' + $nombre + '" >nul'))
[void]$sb.AppendLine(('if not exist "' + $nombre + '" goto fallo'))
[void]$sb.AppendLine('echo  Verificando que haya llegado entero...')
[void]$sb.AppendLine(('powershell -NoProfile -ExecutionPolicy Bypass -Command "$h=(Get-FileHash -LiteralPath ''' + $nombre + ''' -Algorithm SHA256).Hash; if ($h -eq ''' + $hash + ''') { exit 0 } else { exit 1 }"'))
[void]$sb.AppendLine('if errorlevel 1 goto corrupto')
[void]$sb.AppendLine('echo.')
[void]$sb.AppendLine(('echo  LISTO: ' + $nombre))
[void]$sb.AppendLine('echo  Quedo al lado de este archivo. Copialo a la carpeta de FudoPrintDoctor.')
[void]$sb.AppendLine('echo.')
[void]$sb.AppendLine('del /q nativa.part* >nul 2>&1')
[void]$sb.AppendLine('pause')
[void]$sb.AppendLine('goto :eof')
[void]$sb.AppendLine(':falta')
[void]$sb.AppendLine('echo.')
[void]$sb.AppendLine(('echo  FALTAN PEDAZOS. Tienen que estar los ' + $partes.Count + ' archivos nativa.partNN'))
[void]$sb.AppendLine('echo  en esta misma carpeta antes de unirlos.')
[void]$sb.AppendLine('echo.')
[void]$sb.AppendLine('pause')
[void]$sb.AppendLine('goto :eof')
[void]$sb.AppendLine(':corrupto')
[void]$sb.AppendLine('echo.')
[void]$sb.AppendLine('echo  EL ARCHIVO NO LLEGO ENTERO: algun pedazo se corto en la transferencia.')
[void]$sb.AppendLine('echo  Se borra para que nadie lo instale. Volve a pasar los pedazos.')
[void]$sb.AppendLine(('del /q "' + $nombre + '" >nul 2>&1'))
[void]$sb.AppendLine('echo.')
[void]$sb.AppendLine('pause')
[void]$sb.AppendLine('goto :eof')
[void]$sb.AppendLine(':fallo')
[void]$sb.AppendLine('echo.')
[void]$sb.AppendLine('echo  No se pudo armar el archivo.')
[void]$sb.AppendLine('echo.')
[void]$sb.AppendLine('pause')

$unir = Join-Path $Destino 'Unir-Nativa.cmd'
[System.IO.File]::WriteAllText($unir, $sb.ToString(), (New-Object System.Text.UTF8Encoding($false)))

Write-Host ''
Write-Host ("  Unir-Nativa.cmd generado ({0} pedazos, verifica SHA256)" -f $partes.Count)
Write-Host ("  Carpeta: " + $Destino)
Write-Host ''
Write-Host '  En la PC del cliente: pasar los pedazos y el .cmd, doble clic al .cmd.'
