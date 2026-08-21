# Contrato del JSON (`schemaVersion` 1.3)

Pensado para que un agente decida el próximo paso sin leer prosa.

## Streams y exit codes

| Canal | Contenido |
|---|---|
| stdout | Solo el JSON, entre `<<<FUDO_JSON_BEGIN>>>` y `<<<FUDO_JSON_END>>>`. Se emite si la salida está redirigida o si se pasa `-Json`. |
| stderr | Resumen humano y logs `WARN`/`ERROR`. `-Quiet` lo silencia. |

| exit | Significado |
|---|---|
| 0 | Resuelto, no requiere escalamiento |
| 2 | Requiere escalamiento (config de Fudo, hardware, acción del cliente) |
| 3 | Falla del motor (ver `engineErrors[]` o `status: "engine_error"`) |
| 4 | Self-test fallido |

## Raíz

```jsonc
{
  "schemaVersion": "1.3",
  "status": "resolved" | "needs_escalation" | "partial_engine_error" | "engine_error",
  "caseId": "IC-12345",          // solo correlación, no afecta el diagnóstico
  "clientId": "local-987",
  "host": "CAJA-01",
  "timestamp": "2026-08-21T14:39:59-03:00",
  "interface": "USB" | "Ethernet",
  "dryRun": false,
  "autoFix": true,
  "printer": { "name": "...", "driver": "...", "port": "USB001", "workOffline": false },
  "hardware": { ... },
  "diagnosis": { ... },
  "checks": [ ... ],
  "actionsApplied": [ ... ],
  "engineErrors": [ ... ],
  "diagnostics": { ... },
  "telemetry": { ... },
  "humanSummary": "texto plano del resumen",
  "log": [ ... ]
}
```

## `hardware`

```jsonc
{
  "devicesConnected": [ { "name": "...", "instanceId": "...", "portName": "USB001", "status": "..." } ],
  "problemDevices":   [ { "name": "...", "problem": 28, "class": "Printer" } ],
  "printersIdentified": [ ... ],     // ver diagnostics.printersConnected
  "usbDevicesRejected": [ { "nombre": "USB Composite Device", "motivo": "el nombre corresponde a otro tipo de dispositivo", "instanceId": "..." } ],
  "livePorts":  ["USB001"],          // puertos con device físico detrás
  "usbPorts":   ["USB001","USB002"], // todos los USB00x de Windows (pueden ser huérfanos)
  "printersFound": [ { "name": "...", "driver": "...", "port": "...", "isVirtual": true, "virtualReason": "...", "isPos": false } ],
  "testPrintersCreated": ["FUDO-TEST-USB001"]
}
```

El listado identificado de impresoras físicas vive en `diagnostics.printersConnected`:

```jsonc
{
  "nombre": "Epson TM-T20III",
  "marca": "Epson",
  "modelo": "TM-T20III",
  "vidPid": "VID_04B8&PID_0E15",
  "puerto": "USB001",
  "colaWindows": "TM-T20III",        // "" si el device no tiene cola en Windows
  "driverSugerido": "oem_instalado" | "oem_recomendado" | "generico",
  "driverNombre": "EPSON TM-T20III ReceiptE4",
  "driverNota": "texto explicativo",
  "deteccion": "interfaz USBPRINT (usbprint.sys)",   // por qué se considera impresora
  "certeza": "alta" | "media" | "baja"
}
```

Certeza de la detección:

| Certeza | Señal |
|---|---|
| `alta` | interfaz `USBPRINT`, clase de dispositivo `Printer`, driver `usbprint`, o `CompatibleID` con `USB\Class_07` (clase USB 07h = Printer) |
| `media` | VID de fabricante de impresoras |
| `baja` | el nombre menciona impresora / POS / modelo típico de térmica |

Con certeza `media` o `baja` conviene confirmar con el asesor que ese device es la comandera antes
de instalar nada sobre su puerto.
```

## `diagnosis`

```jsonc
{
  "resolved": false,
  "rootCause": "Ninguna impresora fisica conectada (Administrador de dispositivos)",
  "rootCauseCheckId": "hw.deviceConnected",
  "confidence": "high" | "medium" | "low",
  "autoFixesApplied": ["..."],
  "residualEscalation": [ { "id": "...", "name": "...", "plane": "fudo_config", "recommendation": "...", "articleRef": "..." } ],
  "needsEscalation": true,
  "engineErrorCount": 0,
  "nextActions": [
    {
      "priority": 1,
      "checkId": "hw.deviceConnected",
      "layer": 1,
      "status": "fail",
      "what": "qué se detectó",
      "do": "qué hacer, en imperativo",
      "owner": "cliente" | "asesor" | "soporte",
      "articleRef": "https://soporte.fu.do/es/articles/..."
    }
  ]
}
```

**`nextActions` es el campo a consumir**: ya viene priorizado (capas bajas primero: hardware y
sistema operativo antes que configuración de Fudo) y dice quién ejecuta cada paso.

## `checks[]`

Un nodo por chequeo del árbol de diagnóstico.

| Campo | Valores |
|---|---|
| `id` | `env.*`, `nativa.*`, `hw.*`, `printer.*`, `queue.*`, `conn.*`, `fudo.*`, `engine.*`, `args.*` |
| `status` | `ok` \| `warn` \| `fail` \| `fixed` \| `skipped` |
| `plane` | `os` \| `fudo_config` \| `hardware` |
| `layer` | 0 a 5, o 9 para fallas internas del motor |
| `rootCauseCandidate` | Si puede ser la causa raíz |
| `evidence` | Datos crudos que sustentan el veredicto |
| `actionTaken` | Qué remediación se aplicó |
| `articleRef` | Artículo del Help Center |
| `recommendation` | Qué hacer |

Checks principales: `env.spooler`, `nativa.installed`, `nativa.defenderQuarantine`,
`nativa.thirdPartyAV`, `hw.deviceConnected`, `hw.driverPlan`, `hw.driverMissing`,
`hw.notInstalled`, `printer.exists`, `printer.virtualTarget`, `printer.autodetect`,
`printer.offline`, `printer.paused`, `queue.health`, `conn.usb`, `conn.net`, `hw.testprint`,
`fudo.printerRegistered`, `fudo.printerKitchen`, `fudo.categoryKitchen`, `fudo.rooms`.

## `telemetry`

```jsonc
{
  "durationMs": 3613,
  "checksTotal": 18,
  "autoFixCount": 1,
  "resolved": true,
  "escalated": false,
  "category": "os.usb_port",
  "confidence": "high",
  "engineErrors": 0
}
```

Categorías: `nativa.antivirus`, `nativa.antivirus_3p`, `nativa.install`, `os.spooler`,
`os.queue`, `os.printer_state`, `os.usb_port`, `os.driver_faltante`, `os.impresora_virtual`,
`net.ip`, `hardware`, `hardware.no_conectada`, `fudo_config`, `unknown`.
Sirven para medir Contact Rate por causa.

## Errores del motor

Si una etapa explota, el run **sigue** y queda registrada:

```jsonc
"engineErrors": [ { "step": "layer3.network", "message": "...", "type": "...", "at": "linea 812: ...", "hint": "qué hacer" } ]
```

Si explota algo no previsto, el JSON sale igual con `status: "engine_error"`, el detalle en
`error` (mensaje, tipo, línea, comando, stack, hint) y lo recolectado hasta ahí en `partial`.
