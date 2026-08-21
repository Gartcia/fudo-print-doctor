# Arquitectura: diagnóstico por capas

La idea central: **ir de abajo hacia arriba**. Una capa alta no se puede diagnosticar si la de
abajo está rota, y confirmar una capa baja descarta media docena de hipótesis. El orden importa
tanto como los chequeos.

```
 5  Configuración de Fudo      área/cocina/sala, impresora registrada, categorías
 4  Prueba física ESC/POS      ¿el fierro imprime? -> parte aguas hardware vs configuración
 3  Conexión                   puerto USB desmapeado / IP de la Ethernet
 2  Cola de trabajos           un job trabado bloquea todo lo que viene
 1  Cola de Windows            existe, no es virtual, no está offline ni pausada
 1a Hardware                   ¿hay algo conectado? ¿en qué puerto? ¿con driver?
 0b App Nativa + antivirus     causa #1 del registro real de casos
 0  Entorno                    Windows, admin, servicio Spooler
```

## Por qué la capa 1a existe

La versión 1.1 no miraba el hardware: arrancaba en la lista de colas de Windows. En una PC sin
impresora térmica eso llevaba a elegir `Microsoft Print to PDF`, "imprimir" ahí con éxito y
concluir *"el hardware imprime OK, revisá la configuración de Fudo"*. Exactamente al revés.

La capa 1a responde tres preguntas antes de tocar software:

1. **¿Hay hardware?** Si Windows no enumera ninguna impresora, el problema es físico: energía,
   cable, puerto USB, o la impresora está fallada. Ninguna reparación de software sirve.
2. **¿En qué puerto está?** El registro `Enum\USBPRINT` es el único lugar donde vive el mapeo
   `device → USB00x`. Con eso se distingue un puerto **vivo** de un **huérfano** (los `USB001`,
   `USB002` que quedan de instalaciones viejas y no tienen nada detrás).
3. **¿Tiene driver y cola?** Un device presente con código 28 es "sin driver instalado". Un device
   presente sin cola es una impresora conectada que Windows no expone como impresora.

## Planos de responsabilidad

Cada chequeo declara en qué plano vive, y eso define quién resuelve:

| `plane` | Quién resuelve | Ejemplos |
|---|---|---|
| `os` | El motor, o el asesor en la PC | spooler, cola trabada, puerto, driver |
| `hardware` | El cliente en el local, o un técnico | cable, energía, papel, impresora fallada |
| `fudo_config` | El asesor en la web app (o la API) | cocina/área, salas, impresora registrada |

De ahí sale el `owner` de cada acción en `nextActions`: `cliente`, `asesor`, `soporte`.

## Cómo elige la causa raíz

1. Si se aplicaron reparaciones y no quedan fallas duras → **resuelto**. La confianza es `high`
   si además la prueba física salió OK, `medium` si no se pudo probar.
2. Si no, gana el candidato a causa raíz de la **capa más baja** en `fail` o `warn`.
3. Si nada está roto en el sistema operativo y el hardware imprime → la causa probable es la
   configuración de Fudo, que este motor no puede verificar desde la PC.

## Reparaciones automáticas

Todas pasan por `Invoke-Remediation`, que respeta `-DryRun` / `-AutoFix`, registra un antes y
después, y marca si es reversible:

| Reparación | Reversible |
|---|---|
| Iniciar/reiniciar el Spooler | sí |
| Sacar la impresora de offline / reanudar pausada | sí |
| Limpiar cola trabada | **no** (se pierden los trabajos en cola) |
| Restaurar la Nativa de cuarentena + exclusiones quirúrgicas de Defender | sí |
| Reasignar puerto USB probando candidatos con test físico | sí (revierte si ninguno imprime) |
| Instalar driver + cola `FUDO-TEST-<puerto>` | sí (`Remove-Printer`) |

Lo que **no** se automatiza: desactivar antivirus (se usan exclusiones de ruta y proceso, nunca
apagar el AV), tocar antivirus de terceros como McAfee o Avast (requiere acción guiada), y
cualquier cambio en la configuración de Fudo.

## Aislamiento de fallas

Cada capa corre dentro de `Invoke-Step`. Si explota, se registra en `engineErrors[]` con un hint
traducido a acción concreta y el diagnóstico **continúa** con las capas siguientes. Un bug del
motor en la capa 3 no debe impedir ver que el spooler estaba detenido.
