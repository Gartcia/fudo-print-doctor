# Fudo Print Doctor

Motor de diagnóstico y reparación automática del flujo de impresión de comandas en PCs Windows.
Corre en la máquina del cliente (por la herramienta de acceso remoto del asesor o invocado por
un agente), recorre la cadena de impresión por capas, identifica la causa raíz y auto-resuelve
los casos seguros. Lo que no puede resolver solo, lo devuelve como próximos pasos accionables.

- **Un solo archivo**: `FudoPrintDoctor.ps1`. Sin dependencias, sin instalación.
- **Compatible** con Windows PowerShell 5.1 (el que ya viene en Windows) y PowerShell 7+.
- **Dos salidas**: resumen corto para humanos en pantalla, JSON completo para el agente.

## Uso rápido (asesores)

Descargar la carpeta y hacer doble clic:

| Archivo | Qué hace |
|---|---|
| `1-Diagnosticar.cmd` | Solo diagnostica. **No toca nada** en la PC. Empezar siempre por acá. |
| `2-Diagnosticar-y-reparar.cmd` | Diagnostica y aplica las reparaciones seguras. Pide permisos de administrador. |
| `3-Para-el-agente.cmd` | Igual que el 2 pero además deja `resultado.json` al lado del script. |

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
| 0b | App Nativa de Fudo instalada y corriendo; Defender/antivirus de terceros (causa #1 del registro real) |
| **1a** | **Hardware**: qué impresoras hay físicamente conectadas, en qué puerto, con o sin driver |
| 1 | Cola de Windows: descarta impresoras virtuales, instala driver si falta |
| 2 | Cola de trabajos trabada |
| 3 | Puerto USB desmapeado / IP de la impresora Ethernet |
| 4 | Prueba física ESC/POS contra el hardware (aísla hardware vs configuración) |
| 5 | Configuración de Fudo: impresora registrada, cocina/área, categorías, salas |

### Detección de hardware (capa 1a)

Enumera las impresoras físicas con tres fuentes en cascada:

1. `HKLM\SYSTEM\CurrentControlSet\Enum\USBPRINT` → `Device Parameters\PortName`.
   Es el único lugar donde vive el mapeo **device → USB00x**.
2. `Get-PnpDevice` (clase `Printer`).
3. `Win32_PnPEntity` con `Service='usbprint'`, como fallback.

Con eso distingue tres cosas que a ojo se confunden: **puertos USB00x huérfanos** (restos de
instalaciones viejas, sin nada detrás), **device presente sin driver** (código 28 del
Administrador de dispositivos) y **device presente sin cola de impresión**.

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

## Uso desde un agente

```powershell
powershell -NoProfile -ExecutionPolicy Bypass -File .\FudoPrintDoctor.ps1 -Json -CaseId "IC-12345" -ClientId "local-987"
```

- **stdout**: solo el JSON, entre `<<<FUDO_JSON_BEGIN>>>` y `<<<FUDO_JSON_END>>>`.
- **stderr**: resumen humano y logs. `-Quiet` lo silencia.
- **exit code**: `0` resuelto · `2` requiere escalamiento · `3` falla del motor · `4` self-test fallido.

Si la salida **no** está redirigida y no se pasa `-Json`, el JSON no se vuelca a pantalla: queda
en `%TEMP%\FudoPrintDoctor-<fecha>.json` y el script informa la ruta.

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
| `-KeepTestPrinter` | conserva | `:$false` borra la cola `FUDO-TEST-*` al terminar |
| `-CaseId` / `-ClientId` | vacío | Solo correlación de telemetría; no afecta el diagnóstico |
| `-JsonOut` | — | Volcar el JSON a un archivo |
| `-Json` / `-Quiet` | off | Forzar JSON a stdout / silenciar el resumen |
| `-Verbose` | off | Lista todos los chequeos en pantalla |
| `-SelfTest` | off | Corre los 38 asserts de la lógica de decisión. No toca la PC. |

## Desarrollo

```powershell
# Windows PowerShell 5.1 (el que corre en las PCs de los clientes)
powershell -NoProfile -File .\FudoPrintDoctor.ps1 -SelfTest

# PowerShell 7
pwsh -File .\FudoPrintDoctor.ps1 -SelfTest
```

El self-test corre sin impresora ni Windows real: mockea los cmdlets de `PrintManagement` y
valida el árbol de decisión, la clasificación de impresoras virtuales, el aislamiento de etapas
y las regresiones ya corregidas. CI: [`.github/workflows/selftest.yml`](.github/workflows/selftest.yml)
lo corre en `windows-latest` con 5.1 **y** 7 en cada push.

Ver también [`docs/arquitectura-capas.md`](docs/arquitectura-capas.md) y
[`docs/guia-asesores.md`](docs/guia-asesores.md).

## Sobre el .exe

No se publica ejecutable. `ps2exe` empaqueta el script sin compilarlo y, sin firma digital,
Defender/McAfee y SmartScreen lo bloquean — justo el problema que este script viene a resolver.
Los `.cmd` de doble clic dan la misma experiencia sin ese riesgo. Si en algún momento hay
certificado de code signing, `tools/build-exe.ps1` deja el camino armado.

## Estado

Uso interno de soporte. La lógica de decisión está cubierta por el self-test; el comportamiento
sobre hardware real se sigue validando caso por caso.
