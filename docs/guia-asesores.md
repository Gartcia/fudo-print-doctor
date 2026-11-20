# Guía rápida para asesores

## Cómo se corre

Casi siempre lo corrés vos, conectado a la PC del cliente por TeamViewer o AnyDesk.

1. Usá el **`FudoPrintDoctor.cmd` interno** (el del canal), no el del ZIP público: el público no
   manda el reporte y la corrida no queda registrada.
2. Pasalo a la PC del cliente y hacé doble clic. Es lo único que hace falta: el motor se baja
   solo, siempre en la última versión.
3. Acepta el permiso de administrador. **Por TeamViewer:** si TeamViewer no se abrió como
   administrador, el aviso de Windows no lo podés aceptar vos y la pantalla queda en negro hasta
   que el cliente toca *Sí*. Si nadie lo puede aceptar, Print Doctor sigue igual sin esos
   permisos: revisa todo, pero algunas reparaciones no las puede hacer.
4. Se abre una página en el navegador. Lo primero que pide es el **número del caso** (los 15
   dígitos de la conversación de Intercom, o la dirección completa). Si lo volvés a abrir en la
   misma PC dentro de las 2 horas, ya viene escrito: Continuar.
5. Después pregunta **cómo está conectada la impresora que no anda**. Viene marcada la opción que
   corresponde a esa PC (por ejemplo, USB si no tiene impresoras de red), así que casi siempre es
   un clic.
6. Leer **QUE HACER AHORA**. Si termina con cosas por hacer, la ventana negra no se cierra sola.

Si una pregunta queda sin contestar, la página muestra cuánto falta para que siga sola. Después de
una pregunta sin contestar, las siguientes esperan como mucho un minuto.

Lo único que pregunta antes de hacer es si limpiar la cola de impresión cuando hay comandas
trabadas, porque eso las descarta y hay que volver a imprimirlas desde Fudo. Se pregunta **una
vez por revisión**: si decís que sí, vale para el resto. Cualquier otra reparación es reversible y
se aplica sola.

Si Windows muestra "Windows protegió tu PC" al abrir el `.cmd`: *Más información* → *Ejecutar
de todas formas*. Es porque el archivo viene de internet, no porque tenga algo raro.

## Impresora de red que no responde: no hace falta Print Doctor

Si la impresora es de red (tiene su IP) y no responde, **Print Doctor no le puede cambiar la IP**.
Eso se hace con la utilidad de red del fabricante o desde la página web de la impresora. Andá
directo:

1. Self-test de la impresora (apagarla, mantener FEED, encenderla) para leer la IP que tiene.
2. Si es otra, cargar esa IP en Fudo (Administración > Impresoras) o devolverle la anterior con la
   utilidad del fabricante.
3. Si no imprime ni el self-test, es la impresora: técnico.

Si igual lo corrés en modo Red y la impresora no contesta, Print Doctor te dice esto mismo en
segundos y no sigue intentando cosas contra esa IP (no le manda tickets ni limpia las comandas
que la están esperando: salen solas cuando la impresora vuelve a responder).

## Revisión completa o una herramienta

En la misma pantalla de "cómo está conectada" está **Otras herramientas**, para cuando ya sabés
qué hay que hacer. Cada una hace solo eso:
  - **Limpiar colas de impresión**: te muestra las colas que tienen trabajos esperando, elegís
    cuáles (o todas) y las limpia. Si queda uno que no se borra, reinicia el servicio de
    impresión.
  - **Revisar la App Nativa y la extensión.**
  - **Revisar las impresoras USB** o **las de red** (las que ya están instaladas en Windows).
  - **Buscar impresoras en la red**: para las que se usan cargando la IP en Fudo y no están
    instaladas en Windows. Lista lo que contesta, te dice cuáles ya tienen cola y, si querés,
    instala una y manda un ticket de prueba.
  - **Impresora Bluetooth**: lista los dispositivos Bluetooth vinculados que tienen puerto COM,
    elegís cuál es la impresora, le crea la cola y manda un ticket de prueba. **Ojo:** aparecen
    también celulares y auriculares; elegí solo la impresora. Si no aparece, primero hay que
    vincularla desde Configuración > Bluetooth y dispositivos (PIN 0000 o 1234). Las de bajo
    consumo (BLE) no crean puerto COM y esta herramienta no las ve.

Al terminar cualquier herramienta, desde el menú podés elegir otra o pasar a la revisión
completa.

## Cómo leer el resumen

Mientras corre vas viendo cada etapa con su resultado, así que no te quedás esperando en la nada:

```
  [1/9] Entorno de Windows .................... ok  220ms
  [2/9] App Nativa de Fudo y antivirus ........ revisar  310ms
  [3/9] Impresoras conectadas ................. FALLA  480ms
```

**IMPRESORAS INSTALADAS EN WINDOWS** es lo primero que hay que mirar. La que tiene `>>` adelante es
la que el motor diagnostica: la que está fallando. Las que dicen "funcionando — no se toca" quedan
intactas, así no rompemos la cocina mientras arreglamos la caja.

**HARDWARE DE IMPRESION CONECTADO** es lo que Windows ve enchufado, con el puerto de cada uno.

- `0` → no es un problema de software. Revisar energía, cable y puerto USB antes de seguir.
- Si abajo del nombre dice `deteccion: ... (certeza baja)` → Windows no confirma que sea una
  impresora, solo lo sugiere el nombre. Confirmá que ese sea el equipo antes de instalarle nada.
- Los mouse, teclados y hubs USB no aparecen: se descartan y quedan en el JSON con el motivo.

**DESCONECTADAS** aparece cuando Windows tiene la impresora instalada pero el equipo no está
enchufado o está apagado. Es distinto de "no hay impresoras": acá sabemos cuál era y en qué puerto
estaba. Conectarla **al mismo puerto**, encenderla y volver a correr. Si se conecta en otro puerto,
el motor reasigna la cola solo.

Ojo con esto: la cola de Windows (incluida una `FUDO-TEST-*`) sigue existiendo aunque la impresora
no esté. Que aparezca en *Dispositivos e impresoras* no significa que esté conectada.
- La térmica aparece con `-> SIN cola en Windows` → está conectada pero no instalada.
- Aparece `Impresora generica [VID_xxxx]` → Windows la ve pero no sabe qué es. Normal en
  térmicas chinas (XPrinter, 3nStar, Rongta). El driver `Genérico / Solo texto` es el correcto.

**CHEQUEOS** es un semáforo por área:

| | Significado |
|---|---|
| `OK` | Nada que hacer acá |
| `REPARADO` | El motor lo arregló en esta corrida |
| `REVISAR` | Hay algo que requiere una acción humana |
| `FALLA` | Está roto y bloquea la impresión |
| `-` | No se pudo evaluar (por ejemplo, porque una capa anterior falló) |

**QUE HACER AHORA** viene ordenado: lo de abajo (hardware, sistema) antes que lo de arriba
(configuración de Fudo), y cada paso dice quién lo ejecuta:

- `[cliente]` → algo físico en el local, o una acción en su antivirus.
- `[asesor]` → vos, en la PC o en la web app de Fudo.
- `[soporte]` → escalar a Soporte Producto con el JSON.

## Caso: estaba instalada y dejó de imprimir

Síntoma típico: la cola tiene decenas o cientos de trabajos acumulados, dice "sin conexión" y su
puerto no tiene nada conectado. Eso confirma que **las comandas llegan desde Fudo** y se traban en
Windows.

Lo que lo resuelve casi siempre: con la impresora encendida, **desenchufar el cable USB y volver a
enchufarlo**. Windows la re-detecta y le asigna un puerto nuevo. Si corrés el script y le decís que
sí cuando pregunta si espera la reconexión, él detecta el puerto nuevo, apunta la cola ahí, tira un
ticket de prueba y —si la cola quedó rota— la recrea con el mismo nombre.

El nombre se mantiene a propósito: Fudo encuentra la impresora por nombre, así que una cola nueva
llamada distinto obliga a reconfigurar en la web app. Igual, después de recrear conviene verificar
en Fudo que la impresora siga con su cocina/área asignada.

## Los tres casos más comunes

**1. La Nativa bloqueada por el antivirus.**
El motor restaura la App Nativa de la cuarentena de Defender y agrega exclusiones de ruta y
proceso. Con McAfee o Avast **no** se puede automatizar: hay que excluirla a mano en el AV.
Nunca desactivar el antivirus completo: solo excluir.

**2. Se reconectó a otro puerto USB.**
La cola de Windows sigue apuntando al puerto viejo y los trabajos se acumulan sin salir. El
motor lo detecta comparando el puerto de la cola contra el puerto donde el device está realmente
enumerado, y prueba los candidatos con un ticket real.

**3. El hardware imprime pero la comanda no sale.**
Si `Prueba de impresion` dice `OK` y salió el ticket, el problema está en la configuración de
Fudo, no en la PC:

- Impresora registrada con la interfaz correcta (USB o Directo Ethernet)
- **Cocina/área asignada a la impresora** — sin esto no imprime ninguna comanda
- Categorías y subcategorías con cocina asignada
- Salas tildadas, si el local trabaja con salas

Artículos: [áreas y cocinas](https://soporte.fu.do/es/articles/11730815) ·
[USB](https://soporte.fu.do/es/articles/11730817) ·
[Ethernet](https://soporte.fu.do/es/articles/11730816) ·
[instalación](https://soporte.fu.do/es/articles/16419361)

## Cosas para tener en cuenta

- **Ticket de prueba**: sin `-DryRun` el motor manda un ticket ESC/POS real. Avisarle al cliente
  que va a salir un papel.
- **Cola trabada**: cuando el script pregunta si limpiarla, tené en cuenta que los trabajos
  pendientes se descartan. Si eran comandas que el cliente necesita, hay que volver a imprimirlas
  desde Fudo. Es la única reparación irreversible.
- **Cola `FUDO-TEST-*`**: si el motor la creó, queda instalada. Borrarla cuando se instale la
  definitiva: `Remove-Printer -Name "FUDO-TEST-USB001"`.
- **Impresora de red**: si la IP cambió, el motor busca en la misma red quién contesta en el
  puerto 9100 y te lo dice, pero **no** cambia nada: ni en Fudo ni en la impresora. Ver
  [Impresora de red que no responde](#impresora-de-red-que-no-responde-no-hace-falta-print-doctor).
- **Sin permisos de administrador** algunas reparaciones fallan (spooler, drivers). El `.cmd` los
  pide solo; si no se aceptan, sigue sin ellos y te lo avisa.
- **Volver a revisar** desde el menú (R) es mejor que cerrar y abrir: no vuelve a preguntar el
  caso ni el modo. Si la revisión da lo mismo que la anterior del mismo caso, te lo dice: otra
  vuelta no lo va a cambiar, conviene derivar.

## El menú del final

Cuando termina, el script no se cierra: te ofrece un menú. Eso sirve para el ida y vuelta típico
con el cliente sin volver a arrancar todo:

- **R** — revisar de nuevo, después de que el cliente hizo algo. Si venías de una herramienta,
  hace la revisión completa.
- **H** — elegir una herramienta (limpiar colas, buscar en la red, Bluetooth, la App Nativa).
- **U** — le pedís al cliente que desenchufe y vuelva a enchufar el USB, y el script detecta el
  puerto nuevo solo.
- **I** — instalar la impresora que está conectada pero no tiene cola en Windows.
- **L** — limpiar una cola trabada (te avisa cuántas comandas se descartan).
- **N** — buscar impresoras por IP en la red del local.
- **P** — instalar una de las que encontró por IP.
- **T** — tirar un ticket de prueba cuando quieras.
- **D** — ver el detalle completo de los chequeos.
- **J** — guardar el JSON donde vos quieras.

Después de cada acción que cambia algo, vuelve a diagnosticar solo, así siempre ves el estado real.

## Cuándo escalar

- El resumen dice `FALLA` en `Hardware conectado` y ya se probó otro cable y otro puerto.
- La prueba física falla con la impresora bien conectada (posible falla de hardware: hacer el
  self-test de la impresora — apagar, mantener FEED, encender).
- Aparece `Motor (fallas internas)` en los chequeos: es un bug, va a Soporte Producto con el JSON.
