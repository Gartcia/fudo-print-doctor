# FudoPrintDoctor — reglas del proyecto

Motor PowerShell de un solo archivo (`FudoPrintDoctor.ps1`, ~6.000 líneas) que diagnostica y
repara la cadena de impresión de comandas en las PCs Windows de los clientes de Fudo. Lo corren
los asesores de soporte en la PC del cliente.

## Antes de tocar nada

Leé `contexto/00-contexto-y-estado.md` — es el punto de entrada: estado, decisiones tomadas y por
qué, orden de capas, pendientes. Después `contexto/bitacora-diaria.md`, que es lo que la revisión
diaria detecta en la telemetría real. Los `contexto/fudoprintdoctor-vX.Y-*.md` son el detalle de
cada etapa: qué se rompió, por qué, y cómo se arregló. **La carpeta `contexto/` está en
`.gitignore` a propósito**: el repo es público y esos docs mencionan el fileId de la planilla,
pcIds de clientes y nombres de asesores. No la commitees ni cites su contenido en el código.

## Reglas que no se negocian

- **El self-test tiene que pasar antes de commitear.** Se corre así:
  `powershell -NoProfile -ExecutionPolicy Bypass -File .\FudoPrintDoctor.ps1 -SelfTest`
  No toca la PC ni necesita impresora. Si agregás lógica, agregá su escenario al self-test.
- **`VERSION` y `$script:SchemaVersion` tienen que coincidir.** El workflow de Actions falla si no.
- **El `.ps1` va sin acentos ni caracteres no ASCII.** Corre en el PowerShell 5.1 que trae Windows,
  en PCs con cualquier code page. Los `.md` sí llevan acentos.
- **Finales de línea CRLF, sin BOM.** Editá preservándolos.
- **Nada de datos internos en el código ni en los docs del repo.** La URL del endpoint de
  telemetría vive en `FudoPrintDoctor.cmd` interno y en la variable `FUDO_TELEMETRY_URL`, nunca
  en el repo.
- **Entrada nueva en `CHANGELOG.md` por cada versión**, con el formato que ya tiene: qué se
  corrigió y, sobre todo, **qué caso real lo motivó**. El changelog es la memoria del proyecto.

## Cómo se trabaja

1. Un hallazgo entra por la bitácora (telemetría real) o por un asesor.
2. Se implementa, se agrega su escenario al self-test, se corre el self-test.
3. Bump de `VERSION` + `SchemaVersion`, entrada de CHANGELOG.
4. Commit y push. Actions corre el self-test en PowerShell 5.1 y 7, el parser y el chequeo de
   versión.
5. Se avisa a los asesores en el canal de Slack **en lenguaje de asesor**: qué mejoró, qué probar.
   Nada de nombres de funciones.

## Lo que el motor no puede hacer

Casi nada está probado contra hardware real: la reconexión guiada del USB, la recreación de cola,
el replug por software y todo el camino Ethernet salieron de telemetría, no de una impresora
enchufada. Si tenés una impresora térmica a mano, probar eso vale más que cualquier refactor.
