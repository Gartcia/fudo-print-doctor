# Guía rápida para asesores

## Cómo se corre

1. Copiar la carpeta a la PC del cliente (Escritorio o Descargas).
2. Doble clic en **`FudoPrintDoctor.cmd`**.
3. Pide permisos de administrador y muestra qué va a hacer. Enter para arrancar.
4. Leer el bloque **QUE HACER AHORA**.
5. Para escalar, adjuntar el `resultado.json` que queda al lado del script.

Un solo archivo hace todo: diagnostica y repara en la misma corrida. Lo único que puede llegar a
preguntarte es si limpiar la cola de impresión cuando hay comandas trabadas, porque eso las
descarta y hay que volver a imprimirlas desde Fudo. Cualquier otra reparación es reversible y se
aplica sola.

Si Windows muestra "Windows protegió tu PC" al abrir el `.cmd`: *Más información* → *Ejecutar
de todas formas*. Es porque el archivo viene de internet, no porque tenga algo raro.

## Cómo leer el resumen

Mientras corre vas viendo cada etapa con su resultado, así que no te quedás esperando en la nada:

```
  [1/9] Entorno de Windows .................... ok  220ms
  [2/9] App Nativa de Fudo y antivirus ........ revisar  310ms
  [3/9] Impresoras conectadas ................. FALLA  480ms
```

**IMPRESORAS CONECTADAS** es lo primero que hay que mirar.

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

## Los tres casos más comunes

**1. La Nativa bloqueada por el antivirus** (~46% de los casos del registro real).
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
- **Impresora de red**: si la IP cambió por DHCP, el motor escanea la subred buscando el
  puerto 9100 y sugiere la nueva IP, pero **no** la cambia en Fudo. Eso se hace en la web app.
- **Sin permisos de administrador** algunas reparaciones fallan (spooler, drivers). El launcher
  `2-*` los pide solo.

## Cuándo escalar

- El resumen dice `FALLA` en `Hardware conectado` y ya se probó otro cable y otro puerto.
- La prueba física falla con la impresora bien conectada (posible falla de hardware: hacer el
  self-test de la impresora — apagar, mantener FEED, encender).
- Aparece `Motor (fallas internas)` en los chequeos: es un bug, va a Soporte Producto con el JSON.
