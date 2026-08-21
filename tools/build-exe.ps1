<#
.SYNOPSIS
    Empaqueta FudoPrintDoctor.ps1 como .exe con ps2exe. NO es el camino recomendado.

.DESCRIPTION
    ps2exe no compila: embebe el script en un host .NET. Sin firma digital, Defender, McAfee y
    SmartScreen suelen bloquear el resultado — que es justamente el problema que este motor
    diagnostica. Para uso normal preferir los launchers .cmd del repo.

    Si hay certificado de code signing, descomentar el bloque de firma y pasar -CertThumbprint.

.EXAMPLE
    .\tools\build-exe.ps1
#>
[CmdletBinding()]
param(
    [string]$Out = './dist/FudoPrintDoctor.exe',
    [string]$CertThumbprint = ''
)

$ErrorActionPreference = 'Stop'
$root = Split-Path -Parent $PSScriptRoot
$src  = Join-Path $root 'FudoPrintDoctor.ps1'
if (-not (Test-Path $src)) { throw "No encuentro $src" }

if (-not (Get-Module -ListAvailable -Name ps2exe)) {
    Write-Host 'Instalando ps2exe...'
    Install-Module ps2exe -Scope CurrentUser -Force -SkipPublisherCheck
}
Import-Module ps2exe

$outDir = Split-Path -Parent $Out
if ($outDir -and -not (Test-Path $outDir)) { New-Item -ItemType Directory -Path $outDir -Force | Out-Null }

Invoke-ps2exe -InputFile $src -OutputFile $Out `
    -title 'Fudo Print Doctor' -product 'Fudo Print Doctor' -company 'Fudo' `
    -description 'Diagnostico y reparacion del flujo de impresion de comandas' `
    -requireAdmin -noConsole:$false

Write-Host "OK -> $Out"

if ($CertThumbprint) {
    $cert = Get-ChildItem "Cert:\CurrentUser\My\$CertThumbprint" -ErrorAction Stop
    Set-AuthenticodeSignature -FilePath $Out -Certificate $cert -TimestampServer 'http://timestamp.digicert.com'
    Set-AuthenticodeSignature -FilePath $src -Certificate $cert -TimestampServer 'http://timestamp.digicert.com'
    Write-Host 'Firmado.'
} else {
    Write-Warning 'Sin firma digital: es muy probable que el antivirus y SmartScreen bloqueen el .exe.'
}
