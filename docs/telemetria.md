# Telemetría: dónde caen los datos

El objetivo es no depender de que el asesor guarde y adjunte el JSON. Cada corrida manda un POST
con un resumen, y queda una fila en una planilla de Google.

## 1. Crear el receptor (una vez)

1. Planilla nueva en Google Sheets.
2. **Extensiones → Apps Script**, borrar todo y pegar [`tools/telemetria-appscript.gs`](../tools/telemetria-appscript.gs).
3. Cambiar `TOKEN` por una clave inventada.
4. **Implementar → Nueva implementación → Aplicación web**:
   - *Ejecutar como*: Yo
   - *Quién tiene acceso*: Cualquier persona
5. Copiar la URL que termina en `/exec`.

## 2. Conectarlo al motor

**La URL no va en el código.** El repositorio es público, y una URL de escritura publicada se puede
spamear. El motor la busca, en este orden:

1. El parámetro `-TelemetryUrl <url>`.
2. La variable de entorno `FUDO_TELEMETRY_URL`.
3. Un archivo **`telemetria.txt`** al lado del script (o en Descargas / Escritorio), con la URL en una sola línea.

La opción 3 es la práctica: se genera una vez, se distribuye junto al `.ps1` y el `.cmd` por el
canal interno (no por el repo — está en el `.gitignore`), y a partir de ahí cada corrida reporta
sola. Para cambiar de destino, se reemplaza ese archivito.

**Ojo con la extensión**: tiene que ser `.txt`. En Windows, `.url` está reservada para accesos
directos de Internet y el archivo no se lee (se acepta igual por compatibilidad, pero no conviene).

Para verificar que está bien configurado, sin correr el diagnóstico:

```powershell
.\FudoPrintDoctor.ps1 -TestTelemetry
```

Manda una fila de prueba con `caseId = PRUEBA-TELEMETRIA` y dice si llegó. Si falla, el mensaje
indica qué revisar (lo más común: el Apps Script no está implementado con *Quién tiene acceso:
Cualquier persona*).

## Detalle técnico: el redirect de Apps Script

`/exec` responde **302** hacia `script.googleusercontent.com`. Al seguir ese redirect, el POST se
convierte en GET y **se pierde el cuerpo**: la fila nunca llega y el endpoint contesta como si el
pedido estuviera vacío. Por eso el motor, si el primer intento no devuelve `ok`, repite el POST
contra la URL del `Location`. Está cubierto por el self-test con un servidor HTTP real que imita ese
302.

Sobre el riesgo: cualquier URL que llegue a la PC de un cliente es, en la práctica, semi-pública. Lo
peor que puede pasar es que alguien escriba basura en la planilla; por eso el Apps Script valida la
forma del payload y descarta lo que no sea un resultado del motor. Si algún día pasa, se vuelve a
implementar el Apps Script (URL nueva) y se actualiza el `telemetria.url`.

Es silencioso: si no hay internet o la URL falla, el diagnóstico sigue igual y solo queda un `WARN`
en el log.

## 3. Qué se manda

Payload reducido (default), pensado para que no viajen datos de más:

| Campo | Ejemplo |
|---|---|
| `caseId` / `clientId` | `IC-12345` / `local-987` |
| `host` | `DESKTOP-A5RDOJE` |
| entorno: país, zona horaria | `AR`, `America/Buenos_Aires` |
| entorno: SO, build, arquitectura | `Windows 11 Pro`, `26100`, `64-bit` |
| entorno: PowerShell, Chrome, Edge | `5.1.26100.4768`, `139.0.7258.139` |
| entorno: versión de la Nativa | `0.0.36` |
| entorno: conexión de la PC | `cable` / `wifi` |
| interfaz de la impresora | `USB` / `Ethernet` |
| cantidad de colas y de hardware | `2` / `3` |
| estado de cada cola | `CAJA [USB003] no imprime (1440 trabajos)` |
| a qué cola le manda Fudo | `COCINA (118)` |
| causa raíz, categoría, confianza | `os.usb_port`, `high` |
| resuelto / escalado / duración | `true` / `false` / `3613` |
| reparaciones aplicadas | `Puerto USB desmapeado` |

**No** viajan rutas de archivos ni el log de la corrida. Con `-TelemetryFull` se manda el JSON
completo (que sí incluye rutas): usarlo solo para depurar un caso puntual.

La última columna de la planilla (`json`) guarda el payload crudo, para poder reprocesar después
sin perder nada.

## 4. Leer los datos

Desde la planilla directamente, o por la API del Apps Script:

```
GET <URL>/exec?key=TOKEN                 -> últimas 100 corridas en JSON
GET <URL>/exec?key=TOKEN&limit=500
GET <URL>/exec?key=TOKEN&formato=csv
```

La columna `json` no se devuelve por la API (solo queda en la planilla).

## 5. Qué mirar cuando haya datos

- **`categoria`**: cuál es la causa más frecuente. Define dónde conviene invertir.
- **`chrome` y `nativaVersion`**: si los casos se concentran en una versión vieja.
- **`conexionPC` = wifi** con impresoras de red: candidato a problemas intermitentes.
- **`colaQueUsaFudo` vacío** con hardware presente: sospecha de configuración en Fudo.
- **`pais`**: si hay diferencias por región (marcas de impresoras distintas).
