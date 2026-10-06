<#
.SYNOPSIS
    Genera PrintDoctor.cmd (el launcher de Deli, en portugues) a partir de FudoPrintDoctor.cmd.

.DESCRIPTION
    En Brasil la marca es Deli: "Fudo" en portugues se lee como una mala palabra, y por eso la
    marca cambio alla. Los asesores de Deli hablan portugues, y lo que ve el cliente no puede
    decir "Fudo". El launcher de Deli es el mismo que el de Fudo con tres diferencias:
      - los textos que se muestran, en portugues (sin tildes: la consola de cmd no las respeta
        en todas las code pages);
      - el motor se guarda como PrintDoctor.ps1;
      - le pasa -Idioma pt-BR al motor, que hace el resto (ticket, nombres de cola, ventana).

    POR QUE SE GENERA Y NO SE COPIA A MANO. El launcher de Fudo carga casos reales en cada
    linea (la edicion rapida, el orden del sondeo, las descargas). Una copia mantenida a mano
    se queda atras en el primer arreglo. Asi, cada cambio va en FudoPrintDoctor.cmd y se corre
    esto. El self-test (S148) falla si PrintDoctor.cmd quedo desfasado.

    Si un texto nuevo del launcher de Fudo no esta en la tabla, el script NO genera nada y dice
    cual es: un texto en castellano con "Fudo" adentro no puede llegar al cliente de Brasil.

.EXAMPLE
    powershell -NoProfile -ExecutionPolicy Bypass -File .\tools\Generar-LauncherDeli.ps1
#>
[CmdletBinding()]
param(
    [string]$Origen,
    [string]$Destino,
    # Solo compara: sale con 1 si PrintDoctor.cmd no es lo que se generaria hoy.
    [switch]$Verificar
)

$ErrorActionPreference = 'Stop'

$raiz = Split-Path -Parent $MyInvocation.MyCommand.Path
$raiz = Split-Path -Parent $raiz
if (-not $Origen)  { $Origen  = Join-Path $raiz 'FudoPrintDoctor.cmd' }
if (-not $Destino) { $Destino = Join-Path $raiz 'PrintDoctor.cmd' }

function ConvertTo-LauncherDeli {
    param([string]$Texto)
    $nl = "`r`n"
    $cambios = @(
        ,@(('REM ================================================================' + $nl +
            'REM  FUDO PRINT DOCTOR - launcher' + $nl),
           ('REM ================================================================' + $nl +
            'REM  PRINT DOCTOR - launcher de Deli (Brasil)' + $nl +
            'REM  GENERADO por tools\Generar-LauncherDeli.ps1 desde FudoPrintDoctor.cmd:' + $nl +
            'REM  los cambios van alla, no aca. Mismo motor, con -Idioma pt-BR.' + $nl))
        ,@('title Fudo Print Doctor', 'title Print Doctor')
        ,@('set "FPD_MOTOR=%~dp0FudoPrintDoctor.ps1"', 'set "FPD_MOTOR=%~dp0PrintDoctor.ps1"')
        ,@('-File "%FPD_MOTOR%" -Ui web -NoNativaKitCheck', '-File "%FPD_MOTOR%" -Idioma pt-BR -Ui web -NoNativaKitCheck')
        ,@('echo  Pidiendo permisos de administrador...', 'echo  Pedindo permissao de administrador...')
        ,@('echo  Buscando la version publicada del motor...', 'echo  Procurando a versao publicada do motor...')
        ,@('echo  El motor que hay en esta carpeta no es la version publicada (%FPD_PUB%).', 'echo  O motor desta pasta nao e a versao publicada (%FPD_PUB%).')
        ,@('echo  Lo actualizo...', 'echo  Atualizando...')
        ,@('echo  OJO: no se pudo consultar la version publicada (esta PC puede no', 'echo  ATENCAO: nao foi possivel consultar a versao publicada (este PC')
        ,@('echo  tener internet). Se usa el motor que esta en la carpeta, que puede', 'echo  pode estar sem internet). Sera usado o motor desta pasta, que pode')
        ,@('echo  estar desactualizado.', 'echo  estar desatualizado.')
        ,@('echo  Descargando el motor...', 'echo  Baixando o motor...')
        ,@('echo   FUDO PRINT DOCTOR', 'echo   PRINT DOCTOR')
        ,@('echo   Va a revisar la cadena de impresion y reparar lo que pueda:', 'echo   Vai revisar a cadeia de impressao e corrigir o que puder:')
        ,@('echo     - servicio de cola de impresion (spooler)', 'echo     - servico de fila de impressao (spooler)')
        ,@('echo     - impresora en modo offline o pausada', 'echo     - impressora offline ou pausada')
        ,@('echo     - App Nativa de Fudo en cuarentena del antivirus', 'echo     - App Nativa em quarentena do antivirus')
        ,@('echo     - puerto USB cambiado', 'echo     - porta USB trocada')
        ,@('echo     - driver e instalacion de la impresora, si falta', 'echo     - driver e instalacao da impressora, se faltar')
        ,@('echo   Se abre sola una ventana con el diagnostico. Ahi vas a ver lo', 'echo   Uma janela com o diagnostico abre sozinha. Nela voce ve o que')
        ,@('echo   que va encontrando y ahi te va a preguntar lo que necesite.', 'echo   for sendo encontrado, e nela ele pergunta o que precisar.')
        ,@('echo   NO cierres esta ventana: el diagnostico corre aca.', 'echo   NAO feche esta janela: o diagnostico roda aqui.')
        ,@('echo   Si la ventana no abre, la direccion queda escrita aca abajo.', 'echo   Se a janela nao abrir, o endereco fica escrito aqui embaixo.')
        ,@('echo   La pantalla esta hecha para que la pueda mirar el cliente', 'echo   A tela foi feita para o cliente poder acompanhar')
        ,@('echo   mientras vos la usas.', 'echo   enquanto voce usa.')
        ,@('echo   Primero te pregunta como esta conectada la impresora: por cable', 'echo   Primeiro ele pergunta como a impressora esta conectada: por cabo')
        ,@('echo   a esta PC, por red, o las dos. Si no sabes, elegi las dos.', 'echo   neste PC, pela rede, ou as duas. Se nao souber, escolha as duas.')
        ,@('echo   Despues te pide el ID de la conversacion de Intercom: son los', 'echo   Depois ele pede o ID da conversa do Intercom: sao os')
        ,@('echo   15 numeros, y podes pegar la URL entera.', 'echo   15 numeros, e voce pode colar a URL inteira.')
        ,@('echo   Va a IMPRIMIR UN TICKET DE PRUEBA: avisale al cliente.', 'echo   Vai IMPRIMIR UM TICKET DE TESTE: avise o cliente.')
        ,@('echo   Despues te pregunta si salio el papel: es la unica forma de', 'echo   Depois ele pergunta se o papel saiu: e o unico jeito de')
        ,@('echo   saber si quedo resuelto, asi que conviene tener la impresora', 'echo   saber se ficou resolvido, entao e bom ter a impressora')
        ,@('echo   a la vista.', 'echo   a vista.')
        ,@('echo   Si hay comandas trabadas en la cola, primero te pregunta.', 'echo   Se houver pedidos travados na fila, ele pergunta antes.')
        ,@('echo   RESUELTO. Probar imprimir una comanda desde Fudo.', 'echo   RESOLVIDO. Testar imprimir um pedido pela Deli.')
        ,@('echo   Quedan cosas por hacer: mira QUE HACER AHORA aca arriba.', 'echo   Ainda ha coisas a fazer: veja o que fazer agora aqui em cima.')
        ,@('echo   El motor tuvo una falla interna: escalar con resultado.json.', 'echo   O motor teve uma falha interna: escalar com o resultado.json.')
        ,@('echo   El motor esta desactualizado y no diagnostico. Volve a abrir este archivo.', 'echo   O motor esta desatualizado e nao diagnosticou. Abra este arquivo de novo.')
        ,@('echo   Falta el ID de la conversacion: sin eso no se puede seguir el caso.', 'echo   Falta o ID da conversa: sem ele nao da para acompanhar o caso.')
        ,@('echo   Falta el instalador de la App Nativa. Copialo al lado de este archivo.', 'echo   Falta o instalador do App Nativa. Copie ao lado deste arquivo.')
        ,@('echo   Detalle completo: %FPD_JSON%', 'echo   Detalhe completo: %FPD_JSON%')
        ,@('echo   EL MOTOR NO LLEGO A DIAGNOSTICAR: no genero el resultado.', 'echo   O MOTOR NAO CHEGOU A DIAGNOSTICAR: nao gerou o resultado.')
        ,@('echo   NO tomar esto como resuelto. Si arriba hay un error en rojo,', 'echo   NAO considerar isto resolvido. Se aparecer um erro em vermelho')
        ,@('echo   sacale una captura y escribi en #fudo-print-doctor: es un bug', 'echo   aqui em cima, tire um print e escreva em #fudo-print-doctor: e um')
        ,@('echo   del motor, no del cliente.', 'echo   bug do motor, nao do cliente.')
        ,@('echo  Listo. Quedo solo resultado.json: adjuntalo al caso y borralo.', 'echo  Pronto. Ficou so o resultado.json: anexe ao caso e apague.')
        ,@('echo  Esta ventana se cierra sola en 15 segundos.', 'echo  Esta janela fecha sozinha em 15 segundos.')
        ,@('echo  Si queres leer algo de aca arriba, apreta N y queda abierta.', 'echo  Se quiser ler algo aqui em cima, aperte N e ela fica aberta.')
        ,@('echo   ESTA PC NO PUEDE CORRER EL DIAGNOSTICO', 'echo   ESTE PC NAO CONSEGUE RODAR O DIAGNOSTICO')
        ,@('echo   Tiene una version de PowerShell anterior a la 5, que es de', 'echo   Tem uma versao do PowerShell anterior a 5, que e do')
        ,@('echo   Windows 7 o anterior. El motor no puede funcionar ahi.', 'echo   Windows 7 ou anterior. O motor nao funciona nele.')
        ,@('echo   No se ejecuto nada. NO es un problema del cliente ni de la', 'echo   Nada foi executado. NAO e um problema do cliente nem da')
        ,@('echo   impresora: es esta PC.', 'echo   impressora: e este PC.')
        ,@('echo   Que hacer: resolver el caso a mano y dejar anotado en la', 'echo   O que fazer: resolver o caso manualmente e anotar na')
        ,@('echo   conversacion que la PC tiene Windows viejo.', 'echo   conversa que o PC tem Windows antigo.')
        ,@('echo   Le falta la administracion de impresoras de Windows', 'echo   Falta o gerenciamento de impressoras do Windows')
        ,@('echo   (Get-Printer), que existe desde Windows 8. El motor la necesita', 'echo   (Get-Printer), que existe desde o Windows 8. O motor precisa dele')
        ,@('echo   para ver las colas de impresion.', 'echo   para ver as filas de impressao.')
        ,@('echo   No se ejecuto nada. Resolver el caso a mano y dejarlo anotado.', 'echo   Nada foi executado. Resolver o caso manualmente e deixar anotado.')
        ,@('echo  No se pudo ejecutar PowerShell en esta PC, asi que el diagnostico', 'echo  Nao foi possivel executar o PowerShell neste PC, entao o diagnostico')
        ,@('echo  no puede correr. No se ejecuto nada.', 'echo  nao pode rodar. Nada foi executado.')
        ,@('echo  No se pudo descargar y no esta en la carpeta. Esta PC puede no', 'echo  Nao foi possivel baixar e nao esta na pasta. Este PC pode estar')
        ,@('echo  tener internet. Copiar tambien el archivo FudoPrintDoctor.ps1', 'echo  sem internet. Copie tambem o arquivo PrintDoctor.ps1')
        ,@('echo  junto a este .cmd y volver a intentar.', 'echo  junto com este .cmd e tente de novo.')
        ,@('echo  Lo que se descargo no es el motor (el repositorio puede estar', 'echo  O que foi baixado nao e o motor (o repositorio pode estar')
        ,@('echo  privado). Copiar el archivo FudoPrintDoctor.ps1 junto a este .cmd.', 'echo  privado). Copie o arquivo PrintDoctor.ps1 junto com este .cmd.')
    )
    $t = $Texto
    $faltan = @()
    foreach ($c in $cambios) {
        if (-not $t.Contains([string]$c[0])) { $faltan += [string]$c[0]; continue }
        $t = $t.Replace([string]$c[0], [string]$c[1])
    }
    if (@($faltan).Count -gt 0) {
        throw ("El launcher de Fudo cambio y estos textos ya no estan (actualizar la tabla):`r`n  " + (@($faltan) -join "`r`n  "))
    }
    # Lo que se muestra y sigue en castellano: un echo nuevo del launcher de Fudo que no esta en
    # la tabla. Los que dicen "Fudo" no pueden pasar; el canal de Slack se llama asi y queda.
    $sinTraducir = @()
    foreach ($ln in ($t -split "`r`n")) {
        if ($ln -match '^\s*(echo|title|if .* echo)\b' -and $ln -match '(?i)fudo(?!-print-doctor)') { $sinTraducir += $ln }
    }
    if (@($sinTraducir).Count -gt 0) {
        throw ("Hay textos para el cliente que dicen Fudo y no estan en la tabla:`r`n  " + (@($sinTraducir) -join "`r`n  "))
    }
    return $t
}

if (-not (Test-Path $Origen)) { throw "No esta el launcher de Fudo: $Origen" }
$texto = [System.IO.File]::ReadAllText($Origen, [System.Text.Encoding]::ASCII)
$deli  = ConvertTo-LauncherDeli -Texto $texto

if ($Verificar) {
    $actual = ''
    if (Test-Path $Destino) { $actual = [System.IO.File]::ReadAllText($Destino, [System.Text.Encoding]::ASCII) }
    if ($actual -ceq $deli) { Write-Host '  PrintDoctor.cmd esta al dia con FudoPrintDoctor.cmd.'; exit 0 }
    Write-Host '  PrintDoctor.cmd quedo desfasado: correr tools\Generar-LauncherDeli.ps1.' -ForegroundColor Yellow
    exit 1
}

foreach ($ch in $deli.ToCharArray()) { if ([int]$ch -gt 127) { throw 'El launcher generado tiene caracteres no ASCII.' } }
[System.IO.File]::WriteAllText($Destino, $deli, [System.Text.Encoding]::ASCII)
Write-Host ('  Generado: ' + $Destino)
Write-Host '  Para la copia interna con la URL de telemetria: tools\Configurar-Telemetria.cmd.'
