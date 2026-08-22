# Telemetría: dónde caen los datos

El objetivo es no depender de que el asesor guarde y adjunte el JSON. Cada corrida manda un POST
con un resumen, y queda una fila en una planilla de Google.

## 1. Crear el receptor (una vez)

1. Planilla nueva en Google Sheets.
2. **Extensiones → Apps Script**, borrar todo y pegar [`tools/telemetria-appscript.gs`](../tools/telemetria-appscript.gs).
3. Cambiar `TOKEN` por una clave inventada.
4. **Implementar → Nueva implementación → Aplicación web**:
   - *Ejecutar como*: **Yo**
   - *Quién tiene acceso*: **Cualquier persona**

   Este paso es el que más falla. Ojo con dos trampas:

   - **"Cualquier persona"**, no *"Cualquier persona con una cuenta de Google"*. El script no se
     autentica con Google, así que la segunda opción devuelve **HTTP 403** y una página de login en
     lugar de ejecutar el código.
   - Si ya estaba implementado y cambiás el acceso, hay que hacer **Administrar implementaciones →
     editar (lápiz) → cambiar → Implementar**. Editando la implementación existente la URL se
     mantiene; creando una nueva, la URL cambia y hay que actualizarla en el launcher.

   Si la cuenta es de Google Workspace, la organización puede tener bloqueada la opción "Cualquier
   persona". En ese caso no hay vuelta con Apps Script en esa cuenta: se usa una cuenta personal de
   Gmail, o otro receptor (un webhook de Slack es el reemplazo más rápido).
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

## 5. Identificadores: qué hace falta y qué no

El `caseId` es opcional a propósito. Para lo que se quiere responder con esta telemetría, casi no
sirve:

| Pregunta | ¿Necesita identificar al cliente? |
|---|---|
| ¿En qué estado llegan los clientes a Fudo? | No — es agregado sobre atributos |
| ¿Qué tienen en común los que tienen problemas? | No — es agregado |
| ¿Qué solución resolvió el problema? | Sí, pero hace falta unir corridas de la **misma PC**, no del mismo caso |

Para lo tercero se usa **`pcId`**: un hash SHA-256 truncado del `MachineGuid` de Windows. Es estable
(la misma PC siempre da el mismo valor), anónimo (no se puede volver al dato original ni saber de
qué comercio es) y **no requiere que nadie escriba nada**.

Y para no tener que cruzar filas a mano, cada corrida trae el contexto de la anterior **de esa misma
PC**:

```jsonc
"corrida": {
  "numero": 3,
  "statusAnterior": "needs_escalation",
  "causaAnterior": "La impresora 'CAJA' esta desconectada (puerto USB003 sin dispositivo)",
  "transicion": "se_resolvio"
}
```

`transicion` vale `primera`, `se_resolvio`, `volvio_a_fallar`, `sigue_ok` o `sigue_fallando`. Con eso,
**una sola fila ya cuenta la historia**: qué estaba fallando, qué reparación se aplicó y si funcionó.
Eso es exactamente el objetivo "identificar qué solución resuelve el problema", sin joins.

El estado se guarda en `HKCU\Software\Fudo\PrintDoctor` (contador, último status, última causa).

### ¿Y para identificar al comercio?

Desde la PC no hay forma confiable hoy. Por eso cada corrida manda `nativaHuella`: un sondeo de
`%LOCALAPPDATA%\Fudo` que reporta **solo nombres de archivo y nombres de clave** de los `.json`
—ningún valor, para no transportar tokens— y así averiguar si la App Nativa guarda algo usable (un
subdominio, un id de cuenta). Con dos o tres casos reales se decide si hay algo aprovechable.

## 6. En qué estado llegan: el campo `llegada`

Cada corrida clasifica sola la situación que encontró, cruzando tres evidencias independientes:
las colas instaladas y su estado, las entradas históricas del registro `USBPRINT` (impresoras que
*alguna vez* estuvieron en esa PC) y el historial de impresión del spooler.

| `escenario` | Qué significa |
|---|---|
| `nunca_hubo_impresora_en_esta_pc` | Ni colas, ni históricos, ni hardware. Instalación desde cero. |
| `primera_instalacion` | El motor instaló la primera cola de esa PC en esta corrida. |
| `estaba_instalada_y_dejo_de_funcionar` | Hay cola o rastro histórico, y evidencia de uso previo. |
| `instalada_pero_nunca_imprimio` | Hay cola, el log está habilitado y no registró ningún trabajo. |
| `una_funciona_y_otra_no` | Al menos una cola sana y otra fallando (caja/cocina). |
| `todas_funcionan` | Ninguna cola con problemas. |
| `hardware_conectado_sin_instalar` | Impresora enchufada, sin cola en Windows. |

Y `usoPrevio` responde "¿esto imprimió alguna vez?": `si_imprimio_comandas_de_fudo`,
`imprimio_pero_no_comandas_de_fudo`, `no_hay_registro_de_impresion`, o **`desconocido`** cuando el
log del spooler está apagado. Ese último valor es importante: es más honesto que afirmar que nunca
imprimió cuando en realidad no hay registro.

**Límite a tener en cuenta**: el campo `alcance` vale siempre `esta_pc`. Desde la PC no hay forma de
saber si en otra máquina del local ya hay impresoras funcionando, así que "es la primera impresora
del comercio" no se puede afirmar — solo "es la primera de esta PC". Para lo otro haría falta un
identificador de comercio (ver `nativaHuella`) o la API de Fudo.

## 7. El dashboard

La hoja **`resumen`** se recalcula sola con cada corrida que llega (la genera el Apps Script). Trae:

- corridas totales, **PCs distintas**, resueltas y % de resolución;
- **en qué estado llegan** (ranking de `escenario`) y **uso previo**;
- ranking de **causas** (`categoria`);
- **transiciones** (cuántas pasaron a resuelto, cuántas volvieron a fallar);
- **qué resolvió**: `causa anterior ==> reparación aplicada`, ordenado por frecuencia;
- distribución por sistema operativo, versión de Chrome, conexión (cable/wifi) y país.

Es el dashboard con cero infraestructura: vive en la misma planilla y se actualiza al recibir datos.
Si más adelante se quiere algo más lindo, esa hoja ya tiene todo lo necesario para alimentar un
Looker Studio.

## 7. Qué mirar cuando haya datos

- **`categoria`**: cuál es la causa más frecuente. Define dónde conviene invertir.
- **`chrome` y `nativaVersion`**: si los casos se concentran en una versión vieja.
- **`conexionPC` = wifi** con impresoras de red: candidato a problemas intermitentes.
- **`colaQueUsaFudo` vacío** con hardware presente: sospecha de configuración en Fudo.
- **`pais`**: si hay diferencias por región (marcas de impresoras distintas).
