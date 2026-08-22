# Fudo Print Doctor

Motor de diagnóstico y reparación automática del flujo de impresión de comandas en PCs Windows.
Corre en la máquina del cliente (por la herramienta de acceso remoto del asesor o invocado por
un agente), recorre la cadena de impresión por capas, identifica la causa raíz y auto-resuelve
los casos seguros. Lo que no puede resolver solo, lo devuelve como próximos pasos accionables.

- **Un solo archivo**: `FudoPrintDoctor.ps1`. Sin dependencias, sin instalación.
- **Compatible** con Windows PowerShell 5.1 (el que ya viene en Windows) y PowerShell 7+.
- **Dos salidas**: resumen corto para humanos en pantalla, JSON completo para el agente.

## Descargar

Sin instalar nada, sin cuenta de GitHub:

- **Última versión (ZIP)**: [Code → Download ZIP](https://github.com/Gartcia/fudo-print-doctor/archive/refs/heads/main.zip)
- **Mantenerlo al día**: guardá `Actualizar-FudoPrintDoctor.cmd` en una carpeta y hacé doble clic
  cuando quieras la versión nueva. Baja el motor y el launcher, y te dice qué versión quedó.

El script **avisa** solo si está corriendo una versión vieja, y ofrece la opción `A` del menú para
actualizarse en el momento. `-CheckUpdate` compara contra la publicada y termina; `-NoUpdateCheck`
desactiva el chequeo.

**Por qué no se actualiza solo**: corre en la PC de un cliente y no está firmado digitalmente. Una
actualización automática propagaría cualquier bug —o cualquier cambio malicioso en el repo— a todos
los locales sin que nadie lo revise. Avisar y dejar la decisión a una persona cuesta un clic y evita
convertir el repo en un canal de ejecución remota. La opción `A` valida lo que descarga (tamaño,
firma y versión legible) y guarda un `.bak` antes de reemplazar.

Para trabajar en la PC de un cliente, copiale **dos archivos**: `FudoPrintDoctor.cmd` y
`FudoPrintDoctor.ps1`. Si solo copiaste el `.cmd` y esa PC tiene internet, él baja el `.ps1` solo.

## Uso rápido (asesores)

Copiar la carpeta a la PC del cliente y **doble clic en `FudoPrintDoctor.cmd`**. Eso es todo.

- Se eleva a administrador solo.
- Muestra qué va a hacer y espera un Enter antes de tocar nada.
- **Muestra el progreso en vivo**: una línea por etapa con `[n/9]`, el resultado y cuánto tardó,
  y el detalle de lo que está haciendo mientras corre (buscando la Nativa, consultando el
  antivirus, escaneando la subred, enviando el ticket…).
- Diagnostica y repara en la misma corrida. No hace falta un paso previo de diagnóstico.
- Lo único que no se puede deshacer —limpiar la cola de impresión, que descarta las comandas
  pendientes— **te lo pregunta** antes de hacerlo.
- Deja `resultado.json` al lado del script para adjuntar al caso.

Lo que se ve en pantalla:

```
==============================================================================
  FUDO PRINT DOCTOR   v1.3   PC: CAJA-01   Caso: IC-99887
  Modo: diagnostico + reparacion   Interfaz: USB
==============================================================================

  IMPRESORAS CONECTADAS: 2
    1. Epson TM-T20III  [USB001]  -> instalada como 'TM-T20III'
       driver: usa el de Epson ya instalado (EPSON TM-T20III ReceiptE4)
    2. Impresora generica [VID_0416]  [USB002]  -> SIN cola en Windows
       driver: generico de texto (Generic / Text Only)

  CHEQUEOS
    Windows / spooler ............. OK
    App Nativa + antivirus ........ REVISAR
    Hardware conectado ............ OK
    Instalada en Windows .......... REPARADO
    Cola de trabajos .............. OK
    Conexion USB / red ............ OK
    Prueba de impresion ........... OK
    Configuracion de Fudo ......... REVISAR

  RESULTADO: RESUELTO   (confianza alta)
  CAUSA: Puerto USB desmapeado
  SE ARREGLO: Puerto USB desmapeado

  QUE HACER AHORA
    1. [cliente] Excluir la App Nativa de Fudo en McAfee...
    2. [asesor] Verificar en la web app de Fudo: impresora registrada...
       ver: https://soporte.fu.do/es/articles/11730815

  Detalle: 18 chequeos con evidencia en el JSON
==============================================================================
```

## Qué revisa, en orden

| Capa | Qué mira |
|---|---|
| 0 | Windows, permisos de administrador, servicio Spooler |
| 0b | App Nativa de Fudo instalada y corriendo; Defender/antivirus de terceros |
| **1a** | **Hardware**: qué impresoras hay físicamente conectadas, en qué puerto, con o sin driver |
| 1 | Colas de Windows: descarta virtuales, **evalúa todas** y diagnostica la que falla, instala driver si falta |
| 2 | Cola de trabajos trabada |
| 3 | Puerto USB desmapeado / IP de la impresora Ethernet |
| 4 | Prueba física ESC/POS contra el hardware (aísla hardware vs configuración) |
| 5 | Configuración de Fudo: impresora registrada, cocina/área, categorías, salas |

### Detección de hardware (capa 1a)

Primero decide **qué dispositivos USB son realmente impresoras** (`Test-IsPrinterDevice`), con las
señales ordenadas por certeza:

| Certeza | Señal |
|---|---|
| alta | `InstanceId` empieza con `USBPRINT\` (interfaz que crea `usbprint.sys`) |
| alta | clase de dispositivo `Printer`, o driver `usbprint` |
| alta | `CompatibleID` contiene `USB\Class_07` — clase USB 07h = Printer, del estándar USB |
| media | VID de un fabricante de impresoras (Epson `04B8`, Bixolon `1504`, Star `0519`, Citizen `2730`, Zebra `0A5F`…) |
| baja | el nombre menciona impresora / térmica / POS / comandera / modelos típicos (`XP-80C`, `SRP-350`, `5890`) |

Mouse, teclados, hubs, `USB Composite Device`, audio, cámaras y almacenamiento se descartan y
quedan auditables en `hardware.usbDevicesRejected` con el motivo. Cuando la certeza no es alta, el
resumen lo dice para que el asesor confirme que esa es la comandera.

**Presente vs. histórico.** El registro `Enum\USBPRINT` guarda toda impresora que estuvo
conectada alguna vez, así que se cruza contra los dispositivos realmente presentes
(`Win32_PnPEntity` / `Get-PnpDevice -PresentOnly`). Una impresora desenchufada aparece como
**DESCONECTADA**, con el puerto donde estaba, en vez de figurar como conectada. Si la presencia no
se puede verificar, el motor no afirma que esté desconectada.

Cuando la cola apunta a un puerto sin dispositivo, tampoco se "repara" el offline —que es
consecuencia, no causa— ni se corre la prueba física, porque un ticket enviado a un puerto sin
hardware se encola y devolvería un falso OK.

Después enumera las impresoras físicas con tres fuentes en cascada:

1. `HKLM\SYSTEM\CurrentControlSet\Enum\USBPRINT` → `Device Parameters\PortName`.
   Es el único lugar donde vive el mapeo **device → USB00x**.
2. `Win32_PnPEntity` en una sola query (trae `CompatibleID`, `Service`, clase y estado).
3. `Get-PnpDevice` como fallback.

Con eso distingue tres cosas que a ojo se confunden: **puertos USB00x huérfanos** (restos de
instalaciones viejas, sin nada detrás), **device presente sin driver** (código 28 del
Administrador de dispositivos) y **device presente sin cola de impresión**.

### Varias impresoras en el mismo local

Un local típico tiene caja y cocina. El motor evalúa **todas** las colas reales —puerto, offline,
pausada, trabajos en cola, si el puerto tiene hardware presente— les asigna un puntaje de
severidad y diagnostica **la que está fallando**, no la primera que encuentra. Las sanas se listan
como "funcionando — no se toca" y no se les aplica ninguna reparación.

```
  IMPRESORAS INSTALADAS EN WINDOWS: 2
  >> CAJA  [USB003]  NO IMPRIME
         - 1440 trabajos encolados (el mas viejo del 20/08 20:17)
         - el puerto USB003 no tiene ningun dispositivo conectado
         - marcada como sin conexion (offline)
     COCINA  [USB001]  funcionando -- no se toca
```

### Reconexión guiada del USB

El caso más común de "estaba instalada y dejó de imprimir" se resuelve desenchufando y volviendo a
enchufar el cable USB: Windows re-enumera el dispositivo y le asigna un puerto. El motor acompaña
esa secuencia: espera la reconexión (hasta `-ReconnectTimeoutSec`, 120 s por defecto), detecta el
puerto nuevo, apunta la cola ahí, manda un ticket de prueba y —si la cola quedó rota— la recrea.

El reemplazo de una cola es seguro: primero crea una cola temporal y **comprueba que imprima**, y
solo entonces borra la vieja y renombra la nueva **con el mismo nombre**, porque Fudo encuentra la
impresora por nombre. Nunca deja al cliente sin cola.

### Impresoras virtuales

Print to PDF, XPS, OneNote, Fax, Adobe PDF, PDF24, CutePDF, PDFCreator y compañía se descartan
por nombre, driver y puerto. Nunca son objetivo de diagnóstico y la prueba física no corre sobre
ellas: un ticket "impreso" en Print to PDF da un falso "el hardware imprime OK".

### Genérico vs driver del fabricante

Por cada impresora detectada decide qué driver corresponde:

- **`oem_instalado`**: la marca tiene driver propio y ya está en Windows → lo usa.
- **`oem_recomendado`**: Epson, Bixolon, Star, Citizen, Zebra, Custom, Sam4s, Sewoo, Posiflex,
  Hasar. Para comandas ESC/POS el genérico suele alcanzar; el oficial se justifica si el modelo
  necesita corte automático o si el genérico falla.
- **`generico`**: genéricas y desconocidas (XPrinter, 3nStar, Rongta y similares) → el inbox
  `Generic / Text Only` ("Genérico / Solo texto") es el correcto.

Si hay hardware conectado sin cola, el motor instala el driver que corresponda y crea una cola
`FUDO-TEST-<puerto>` para poder hacer la prueba física. Queda instalada y se reporta con el
comando de limpieza; `-KeepTestPrinter:$false` la borra al final.

## Qué repara y qué pregunta

Cada reparación pasa por el mismo envoltorio, que respeta `-DryRun` / `-AutoFix`, registra
antes/después en `actionsApplied[]` y declara si es reversible.

| Reparación | Reversible | Pregunta |
|---|---|---|
| Iniciar/reiniciar el Spooler | sí | no |
| Sacar de offline / reanudar pausada | sí | no |
| Restaurar la Nativa de cuarentena + exclusiones de Defender | sí | no |
| Reasignar el puerto USB (revierte si ninguno imprime) | sí | no |
| Instalar driver + cola `FUDO-TEST-<puerto>` | sí (`Remove-Printer`) | no |
| **Limpiar la cola de impresión** | **no** — se pierden las comandas pendientes | **sí** |

La prueba física verifica además que el ticket **haya salido de la cola**: `WritePrinter` OK solo
significa que el spooler lo aceptó, no que el papel salió. Si el trabajo queda encolado, el
resultado es "la impresora no está respondiendo" y no un OK de hardware.

La única pregunta es la última, y solo cuando hay una cola trabada. Si el script corre sin humano
(agente, `-Quiet`, `-Json`, salida redirigida) no la aplica: la deja en `nextActions` con el
comando exacto para hacerla. Se puede decidir de antemano con `-AllowQueuePurge $true` / `$false`.

No se automatiza nunca: desactivar el antivirus (solo exclusiones de ruta y proceso), tocar
antivirus de terceros como McAfee o Avast, ni cambiar la configuración de Fudo.

## Menú de acciones

Al terminar el diagnóstico, en consola interactiva aparece un menú para seguir trabajando sin
cerrar y reabrir la app. Las letras son estables (siempre la misma tecla para lo mismo):

```
   [R]  Volver a revisar todo
   [U]  Esperar a que conectes/desconectes el USB y revisar de nuevo
   [I]  Instalar la impresora conectada en USB002 (driver de texto generico)
   [L]  Limpiar la cola de 'CAJA' (1440 trabajos)
   [N]  Buscar impresoras en la red (por IP)
   [P]  Instalar una de las impresoras de red encontradas
   [F]  Instalar / reparar la App Nativa de Fudo
   [T]  Imprimir un ticket de prueba
   [D]  Ver el detalle completo de los chequeos
   [J]  Guardar el JSON en un archivo
   [S]  Salir
```

Las opciones aparecen según lo que se encontró: `U` solo si hay una impresora desconectada, `L`
solo si hay una cola con trabajos, `P` solo después de encontrar impresoras por IP. Después de cada
acción que cambia algo, el diagnóstico se vuelve a correr solo. `-NoMenu` lo desactiva.

## Impresoras de red (Ethernet)

Cuando no hay IP conocida, el motor barre la subred local buscando el puerto de impresión y, en cada
hallazgo, confirma si **responde como impresora**: le manda `DLE EOT 1` (pedido de estado en tiempo
real) y una térmica contesta un byte. Así distingue una comandera de cualquier otro equipo que tenga
el 9100 abierto.

Reporta cuántas encontró, en qué IPs, cuáles **ya tienen** una cola de Windows apuntando ahí, y si
no encuentra nada lo dice explícitamente con los pasos para leer la IP real de la impresora
(self-test: apagar, mantener FEED, encender).

**Dos caminos en Fudo, y conviene saber cuál se va a usar antes de instalar nada:**

- **Directo Ethernet**: Fudo imprime por socket a la IP y **no usa ninguna cola de Windows**. Si en
  Fudo solo aparece el campo de IP, es este camino: no hay que instalar nada, alcanza con cargar la
  IP y el puerto 9100.
- **Impresora del sistema operativo**: Fudo imprime a través de una cola de Windows, elegida por
  nombre. Acá sí hay que instalarla, y para eso está la opción `P` del menú o
  `-PrinterIp <ip> -InstallNetworkPrinter`: crea el puerto TCP/IP y la cola con driver de texto
  genérico, con el nombre que elijas (`-NewPrinterName`), y manda un ticket de prueba.

El motor reporta si hay una **cola de Windows apuntando a esa IP**, que es un dato distinto de "está
configurada en Fudo": eso último no se puede saber desde la PC.

## Telemetría (opcional)

Para no depender de que el asesor guarde el JSON: con `-TelemetryUrl` (o fijando
`$script:TelemetryUrl` en el script, que es lo práctico para todo el equipo) cada corrida hace un
POST con un resumen del resultado. Es silencioso: si falla, no molesta ni corta el diagnóstico.

Receptor listo para usar en [`tools/telemetria-appscript.gs`](tools/telemetria-appscript.gs) (Google
Sheets + Apps Script), con los pasos en [`docs/telemetria.md`](docs/telemetria.md). La URL no va en
el código: se pone en un archivo `telemetria.txt` al lado del script. `-TestTelemetry` manda una fila
de prueba para verificar la configuración.

Además del resultado del diagnóstico viaja el **contexto de la PC**, que el motor recolecta sin
preguntarle nada al cliente:

| Dato | De dónde sale |
|---|---|
| Sistema operativo, build, arquitectura | `Win32_OperatingSystem` |
| Versión de PowerShell | `$PSVersionTable` |
| Versión de Chrome y de Edge | `VersionInfo` del ejecutable, o el registro de Google Update |
| Versión de la App Nativa de Fudo | registro de desinstalación |
| País, cultura, zona horaria | `RegionInfo` / `Get-TimeZone` (local, sin geolocalizar por IP) |
| Conexión de la PC: cable o wifi | `Get-NetAdapter` |
| Cantidad de colas y de impresoras físicas | inventario de las capas 1 y 1a |
| A qué cola le manda Fudo | historial del spooler (ver abajo) |

`-TelemetryFull` manda el JSON completo (que incluye rutas): solo para depurar un caso puntual.

## ¿A qué impresora le manda Fudo?

Desde la PC no hay acceso a la configuración de Fudo, pero sí a una evidencia muy buena: el log del
spooler de Windows (`Microsoft-Windows-PrintService/Operational`, evento 307) registra cada trabajo
impreso con su cola y el nombre del documento. Los trabajos de la App Nativa se llaman
`node print job`, así que se puede decir **qué cola recibió comandas de Fudo y cuándo fue la
última**.

Ese log viene **deshabilitado** de fábrica en Windows. Si está apagado, el motor lo habilita
(reparación reversible) y avisa que a partir de la próxima corrida va a poder responder esa
pregunta. Si está habilitado y ninguna cola recibió trabajos de la Nativa, eso apunta a que el
problema está en la configuración de Fudo y no en Windows.

Esto **no** reemplaza consultar la API de Fudo: dice a dónde llegan los trabajos, no qué cocina o
área tiene asignada cada impresora.

## App Nativa de Fudo

Dos formas, y la primera es la recomendada porque evita que el cliente descargue nada (y que el
antivirus borre la descarga a mitad de camino):

1. **Instalador que ya está en la PC**: si el asesor copió el `.exe` junto al script, el motor lo
   encuentra solo (también busca en Descargas y Escritorio). O se indica con `-NativeInstallerPath`.
   `-NativeInstallerArgs` permite pasarle flags de instalación silenciosa.
2. **Descarga**: con `-NativeInstallerUrl`.

En los dos casos agrega **primero** las exclusiones de antivirus (carpeta del instalador, `%TEMP%`,
`%LOCALAPPDATA%\Fudo`, `%LOCALAPPDATA%\Programs` y el proceso), después ejecuta y verifica que la
Nativa quede corriendo.

## Uso desde un agente

```powershell
powershell -NoProfile -ExecutionPolicy Bypass -File .\FudoPrintDoctor.ps1 -Json -CaseId "IC-12345" -ClientId "local-987"
```

Variantes útiles: `-DryRun` (no toca nada), `-AllowQueuePurge $true` (limpiar la cola sin
preguntar), `-PrinterName "<cola>"` para forzar el objetivo.

- **stdout**: el JSON entre `<<<FUDO_JSON_BEGIN>>>` y `<<<FUDO_JSON_END>>>`, **solo si se pasa
  `-Json`**. Sin ese switch nunca se imprime en pantalla (el asesor no tiene que ver el JSON).
- **stderr**: resumen humano y logs. `-Quiet` lo silencia.
- **exit code**: `0` resuelto · `2` requiere escalamiento · `3` falla del motor · `4` self-test fallido.

Sin `-Json`, el JSON queda en el archivo de `-JsonOut` o en `%TEMP%\FudoPrintDoctor-<fecha>.json`, y
el script informa la ruta al final. El resumen humano siempre va último, así queda a la vista.

Contrato completo del JSON: [`docs/contrato-json.md`](docs/contrato-json.md).

## Parámetros

| Parámetro | Default | Para qué |
|---|---|---|
| `-PrinterName` | autodetecta | Nombre exacto de la cola en Windows |
| `-Interface` | `auto` | `auto` \| `USB` \| `Ethernet` |
| `-PrinterIp` / `-Port` | — / `9100` | Impresora de red (interfaz "Directo Ethernet" de Fudo) |
| `-AutoFix` | `$true` | Aplicar reparaciones seguras |
| `-DryRun` | off | No modifica nada; registra qué haría |
| `-TestPrint` | `$true` | Emitir ticket ESC/POS de prueba |
| `-InstallGenericDriver` | `$true` | Instalar driver y cola de prueba si el hardware está sin instalar |
| `-AllowQueuePurge` | pregunta | Limpiar la cola sin preguntar (`$true`) o nunca (`$false`) |
| `-WaitReconnect` | pregunta | Esperar la reconexión del USB sin preguntar (`$true`) o nunca (`$false`) |
| `-ReconnectTimeoutSec` | `120` | Cuánto esperar la reconexión |
| `-CheckUpdate` / `-NoUpdateCheck` | off | Comparar con la versión publicada / no chequear |
| `-InstallNetworkPrinter` | off | Instalar la impresora de `-PrinterIp` como cola de Windows |
| `-NewPrinterName` | auto | Nombre de la cola que se cree |
| `-TelemetryUrl` / `-TelemetryFull` | vacío | Enviar el resultado por POST / mandar el JSON completo |
| `-NativeInstallerUrl` | vacío | URL del instalador de la App Nativa |
| `-NativeInstallerPath` | autodetecta | Instalador de la Nativa que ya está en la PC |
| `-NativeInstallerArgs` | vacío | Flags para el instalador (ej. `/S`) |
| `-NoMenu` | off | No mostrar el menú de acciones al terminar |
| `-SkipIrreversible` | off | No aplica nada irreversible, sin preguntar |
| `-KeepTestPrinter` | conserva | `:$false` borra la cola `FUDO-TEST-*` al terminar |
| `-CaseId` / `-ClientId` | vacío | Solo correlación de telemetría; no afecta el diagnóstico |
| `-JsonOut` | — | Volcar el JSON a un archivo |
| `-Json` / `-Quiet` | off | Forzar JSON a stdout / silenciar el resumen |
| `-Verbose` | off | Lista todos los chequeos en pantalla |
| `-SelfTest` | off | Corre los 101 asserts de la lógica de decisión. No toca la PC. |

## Desarrollo

```powershell
# Windows PowerShell 5.1 (el que corre en las PCs de los clientes)
powershell -NoProfile -File .\FudoPrintDoctor.ps1 -SelfTest

# PowerShell 7
pwsh -File .\FudoPrintDoctor.ps1 -SelfTest
```

El self-test corre sin impresora ni Windows real: mockea los cmdlets de `PrintManagement` y
valida el árbol de decisión, la clasificación de dispositivos USB (que un mouse o un
`USB Composite Device` no pasen por impresora) y de impresoras virtuales, el aislamiento de
etapas y todas las regresiones ya corregidas. CI: [`.github/workflows/selftest.yml`](.github/workflows/selftest.yml)
lo corre en `windows-latest` con 5.1 **y** 7 en cada push.

Ver también [`docs/arquitectura-capas.md`](docs/arquitectura-capas.md) y
[`docs/guia-asesores.md`](docs/guia-asesores.md).

## Sobre el .exe

No se publica ejecutable. `ps2exe` empaqueta el script sin compilarlo y, sin firma digital,
Defender/McAfee y SmartScreen lo bloquean — justo el problema que este script viene a resolver.
El `.cmd` de doble clic da la misma experiencia sin ese riesgo. Si en algún momento hay
certificado de code signing, `tools/build-exe.ps1` deja el camino armado.

## Estado

Uso interno de soporte. La lógica de decisión está cubierta por el self-test; el comportamiento
sobre hardware real se sigue validando caso por caso.
