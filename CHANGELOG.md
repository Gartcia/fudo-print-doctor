# Changelog

Formato: [Keep a Changelog](https://keepachangelog.com/es-ES/1.1.0/). Versionado del `schemaVersion` del JSON.

## [1.4] - 2026-08-21

### Corregido
- **Falso positivo de detección**: cualquier dispositivo USB podía pasar por impresora. El token
  `POS` de la lista de marcas matcheaba `USB Com`**`pos`**`ite Device` y `Generic` matcheaba
  `Generic USB Hub`. Ahora hay un clasificador explícito (`Test-IsPrinterDevice`) con señales
  ordenadas por certeza: interfaz `USBPRINT` / clase `Printer` / driver `usbprint` /
  `CompatibleID USB\Class_07` (clase USB 07h del estándar) → alta; VID de fabricante de
  impresoras → media; nombre que menciona impresora o modelo típico → baja. Mouse, teclados,
  hubs, composites, audio, cámaras y almacenamiento se descartan.
- `Test-IsPosPrinter` (heurística sobre colas de Windows) usa límites de palabra.
- `5890` y `80c` salieron de la lista de marcas: son números de modelo, y generaban etiquetas
  absurdas como "80c XP" para una `XP-80C`.

### Agregado
- `hardware.usbDevicesRejected[]`: qué dispositivos USB se descartaron y por qué.
- `deteccion` y `certeza` por impresora; el resumen las muestra cuando la certeza no es alta.
- `-SkipIrreversible`: repara todo menos lo que no se puede deshacer (hoy, la purga de la cola).
- Launcher `2-Diagnosticar-y-reparar.cmd` usa `-SkipIrreversible` y avisa qué va a hacer antes de
  arrancar; la purga de cola queda en `4-Reparar-todo-incluida-la-cola.cmd`.

## [1.3] - 2026-08-21

### Agregado
- Conteo y listado de impresoras físicas conectadas, con marca/modelo cuando se puede identificar
  (nombre + `InstanceId` + tabla de VID USB) y su puerto.
- Check `hw.driverPlan`: por cada impresora decide si corresponde el driver del fabricante
  (Epson, Bixolon, Star, Citizen, Zebra, Custom, Sam4s, Sewoo, Posiflex, Hasar) o el inbox
  `Generic / Text Only`. Si el driver OEM ya está instalado, lo usa para la cola de prueba.
- Switch `-Json` para forzar el JSON a stdout.

### Cambiado
- Consola legible: resumen compacto (impresoras detectadas, semáforo por área, causa, hasta 3
  acciones) con color cuando la consola es interactiva. `-Verbose` lista todos los chequeos.
- Si la salida no está redirigida, el JSON ya no se vuelca a pantalla: se guarda en
  `%TEMP%\FudoPrintDoctor-<fecha>.json` y se informa la ruta.
- `nextActions[].owner` simplificado a `cliente` / `asesor` / `soporte`.

## [1.2] - 2026-08-21

### Agregado
- **Capa 1a**: inventario de hardware antes de elegir impresora. Registro `Enum\USBPRINT`
  (mapeo device → USB00x), `Get-PnpDevice` y `Win32_PnPEntity` como fallback.
- Detección de puertos USB00x huérfanos y de dispositivos presentes sin driver (código 28).
- Instalación del driver inbox genérico + cola `FUDO-TEST-<puerto>` cuando hay hardware sin cola.
- Bloque `hardware` en el JSON. Categorías `hardware.no_conectada`, `os.driver_faltante`,
  `os.impresora_virtual`.
- Parámetros `-InstallGenericDriver`, `-KeepTestPrinter`.

### Corregido
- **Falso positivo grave**: el motor elegía `Microsoft Print to PDF` como objetivo y el envío RAW
  contra esa cola devolvía éxito, concluyendo "el hardware imprime OK". Ahora las impresoras
  virtuales se descartan por nombre, driver y puerto, y la prueba física se saltea sobre ellas.
- Capa 3 USB: compara el puerto de la cola contra el puerto donde está enumerado el device
  (caso del artículo 11730817) y prueba primero los puertos con hardware vivo.

## [1.1] - 2026-08-21

### Corregido
- **Crash en cualquier PC sin impresora POS**: con `Set-StrictMode -Version 2.0`, acceder a
  `.Count` sobre `$null` o un escalar lanza `PropertyNotFoundStrict`. `Resolve-TargetPrinter`
  hacía `$candidates = $allPrinters | Where-Object {...}` sin `@()`, y el run moría antes de
  emitir cualquier salida. Ahora `StrictMode 1.0` y todos los `.Count` blindados con `@()`.

### Agregado
- `Invoke-Step`: cada capa corre aislada; si una explota queda en `engineErrors[]` y el
  diagnóstico continúa.
- `try/catch` global: toda falla sale como JSON con `status:"engine_error"` y un `hint` accionable.
- `diagnosis.nextActions[]` priorizado con owner y artículo del Help Center.
- Preflight de parámetros, exit codes, stdout reservado al JSON delimitado.

## [1.0]

- Versión inicial: diagnóstico por capas, remediaciones idempotentes, JSON + resumen humano.
